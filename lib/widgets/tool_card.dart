import 'package:flutter/material.dart';

import '../../core/theme.dart' show PfHaptics, PfMotion;
import '../../core/tools.dart';

/// Home grid card for one tool (docs/design.md — icon chip spec).
/// F19 polish: press-scale animation (springs back on release), category
/// gradient ring on the icon chip, subtle tile sheen in dark mode.
class ToolCard extends StatefulWidget {
  const ToolCard({
    super.key,
    required this.tool,
    required this.onTap,
    this.isPinned = false,
    this.onTogglePin,
  });

  final PfTool tool;
  final VoidCallback onTap;
  final bool isPinned;
  final VoidCallback? onTogglePin;

  @override
  State<ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<ToolCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = widget.tool.category.color;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: PfMotion.fast,
        curve: PfMotion.ease,
        child: Card(
          margin: EdgeInsets.zero,
          child: InkWell(
            onTap: () {
              PfHaptics.tap();
              widget.onTap();
            },
            onLongPress: widget.onTogglePin != null
                ? () {
                    PfHaptics.heavy();
                    widget.onTogglePin!();
                  }
                : null,
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              color.withValues(alpha: 0.16),
                              color.withValues(alpha: 0.07),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(
                            color: color.withValues(alpha: 0.22),
                          ),
                        ),
                        child: Icon(widget.tool.icon, color: color, size: 22),
                      ),
                      const Spacer(),
                      Text(
                        widget.tool.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600, color: scheme.onSurface),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.tool.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (widget.isPinned)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Tooltip(
                      message: 'Pinned',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          PfHaptics.tap();
                          widget.onTogglePin?.call();
                        },
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.amber.withValues(alpha: 0.35),
                              width: 1,
                            ),
                          ),
                          child: const Icon(
                            Icons.star_rounded,
                            size: 16,
                            color: Colors.amber,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
