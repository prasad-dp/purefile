import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;

import 'errors.dart';
import 'file_io.dart' show uniqueDestination, atomicWriteBytes;

/// Target formats for Convert Image.
enum ImageTarget { jpeg, png, webp }

final class ImageConvertItem {
  const ImageConvertItem({required this.path, required this.name});
  final String path;
  final String name;
}

final class ImageConvertArgs {
  const ImageConvertArgs({
    required this.items,
    required this.outputDir,
    required this.target,
    this.jpegQuality = 90,
  });

  final List<ImageConvertItem> items;
  final String outputDir;
  final ImageTarget target;

  /// Quality for JPEG targets only (90 ≈ visually lossless default).
  final int jpegQuality;
}

final class ImageConvertFileResult {
  const ImageConvertFileResult({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.target,
    required this.converted,
  });

  final String path;
  final String name;
  final int sizeBytes;

  /// The requested target format.
  final ImageTarget target;

  /// False when the file was already in the target format and was copied
  /// through byte-identical instead of uselessly re-encoded.
  final bool converted;
}

final class ImageConvertResult {
  const ImageConvertResult({
    required this.files,
    required this.zipPath,
    required this.zipBytes,
  });

  /// One entry per input (input order). [ImageConvertFileResult.converted]
  /// is false for copy-through files.
  final List<ImageConvertFileResult> files;

  /// Set when 2+ outputs were produced (edge #36).
  final String? zipPath;
  final int zipBytes;
}

/// Convert Image task — runs inside the job isolate.
///
/// Every image is decoded and its EXIF orientation baked, then re-encoded
/// into the target format. Files already in the target format are copied
/// through byte-identical (a same-format "conversion" is a no-op — the user
/// gets the identical file rather than a generation-loss copy). Conversions
/// to JPEG flatten transparency onto white first. One unreadable image is
/// skipped and reported; if none survive the job fails and no output is
/// written.
Future<ImageConvertResult> imageConvertTask(
  ImageConvertArgs args, {
  void Function(double fraction, String? label)? onProgress,
  bool Function()? isCancelled,
}) async {
  final results = <ImageConvertFileResult>[];
  final failed = <String>[];

  for (var i = 0; i < args.items.length; i++) {
    if (isCancelled?.call() ?? false) throw const JobCancelled();
    final item = args.items[i];
    onProgress?.call(i / args.items.length, 'Converting ${item.name}');

    try {
      results.add(await _convertOne(args, item));
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

  String? zipPath;
  var zipBytes = 0;
  if (results.length > 1) {
    onProgress?.call(0.95, 'Packing zip');
    final archive = Archive();
    for (final f in results) {
      archive.add(ArchiveFile(f.name, f.sizeBytes, File(f.path).readAsBytesSync()));
    }
    final zip = Uint8List.fromList(ZipEncoder().encode(archive));
    zipPath = uniqueDestination(args.outputDir, 'converted images.zip');
    await atomicWriteBytes(zipPath, zip);
    zipBytes = zip.length;
  }

  return ImageConvertResult(files: results, zipPath: zipPath, zipBytes: zipBytes);
}

Future<ImageConvertFileResult> _convertOne(
  ImageConvertArgs args,
  ImageConvertItem item,
) async {
  final sourceExt = _extensionOf(item.name);
  final targetExt = switch (args.target) {
    ImageTarget.jpeg => 'jpg',
    ImageTarget.png => 'png',
    ImageTarget.webp => 'webp',
  };

  // Same format → copy through byte-identical (no pointless re-encode).
  if (sourceExt == targetExt ||
      (sourceExt == 'jpeg' && targetExt == 'jpg') ||
      (sourceExt == 'jpg' && targetExt == 'jpeg')) {
    return _copyThrough(args, item, args.target);
  }

  final bytes = File(item.path).readAsBytesSync();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw CorruptedFile(fileName: item.name, detail: 'Unreadable image data');
  }

  var working = img.bakeOrientation(decoded);
  if (args.target == ImageTarget.jpeg) {
    // JPEG has no alpha — flatten onto white (edge #24).
    final flattened = img.Image(width: working.width, height: working.height);
    img.fill(flattened, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(flattened, working);
    working = flattened;
  }

  final Uint8List outBytes;
  switch (args.target) {
    case ImageTarget.jpeg:
      outBytes = Uint8List.fromList(img.encodeJpg(working, quality: args.jpegQuality));
    case ImageTarget.png:
      outBytes = Uint8List.fromList(img.encodePng(working));
    case ImageTarget.webp:
      outBytes = Uint8List.fromList(img.encodeWebP(working));
  }

  final stem = _stemOf(item.name);
  final outName = '$stem.$targetExt';
  final target = uniqueDestination(args.outputDir, outName);
  await atomicWriteBytes(target, outBytes);
  return ImageConvertFileResult(
    path: target,
    name: outName,
    sizeBytes: outBytes.length,
    target: args.target,
    converted: true,
  );
}

/// Copies the source file to the output name unchanged (same-format
/// requests — a same-format "conversion" is a no-op, and a byte-identical
/// copy is the honest answer).
Future<ImageConvertFileResult> _copyThrough(
  ImageConvertArgs args,
  ImageConvertItem item,
  ImageTarget? target,
) async {
  final bytes = File(item.path).readAsBytesSync();
  final stem = _stemOf(item.name);
  final ext = _extensionOf(item.name);
  final outName = '$stem.$ext';
  final outPath = uniqueDestination(args.outputDir, outName);
  await atomicWriteBytes(outPath, bytes);
  return ImageConvertFileResult(
    path: outPath,
    name: outName,
    sizeBytes: bytes.length,
    target: target ?? ImageTarget.png,
    converted: false,
  );
}

String _extensionOf(String name) {
  final dot = name.lastIndexOf('.');
  final ext = dot > 0 ? name.substring(dot + 1).toLowerCase() : 'jpg';
  return ext == 'jpeg' ? 'jpg' : ext;
}

String _stemOf(String name) {
  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name;
  return stem.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_');
}
