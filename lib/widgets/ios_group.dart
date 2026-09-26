import 'package:flutter/material.dart';

import '../core/theme.dart';

/// iOS "inset grouped" building blocks (F19b): sectioned cards with padded
/// margins, hairline row separators, chevroned list items — the iOS Settings
/// grammar, built with Material widgets so theming stays unified.

/// Side rail for inset groups (iOS 16pt margins).
const pfGroupH = 16.0;

/// One inset-grouped card: rounded 20, floating on the grouped background.
class PfSection extends StatelessWidget {
  const PfSection({super.key, required this.child, this.margin});

  final Widget child;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin ??
          const EdgeInsets.fromLTRB(pfGroupH, 8, pfGroupH, 8),
      child: Card(child: child),
    );
  }
}

/// One row inside a [PfSection]. Rows get hairline separators between them
/// (never above the first or below the last — that's the iOS look).
class PfGroupItem extends StatelessWidget {
  const PfGroupItem({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.showChevron = false,
    this.destructive = false,
    this.first = false,
    this.last = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// iOS Settings chevron (chevron.right equivalent, tinted gray).
  final bool showChevron;

  /// Red text (destructive actions).
  final bool destructive;

  /// Separator control: this row is first/last in its group.
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.2,
                    color: destructive ? PfColors.error : scheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          if (showChevron)
            Icon(Icons.chevron_right_rounded,
                size: 20, color: scheme.outline.withValues(alpha: 0.6)),
        ],
      ),
    );

    final row = onTap != null
        ? InkWell(
            onTap: () {
              PfHaptics.tap();
              onTap!();
            },
            splashFactory: NoSplash.splashFactory,
            highlightColor: scheme.onSurface.withValues(alpha: 0.04),
            child: content,
          )
        : content;

    if (last) return row;
    return Column(
      children: [
        row,
        Divider(
          height: 0.5,
          thickness: 0.5,
          indent: leading != null ? 60 : 16,
          color: PfColors.separator(isDark),
        ),
      ],
    );
  }
}

/// Small gray section header above a group (iOS Settings uppercase-free
/// style: 13pt, secondary color, on the grouped background).
class PfSectionHeader extends StatelessWidget {
  const PfSectionHeader(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(pfGroupH + 16, 16, pfGroupH + 16, 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          letterSpacing: -0.1,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
