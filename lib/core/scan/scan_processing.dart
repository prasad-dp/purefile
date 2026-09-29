import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Pure-Dart document-scan processing core (feature 11). Everything here is
/// unit-testable without a device: quad detection, perspective warp, and the
/// shadow-clean enhancement. The camera is just a capture front-end.

/// A corner in pixel coordinates.
class QuadPoint {
  const QuadPoint(this.x, this.y);
  final double x;
  final double y;
}

/// The four corners of a detected document, ordered TL, TR, BR, BL.
class QuadCorners {
  const QuadCorners(this.tl, this.tr, this.br, this.bl);
  final QuadPoint tl;
  final QuadPoint tr;
  final QuadPoint br;
  final QuadPoint bl;
}

/// Finds the bounding box of the largest bright connected component and
/// returns its extreme-point corners, or null when nothing convincing is
/// found (blank frame, dark table, or the document fills the whole frame).
QuadCorners? detectDocumentQuad(
  img.Image image, {
  int? threshold,
  int minAreaFraction = 4,
}) {
  final w = image.width;
  final h = image.height;
  if (w < 16 || h < 16) return null;

  final effThreshold = threshold ?? _computeOtsuThreshold(image);

  // 1. Binarize by luminance: pages are bright against darker tables.
  final bright = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = image.getPixel(x, y);
      bright[y * w + x] = p.luminance >= effThreshold ? 1 : 0;
    }
  }

  // 2. Iterative flood fill to label components; keep the largest.
  final labels = Uint32List(w * h);
  var bestLabel = 0;
  var bestArea = 0;
  var nextLabel = 0;
  final stack = <int>[];
  final minArea = w * h ~/ minAreaFraction;
  for (var i = 0; i < bright.length; i++) {
    if (bright[i] == 0 || labels[i] != 0) continue;
    nextLabel++;
    var area = 0;
    stack.add(i);
    labels[i] = nextLabel;
    while (stack.isNotEmpty) {
      final idx = stack.removeLast();
      area++;
      final x = idx % w;
      final y = idx ~/ w;
      if (x + 1 < w && bright[idx + 1] == 1 && labels[idx + 1] == 0) {
        labels[idx + 1] = nextLabel;
        stack.add(idx + 1);
      }
      if (x > 0 && bright[idx - 1] == 1 && labels[idx - 1] == 0) {
        labels[idx - 1] = nextLabel;
        stack.add(idx - 1);
      }
      if (y + 1 < h && bright[idx + w] == 1 && labels[idx + w] == 0) {
        labels[idx + w] = nextLabel;
        stack.add(idx + w);
      }
      if (y > 0 && bright[idx - w] == 1 && labels[idx - w] == 0) {
        labels[idx - w] = nextLabel;
        stack.add(idx - w);
      }
    }
    if (area > bestArea) {
      bestArea = area;
      bestLabel = nextLabel;
    }
  }

  if (bestArea < minArea) return null;
  // A component covering ~the whole frame gives nothing to crop — the page
  // fills the view or the frame is uniformly bright.
  if (bestArea > w * h * 97 ~/ 100) return null;

  // 3. Bounding box + diagonal extreme points of the winning component.
  var minX = w, minY = h, maxX = -1, maxY = -1;
  var tlScore = 1 << 30, brScore = -(1 << 30);
  QuadPoint? tl, br;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (labels[y * w + x] != bestLabel) continue;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
      final s = x + y;
      if (s < tlScore) {
        tlScore = s;
        tl = QuadPoint(x.toDouble(), y.toDouble());
      }
      if (s > brScore) {
        brScore = s;
        br = QuadPoint(x.toDouble(), y.toDouble());
      }
    }
  }
  if (tl == null || br == null) return null;

  // 4. Anti-diagonal extremes inside the bounding box.
  var trScore = -(1 << 30), blScore = -(1 << 30);
  QuadPoint? tr, bl;
  for (var y = minY; y <= maxY; y++) {
    for (var x = minX; x <= maxX; x++) {
      if (labels[y * w + x] != bestLabel) continue;
      // TR maximizes (right and up), BL maximizes (left and down).
      final trS = x - y;
      final blS = y - x;
      if (trS > trScore) {
        trScore = trS;
        tr = QuadPoint(x.toDouble(), y.toDouble());
      }
      if (blS > blScore) {
        blScore = blS;
        bl = QuadPoint(x.toDouble(), y.toDouble());
      }
    }
  }

  return QuadCorners(tl, tr ?? tl, br, bl ?? tl);
}

/// Perspective-warp the quad region to a rectangle of [outWidth] x [outHeight]
/// pixels. Builds the homography from unit square to the quad, then maps every
/// output pixel back to the source (inverse map) with bilinear sampling.
img.Image warpQuad(
  img.Image src,
  QuadCorners corners,
  int outWidth,
  int outHeight,
) {
  final outW = outWidth.clamp(1, 8192);
  final outH = outHeight.clamp(1, 8192);
  final out = img.Image(width: outW, height: outH, numChannels: 3);

  final h = _homographyUnitSquareTo(
    corners.tl.x, corners.tl.y,
    corners.tr.x, corners.tr.y,
    corners.br.x, corners.br.y,
    corners.bl.x, corners.bl.y,
  );

  for (var y = 0; y < outH; y++) {
    for (var x = 0; x < outW; x++) {
      // Homography domain is the unit square — normalize output pixels.
      final u = (x + 0.5) / outW;
      final v = (y + 0.5) / outH;
      final p = _applyH(h, u, v);
      final c = _sampleBilinear(src, p.$1, p.$2);
      out.setPixelRgba(x, y, c.$1, c.$2, c.$3, 255);
    }
  }
  return out;
}

/// Adobe Scan style document enhancement: lifts shadows, removes vignetting
/// and lighting gradients, whitens paper to clean pure white, darkens text,
/// and preserves vibrant inks, stamps, logos, and signatures when [preserveColor]
/// is true, or renders high-contrast clean paper grayscale when false.
img.Image enhanceDocument(
  img.Image src, {
  int blockSize = 32,
  bool preserveColor = true,
}) {
  final w = src.width;
  final h = src.height;
  if (w < blockSize * 2 || h < blockSize * 2) {
    return img.grayscale(src);
  }

  // 1. Build smooth background illumination map from downsampled average.
  final bgSmall = img.copyResize(
    src,
    width: (w / blockSize).ceil(),
    height: (h / blockSize).ceil(),
    interpolation: img.Interpolation.average,
  );
  final bgFull = img.copyResize(
    bgSmall,
    width: w,
    height: h,
    interpolation: img.Interpolation.linear,
  );

  final out = img.Image(width: w, height: h, numChannels: 3);

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = src.getPixel(x, y);
      final bgPixel = bgFull.getPixel(x, y);

      // Local background brightness with slight boost for text-heavy areas.
      final bgLum = (bgPixel.luminance.toDouble() * 1.05 + 5.0).clamp(25.0, 255.0);
      final gain = 255.0 / bgLum;

      final rGain = (p.r * gain).clamp(0.0, 255.0);
      final gGain = (p.g * gain).clamp(0.0, 255.0);
      final bGain = (p.b * gain).clamp(0.0, 255.0);
      final lumNorm = 0.299 * rGain + 0.587 * gGain + 0.114 * bGain;

      double rOut, gOut, bOut;
      if (lumNorm >= 175.0) {
        // Smoothstep paper whitening
        final t = ((lumNorm - 175.0) / 80.0).clamp(0.0, 1.0);
        final s = t * t * (3.0 - 2.0 * t);
        if (preserveColor) {
          rOut = rGain * (1.0 - s) + 255.0 * s;
          gOut = gGain * (1.0 - s) + 255.0 * s;
          bOut = bGain * (1.0 - s) + 255.0 * s;
        } else {
          final v = lumNorm * (1.0 - s) + 255.0 * s;
          rOut = gOut = bOut = v;
        }
      } else if (lumNorm < 130.0) {
        // Ink and text deepening for clarity
        final dFactor = 0.82 + 0.18 * (lumNorm / 130.0);
        if (preserveColor) {
          rOut = rGain * dFactor;
          gOut = gGain * dFactor;
          bOut = bGain * dFactor;
        } else {
          final v = lumNorm * dFactor;
          rOut = gOut = bOut = v;
        }
      } else {
        if (preserveColor) {
          rOut = rGain;
          gOut = gGain;
          bOut = bGain;
        } else {
          rOut = gOut = bOut = lumNorm;
        }
      }

      out.setPixelRgba(
        x,
        y,
        rOut.round().clamp(0, 255),
        gOut.round().clamp(0, 255),
        bOut.round().clamp(0, 255),
        255,
      );
    }
  }

  return out;
}

/// Filter theme presets for scanned documents (Adobe Scan style).
enum ScanFilter {
  /// Adobe Scan Auto Color: shadow lifting, paper whitening, and text darkening
  /// while preserving rich original inks, stamps, logos, and signatures.
  enhanced,

  /// Preserves natural photo colors after perspective deskewing.
  original,

  /// Clean continuous-tone grayscale with paper whitening and shadow removal.
  grayscale,

  /// Crisp high-contrast black & white for printable text.
  monochrome,
}

/// High-contrast binary monochrome for sharp printed text.
img.Image applyMonochrome(img.Image src, {int threshold = 140}) {
  final gray = img.grayscale(src);
  final out = img.Image(width: gray.width, height: gray.height, numChannels: 3);
  for (var y = 0; y < gray.height; y++) {
    for (var x = 0; x < gray.width; x++) {
      final lum = gray.getPixel(x, y).luminance;
      final v = lum >= threshold ? 255 : 0;
      out.setPixelRgba(x, y, v, v, v, 255);
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Homography from unit square to arbitrary quad (projective mapping).
// ---------------------------------------------------------------------------

/// Solves the 8-parameter homography mapping (0,0),(1,0),(1,1),(0,1) to the
/// given corners. Returns [h0..h7] with h8 = 1.
List<double> _homographyUnitSquareTo(
  double x0, double y0, // TL
  double x1, double y1, // TR
  double x2, double y2, // BR
  double x3, double y3, // BL
) {
  final a = List<double>.filled(81, 0);
  final b = List<double>.filled(9, 0);
  void row(int r, double u, double v, double x, double y) {
    a[r * 9 + 0] = u;
    a[r * 9 + 1] = v;
    a[r * 9 + 2] = 1;
    a[r * 9 + 3] = 0;
    a[r * 9 + 4] = 0;
    a[r * 9 + 5] = 0;
    a[r * 9 + 6] = -u * x;
    a[r * 9 + 7] = -v * x;
    b[r] = x;
  }

  void row2(int r, double u, double v, double x, double y) {
    a[r * 9 + 0] = 0;
    a[r * 9 + 1] = 0;
    a[r * 9 + 2] = 0;
    a[r * 9 + 3] = u;
    a[r * 9 + 4] = v;
    a[r * 9 + 5] = 1;
    a[r * 9 + 6] = -u * y;
    a[r * 9 + 7] = -v * y;
    b[r] = y;
  }

  row(0, 0, 0, x0, y0);
  row2(1, 0, 0, x0, y0);
  row(2, 1, 0, x1, y1);
  row2(3, 1, 0, x1, y1);
  row(4, 1, 1, x2, y2);
  row2(5, 1, 1, x2, y2);
  row(6, 0, 1, x3, y3);
  row2(7, 0, 1, x3, y3);
  a[8 * 9 + 8] = 1; // h8 = 1 normalization row
  b[8] = 1;

  return _solveLinearSystem(a, b, 9);
}

/// Gaussian elimination with partial pivoting for a small dense system.
List<double> _solveLinearSystem(List<double> a, List<double> b, int n) {
  final m = List<double>.from(a);
  final rhs = List<double>.from(b);
  for (var col = 0; col < n; col++) {
    var pivot = col;
    for (var r = col + 1; r < n; r++) {
      if (m[r * n + col].abs() > m[pivot * n + col].abs()) pivot = r;
    }
    if (m[pivot * n + col].abs() < 1e-12) {
      throw const FormatException('degenerate homography');
    }
    if (pivot != col) {
      for (var c = 0; c < n; c++) {
        final t = m[col * n + c];
        m[col * n + c] = m[pivot * n + c];
        m[pivot * n + c] = t;
      }
      final t2 = rhs[col];
      rhs[col] = rhs[pivot];
      rhs[pivot] = t2;
    }
    final d = m[col * n + col];
    for (var r = col + 1; r < n; r++) {
      final f = m[r * n + col] / d;
      if (f == 0) continue;
      for (var c = col; c < n; c++) {
        m[r * n + c] -= f * m[col * n + c];
      }
      rhs[r] -= f * rhs[col];
    }
  }
  final x = List<double>.filled(n, 0);
  for (var r = n - 1; r >= 0; r--) {
    var sum = rhs[r];
    for (var c = r + 1; c < n; c++) {
      sum -= m[r * n + c] * x[c];
    }
    x[r] = sum / m[r * n + r];
  }
  return x;
}

(double, double) _applyH(List<double> h, double u, double v) {
  final denom = h[6] * u + h[7] * v + 1;
  return (
    (h[0] * u + h[1] * v + h[2]) / denom,
    (h[3] * u + h[4] * v + h[5]) / denom,
  );
}

(int, int, int) _sampleBilinear(img.Image src, double fx, double fy) {
  final x0 = fx.floor();
  final y0 = fy.floor();
  final tx = fx - x0;
  final ty = fy - y0;
  int ch(num px, num py, int channel) {
    final cx = px.round().clamp(0, src.width - 1);
    final cy = py.round().clamp(0, src.height - 1);
    final p = src.getPixel(cx, cy);
    return switch (channel) {
      0 => p.r.toInt(),
      1 => p.g.toInt(),
      _ => p.b.toInt(),
    };
  }

  int mix(int c00, int c10, int c01, int c11) =>
      ((c00 * (1 - tx) + c10 * tx) * (1 - ty) +
              (c01 * (1 - tx) + c11 * tx) * ty)
          .round()
          .clamp(0, 255);

  final r = mix(ch(x0, y0, 0), ch(x0 + 1, y0, 0), ch(x0, y0 + 1, 0),
      ch(x0 + 1, y0 + 1, 0));
  final g = mix(ch(x0, y0, 1), ch(x0 + 1, y0, 1), ch(x0, y0 + 1, 1),
      ch(x0 + 1, y0 + 1, 1));
  final b = mix(ch(x0, y0, 2), ch(x0 + 1, y0, 2), ch(x0, y0 + 1, 2),
      ch(x0 + 1, y0 + 1, 2));
  return (r, g, b);
}

/// Computes the optimal binarization threshold via Otsu's method on the
/// image's luminance histogram. Runs in sub-millisecond time.
int _computeOtsuThreshold(img.Image image) {
  final hist = List<int>.filled(256, 0);
  final total = image.width * image.height;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final lum = image.getPixel(x, y).luminance.toInt().clamp(0, 255);
      hist[lum]++;
    }
  }
  var sum = 0.0;
  for (var i = 0; i < 256; i++) {
    sum += i * hist[i];
  }
  var sumB = 0.0;
  var wB = 0;
  var maxVar = 0.0;
  var bestThreshold = 128;
  for (var t = 0; t < 256; t++) {
    wB += hist[t];
    if (wB == 0) continue;
    final wF = total - wB;
    if (wF == 0) break;
    sumB += t * hist[t];
    final mB = sumB / wB;
    final mF = (sum - sumB) / wF;
    final variance = wB.toDouble() * wF.toDouble() * (mB - mF) * (mB - mF);
    if (variance > maxVar) {
      maxVar = variance;
      bestThreshold = t;
    }
  }
  return bestThreshold.clamp(60, 200);
}

