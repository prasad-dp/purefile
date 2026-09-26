import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:purefile/core/scan/scan_processing.dart';
import 'package:purefile/core/scan/scan_service.dart';

/// A 300x200 image, white 240x160 rectangle at (30, 20) on a dark gray
/// background — a synthetic "document on a table".
img.Image _docOnTable() {
  final im = img.Image(width: 300, height: 200, numChannels: 3);
  img.fill(im, color: img.ColorRgb8(40, 40, 40));
  img.fillRect(im,
      x1: 30, y1: 20, x2: 269, y2: 179, color: img.ColorRgb8(230, 230, 230));
  return im;
}

/// A gray page with a black bar in the middle — for enhancement contrast.
img.Image _pageWithInk() {
  final im = img.Image(width: 200, height: 200, numChannels: 3);
  img.fill(im, color: img.ColorRgb8(140, 140, 140)); // shadowed paper
  img.fillRect(im,
      x1: 40, y1: 90, x2: 159, y2: 109, color: img.ColorRgb8(20, 20, 20));
  return im;
}

/// Point-in-convex-quad fill (image 4.9 has no fillQuad).
void _fillQuad(img.Image im, List<img.Point> q, img.ColorRgb8 color) {
  num cross(img.Point o, img.Point a, img.Point b) =>
      (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
  for (var y = 0; y < im.height; y++) {
    for (var x = 0; x < im.width; x++) {
      final p = img.Point(x, y);
      final signs = [
        cross(q[0], q[1], p),
        cross(q[1], q[2], p),
        cross(q[2], q[3], p),
        cross(q[3], q[0], p),
      ];
      final hasPos = signs.any((s) => s > 0);
      final hasNeg = signs.any((s) => s < 0);
      if (!(hasPos && hasNeg)) {
        im.setPixelRgba(x, y, color.r, color.g, color.b, 255);
      }
    }
  }
}

void main() {
  // ------------------------------------------------------------- detection

  test('detectDocumentQuad finds the page corners on a flat document', () {
    final quad = detectDocumentQuad(_docOnTable())!;
    // Rect fixture: extreme-point corners == rect corners.
    expect(quad.tl.x, 30);
    expect(quad.tl.y, 20);
    expect(quad.tr.x, 269);
    expect(quad.tr.y, 20);
    expect(quad.br.x, 269);
    expect(quad.br.y, 179);
    expect(quad.bl.x, 30);
    expect(quad.bl.y, 179);
  });

  test('detectDocumentQuad returns null on a blank/dark frame', () {
    final dark = img.Image(width: 120, height: 120, numChannels: 3);
    img.fill(dark, color: img.ColorRgb8(20, 20, 20));
    expect(detectDocumentQuad(dark), isNull);
  });

  test('detectDocumentQuad returns null when the page fills the frame', () {
    final allWhite = img.Image(width: 100, height: 100, numChannels: 3);
    img.fill(allWhite, color: img.ColorRgb8(240, 240, 240));
    expect(detectDocumentQuad(allWhite), isNull);
  });

  test('detectDocumentQuad ignores tiny specks (min area rule)', () {
    final im = img.Image(width: 300, height: 200, numChannels: 3);
    img.fill(im, color: img.ColorRgb8(40, 40, 40));
    img.fillRect(im,
        x1: 10, y1: 10, x2: 18, y2: 18, color: img.ColorRgb8(240, 240, 240));
    expect(detectDocumentQuad(im), isNull);
  });

  // ----------------------------------------------------------------- warp

  test('warpQuad maps an axis-aligned rect 1:1 (identity homography)', () {
    final src = _docOnTable();
    final out = warpQuad(
      src,
      const QuadCorners(
        QuadPoint(30, 20),
        QuadPoint(269, 20),
        QuadPoint(269, 179),
        QuadPoint(30, 179),
      ),
      240,
      160,
    );
    expect(out.width, 240);
    expect(out.height, 160);
    // Corners and center of the output are page-white.
    num lum(int x, int y) => out.getPixel(x, y).luminance;
    expect(lum(2, 2), greaterThan(200));
    expect(lum(237, 2), greaterThan(200));
    expect(lum(237, 157), greaterThan(200));
    expect(lum(2, 157), greaterThan(200));
    expect(lum(120, 80), greaterThan(200));
  });

  test('warpQuad corrects a perspective-skewed page', () {
    // Same 240x160 page drawn skewed: TL pulled inward like a tilted photo.
    final src = img.Image(width: 300, height: 200, numChannels: 3);
    img.fill(src, color: img.ColorRgb8(40, 40, 40));
    _fillQuad(src, [
      img.Point(60, 40),
      img.Point(280, 25),
      img.Point(270, 175),
      img.Point(45, 160),
    ], img.ColorRgb8(230, 230, 230));

    final out = warpQuad(
      src,
      const QuadCorners(
        QuadPoint(60, 40),
        QuadPoint(280, 25),
        QuadPoint(270, 175),
        QuadPoint(45, 160),
      ),
      240,
      160,
    );

    // After warping, the whole output is inside the (now upright) page.
    num lum(int x, int y) => out.getPixel(x, y).luminance;
    expect(lum(4, 4), greaterThan(190));
    expect(lum(235, 4), greaterThan(190));
    expect(lum(235, 155), greaterThan(190));
    expect(lum(4, 155), greaterThan(190));
  });

  test('warpQuad output size is clamped to sane bounds', () {
    final src = _docOnTable();
    final out = warpQuad(
      src,
      const QuadCorners(
        QuadPoint(30, 20),
        QuadPoint(269, 20),
        QuadPoint(269, 179),
        QuadPoint(30, 179),
      ),
      0,
      -5,
    );
    expect(out.width, 1);
    expect(out.height, 1);
  });

  // ------------------------------------------------------------- enhance

  test('enhanceDocument lifts shadowed paper toward white, keeps ink dark', () {
    final out = enhanceDocument(_pageWithInk());
    num lum(int x, int y) => out.getPixel(x, y).luminance;
    // Paper was 140 gray; background division + curve push it near white.
    expect(lum(20, 20), greaterThan(200));
    // Ink stays dark (bg division mixes a little ink into the estimate).
    expect(lum(100, 100), lessThan(120));
    // Output is grayscale (r == g == b).
    final p = out.getPixel(20, 20);
    expect(p.r, p.g);
    expect(p.g, p.b);
  });

  test('enhanceDocument on a tiny image just grayscales', () {
    final tiny = img.Image(width: 8, height: 8, numChannels: 3);
    img.fill(tiny, color: img.ColorRgb8(200, 180, 160));
    final out = enhanceDocument(tiny);
    expect(out.width, 8);
    final p = out.getPixel(4, 4);
    expect(p.r, p.g);
    expect(p.g, p.b);
  });

  // -------------------------------------------------------- processScanPage

  test('processScanPage crops, enhances and JPEG-encodes the page', () {
    final im = _docOnTable();
    final bytes = Uint8List.fromList(img.encodeJpg(im));

    final page = processScanPage(bytes);

    expect(page.bytes.first, 0xFF, reason: 'JPEG SOI');
    expect(page.bytes[1], 0xD8, reason: 'JPEG SOI');
    // The 240x160 page was cropped out of the 300x200 frame.
    expect(page.width, lessThan(300));
    expect(page.height, lessThan(200));
  });

  test('processScanPage keeps the full frame when nothing is detected', () {
    final dark = img.Image(width: 120, height: 90, numChannels: 3);
    img.fill(dark, color: img.ColorRgb8(30, 30, 30));
    final bytes = Uint8List.fromList(img.encodeJpg(dark));

    final page = processScanPage(bytes);
    expect(page.width, 120);
    expect(page.height, 90);
  });

  test('processScanPage respects maxSide downscale', () {
    final im = img.Image(width: 400, height: 300, numChannels: 3);
    img.fill(im, color: img.ColorRgb8(220, 220, 220));
    final bytes = Uint8List.fromList(img.encodeJpg(im));

    final page = processScanPage(bytes, autoCrop: false, maxSide: 100);
    expect(page.width, 100);
    expect(page.height, 75);
  });

  test('processScanPage throws on unreadable bytes', () {
    expect(() => processScanPage(Uint8List(0)),
        throwsA(isA<ScanPageException>()));
  });

  // ------------------------------------------------------------ ScanSession

  test('ScanSession pages land on disk in order and discard cleans up', () {
    final session = ScanSession('${Directory.systemTemp.path}/pf_scan_test');
    try {
      final p1 = session.addPage(Uint8List.fromList([1, 2, 3]));
      final p2 = session.addPage(Uint8List.fromList([4, 5, 6]));
      expect(session.pagePaths, [p1, p2]);
      expect(p1.endsWith('page_01.jpg'), isTrue);
      expect(p2.endsWith('page_02.jpg'), isTrue);
      expect(File(p1).readAsBytesSync(), [1, 2, 3]);

      session.removePage(p1);
      expect(session.pagePaths, [p2]);
      expect(File(p1).existsSync(), isFalse);
    } finally {
      session.discard();
    }
    expect(Directory('${Directory.systemTemp.path}/pf_scan_test').existsSync(),
        isFalse);
  });
}
