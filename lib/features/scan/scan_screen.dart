import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/history/history_store.dart';
import '../../core/pdf/images_to_pdf_service.dart';
import '../../core/scan/scan_service.dart';

/// Feature 11: Document Scanner (Adobe Scan style).
///
/// Multi-page camera capture with filter themes (Auto Clean, Original Color,
/// Grayscale, B&W Text), reorderable page strip, per-page filter adjustment,
/// and transparent save destination with direct Open, Share, and Save to Device.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  CameraController? _controller;
  bool _camReady = false;
  bool _camFailed = false;
  bool _busy = false;
  bool _saving = false;
  bool _torchOn = false;
  ScanFilter _activeFilter = ScanFilter.enhanced;
  final List<_ScanPageItem> _pages = [];

  Future<void> _toggleTorch() async {
    final ctrl = _controller;
    if (ctrl == null || !_camReady) return;
    try {
      final next = !_torchOn;
      await ctrl.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      setState(() => _torchOn = next);
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _resetSessionDir();
    _initCamera();
  }

  /// Scratch pages from a previous run are junk (numbering restarts at
  /// page_01); anything worth keeping is already inside a saved PDF.
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

  Future<void> _capture() async {
    final ctrl = _controller;
    if (_busy || !_camReady || ctrl == null) return;
    setState(() => _busy = true);
    try {
      final file = await ctrl.takePicture();
      final bytes = await file.readAsBytes();
      await _addProcessed(bytes, _activeFilter);
    } on CameraException {
      if (mounted) {
        setState(() => _camFailed = true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Gallery import runs through the exact same processing pipeline as the
  /// camera path — a photo of a document becomes a scan page either way.
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
    final dir = await getApplicationDocumentsDirectory();
    final sessionDir = '${dir.path}${Platform.pathSeparator}scan_session';
    final session = ScanSession(sessionDir);
    final path = session.addPage(page.bytes);
    if (mounted) {
      setState(() => _pages.add(_ScanPageItem(
            path: path,
            width: page.width,
            height: page.height,
            rawBytes: bytes,
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

  Future<void> _showPageOptions(int index) async {
    final item = _pages[index];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Page ${index + 1} Filter',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                SizedBox(
                  height: 180,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(File(item.path), fit: BoxFit.contain),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final f in [
                      (ScanFilter.enhanced, 'Auto Clean'),
                      (ScanFilter.original, 'Color'),
                      (ScanFilter.grayscale, 'Grayscale'),
                      (ScanFilter.monochrome, 'B&W'),
                    ])
                      ChoiceChip(
                        label: Text(f.$2),
                        selected: item.filter == f.$1,
                        onSelected: (selected) async {
                          if (selected) {
                            await _changePageFilter(index, f.$1);
                            setModalState(() {});
                          }
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                        label: const Text('Delete Page', style: TextStyle(color: Colors.red)),
                        onPressed: () {
                          setState(() => _pages.removeAt(index));
                          Navigator.pop(ctx);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Done'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
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
                labelText: 'PDF Name',
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
            child: const Text('Save'),
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
                    setState(_pages.clear);
                  },
                  child: const Text('Scan New Document'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _reorder(int oldI, int newI) {
    setState(() {
      final p = _pages.removeAt(oldI);
      _pages.insert(newI, p);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Document'),
        actions: [
          if (_camReady)
            IconButton(
              tooltip: _torchOn ? 'Turn off flash' : 'Turn on flash',
              icon: Icon(_torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded),
              onPressed: _toggleTorch,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _preview()),
          _filterBar(),
          _pageStrip(),
          _controls(),
        ],
      ),
    );
  }

  Widget _preview() {
    if (_camReady && _controller != null) {
      return CameraPreview(_controller!);
    }
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.document_scanner_rounded,
              size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(
            _camFailed
                ? 'Camera unavailable — import a photo instead'
                : 'Starting camera…',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _filterBar() {
    final filters = [
      (ScanFilter.enhanced, 'Auto Clean', Icons.auto_fix_high_rounded),
      (ScanFilter.original, 'Color', Icons.photo_camera_back_outlined),
      (ScanFilter.grayscale, 'Grayscale', Icons.filter_b_and_w_rounded),
      (ScanFilter.monochrome, 'B&W Text', Icons.text_snippet_outlined),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final f in filters)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  avatar: Icon(f.$3, size: 16),
                  label: Text(f.$2),
                  selected: _activeFilter == f.$1,
                  onSelected: (selected) {
                    if (selected) setState(() => _activeFilter = f.$1);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _pageStrip() {
    return SizedBox(
      height: 96,
      child: _pages.isEmpty
          ? const SizedBox.shrink()
          : ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _pages.length,
              onReorderItem: _reorder,
              buildDefaultDragHandles: true,
              itemBuilder: (context, i) {
                final p = _pages[i];
                return Stack(
                  key: ValueKey(p.path),
                  children: [
                    InkWell(
                      onTap: () => _showPageOptions(i),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.file(File(p.path),
                              width: 72, height: 88, fit: BoxFit.cover),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: InkWell(
                        onTap: () => setState(() => _pages.removeAt(i)),
                        child: Container(
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black54,
                          ),
                          child: const Icon(Icons.cancel_rounded,
                              size: 18, color: Colors.white),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 4,
                      left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(color: Colors.white, fontSize: 10),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  Widget _controls() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _import,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Import'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _pages.isEmpty || _saving ? null : _startSavePdf,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.picture_as_pdf_rounded),
                    label: Text(_pages.isEmpty
                        ? 'Save PDF'
                        : 'Save PDF (${_pages.length})'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy || !_camReady ? null : _capture,
                icon: const Icon(Icons.camera_alt_rounded),
                label: Text(_busy ? 'Processing…' : 'Capture page'),
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

/// Top-level isolate runner for single scan page image processing.
Future<ScanPage> runScanPageInIsolate(Uint8List bytes, [ScanFilter filter = ScanFilter.enhanced]) {
  return Isolate.run(() => processScanPage(bytes, filter: filter));
}

/// Top-level isolate runner for scan images to PDF generation.
Future<ImagesToPdfResult> runScanImagesToPdfInIsolate(ImagesToPdfArgs args) {
  return Isolate.run(() => imagesToPdfTask(args));
}
