import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'PureFile'**
  String get appName;

  /// No description provided for @homeSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search tools'**
  String get homeSearchHint;

  /// No description provided for @privacyBadge.
  ///
  /// In en, this message translates to:
  /// **'100% offline — your files never leave this phone'**
  String get privacyBadge;

  /// No description provided for @toolComingSoon.
  ///
  /// In en, this message translates to:
  /// **'{tool} arrives in the next build step'**
  String toolComingSoon(String tool);

  /// No description provided for @categoryPdf.
  ///
  /// In en, this message translates to:
  /// **'PDF'**
  String get categoryPdf;

  /// No description provided for @categoryImage.
  ///
  /// In en, this message translates to:
  /// **'Images'**
  String get categoryImage;

  /// No description provided for @categoryZip.
  ///
  /// In en, this message translates to:
  /// **'ZIP'**
  String get categoryZip;

  /// No description provided for @categoryScan.
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get categoryScan;

  /// No description provided for @categoryOcr.
  ///
  /// In en, this message translates to:
  /// **'OCR'**
  String get categoryOcr;

  /// No description provided for @categorySign.
  ///
  /// In en, this message translates to:
  /// **'Sign'**
  String get categorySign;

  /// No description provided for @categoryVault.
  ///
  /// In en, this message translates to:
  /// **'Vault'**
  String get categoryVault;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @appearanceSection.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearanceSection;

  /// No description provided for @appearanceMode.
  ///
  /// In en, this message translates to:
  /// **'Theme mode'**
  String get appearanceMode;

  /// No description provided for @appearanceModeBody.
  ///
  /// In en, this message translates to:
  /// **'Choose automatic, light, or dark'**
  String get appearanceModeBody;

  /// No description provided for @appearanceAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get appearanceAuto;

  /// No description provided for @appearanceLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get appearanceLight;

  /// No description provided for @appearanceDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get appearanceDark;

  /// No description provided for @themeTooltipAutoLight.
  ///
  /// In en, this message translates to:
  /// **'Automatic (day mode) — tap for dark'**
  String get themeTooltipAutoLight;

  /// No description provided for @themeTooltipAutoDark.
  ///
  /// In en, this message translates to:
  /// **'Automatic (night mode) — tap for light'**
  String get themeTooltipAutoDark;

  /// No description provided for @themeTooltipLight.
  ///
  /// In en, this message translates to:
  /// **'Light theme — tap for dark'**
  String get themeTooltipLight;

  /// No description provided for @themeTooltipDark.
  ///
  /// In en, this message translates to:
  /// **'Dark theme — tap for light'**
  String get themeTooltipDark;

  /// No description provided for @privacyDashboard.
  ///
  /// In en, this message translates to:
  /// **'Privacy dashboard'**
  String get privacyDashboard;

  /// No description provided for @privacyDashboardBody.
  ///
  /// In en, this message translates to:
  /// **'Files processed · 0 uploaded · crash log'**
  String get privacyDashboardBody;

  /// No description provided for @aboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About PureFile'**
  String get aboutTitle;

  /// No description provided for @aboutBody.
  ///
  /// In en, this message translates to:
  /// **'PureFile 1.0.0 · 100% offline · no accounts, no uploads'**
  String get aboutBody;

  /// No description provided for @onboarding1Title.
  ///
  /// In en, this message translates to:
  /// **'One toolbox for your files'**
  String get onboarding1Title;

  /// No description provided for @onboarding1Body.
  ///
  /// In en, this message translates to:
  /// **'Compress, merge, split, convert and pack PDFs, images and ZIPs — all in one private app.'**
  String get onboarding1Body;

  /// No description provided for @onboarding2Title.
  ///
  /// In en, this message translates to:
  /// **'Your files never leave your phone'**
  String get onboarding2Title;

  /// No description provided for @onboarding2Body.
  ///
  /// In en, this message translates to:
  /// **'Everything runs on this device. No uploads, no accounts, no tracking — PureFile has no internet permission at all.'**
  String get onboarding2Body;

  /// No description provided for @onboarding3Title.
  ///
  /// In en, this message translates to:
  /// **'Works in airplane mode'**
  String get onboarding3Title;

  /// No description provided for @onboarding3Body.
  ///
  /// In en, this message translates to:
  /// **'No cloud needed. Open PureFile anywhere and every tool just works.'**
  String get onboarding3Body;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @getStarted.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get getStarted;

  /// No description provided for @pickFiles.
  ///
  /// In en, this message translates to:
  /// **'Pick files'**
  String get pickFiles;

  /// No description provided for @selectedFiles.
  ///
  /// In en, this message translates to:
  /// **'{count} files · {size} total'**
  String selectedFiles(int count, String size);

  /// No description provided for @rejectedFiles.
  ///
  /// In en, this message translates to:
  /// **'These files were rejected'**
  String get rejectedFiles;

  /// No description provided for @start.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get start;

  /// No description provided for @addMore.
  ///
  /// In en, this message translates to:
  /// **'Add more files'**
  String get addMore;

  /// No description provided for @processing.
  ///
  /// In en, this message translates to:
  /// **'Processing…'**
  String get processing;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @doneTitle.
  ///
  /// In en, this message translates to:
  /// **'{count} file(s) ready'**
  String doneTitle(int count);

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @reset.
  ///
  /// In en, this message translates to:
  /// **'Start over'**
  String get reset;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// No description provided for @pipelinePreviewNote.
  ///
  /// In en, this message translates to:
  /// **'Pipeline preview — real per-tool processing arrives with each tool feature.'**
  String get pipelinePreviewNote;

  /// No description provided for @unknownTool.
  ///
  /// In en, this message translates to:
  /// **'Unknown tool'**
  String get unknownTool;

  /// No description provided for @qualityTitle.
  ///
  /// In en, this message translates to:
  /// **'Quality'**
  String get qualityTitle;

  /// No description provided for @qualityLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get qualityLow;

  /// No description provided for @qualityMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get qualityMedium;

  /// No description provided for @qualityHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get qualityHigh;

  /// No description provided for @savedPercent.
  ///
  /// In en, this message translates to:
  /// **'Saved {percent}%'**
  String savedPercent(int percent);

  /// No description provided for @keptOriginalNote.
  ///
  /// In en, this message translates to:
  /// **'Already optimized — kept your original (no smaller copy was possible).'**
  String get keptOriginalNote;

  /// No description provided for @minFilesHint.
  ///
  /// In en, this message translates to:
  /// **'Pick at least {count} files to start'**
  String minFilesHint(int count);

  /// No description provided for @splitModeEveryN.
  ///
  /// In en, this message translates to:
  /// **'Every N'**
  String get splitModeEveryN;

  /// No description provided for @splitModeRanges.
  ///
  /// In en, this message translates to:
  /// **'Ranges'**
  String get splitModeRanges;

  /// No description provided for @splitModeExtract.
  ///
  /// In en, this message translates to:
  /// **'Extract'**
  String get splitModeExtract;

  /// No description provided for @splitIntervalLabel.
  ///
  /// In en, this message translates to:
  /// **'Pages per file'**
  String get splitIntervalLabel;

  /// No description provided for @splitIntervalError.
  ///
  /// In en, this message translates to:
  /// **'Enter a number of pages of 1 or more'**
  String get splitIntervalError;

  /// No description provided for @splitRangesLabel.
  ///
  /// In en, this message translates to:
  /// **'Page ranges'**
  String get splitRangesLabel;

  /// No description provided for @splitRangesHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 1-3,5,8-10'**
  String get splitRangesHint;

  /// No description provided for @splitRangesError.
  ///
  /// In en, this message translates to:
  /// **'Enter at least one valid range'**
  String get splitRangesError;

  /// No description provided for @splitSelectionLabel.
  ///
  /// In en, this message translates to:
  /// **'Pages to extract'**
  String get splitSelectionLabel;

  /// No description provided for @splitSelectionHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 2,5,9 — each becomes its own PDF'**
  String get splitSelectionHint;

  /// No description provided for @splitSelectionError.
  ///
  /// In en, this message translates to:
  /// **'Enter at least one page number'**
  String get splitSelectionError;

  /// No description provided for @splitFixInputHint.
  ///
  /// In en, this message translates to:
  /// **'Fix the split options above to enable Start.'**
  String get splitFixInputHint;

  /// No description provided for @fitTitle.
  ///
  /// In en, this message translates to:
  /// **'Page size'**
  String get fitTitle;

  /// No description provided for @fitImageSize.
  ///
  /// In en, this message translates to:
  /// **'Image size'**
  String get fitImageSize;

  /// No description provided for @fitA4.
  ///
  /// In en, this message translates to:
  /// **'A4'**
  String get fitA4;

  /// No description provided for @formatTitle.
  ///
  /// In en, this message translates to:
  /// **'Output format'**
  String get formatTitle;

  /// No description provided for @dpiTitle.
  ///
  /// In en, this message translates to:
  /// **'Resolution — {dpi} DPI'**
  String dpiTitle(int dpi);

  /// No description provided for @pagesLabel.
  ///
  /// In en, this message translates to:
  /// **'Pages (empty = all)'**
  String get pagesLabel;

  /// No description provided for @pagesHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 1,3,5'**
  String get pagesHint;

  /// No description provided for @downscaleTitle.
  ///
  /// In en, this message translates to:
  /// **'Shrink large photos'**
  String get downscaleTitle;

  /// No description provided for @downscaleSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Scale photos over 2560 px down before compressing'**
  String get downscaleSubtitle;

  /// No description provided for @convertToTitle.
  ///
  /// In en, this message translates to:
  /// **'Convert to'**
  String get convertToTitle;

  /// No description provided for @historyTitle.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get historyTitle;

  /// No description provided for @historyEmpty.
  ///
  /// In en, this message translates to:
  /// **'Files you create with PureFile appear here for 7 days. Stored only on this device.'**
  String get historyEmpty;

  /// No description provided for @historyClearTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear history'**
  String get historyClearTitle;

  /// No description provided for @historyClearBody.
  ///
  /// In en, this message translates to:
  /// **'Remove all entries from this list? The files themselves stay in the app\'s outputs folder.'**
  String get historyClearBody;

  /// No description provided for @historyClearConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get historyClearConfirm;

  /// No description provided for @vaultTitle.
  ///
  /// In en, this message translates to:
  /// **'Private Vault'**
  String get vaultTitle;

  /// No description provided for @vaultLockNow.
  ///
  /// In en, this message translates to:
  /// **'Lock now'**
  String get vaultLockNow;

  /// No description provided for @vaultDestroy.
  ///
  /// In en, this message translates to:
  /// **'Destroy vault'**
  String get vaultDestroy;

  /// No description provided for @vaultSecretLabel.
  ///
  /// In en, this message translates to:
  /// **'Secret'**
  String get vaultSecretLabel;

  /// No description provided for @vaultSecretHint.
  ///
  /// In en, this message translates to:
  /// **'At least 8 characters. There is no recovery — if you forget it, the files in the vault are gone.'**
  String get vaultSecretHint;

  /// No description provided for @vaultSecretConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm secret'**
  String get vaultSecretConfirm;

  /// No description provided for @vaultSetupTitle.
  ///
  /// In en, this message translates to:
  /// **'Create your vault'**
  String get vaultSetupTitle;

  /// No description provided for @vaultSetupBody.
  ///
  /// In en, this message translates to:
  /// **'Files in the vault are encrypted on this device with AES-256-GCM. Your secret never leaves the phone.'**
  String get vaultSetupBody;

  /// No description provided for @vaultCreate.
  ///
  /// In en, this message translates to:
  /// **'Create vault'**
  String get vaultCreate;

  /// No description provided for @vaultLockedTitle.
  ///
  /// In en, this message translates to:
  /// **'Vault locked'**
  String get vaultLockedTitle;

  /// No description provided for @vaultUnlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get vaultUnlock;

  /// No description provided for @vaultSoftLockTitle.
  ///
  /// In en, this message translates to:
  /// **'Locked while away'**
  String get vaultSoftLockTitle;

  /// No description provided for @vaultUnlockBiometrics.
  ///
  /// In en, this message translates to:
  /// **'Unlock with biometrics'**
  String get vaultUnlockBiometrics;

  /// No description provided for @vaultUseSecret.
  ///
  /// In en, this message translates to:
  /// **'Use secret instead'**
  String get vaultUseSecret;

  /// No description provided for @vaultEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing in your vault yet. Import a file and PureFile will encrypt it and securely erase the original.'**
  String get vaultEmpty;

  /// No description provided for @vaultImport.
  ///
  /// In en, this message translates to:
  /// **'Import file'**
  String get vaultImport;

  /// No description provided for @vaultExport.
  ///
  /// In en, this message translates to:
  /// **'Export copy'**
  String get vaultExport;

  /// No description provided for @vaultSaveBack.
  ///
  /// In en, this message translates to:
  /// **'Save to device…'**
  String get vaultSaveBack;

  /// No description provided for @vaultExportDone.
  ///
  /// In en, this message translates to:
  /// **'{name} exported to outputs'**
  String vaultExportDone(String name);

  /// No description provided for @vaultRemoveTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove file'**
  String get vaultRemoveTitle;

  /// No description provided for @vaultRemoveBody.
  ///
  /// In en, this message translates to:
  /// **'Erase “{name}” from the vault? The encrypted copy is securely deleted.'**
  String vaultRemoveBody(String name);

  /// No description provided for @vaultRemoveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get vaultRemoveConfirm;

  /// No description provided for @vaultEncryptedNote.
  ///
  /// In en, this message translates to:
  /// **'encrypted on device'**
  String get vaultEncryptedNote;

  /// No description provided for @privacyProcessed.
  ///
  /// In en, this message translates to:
  /// **'files processed'**
  String get privacyProcessed;

  /// No description provided for @privacyUploaded.
  ///
  /// In en, this message translates to:
  /// **'files uploaded'**
  String get privacyUploaded;

  /// No description provided for @privacyFactsTitle.
  ///
  /// In en, this message translates to:
  /// **'Why the 0 stays 0'**
  String get privacyFactsTitle;

  /// No description provided for @privacyFactOffline.
  ///
  /// In en, this message translates to:
  /// **'PureFile has no internet permission — the OS itself blocks any upload.'**
  String get privacyFactOffline;

  /// No description provided for @privacyFactNoAccount.
  ///
  /// In en, this message translates to:
  /// **'No accounts, no sign-in, no profile.'**
  String get privacyFactNoAccount;

  /// No description provided for @privacyFactNoTracking.
  ///
  /// In en, this message translates to:
  /// **'No analytics, no ads, no tracking SDKs.'**
  String get privacyFactNoTracking;

  /// No description provided for @privacyTopTools.
  ///
  /// In en, this message translates to:
  /// **'Most used tools'**
  String get privacyTopTools;

  /// No description provided for @storageOutputsTitle.
  ///
  /// In en, this message translates to:
  /// **'Output files on this device'**
  String get storageOutputsTitle;

  /// No description provided for @storageCalculating.
  ///
  /// In en, this message translates to:
  /// **'Calculating…'**
  String get storageCalculating;

  /// No description provided for @storageOutputsBody.
  ///
  /// In en, this message translates to:
  /// **'{count} files · {size} in the app\'s outputs folder'**
  String storageOutputsBody(int count, String size);

  /// No description provided for @clearOutputsAction.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clearOutputsAction;

  /// No description provided for @clearOutputsTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete output files?'**
  String get clearOutputsTitle;

  /// No description provided for @clearOutputsBody.
  ///
  /// In en, this message translates to:
  /// **'Removes every file in the outputs folder. History entries will show as expired. Vault files are not touched.'**
  String get clearOutputsBody;

  /// No description provided for @clearOutputsConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get clearOutputsConfirm;

  /// No description provided for @crashLogTitle.
  ///
  /// In en, this message translates to:
  /// **'Crash log'**
  String get crashLogTitle;

  /// No description provided for @crashLogSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Local-only diagnostics · never sent anywhere'**
  String get crashLogSubtitle;

  /// No description provided for @crashLogEmpty.
  ///
  /// In en, this message translates to:
  /// **'No crashes recorded. Nothing diagnostic ever leaves this device.'**
  String get crashLogEmpty;

  /// No description provided for @crashLogClearTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear crash log?'**
  String get crashLogClearTitle;

  /// No description provided for @crashLogClearBody.
  ///
  /// In en, this message translates to:
  /// **'Removes all locally recorded crash entries.'**
  String get crashLogClearBody;

  /// No description provided for @crashLogClearConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get crashLogClearConfirm;

  /// No description provided for @privacyResetAction.
  ///
  /// In en, this message translates to:
  /// **'Reset counters'**
  String get privacyResetAction;

  /// No description provided for @privacyResetTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset privacy counters?'**
  String get privacyResetTitle;

  /// No description provided for @privacyResetBody.
  ///
  /// In en, this message translates to:
  /// **'The processed-files counters return to zero. Your files are not touched.'**
  String get privacyResetBody;

  /// No description provided for @privacyResetConfirm.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get privacyResetConfirm;

  /// No description provided for @shareChooserTitle.
  ///
  /// In en, this message translates to:
  /// **'Open with PureFile'**
  String get shareChooserTitle;

  /// No description provided for @shareChooserCount.
  ///
  /// In en, this message translates to:
  /// **'{count} shared file(s) received'**
  String shareChooserCount(int count);

  /// No description provided for @shareChooserNoTool.
  ///
  /// In en, this message translates to:
  /// **'No tool fits these files'**
  String get shareChooserNoTool;

  /// No description provided for @shareChooserNoToolBody.
  ///
  /// In en, this message translates to:
  /// **'The files may be an unsupported type or too large. Try opening PureFile directly and picking a tool first.'**
  String get shareChooserNoToolBody;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
