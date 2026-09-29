import 'dart:io';

import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter/widgets.dart' show TextEditingController;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../errors.dart';
import '../file_io.dart';
import '../history/history_store.dart';
import '../formats.dart' show PfMagic;
// Aliased: this file's flow-state classes (JobDone etc.) must not shadow the
// generic JobEvent types from the isolate runner.
import '../isolate_runner.dart' as runner;
import '../pdf/pdf_compress_service.dart';
import '../pdf/pdf_merge_service.dart';
import '../pdf/pdf_split_service.dart';
import '../pdf/images_to_pdf_service.dart';
import '../pdf/pdf_to_images_service.dart';
import '../pdf/ocr_service.dart';
import '../ocr/mlkit_ocr.dart';
import '../image_compress_service.dart';
import '../image_convert_service.dart';
import '../privacy/usage_store.dart';
import '../zip_service.dart';
import '../validation/validator.dart';
import 'copy_through_service.dart';

/// Per-tool options state (Feature 2: Compress PDF quality).
final pdfCompressQualityProvider =
    StateProvider<PdfCompressQuality>((_) => PdfCompressQuality.medium);

/// Feature 4: Split PDF options — mode + the three text inputs.
/// TextEditingControllers live in the state so typing survives rebuilds.
final splitOptionsProvider = StateProvider<SplitOptionsState>((_) => SplitOptionsState());

/// Feature 5: Images → PDF page-fit choice.
final imagesToPdfFitProvider = StateProvider<ImageFit>((_) => ImageFit.imageSize);

/// Feature 6: PDF → Images output choices (format, DPI, page selection).
final pdfToImagesOptionsProvider =
    StateProvider<PdfToImagesOptionsState>((_) => PdfToImagesOptionsState());

/// Feature 7: Compress Images options (quality preset + downscale toggle).
final imageCompressOptionsProvider =
    StateProvider<ImageCompressOptionsState>((_) => ImageCompressOptionsState());

final class ImageCompressOptionsState {
  ImageCompressOptionsState({this.quality = ImageQuality.medium, this.downscale = false});

  final ImageQuality quality;
  final bool downscale;

  ImageCompressOptionsState withQuality(ImageQuality q) =>
      ImageCompressOptionsState(quality: q, downscale: downscale);

  ImageCompressOptionsState withDownscale(bool v) =>
      ImageCompressOptionsState(quality: quality, downscale: v);
}

/// Feature 8: Convert Image target format.
final imageConvertTargetProvider =
    StateProvider<ImageTarget>((_) => ImageTarget.jpeg);

/// Feature 12: OCR page selection (empty = all pages).
final ocrOptionsProvider = StateProvider<OcrOptionsState>((_) => OcrOptionsState());

final class OcrOptionsState {
  OcrOptionsState({
    this.script = 'latin',
    this.enhanceImage = true,
    this.preserveLayout = true,
  }) : pagesController = TextEditingController();

  final TextEditingController pagesController;
  String script;
  bool enhanceImage;
  bool preserveLayout;

  /// Empty text = every page (the service clamps to real pages).
  List<int> get pages => parsePageSelection(pagesController.text);
}

final class PdfToImagesOptionsState {
  PdfToImagesOptionsState({PdfToImagesFormat? format, int? dpi})
      : format = format ?? PdfToImagesFormat.png,
        _dpi = dpi ?? 200,
        pagesController = TextEditingController();

  final PdfToImagesFormat format;
  int _dpi;
  int get dpi => _dpi;
  final TextEditingController pagesController;

  /// Empty text = every page (the service clamps to real pages).
  List<int> get pages => parsePageSelection(pagesController.text);

  PdfToImagesOptionsState withFormat(PdfToImagesFormat newFormat) {
    final next = PdfToImagesOptionsState(format: newFormat, dpi: _dpi)
      ..pagesController.text = pagesController.text;
    return next;
  }

  PdfToImagesOptionsState withDpi(int newDpi) {
    final next = PdfToImagesOptionsState()
      ..pagesController.text = pagesController.text
      .._dpi = newDpi.clamp(72, 300);
    return next;
  }
}

List<int> parsePageSelection(String text) => [
      for (final part in text.split(RegExp(r'[,;\s]+')))
        ?(int.tryParse(part.trim())),
    ];

final class SplitOptionsState {
  SplitOptionsState({SplitMode? mode})
      : mode = mode ?? SplitMode.everyN,
        intervalController = TextEditingController(text: '1'),
        rangesController = TextEditingController(),
        selectionController = TextEditingController();

  final SplitMode mode;
  final TextEditingController intervalController;
  final TextEditingController rangesController;
  final TextEditingController selectionController;

  int get interval {
    final v = int.tryParse(intervalController.text.trim());
    return v ?? 0;
  }

  List<(int, int)> get ranges {
    final parsed = <(int, int)>[];
    for (final part in rangesController.text.split(RegExp(r'[,;]'))) {
      final token = part.trim();
      if (token.isEmpty) continue;
      final dash = token.indexOf('-');
      if (dash <= 0) {
        final page = int.tryParse(token);
        if (page != null) parsed.add((page, page));
        continue;
      }
      final start = int.tryParse(token.substring(0, dash).trim());
      final end = int.tryParse(token.substring(dash + 1).trim());
      if (start != null && end != null) parsed.add((start, end));
    }
    return parsed;
  }

  List<int> get selection => [
        for (final part in selectionController.text.split(RegExp(r'[,;\s]+')))
          ?(int.tryParse(part.trim())),
      ];

  bool get intervalValid => interval >= 1;

  bool get rangesValid => ranges.isNotEmpty;

  bool get selectionValid => selection.isNotEmpty;

  bool get valid => switch (mode) {
        SplitMode.everyN => intervalValid,
        SplitMode.ranges => rangesValid,
        SplitMode.extract => selectionValid,
      };

  SplitOptionsState._(
      this.mode, this.intervalController, this.rangesController,
      this.selectionController);

  /// Re-publishes this options state so Riverpod listeners re-evaluate.
  /// BUGFIX (split options never synced): the TextFields only wrote into
  /// their TextEditingControllers — the provider never re-emitted, so
  /// errorText and the Start button's `valid` stayed frozen until the user
  /// left the screen and came back. Publishing a NEW instance that SHARES
  /// the same controllers keeps focus/cursor intact and notifies listeners.
  SplitOptionsState publish(SplitMode newMode) => SplitOptionsState._(
      newMode, intervalController, rangesController, selectionController);
}

sealed class JobFlowState {
  const JobFlowState();
}

final class JobIdle extends JobFlowState {
  const JobIdle();
}

/// A validated selection waiting for the user to press start.
final class JobReady extends JobFlowState {
  const JobReady({required this.files, required this.rejections});

  final List<PickedFile> files;
  final List<(String, PureError)> rejections;

  int get totalBytes => files.fold(0, (sum, f) => sum + f.sizeBytes);
}

final class JobRunning extends JobFlowState {
  const JobRunning({required this.fraction, this.label});
  final double fraction;
  final String? label;
}

final class JobDone extends JobFlowState {
  const JobDone({required this.outputs, this.result});
  final List<OutputInfo> outputs;
  final Object? result;
}

final class JobError extends JobFlowState {
  const JobError(this.error);
  final PureError error;
}

final jobFlowProvider =
    NotifierProvider<JobFlowController, JobFlowState>(JobFlowController.new);

/// Builds the per-tool isolate args from the output dir. The closure captures
/// the picked files and options on the UI side; the controller stays generic.
typedef ToolArgsBuilder = Object? Function(String outputDir);

/// Drives one tool job through the pipeline contract (F1–F8):
/// pick → validate → isolate run (progress/cancel/timeout) → result.
class JobFlowController extends Notifier<JobFlowState> {
  runner.JobHandle<Object?>? _handle;
  String? _outputDir;

  /// Tool id of the current job, recorded into history on success (F10).
  String? _runningToolId;

  @override
  JobFlowState build() => const JobIdle();

  Future<String> _ensureOutputDir() async {
    if (_outputDir != null) return _outputDir!;
    final docs = await appDocumentsPath();
    final dir = '${Directory(docs).path}${Platform.pathSeparator}outputs';
    Directory(dir).createSync(recursive: true);
    return _outputDir = dir;
  }

  /// F1/F2/F3: pick then validate. Replaces any current selection (the
  /// initial pick + share intake). Rejections are shown, not fatal.
  /// [maxFiles] caps how many files this tool accepts (e.g. Compress PDF = 1);
  /// extras land in `rejections` instead of failing the whole selection.
  Future<void> selectFiles(
    List<String> paths, {
    Set<PfMagic>? allowedMagic,
    int? maxFiles,
  }) async {
    final result = await validatePick(paths, allowedMagic: allowedMagic);
    if (result.accepted.isEmpty && result.rejected.isNotEmpty) {
      state = JobError(result.rejected.first.$2);
      return;
    }
    var accepted = result.accepted;
    var rejected = result.rejected;
    if (maxFiles != null && accepted.length > maxFiles) {
      rejected = [
        ...rejected,
        for (final extra in accepted.skip(maxFiles)) (extra.name, const SingleFileOnly()),
      ];
      accepted = accepted.take(maxFiles).toList();
    }
    state = JobReady(files: accepted, rejections: rejected);
  }

  /// "Add more files": validates the NEW picks and APPENDS them to the
  /// current selection (deduped by path — picking the same file twice keeps
  /// it once). The combined list still respects [maxFiles]: extras become
  /// rejections. No-op when there is nothing to add.
  Future<void> addFiles(
    List<String> paths, {
    Set<PfMagic>? allowedMagic,
    int? maxFiles,
  }) async {
    final current = state;
    if (paths.isEmpty) return;
    if (current is! JobReady) {
      await selectFiles(paths, allowedMagic: allowedMagic, maxFiles: maxFiles);
      return;
    }

    final result = await validatePick(paths, allowedMagic: allowedMagic);
    if (result.accepted.isEmpty && result.rejected.isNotEmpty) {
      // Nothing valid among the new picks — surface why, keep the selection.
      state = JobReady(
        files: current.files,
        rejections: [...current.rejections, ...result.rejected],
      );
      return;
    }

    final existing = current.files;
    final fresh = [
      for (final a in result.accepted)
        if (!existing.any((e) => e.path == a.path)) a,
    ];

    final combined = [...existing, ...fresh];
    var rejected = [...current.rejections, ...result.rejected];
    var kept = combined;
    if (maxFiles != null && combined.length > maxFiles) {
      rejected = [
        ...rejected,
        for (final extra in combined.skip(maxFiles))
          (extra.name, const SingleFileOnly()),
      ];
      kept = combined.take(maxFiles).toList();
    }
    state = JobReady(files: kept, rejections: rejected);
  }

  /// Reorders the picked files (merge tool — F10). No-op unless ready.
  /// [newIndex] is already adjusted for the removed item (onReorderItem).
  void reorder(int oldIndex, int newIndex) {
    final current = state;
    if (current is! JobReady) return;
    final files = [...current.files];
    final moved = files.removeAt(oldIndex);
    files.insert(newIndex, moved);
    state = JobReady(files: files, rejections: current.rejections);
  }

  /// F2 (batch caps + storage) then F4 (isolate run) with per-tool args.
  ///
  /// ISOLATE-SAFETY RULE: pass top-level function `runToolTask` as [entry] and
  /// the pure [args] object directly to [runJob]. NEVER construct a lambda/closure
  /// inside an instance method (e.g. `(ctx) => runToolTask(args, ctx)`); in Dart,
  /// any closure created inside an instance method captures that method's context
  /// frame (`this`, `_AsyncCompleter`, Riverpod ref), which transitively drags
  /// watched widget elements (RenderParagraph, PipelineOwner, WidgetsFlutterBinding)
  /// into the isolate and causes "object is unsendable" at Start.
  Future<void> start({ToolArgsBuilder? makeArgs, String? toolId}) async {
    final current = state;
    if (current is! JobReady) return;
    _runningToolId = toolId;
    String? outputDir;
    try {
      outputDir = await _ensureOutputDir();
      validateBatch(current.files, outputDirectory: outputDir);

      final args = makeArgs?.call(outputDir) ??
          CopyThroughArgs(
            jobs: [
              for (final f in current.files) (f.path, f.name, f.sizeBytes),
            ],
            outputDir: outputDir,
          );

      state = const JobRunning(fraction: 0);
      _handle = runner.runJob<Object?>(
        entry: runToolTask,
        args: args,
      );

      _handle!.events.listen((event) {
        switch (event) {
          case runner.JobProgress<Object?>(:final fraction, :final label):
            state = JobRunning(fraction: fraction, label: label);
          case runner.JobDone<Object?>(:final result):
            final outputs = _toOutputs(result);
            state = JobDone(outputs: outputs, result: result);
            _recordHistory(outputs);
          case runner.JobFailed<Object?>(:final error):
            // A cancel triggers a JobFailed(JobCancelled) event too — keep
            // the clean Idle state set by cancel() instead of surfacing it.
            if (!(_handle?.isCancelled ?? false)) state = JobError(error);
        }
      });

      await _handle!.future;
    } on JobCancelled {
      state = const JobIdle();
      if (outputDir != null) cleanupTempFiles(outputDir);
    } on PureError {
      // State already set by the event stream.
      if (outputDir != null) cleanupTempFiles(outputDir);
    } catch (e) {
      // Non-typed failures (e.g. a platform-channel hiccup while resolving
      // the output dir) must never die silently with the UI stuck on Ready.
      state = JobError(UnknownFailure(e.toString()));
      if (outputDir != null) cleanupTempFiles(outputDir);
    }
  }

  // NOTE: tool dispatch lives in the TOP-LEVEL runToolTask() below — it
  // must stay out of this class or the spawn closure becomes unsendable.

  List<OutputInfo> _toOutputs(Object? result) => switch (result) {
        PdfCompressResult(
          :final outputPath,
          :final compressedBytes,
          :final keptOriginal,
          :final savedPercent,
        ) =>
          [
            OutputInfo(
              path: outputPath,
              name: outputPath.split(Platform.pathSeparator).last,
              sizeBytes: compressedBytes,
              keptOriginal: keptOriginal,
              savedPercent: savedPercent,
            ),
          ],
        MergeResult(:final outputPath, :final outputBytes, :final failedNames) => [
            OutputInfo(
              path: outputPath,
              name: outputPath.split(Platform.pathSeparator).last,
              sizeBytes: outputBytes,
              warning: failedNames.isEmpty
                  ? null
                  : 'Could not merge: ${failedNames.join(', ')}',
            ),
          ],
        ImagesToPdfResult(:final outputPath, :final outputBytes, :final pageCount) => [
            OutputInfo(
              path: outputPath,
              name: outputPath.split(Platform.pathSeparator).last,
              sizeBytes: outputBytes,
              warning: pageCount > 1 ? '$pageCount pages created' : null,
            ),
          ],
        PdfToImagesResult(
          :final outputPath,
          :final outputBytes,
          :final imageCount,
          :final pageCountTotal,
        ) =>
          [
            OutputInfo(
              path: outputPath,
              name: outputPath.split(Platform.pathSeparator).last,
              sizeBytes: outputBytes,
              warning: imageCount > 1
                  ? '$imageCount of $pageCountTotal pages rendered'
                  : null,
            ),
          ],
        SplitResult(:final outputPath, :final outputBytes, :final pieceCount) => [
            OutputInfo(
              path: outputPath,
              name: outputPath.split(Platform.pathSeparator).last,
              sizeBytes: outputBytes,
              warning: pieceCount > 1 ? 'zipped $pieceCount pieces' : null,
            ),
            if (pieceCount > 1)
              OutputInfo(
                path: '',
                name: '$pieceCount split PDFs are packed inside this zip',
                sizeBytes: 0,
              ),
          ],
        ImageConvertResult(:final files, :final zipPath, :final zipBytes) => [
            if (zipPath != null)
              OutputInfo(
                path: zipPath,
                name: zipPath.split(Platform.pathSeparator).last,
                sizeBytes: zipBytes,
              ),
            for (final f in files)
              OutputInfo(
                path: f.path,
                name: f.name,
                sizeBytes: f.sizeBytes,
                warning: f.converted ? null : 'already ${f.target.name} — copied as-is',
              ),
          ],
        ZipCreateResult(
          :final zipPath,
          :final zipBytes,
          :final fileCount,
          :final failedNames,
        ) =>
          [
            OutputInfo(
              path: zipPath,
              name: zipPath.split(Platform.pathSeparator).last,
              sizeBytes: zipBytes,
              warning: failedNames.isEmpty
                  ? '$fileCount files packed'
                  : '$fileCount files packed · skipped: ${failedNames.join(', ')}',
            ),
          ],
        ZipExtractResult(
          :final folderPath,
          :final fileCount,
          :final totalBytes,
          :final filePaths,
        ) =>
          [
            if (filePaths.isEmpty)
              OutputInfo(
                path: folderPath,
                name: folderPath.split(Platform.pathSeparator).last,
                sizeBytes: totalBytes,
                warning: '$fileCount files extracted',
              )
            else
              for (final p in filePaths)
                OutputInfo(
                  path: p,
                  name: p.split(Platform.pathSeparator).last,
                  sizeBytes: File(p).existsSync() ? File(p).lengthSync() : 0,
                  warning: 'Extracted · $fileCount files in ${folderPath.split(Platform.pathSeparator).last}',
                ),
          ],
        OcrResult(
          :final outputPath,
          :final outputBytes,
          :final textPath,
          :final textBytes,
          :final pageCount,
          :final noText,
          :final wordCount,
          :final characterCount,
        ) =>
          [
            OutputInfo(
              path: outputPath,
              name: outputPath.split(Platform.pathSeparator).last,
              sizeBytes: outputBytes,
              warning: noText
                  ? 'No text detected'
                  : 'Searchable PDF · $pageCount page(s) · $wordCount words',
            ),
            OutputInfo(
              path: textPath,
              name: textPath.split(Platform.pathSeparator).last,
              sizeBytes: textBytes > 0
                  ? textBytes
                  : (File(textPath).existsSync() ? File(textPath).lengthSync() : 0),
              warning: 'Plain text · $characterCount chars',
            ),
          ],
        CopyThroughResult(:final outputs) => outputs,
        ImageCompressResult(:final files, :final zipPath, :final zipBytes) => [
            if (zipPath != null)
              OutputInfo(
                path: zipPath,
                name: zipPath.split(Platform.pathSeparator).last,
                sizeBytes: zipBytes,
                warning: files.any((f) => f.keptOriginal)
                    ? 'some files were already optimized and kept as-is'
                    : null,
              ),
            for (final f in files)
              OutputInfo(
                path: f.path,
                name: f.name,
                sizeBytes: f.sizeBytes,
                savedPercent: f.originalBytes == 0
                    ? 0
                    : ((f.originalBytes - f.sizeBytes) / f.originalBytes * 100)
                        .round()
                        .clamp(0, 100),
                keptOriginal: f.keptOriginal,
              ),
          ],
        _ => throw const UnknownFailure('Unknown job result'),
      };

  /// F10: best-effort history record for each real output. Fire-and-forget:
  /// a history failure must never fail a finished job. F15: the same loop
  /// feeds the privacy-dashboard counters (one atomic UsageProcessed event).
  Future<void> _recordHistory(List<OutputInfo> outputs) async {
    final toolId = _runningToolId;
    if (toolId == null) return;
    var count = 0;
    var bytes = 0;
    for (final o in outputs) {
      if (o.path.isEmpty) continue; // informational rows (e.g. zip contents)
      count++;
      bytes += o.sizeBytes;
      try {
        final isDir = FileSystemEntity.typeSync(o.path) == FileSystemEntityType.directory;
        await ref.read(historyProvider).record(HistoryEntry(
              path: o.path,
              fileName: o.name,
              toolId: toolId,
              sizeBytes: o.sizeBytes,
              createdAt: DateTime.now(),
              isDirectory: isDir,
            ));
      } catch (_) {
        // History is a convenience; output files remain fully usable.
      }
    }
    if (count > 0) {
      try {
        await ref.read(usageStoreProvider).apply(
              UsageProcessed(toolId: toolId, count: count, bytes: bytes),
            );
      } catch (_) {
        // Counters are a convenience too — never fail a finished job.
      }
    }
  }

  /// F4: cancel removes temps and never leaves a partial history entry.
  Future<void> cancel() async {
    _handle?.cancel();
    if (_outputDir != null) cleanupTempFiles(_outputDir!);
  }

  void reset() {
    _handle = null;
    _runningToolId = null;
    state = const JobIdle();
  }
}

/// Runs the matching per-tool task for [args]. TOP-LEVEL on purpose: this is
/// the entry sent across the isolate boundary, and a top-level function
/// reference is sendable while an instance tear-off would drag the controller
/// (and with it the whole widget tree) into the spawn — the "object is
/// unsendable" device failure this shape fixed.
Future<Object?> runToolTask(Object? args, runner.PfJobContext ctx) async {
  switch (args) {
    case PdfCompressArgs():
      return pdfCompressTask(
        args,
        onProgress: ctx.report,
        isCancelled: () => ctx.isCancelled,
      );
    case MergeArgs():
      return pdfMergeTask(
        args,
        onProgress: ctx.report,
        isCancelled: () => ctx.isCancelled,
      );
    case SplitArgs():
      return pdfSplitTask(
        args,
        onProgress: ctx.report,
        isCancelled: () => ctx.isCancelled,
      );
    case ImagesToPdfArgs():
      return imagesToPdfTask(
        args,
        onProgress: ctx.report,
        isCancelled: () => ctx.isCancelled,
      );
    case PdfToImagesArgs():
      return pdfToImagesTask(
        args,
        renderer: pdfxPageRenderer,
        onProgress: ctx.report,
        isCancelled: () => ctx.isCancelled,
      );
    case OcrArgs():
      return ocrTask(
        args,
        recognize: mlkitPageRecognizer(
          scriptName: args.script,
          enhanceForOcr: args.enhanceImage,
        ),
        renderPage: ocrPageRaster,
        onProgress: ctx.report,
        isCancelled: () => ctx.isCancelled,
      );
    case ImageCompressArgs():
      return imageCompressTask(
        args,
        onProgress: ctx.report,
        isCancelled: () => ctx.isCancelled,
      );
    case ImageConvertArgs():
      return imageConvertTask(
        args,
        onProgress: ctx.report,
        isCancelled: () => ctx.isCancelled,
      );
    case ZipCreateArgs():
      return zipCreateTask(
        args,
        onProgress: ctx.report,
        isCancelled: () => ctx.isCancelled,
      );
    case ZipExtractArgs():
      return zipExtractTask(
        args,
        onProgress: ctx.report,
        isCancelled: () => ctx.isCancelled,
      );
    case CopyThroughArgs():
      return copyThrough(
        args,
        onProgress: ctx.report,
        isCancelled: () => ctx.isCancelled,
      );
    default:
      throw const UnknownFailure('Unknown tool arguments');
  }
}

/// App documents directory — `outputs/` lives here on device.
/// Falls back to a temp dir in environments without platform channels (tests).
Future<String> appDocumentsPath() async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  } on MissingPluginException {
    return Directory.systemTemp.createTempSync('pf_docs').path;
  }
}
