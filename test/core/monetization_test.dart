import 'package:flutter_test/flutter_test.dart';
import 'package:purefile/core/monetization/ads_service.dart';
import 'package:purefile/core/monetization/billing_service.dart';
import 'package:purefile/core/monetization/pro_limits.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PfProLimits', () {
    test('resolves free tier limits correctly', () {
      expect(PfProLimits.maxFileBytes(isPro: false), 50 * 1024 * 1024);
      expect(PfProLimits.maxBatchFiles(isPro: false), 30);
      expect(PfProLimits.maxBatchBytes(isPro: false), 100 * 1024 * 1024);
      expect(PfProLimits.dpiPresets(isPro: false), [1.0, 2.0]);
      expect(PfProLimits.maxSavedSignatures(isPro: false), 1);
    });

    test('resolves Pro tier limits correctly', () {
      expect(PfProLimits.maxFileBytes(isPro: true), 500 * 1024 * 1024);
      expect(PfProLimits.maxBatchFiles(isPro: true), 100);
      expect(PfProLimits.maxBatchBytes(isPro: true), 500 * 1024 * 1024);
      expect(PfProLimits.dpiPresets(isPro: true), [1.0, 2.0, 3.0, 4.0]);
      expect(PfProLimits.maxSavedSignatures(isPro: true), 999);
    });
  });

  group('BillingService', () {
    late SharedPreferences prefs;
    late BillingService billing;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      billing = BillingService(prefs: prefs);
      await billing.initialize();
    });

    tearDown(() {
      billing.dispose();
    });

    test('starts as not pro by default', () {
      expect(billing.isPro, isFalse);
    });

    test('populates product options including lifetime and annual', () {
      expect(billing.products, isNotEmpty);
      final productIds = billing.products.map((p) => p.id).toList();
      expect(productIds, contains(PfProductIds.lifetime));
      expect(productIds, contains(PfProductIds.annual));
      expect(productIds, contains(PfProductIds.monthly));
    });

    test('setProStatus updates entitlement and stream', () async {
      final statuses = <bool>[];
      final sub = billing.proStatusStream.listen(statuses.add);

      await billing.setProStatus(true);
      expect(billing.isPro, isTrue);
      expect(prefs.getBool(BillingService.prefKeyIsPro), isTrue);

      await billing.setProStatus(false);
      expect(billing.isPro, isFalse);

      await pumpEventQueue();
      await sub.cancel();
      expect(statuses, contains(true));
      expect(statuses, contains(false));
    });
  });

  group('AdsService', () {
    test('provides official test ad unit ids', () {
      expect(AdsService.bannerAdUnitId, isNotEmpty);
      expect(AdsService.interstitialAdUnitId, isNotEmpty);
    });

    test('never shows interstitial if user is Pro', () async {
      final ads = AdsService(isProGetter: () => true);
      final shown = await ads.showInterstitialIfAllowed();
      expect(shown, isFalse);
      ads.dispose();
    });

    test('throttles interstitials below frequency cap', () async {
      final ads = AdsService(isProGetter: () => false);
      // Completed jobs count is 1 (< 3 jobs required)
      final shown1 = await ads.showInterstitialIfAllowed();
      expect(shown1, isFalse);

      // Completed jobs count is 2 (< 3 jobs required)
      final shown2 = await ads.showInterstitialIfAllowed();
      expect(shown2, isFalse);

      ads.dispose();
    });
  });
}
