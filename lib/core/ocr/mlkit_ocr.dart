import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show PlatformException;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:pdfx/pdfx.dart' as pdfx;

import '../errors.dart';
import '../pdf/ocr_service.dart';

/// Device [PageRecognizer] backed by ML Kit with bundled models (no Play
/// Services model downloads — models ship inside the APK, see
/// android/app/build.gradle.kts). Latin/CJK/Devanagari.
PageRecognizer mlkitPageRecognizer({TextRecognitionScript script = TextRecognitionScript.latin}) {
  return (Uint8List pageImageBytes) async {
    // InputImage needs a path — stage the rendered PNG in a temp file.
    final tmp = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}pf_ocr_${DateTime.now().microsecondsSinceEpoch}.png');
    try {
      await tmp.writeAsBytes(pageImageBytes, flush: true);
      final inputImage = InputImage.fromFilePath(tmp.path);
      final recognizer = TextRecognizer(script: script);
      try {
        final result = await recognizer.processImage(inputImage);
        return [
          for (final block in result.blocks)
            for (final line in block.lines)
              if (line.text.trim().isNotEmpty)
                OcrElement(
                  text: line.text.trim(),
                  box: line.boundingBox,
                ),
        ];
      } finally {
        await recognizer.close();
      }
    } on PlatformException {
      // No Play Services / recognizer failed to construct.
      throw const OcrUnavailable();
    } finally {
      if (tmp.existsSync()) tmp.deleteSync();
    }
  };
}

/// Device [PageRaster]: pdfx render at 200 DPI-equivalent scale (the same
/// density the invisible text layer mapping assumes).
Future<(double, double, Uint8List)> ocrPageRaster(
  String inputPath,
  int pageNumber,
) async {
  final doc =
      await pdfx.PdfDocument.openData(File(inputPath).readAsBytesSync());
  try {
    final page = await doc.getPage(pageNumber);
    try {
      final scale = 200 / 72;
      final wPx = (page.width * scale).round().clamp(1, 4096);
      final hPx = (page.height * scale).round().clamp(1, 4096);
      final image = await page.render(
        width: wPx.toDouble(),
        height: hPx.toDouble(),
        format: pdfx.PdfPageImageFormat.png,
        quality: 90,
        backgroundColor: '#FFFFFF',
      );
      if (image == null || image.bytes.isEmpty) {
        throw CorruptedFile(fileName: _nameOf(inputPath), detail: 'Page render failed');
      }
      return (page.width, page.height, Uint8List.fromList(image.bytes));
    } finally {
      await page.close();
    }
  } finally {
    await doc.close();
  }
}

String _nameOf(String path) => path.split(Platform.pathSeparator).last;
