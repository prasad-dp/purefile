import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/tools.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../widgets/hero_header.dart';
import '../../widgets/tool_card.dart';

/// Home: gradient hero, iOS-style search, category-sectioned tool grid.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final tools = kPfTools
        .where((t) =>
            _query.isEmpty ||
            t.title.toLowerCase().contains(_query) ||
            t.subtitle.toLowerCase().contains(_query))
        .toList();

    final categories = PfCategory.values
        .where((c) => tools.any((t) => t.category == c))
        .toList();

    final width = MediaQuery.sizeOf(context).width;
    final crossAxisCount = width >= 900 ? 4 : (width >= 560 ? 3 : 2);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverHeroHeader(
            title: loc.appName,
            actions: [
              HeroAction(
                icon: Icons.history_rounded,
                tooltip: loc.historyTitle,
                onPressed: () => context.push('/history'),
              ),
              HeroAction(
                icon: Icons.settings_outlined,
                tooltip: loc.settingsTitle,
                onPressed: () => context.push('/settings'),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // iOS-search-flavored field: filled capsule, leading glass
                  // icon, no borders until focus.
                  TextField(
                    onChanged: (v) =>
                        setState(() => _query = v.trim().toLowerCase()),
                    decoration: InputDecoration(
                      hintText: loc.homeSearchHint,
                      prefixIcon: Icon(Icons.search_rounded,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant),
                      filled: true,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const _PrivacyBadge(),
                ],
              ),
            ),
          ),
          for (final category in categories) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration:
                          BoxDecoration(color: category.color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      categoryLabel(loc, category),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.1,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.3,
                ),
                itemCount: tools.where((t) => t.category == category).length,
                itemBuilder: (context, i) {
                  final tool =
                      tools.where((t) => t.category == category).elementAt(i);
                  return ToolCard(
                    tool: tool,
                    onTap: () => context.push(tool.route),
                  );
                },
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }
}

class _PrivacyBadge extends StatelessWidget {
  const _PrivacyBadge();

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: PfColors.heroGradient,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: PfColors.primaryLight.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.verified_user_rounded, size: 18, color: Colors.white),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              loc.privacyBadge,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

String categoryLabel(AppLocalizations loc, PfCategory category) => switch (category) {
      PfCategory.pdf => loc.categoryPdf,
      PfCategory.image => loc.categoryImage,
      PfCategory.zip => loc.categoryZip,
      PfCategory.scan => loc.categoryScan,
      PfCategory.ocr => loc.categoryOcr,
      PfCategory.sign => loc.categorySign,
      PfCategory.vault => loc.categoryVault,
    };
