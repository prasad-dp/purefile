import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Crafted hero header (F19b): the brand gradient flows behind a large title
/// with icon actions. iOS "large title" grammar with PureFile's gradient.
class HeroHeader extends StatelessWidget {
  const HeroHeader({
    super.key,
    required this.title,
    required List<HeroAction> actions,
  }) : _actions = actions; // ignore: prefer_initializing_formals

  final String title;
  final List<HeroAction> _actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: PfColors.heroGradient),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 12, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.9,
                    color: Colors.white,
                  ),
                ),
              ),
              for (final action in _actions)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: IconButton(
                    onPressed: action.onPressed,
                    tooltip: action.tooltip,
                    // White-tinted circles keep the actions legible on the
                    // gradient (iOS-style tinted icon buttons).
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.16),
                    ),
                    icon: Icon(action.icon, size: 20, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Descriptor so call sites don't build raw widgets per action.
class HeroAction {
  const HeroAction({required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
}

/// Convenience so the header can live inside a CustomScrollView sliver.
class SliverHeroHeader extends SliverToBoxAdapter {
  SliverHeroHeader({
    super.key,
    required String title,
    required List<HeroAction> actions,
  }) : super(
          child: HeroHeader(title: title, actions: actions),
        );
}

/// Unused-import guard for the analyzer on some Flutter versions.
typedef HeroHeaderWidget = HeroHeader;
