import 'dart:io';

import '../constants.dart';
import '../errors.dart';
import '../formats.dart';

/// One file accepted into a job.
final class PickedFile {
  PickedFile({required this.path, required this.name, required this.sizeBytes, required this.magic});

  final String path;
  final String name;
  final int sizeBytes;
  final PfMagic magic;
}

/// Result of validating a user selection: accepted files + per-file reasons.
final class PickResult {
  PickResult({required this.accepted, required this.rejected});

  final List<PickedFile> accepted;

  /// (fileName, error) pairs for files the user must fix or drop.
  final List<(String, PureError)> rejected;

  bool get hasRejections => rejected.isNotEmpty;
}

/// Per-file validation: exists, non-empty, size limit, magic bytes vs extension.
/// Never throws — returns the rejection reason instead (edge cases #1–#9).
Future<PickResult> validatePick(List<String> paths, {Set<PfMagic>? allowedMagic}) async {
  final accepted = <PickedFile>[];
  final rejected = <(String, PureError)>[];

  if (paths.length > PfLimits.maxBatchFiles) {
    rejected.add((
      '${paths.length} files',
      BatchTooLarge(files: paths.length, limit: PfLimits.maxBatchFiles),
    ));
    return PickResult(accepted: accepted, rejected: rejected);
  }

  for (final path in paths) {
    final name = path.split(Platform.pathSeparator).last;
    final file = File(path);
    try {
      final stat = file.statSync();
      if (stat.type == FileSystemEntityType.directory) {
        rejected.add((name, const UnsupportedFormat(fileName: 'Folder', expected: 'file')));
        continue;
      }
      if (stat.size == 0) {
        rejected.add((name, CorruptedFile(fileName: name)));
        continue;
      }
      if (stat.size > PfLimits.maxFileBytes) {
        rejected.add((name, FileTooLarge(fileName: name, sizeBytes: stat.size, limitBytes: PfLimits.maxFileBytes)));
        continue;
      }
      final magic = await sniffFileMagic(path);
      final expected = magicForExtension(name);
      if (expected != null && magic == PfMagic.unknown) {
        rejected.add((name, CorruptedFile(fileName: name, detail: 'Its contents do not match its type')));
        continue;
      }
      if (expected != null && !expected.contains(magic)) {
        rejected.add((name, UnsupportedFormat(fileName: name, expected: expectedLabel(expected))));
        continue;
      }
      if (allowedMagic != null && !allowedMagic.contains(magic)) {
        rejected.add((name, UnsupportedFormat(fileName: name, expected: allowedLabel(allowedMagic))));
        continue;
      }
      accepted.add(PickedFile(path: path, name: name, sizeBytes: stat.size, magic: magic));
    } on FileSystemException {
      rejected.add((name, CorruptedFile(fileName: name)));
    }
  }
  return PickResult(accepted: accepted, rejected: rejected);
}

/// Batch-level validation before starting: combined size + free storage.
/// Throws the matching typed error (edge cases #4, #34).
void validateBatch(List<PickedFile> files, {required String outputDirectory}) {
  if (files.isEmpty) {
    throw const UnsupportedFormat(fileName: 'Nothing selected', expected: 'at least one file');
  }
  if (files.length > PfLimits.maxBatchFiles) {
    throw BatchTooLarge(files: files.length, limit: PfLimits.maxBatchFiles);
  }
  final totalBytes = files.fold<int>(0, (sum, f) => sum + f.sizeBytes);
  if (totalBytes > PfLimits.maxBatchBytes) {
    throw BatchTooHeavy(totalBytes: totalBytes, limitBytes: PfLimits.maxBatchBytes);
  }
  final needed = (totalBytes * PfLimits.minFreeStorageFactor).round();
  final free = freeDiskBytes(outputDirectory);
  if (free != null && free < needed) {
    throw InsufficientStorage(neededBytes: needed, freeBytes: free);
  }
}

/// Free disk bytes under [dirPath], or null when the platform query fails
/// (e.g. Windows dev shell) — the storage check is then skipped by design.
int? freeDiskBytes(String dirPath) {
  try {
    final result = Process.runSync('df', ['-B', '1', dirPath]);
    if (result.exitCode != 0) return null;
    final lines = (result.stdout as String).trim().split('\n');
    if (lines.length < 2) return null;
    final columns = lines.last.trim().split(RegExp(r'\s+'));
    if (columns.length < 4) return null;
    return int.tryParse(columns[3]);
  } catch (_) {
    return null;
  }
}

String expectedLabel(Set<PfMagic> expected) => expected
    .map((m) => switch (m) {
          PfMagic.pdf => 'PDF',
          PfMagic.png => 'PNG',
          PfMagic.jpeg => 'JPG',
          PfMagic.webp => 'WebP',
          PfMagic.gif => 'GIF',
          PfMagic.zip => 'ZIP',
          PfMagic.heic => 'HEIC',
          PfMagic.unknown => 'known',
        })
    .join('/');

String allowedLabel(Set<PfMagic> allowed) => 'one of: ${expectedLabel(allowed)}';
