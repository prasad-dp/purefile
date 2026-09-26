import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'errors.dart';
import 'file_io.dart' show uniqueDestination, atomicWriteBytes;

/// Zip-bomb guard (edge #22): an archive may declare at most this multiple of
/// its own compressed size as uncompressed content, bounded below (small
/// archives get a floor) and above (absolute cap).
const int _bombRatio = 20;
const int _bombFloorBytes = 100 * 1024 * 1024;
const int _bombCeilingBytes = 1024 * 1024 * 1024;

int _allowedUncompressedBytes(int archiveBytes) =>
    (archiveBytes * _bombRatio).clamp(_bombFloorBytes, _bombCeilingBytes);

// ---------------------------------------------------------------------------
// Create
// ---------------------------------------------------------------------------

final class ZipCreateItem {
  const ZipCreateItem({required this.path, required this.name});
  final String path;
  final String name;
}

final class ZipCreateArgs {
  const ZipCreateArgs({required this.items, required this.outputDir});
  final List<ZipCreateItem> items;
  final String outputDir;
}

final class ZipCreateResult {
  const ZipCreateResult({
    required this.zipPath,
    required this.zipBytes,
    required this.fileCount,
    required this.failedNames,
  });

  final String zipPath;
  final int zipBytes;
  final int fileCount;

  /// Inputs that vanished between pick and run (rare) — skipped and reported.
  final List<String> failedNames;
}

/// ZIP create task — runs inside the job isolate. Any file type is welcome.
/// Duplicate names are deduplicated as `name (1).ext`, `name (2).ext`, …
Future<ZipCreateResult> zipCreateTask(
  ZipCreateArgs args, {
  void Function(double fraction, String? label)? onProgress,
  bool Function()? isCancelled,
}) async {
  if (args.items.isEmpty) {
    throw const UnsupportedFormat(fileName: 'Nothing selected', expected: 'at least one file');
  }

  final archive = Archive();
  final usedNames = <String>{};
  final failed = <String>[];

  for (var i = 0; i < args.items.length; i++) {
    if (isCancelled?.call() ?? false) throw const JobCancelled();
    final item = args.items[i];
    onProgress?.call(i / args.items.length, 'Adding ${item.name}');

    final file = File(item.path);
    if (!file.existsSync()) {
      failed.add(item.name);
      continue;
    }
    final bytes = file.readAsBytesSync();
    archive.add(ArchiveFile(_uniqueEntryName(item.name, usedNames), bytes.length, bytes));
  }

  if (archive.isEmpty) {
    throw CorruptedFile(fileName: args.items.first.name, detail: 'No file could be added');
  }

  onProgress?.call(0.95, 'Packing zip');
  final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive));
  final target = uniqueDestination(args.outputDir, 'archive.zip');
  await atomicWriteBytes(target, zipBytes);
  return ZipCreateResult(
    zipPath: target,
    zipBytes: zipBytes.length,
    fileCount: archive.length,
    failedNames: failed,
  );
}

/// Deduplicates entry names within one archive: `name (1).ext`, `name (2).ext`, …
String _uniqueEntryName(String name, Set<String> used) {
  final normalized = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_');
  if (used.add(normalized.toLowerCase())) return normalized;
  final dot = normalized.lastIndexOf('.');
  final stem = dot > 0 ? normalized.substring(0, dot) : normalized;
  final ext = dot > 0 ? normalized.substring(dot) : '';
  for (var i = 1;; i++) {
    final candidate = '$stem ($i)$ext';
    if (used.add(candidate.toLowerCase())) return candidate;
  }
}

// ---------------------------------------------------------------------------
// Extract
// ---------------------------------------------------------------------------

final class ZipExtractArgs {
  const ZipExtractArgs({required this.zipPath, required this.outputDir});
  final String zipPath;
  final String outputDir;
}

final class ZipExtractResult {
  const ZipExtractResult({
    required this.folderPath,
    required this.fileCount,
    required this.totalBytes,
    required this.filePaths,
  });

  /// The folder all extracted files live in (named after the archive).
  final String folderPath;
  final int fileCount;
  final int totalBytes;
  final List<String> filePaths;
}

/// ZIP extract task — runs inside the job isolate.
///
/// Security (edge #21/#22):
/// • Declared uncompressed sizes are checked BEFORE any decompression — an
///   archive expanding beyond the ratio cap is rejected as a zip bomb.
/// • Entry paths are sanitized; any entry that escapes the output folder
///   (`..`, absolute paths treated as escapes after stripping drives/roots
///   is not enough — `..` aborts the whole extract) aborts with a typed
///   error. Nothing from a hostile archive is ever written.
/// Duplicate entry names are deduplicated as `name (1).ext`, …
Future<ZipExtractResult> zipExtractTask(
  ZipExtractArgs args, {
  void Function(double fraction, String? label)? onProgress,
  bool Function()? isCancelled,
}) async {
  final zipName = args.zipPath.split(Platform.pathSeparator).last;
  final zipBytes = File(args.zipPath).readAsBytesSync();

  final archive = ZipDecoder().decodeBytes(zipBytes);

  // Guard 1 — bomb check on declared sizes, before decompressing anything.
  var declaredTotal = 0;
  for (final f in archive) {
    if (f.isFile) declaredTotal += f.size;
  }
  final allowed = _allowedUncompressedBytes(zipBytes.length);
  if (declaredTotal > allowed) {
    throw ZipBombDetected(declaredBytes: declaredTotal);
  }

  // Guard 2 — zip-slip, phase 1: validate EVERY entry path before any disk
  // I/O. A single hostile entry aborts with nothing written, not even the
  // innocent files or the output folder.
  final fileEntries = archive.where((f) => f.isFile).toList();
  final safeNames = <String>[];
  for (final entry in fileEntries) {
    final safe = _safeEntryName(entry.name);
    if (safe == null) {
      throw ZipSlipDetected(entryName: entry.name);
    }
    safeNames.add(safe);
  }

  // Output folder named after the archive, unique on disk.
  final stem = _stemOf(zipName);
  final folderPath = uniqueDestination(args.outputDir, stem);
  Directory(folderPath).createSync(recursive: true);

  final usedNames = <String>{};
  final extractedPaths = <String>[];
  var totalBytes = 0;

  for (var i = 0; i < fileEntries.length; i++) {
    if (isCancelled?.call() ?? false) throw const JobCancelled();
    final entry = fileEntries[i];
    onProgress?.call(i / fileEntries.length, 'Extracting ${entry.name}');

    final outPath = '$folderPath${Platform.pathSeparator}${safeNames[i]}';
    final unique = _dedupePath(outPath, usedNames);
    Directory(unique).parent.createSync(recursive: true);
    final data = entry.content as List<int>;
    await atomicWriteBytes(unique, Uint8List.fromList(data));
    extractedPaths.add(unique);
    totalBytes += data.length;
  }

  if (extractedPaths.isEmpty) {
    throw CorruptedFile(fileName: zipName, detail: 'The archive contains no files');
  }

  return ZipExtractResult(
    folderPath: folderPath,
    fileCount: extractedPaths.length,
    totalBytes: totalBytes,
    filePaths: extractedPaths,
  );
}

/// Normalizes an entry path to a safe relative path inside the output folder.
/// Returns null when the entry tries to escape (`..`) — a zip-slip attack.
String? _safeEntryName(String name) {
  var n = name.replaceAll('\\', '/');
  // Absolute paths lose their root/drive and land inside the folder (safe);
  // only `..` segments are malicious.
  n = n.replaceFirst(RegExp(r'^/+'), '');
  n = n.replaceFirst(RegExp(r'^[A-Za-z]:/'), '');
  final parts = <String>[];
  for (final part in n.split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') return null;
    parts.add(part.replaceAll(RegExp(r'[<>:"|?*\x00-\x1f]'), '_'));
  }
  if (parts.isEmpty) return null;
  return parts.join(Platform.pathSeparator);
}

String _dedupePath(String path, Set<String> used) {
  if (used.add(path.toLowerCase())) return path;
  final dir = File(path).parent.path;
  final name = path.split(Platform.pathSeparator).last;
  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name;
  final ext = dot > 0 ? name.substring(dot) : '';
  for (var i = 1;; i++) {
    final candidate = '$dir${Platform.pathSeparator}$stem ($i)$ext';
    if (used.add(candidate.toLowerCase())) return candidate;
  }
}

String _stemOf(String name) {
  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name;
  return stem.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_');
}
