import 'package:flutter/material.dart';

import '../core/errors.dart';
import '../core/theme.dart' show PfColors;

/// One picked file with a live size badge — iOS row grammar: tinted plate,
/// quiet metadata, tabular numerals.
class FileChip extends StatelessWidget {
  const FileChip({super.key, required this.name, required this.sizeBytes});

  final String name;
  final int sizeBytes;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        leading: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(9),
          ),
          child: const Icon(Icons.insert_drive_file_outlined,
              size: 18, color: PfColors.primaryLight),
        ),
        title: Text(name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.2)),
        trailing: Text(
          formatMb(sizeBytes),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: scheme.onSurfaceVariant,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
