import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Product IDs registered in Google Play Console / Apple App Store.
abstract final class PfProductIds {
  static const String lifetime = 'purefile_pro_lifetime';
  static const String annual = 'purefile_pro_annual';
  static const String monthly = 'purefile_pro_monthly';

  static const Set<String> all = {lifetime, annual, monthly};
}

/// Normalized product display model.
class PfProductItem {
  const PfProductItem({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    this.rawDetails,
    this.isPopular = false,
  });

  final String id;
  final String title;
  final String description;
  final String price;
  final ProductDetails? rawDetails;
  final bool isPopular;
}

/// Billing service managing In-App Purchases and Pro entitlement state.
class BillingService {
  BillingService({SharedPreferences? prefs, InAppPurchase? iap})
      : _prefs = prefs,
        _iap = iap ?? InAppPurchase.instance;

  static const String prefKeyIsPro = 'pf.monetization.is_pro';

  SharedPreferences? _prefs;
  final InAppPurchase _iap;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  final _proStatusController = StreamController<bool>.broadcast();
  Stream<bool> get proStatusStream => _proStatusController.stream;

  bool _isPro = false;
  bool get isPro => _isPro;

  List<PfProductItem> _products = [];
  List<PfProductItem> get products => _products;

  bool _isAvailable = false;
  bool get isAvailable => _isAvailable;

  /// Initializes billing, listens to purchase stream, and loads cached entitlement.
  Future<void> initialize() async {
    _prefs ??= await SharedPreferences.getInstance();
    _isPro = _prefs?.getBool(prefKeyIsPro) ?? false;
    _proStatusController.add(_isPro);

    try {
      _isAvailable = await _iap.isAvailable();
      if (_isAvailable) {
        _subscription = _iap.purchaseStream.listen(
          _handlePurchaseUpdates,
          onError: (error) {
            debugPrint('[BillingService] Purchase stream error: $error');
          },
        );
        await loadProducts();
      } else {
        _populateFallbackProducts();
      }
    } catch (e) {
      debugPrint('[BillingService] Initialization error: $e');
      _populateFallbackProducts();
    }
  }

  /// Loads registered products from store or populates fallbacks.
  Future<void> loadProducts() async {
    try {
      final response = await _iap.queryProductDetails(PfProductIds.all);
      if (response.productDetails.isNotEmpty) {
        _products = response.productDetails.map((details) {
          final isLifetime = details.id == PfProductIds.lifetime;
          return PfProductItem(
            id: details.id,
            title: isLifetime
                ? 'Lifetime Unlock'
                : details.id == PfProductIds.annual
                    ? 'Annual Plan'
                    : 'Monthly Plan',
            description: isLifetime
                ? 'Pay once, own PureFile Pro forever'
                : details.id == PfProductIds.annual
                    ? 'Best value: 12 months with 3-day free trial'
                    : 'Flexible monthly billing, cancel anytime',
            price: details.price,
            rawDetails: details,
            isPopular: isLifetime,
          );
        }).toList();

        // Sort so Lifetime is featured first
        _products.sort((a, b) {
          if (a.id == PfProductIds.lifetime) return -1;
          if (b.id == PfProductIds.lifetime) return 1;
          return 0;
        });
      } else {
        _populateFallbackProducts();
      }
    } catch (_) {
      _populateFallbackProducts();
    }
  }

  void _populateFallbackProducts() {
    final isIndia = isIndiaLocale();
    if (isIndia) {
      _products = const [
        PfProductItem(
          id: PfProductIds.lifetime,
          title: 'Lifetime Unlock',
          description: 'Pay once, own PureFile Pro forever · All features',
          price: '₹49',
          isPopular: true,
        ),
        PfProductItem(
          id: PfProductIds.annual,
          title: 'Annual Plan',
          description: '₹2.4/month · Billed annually with 3-day trial',
          price: '₹29/yr',
          isPopular: false,
        ),
        PfProductItem(
          id: PfProductIds.monthly,
          title: 'Monthly Plan',
          description: 'Flexible monthly billing · Cancel anytime',
          price: '₹9/mo',
          isPopular: false,
        ),
      ];
    } else {
      // Global Purchasing Power Parity (PPP) adjusted pricing
      _products = const [
        PfProductItem(
          id: PfProductIds.lifetime,
          title: 'Lifetime Unlock',
          description: 'Pay once, own PureFile Pro forever · PPP Adjusted',
          price: '\$2.99',
          isPopular: true,
        ),
        PfProductItem(
          id: PfProductIds.annual,
          title: 'Annual Plan',
          description: '\$0.16/month · Billed annually with 3-day trial',
          price: '\$1.99/yr',
          isPopular: false,
        ),
        PfProductItem(
          id: PfProductIds.monthly,
          title: 'Monthly Plan',
          description: 'Flexible monthly billing · Cancel anytime',
          price: '\$0.49/mo',
          isPopular: false,
        ),
      ];
    }
  }

  /// Detects whether the current device is in the India region.
  static bool isIndiaLocale([String? overrideLocale]) {
    try {
      final loc = (overrideLocale ?? (kIsWeb ? '' : Platform.localeName)).toUpperCase();
      return loc.endsWith('_IN') || loc.endsWith('-IN') || loc.contains('IN');
    } catch (_) {
      return false;
    }
  }

  /// Initiates purchase flow.
  Future<bool> purchase(PfProductItem item) async {
    if (item.rawDetails == null || !_isAvailable) {
      // In offline / simulator / test environments, toggle Pro directly for testing.
      await setProStatus(true);
      return true;
    }

    final purchaseParam = PurchaseParam(productDetails: item.rawDetails!);
    if (item.id == PfProductIds.lifetime) {
      return await _iap.buyNonConsumable(purchaseParam: purchaseParam);
    } else {
      return await _iap.buyNonConsumable(purchaseParam: purchaseParam);
    }
  }

  /// Restores previous purchases for existing users.
  Future<void> restorePurchases() async {
    if (!_isAvailable) {
      return;
    }
    try {
      await _iap.restorePurchases();
    } catch (e) {
      debugPrint('[BillingService] Restore purchases error: $e');
    }
  }

  Future<void> _handlePurchaseUpdates(List<PurchaseDetails> purchaseDetailsList) async {
    for (final purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        // Pending transaction
      } else if (purchaseDetails.status == PurchaseStatus.error) {
        debugPrint('[BillingService] Purchase failed: ${purchaseDetails.error}');
      } else if (purchaseDetails.status == PurchaseStatus.purchased ||
          purchaseDetails.status == PurchaseStatus.restored) {
        if (PfProductIds.all.contains(purchaseDetails.productID)) {
          await setProStatus(true);
        }
        if (purchaseDetails.pendingCompletePurchase) {
          await _iap.completePurchase(purchaseDetails);
        }
      }
    }
  }

  /// Updates Pro status and persists to SharedPreferences.
  Future<void> setProStatus(bool isPro) async {
    _isPro = isPro;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs?.setBool(prefKeyIsPro, isPro);
    _proStatusController.add(isPro);
  }

  void dispose() {
    _subscription?.cancel();
    _proStatusController.close();
  }
}
