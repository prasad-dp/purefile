import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../../core/history/history_store.dart';
import '../../core/pdf/pdf_stamp_service.dart';
import '../../core/theme.dart';

/// Feature 13: Signature & Stamp.
///
/// Dedicated interactive flow:
/// - Pick a PDF to stamp.
/// - Draw signature with ink color (Black, Legal Blue, Red) and stroke thickness.
/// - Optional dynamic date stamp ("Signed: YYYY-MM-DD").
/// - Signature library: save and reuse frequent signatures.
/// - Choose page, anchor position, scale, and flatten directly into the PDF.
/// - Post-save sheet with Open, Share, and Save to Device.
class SignScreen extends ConsumerStatefulWidget {
  const SignScreen({super.key});

  @override
  ConsumerState<SignScreen> createState() => _SignScreenState();
}

class _SignScreenState extends ConsumerState<SignScreen> {
  String? _pdfPath;
  String? _pdfName;
  Uint8List? _stampBytes;
  bool _busy = false;

  final List<List<Offset>> _strokes = [];
  final List<List<Offset>> _redo = [];

  int _page = 1;
  StampAnchor _anchor = StampAnchor.bottomRight;
  int _scalePercent = 25;
  int _pageCount = 1;

  // Customization
  Color _selectedInk = const Color(0xFF111827); // Default Black
  final double _strokeWidth = 3.0;
  bool _includeDate = false;

  final List<File> _savedSignatures = [];

  static const _padColor = Color(0xFFFFFFFF);

  @override
  void initState() {
    super.initState();
    _loadSavedSignatures();
  }

  Future<void> _loadSavedSignatures() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final sigDir = Directory('${dir.path}${Platform.pathSeparator}signatures');
      if (sigDir.existsSync()) {
        final files = sigDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.png'))
            .toList();
        if (mounted) setState(() => _savedSignatures..clear()..addAll(files));
      }
    } catch (_) {}
  }

  void _undo() {
    if (_strokes.isEmpty) return;
    setState(() {
      _redo.add(_strokes.removeLast());
    });
  }

  void _clear() {
    setState(() {
      _strokes.clear();
      _redo.clear();
    });
  }

  /// Renders the strokes to a tight-cropped PNG with transparency.
  Future<void> _useDrawing({bool saveToLibrary = false}) async {
    if (_strokes.isEmpty) return;
    setState(() => _busy = true);
    try {
      var minX = double.infinity, minY = double.infinity;
      var maxX = 0.0, maxY = 0.0;
      for (final s in _strokes) {
        for (final p in s) {
          if (p.dx < minX) minX = p.dx;
          if (p.dy < minY) minY = p.dy;
          if (p.dx > maxX) maxX = p.dx;
          if (p.dy > maxY) maxY = p.dy;
        }
      }
      const pad = 12.0;
      minX -= pad;
      minY -= pad;
      maxX += pad;
      maxY += pad;

      final extraHeight = _includeDate ? 28.0 : 0.0;
      final w = (maxX - minX).clamp(1, 2048).ceil();
      final h = (maxY - minY + extraHeight).clamp(1, 2048).ceil();

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.scale(2);

      _paintStrokes(canvas, Offset(-minX, -minY));

      if (_includeDate) {
        final now = DateTime.now();
        final dateStr =
            'Signed: ${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
        final textPainter = TextPainter(
          text: TextSpan(
            text: dateStr,
            style: TextStyle(
              color: _selectedInk,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        textPainter.paint(
          canvas,
          Offset(
            ((w - textPainter.width) / 2).clamp(0, double.infinity),
            (maxY - minY + 4),
          ),
        );
      }

      final picture = recorder.endRecording();
      final image = await picture.toImage(w * 2, h * 2);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final pngBytes = byteData.buffer.asUint8List();

      if (saveToLibrary) {
        final dir = await getApplicationDocumentsDirectory();
        final sigDir = Directory('${dir.path}${Platform.pathSeparator}signatures');
        if (!sigDir.existsSync()) sigDir.createSync(recursive: true);
        final file = File(
            '${sigDir.path}${Platform.pathSeparator}sig_${DateTime.now().millisecondsSinceEpoch}.png');
        await file.writeAsBytes(pngBytes, flush: true);
        await _loadSavedSignatures();
      }

      if (mounted) {
        setState(() {
          _stampBytes = pngBytes;
          _strokes.clear();
          _redo.clear();
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _paintStrokes(Canvas canvas, Offset shift) {
    final paint = Paint()
      ..color = _selectedInk
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final s in _strokes) {
      if (s.length == 1) {
        canvas.drawCircle(
            Offset(s.first.dx + shift.dx, s.first.dy + shift.dy),
            _strokeWidth / 2,
            Paint()..color = _selectedInk);
        continue;
      }
      final path = Path()..moveTo(s.first.dx + shift.dx, s.first.dy + shift.dy);
      for (var i = 1; i < s.length; i++) {
        path.lineTo(s[i].dx + shift.dx, s[i].dy + shift.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  Future<void> _importStamp() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
      withData: true,
    );
    final files = picked?.files;
    final data = (files == null || files.isEmpty) ? null : files.first.bytes;
    if (data == null || data.isEmpty) return;
    setState(() => _stampBytes = data);
  }

  Future<void> _pickPdf() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: false,
    );
    final files = picked?.files;
    final path = (files == null || files.isEmpty) ? null : files.first.path;
    if (path == null) return;
    var pages = 1;
    try {
      final doc = PdfDocument(inputBytes: File(path).readAsBytesSync());
      pages = doc.pages.count.clamp(1, 9999);
      doc.dispose();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _pdfPath = path;
      _pdfName = path.split(Platform.pathSeparator).last;
      _pageCount = pages;
      _page = _page.clamp(1, pages);
    });
  }

  Future<void> _flattenStamp() async {
    final pdf = _pdfPath;
    final stamp = _stampBytes;
    if (pdf == null || stamp == null || _busy) return;
    setState(() => _busy = true);
    try {
      final docs = await getApplicationDocumentsDirectory();
      final outputs = '${docs.path}${Platform.pathSeparator}outputs';
      Directory(outputs).createSync(recursive: true);

      final page = _page;
      final anchor = _anchor;
      final scalePercent = _scalePercent;
      final args = StampArgs(
        inputPath: pdf,
        outputDir: outputs,
        stampBytes: stamp,
        pageNumber: page,
        anchor: anchor,
        marginPt: 24,
        scalePercent: scalePercent,
      );
      final result = await runStampInIsolate(args);
      try {
        await ref.read(historyProvider).record(HistoryEntry(
              path: result.outputPath,
              fileName: result.outputPath.split(Platform.pathSeparator).last,
              toolId: 'sign',
              sizeBytes: result.outputBytes,
              createdAt: DateTime.now(),
            ));
      } catch (_) {}
      if (mounted) {
        _showSuccessSheet(result);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showSuccessSheet(StampResult result) {
    final fileName = result.outputPath.split(Platform.pathSeparator).last;
    final sizeMb = (result.outputBytes / (1024 * 1024)).toStringAsFixed(2);

    showModalBottomSheet<void>(
      context: context,
      isDismissible: true,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.green, size: 48),
              const SizedBox(height: 10),
              Text('Document Signed',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text('$fileName · $sizeMb MB',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(sheetCtx),
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
      appBar: AppBar(title: const Text('Sign & Stamp')),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _pdfPicker(),
                const SizedBox(height: 12),
                if (_savedSignatures.isNotEmpty) ...[
                  _savedSignaturesSection(),
                  const SizedBox(height: 12),
                ],
                _signaturePad(),
                const SizedBox(height: 12),
                _stampPreview(),
                const SizedBox(height: 12),
                _options(),
                const SizedBox(height: 16),
                _saveButton(),
              ],
            ),
    );
  }

  Widget _pdfPicker() {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.picture_as_pdf_rounded),
        title: Text(_pdfName ?? 'Choose a PDF'),
        subtitle: _pdfPath != null ? Text('$_pageCount page(s)') : null,
        trailing: const Icon(Icons.folder_open_rounded),
        onTap: _pickPdf,
      ),
    );
  }

  Widget _savedSignaturesSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bookmark_border_rounded, size: 18),
                const SizedBox(width: 6),
                Text('Saved Signatures',
                    style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final f in _savedSignatures)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: InkWell(
                        onTap: () {
                          setState(() => _stampBytes = f.readAsBytesSync());
                        },
                        child: Stack(
                          children: [
                            Container(
                              width: 88,
                              height: 48,
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Image.file(f, fit: BoxFit.contain),
                            ),
                            Positioned(
                              top: 2,
                              right: 2,
                              child: InkWell(
                                onTap: () async {
                                  if (f.existsSync()) f.deleteSync();
                                  await _loadSavedSignatures();
                                },
                                child: Container(
                                  decoration: const BoxDecoration(
                                    color: Colors.black45,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.close,
                                      size: 14, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
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

  Widget _signaturePad() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Draw signature',
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                // Ink colors
                for (final c in [
                  const Color(0xFF111827), // Black
                  const Color(0xFF1D4ED8), // Legal Blue
                  const Color(0xFFDC2626), // Red
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: InkWell(
                      onTap: () => setState(() => _selectedInk = c),
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _selectedInk == c
                                ? Colors.white
                                : Colors.transparent,
                            width: 2,
                          ),
                          boxShadow: [
                            if (_selectedInk == c)
                              BoxShadow(color: c.withValues(alpha: 0.6), blurRadius: 4),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Undo',
                  icon: const Icon(Icons.undo_rounded, size: 20),
                  onPressed: _strokes.isEmpty ? null : _undo,
                ),
                IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  onPressed: _strokes.isEmpty ? null : _clear,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: 140,
              decoration: BoxDecoration(
                color: _padColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: PfColors.hairline(
                        Theme.of(context).brightness == Brightness.dark)),
              ),
              child: GestureDetector(
                onPanStart: (d) {
                  setState(() {
                    _strokes.add([d.localPosition]);
                    _redo.clear();
                  });
                },
                onPanUpdate: (d) {
                  if (_strokes.isEmpty) return;
                  setState(() => _strokes.last.add(d.localPosition));
                },
                child: CustomPaint(
                  painter: _SignaturePainter(
                    strokes: _strokes,
                    inkColor: _selectedInk,
                    strokeWidth: _strokeWidth,
                  ),
                  size: Size.infinite,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Checkbox(
                  value: _includeDate,
                  onChanged: (v) => setState(() => _includeDate = v ?? false),
                ),
                const Text('Add date stamp', style: TextStyle(fontSize: 13)),
                const Spacer(),
                OutlinedButton(
                  onPressed: _strokes.isEmpty ? null : () => _useDrawing(saveToLibrary: true),
                  child: const Text('Save & Use'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _strokes.isEmpty ? null : () => _useDrawing(saveToLibrary: false),
                  child: const Text('Use Drawing'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stampPreview() {
    final stamp = _stampBytes;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 120,
              height: 56,
              decoration: BoxDecoration(
                border: Border.all(
                    color: PfColors.hairline(
                        Theme.of(context).brightness == Brightness.dark)),
                borderRadius: BorderRadius.circular(8),
                color: Colors.white,
              ),
              child: stamp == null
                  ? const Center(
                      child: Text('No signature yet',
                          style: TextStyle(fontSize: 12, color: Colors.grey)))
                  : Image.memory(stamp, fit: BoxFit.contain),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _importStamp,
              icon: const Icon(Icons.upload_rounded),
              label: const Text('Import image'),
            ),
            if (stamp != null)
              IconButton(
                tooltip: 'Remove',
                onPressed: () => setState(() => _stampBytes = null),
                icon: const Icon(Icons.close_rounded),
              ),
          ],
        ),
      ),
    );
  }

  Widget _options() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Page', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(width: 12),
                Expanded(
                  child: Slider(
                    value: _page.toDouble(),
                    min: 1,
                    max: _pageCount.toDouble(),
                    divisions: _pageCount > 1 ? _pageCount - 1 : null,
                    label: '$_page',
                    onChanged: (v) => setState(() => _page = v.round()),
                  ),
                ),
                Text('$_page / $_pageCount'),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('Position', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(width: 12),
                Expanded(
                  child: SegmentedButton<StampAnchor>(
                    segments: const [
                      ButtonSegment(
                          value: StampAnchor.topLeft,
                          icon: Icon(Icons.north_west)),
                      ButtonSegment(
                          value: StampAnchor.topRight,
                          icon: Icon(Icons.north_east)),
                      ButtonSegment(
                          value: StampAnchor.center,
                          icon: Icon(Icons.center_focus_strong)),
                      ButtonSegment(
                          value: StampAnchor.bottomLeft,
                          icon: Icon(Icons.south_west)),
                      ButtonSegment(
                          value: StampAnchor.bottomRight,
                          icon: Icon(Icons.south_east)),
                    ],
                    selected: {_anchor},
                    onSelectionChanged: (s) =>
                        setState(() => _anchor = s.first),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('Size', style: Theme.of(context).textTheme.titleSmall),
                Expanded(
                  child: Slider(
                    value: _scalePercent.toDouble(),
                    min: 5,
                    max: 80,
                    label: '$_scalePercent%',
                    onChanged: (v) => setState(() => _scalePercent = v.round()),
                  ),
                ),
                SizedBox(
                    width: 44,
                    child: Text('$_scalePercent%', textAlign: TextAlign.end)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _saveButton() {
    final ready = _pdfPath != null && _stampBytes != null;
    return FilledButton.icon(
      onPressed: ready ? _flattenStamp : null,
      icon: const Icon(Icons.approval_rounded),
      label: const Text('Flatten into PDF'),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  _SignaturePainter({
    required this.strokes,
    required this.inkColor,
    required this.strokeWidth,
  });

  final List<List<Offset>> strokes;
  final Color inkColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = inkColor
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final s in strokes) {
      if (s.length == 1) {
        canvas.drawCircle(s.first, strokeWidth / 2, Paint()..color = inkColor);
        continue;
      }
      final path = Path()..moveTo(s.first.dx, s.first.dy);
      for (var i = 1; i < s.length; i++) {
        path.lineTo(s[i].dx, s[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) =>
      oldDelegate.strokes != strokes ||
      oldDelegate.inkColor != inkColor ||
      oldDelegate.strokeWidth != strokeWidth;
}

/// Top-level isolate runner to guarantee the closure captures ONLY [args]
/// and never the enclosing State or widget element tree.
Future<StampResult> runStampInIsolate(StampArgs args) {
  return Isolate.run(() => stampTask(args));
}
