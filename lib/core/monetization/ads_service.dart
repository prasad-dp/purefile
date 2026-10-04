import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Service managing AdMob Banner and Interstitial ads with strict frequency capping.
class AdsService {
  AdsService({bool Function()? isProGetter}) : _isProGetter = isProGetter;

  final bool Function()? _isProGetter;

  bool get isPro => _isProGetter?.call() ?? false;

  InterstitialAd? _interstitialAd;
  bool _isInterstitialLoading = false;
  DateTime? _lastInterstitialShownAt;
  int _completedJobsSinceLastAd = 0;

  /// Frequency capping: show at most 1 interstitial per 3 completed jobs.
  static const int minJobsBetweenAds = 3;

  /// Cooldown: at least 3 minutes between interstitials.
  static const Duration minCooldownBetweenAds = Duration(minutes: 3);

  // Official Google AdMob Test Ad Unit IDs
  static String get bannerAdUnitId {
    if (kIsWeb) return '';
    if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/2934735716'; // iOS Banner Test ID
    }
    // Android Banner Test ID (default on Android and tests)
    return 'ca-app-pub-3940256099942544/6300978111';
  }

  static String get interstitialAdUnitId {
    if (kIsWeb) return '';
    if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/4411468910'; // iOS Interstitial Test ID
    }
    // Android Interstitial Test ID (default on Android and tests)
    return 'ca-app-pub-3940256099942544/1033173712';
  }

  /// Initializes AdMob SDK safely.
  Future<void> initialize() async {
    if (isPro || kIsWeb) return;
    try {
      await MobileAds.instance.initialize();
      preloadInterstitial();
    } catch (e) {
      debugPrint('[AdsService] Initialization error: $e');
    }
  }

  /// Preloads an interstitial ad in the background.
  void preloadInterstitial() {
    if (isPro || kIsWeb || _isInterstitialLoading || _interstitialAd != null) {
      return;
    }

    final adUnitId = interstitialAdUnitId;
    if (adUnitId.isEmpty) return;

    _isInterstitialLoading = true;
    InterstitialAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isInterstitialLoading = false;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _interstitialAd = null;
              preloadInterstitial(); // Preload for next time
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _interstitialAd = null;
              preloadInterstitial();
            },
          );
        },
        onAdFailedToLoad: (error) {
          _isInterstitialLoading = false;
          _interstitialAd = null;
          debugPrint('[AdsService] Interstitial failed to load: $error');
        },
      ),
    );
  }

  /// Checks frequency caps and displays the interstitial ad if allowed.
  /// Call this when a file processing job finishes successfully on the Done screen.
  Future<bool> showInterstitialIfAllowed() async {
    if (isPro || kIsWeb) return false;

    _completedJobsSinceLastAd++;

    final now = DateTime.now();
    final cooldownPassed = _lastInterstitialShownAt == null ||
        now.difference(_lastInterstitialShownAt!) >= minCooldownBetweenAds;

    if (_completedJobsSinceLastAd >= minJobsBetweenAds && cooldownPassed) {
      if (_interstitialAd != null) {
        _completedJobsSinceLastAd = 0;
        _lastInterstitialShownAt = now;
        await _interstitialAd!.show();
        return true;
      } else {
        preloadInterstitial();
      }
    }
    return false;
  }

  void dispose() {
    _interstitialAd?.dispose();
    _interstitialAd = null;
  }
}
