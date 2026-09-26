import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect, Size;

import 'package:image/image.dart' as img;
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../errors.dart';
import '../file_io.dart' show uniqueDestination;

/// Where the stamp sits on the page (margin kept from every referenced edge).
enum StampAnchor { topLeft, topRight, center, bottomLeft, bottomRight }

final class StampArgs {
  const StampArgs({
    required this.inputPath,
    required this.outputDir,
    required this.stampBytes,
    this.pageNumber = 1,
    this.anchor = StampAnchor.bottomRight,
    this.marginPt = 24,
    this.scalePercent = 25,
  });

  final String inputPath;
  final String outputDir;

  /// PNG bytes (alpha preserved — a drawn signature must not get a white box).
  final Uint8List stampBytes;

  /// 1-based page receiving the stamp.
  final int pageNumber;

  final StampAnchor anchor;

  /// Distance from the referenced edges, in points.
  final double marginPt;

  /// Stamp width as a percentage of the page width (5–80).
  final int scalePercent;
}

final class StampResult {
  const StampResult({
    required this.outputPath,
    required this.outputBytes,
    required this.pageCount,
  });
  final String outputPath;
  final int outputBytes;
  final int pageCount;
}

/// Computes the stamp rectangle in page points (origin = top-left).
/// Pure math — unit-tested directly.
Rect stampRect({
  required Size pageSize,
  required Size stampSize,
  required StampAnchor anchor,
  required double marginPt,
  required int scalePercent,
}) {
  final clamped = scalePercent.clamp(5, 80).toDouble();
  final w = pageSize.width * clamped / 100;
  final h = stampSize.height <= 0 || stampSize.width <= 0
      ? w
      : w * stampSize.height / stampSize.width;

  final maxX = pageSize.width - marginPt - w;
  final maxY = pageSize.height - marginPt - h;
  final x = switch (anchor) {
    StampAnchor.topLeft || StampAnchor.bottomLeft => marginPt,
    StampAnchor.center => maxX / 2,
    StampAnchor.topRight || StampAnchor.bottomRight => maxX,
  };
  final y = switch (anchor) {
    StampAnchor.topLeft || StampAnchor.topRight => marginPt,
    StampAnchor.center => maxY / 2,
    StampAnchor.bottomLeft || StampAnchor.bottomRight => maxY,
  };
  return Rect.fromLTWH(x, y, w, h);
}

/// Flattens [args.stampBytes] onto the requested page of a rebuilt document.
///
/// ALL pages are preserved 1:1 via templates (merge-service pattern); the
/// stamp is drawn only on [StampArgs.pageNumber], ON TOP of the content — a
/// flatten, not an annotation, so no PDF viewer can peel it off.
/// Encrypted input → [PasswordRequired]; corrupt → [CorruptedFile];
/// out-of-range page → [UnsupportedFormat] (nothing written).
Future<StampResult> stampTask(
  StampArgs args, {
  void Function(double fraction, String? label)? onProgress,
  bool Function()? isCancelled,
}) async {
  onProgress?.call(0, 'Opening document');

  // Decode the stamp first: its aspect drives the placement rect.
  // image-4.9 throws on some inputs (e.g. 0 bytes) rather than returning
  // null — normalize everything to a typed error.
  img.Image? decoded;
  try {
    decoded = img.decodePng(args.stampBytes) ?? img.decodeImage(args.stampBytes);
  } catch (_) {
    throw UnsupportedFormat(
      fileName: 'signature',
      expected: 'a readable PNG/JPG stamp image',
    );
  }
  if (decoded == null) {
    throw UnsupportedFormat(
      fileName: 'signature',
      expected: 'a readable PNG/JPG stamp image',
    );
  }
  final stampSize = Size(decoded.width.toDouble(), decoded.height.toDouble());

  // Probe open: classifies encrypted vs corrupt before any work happens.
  final bytes = File(args.inputPath).readAsBytesSync();
  late final PdfDocument src;
  try {
    src = PdfDocument(inputBytes: bytes);
  } on ArgumentError catch (e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('password') || msg.contains('encrypt')) {
      throw PasswordRequired(fileName: _nameOf(args.inputPath));
    }
    throw CorruptedFile(fileName: _nameOf(args.inputPath));
  }

  try {
    final pageCount = src.pages.count;
    if (args.pageNumber < 1 || args.pageNumber > pageCount) {
      throw UnsupportedFormat(
        fileName: _nameOf(args.inputPath),
        expected: 'a page between 1 and $pageCount',
      );
    }

    final out = PdfDocument();
    try {
      for (var p = 0; p < pageCount; p++) {
        if (isCancelled?.call() ?? false) throw const JobCancelled();
        final srcPage = src.pages[p];
        final template = srcPage.createTemplate();
        final w = srcPage.size.width;
        final h = srcPage.size.height;

        final section = out.sections!.add();
        // Wide pages: landscape-first so (w,h) is kept verbatim (F3 lesson).
        if (w > h) {
          section.pageSettings.orientation = PdfPageOrientation.landscape;
        }
        section.pageSettings.size = Size(w, h);
        final page = section.pages.add();
        page.graphics.drawPdfTemplate(template, Offset.zero, Size(w, h));

        if (p == args.pageNumber - 1) {
          onProgress?.call(0.4 + 0.3 * p / pageCount, 'Placing stamp');
          final rect = stampRect(
            pageSize: Size(w, h),
            stampSize: stampSize,
            anchor: args.anchor,
            marginPt: args.marginPt,
            scalePercent: args.scalePercent,
          );
          page.graphics.drawImage(PdfBitmap(args.stampBytes), rect);
        }
      }

      onProgress?.call(0.85, 'Saving');
      final outBytes = Uint8List.fromList(out.saveSync());
      final stem = _stemOf(args.inputPath);
      final target = uniqueDestination(args.outputDir, '$stem signed.pdf');
      File(target).writeAsBytesSync(outBytes, flush: true);

      onProgress?.call(1, null);
      return StampResult(
        outputPath: target,
        outputBytes: outBytes.length,
        pageCount: pageCount,
      );
    } finally {
      out.dispose();
    }
  } finally {
    src.dispose();
  }
}

String _stemOf(String path) {
  final name = _nameOf(path);
  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name;
  return stem.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_');
}

String _nameOf(String path) => path.split(Platform.pathSeparator).last;
