import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/appearance.dart';
import '../core/theme.dart' show PfHaptics, PfMotion;
import '../l10n/generated/app_localizations.dart';

export '../core/appearance.dart' show toggleThemeMode;

/// Tooltip states the ACTIVE brightness and what tapping does.
String _tooltip(AppLocalizations loc, ThemeMode mode, Brightness active) {
  final activeIsLight = mode == ThemeMode.light ||
      (mode == ThemeMode.system && active == Brightness.light);
  return switch ((mode, activeIsLight)) {
    (ThemeMode.system, true) => loc.themeTooltipAutoLight,
    (ThemeMode.system, false) => loc.themeTooltipAutoDark,
    (_, true) => loc.themeTooltipLight,
    (_, false) => loc.themeTooltipDark,
  };
}

/// The button always shows the ACTIVE brightness: sun in light, moon in dark
/// (system mode included — the dot badge is the "automatic" hint).
IconData _iconFor(ThemeMode mode, Brightness platformBrightness) {
  final activeIsLight = mode == ThemeMode.light ||
      (mode == ThemeMode.system && platformBrightness == Brightness.light);
  return activeIsLight
      ? Icons.light_mode_outlined
      : Icons.dark_mode_outlined;
}

/// The quick theme button (home hero header). One tap always lands on the
/// OPPOSITE brightness — light ⇄ dark from anywhere; Auto shows what's
/// active with a small dot badge and is selectable from Settings. Pure icon,
/// localized tooltip for accessibility.
class ThemeToggleIcon extends ConsumerStatefulWidget {
  const ThemeToggleIcon(
      {super.key, this.size = 20, this.color, this.background});

  final double size;

  /// Icon tint — set it when the toggle sits on a colored surface (hero
  /// gradient); defaults to the theme's icon color.
  final Color? color;

  /// Fill behind the icon (hero-header glass circle). Null = no fill. Also
  /// used to punch out the auto-dot badge border.
  final Color? background;

  @override
  ConsumerState<ThemeToggleIcon> createState() => _ThemeToggleIconState();
}

class _ThemeToggleIconState extends ConsumerState<ThemeToggleIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;
  ThemeMode? _lastMode;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
        vsync: this, duration: PfMotion.slow, value: 1.0);
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final mode = ref.watch(themeModeProvider);
    final controller = ref.read(themeModeProvider.notifier);
    final platformBrightness = MediaQuery.platformBrightnessOf(context);

    // Morph (spin + fade) whenever the MODE changes. A system-brightness
    // flip alone changes the glyph, not the mode — AnimatedSwitcher below
    // cross-fades that without the full spin.
    if (_lastMode != null && _lastMode != mode) {
      _spin.forward(from: 0.0);
    }
    _lastMode = mode;

    return RotationTransition(
      turns: _spin,
      child: FadeTransition(
        opacity: _spin,
        child: IconButton(
          tooltip: _tooltip(loc, mode, platformBrightness),
          style: widget.background == null
              ? null
              : IconButton.styleFrom(backgroundColor: widget.background),
          onPressed: () {
            PfHaptics.tap();
            controller.setMode(
                toggleThemeMode(mode, platformBrightness));
          },
          icon: _BadgeIcon(
            showDot: mode == ThemeMode.system,
            borderColor: widget.background ??
                Theme.of(context).scaffoldBackgroundColor,
            child: AnimatedSwitcher(
              duration: PfMotion.fast,
              child: Icon(
                _iconFor(mode, platformBrightness),
                key: ValueKey((mode, platformBrightness)),
                size: widget.size,
                color: widget.color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Wraps the icon with the tiny "automatic" dot badge (bottom-right) shown
/// only while the mode is system-driven.
class _BadgeIcon extends StatelessWidget {
  const _BadgeIcon({
    required this.child,
    required this.showDot,
    required this.borderColor,
  });

  final Widget child;
  final bool showDot;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    if (!showDot) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.primary,
              border: Border.all(color: borderColor, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

/// Standalone appearance toggle (app-bar actions). Same direct light ⇄ dark
/// rule; shows the active brightness. Auto stays in Settings.
class ThemeToggleButton extends ConsumerWidget {
  const ThemeToggleButton({super.key, this.color, this.size = 22});

  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context)!;
    final mode = ref.watch(themeModeProvider);
    final controller = ref.read(themeModeProvider.notifier);
    final platformBrightness = MediaQuery.platformBrightnessOf(context);

    return IconButton(
      tooltip: _tooltip(loc, mode, platformBrightness),
      onPressed: () {
        PfHaptics.tap();
        controller.setMode(toggleThemeMode(mode, platformBrightness));
      },
      icon: AnimatedSwitcher(
        duration: PfMotion.normal,
        switchInCurve: PfMotion.ease,
        switchOutCurve: PfMotion.ease,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: ScaleTransition(scale: anim, child: child),
        ),
        child: Icon(
          _iconFor(mode, platformBrightness),
          key: ValueKey((mode, platformBrightness)),
          size: size,
          color: color,
        ),
      ),
    );
  }
}
