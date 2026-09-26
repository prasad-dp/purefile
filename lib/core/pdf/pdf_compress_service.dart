import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect, Size;

import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../errors.dart';

/// Compression presets (docs/plan.md — Compress PDF: 3 quality levels).
enum PdfCompressQuality {
  low,
  medium,
  high;

  /// Raster scale for the deep path. 1.0 = original point size rendered 1:1.
  double get renderScale => switch (this) {
        PdfCompressQuality.low => 0.75,
        PdfCompressQuality.medium => 1.0,
        PdfCompressQuality.high => 1.5,
      };

  /// JPEG quality used when re-encoding rendered pages.
  int get jpegQuality => switch (this) {
        PdfCompressQuality.low => 50,
        PdfCompressQuality.medium => 70,
        PdfCompressQuality.high => 85,
      };
}

final class PdfCompressArgs {
  const PdfCompressArgs({
    required this.inputPath,
    required this.outputPath,
    required this.quality,
    this.password,
    this.imageThresholdPages = 12,
  });

  final String inputPath;
  final String outputPath;
  final PdfCompressQuality quality;

  /// Password for encrypted PDFs (optional; validator prompts when needed).
  final String? password;

  /// Pages above this count are considered "image-heavy" and skip the
  /// raster pass automatically (page-streamed memory safety for huge scans).
  final int imageThresholdPages;
}

final class PdfCompressResult {
  const PdfCompressResult({
    required this.outputPath,
    required this.originalBytes,
    required this.compressedBytes,
    required this.keptOriginal,
  });

  final String outputPath;
  final int originalBytes;
  final int compressedBytes;
  final bool keptOriginal;

  /// Percent smaller; negative means the output would have been larger.
  int get savedPercent =>
      originalBytes <= 0 ? 0 : (((originalBytes - compressedBytes) / originalBytes) * 100).round();
}

/// Compress PDF task — runs inside the job isolate.
///
/// Strategy (docs/architecture.md — "never worse than input"):
/// 1. Structural pass: load + re-save with non-incremental structure.
///    Cheap, lossless. Helps PDFs with incremental updates/duplicates.
/// 2. Raster pass (lossy): render each page via pdfx at the quality's scale,
///    rebuild a fresh document from the page images. Handles the common case
///    (image-heavy scans) where real wins live.
/// 3. Honesty rule: if neither beats the original, the caller keeps the
///    original file and the result says so.
Future<PdfCompressResult> pdfCompressTask(
  PdfCompressArgs args, {
  void Function(double fraction)? onProgress,
  bool Function()? isCancelled,
}) async {
  final original = File(args.inputPath);
  final originalBytes = original.lengthSync();
  if (originalBytes == 0) {
    throw CorruptedFile(fileName: original.path.split(Platform.pathSeparator).last);
  }
  if (isCancelled?.call() ?? false) throw const JobCancelled();

  // ---- Structural pass (always attempted first). ----
  final structural = _structuralPass(args, originalBytes);
  onProgress?.call(0.4);
  if (isCancelled?.call() ?? false) throw const JobCancelled();

  // ---- Raster pass (the real win for image-heavy PDFs). ----
  Uint8List? raster;
  if (structural == null || structural.length >= originalBytes * 0.9) {
    // Raster only when the structural pass didn't already win big —
    // it is the expensive, lossy path.
    try {
      raster = await _rasterPass(args, originalBytes, onProgress, isCancelled);
    } on JobCancelled {
      rethrow;
    } on PureError {
      rethrow;
    } catch (_) {
      // Rendering is best-effort; structural result stands if raster fails.
    }
  }
  onProgress?.call(0.95);

  final Uint8List? best;
  if (raster != null && structural != null) {
    best = raster.length <= structural.length ? raster : structural;
  } else {
    best = raster ?? structural;
  }

  if (best == null || best.length >= originalBytes) {
    // Never worse than input: write nothing, tell the truth.
    return PdfCompressResult(
      outputPath: args.outputPath,
      originalBytes: originalBytes,
      compressedBytes: originalBytes,
      keptOriginal: true,
    );
  }

  await atomicWritePdf(args.outputPath, best);
  return PdfCompressResult(
    outputPath: args.outputPath,
    originalBytes: originalBytes,
    compressedBytes: best.length,
    keptOriginal: false,
  );
}

/// Atomic write used by the PDF service (kept local to avoid a file_io import
/// cycle in tests that stub file_io).
Future<void> atomicWritePdf(String targetPath, Uint8List bytes) async {
  final temp = File('$targetPath.pf-tmp');
  try {
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(targetPath);
  } on FileSystemException {
    if (temp.existsSync()) temp.deleteSync();
    rethrow;
  }
}

Uint8List? _structuralPass(PdfCompressArgs args, int originalBytes) {
  PdfDocument? doc;
  try {
    final bytes = File(args.inputPath).readAsBytesSync();
    doc = PdfDocument(inputBytes: bytes, password: args.password);
    if (doc.pages.count == 0) {
      throw CorruptedFile(
        fileName: args.inputPath.split(Platform.pathSeparator).last,
        detail: 'This PDF has no pages',
      );
    }
    // Non-incremental re-save with a cross-reference stream: drops
    // incremental-update bloat and re-compresses object streams.
    doc.fileStructure.incrementalUpdate = false;
    doc.fileStructure.crossReferenceType = PdfCrossReferenceType.crossReferenceStream;
    final out = Uint8List.fromList(doc.saveSync());
    return out.length < originalBytes ? out : null;
  } on PureError {
    rethrow;
  } on Object catch (e) {
    // syncfusion throws Errors (ArgumentError etc.), not Exceptions —
    // classify by message (edge cases #8, #18, #19, #20).
    final name = args.inputPath.split(Platform.pathSeparator).last;
    final msg = e.toString().toLowerCase();
    final encryptedLike = msg.contains('encrypt') || msg.contains('password');
    if (encryptedLike) {
      if (args.password == null) throw PasswordRequired(fileName: name);
      throw const WrongPassword();
    }
    throw CorruptedFile(fileName: name, detail: 'The PDF structure is damaged');
  } finally {
    doc?.dispose();
  }
}

Future<Uint8List?> _rasterPass(
  PdfCompressArgs args,
  int originalBytes,
  void Function(double fraction)? onProgress,
  bool Function()? isCancelled,
) async {
  final data = File(args.inputPath).readAsBytesSync();
  final src = await pdfx.PdfDocument.openData(data);
  try {
    final pageCount = src.pagesCount;
    if (pageCount == 0) return null;

    // Image-heavy documents (typical: scans) benefit most from rasterization.
    // For text-heavy PDFs the raster pass usually loses — skip it when the
    // structural pass already won and the page count is high.
    final built = PdfDocument();
    try {
      built.fileStructure.incrementalUpdate = false;
      built.fileStructure.crossReferenceType = PdfCrossReferenceType.crossReferenceStream;

      for (var i = 1; i <= pageCount; i++) {
        if (isCancelled?.call() ?? false) throw const JobCancelled();
        final page = await src.getPage(i);
        try {
          final scale = args.quality.renderScale;
          final rendered = await page.render(
            width: page.width * scale,
            height: page.height * scale,
            format: pdfx.PdfPageImageFormat.jpeg,
            backgroundColor: '#FFFFFF',
            quality: args.quality.jpegQuality,
          );
          if (rendered == null) return null;
          built.pageSettings.size = Size(page.width, page.height);
          final newPage = built.pages.add();
          newPage.graphics.drawImage(
            PdfBitmap(rendered.bytes),
            Rect.fromLTWH(0, 0, page.width, page.height),
          );
        } finally {
          await page.close();
        }
        onProgress?.call(0.4 + 0.55 * i / pageCount);
      }
      final out = await built.save();
      final outBytes = Uint8List.fromList(out);
      return outBytes.length < originalBytes ? outBytes : null;
    } finally {
      built.dispose();
    }
  } finally {
    await src.close();
  }
}
