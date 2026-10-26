import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/ableton_provider.dart';
import '../providers/locator_groups_provider.dart';
import '../theme/app_theme.dart';
import 'tap_scale.dart';

/// Compact row of numbered scene chips for the app bar. Tapping an assigned
/// chip switches to its setlist; an unassigned chip calls [onAssign].
class SceneChips extends StatelessWidget {
  final void Function(int index) onAssign;
  const SceneChips({super.key, required this.onAssign});

  @override
  Widget build(BuildContext context) {
    final groups = context.watch<LocatorGroupsProvider>();
    final col = context.col;
    final scenes = groups.scenes;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: col.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: col.border),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < scenes.length; i++)
              _Chip(
                index: i,
                name: scenes[i].name,
                setlistName: groups.setlistForScene(i)?.name,
                active: groups.isSceneActive(i),
                onTap: () async {
                  if (groups.setlistForScene(i) == null) {
                    onAssign(i);
                    return;
                  }
                  if (groups.isSceneActive(i)) return;
                  final ableton = context.read<AbletonProvider>();
                  await groups.activateScene(i);
                  ableton.selectStartOfSetlist();
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final int index;
  final String name;
  final String? setlistName;
  final bool active;
  final VoidCallback onTap;

  const _Chip({
    required this.index,
    required this.name,
    required this.setlistName,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    final assigned = setlistName != null;
    // Same color per scene number everywhere (chips, tiles).
    final color = AppTheme.songColors[index % AppTheme.songColors.length];
    return Tooltip(
      message: assigned ? '$name → $setlistName' : '$name (tap to assign)',
      child: TapScale(
        onTap: onTap,
        pressedScale: 0.9,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 28,
          height: 28,
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          decoration: BoxDecoration(
            color: active
                ? color
                : assigned
                    ? color.withValues(alpha: 0.12)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active
                  ? color
                  : assigned
                      ? color.withValues(alpha: 0.5)
                      : col.border,
            ),
            boxShadow: active
                ? [BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 8)]
                : null,
          ),
          child: Center(
            child: Text(
              '${index + 1}',
              style: TextStyle(
                color: active
                    ? Colors.black
                    : assigned
                        ? color
                        : col.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
