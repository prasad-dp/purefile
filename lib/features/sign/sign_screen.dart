import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../../core/history/history_store.dart';
import '../../core/pdf/pdf_stamp_service.dart';
import '../../core/theme.dart';

/// Feature 13: Signature & Stamp — dedicated interactive flow (like the
/// scanner): pick a PDF, draw a signature (or import a stamp image), choose
/// page/anchor/size, flatten it in.
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
  String? _savedName;

  final List<List<Offset>> _strokes = [];
  final List<List<Offset>> _redo = [];

  int _page = 1;
  StampAnchor _anchor = StampAnchor.bottomRight;
  int _scalePercent = 25;
  int _pageCount = 1;

  static const _padColor = Color(0xFFFFFFFF);
  static const _inkColor = Color(0xFF1A1A1A);

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
  Future<void> _useDrawing() async {
    if (_strokes.isEmpty) return;
    setState(() => _busy = true);
    try {
      // Bounds over all points, padded.
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
      final w = (maxX - minX).clamp(1, 2048).ceil();
      final h = (maxY - minY).clamp(1, 2048).ceil();

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.scale(2); // retina-ish sharpness
      _paintStrokes(canvas, Offset(-minX, -minY));
      final picture = recorder.endRecording();
      final image = await picture.toImage(w * 2, h * 2);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      if (mounted) {
        setState(() {
          _stampBytes = byteData.buffer.asUint8List();
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
      ..color = _inkColor
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final s in _strokes) {
      if (s.length == 1) {
        canvas.drawCircle(
            Offset(s.first.dx + shift.dx, s.first.dy + shift.dy),
            1.5,
            Paint()..color = _inkColor);
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
    // Probe the page count so the page slider is meaningful.
    var pages = 1;
    try {
      final doc = PdfDocument(inputBytes: File(path).readAsBytesSync());
      pages = doc.pages.count.clamp(1, 9999);
      doc.dispose();
    } catch (_) {
      // Let the flatten step classify corrupt/encrypted with typed errors.
    }
    if (!mounted) return;
    setState(() {
      _pdfPath = path;
      _pdfName = path.split(Platform.pathSeparator).last;
      _pageCount = pages;
      _page = _page.clamp(1, pages);
      _savedName = null;
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
      // ISOLATE-SAFETY: read State fields into locals BEFORE the closure —
      // a closure that reads `this.*` captures the whole State (element tree)
      // and Isolate.run rejects it as unsendable on device.
      final page = _page;
      final anchor = _anchor;
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
      } catch (_) {
        // History is best-effort.
      }
      if (mounted) {
        setState(() {
          _savedName = result.outputPath.split(Platform.pathSeparator).last;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
                _signaturePad(),
                const SizedBox(height: 12),
                _stampPreview(),
                const SizedBox(height: 12),
                _options(),
                const SizedBox(height: 16),
                _saveButton(),
                if (_savedName != null) ...[
                  const SizedBox(height: 8),
                  Text('Saved: $_savedName',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
    );
  }

  Widget _pdfPicker() {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.picture_as_pdf_rounded),
        title: Text(_pdfName ?? 'Choose a PDF'),
        trailing: const Icon(Icons.folder_open_rounded),
        onTap: _pickPdf,
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
                  child: Text('Draw your signature',
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                IconButton(
                  tooltip: 'Undo',
                  onPressed: _strokes.isEmpty ? null : _undo,
                  icon: const Icon(Icons.undo_rounded),
                ),
                IconButton(
                  tooltip: 'Clear',
                  onPressed: _strokes.isEmpty ? null : _clear,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
            GestureDetector(
              onPanStart: (d) => setState(() => _strokes.add([d.localPosition])),
              onPanUpdate: (d) => setState(() {
                _strokes.last.add(d.localPosition);
              }),
              child: Container(
                height: 160,
                decoration: BoxDecoration(
                  color: _padColor,
                  border: Border.all(color: PfColors.hairline(Theme.of(context).brightness == Brightness.dark)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: CustomPaint(
                  painter: _SignaturePainter(
                    strokes: _strokes,
                    inkColor: _inkColor,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _strokes.isEmpty ? null : _useDrawing,
              icon: const Icon(Icons.check_rounded),
              label: const Text('Use this signature'),
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
                border: Border.all(color: PfColors.hairline(Theme.of(context).brightness == Brightness.dark)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: stamp == null
                  ? const Center(
                      child: Text('No signature yet',
                          style: TextStyle(fontSize: 12)))
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
                    child: Text('$_scalePercent%',
                        textAlign: TextAlign.end)),
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
  _SignaturePainter({required this.strokes, required this.inkColor});

  final List<List<Offset>> strokes;
  final Color inkColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = inkColor
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final s in strokes) {
      if (s.length == 1) {
        canvas.drawCircle(s.first, 1.5, Paint()..color = inkColor);
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
      oldDelegate.strokes != strokes;
}

/// Top-level isolate runner to guarantee the closure captures ONLY [args]
/// and never the enclosing State or widget element tree.
Future<StampResult> runStampInIsolate(StampArgs args) {
  return Isolate.run(() => stampTask(args));
}
