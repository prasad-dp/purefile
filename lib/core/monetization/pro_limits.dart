import '../constants.dart';

/// Dynamic limits for PureFile based on user's Pro status.
///
/// Free users get the standard generous offline toolset.
/// Pro users unlock massive file sizes, huge batches, and ultra high DPI.
abstract final class PfProLimits {
  /// Maximum size of a single file in bytes.
  static int maxFileBytes({required bool isPro}) =>
      isPro ? 500 * 1024 * 1024 : PfLimits.maxFileBytes; // 500 MB vs 50 MB

  /// Maximum number of files in one job.
  static int maxBatchFiles({required bool isPro}) =>
      isPro ? 100 : PfLimits.maxBatchFiles; // 100 files vs 30 files

  /// Maximum combined size of a batch job in bytes.
  static int maxBatchBytes({required bool isPro}) =>
      isPro ? 500 * 1024 * 1024 : PfLimits.maxBatchBytes; // 500 MB vs 100 MB

  /// Available DPI presets for PDF to Image conversion.
  static List<double> dpiPresets({required bool isPro}) =>
      isPro ? const [1.0, 2.0, 3.0, 4.0] : const [1.0, 2.0];

  /// Maximum extracted archive size (zip-bomb guard).
  static int maxExtractedBytes({required bool isPro}) =>
      isPro ? 1024 * 1024 * 1024 : PfLimits.maxExtractedBytes; // 1 GB vs 200 MB

  /// Maximum number of saved signatures in Signature Studio library.
  static int maxSavedSignatures({required bool isPro}) =>
      isPro ? 999 : 1;
}
