import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;

import 'errors.dart';
import 'file_io.dart' show uniqueDestination, atomicWriteBytes;

/// Output quality presets (JPEG quality; PNG/WebP use lossless re-encode).
enum ImageQuality { low, medium, high }

int jpegQualityOf(ImageQuality q) => switch (q) {
      ImageQuality.low => 60,
      ImageQuality.medium => 75,
      ImageQuality.high => 88,
    };

final class ImageCompressItem {
  const ImageCompressItem({required this.path, required this.name});
  final String path;
  final String name;
}

final class ImageCompressArgs {
  const ImageCompressArgs({
    required this.items,
    required this.outputDir,
    required this.quality,
    this.maxSide,
  });

  final List<ImageCompressItem> items;
  final String outputDir;
  final ImageQuality quality;

  /// When set, images larger than this on their longest side are scaled down
  /// (aspect preserved). Null = keep original dimensions. Opt-in.
  final int? maxSide;
}

final class ImageCompressFileResult {
  const ImageCompressFileResult({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.originalBytes,
    required this.keptOriginal,
  });

  final String path;
  final String name;
  final int sizeBytes;
  final int originalBytes;

  /// True when the re-encode was not smaller — the original file is copied
  /// to the output name instead (never worse than input, per file).
  final bool keptOriginal;
}

final class ImageCompressResult {
  const ImageCompressResult({
    required this.files,
    required this.zipPath,
    required this.zipBytes,
  });

  /// One entry per input (in input order), including kept-original ones.
  final List<ImageCompressFileResult> files;

  /// Set when 2+ outputs were produced: a zip of all results for one-tap
  /// sharing (edge #36). Null for single-file results.
  final String? zipPath;
  final int zipBytes;

  int get savedPercent {
    final before = files.fold<int>(0, (s, f) => s + f.originalBytes);
    final after = files.fold<int>(0, (s, f) => s + f.sizeBytes);
    if (before == 0) return 0;
    final saved = ((before - after) / before * 100).round();
    return saved > 0 ? saved : 0;
  }
}

/// Compress Images task — runs inside the job isolate.
///
/// Every image is decoded, its EXIF orientation baked, optionally scaled
/// down, and re-encoded in its own format (JPEG at the preset quality, PNG
/// at best zlib effort, WebP lossless). A re-encode that isn't smaller than
/// the source writes a copy of the original instead and is reported as
/// kept-original. One unreadable image is skipped and reported; if none
/// survive the job fails with a typed error and no output.
Future<ImageCompressResult> imageCompressTask(
  ImageCompressArgs args, {
  void Function(double fraction, String? label)? onProgress,
  bool Function()? isCancelled,
}) async {
  final results = <ImageCompressFileResult>[];
  final failed = <String>[];

  for (var i = 0; i < args.items.length; i++) {
    if (isCancelled?.call() ?? false) throw const JobCancelled();
    final item = args.items[i];
    onProgress?.call(i / args.items.length, 'Compressing ${item.name}');

    try {
      results.add(await _compressOne(args, item));
    } on PureError catch (e) {
      if (e is JobCancelled) rethrow;
      failed.add(item.name);
    } on Object {
      failed.add(item.name);
    }
  }

  if (results.isEmpty) {
    throw CorruptedFile(
      fileName: args.items.first.name,
      detail: 'No image could be read',
    );
  }

  // Multi-output → one zip for sharing; individual files stay on disk too.
  String? zipPath;
  var zipBytes = 0;
  if (results.length > 1) {
    onProgress?.call(0.95, 'Packing zip');
    final archive = Archive();
    for (final f in results) {
      archive.add(ArchiveFile(f.name, f.sizeBytes, File(f.path).readAsBytesSync()));
    }
    final zip = Uint8List.fromList(ZipEncoder().encode(archive));
    zipPath = uniqueDestination(args.outputDir, 'compressed images.zip');
    await atomicWriteBytes(zipPath, zip);
    zipBytes = zip.length;
  }

  return ImageCompressResult(files: results, zipPath: zipPath, zipBytes: zipBytes);
}

Future<ImageCompressFileResult> _compressOne(
  ImageCompressArgs args,
  ImageCompressItem item,
) async {
  final originalBytes = File(item.path).lengthSync();
  final bytes = File(item.path).readAsBytesSync();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw CorruptedFile(fileName: item.name, detail: 'Unreadable image data');
  }

  var working = img.bakeOrientation(decoded);
  if (args.maxSide != null) {
    final longest = working.width > working.height ? working.width : working.height;
    if (longest > args.maxSide!) {
      final scale = args.maxSide! / longest;
      working = img.copyResize(
        working,
        width: (working.width * scale).round(),
        height: (working.height * scale).round(),
        interpolation: img.Interpolation.average,
      );
    }
  }

  final outBytes = _encode(working, item.name, jpegQualityOf(args.quality));
  final stem = _stemOf(item.name);
  final ext = _extensionOf(item.name);
  final outName = '${stem}_compressed.$ext';

  // Never worse than input: an equal-or-bigger output keeps the original.
  final Uint8List finalBytes;
  var kept = false;
  if (outBytes.length < originalBytes) {
    finalBytes = outBytes;
  } else {
    finalBytes = bytes;
    kept = true;
  }

  final target = uniqueDestination(args.outputDir, outName);
  await atomicWriteBytes(target, finalBytes);
  return ImageCompressFileResult(
    path: target,
    name: outName,
    sizeBytes: finalBytes.length,
    originalBytes: originalBytes,
    keptOriginal: kept,
  );
}

Uint8List _encode(img.Image image, String name, int quality) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
    return Uint8List.fromList(img.encodeJpg(image, quality: quality));
  }
  if (lower.endsWith('.webp')) {
    return Uint8List.fromList(img.encodeWebP(image));
  }
  return Uint8List.fromList(img.encodePng(image, level: 9));
}

String _extensionOf(String name) {
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(dot + 1).toLowerCase() : 'jpg';
}

String _stemOf(String name) {
  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name;
  return stem.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_');
}
