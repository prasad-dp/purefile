import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, FilteringTextInputFormatter;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/errors.dart';
import '../../core/file_io.dart';
import '../../core/formats.dart';
import '../../core/jobs/copy_through_service.dart';
import '../../core/jobs/job_controller.dart';
import '../../core/pdf/pdf_compress_service.dart';
import '../../core/pdf/pdf_merge_service.dart';
import '../../core/pdf/pdf_split_service.dart';
import '../../core/pdf/images_to_pdf_service.dart';
import '../../core/pdf/pdf_to_images_service.dart';
import '../../core/pdf/ocr_service.dart';
import '../../core/image_compress_service.dart';
import '../../core/image_convert_service.dart';
import '../../core/zip_service.dart';
import '../../core/tools.dart';
import '../../core/share_intake/share_intake.dart';
import '../../core/theme.dart' show PfHaptics;
import '../../core/validation/validator.dart';
import '../../core/theme.dart' show PfColors;
import '../../l10n/generated/app_localizations.dart';
import '../../widgets/file_chip.dart';

/// The shared pipeline every tool uses (docs/architecture.md):
/// pick → validate → options → isolate run (progress/cancel) → result.
///
/// Per-tool behavior is expressed via [ToolUiSpec]: which file types are
/// allowed, the options widget, and how the args + result map to the generic
/// output model. Feature 2 (Compress PDF) is the first real tool; features
/// 3+ register their own spec instead of touching this screen.
class ToolFlowScreen extends ConsumerStatefulWidget {
  const ToolFlowScreen({super.key, required this.tool});

  final PfTool tool;

  static PfTool? fromRoute(String toolId) {
    for (final t in kPfTools) {
      if (t.route == '/tools/$toolId') return t;
    }
    return null;
  }

  @override
  ConsumerState<ToolFlowScreen> createState() => _ToolFlowScreenState();
}

class _ToolFlowScreenState extends ConsumerState<ToolFlowScreen> {
  PfTool get tool => widget.tool;

  ToolUiSpec _spec(AppLocalizations loc) => toolUiSpec(tool.id);

  @override
  void initState() {
    super.initState();
    // BUGFIX (cross-tool selection leak): the flow state is app-scoped, so a
    // JobReady left over from another tool (e.g. Merge) would otherwise SHOW
    // UP HERE (e.g. Split) with the old files pre-selected. Entering a tool
    // always starts from Idle — reset in the post-frame hook (providers must
    // not be modified during widget build); the share intake below then
    // fills a FRESH selection. First frame may flash the stale state for a
    // sub-frame moment; the post-frame fix keeps every interaction clean.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(jobFlowProvider.notifier).reset();
      _intakeShared();
    });
  }

  void _intakeShared() {
    if (!mounted) return;
    final pending = ref.read(shareIntakeProvider);
    if (pending.isEmpty) return;
    final current = ref.read(jobFlowProvider);
    if (current is! JobIdle && current is! JobReady) return;
    final spec = toolUiSpec(tool.id);
    ref.read(shareIntakeProvider.notifier).consume();
    ref.read(jobFlowProvider.notifier).selectFiles(
          pending,
          allowedMagic: spec.allowedMagic,
          maxFiles: spec.maxFiles,
        );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final state = ref.watch(jobFlowProvider);
    final controller = ref.read(jobFlowProvider.notifier);

    // F16: a share arriving while this screen is open refills the selection.
    ref.listen(shareIntakeProvider, (prev, next) {
      if (next.isNotEmpty) _intakeShared();
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(tool.title),
        actions: [
          if (state is JobReady || state is JobDone || state is JobError)
            IconButton(
              tooltip: loc.reset,
              onPressed: controller.reset,
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      body: SafeArea(
        child: switch (state) {
          JobIdle() => _PickStage(
              tool: tool,
              spec: _spec(loc),
              onPick: () => _pickAndValidate(context, controller, loc),
            ),
          JobReady(:final files, :final rejections, :final totalBytes) =>
            _ReadyStage(
              files: files,
              rejections: rejections,
              totalBytes: totalBytes,
              spec: _spec(loc),
              optionsValid:
                  tool.id != 'pdf_split' || ref.watch(splitOptionsProvider).valid,
              onReorder: controller.reorder,
              onStart: () => controller.start(
                toolId: tool.id,
                makeArgs: (outputDir) => makeToolArgs(
                  tool: tool,
                  files: files,
                  outputDir: outputDir,
                  // BUGFIX (Start dead on split): ref.watch is illegal
                  // inside a tap callback — it threw when Start was tapped.
                  // Options are already live via the build's watch above;
                  // read() here is the legal one-shot lookup.
                  options: switch (tool.id) {
                    'pdf_compress' => ref.read(pdfCompressQualityProvider),
                    'pdf_split' => ref.read(splitOptionsProvider),
                    'images_to_pdf' => ref.read(imagesToPdfFitProvider),
                    'pdf_to_images' => ref.read(pdfToImagesOptionsProvider),
                    'image_compress' => ref.read(imageCompressOptionsProvider),
                    'image_convert' => ref.read(imageConvertTargetProvider),
                    'ocr' => ref.read(ocrOptionsProvider),
                    _ => null,
                  },
                ),
              ),
              // BUGFIX (add-more replaced the selection): append via
              // addFiles — selectFiles overwrote the list with only the
              // newly picked file.
              onPickMore: () => _pickMore(context, controller, loc),
            ),
          JobRunning(:final fraction, :final label) => _RunningStage(
              fraction: fraction,
              label: label,
              onCancel: controller.cancel,
            ),
          JobDone(:final outputs, :final result) =>
              _DoneStage(outputs: outputs, rawResult: result),
          JobError(:final error) => _ErrorStage(
              error: error,
              onRetry: controller.reset,
            ),
        },
      ),
    );
  }

  Future<void> _pickAndValidate(
    BuildContext context,
    JobFlowController controller,
    AppLocalizations loc,
  ) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
      withData: false,
    );
    final paths = result?.paths.whereType<String>().toList() ?? const [];
    if (paths.isEmpty) return;
    final spec = _spec(loc);
    await controller.selectFiles(
      paths,
      allowedMagic: spec.allowedMagic,
      maxFiles: spec.maxFiles,
    );
  }

  /// "Add more files" from the Ready stage: APPEND to the selection.
  Future<void> _pickMore(
    BuildContext context,
    JobFlowController controller,
    AppLocalizations loc,
  ) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
      withData: false,
    );
    final paths = result?.paths.whereType<String>().toList() ?? const [];
    if (paths.isEmpty) return;
    final spec = _spec(loc);
    await controller.addFiles(
      paths,
      allowedMagic: spec.allowedMagic,
      maxFiles: spec.maxFiles,
    );
  }
}

/// Per-tool UI contract, keyed by tool id (F16: shared with the share-intake
/// chooser so eligibility rules can't drift from the tool flow's own rules).
ToolUiSpec toolUiSpec(String toolId) {
  if (toolId == 'pdf_compress') {
    return ToolUiSpec(
      allowedMagic: const {PfMagic.pdf},
      maxFiles: 1,
      optionsBuilder: (context) => const PdfCompressOptions(),
    );
  }
  if (toolId == 'pdf_merge') {
    // F10: 2+ PDFs and/or images in any order, user-reorderable.
    return const ToolUiSpec(
      allowedMagic: {PfMagic.pdf, PfMagic.jpeg, PfMagic.png, PfMagic.webp, PfMagic.heic},
      minFiles: 2,
      reorderable: true,
    );
  }
  if (toolId == 'zip_create') {
    // F9: pack any files into a zip (no type restriction).
    return const ToolUiSpec(minFiles: 1);
  }
  if (toolId == 'zip_extract') {
    // F9: exactly one zip archive.
    return const ToolUiSpec(
      allowedMagic: {PfMagic.zip},
      maxFiles: 1,
    );
  }
  if (toolId == 'image_convert') {
    // F8: batch images with a target-format picker.
    return const ToolUiSpec(
      allowedMagic: {PfMagic.jpeg, PfMagic.png, PfMagic.webp, PfMagic.heic},
      minFiles: 1,
      optionsBuilder: _buildImageConvertOptions,
    );
  }
  if (toolId == 'image_compress') {
    // F7: batch images with quality + downscale options.
    return const ToolUiSpec(
      allowedMagic: {PfMagic.jpeg, PfMagic.png, PfMagic.webp, PfMagic.heic},
      minFiles: 1,
      optionsBuilder: _buildImageCompressOptions,
    );
  }
  if (toolId == 'pdf_to_images') {
    // F6: one PDF; format/DPI/pages options appear in the ready stage.
    return const ToolUiSpec(
      allowedMagic: {PfMagic.pdf},
      maxFiles: 1,
      optionsBuilder: _buildPdfToImagesOptions,
    );
  }
  if (toolId == 'ocr') {
    // Top-notch OCR: accepts 1 PDF or 1+ Images (reorderable).
    return const ToolUiSpec(
      allowedMagic: {
        PfMagic.pdf,
        PfMagic.jpeg,
        PfMagic.png,
        PfMagic.webp,
        PfMagic.heic,
      },
      minFiles: 1,
      reorderable: true,
      optionsBuilder: _buildOcrOptions,
    );
  }
  if (toolId == 'images_to_pdf') {
    // F5: batch of images, reorderable, page-fit choice in options.
    return const ToolUiSpec(
      allowedMagic: {PfMagic.jpeg, PfMagic.png, PfMagic.webp, PfMagic.heic},
      minFiles: 1,
      reorderable: true,
      optionsBuilder: _buildImagesToPdfOptions,
    );
  }
  if (toolId == 'pdf_split') {
    // F11: exactly one PDF; split-mode options appear in the ready stage.
    return const ToolUiSpec(
      allowedMagic: {PfMagic.pdf},
      maxFiles: 1,
      optionsBuilder: _buildSplitOptions,
    );
  }
  // Default: no options, accept common files (copy-through fallback until
  // the tool's feature lands).
  return const ToolUiSpec();
}

/// Builds the per-tool isolate args from the picked files + options state.
Object? makeToolArgs({
  required PfTool tool,
  required List<PickedFile> files,
  required String outputDir,
  required Object? options,
}) {
  if (tool.id == 'pdf_compress') {
    final quality = options is PdfCompressQuality ? options : PdfCompressQuality.medium;
    final file = files.single;
    final target = uniqueDestination(outputDir, 'compressed_${file.name}');
    return PdfCompressArgs(
      inputPath: file.path,
      outputPath: target,
      quality: quality,
    );
  }
  if (tool.id == 'zip_create') {
    return ZipCreateArgs(
      items: [
        for (final f in files) ZipCreateItem(path: f.path, name: f.name),
      ],
      outputDir: outputDir,
    );
  }
  if (tool.id == 'zip_extract') {
    final file = files.single;
    return ZipExtractArgs(zipPath: file.path, outputDir: outputDir);
  }
  if (tool.id == 'image_convert') {
    final target = options is ImageTarget ? options : ImageTarget.jpeg;
    return ImageConvertArgs(
      items: [
        for (final f in files) ImageConvertItem(path: f.path, name: f.name),
      ],
      outputDir: outputDir,
      target: target,
    );
  }
  if (tool.id == 'image_compress') {
    final opts = options is ImageCompressOptionsState
        ? options
        : ImageCompressOptionsState();
    return ImageCompressArgs(
      items: [
        for (final f in files) ImageCompressItem(path: f.path, name: f.name),
      ],
      outputDir: outputDir,
      quality: opts.quality,
      maxSide: opts.downscale ? 2560 : null,
    );
  }
  if (tool.id == 'pdf_to_images') {
    final file = files.single;
    final opts = options is PdfToImagesOptionsState
        ? options
        : PdfToImagesOptionsState();
    return PdfToImagesArgs(
      inputPath: file.path,
      outputDir: outputDir,
      pages: opts.pages, // empty = all pages (service contract)
      format: opts.format,
      dpi: opts.dpi,
    );
  }
  if (tool.id == 'ocr') {
    final opts = options is OcrOptionsState ? options : OcrOptionsState();
    final isSinglePdf = files.length == 1 && files.single.magic == PfMagic.pdf;
    if (isSinglePdf) {
      return OcrArgs(
        inputPath: files.single.path,
        outputDir: outputDir,
        pages: opts.pages, // empty = all pages (service contract)
        script: opts.script,
        enhanceImage: opts.enhanceImage,
        preserveLayout: opts.preserveLayout,
      );
    } else {
      return OcrArgs(
        inputPath: files.first.path,
        imagePaths: [for (final f in files) f.path],
        outputDir: outputDir,
        script: opts.script,
        enhanceImage: opts.enhanceImage,
        preserveLayout: opts.preserveLayout,
      );
    }
  }
  if (tool.id == 'images_to_pdf') {
    return ImagesToPdfArgs(
      images: [for (final f in files) (f.path, f.name)],
      outputDir: outputDir,
      fit: options is ImageFit ? options : ImageFit.imageSize,
    );
  }
  if (tool.id == 'pdf_split') {
    final file = files.single;
    final opts = options is SplitOptionsState ? options : SplitOptionsState();
    return SplitArgs(
      inputPath: file.path,
      outputDir: outputDir,
      mode: opts.mode,
      interval: opts.interval,
      ranges: opts.ranges,
      selection: opts.selection,
    );
  }
  if (tool.id == 'pdf_merge') {
    return MergeArgs(
      items: [
        for (final f in files)
          MergeItem(
            path: f.path,
            name: f.name,
            isPdf: f.magic == PfMagic.pdf,
          ),
      ],
      outputDir: outputDir,
    );
  }
  // Copy-through fallback for tools whose feature hasn't landed yet.
  return CopyThroughArgs(
    jobs: [
      for (final f in files) (f.path, f.name, f.sizeBytes),
    ],
    outputDir: outputDir,
  );
}

/// Per-tool UI contract.
class ToolUiSpec {
  const ToolUiSpec({
    this.allowedMagic,
    this.maxFiles,
    this.minFiles,
    this.reorderable = false,
    this.optionsBuilder,
  });

  /// Magic types this tool accepts; null = any known type.
  final Set<PfMagic>? allowedMagic;

  /// Max files this tool accepts per job; null = batch tools default.
  final int? maxFiles;

  /// Minimum files required before Start enables; null = 1.
  final int? minFiles;

  /// Whether the file list can be reordered (drag handles).
  final bool reorderable;

  final WidgetBuilder? optionsBuilder;
}

Widget _buildSplitOptions(BuildContext context) => const SplitOptions();

Widget _buildImagesToPdfOptions(BuildContext context) => const ImagesToPdfOptions();

Widget _buildPdfToImagesOptions(BuildContext context) => const PdfToImagesOptions();

Widget _buildOcrOptions(BuildContext context) => const OcrOptions();

Widget _buildImageCompressOptions(BuildContext context) => const ImageCompressOptions();

Widget _buildImageConvertOptions(BuildContext context) => const ImageConvertOptions();

class ImageConvertOptions extends ConsumerWidget {
  const ImageConvertOptions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context)!;
    final target = ref.watch(imageConvertTargetProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(loc.convertToTitle,
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<ImageTarget>(
              segments: const [
                ButtonSegment(value: ImageTarget.jpeg, label: Text('JPG')),
                ButtonSegment(value: ImageTarget.png, label: Text('PNG')),
                ButtonSegment(value: ImageTarget.webp, label: Text('WebP')),
              ],
              selected: {target},
              onSelectionChanged: (s) =>
                  ref.read(imageConvertTargetProvider.notifier).state = s.first,
            ),
          ],
        ),
      ),
    );
  }
}

class ImageCompressOptions extends ConsumerWidget {
  const ImageCompressOptions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context)!;
    final options = ref.watch(imageCompressOptionsProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(loc.qualityTitle, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<ImageQuality>(
              segments: [
                ButtonSegment(value: ImageQuality.low, label: Text(loc.qualityLow)),
                ButtonSegment(value: ImageQuality.medium, label: Text(loc.qualityMedium)),
                ButtonSegment(value: ImageQuality.high, label: Text(loc.qualityHigh)),
              ],
              selected: {options.quality},
              onSelectionChanged: (s) => ref
                  .read(imageCompressOptionsProvider.notifier)
                  .state = options.withQuality(s.first),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(loc.downscaleTitle),
              subtitle: Text(loc.downscaleSubtitle),
              value: options.downscale,
              onChanged: (v) => ref
                  .read(imageCompressOptionsProvider.notifier)
                  .state = options.withDownscale(v),
            ),
          ],
        ),
      ),
    );
  }
}

class PdfToImagesOptions extends ConsumerWidget {
  const PdfToImagesOptions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context)!;
    final options = ref.watch(pdfToImagesOptionsProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(loc.formatTitle, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<PdfToImagesFormat>(
              segments: [
                ButtonSegment(value: PdfToImagesFormat.png, label: const Text('PNG')),
                ButtonSegment(value: PdfToImagesFormat.jpeg, label: const Text('JPG')),
              ],
              selected: {options.format},
              onSelectionChanged: (s) => ref
                  .read(pdfToImagesOptionsProvider.notifier)
                  .state = options.withFormat(s.first),
            ),
            const SizedBox(height: 12),
            Text(loc.dpiTitle(options.dpi),
                style: Theme.of(context).textTheme.titleSmall),
            Slider(
              value: options.dpi.toDouble(),
              min: 72,
              max: 300,
              divisions: 4,
              label: '${options.dpi} DPI',
              onChanged: (v) => ref
                  .read(pdfToImagesOptionsProvider.notifier)
                  .state = options.withDpi(v.round()),
            ),
            TextField(
              controller: options.pagesController,
              decoration: InputDecoration(
                labelText: loc.pagesLabel,
                helperText: loc.pagesHint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OcrOptions extends ConsumerStatefulWidget {
  const OcrOptions({super.key});

  @override
  ConsumerState<OcrOptions> createState() => _OcrOptionsState();
}

class _OcrOptionsState extends ConsumerState<OcrOptions> {
  static const _scripts = [
    ('latin', 'Latin (English, Spanish, French, German, etc.)'),
    ('devanagari', 'Devanagari (हिन्दी / Marathi / Sanskrit)'),
    ('chinese', 'Chinese (中文)'),
    ('japanese', 'Japanese (日本語)'),
    ('korean', 'Korean (한국어)'),
  ];

  @override
  Widget build(BuildContext context) {
    final options = ref.watch(ocrOptionsProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              initialValue: options.script,
              decoration: const InputDecoration(
                labelText: 'Language / Script Model',
                prefixIcon: Icon(Icons.language_rounded),
              ),
              items: [
                for (final (id, label) in _scripts)
                  DropdownMenuItem(
                    value: id,
                    child: Text(label, style: const TextStyle(fontSize: 13)),
                  ),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    options.script = val;
                  });
                }
              },
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              secondary: const Icon(Icons.auto_fix_high_rounded),
              title: const Text('Auto-Enhance for OCR'),
              subtitle: const Text('Lifts shadows and boosts contrast for higher accuracy'),
              value: options.enhanceImage,
              onChanged: (v) {
                setState(() {
                  options.enhanceImage = v;
                });
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              secondary: const Icon(Icons.format_align_left_rounded),
              title: const Text('Preserve Natural Layout'),
              subtitle: const Text('Maintains paragraphs, columns, and line structure'),
              value: options.preserveLayout,
              onChanged: (v) {
                setState(() {
                  options.preserveLayout = v;
                });
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: options.pagesController,
              decoration: const InputDecoration(
                labelText: 'Page Range (PDFs only)',
                helperText: 'e.g. 1-3, 5 (leave blank for all pages or images)',
                prefixIcon: Icon(Icons.pages_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ImagesToPdfOptions extends ConsumerWidget {
  const ImagesToPdfOptions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context)!;
    final fit = ref.watch(imagesToPdfFitProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(loc.fitTitle, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<ImageFit>(
              segments: [
                ButtonSegment(value: ImageFit.imageSize, label: Text(loc.fitImageSize)),
                ButtonSegment(value: ImageFit.a4, label: Text(loc.fitA4)),
              ],
              selected: {fit},
              onSelectionChanged: (s) =>
                  ref.read(imagesToPdfFitProvider.notifier).state = s.first,
            ),
          ],
        ),
      ),
    );
  }
}

class SplitOptions extends ConsumerWidget {
  const SplitOptions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context)!;
    final options = ref.watch(splitOptionsProvider);
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<SplitMode>(
              segments: [
                ButtonSegment(value: SplitMode.everyN, label: Text(loc.splitModeEveryN)),
                ButtonSegment(value: SplitMode.ranges, label: Text(loc.splitModeRanges)),
                ButtonSegment(value: SplitMode.extract, label: Text(loc.splitModeExtract)),
              ],
              selected: {options.mode},
              onSelectionChanged: (s) => ref
                  .read(splitOptionsProvider.notifier)
                  .state = options.publish(s.first),
            ),
            const SizedBox(height: 12),
            // BUGFIX (options out of sync): every field re-publishes the
            // options state on change — previously typing never notified
            // Riverpod, so errorText/Start stayed stale until re-entry.
            switch (options.mode) {
              SplitMode.everyN => TextField(
                  controller: options.intervalController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => ref
                      .read(splitOptionsProvider.notifier)
                      .state = options.publish(options.mode),
                  decoration: InputDecoration(
                    labelText: loc.splitIntervalLabel,
                    errorText: options.intervalValid ? null : loc.splitIntervalError,
                  ),
                ),
              SplitMode.ranges => TextField(
                  controller: options.rangesController,
                  onChanged: (_) => ref
                      .read(splitOptionsProvider.notifier)
                      .state = options.publish(options.mode),
                  decoration: InputDecoration(
                    labelText: loc.splitRangesLabel,
                    helperText: loc.splitRangesHint,
                    errorText: options.rangesValid ? null : loc.splitRangesError,
                  ),
                ),
              SplitMode.extract => TextField(
                  controller: options.selectionController,
                  onChanged: (_) => ref
                      .read(splitOptionsProvider.notifier)
                      .state = options.publish(options.mode),
                  decoration: InputDecoration(
                    labelText: loc.splitSelectionLabel,
                    helperText: loc.splitSelectionHint,
                    errorText: options.selectionValid ? null : loc.splitSelectionError,
                  ),
                ),
            },
            if (!options.valid) ...[
              const SizedBox(height: 8),
              Text(
                loc.splitFixInputHint,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class PdfCompressOptions extends ConsumerWidget {
  const PdfCompressOptions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context)!;
    final quality = ref.watch(pdfCompressQualityProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(loc.qualityTitle, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<PdfCompressQuality>(
              segments: [
                ButtonSegment(value: PdfCompressQuality.low, label: Text(loc.qualityLow)),
                ButtonSegment(value: PdfCompressQuality.medium, label: Text(loc.qualityMedium)),
                ButtonSegment(value: PdfCompressQuality.high, label: Text(loc.qualityHigh)),
              ],
              selected: {quality},
              onSelectionChanged: (s) =>
                  ref.read(pdfCompressQualityProvider.notifier).state = s.first,
            ),
          ],
        ),
      ),
    );
  }
}

class _PickStage extends StatelessWidget {
  const _PickStage({required this.tool, required this.spec, required this.onPick});

  final PfTool tool;
  final ToolUiSpec spec;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  // Gradient icon plate matching the home card language.
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          tool.category.color.withValues(alpha: 0.18),
                          tool.category.color.withValues(alpha: 0.08),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: tool.category.color.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Icon(tool.icon,
                        color: tool.category.color, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      tool.subtitle,
                      style: const TextStyle(
                          fontSize: 15, height: 1.35, letterSpacing: -0.2),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.file_open_rounded),
            label: Text(loc.pickFiles),
          ),
          const Spacer(),
          Text(
            loc.pipelinePreviewNote,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ReadyStage extends StatelessWidget {
  const _ReadyStage({
    required this.files,
    required this.rejections,
    required this.totalBytes,
    required this.spec,
    required this.optionsValid,
    required this.onReorder,
    required this.onStart,
    required this.onPickMore,
  });

  final List<PickedFile> files;
  final List<(String, PureError)> rejections;
  final int totalBytes;
  final ToolUiSpec spec;

  /// Whether the per-tool options state allows starting (split inputs).
  final bool optionsValid;

  final void Function(int oldIndex, int newIndex) onReorder;
  final VoidCallback onStart;
  final VoidCallback onPickMore;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final canStart = files.length >= (spec.minFiles ?? 1) && optionsValid;

    final listSection = spec.reorderable
        ? ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: true,
            itemCount: files.length,
            // onReorderItem passes an already-adjusted newIndex (no manual -1).
            onReorderItem: onReorder,
            itemBuilder: (context, i) {
              final file = files[i];
              return Container(
                key: ValueKey('${file.path}#$i'),
                child: FileChip(name: file.name, sizeBytes: file.sizeBytes),
              );
            },
          )
        : Column(
            children: [
              for (final file in files)
                FileChip(name: file.name, sizeBytes: file.sizeBytes),
            ],
          );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          loc.selectedFiles(files.length, formatMb(totalBytes)),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        listSection,
        if (rejections.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(loc.rejectedFiles, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final (name, error) in rejections)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                dense: true,
                leading: Icon(Icons.warning_amber_rounded,
                    color: Theme.of(context).colorScheme.onErrorContainer),
                title: Text(name),
                subtitle: Text(error.message,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer)),
              ),
            ),
        ],
        if (spec.optionsBuilder != null) ...[
          const SizedBox(height: 16),
          spec.optionsBuilder!(context),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: canStart ? onStart : null,
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(loc.start),
        ),
        if (!canStart) ...[
          const SizedBox(height: 8),
          Text(
            loc.minFilesHint(spec.minFiles ?? 1),
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onPickMore,
          icon: const Icon(Icons.add_rounded),
          label: Text(loc.addMore),
        ),
      ],
    );
  }
}

class _RunningStage extends StatelessWidget {
  const _RunningStage({
    required this.fraction,
    required this.label,
    required this.onCancel,
  });

  final double fraction;
  final String? label;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label ?? loc.processing,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 24),
          LinearProgressIndicator(value: fraction <= 0 ? null : fraction),
          const SizedBox(height: 8),
          Text(
            '${(fraction * 100).toStringAsFixed(0)}%',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 32),
          OutlinedButton.icon(
            onPressed: onCancel,
            icon: const Icon(Icons.close_rounded),
            label: Text(loc.cancel),
          ),
        ],
      ),
    );
  }
}

enum _OutputAction { saveAs, rename }

class _DoneStage extends StatefulWidget {
  const _DoneStage({
    required this.outputs,
    this.rawResult,
  });

  final List<OutputInfo> outputs;
  final Object? rawResult;

  @override
  State<_DoneStage> createState() => _DoneStageState();
}

class _DoneStageState extends State<_DoneStage> {
  late List<OutputInfo> _items;

  @override
  void initState() {
    super.initState();
    _items = List<OutputInfo>.from(widget.outputs);
  }

  @override
  void didUpdateWidget(covariant _DoneStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.outputs != widget.outputs) {
      _items = List<OutputInfo>.from(widget.outputs);
    }
  }

  Future<void> _saveToDevice(OutputInfo output) async {
    final file = File(output.path);
    if (!file.existsSync()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File not found on device')),
      );
      return;
    }

    try {
      final bytes = await file.readAsBytes();
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save to Device',
        fileName: output.name,
        type: FileType.any,
        bytes: bytes,
      );

      if (savePath != null) {
        final targetFile = File(savePath);
        if (!targetFile.existsSync() || targetFile.lengthSync() == 0) {
          await file.copy(savePath);
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved to: ${savePath.split(Platform.pathSeparator).last}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save error: $e')),
      );
    }
  }

  Future<void> _renameOutput(OutputInfo output) async {
    final controller = TextEditingController(text: output.name);
    final formKey = GlobalKey<FormState>();

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename File'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'New name',
              hintText: 'Enter new file name',
            ),
            validator: (val) {
              if (val == null || val.trim().isEmpty) return 'Name cannot be empty';
              if (RegExp(r'[\\/:*?"<>|\x00-\x1f]').hasMatch(val)) {
                return 'Invalid characters in name';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(ctx).pop(controller.text.trim());
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    if (newName != null && newName.trim().isNotEmpty && newName.trim() != output.name) {
      final cleanName = newName.trim();
      final oldFile = File(output.path);
      if (!oldFile.existsSync()) return;

      final dir = oldFile.parent.path;
      final uniquePath = uniqueDestination(dir, cleanName);
      try {
        final renamedFile = await oldFile.rename(uniquePath);
        final actualNewName = renamedFile.path.split(Platform.pathSeparator).last;
        setState(() {
          final idx = _items.indexOf(output);
          if (idx != -1) {
            _items[idx] = OutputInfo(
              path: renamedFile.path,
              name: actualNewName,
              sizeBytes: output.sizeBytes,
              savedPercent: output.savedPercent,
              keptOriginal: output.keptOriginal,
              warning: output.warning,
            );
          }
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Renamed to $actualNewName')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Rename failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    PfHaptics.success();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Icon(Icons.check_circle_rounded, color: scheme.primary, size: 56),
        const SizedBox(height: 8),
        Text(
          loc.doneTitle(_items.length),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (widget.rawResult is OcrResult) ...[
          const SizedBox(height: 16),
          _OcrExtractedTextCard(result: widget.rawResult as OcrResult),
        ],
        for (final output in _items) ...[
          if (output.savedPercent > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                loc.savedPercent(output.savedPercent),
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600),
              ),
            ),
          if (output.keptOriginal)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                loc.keptOriginalNote,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          if (output.warning != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                output.warning!,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: PfColors.warning),
              ),
            ),
        ],
        const SizedBox(height: 16),
        for (final output in _items)
          Card(
            child: ListTile(
              leading: const Icon(Icons.insert_drive_file_rounded),
              title: Text(output.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(formatMb(output.sizeBytes)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: loc.share,
                    icon: const Icon(Icons.share_rounded),
                    onPressed: () {
                      SharePlus.instance.share(
                        ShareParams(files: [XFile(output.path)]),
                      );
                    },
                  ),
                  IconButton(
                    tooltip: loc.open,
                    icon: const Icon(Icons.open_in_new_rounded),
                    onPressed: () => OpenFilex.open(output.path),
                  ),
                  PopupMenuButton<_OutputAction>(
                    icon: const Icon(Icons.more_vert_rounded),
                    tooltip: 'More actions',
                    onSelected: (action) {
                      switch (action) {
                        case _OutputAction.saveAs:
                          _saveToDevice(output);
                        case _OutputAction.rename:
                          _renameOutput(output);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: _OutputAction.saveAs,
                        child: Row(
                          children: [
                            Icon(Icons.download_rounded, size: 20),
                            SizedBox(width: 10),
                            Text('Save to Device'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: _OutputAction.rename,
                        child: Row(
                          children: [
                            Icon(Icons.edit_rounded, size: 20),
                            SizedBox(width: 10),
                            Text('Rename'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _OcrExtractedTextCard extends StatelessWidget {
  const _OcrExtractedTextCard({required this.result});

  final OcrResult result;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = result.extractedText.trim();
    final hasText = text.isNotEmpty && !result.noText;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.text_snippet_rounded,
                    color: scheme.onPrimaryContainer,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Recognized Text',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      if (hasText)
                        Text(
                          '${result.wordCount} words · ${result.characterCount} chars · ${result.pageCount} page(s)',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                    ],
                  ),
                ),
                if (hasText) ...[
                  IconButton.filledTonal(
                    tooltip: 'Copy all text',
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: text));
                      PfHaptics.success();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Recognized text copied to clipboard'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 6),
                  IconButton.filledTonal(
                    tooltip: 'Share text',
                    icon: const Icon(Icons.share_rounded, size: 18),
                    onPressed: () {
                      SharePlus.instance.share(ShareParams(text: text));
                    },
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            if (!hasText)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.errorContainer.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: scheme.error, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'No text was detected on this document. Make sure the document is well-lit and oriented properly.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onErrorContainer,
                            ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                constraints: const BoxConstraints(maxHeight: 220),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Scrollbar(
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    child: SelectableText(
                      text,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontFamily: 'monospace',
                            height: 1.45,
                          ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ErrorStage extends StatelessWidget {
  const _ErrorStage({required this.error, required this.onRetry});

  final PureError error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.error_outline_rounded, color: scheme.error, size: 56),
          const SizedBox(height: 16),
          Text(
            error.message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            error.hint,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(loc.tryAgain),
          ),
        ],
      ),
    );
  }
}

/// go_router builder helper (route: /tools/:toolId).
Widget toolFlowBuilder(BuildContext context, GoRouterState state) {
  final tool = ToolFlowScreen.fromRoute(state.pathParameters['toolId'] ?? '');
  if (tool == null) {
    return Scaffold(
      body: Center(
        child: Text(
          AppLocalizations.of(context)?.unknownTool ?? 'Unknown tool',
        ),
      ),
    );
  }
  return ToolFlowScreen(tool: tool);
}
