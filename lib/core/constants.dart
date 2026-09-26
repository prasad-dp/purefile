/// Single source of truth for every limit in PureFile.
/// See docs/requirements.md — "Limits".
abstract final class PfLimits {
  /// Maximum size of a single input file (50 MB).
  static const int maxFileBytes = 50 * 1024 * 1024;

  /// Maximum number of files in one job.
  static const int maxBatchFiles = 30;

  /// Maximum combined size of one job (100 MB).
  static const int maxBatchBytes = 100 * 1024 * 1024;

  /// A job requires this factor of the input size as free storage.
  static const double minFreeStorageFactor = 2.0;

  /// History entries older than this are purged (days).
  static const int historyPurgeDaysDefault = 30;

  /// DPI presets for PDF→Images.
  static const List<double> dpiPresets = [1.0, 2.0, 3.0];

  /// Default JPEG/WebP quality for image tools.
  static const int imageQualityDefault = 80;

  /// Hard cap on decompressed bytes when extracting an archive (zip-bomb guard).
  static const int maxExtractedBytes = 200 * 1024 * 1024;
}
