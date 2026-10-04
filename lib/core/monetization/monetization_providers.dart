import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ads_service.dart';
import 'billing_service.dart';

/// App-wide BillingService singleton provider.
final billingServiceProvider = Provider<BillingService>((ref) {
  final service = BillingService();
  ref.onDispose(service.dispose);
  return service;
});

/// Pro entitlement state notifier.
class ProNotifier extends StateNotifier<bool> {
  ProNotifier(this._billingService) : super(_billingService.isPro) {
    _billingService.proStatusStream.listen((status) {
      if (mounted) {
        state = status;
      }
    });
  }

  final BillingService _billingService;

  Future<void> toggleForTesting() async {
    final next = !state;
    await _billingService.setProStatus(next);
    state = next;
  }

  Future<void> setPro(bool isPro) async {
    await _billingService.setProStatus(isPro);
    state = isPro;
  }
}

/// Reactive provider tracking whether the current user is PureFile Pro.
final isProProvider = StateNotifierProvider<ProNotifier, bool>((ref) {
  final billing = ref.watch(billingServiceProvider);
  return ProNotifier(billing);
});

/// App-wide AdsService singleton provider.
final adsServiceProvider = Provider<AdsService>((ref) {
  final isPro = ref.watch(isProProvider);
  final service = AdsService(isProGetter: () => isPro);
  ref.onDispose(service.dispose);
  return service;
});
