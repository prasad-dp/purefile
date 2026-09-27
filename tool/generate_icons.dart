// Generates every PureFile brand icon from one master mark (feature 17).
//
// Run from the project root:
//   dart run tool/generate_icons.dart
//
// Outputs:
//   assets/brand/icon_1024.png          — the master icon
//   assets/brand/icon_launcher.png      — the launcher-look composite
//       (adaptive background + foreground, circle-masked) so in-app surfaces
//       can show exactly what launchers render on the home screen
//   android/.../mipmap-*/ic_launcher.png        — legacy round-rect icons
//   android/.../mipmap-*/ic_launcher_foreground.png — adaptive foreground
//   android/.../mipmap-*/ic_launcher_background.png — adaptive background
//   ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png — all iOS sizes
//
// The mark: teal→sky vertical gradient round-rect, three white document bars,
// with the bottom bar pulled right (the "F" gesture) and a small sky spark.
import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;

const teal = 0xFF0F766E;
const sky = 0xFF0284C7;
const white = 0xFFFFFFFF;

void main() {
  final root = Directory.current.path;
  final master = _drawIcon(1024, platformPadding: false);
  final masterDir = Directory('$root/assets/brand')
    ..createSync(recursive: true);
  File('${masterDir.path}/icon_1024.png')
      .writeAsBytesSync(img.encodePng(master));
  stdout.writeln('assets/brand/icon_1024.png');

  // Adaptive foreground keeps the mark inside the inner 66% safe zone
  // (Android crops a variable circular mask out of 108/108dp).
  final fg = _drawMark(432, canvas: 1024);
  final bg = _drawAdaptiveBackground(1024);

  // In-app "launcher look": the adaptive composite (full-bleed gradient +
  // centered mark at adaptive scale) pre-masked to a circle — what most
  // launchers render on the home screen. Used by the settings About row so
  // the in-app logo matches the installed app icon. Drawn directly (no
  // compositeImage — fill/alpha semantics differ across image-pkg versions).
  final launcherLook = img.Image(width: 1024, height: 1024, numChannels: 4);
  _fillVerticalGradient(launcherLook, 1024, from: teal, to: sky);
  _drawMarkInto(launcherLook, area: 432, offset: (1024 - 432) ~/ 2);
  _maskToCircle(launcherLook);
  File('${masterDir.path}/icon_launcher.png')
      .writeAsBytesSync(img.encodePng(img.copyResize(launcherLook, width: 512)));
  stdout.writeln('assets/brand/icon_launcher.png');

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
    final dir = Directory(
        '$root/android/app/src/main/res/mipmap-${entry.key}')
      ..createSync(recursive: true);
    final legacy = _drawIcon(entry.value, platformPadding: true);
    File('${dir.path}/ic_launcher.png')
        .writeAsBytesSync(img.encodePng(legacy));
    if (entry.key == 'xxxhdpi') {
      // Adaptive layers are density-scalable from the largest set.
      for (final fgEntry in fgDensities.entries) {
        final fdir = Directory(
            '$root/android/app/src/main/res/mipmap-${fgEntry.key}')
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
  stdout.writeln('android mipmaps written');

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
  final iosDir = Directory(
      '$root/ios/Runner/Assets.xcassets/AppIcon.appiconset');
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

/// Full-square icon with rounded corners. [platformPadding] adds the ~10%
/// visual padding launchers expect on legacy icons.
img.Image _drawIcon(int size, {required bool platformPadding}) {
  final image = img.Image(width: size, height: size);
  img.fill(image, color: img.ColorUint8.rgba(0, 0, 0, 0));
  final pad = platformPadding ? (size * 0.05).round() : 0;
  final rect = size - 2 * pad;
  _fillRoundRect(image,
      x1: pad,
      y1: pad,
      x2: pad + rect - 1,
      y2: pad + rect - 1,
      radius: (rect * 0.22).round());
  final markPad = pad + (rect * 0.18).round();
  _drawMarkInto(image,
      area: size - 2 * markPad, offset: markPad);
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

/// Vertical teal→sky gradient fill (shared by the adaptive background and
/// the in-app launcher look).
void _fillVerticalGradient(img.Image image, int size,
    {required int from, required int to}) {
  for (var y = 0; y < size; y++) {
    final t = y / (size - 1);
    final c = _lerpColor(from, to, t);
    for (var x = 0; x < size; x++) {
      image.setPixel(x, y, c);
    }
  }
}

/// Adaptive background layer: full-bleed gradient (the mask crops it).
img.Image _drawAdaptiveBackground(int size) {
  final image = img.Image(width: size, height: size);
  _fillVerticalGradient(image, size, from: teal, to: sky);
  return image;
}

/// Just the document mark, centered on a transparent [canvas]² layer
/// (adaptive foreground).
img.Image _drawMark(int area, {required int canvas}) {
  final image = img.Image(width: canvas, height: canvas);
  img.fill(image, color: img.ColorUint8.rgba(0, 0, 0, 0));
  _drawMarkInto(image, area: area, offset: (canvas - area) ~/ 2);
  return image;
}

void _drawMarkInto(img.Image image, {required int area, required int offset}) {
  final white = img.ColorUint8.rgba(255, 255, 255, 255);
  final skyBar = img.ColorUint8.rgba(2, 132, 199, 255);

  // Three document bars; the bottom one shifted right (the "F" gesture).
  final barH = (area * 0.115).round();
  final barW = (area * 0.72).round();
  final gap = (area * 0.135).round();
  var y = offset + (area * 0.10).round();
  for (var i = 0; i < 3; i++) {
    final dx = i == 2 ? (area * 0.16).round() : 0;
    img.fillRect(image,
        x1: offset + dx,
        y1: y,
        x2: offset + dx + barW - 1,
        y2: y + barH - 1,
        color: i == 2 ? skyBar : white,
        radius: barH / 2,
        alphaBlend: true);
    y += barH + gap;
  }

  // Sky spark: circle at the top-right of the mark.
  img.fillCircle(image,
      x: offset + area - (area * 0.05).round(),
      y: offset + (area * 0.12).round(),
      radius: (area * 0.075).round(),
      color: white,
      antialias: true);
}

img.ColorUint8 _lerpColor(int a, int b, double t) {
  final ar = (a >> 16) & 0xFF, ag = (a >> 8) & 0xFF, ab = a & 0xFF;
  final br = (b >> 16) & 0xFF, bg = (b >> 8) & 0xFF, bb = b & 0xFF;
  return img.ColorUint8.rgb(
    ar + ((br - ar) * t).round(),
    ag + ((bg - ag) * t).round(),
    ab + ((bb - ab) * t).round(),
  );
}

/// Vertical teal→sky gradient inside a rounded rect (alpha outside).
void _fillRoundRect(img.Image image,
    {required int x1, required int y1, required int x2, required int y2,
    required int radius}) {
  for (var y = y1; y <= y2; y++) {
    final t = (y - y1) / max(1, y2 - y1);
    final c = _lerpColor(teal, sky, t);
    for (var x = x1; x <= x2; x++) {
      if (_inRoundRect(x, y, x1, y1, x2, y2, radius)) {
        image.setPixel(x, y, c);
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
