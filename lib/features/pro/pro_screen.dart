import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/monetization/billing_service.dart';
import '../../core/monetization/monetization_providers.dart';
import '../../core/theme.dart';

/// Premium paywall & subscription management screen for PureFile Pro.
class ProScreen extends ConsumerStatefulWidget {
  const ProScreen({super.key});

  @override
  ConsumerState<ProScreen> createState() => _ProScreenState();
}

class _ProScreenState extends ConsumerState<ProScreen> {
  String _selectedProductId = PfProductIds.lifetime;
  bool _isPurchasing = false;

  @override
  Widget build(BuildContext context) {
    final isPro = ref.watch(isProProvider);
    final billing = ref.watch(billingServiceProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B0F17) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.pop(),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              PfHaptics.tap();
              await billing.restorePurchases();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Purchases restored successfully'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('Restore'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          children: [
            // Pro Crown Badge
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.workspace_premium_rounded,
                  size: 40,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header Title & Subtitle
            const Center(
              child: Text(
                'PureFile Pro',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  isPro
                      ? 'You have unlocked the full power of PureFile. 100% ad-free forever.'
                      : 'Supercharge your offline file toolbox with ultimate file limits and an ad-free experience.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: isDark ? PfColors.textMutedDark : PfColors.textMutedLight,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            if (isPro) ...[
              // Already Pro Banner
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF13221C) : const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF10B981).withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.verified_rounded,
                      color: Color(0xFF10B981),
                      size: 44,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'PureFile Pro Active',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF10B981),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'All Pro limits unlocked · Ads disabled',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? PfColors.textMutedDark : PfColors.textMutedLight,
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: () async {
                        await ref.read(isProProvider.notifier).setPro(false);
                      },
                      child: const Text('Switch to Free (Test Mode)'),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Feature highlights
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF141A24) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? const Color(0xFF242E3D) : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Column(
                  children: const [
                    _FeatureRow(
                      icon: Icons.block_rounded,
                      iconColor: Color(0xFF10B981),
                      title: '100% Ad-Free Experience',
                      subtitle: 'Zero banner or interstitial ads anywhere in the app.',
                    ),
                    Divider(height: 20),
                    _FeatureRow(
                      icon: Icons.speed_rounded,
                      iconColor: Color(0xFF3B82F6),
                      title: '500 MB File Limit',
                      subtitle: 'Process huge 500 MB files (free tier is 50 MB).',
                    ),
                    Divider(height: 20),
                    _FeatureRow(
                      icon: Icons.layers_rounded,
                      iconColor: Color(0xFF8B5CF6),
                      title: '100-File Batches',
                      subtitle: 'Merge and batch compress up to 100 files simultaneously.',
                    ),
                    Divider(height: 20),
                    _FeatureRow(
                      icon: Icons.high_quality_rounded,
                      iconColor: Color(0xFFF59E0B),
                      title: 'Ultra HD 600 DPI',
                      subtitle: 'Studio print quality rendering for PDF to image export.',
                    ),
                    Divider(height: 20),
                    _FeatureRow(
                      icon: Icons.draw_rounded,
                      iconColor: Color(0xFFEC4899),
                      title: 'Unlimited Signatures',
                      subtitle: 'Save and manage all your signatures in Signature Studio.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Plan options
              Text(
                'CHOOSE YOUR PLAN',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: isDark ? PfColors.textMutedDark : PfColors.textMutedLight,
                ),
              ),
              const SizedBox(height: 12),

              ...billing.products.map((product) {
                final isSelected = _selectedProductId == product.id;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    onTap: () {
                      PfHaptics.tap();
                      setState(() => _selectedProductId = product.id);
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF141A24) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFFF59E0B)
                              : isDark
                                  ? const Color(0xFF242E3D)
                                  : const Color(0xFFE2E8F0),
                          width: isSelected ? 2 : 1,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                                  blurRadius: 10,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isSelected
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_unchecked_rounded,
                            color: isSelected
                                ? const Color(0xFFF59E0B)
                                : isDark
                                    ? PfColors.textMutedDark
                                    : PfColors.textMutedLight,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      product.title,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if (product.isPopular) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF59E0B),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          'BEST VALUE',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  product.description,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? PfColors.textMutedDark
                                        : PfColors.textMutedLight,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            product.price,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFF59E0B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 12),

              // Upgrade Button
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _isPurchasing
                    ? null
                    : () async {
                        PfHaptics.tap();
                        setState(() => _isPurchasing = true);
                        try {
                          final selected = billing.products.firstWhere(
                            (p) => p.id == _selectedProductId,
                            orElse: () => billing.products.first,
                          );
                          await billing.purchase(selected);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('PureFile Pro activated! Enjoy unlimited access.'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                            context.pop();
                          }
                        } finally {
                          if (mounted) {
                            setState(() => _isPurchasing = false);
                          }
                        }
                      },
                child: _isPurchasing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Unlock PureFile Pro',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
              const SizedBox(height: 12),

              // Guarantee note
              Center(
                child: Text(
                  '100% Offline processing guarantee · No recurring hidden fees',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? PfColors.textMutedDark : PfColors.textMutedLight,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 20, color: iconColor),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? PfColors.textMutedDark : PfColors.textMutedLight,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
