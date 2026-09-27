import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/history/history_store.dart';
import '../../core/pdf/images_to_pdf_service.dart';
import '../../core/scan/scan_service.dart';

/// Feature 11: Document Scanner.
///
/// Device-only camera capture; without a usable camera (desktop, some
/// emulators) the screen degrades to gallery import. Processing is the
/// pure-Dart core (auto-crop, deskew, shadow-clean) run via [Isolate.run]
/// per shot so the UI never freezes mid-capture.
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
  final List<_ScanPageItem> _pages = [];

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
      final d = Directory(
          '${dir.path}${Platform.pathSeparator}scan_session');
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
      await _addProcessed(bytes);
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
        await _addProcessed(File(f.path!).readAsBytesSync());
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addProcessed(Uint8List bytes) async {
    final page = await runScanPageInIsolate(bytes);
    final dir = await getApplicationDocumentsDirectory();
    final sessionDir =
        '${dir.path}${Platform.pathSeparator}scan_session';
    final session = ScanSession(sessionDir);
    final path = session.addPage(page.bytes);
    if (mounted) {
      setState(() => _pages.add(_ScanPageItem(
            path: path,
            width: page.width,
            height: page.height,
          )));
    }
  }

  Future<void> _savePdf() async {
    if (_pages.isEmpty || _saving) return;
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
        // History is best-effort; the PDF is already saved.
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved: $name')),
      );
      setState(_pages.clear);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
      appBar: AppBar(title: Text('Scan Document')),
      body: Column(
        children: [
          Expanded(child: _preview()),
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
                    Padding(
                      padding: const EdgeInsets.all(4),
                      child: Image.file(File(p.path), width: 72, height: 88,
                          fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: InkWell(
                        onTap: () => setState(() => _pages.removeAt(i)),
                        child: const Icon(Icons.cancel_rounded, size: 20),
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
                    onPressed:
                        _pages.isEmpty || _saving ? null : _savePdf,
                    icon: _saving
                        ? const SizedBox(
                            width: 16, height: 16,
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
  _ScanPageItem({required this.path, required this.width, required this.height});
  final String path;
  final int width;
  final int height;
}

/// Top-level isolate runner for single scan page image processing.
Future<ScanPage> runScanPageInIsolate(Uint8List bytes) {
  return Isolate.run(() => processScanPage(bytes));
}

/// Top-level isolate runner for scan images to PDF generation.
Future<ImagesToPdfResult> runScanImagesToPdfInIsolate(ImagesToPdfArgs args) {
  return Isolate.run(() => imagesToPdfTask(args));
}
