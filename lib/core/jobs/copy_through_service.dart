import 'dart:io';

import '../errors.dart';
import '../file_io.dart';

/// Feature 1 proves the pipeline with a copy-through job: every picked file
/// is streamed to a new output in `outputs/`. Real tools (features 2+) replace
/// this task with compress/merge/etc. while reusing the exact same machinery.
final class CopyThroughArgs {
  const CopyThroughArgs({required this.jobs, required this.outputDir});

  /// (sourcePath, outputFileName, sizeBytes) — all sendable primitives.
  final List<(String, String, int)> jobs;
  final String outputDir;
}

final class CopyThroughResult {
  const CopyThroughResult({required this.outputs});
  final List<OutputInfo> outputs;
}

final class OutputInfo {
  const OutputInfo({
    required this.path,
    required this.name,
    required this.sizeBytes,
    this.keptOriginal = false,
    this.savedPercent = 0,
    this.warning,
  });
  final String path;
  final String name;
  final int sizeBytes;

  /// True when the tool kept the original because the output was not better
  /// ("never worse than input" honesty rule). No new file was written.
  final bool keptOriginal;

  /// Percent smaller than the input (compression tools; 0 otherwise).
  final int savedPercent;

  /// Non-fatal caveat to show on the result (e.g. merge items skipped).
  final String? warning;
}

/// Runs in the job isolate: sequential copies with progress + cancel.
/// Inputs are only read; outputs land in [CopyThroughArgs.outputDir].
Future<CopyThroughResult> copyThroughTask(CopyThroughArgs args) async {
  return copyThrough(args, onProgress: null, isCancelled: null);
}

/// Testable variant with injected progress/cancel hooks.
Future<CopyThroughResult> copyThrough(
  CopyThroughArgs args, {
  void Function(double fraction, String? label)? onProgress,
  bool Function()? isCancelled,
}) async {
  Directory(args.outputDir).createSync(recursive: true);
  final outputs = <OutputInfo>[];

  for (var i = 0; i < args.jobs.length; i++) {
    if (isCancelled?.call() ?? false) throw const JobCancelled();
    final (source, name, size) = args.jobs[i];
    final target = uniqueDestination(args.outputDir, name);
    onProgress?.call(i / args.jobs.length, 'Processing $name');
    await atomicCopyFile(
      source,
      target,
      onProgress: (f) => onProgress?.call((i + f) / args.jobs.length, 'Processing $name'),
      isCancelled: isCancelled,
    );
    outputs.add(OutputInfo(path: target, name: target.split(Platform.pathSeparator).last, sizeBytes: size));
  }
  return CopyThroughResult(outputs: outputs);
}
