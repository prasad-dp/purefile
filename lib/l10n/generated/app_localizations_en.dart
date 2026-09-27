// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'PureFile';

  @override
  String get homeSearchHint => 'Search tools';

  @override
  String get privacyBadge => '100% offline — your files never leave this phone';

  @override
  String toolComingSoon(String tool) {
    return '$tool arrives in the next build step';
  }

  @override
  String get categoryPdf => 'PDF';

  @override
  String get categoryImage => 'Images';

  @override
  String get categoryZip => 'ZIP';

  @override
  String get categoryScan => 'Scan';

  @override
  String get categoryOcr => 'OCR';

  @override
  String get categorySign => 'Sign';

  @override
  String get categoryVault => 'Vault';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get appearanceSection => 'Appearance';

  @override
  String get appearanceMode => 'Theme mode';

  @override
  String get appearanceModeBody => 'Choose automatic, light, or dark';

  @override
  String get appearanceAuto => 'Auto';

  @override
  String get appearanceLight => 'Light';

  @override
  String get appearanceDark => 'Dark';

  @override
  String get themeTooltipAutoLight => 'Automatic (day mode) — tap for dark';

  @override
  String get themeTooltipAutoDark => 'Automatic (night mode) — tap for light';

  @override
  String get themeTooltipLight => 'Light theme — tap for dark';

  @override
  String get themeTooltipDark => 'Dark theme — tap for light';

  @override
  String get privacyDashboard => 'Privacy dashboard';

  @override
  String get privacyDashboardBody => 'Files processed · 0 uploaded · crash log';

  @override
  String get aboutTitle => 'About PureFile';

  @override
  String get aboutBody =>
      'PureFile 1.0.0 · 100% offline · no accounts, no uploads';

  @override
  String get onboarding1Title => 'One toolbox for your files';

  @override
  String get onboarding1Body =>
      'Compress, merge, split, convert and pack PDFs, images and ZIPs — all in one private app.';

  @override
  String get onboarding2Title => 'Your files never leave your phone';

  @override
  String get onboarding2Body =>
      'Everything runs on this device. No uploads, no accounts, no tracking — PureFile has no internet permission at all.';

  @override
  String get onboarding3Title => 'Works in airplane mode';

  @override
  String get onboarding3Body =>
      'No cloud needed. Open PureFile anywhere and every tool just works.';

  @override
  String get skip => 'Skip';

  @override
  String get next => 'Next';

  @override
  String get getStarted => 'Get started';

  @override
  String get pickFiles => 'Pick files';

  @override
  String selectedFiles(int count, String size) {
    return '$count files · $size total';
  }

  @override
  String get rejectedFiles => 'These files were rejected';

  @override
  String get start => 'Start';

  @override
  String get addMore => 'Add more files';

  @override
  String get processing => 'Processing…';

  @override
  String get cancel => 'Cancel';

  @override
  String doneTitle(int count) {
    return '$count file(s) ready';
  }

  @override
  String get share => 'Share';

  @override
  String get open => 'Open';

  @override
  String get reset => 'Start over';

  @override
  String get tryAgain => 'Try again';

  @override
  String get pipelinePreviewNote =>
      'Pipeline preview — real per-tool processing arrives with each tool feature.';

  @override
  String get unknownTool => 'Unknown tool';

  @override
  String get qualityTitle => 'Quality';

  @override
  String get qualityLow => 'Low';

  @override
  String get qualityMedium => 'Medium';

  @override
  String get qualityHigh => 'High';

  @override
  String savedPercent(int percent) {
    return 'Saved $percent%';
  }

  @override
  String get keptOriginalNote =>
      'Already optimized — kept your original (no smaller copy was possible).';

  @override
  String minFilesHint(int count) {
    return 'Pick at least $count files to start';
  }

  @override
  String get splitModeEveryN => 'Every N';

  @override
  String get splitModeRanges => 'Ranges';

  @override
  String get splitModeExtract => 'Extract';

  @override
  String get splitIntervalLabel => 'Pages per file';

  @override
  String get splitIntervalError => 'Enter a number of pages of 1 or more';

  @override
  String get splitRangesLabel => 'Page ranges';

  @override
  String get splitRangesHint => 'e.g. 1-3,5,8-10';

  @override
  String get splitRangesError => 'Enter at least one valid range';

  @override
  String get splitSelectionLabel => 'Pages to extract';

  @override
  String get splitSelectionHint => 'e.g. 2,5,9 — each becomes its own PDF';

  @override
  String get splitSelectionError => 'Enter at least one page number';

  @override
  String get splitFixInputHint =>
      'Fix the split options above to enable Start.';

  @override
  String get fitTitle => 'Page size';

  @override
  String get fitImageSize => 'Image size';

  @override
  String get fitA4 => 'A4';

  @override
  String get formatTitle => 'Output format';

  @override
  String dpiTitle(int dpi) {
    return 'Resolution — $dpi DPI';
  }

  @override
  String get pagesLabel => 'Pages (empty = all)';

  @override
  String get pagesHint => 'e.g. 1,3,5';

  @override
  String get downscaleTitle => 'Shrink large photos';

  @override
  String get downscaleSubtitle =>
      'Scale photos over 2560 px down before compressing';

  @override
  String get convertToTitle => 'Convert to';

  @override
  String get historyTitle => 'History';

  @override
  String get historyEmpty =>
      'Files you create with PureFile appear here for 7 days. Stored only on this device.';

  @override
  String get historyClearTitle => 'Clear history';

  @override
  String get historyClearBody =>
      'Remove all entries from this list? The files themselves stay in the app\'s outputs folder.';

  @override
  String get historyClearConfirm => 'Clear';

  @override
  String get vaultTitle => 'Private Vault';

  @override
  String get vaultLockNow => 'Lock now';

  @override
  String get vaultDestroy => 'Destroy vault';

  @override
  String get vaultSecretLabel => 'Secret';

  @override
  String get vaultSecretHint =>
      'At least 8 characters. There is no recovery — if you forget it, the files in the vault are gone.';

  @override
  String get vaultSecretConfirm => 'Confirm secret';

  @override
  String get vaultSetupTitle => 'Create your vault';

  @override
  String get vaultSetupBody =>
      'Files in the vault are encrypted on this device with AES-256-GCM. Your secret never leaves the phone.';

  @override
  String get vaultCreate => 'Create vault';

  @override
  String get vaultLockedTitle => 'Vault locked';

  @override
  String get vaultUnlock => 'Unlock';

  @override
  String get vaultSoftLockTitle => 'Locked while away';

  @override
  String get vaultUnlockBiometrics => 'Unlock with biometrics';

  @override
  String get vaultUseSecret => 'Use secret instead';

  @override
  String get vaultEmpty =>
      'Nothing in your vault yet. Import a file and PureFile will encrypt it and securely erase the original.';

  @override
  String get vaultImport => 'Import file';

  @override
  String get vaultExport => 'Export copy';

  @override
  String get vaultSaveBack => 'Save to device…';

  @override
  String vaultExportDone(String name) {
    return '$name exported to outputs';
  }

  @override
  String get vaultRemoveTitle => 'Remove file';

  @override
  String vaultRemoveBody(String name) {
    return 'Erase “$name” from the vault? The encrypted copy is securely deleted.';
  }

  @override
  String get vaultRemoveConfirm => 'Remove';

  @override
  String get vaultEncryptedNote => 'encrypted on device';

  @override
  String get privacyProcessed => 'files processed';

  @override
  String get privacyUploaded => 'files uploaded';

  @override
  String get privacyFactsTitle => 'Why the 0 stays 0';

  @override
  String get privacyFactOffline =>
      'PureFile has no internet permission — the OS itself blocks any upload.';

  @override
  String get privacyFactNoAccount => 'No accounts, no sign-in, no profile.';

  @override
  String get privacyFactNoTracking => 'No analytics, no ads, no tracking SDKs.';

  @override
  String get privacyTopTools => 'Most used tools';

  @override
  String get storageOutputsTitle => 'Output files on this device';

  @override
  String get storageCalculating => 'Calculating…';

  @override
  String storageOutputsBody(int count, String size) {
    return '$count files · $size in the app\'s outputs folder';
  }

  @override
  String get clearOutputsAction => 'Clear';

  @override
  String get clearOutputsTitle => 'Delete output files?';

  @override
  String get clearOutputsBody =>
      'Removes every file in the outputs folder. History entries will show as expired. Vault files are not touched.';

  @override
  String get clearOutputsConfirm => 'Delete';

  @override
  String get crashLogTitle => 'Crash log';

  @override
  String get crashLogSubtitle => 'Local-only diagnostics · never sent anywhere';

  @override
  String get crashLogEmpty =>
      'No crashes recorded. Nothing diagnostic ever leaves this device.';

  @override
  String get crashLogClearTitle => 'Clear crash log?';

  @override
  String get crashLogClearBody => 'Removes all locally recorded crash entries.';

  @override
  String get crashLogClearConfirm => 'Clear';

  @override
  String get privacyResetAction => 'Reset counters';

  @override
  String get privacyResetTitle => 'Reset privacy counters?';

  @override
  String get privacyResetBody =>
      'The processed-files counters return to zero. Your files are not touched.';

  @override
  String get privacyResetConfirm => 'Reset';

  @override
  String get shareChooserTitle => 'Open with PureFile';

  @override
  String shareChooserCount(int count) {
    return '$count shared file(s) received';
  }

  @override
  String get shareChooserNoTool => 'No tool fits these files';

  @override
  String get shareChooserNoToolBody =>
      'The files may be an unsupported type or too large. Try opening PureFile directly and picking a tool first.';
}
