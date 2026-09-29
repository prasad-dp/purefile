// Generates every PureFile brand icon from one master mark (feature 17).
//
// Run from the project root:
//   dart run tool/generate_icons.dart
//
// Outputs:
//   assets/brand/icon_1024.png          — the master icon (squircle + rim + depth)
//   assets/brand/icon_launcher.png      — the launcher-look composite
//       (adaptive background + foreground, circle-masked) so in-app surfaces
//       can show exactly what launchers render on the home screen
//   app_logo.png                        — root preview asset
//   android/.../mipmap-*/ic_launcher.png        — legacy round-rect icons
//   android/.../mipmap-*/ic_launcher_round.png  — legacy circular icons
//   android/.../mipmap-*/ic_launcher_foreground.png — adaptive foreground
//   android/.../mipmap-*/ic_launcher_background.png — adaptive background
//   ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png — all iOS sizes
//
// The mark: deep emerald-teal→royal sapphire gradient with frosted rim light,
// three floating document bars with soft depth shadows, where the bottom
// bar is high-contrast Ice Cyan (#7DD3FC) pulled right (the "F" gesture),
// and a radiant diamond star sparkle at the top right.
import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;

const teal = 0xFF0D6E66;
const sapphire = 0xFF0369A1;
const white = 0xFFFFFFFF;
// High-contrast Ice Cyan (#7DD3FC) - distinct from sapphire background:
const iceCyan = 0xFF7DD3FC;

void main() {
  final root = Directory.current.path;
  final master = _drawIcon(1024, platformPadding: false);
  final masterDir = Directory('$root/assets/brand')..createSync(recursive: true);

  final masterBytes = img.encodePng(master);
  File('${masterDir.path}/icon_1024.png').writeAsBytesSync(masterBytes);
  File('$root/app_logo.png').writeAsBytesSync(masterBytes);
  stdout.writeln('assets/brand/icon_1024.png & app_logo.png written');

  // Adaptive foreground keeps the mark inside the inner 66% safe zone
  // (Android crops a variable circular mask out of 108/108dp).
  final fg = _drawMark(432, canvas: 1024);
  final bg = _drawAdaptiveBackground(1024);

  // In-app "launcher look": the adaptive composite (full-bleed gradient +
  // centered mark at adaptive scale) pre-masked to a circle — what most
  // launchers render on the home screen.
  final launcherLook = img.Image(width: 1024, height: 1024, numChannels: 4);
  _fillGradient(launcherLook, 1024, from: teal, to: sapphire);
  _drawMarkInto(launcherLook, area: 432, offset: (1024 - 432) ~/ 2);
  _maskToCircle(launcherLook);
  File('${masterDir.path}/icon_launcher.png')
      .writeAsBytesSync(img.encodePng(img.copyResize(launcherLook, width: 512)));
  stdout.writeln('assets/brand/icon_launcher.png written');

  // Android legacy + adaptive densities.
  const densities = {
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
  };
  const fgDensities = {
    'mdpi': 108,
    'hdpi': 162,
    'xhdpi': 216,
    'xxhdpi': 324,
    'xxxhdpi': 432,
  };
  for (final entry in densities.entries) {
    final dir = Directory('$root/android/app/src/main/res/mipmap-${entry.key}')
      ..createSync(recursive: true);
    final legacy = _drawIcon(entry.value, platformPadding: true);
    File('${dir.path}/ic_launcher.png')
        .writeAsBytesSync(img.encodePng(legacy));

    // Circular icon for devices with round launcher preference
    final roundIcon = _drawRoundIcon(entry.value);
    File('${dir.path}/ic_launcher_round.png')
        .writeAsBytesSync(img.encodePng(roundIcon));

    if (entry.key == 'xxxhdpi') {
      // Adaptive layers are density-scalable from the largest set.
      for (final fgEntry in fgDensities.entries) {
        final fdir = Directory('$root/android/app/src/main/res/mipmap-${fgEntry.key}')
          ..createSync(recursive: true);
        final scaled = img.copyResize(fg, width: fgEntry.value);
        File('${fdir.path}/ic_launcher_foreground.png')
            .writeAsBytesSync(img.encodePng(scaled));
        final bgScaled = img.copyResize(bg, width: fgEntry.value);
        File('${fdir.path}/ic_launcher_background.png')
            .writeAsBytesSync(img.encodePng(bgScaled));
      }
    }
  }
  stdout.writeln('android mipmaps written (legacy, round, adaptive)');

  // iOS: the AppIcon.appiconset sizes (name @scale).
  const iosSizes = {
    'Icon-App-1024x1024@1x': 1024,
    'Icon-App-20x20@1x': 20,
    'Icon-App-20x20@2x': 40,
    'Icon-App-20x20@3x': 60,
    'Icon-App-29x29@1x': 29,
    'Icon-App-29x29@2x': 58,
    'Icon-App-29x29@3x': 87,
    'Icon-App-40x40@1x': 40,
    'Icon-App-40x40@2x': 80,
    'Icon-App-40x40@3x': 120,
    'Icon-App-60x60@2x': 120,
    'Icon-App-60x60@3x': 180,
    'Icon-App-76x76@1x': 76,
    'Icon-App-76x76@2x': 152,
    'Icon-App-83.5x83.5@2x': 167,
  };
  final iosDir = Directory('$root/ios/Runner/Assets.xcassets/AppIcon.appiconset');
  if (iosDir.existsSync()) {
    for (final entry in iosSizes.entries) {
      final scaled = img.copyResize(master, width: entry.value);
      File('${iosDir.path}/${entry.key}.png')
          .writeAsBytesSync(img.encodePng(scaled));
    }
    stdout.writeln('iOS appiconset written');
  } else {
    stdout.writeln('iOS appiconset not found — skipped (Android-only build)');
  }
}

/// Full-square icon with rounded corners, frosted rim, and floating mark.
img.Image _drawIcon(int size, {required bool platformPadding}) {
  final image = img.Image(width: size, height: size, numChannels: 4);
  img.fill(image, color: img.ColorUint8.rgba(0, 0, 0, 0));
  final pad = platformPadding ? (size * 0.05).round() : 0;
  final rect = size - 2 * pad;
  _fillRoundRectWithRim(image,
      x1: pad,
      y1: pad,
      x2: pad + rect - 1,
      y2: pad + rect - 1,
      radius: (rect * 0.225).round(),
      from: teal,
      to: sapphire);

  final markPad = pad + (rect * 0.19).round();
  _drawMarkInto(image,
      area: size - 2 * markPad, offset: markPad);
  return image;
}

/// Circular legacy icon for round-launcher configurations.
img.Image _drawRoundIcon(int size) {
  final image = img.Image(width: size, height: size, numChannels: 4);
  img.fill(image, color: img.ColorUint8.rgba(0, 0, 0, 0));
  _fillGradient(image, size, from: teal, to: sapphire);
  final markArea = (size * 0.55).round();
  _drawMarkInto(image, area: markArea, offset: (size - markArea) ~/ 2);
  _maskToCircle(image);
  return image;
}

/// Zeroes alpha outside the centered circle (launcher-style mask).
void _maskToCircle(img.Image image) {
  final size = image.width;
  final r = size / 2;
  final transparent = img.ColorUint8.rgba(0, 0, 0, 0);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final dx = x - r + 0.5;
      final dy = y - r + 0.5;
      if (dx * dx + dy * dy > r * r) {
        image.setPixel(x, y, transparent);
      }
    }
  }
}

/// Diagonal teal→sapphire gradient fill.
void _fillGradient(img.Image image, int size,
    {required int from, required int to}) {
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final t = (y * 0.75 + x * 0.25) / (size - 1);
      final c = _lerpColor(from, to, t.clamp(0.0, 1.0));
      image.setPixel(x, y, c);
    }
  }
}

/// Adaptive background layer: full-bleed gradient with full opacity.
img.Image _drawAdaptiveBackground(int size) {
  final image = img.Image(width: size, height: size, numChannels: 4);
  _fillGradient(image, size, from: teal, to: sapphire);
  return image;
}

/// Just the document mark, centered on a transparent [canvas]² layer
/// (adaptive foreground).
img.Image _drawMark(int area, {required int canvas}) {
  final image = img.Image(width: canvas, height: canvas, numChannels: 4);
  img.fill(image, color: img.ColorUint8.rgba(0, 0, 0, 0));
  _drawMarkInto(image, area: area, offset: (canvas - area) ~/ 2);
  return image;
}

void _drawMarkInto(img.Image image, {required int area, required int offset}) {
  final whiteColor = img.ColorUint8.rgba(255, 255, 255, 255);
  // Ice Cyan (#7DD3FC) - radiant and highly visible on sapphire
  final cyanColor = img.ColorUint8.rgba(125, 211, 252, 255);

  final barH = (area * 0.115).round();
  final barW = (area * 0.72).round();
  final gap = (area * 0.135).round();
  var y = offset + (area * 0.11).round();

  // Shadow params
  final shadow1 = img.ColorUint8.rgba(0, 25, 45, 65);
  final shadow2 = img.ColorUint8.rgba(0, 25, 45, 35);
  final int shadowDy1 = max(1, (area * 0.010).round()).toInt();
  final int shadowDy2 = max(2, (area * 0.018).round()).toInt();

  for (var i = 0; i < 3; i++) {
    final dx = i == 2 ? (area * 0.16).round() : 0;
    final color = i == 2 ? cyanColor : whiteColor;
    final bx1 = offset + dx;
    final by1 = y;
    final bx2 = offset + dx + barW - 1;
    final by2 = y + barH - 1;
    final r = barH / 2;

    // Dual-layer soft ambient drop shadow
    img.fillRect(image,
        x1: bx1, y1: by1 + shadowDy2, x2: bx2, y2: by2 + shadowDy2,
        color: shadow2, radius: r, alphaBlend: true);
    img.fillRect(image,
        x1: bx1, y1: by1 + shadowDy1, x2: bx2, y2: by2 + shadowDy1,
        color: shadow1, radius: r, alphaBlend: true);

    // Main crisp capsule bar
    img.fillRect(image,
        x1: bx1, y1: by1, x2: bx2, y2: by2,
        color: color, radius: r, alphaBlend: true);

    y += barH + gap;
  }

  // Radiant diamond sparkle star at top right (precision & intelligence)
  final sparkRadius = (area * 0.085).round();
  final sparkX = offset + area - (area * 0.04).round();
  final sparkY = offset + (area * 0.13).round();
  _drawSparkle(image,
      cx: sparkX,
      cy: sparkY,
      radius: sparkRadius,
      color: whiteColor);
}

void _drawSparkle(img.Image image,
    {required int cx, required int cy, required int radius, required img.ColorUint8 color}) {
  final glow = img.ColorUint8.rgba(color.r.toInt(), color.g.toInt(), color.b.toInt(), 55);
  final int outerR = radius + max(1, (radius * 0.35).round()).toInt();

  // Ambient soft glow
  for (var dy = -outerR; dy <= outerR; dy++) {
    for (var dx = -outerR; dx <= outerR; dx++) {
      final nx = dx.abs() / outerR;
      final ny = dy.abs() / outerR;
      if (pow(nx, 0.7) + pow(ny, 0.7) <= 1.0) {
        final int x = cx + dx;
        final int y = cy + dy;
        if (x >= 0 && x < image.width && y >= 0 && y < image.height) {
          image.setPixel(x, y, glow);
        }
      }
    }
  }

  // Diamond core
  for (var dy = -radius; dy <= radius; dy++) {
    for (var dx = -radius; dx <= radius; dx++) {
      final nx = dx.abs() / radius;
      final ny = dy.abs() / radius;
      if (pow(nx, 0.75) + pow(ny, 0.75) <= 1.0) {
        final x = cx + dx;
        final y = cy + dy;
        if (x >= 0 && x < image.width && y >= 0 && y < image.height) {
          image.setPixel(x, y, color);
        }
      }
    }
  }
}

img.ColorUint8 _lerpColor(int a, int b, double t) {
  final ar = (a >> 16) & 0xFF, ag = (a >> 8) & 0xFF, ab = a & 0xFF;
  final br = (b >> 16) & 0xFF, bg = (b >> 8) & 0xFF, bb = b & 0xFF;
  return img.ColorUint8.rgba(
    ar + ((br - ar) * t).round(),
    ag + ((bg - ag) * t).round(),
    ab + ((bb - ab) * t).round(),
    255,
  );
}

/// Rich gradient inside rounded rect with subtle frosted rim light.
void _fillRoundRectWithRim(img.Image image,
    {required int x1, required int y1, required int x2, required int y2,
    required int radius, required int from, required int to}) {
  final h = max(1, y2 - y1);
  for (var y = y1; y <= y2; y++) {
    for (var x = x1; x <= x2; x++) {
      if (_inRoundRect(x, y, x1, y1, x2, y2, radius)) {
        final t = ((y - y1) * 0.75 + (x - x1) * 0.25) / max(1, h);
        final c = _lerpColor(from, to, t.clamp(0.0, 1.0));
        image.setPixel(x, y, c);
      }
    }
  }

  // Frosted rim bezel light on the squircle perimeter
  final rimColor = img.ColorUint8.rgba(255, 255, 255, 45);
  final int innerR = max(1, radius - 2).toInt();
  for (var y = y1; y <= y2; y++) {
    for (var x = x1; x <= x2; x++) {
      if (_inRoundRect(x, y, x1, y1, x2, y2, radius) &&
          !_inRoundRect(x, y, x1 + 2, y1 + 2, x2 - 2, y2 - 2, innerR)) {
        image.setPixel(x, y, rimColor);
      }
    }
  }
}

bool _inRoundRect(int x, int y, int x1, int y1, int x2, int y2, int r) {
  if (x < x1 || x > x2 || y < y1 || y > y2) return false;
  final cx = x < x1 + r
      ? x1 + r
      : x > x2 - r
          ? x2 - r
          : x;
  final cy = y < y1 + r
      ? y1 + r
      : y > y2 - r
          ? y2 - r
          : y;
  final dx = x - cx;
  final dy = y - cy;
  if (x >= x1 + r && x <= x2 - r) return true;
  if (y >= y1 + r && y <= y2 - r) return true;
  return dx * dx + dy * dy <= r * r;
}
