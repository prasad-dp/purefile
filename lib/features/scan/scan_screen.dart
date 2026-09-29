import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/history/history_store.dart';
import '../../core/pdf/images_to_pdf_service.dart';
import '../../core/scan/scan_service.dart';
import '../../core/share_intake/share_intake.dart';

/// Document scan types (Adobe Scan modes).
enum ScanDocType {
  /// Standard single or multi-page documents, letters, receipts, and contracts.
  document,

  /// Two-sided ID cards, driver licenses, or badges stitched onto a single page.
  idCard,

  /// Wide pages, books, or two-column forms.
  book,
}

/// Feature 11: Document Scanner (Adobe Scan full-screen experience).
///
/// Features:
/// - Immersive edge-to-edge full-screen camera viewfinder
/// - Adobe Scan modes: Document, 2-Sided ID Card, Book / Form
/// - Live viewfinder guides with corner brackets & ID card aspect reticle
/// - 2-Sided ID card capture (front + back stitched onto single A4 sheet)
/// - Auto Color (Magic Color), Original, Grayscale, and B&W Text filters
/// - Quick thumbnail review bubble with page count badge
/// - Reorderable page review, per-page filter adjustment, and high-DPI PDF export
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _controller;
  bool _camReady = false;
  bool _camFailed = false;
  bool _busy = false;
  bool _saving = false;
  bool _torchOn = false;
  bool _autoCapture = false;

  ScanDocType _scanMode = ScanDocType.document;
  ScanFilter _activeFilter = ScanFilter.enhanced;

  /// Stored front side of an ID card when in [ScanDocType.idCard] mode.
  Uint8List? _idCardFrontBytes;

  final List<_ScanPageItem> _pages = [];

  @override
  void initState() {
    super.initState();
    _resetSessionDir();
    _initCamera();
  }

  void _resetSessionDir() {
    getApplicationDocumentsDirectory().then((dir) {
      final d = Directory('${dir.path}${Platform.pathSeparator}scan_session');
      if (d.existsSync()) d.deleteSync(recursive: true);
    }).catchError((_) {});
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _camFailed = true);
        return;
      }
      final back = cameras
          .where((c) => c.lensDirection == CameraLensDirection.back)
          .toList();
      final desc = back.isNotEmpty ? back.first : cameras.first;
      final ctrl = CameraController(
        desc,
        ResolutionPreset.high,
        imageFormatGroup: ImageFormatGroup.jpeg,
        enableAudio: false,
      );
      await ctrl.initialize();
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      setState(() {
        _controller = ctrl;
        _camReady = true;
      });
    } on CameraException {
      if (mounted) setState(() => _camFailed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _toggleTorch() async {
    final ctrl = _controller;
    if (ctrl == null || !_camReady) return;
    try {
      final next = !_torchOn;
      await ctrl.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      setState(() => _torchOn = next);
    } catch (_) {}
  }

  Future<void> _capture() async {
    final ctrl = _controller;
    if (_busy || !_camReady || ctrl == null) return;
    HapticFeedback.mediumImpact();
    setState(() => _busy = true);
    try {
      final file = await ctrl.takePicture();
      final bytes = await file.readAsBytes();

      if (_scanMode == ScanDocType.idCard) {
        if (_idCardFrontBytes == null) {
          // Captured front side — now prompt for back side
          setState(() {
            _idCardFrontBytes = bytes;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Front side captured! Now flip ID to scan back side.'),
                duration: Duration(seconds: 3),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        } else {
          // Captured back side — stitch front and back into single document page
          final frontBytes = _idCardFrontBytes!;
          final backBytes = bytes;
          setState(() => _idCardFrontBytes = null);

          // Process both sides with active filter
          final procFront = await runScanPageInIsolate(frontBytes, _activeFilter);
          final procBack = await runScanPageInIsolate(backBytes, _activeFilter);

          // Stitch onto single clean A4 sheet
          final stitched = await runStitchIdCardInIsolate(procFront.bytes, procBack.bytes);
          await _saveAndAddPage(stitched.bytes, stitched.width, stitched.height, bytes, _activeFilter);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('ID Card (2-sided) stitched onto single page ✓'),
                duration: Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      } else {
        // Standard document or book page
        await _addProcessed(bytes, _activeFilter);
      }
    } on CameraException {
      if (mounted) setState(() => _camFailed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    if (_busy) return;
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
      withData: false,
      allowMultiple: true,
    );
    if (picked == null) return;
    setState(() => _busy = true);
    try {
      for (final f in picked.files) {
        if (f.path == null) continue;
        await _addProcessed(File(f.path!).readAsBytesSync(), _activeFilter);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addProcessed(Uint8List bytes, ScanFilter filter) async {
    final page = await runScanPageInIsolate(bytes, filter);
    await _saveAndAddPage(page.bytes, page.width, page.height, bytes, filter);
  }

  Future<void> _saveAndAddPage(
    Uint8List jpegBytes,
    int width,
    int height,
    Uint8List rawBytes,
    ScanFilter filter,
  ) async {
    final dir = await getApplicationDocumentsDirectory();
    final sessionDir = '${dir.path}${Platform.pathSeparator}scan_session';
    final session = ScanSession(sessionDir);
    final path = session.addPage(jpegBytes);
    if (mounted) {
      setState(() => _pages.add(_ScanPageItem(
            path: path,
            width: width,
            height: height,
            rawBytes: rawBytes,
            filter: filter,
          )));
    }
  }

  Future<void> _changePageFilter(int index, ScanFilter newFilter) async {
    final item = _pages[index];
    if (item.filter == newFilter) return;
    setState(() => _busy = true);
    try {
      final page = await runScanPageInIsolate(item.rawBytes, newFilter);
      final file = File(item.path);
      await file.writeAsBytes(page.bytes, flush: true);
      setState(() {
        item.filter = newFilter;
        item.width = page.width;
        item.height = page.height;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openReviewSheet() async {
    if (_pages.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ReviewPagesModal(
        pages: _pages,
        onFilterChanged: (idx, filter) async {
          await _changePageFilter(idx, filter);
          setState(() {});
        },
        onDelete: (idx) {
          setState(() => _pages.removeAt(idx));
        },
        onReorder: (oldI, newI) {
          setState(() {
            final p = _pages.removeAt(oldI);
            _pages.insert(newI, p);
          });
        },
        onSavePdf: () {
          Navigator.pop(ctx);
          _startSavePdf();
        },
      ),
    );
  }

  Future<void> _startSavePdf() async {
    if (_pages.isEmpty || _saving) return;

    final now = DateTime.now();
    final defaultStem =
        'Scan_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    final nameController = TextEditingController(text: defaultStem);

    final confirmedName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save Scanned PDF'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'PDF Document Name',
                suffixText: '.pdf',
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.folder_outlined, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Saved to: PureFile / Documents / outputs',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, nameController.text.trim()),
            child: const Text('Save PDF'),
          ),
        ],
      ),
    );

    if (confirmedName == null || confirmedName.isEmpty) return;

    setState(() => _saving = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final outputs = '${dir.path}${Platform.pathSeparator}outputs';
      Directory(outputs).createSync(recursive: true);
      final args = ImagesToPdfArgs(
        images: [
          for (final p in _pages)
            (p.path, p.path.split(Platform.pathSeparator).last),
        ],
        outputDir: outputs,
        outputFileName: confirmedName,
      );
      final result = await runScanImagesToPdfInIsolate(args);
      final name = result.outputPath.split(Platform.pathSeparator).last;
      try {
        await ref.read(historyProvider).record(HistoryEntry(
              path: result.outputPath,
              fileName: name,
              toolId: 'scan',
              sizeBytes: result.outputBytes,
              createdAt: DateTime.now(),
            ));
      } catch (_) {
        // History is best-effort.
      }
      if (!mounted) return;
      _showScanCompleteSheet(result);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showScanCompleteSheet(ImagesToPdfResult result) {
    final fileName = result.outputPath.split(Platform.pathSeparator).last;
    final sizeMb = (result.outputBytes / (1024 * 1024)).toStringAsFixed(2);

    showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.green, size: 48),
              const SizedBox(height: 10),
              Text(
                'Document Saved',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                '$fileName · $sizeMb MB · ${result.pageCount} page(s)',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.folder_open_rounded, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        result.outputPath,
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: const Text('Open'),
                      onPressed: () => OpenFilex.open(result.outputPath),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.share_rounded),
                      label: const Text('Share'),
                      onPressed: () {
                        SharePlus.instance.share(
                          ShareParams(files: [XFile(result.outputPath)]),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('Save As'),
                      onPressed: () async {
                        final bytes = await File(result.outputPath).readAsBytes();
                        await FilePicker.platform.saveFile(
                          dialogTitle: 'Save to Device',
                          fileName: fileName,
                          type: FileType.any,
                          bytes: bytes,
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.text_snippet_rounded),
                  label: const Text('Recognize Text (OCR)'),
                  onPressed: () {
                    Navigator.pop(sheetCtx);
                    ref.read(shareIntakeProvider.notifier).intake([result.outputPath]);
                    context.push('/tools/ocr');
                  },
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.pop(sheetCtx);
                    context.pop();
                  },
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Edge-to-edge full screen camera preview
          Positioned.fill(child: _buildCameraPreview()),

          // 2. Viewfinder overlays and live reticle guidelines
          Positioned.fill(child: _buildViewfinderOverlay()),

          // 3. Floating top bar (Back, Flash, Auto/Manual toggle)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildTopBar(),
          ),

          // 4. Floating bottom bar (Filter chips, Mode carousel, Shutter & Thumbnail bubble)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomControls(),
          ),

          // 5. Loading overlay when busy
          if (_busy || _saving)
            Positioned.fill(
              child: Container(
                color: Colors.black45,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: Colors.white),
                        const SizedBox(height: 12),
                        Text(
                          _saving ? 'Saving PDF…' : 'Enhancing document…',
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (_camReady && _controller != null) {
      final previewSize = _controller!.value.previewSize;
      if (previewSize == null) return const SizedBox.shrink();

      return ClipRect(
        child: SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: previewSize.height,
              height: previewSize.width,
              child: CameraPreview(_controller!),
            ),
          ),
        ),
      );
    }

    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.document_scanner_rounded, size: 56, color: Colors.white54),
          const SizedBox(height: 16),
          Text(
            _camFailed
                ? 'Camera unavailable — import photos from gallery instead'
                : 'Starting camera…',
            style: const TextStyle(color: Colors.white70, fontSize: 15),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildViewfinderOverlay() {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;

          return Stack(
            children: [
              // Reticle guide depending on mode
              Center(
                child: _buildModeReticle(w, h),
              ),

              // Guidance prompt chip
              Positioned(
                top: MediaQuery.of(context).padding.top + 70,
                left: 20,
                right: 20,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24, width: 0.8),
                    ),
                    child: Text(
                      _getGuidanceText(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.2,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _getGuidanceText() {
    switch (_scanMode) {
      case ScanDocType.document:
        return 'Align document inside frame';
      case ScanDocType.idCard:
        if (_idCardFrontBytes == null) {
          return 'Step 1 of 2: Position FRONT of ID Card';
        } else {
          return 'Step 2 of 2: Flip and position BACK of ID Card';
        }
      case ScanDocType.book:
        return 'Position book or form inside frame';
    }
  }

  Widget _buildModeReticle(double screenW, double screenH) {
    if (_scanMode == ScanDocType.idCard) {
      // ID Card standard aspect ratio ~1.586
      final cardW = screenW * 0.85;
      final cardH = cardW / 1.586;

      return Container(
        width: cardW,
        height: cardH,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF00E5FF),
            width: 2.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00E5FF).withValues(alpha: 0.25),
              blurRadius: 16,
            ),
          ],
        ),
      );
    }

    if (_scanMode == ScanDocType.book) {
      final bookW = screenW * 0.90;
      final bookH = screenH * 0.58;

      return Container(
        width: bookW,
        height: bookH,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white70, width: 1.5),
        ),
        child: Center(
          child: Container(
            width: 1.5,
            height: bookH,
            color: Colors.white38,
          ),
        ),
      );
    }

    // Default Document Reticle (Adobe Scan style corner brackets)
    final docW = screenW * 0.86;
    final docH = screenH * 0.58;

    return SizedBox(
      width: docW,
      height: docH,
      child: Stack(
        children: [
          // Top Left
          Positioned(
            top: 0,
            left: 0,
            child: _buildCornerBracket(top: true, left: true),
          ),
          // Top Right
          Positioned(
            top: 0,
            right: 0,
            child: _buildCornerBracket(top: true, left: false),
          ),
          // Bottom Left
          Positioned(
            bottom: 0,
            left: 0,
            child: _buildCornerBracket(top: false, left: true),
          ),
          // Bottom Right
          Positioned(
            bottom: 0,
            right: 0,
            child: _buildCornerBracket(top: false, left: false),
          ),
        ],
      ),
    );
  }

  Widget _buildCornerBracket({required bool top, required bool left}) {
    const double length = 28;
    const double thickness = 3.5;
    const color = Color(0xFF00E5FF);

    return SizedBox(
      width: length,
      height: length,
      child: CustomPaint(
        painter: _CornerPainter(
          top: top,
          left: left,
          thickness: thickness,
          color: color,
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 8, 16, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.black.withValues(alpha: 0.8),
            Colors.transparent,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Close button
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white, size: 26),
            onPressed: () {
              if (_pages.isNotEmpty) {
                showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Discard Scan Session?'),
                    content: Text(
                        'You have ${_pages.length} unsaved scan page(s). Exiting will discard them.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Keep Scanning'),
                      ),
                      FilledButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          context.pop();
                        },
                        style: FilledButton.styleFrom(backgroundColor: Colors.red),
                        child: const Text('Discard'),
                      ),
                    ],
                  ),
                );
              } else {
                context.pop();
              }
            },
          ),

          // Flash toggle
          IconButton(
            icon: Icon(
              _torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
              color: _torchOn ? const Color(0xFFFFD600) : Colors.white70,
              size: 24,
            ),
            onPressed: _toggleTorch,
          ),

          // Auto / Manual capture pill
          InkWell(
            onTap: () => setState(() => _autoCapture = !_autoCapture),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _autoCapture
                    ? const Color(0xFF00E5FF).withValues(alpha: 0.25)
                    : Colors.white12,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _autoCapture ? const Color(0xFF00E5FF) : Colors.white30,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _autoCapture ? Icons.bolt_rounded : Icons.touch_app_rounded,
                    color: _autoCapture ? const Color(0xFF00E5FF) : Colors.white,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _autoCapture ? 'Auto Capture' : 'Manual',
                    style: TextStyle(
                      color: _autoCapture ? const Color(0xFF00E5FF) : Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.of(context).padding.bottom + 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.95),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Retake button if front of ID card is pending
          if (_scanMode == ScanDocType.idCard && _idCardFrontBytes != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextButton.icon(
                onPressed: () => setState(() => _idCardFrontBytes = null),
                icon: const Icon(Icons.refresh_rounded, size: 16, color: Colors.amber),
                label: const Text('Retake Front Side', style: TextStyle(color: Colors.amber)),
                style: TextButton.styleFrom(
                  backgroundColor: Colors.black54,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                ),
              ),
            ),

          // Filter chips
          _buildFilterRow(),

          const SizedBox(height: 12),

          // Scan Mode carousel
          _buildModeSelector(),

          const SizedBox(height: 20),

          // Shutter Action Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Gallery import
              IconButton(
                onPressed: _busy ? null : _import,
                icon: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white12,
                  ),
                  child: const Icon(Icons.photo_library_outlined, color: Colors.white, size: 24),
                ),
              ),

              // Large Adobe Scan circular shutter button
              GestureDetector(
                onTap: _busy || !_camReady ? null : _capture,
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                  ),
                  child: Center(
                    child: Container(
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _scanMode == ScanDocType.idCard
                            ? const Color(0xFF00E5FF)
                            : Colors.white,
                      ),
                      child: _busy
                          ? const Center(
                              child: SizedBox(
                                width: 26,
                                height: 26,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                  color: Colors.black87,
                                ),
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
              ),

              // Page thumbnail bubble with badge
              GestureDetector(
                onTap: _pages.isEmpty ? null : _openReviewSheet,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white30, width: 1.2),
                      ),
                      child: _pages.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(9),
                              child: Image.file(
                                File(_pages.last.path),
                                fit: BoxFit.cover,
                              ),
                            )
                          : const Icon(Icons.description_outlined, color: Colors.white54, size: 22),
                    ),
                    if (_pages.isNotEmpty)
                      Positioned(
                        top: -6,
                        right: -6,
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: const BoxDecoration(
                            color: Color(0xFF00E5FF),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${_pages.length}',
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterRow() {
    final filters = [
      (ScanFilter.enhanced, 'Auto Color', Icons.auto_fix_high_rounded),
      (ScanFilter.original, 'Original', Icons.photo_camera_back_outlined),
      (ScanFilter.grayscale, 'Grayscale', Icons.filter_b_and_w_rounded),
      (ScanFilter.monochrome, 'B&W Text', Icons.text_snippet_outlined),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final f in filters)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                avatar: Icon(
                  f.$3,
                  size: 14,
                  color: _activeFilter == f.$1 ? Colors.black : Colors.white70,
                ),
                label: Text(
                  f.$2,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _activeFilter == f.$1 ? Colors.black : Colors.white,
                  ),
                ),
                selected: _activeFilter == f.$1,
                selectedColor: Colors.white,
                backgroundColor: Colors.white12,
                showCheckmark: false,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                onSelected: (selected) {
                  if (selected) setState(() => _activeFilter = f.$1);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildModeSelector() {
    final modes = [
      (ScanDocType.document, 'Document'),
      (ScanDocType.idCard, 'ID Card (2-Sided)'),
      (ScanDocType.book, 'Book / Form'),
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final m in modes)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: InkWell(
              onTap: () {
                if (_scanMode != m.$1) {
                  setState(() {
                    _scanMode = m.$1;
                    _idCardFrontBytes = null;
                  });
                }
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: _scanMode == m.$1
                      ? Colors.white.withValues(alpha: 0.18)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _scanMode == m.$1 ? const Color(0xFF00E5FF) : Colors.transparent,
                    width: 1,
                  ),
                ),
                child: Text(
                  m.$2,
                  style: TextStyle(
                    color: _scanMode == m.$1 ? const Color(0xFF00E5FF) : Colors.white60,
                    fontSize: 13,
                    fontWeight: _scanMode == m.$1 ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Modal sheet for reviewing, reordering, filtering, and saving scanned pages.
class _ReviewPagesModal extends StatelessWidget {
  const _ReviewPagesModal({
    required this.pages,
    required this.onFilterChanged,
    required this.onDelete,
    required this.onReorder,
    required this.onSavePdf,
  });

  final List<_ScanPageItem> pages;
  final void Function(int index, ScanFilter filter) onFilterChanged;
  final void Function(int index) onDelete;
  final void Function(int oldIndex, int newIndex) onReorder;
  final VoidCallback onSavePdf;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Scanned Pages (${pages.length})',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            const Divider(color: Colors.white12, height: 1),

            // Reorderable page list
            Expanded(
              child: pages.isEmpty
                  ? const Center(
                      child: Text(
                        'No scanned pages yet',
                        style: TextStyle(color: Colors.white54),
                      ),
                    )
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      itemCount: pages.length,
                      onReorder: onReorder,
                      itemBuilder: (ctx, i) {
                        final p = pages[i];
                        return Container(
                          key: ValueKey(p.path),
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Row(
                            children: [
                              // Drag reorder handle
                              const Icon(Icons.drag_indicator_rounded, color: Colors.white38),
                              const SizedBox(width: 8),

                              // Page thumbnail
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  File(p.path),
                                  width: 60,
                                  height: 80,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              const SizedBox(width: 14),

                              // Details & Filter
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Page ${i + 1}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 6,
                                      children: [
                                        for (final f in [
                                          (ScanFilter.enhanced, 'Auto Color'),
                                          (ScanFilter.original, 'Original'),
                                          (ScanFilter.grayscale, 'Grayscale'),
                                          (ScanFilter.monochrome, 'B&W Text'),
                                        ])
                                          ChoiceChip(
                                            label: Text(
                                              f.$2,
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: p.filter == f.$1 ? Colors.black : Colors.white70,
                                              ),
                                            ),
                                            selected: p.filter == f.$1,
                                            selectedColor: Colors.white,
                                            backgroundColor: Colors.white10,
                                            showCheckmark: false,
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: -2),
                                            onSelected: (selected) {
                                              if (selected) onFilterChanged(i, f.$1);
                                            },
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              // Delete button
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                                onPressed: () => onDelete(i),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),

            // Bottom action row
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white30),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Add More Pages'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: pages.isEmpty ? null : onSavePdf,
                      icon: const Icon(Icons.picture_as_pdf_rounded),
                      label: Text('Save PDF (${pages.length})'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF00E5FF),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanPageItem {
  _ScanPageItem({
    required this.path,
    required this.width,
    required this.height,
    required this.rawBytes,
    required this.filter,
  });
  String path;
  int width;
  int height;
  final Uint8List rawBytes;
  ScanFilter filter;
}

class _CornerPainter extends CustomPainter {
  _CornerPainter({
    required this.top,
    required this.left,
    required this.thickness,
    required this.color,
  });

  final bool top;
  final bool left;
  final double thickness;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    if (top && left) {
      path.moveTo(0, size.height);
      path.lineTo(0, 0);
      path.lineTo(size.width, 0);
    } else if (top && !left) {
      path.moveTo(size.width, size.height);
      path.lineTo(size.width, 0);
      path.lineTo(0, 0);
    } else if (!top && left) {
      path.moveTo(0, 0);
      path.lineTo(0, size.height);
      path.lineTo(size.width, size.height);
    } else {
      path.moveTo(size.width, 0);
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CornerPainter oldDelegate) => false;
}

/// Top-level isolate runner for single scan page image processing.
Future<ScanPage> runScanPageInIsolate(Uint8List bytes, [ScanFilter filter = ScanFilter.enhanced]) {
  return Isolate.run(() => processScanPage(bytes, filter: filter));
}

/// Top-level isolate runner for scan images to PDF generation.
Future<ImagesToPdfResult> runScanImagesToPdfInIsolate(ImagesToPdfArgs args) {
  return Isolate.run(() => imagesToPdfTask(args));
}

/// Top-level isolate runner for stitching 2-sided ID card pages.
Future<ScanPage> runStitchIdCardInIsolate(Uint8List front, Uint8List back) {
  return Isolate.run(() => stitchIdCardPages(frontBytes: front, backBytes: back));
}
