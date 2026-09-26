import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'errors.dart';

const String kPfTempSuffix = '.pf-tmp';

/// Returns a destination path that never overwrites an existing file:
/// `report.pdf` → `report (2).pdf` → `report (3).pdf` … (edge case #33).
String uniqueDestination(String directory, String fileName) {
  final dot = fileName.lastIndexOf('.');
  final stem = dot > 0 ? fileName.substring(0, dot) : fileName;
  final ext = dot > 0 ? fileName.substring(dot) : '';
  var candidate = '$directory${Platform.pathSeparator}$fileName';
  var n = 2;
  // Also treat directories as taken: a folder named `report.pdf` must not
  // collide with the output file (extract tests caught this).
  while (File(candidate).existsSync() || Directory(candidate).existsSync()) {
    candidate = '$directory${Platform.pathSeparator}$stem ($n)$ext';
    n++;
  }
  return candidate;
}

/// Atomic write: bytes go to a temp file in the same directory, then rename.
/// A kill mid-write never leaves a corrupt "result" (reliability rules).
Future<void> atomicWriteBytes(String targetPath, Uint8List bytes) async {
  final tempPath = '$targetPath$kPfTempSuffix';
  final temp = File(tempPath);
  try {
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(targetPath);
  } on FileSystemException {
    if (temp.existsSync()) temp.deleteSync();
    rethrow;
  }
}

/// Streaming atomic copy for large files — constant memory, reports progress.
/// Returns bytes written. Handles are closed BEFORE the rename (required on
/// Windows, which refuses to rename/move an open file).
Future<int> atomicCopyFile(
  String sourcePath,
  String targetPath, {
  void Function(double fraction)? onProgress,
  bool Function()? isCancelled,
}) async {
  final source = File(sourcePath);
  final total = source.lengthSync();
  final temp = File('$targetPath$kPfTempSuffix');
  final input = source.openSync();
  final output = temp.openSync(mode: FileMode.write);
  var written = 0;
  var ok = false;
  try {
    const chunkSize = 512 * 1024;
    final buffer = Uint8List(chunkSize);
    while (written < total) {
      if (isCancelled?.call() ?? false) throw const JobCancelled();
      final toRead = min(chunkSize, total - written);
      input.readIntoSync(buffer, 0, toRead);
      output.writeFromSync(buffer, 0, toRead);
      written += toRead;
      onProgress?.call(written / total);
    }
    await output.flush();
    ok = true;
  } finally {
    input.closeSync();
    output.closeSync();
    if (!ok && temp.existsSync()) {
      try {
        temp.deleteSync();
      } catch (_) {
        // Best effort — never mask the original failure.
      }
    }
  }
  try {
    await temp.rename(targetPath);
  } catch (_) {
    if (temp.existsSync()) {
      try {
        temp.deleteSync();
      } catch (_) {}
    }
    rethrow;
  }
  return written;
}

/// Deletes leftover temp files in a directory (app-start orphan sweep).
void cleanupTempFiles(String directory) {
  final dir = Directory(directory);
  if (!dir.existsSync()) return;
  for (final entity in dir.listSync()) {
    if (entity is File && entity.path.endsWith(kPfTempSuffix)) {
      try {
        entity.deleteSync();
      } catch (_) {
        // Best effort — never fail startup over cleanup.
      }
    }
  }
}

/// Overwrites the file bytes with random data before unlinking (vault).
Future<void> secureDelete(String path, {int passes = 3}) async {
  final file = File(path);
  if (!file.existsSync()) return;
  final length = file.lengthSync();
  final raf = file.openSync(mode: FileMode.write);
  try {
    final random = Random.secure();
    final buffer = Uint8List(64 * 1024);
    for (var p = 0; p < passes; p++) {
      var written = 0;
      while (written < length) {
        final toWrite = min(buffer.length, length - written);
        for (var i = 0; i < toWrite; i++) {
          buffer[i] = random.nextInt(256);
        }
        raf.setPositionSync(written);
        raf.writeFromSync(buffer, 0, toWrite);
        written += toWrite;
      }
      await raf.flush();
    }
  } finally {
    raf.closeSync();
  }
  file.deleteSync();
}
