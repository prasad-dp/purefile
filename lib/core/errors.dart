/// Typed errors for every failure mode in PureFile.
///
/// Contract (docs/edge-cases.md): no silent failures — every error maps to a
/// human message plus a suggested fix. Never surface raw stack traces.
sealed class PureError implements Exception {
  const PureError(this.message, this.hint);

  /// Short human message shown to the user.
  final String message;

  /// Suggested fix shown under the message.
  final String hint;

  @override
  String toString() => '$runtimeType: $message';
}

final class FileTooLarge extends PureError {
  FileTooLarge({required String fileName, required int sizeBytes, required int limitBytes})
      : super(
          '"$fileName" is too large',
          'Limit is one file up to ${formatMb(limitBytes)}. Tip: shrink it with a desktop tool first.',
        );
}

final class BatchTooLarge extends PureError {
  const BatchTooLarge({required int files, required int limit})
      : super(
          'Too many files selected ($files)',
          'You can process up to $limit files in one job.',
        );
}

final class SingleFileOnly extends PureError {
  const SingleFileOnly()
      : super('This tool processes one file at a time',
            'Select a single file and try again.');
}

final class BatchTooHeavy extends PureError {
  BatchTooHeavy({required int totalBytes, required int limitBytes})
      : super(
          'Selection is too heavy (${formatMb(totalBytes)})',
          'Combined limit is ${formatMb(limitBytes)} per job.',
        );
}

final class UnsupportedFormat extends PureError {
  const UnsupportedFormat({required String fileName, required String expected})
      : super(
          '"$fileName" is not a supported $expected file',
          'Check the file and try the right tool for its type.',
        );
}

final class CorruptedFile extends PureError {
  const CorruptedFile({required String fileName, String detail = 'The file is empty or unreadable'})
      : super('"$fileName" could not be read', '$detail. Try re-exporting or re-downloading it.');
}

final class PasswordRequired extends PureError {
  const PasswordRequired({required String fileName})
      : super('"$fileName" is password-protected', 'Enter the password to continue.');
}

final class WrongPassword extends PureError {
  const WrongPassword() : super('Wrong password', 'Check the password and try again.');
}

final class InsufficientStorage extends PureError {
  InsufficientStorage({required int neededBytes, required int freeBytes})
      : super(
          'Not enough storage',
          'Needs about ${formatMb(neededBytes)}, only ${formatMb(freeBytes)} free.',
        );
}

final class JobCancelled extends PureError {
  const JobCancelled() : super('Job cancelled', 'Nothing was saved.');
}

final class JobTimedOut extends PureError {
  const JobTimedOut() : super('This file took too long', 'Try a smaller file or lower quality.');
}

final class ZipSlipDetected extends PureError {
  const ZipSlipDetected({required String entryName})
      : super('Blocked unsafe path in archive', '"$entryName" tried to escape the output folder.');
}

final class ZipBombDetected extends PureError {
  ZipBombDetected({required int declaredBytes})
      : super('Unsafe archive', 'It expands to ${formatMb(declaredBytes)} — above the safety cap.');
}

final class OcrUnavailable extends PureError {
  const OcrUnavailable()
      : super('Text recognition is unavailable on this device',
          'This device lacks Google Play Services. All other tools still work.');
}

final class NoTextFound extends PureError {
  const NoTextFound() : super('No text found', 'The page may be blank or contain only handwriting.');
}

final class UnknownFailure extends PureError {
  const UnknownFailure([String detail = 'Something went wrong'])
      : super(detail, 'Please try again. If it repeats, check Settings → Crash log.');
}

String formatMb(int bytes) {
  final mb = bytes / (1024 * 1024);
  return mb >= 10 ? '${mb.round()} MB' : '${mb.toStringAsFixed(1)} MB';
}
