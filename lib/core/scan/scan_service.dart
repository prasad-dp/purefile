import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'scan_processing.dart';

/// One processed scan page: encoded JPEG bytes + pixel dimensions.
final class ScanPage {
  const ScanPage({required this.bytes, required this.width, required this.height});
  final Uint8List bytes;
  final int width;
  final int height;
}

/// Processes one captured/imported photo into a scanner-style page:
/// 1. decode + EXIF orientation bake (phone photos render sideways otherwise)
/// 2. downscale so the longest side is [maxSide] (memory + speed bound)
/// 3. best-effort auto-crop: detect the document quad and perspective-warp it
///    to a rectangle; when detection is not confident the full frame is kept
/// 4. shadow-clean enhancement (paper → white, ink → dark)
/// 5. JPEG encode at [quality]
///
/// Pure CPU — safe to run inside `Isolate.run` from the capture UI.
ScanPage processScanPage(
  Uint8List bytes, {
  bool autoCrop = true,
  int maxSide = 2200,
  int quality = 90,
}) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    // image-4.9 throws RangeError/FormatException on some malformed inputs
    // (e.g. 0-byte files) instead of returning null — normalize to our error.
    throw const ScanPageException('not a readable image');
  }
  if (decoded == null) {
    throw const ScanPageException('not a readable image');
  }
  img.Image image = img.bakeOrientation(decoded);

  final longest = image.width > image.height ? image.width : image.height;
  if (longest > maxSide) {
    final scale = maxSide / longest;
    image = img.copyResize(
      image,
      width: (image.width * scale).round(),
      height: (image.height * scale).round(),
      interpolation: img.Interpolation.average,
    );
  }

  if (autoCrop) {
    try {
      final quad = detectDocumentQuad(image);
      if (quad != null) {
        final w = _edgeLength(quad.tl, quad.tr);
        final h = _edgeLength(quad.tr, quad.br);
        // Guard against degenerate detections (thin slivers, single points).
        if (w >= 24 && h >= 24) {
          image = warpQuad(image, quad, w.round(), h.round());
        }
      }
    } on FormatException {
      // Degenerate homography — keep the uncropped frame.
    }
  }

  image = enhanceDocument(image);

  final jpeg = img.encodeJpg(image, quality: quality);
  return ScanPage(
    bytes: Uint8List.fromList(jpeg),
    width: image.width,
    height: image.height,
  );
}

double _edgeLength(QuadPoint a, QuadPoint b) {
  final dx = a.x - b.x;
  final dy = a.y - b.y;
  return math.sqrt(dx * dx + dy * dy);
}

/// Thrown for unreadable page images (typed at the UI layer).
class ScanPageException implements Exception {
  const ScanPageException(this.message);
  final String message;
  @override
  String toString() => 'ScanPageException: $message';
}

/// A capture session: processed pages accumulate as JPEG files in a temp dir
/// until the user presses Done (paths flow into the Images→PDF pipeline).
class ScanSession {
  ScanSession(this.dir) {
    Directory(dir).createSync(recursive: true);
  }

  final String dir;
  final List<String> pagePaths = [];

  /// Saves page bytes as `page_NN.jpg` (1-based, stable ordering) and returns
  /// the path. Existing pages are never overwritten.
  String addPage(Uint8List jpegBytes) {
    final n = pagePaths.length + 1;
    final path =
        '$dir${Platform.pathSeparator}page_${n.toString().padLeft(2, '0')}.jpg';
    File(path).writeAsBytesSync(jpegBytes, flush: true);
    pagePaths.add(path);
    return path;
  }

  /// Removes a page from disk and the ordered list.
  void removePage(String path) {
    final f = File(path);
    if (f.existsSync()) f.deleteSync();
    pagePaths.remove(path);
  }

  void discard() {
    final d = Directory(dir);
    if (d.existsSync()) d.deleteSync(recursive: true);
    pagePaths.clear();
  }
}
