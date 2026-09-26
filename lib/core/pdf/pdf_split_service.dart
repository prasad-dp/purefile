import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Offset, Size;

import 'package:archive/archive.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../errors.dart';
import '../file_io.dart' show uniqueDestination, atomicWriteBytes;

/// How the user asked to split the document.
enum SplitMode {
  /// Fixed-size chunks: pages 1..n in groups of [SplitArgs.interval].
  everyN,

  /// Comma/semicolon-separated ranges like `1-3,5,8-10` (1-based, inclusive).
  ranges,

  /// The selected pages, each as its own PDF.
  extract,
}

final class SplitArgs {
  const SplitArgs({
    required this.inputPath,
    required this.outputDir,
    required this.mode,
    this.interval = 1,
    this.ranges = const [],
    this.selection = const [],
    this.password,
  });

  final String inputPath;
  final String outputDir;
  final SplitMode mode;

  /// [SplitMode.everyN]: pages per output piece (validated ≥ 1).
  final int interval;

  /// [SplitMode.ranges]: 1-based inclusive (start, end) pairs, in user order.
  final List<(int, int)> ranges;

  /// [SplitMode.extract]: 1-based page numbers, deduplicated and sorted.
  final List<int> selection;

  /// Password for opening encrypted PDFs (v1: single password).
  final String? password;
}

final class SplitResult {
  const SplitResult({required this.outputPath, required this.outputBytes, required this.pieceCount});

  /// A single PDF when the split produced one piece, otherwise a zip of the
  /// pieces (edge case #36 — multi-output results are zipped for sharing).
  final String outputPath;
  final int outputBytes;
  final int pieceCount;
}

/// Split PDF task — runs inside the job isolate.
///
/// Every piece is a valid standalone PDF built from page templates (no
/// re-encode). Ranges/slices that fall outside the document are skipped; if
/// nothing usable remains, the whole split fails with a typed error and no
/// output is written.
Future<SplitResult> pdfSplitTask(
  SplitArgs args, {
  void Function(double fraction, String? label)? onProgress,
  bool Function()? isCancelled,
}) async {
  final name = args.inputPath.split(Platform.pathSeparator).last;

  final List<(int, int)> pieces;
  int pageCount;
  try {
    final bytes = File(args.inputPath).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes, password: args.password);
    try {
      pageCount = doc.pages.count;
      if (pageCount == 0) {
        throw CorruptedFile(fileName: name, detail: 'This PDF has no pages');
      }
      pieces = switch (args.mode) {
        SplitMode.everyN => _everyNPieces(pageCount, args.interval, name),
        SplitMode.ranges => _rangePieces(args.ranges, pageCount, name),
        SplitMode.extract => _extractPieces(args.selection, pageCount, name),
      };
    } finally {
      doc.dispose();
    }
  } on PureError {
    rethrow;
  } on Object catch (e) {
    // syncfusion throws Errors (ArgumentError etc.), not Exceptions —
    // classify by message (same contract as the compress service).
    final msg = e.toString().toLowerCase();
    final encryptedLike = msg.contains('encrypt') || msg.contains('password');
    if (encryptedLike) {
      if (args.password == null) throw PasswordRequired(fileName: name);
      throw const WrongPassword();
    }
    throw CorruptedFile(fileName: name, detail: 'The PDF structure is damaged');
  }

  // Build every piece, reporting progress per piece and honoring cancel.
  final pieceFiles = <(String, Uint8List)>[];
  final stem = _stemOf(name);
  for (var i = 0; i < pieces.length; i++) {
    if (isCancelled?.call() ?? false) throw const JobCancelled();
    final (start, end) = pieces[i];
    final label = start == end ? 'Page $start' : 'Pages $start-$end';
    onProgress?.call((i + 1) / (pieces.length + 1), label);

    final bytes = File(args.inputPath).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes, password: args.password);
    try {
      pieceFiles.add((
        '$stem${_pieceSuffix(start, end)}.pdf',
        _extractPiece(doc, start, end),
      ));
    } finally {
      doc.dispose();
    }
  }

  if (pieceFiles.length == 1) {
    final (fileName, data) = pieceFiles.single;
    final target = uniqueDestination(args.outputDir, fileName);
    await atomicWriteBytes(target, data);
    return SplitResult(outputPath: target, outputBytes: data.length, pieceCount: 1);
  }

  // 2+ pieces → one zip (names inside the zip need no uniqueness pass).
  onProgress?.call(pieces.length / (pieces.length + 1), 'Packing zip');
  final archive = Archive();
  for (final (fileName, data) in pieceFiles) {
    archive.add(ArchiveFile(fileName, data.length, data));
  }
  final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive));
  final zipTarget = uniqueDestination(args.outputDir, '$stem split.zip');
  await atomicWriteBytes(zipTarget, zipBytes);
  return SplitResult(
    outputPath: zipTarget,
    outputBytes: zipBytes.length,
    pieceCount: pieceFiles.length,
  );
}

/// Extracts [start]..[end] (1-based inclusive) into a standalone PDF.
Uint8List _extractPiece(PdfDocument doc, int start, int end) {
  final piece = PdfDocument();
  piece.fileStructure.incrementalUpdate = false;
  piece.fileStructure.crossReferenceType = PdfCrossReferenceType.crossReferenceStream;
  try {
    for (var p = start; p <= end; p++) {
      final srcPage = doc.pages[p - 1];
      final template = srcPage.createTemplate();
      final w = srcPage.size.width;
      final h = srcPage.size.height;
      final section = piece.sections!.add();
      if (w > h) section.pageSettings.orientation = PdfPageOrientation.landscape;
      section.pageSettings.size = Size(w, h);
      final page = section.pages.add();
      page.graphics.drawPdfTemplate(template, Offset.zero, Size(w, h));
    }
    return Uint8List.fromList(piece.saveSync());
  } finally {
    piece.dispose();
  }
}

List<(int, int)> _everyNPieces(int pageCount, int interval, String name) {
  if (interval < 1) {
    throw UnsupportedFormat(fileName: name, expected: 'pages per file of at least 1');
  }
  return [
    for (var start = 1; start <= pageCount; start += interval)
      (start, (start + interval - 1).clamp(1, pageCount)),
  ];
}

List<(int, int)> _rangePieces(List<(int, int)> ranges, int pageCount, String name) {
  final kept = <(int, int)>[];
  for (final (start, end) in ranges) {
    // Entirely outside the document or reversed → meaningless piece, skip.
    if (start < 1 || start > pageCount || end < start) continue;
    kept.add((start.clamp(1, pageCount), end.clamp(1, pageCount)));
  }
  if (kept.isEmpty) {
    throw UnsupportedFormat(fileName: name, expected: 'a range within the document');
  }
  return kept;
}

List<(int, int)> _extractPieces(List<int> selection, int pageCount, String name) {
  final pages = {...selection}.where((p) => p >= 1 && p <= pageCount).toList()..sort();
  if (pages.isEmpty) {
    throw UnsupportedFormat(fileName: name, expected: 'a selected page within the document');
  }
  return [for (final p in pages) (p, p)];
}

/// Strips the extension and anything a filesystem would treat as a path or a
/// control character (edge #31: emoji/Cyrillic names must survive).
String _stemOf(String name) {
  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name;
  return stem.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_');
}

String _pieceSuffix(int start, int end) =>
    start == end ? '_p$start' : '_p$start-$end';
