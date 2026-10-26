import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/ableton_state.dart';
import '../providers/ableton_provider.dart';
import '../providers/locator_groups_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/setlist_selector.dart';
import 'scene_screen.dart';
import '../widgets/tap_scale.dart';
import '../widgets/transport_controls.dart';

class PerformanceScreen extends StatefulWidget {
  const PerformanceScreen({super.key});

  @override
  State<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends State<PerformanceScreen> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'PerformanceScreen');
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final p = context.read<AbletonProvider>();
    if (!p.isConnected) return KeyEventResult.ignored;

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.space) {
      p.isPlaying ? p.stop() : p.play();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      if (!p.isPlaying) p.play();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.arrowDown) {
      p.goToNext();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowUp) {
      p.goToPrevious();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyR) {
      p.record();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final ableton = context.watch<AbletonProvider>();
    final state = ableton.state;
    final locators = ableton.locators;
    final selected = ableton.selectedLocator;
    final next = ableton.nextLocator;
    final prev = ableton.previousLocator;
    final selectedIdx = ableton.selectedIndex;
    final col = context.col;

    final groups = context.watch<LocatorGroupsProvider>();
    final activeName = selected?.name ?? state.currentLocatorName;
    final sig = groups.getLocatorSig(activeName) ?? ableton.locatorTimeSig;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: col.background,
        body: GestureDetector(
          onVerticalDragEnd: (d) {
            if (d.primaryVelocity == null) return;
            if (d.primaryVelocity! < -300) ableton.goToNext();
            if (d.primaryVelocity! > 300) ableton.goToPrevious();
          },
          child: Column(
            children: [
              // ── Top bar ──────────────────────────────────────────────────
              SafeArea(
                bottom: false,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down_rounded,
                            size: 28),
                        onPressed: () => Navigator.of(context).pop(),
                        color: col.textSecondary,
                        tooltip: 'Exit performance mode',
                      ),
                      const Spacer(),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            [
                              if ((state.projectName ?? '').isNotEmpty)
                                state.projectName!,
                              groups.activeDisplayName,
                              if (groups.activeSceneIndex != null)
                                groups.activeSetlistName,
                            ].join('  ·  '),
                            style: TextStyle(
                              color: col.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (locators.isNotEmpty && selectedIdx != null) ...[
                            const SizedBox(height: 3),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.accent.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'SONG ${selectedIdx + 1} OF ${locators.length}',
                                style: const TextStyle(
                                  color: AppTheme.accent,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const Spacer(),
                      const SetlistSwitchButton(),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.grid_view_rounded, size: 20),
                        color: col.textSecondary,
                        tooltip: 'Scenes',
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const SceneScreen()),
                        ),
                      ),
                      const SizedBox(width: 4),
                      _ConnectionPill(state.connectionStatus),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
              ),

              // ── Setlist progress ─────────────────────────────────────────
              if (locators.isNotEmpty && selectedIdx != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
                  child: _SetlistProgress(
                      count: locators.length, current: selectedIdx),
                ),

              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 12, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Beat indicator
                            if (ableton.isConnected)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                child: _BeatIndicator(
                                    state: state, locatorTimeSig: sig),
                              ),

                            // Current song: takes all remaining height
                            Expanded(
                              child: _CurrentCard(
                                locator: selected,
                                index: selectedIdx,
                                isPlaying: state.isPlaying,
                                sig: sig,
                                bpm: state.bpm,
                              ),
                            ),

                            const SizedBox(height: 12),

                            // Previous / Next
                            IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: _NavCard(
                                      label: 'PREV',
                                      name: prev?.name,
                                      leading: true,
                                      onTap: prev != null
                                          ? ableton.goToPrevious
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _NavCard(
                                      label: 'NEXT',
                                      name: next?.name,
                                      leading: false,
                                      onTap: next != null
                                          ? ableton.goToNext
                                          : null,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 12),

                            // Stats strip
                            if (ableton.isConnected)
                              _StatsStrip(state: state, locatorTimeSig: sig),
                          ],
                        ),
                      ),
                    ),
                    const SafeArea(
                      top: false,
                      left: false,
                      child: SidebarTransport(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// One segment per song; falls back to a continuous bar for long setlists.
class _SetlistProgress extends StatelessWidget {
  final int count;
  final int current;
  const _SetlistProgress({required this.count, required this.current});

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    if (count > 32) {
      return LinearProgressIndicator(
        value: (current + 1) / count,
        backgroundColor: col.border,
        valueColor: const AlwaysStoppedAnimation(AppTheme.accent),
        minHeight: 4,
        borderRadius: BorderRadius.circular(2),
      );
    }
    return Row(
      children: List.generate(count, (i) {
        final done = i < current;
        final isCurrent = i == current;
        return Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            height: isCurrent ? 6 : 4,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(
              color: isCurrent
                  ? AppTheme.accent
                  : done
                      ? AppTheme.accent.withValues(alpha: 0.4)
                      : col.border,
              borderRadius: BorderRadius.circular(3),
              boxShadow: isCurrent
                  ? [
                      BoxShadow(
                        color: AppTheme.accent.withValues(alpha: 0.5),
                        blurRadius: 6,
                      ),
                    ]
                  : null,
            ),
          ),
        );
      }),
    );
  }
}

class _NavCard extends StatelessWidget {
  final String label;
  final String? name;
  final bool leading; // true = chevron on the left (previous)
  final VoidCallback? onTap;
  const _NavCard({
    required this.label,
    required this.name,
    required this.leading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    final enabled = onTap != null;
    final chevron = Icon(
      leading ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
      color: enabled ? AppTheme.accent : col.border,
      size: 26,
    );
    return TapScale(
      onTap: onTap,
      pressedScale: 0.97,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: col.surfaceVariant,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: col.border),
        ),
        child: Row(
          children: [
            if (leading) chevron,
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment:
                    leading ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: col.textMuted,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    name ?? '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: leading ? TextAlign.start : TextAlign.end,
                    style: TextStyle(
                      color: enabled ? col.textPrimary : col.textMuted,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (!leading) chevron,
          ],
        ),
      ),
    );
  }
}

class _BeatIndicator extends StatelessWidget {
  final AbletonState state;
  final (int, int)? locatorTimeSig;
  const _BeatIndicator({required this.state, this.locatorTimeSig});

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    final sig = (locatorTimeSig?.$1 ?? state.timeSigNumerator).clamp(1, 16);
    final beat = (state.currentBeat % sig).toInt() + 1;

    return SizedBox(
      height: 28,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(sig, (i) {
          final isActive = state.isPlaying && beat == i + 1;
          final isDown = i == 0;
          final dotSize = isActive
              ? 22.0
              : isDown
                  ? 11.0
                  : 8.0;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            margin: const EdgeInsets.symmetric(horizontal: 6),
            width: dotSize,
            height: dotSize,
            decoration: BoxDecoration(
              color: isActive
                  ? AppTheme.accent
                  : isDown
                      ? col.borderBright
                      : col.border,
              shape: BoxShape.circle,
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: AppTheme.accent.withValues(alpha: 0.55),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
          );
        }),
      ),
    );
  }
}

class _CurrentCard extends StatelessWidget {
  final AbletonLocator? locator;
  final int? index;
  final bool isPlaying;
  final (int, int)? sig;
  final double bpm;
  const _CurrentCard({
    required this.locator,
    required this.index,
    required this.isPlaying,
    required this.sig,
    required this.bpm,
  });

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    final color = index != null
        ? AppTheme.songColors[index! % AppTheme.songColors.length]
        : AppTheme.accent;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: isPlaying ? 0.22 : 0.12),
            color.withValues(alpha: 0.03),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: color.withValues(alpha: isPlaying ? 0.7 : 0.3),
          width: isPlaying ? 2 : 1,
        ),
        boxShadow: isPlaying
            ? [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 30)]
            : null,
      ),
      child: locator == null
          ? Center(
              child: Text(
                'Select a locator to begin',
                style: TextStyle(color: col.textMuted, fontSize: 16),
              ),
            )
          : Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isPlaying ? AppTheme.success : col.textMuted,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isPlaying ? 'NOW PLAYING' : 'READY',
                      style: TextStyle(
                        color: isPlaying ? AppTheme.success : col.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.6,
                      ),
                    ),
                    const Spacer(),
                    if (index != null)
                      Text(
                        (index! + 1).toString().padLeft(2, '0'),
                        style: TextStyle(
                          color: color.withValues(alpha: 0.9),
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                  ],
                ),
                Expanded(
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        locator!.name,
                        style: TextStyle(
                          color: col.textPrimary,
                          fontSize: 72,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -2,
                          height: 1.05,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _Chip(sig != null ? '${sig!.$1}/${sig!.$2}' : '--/--'),
                    const SizedBox(width: 8),
                    _Chip('${bpm.toStringAsFixed(1)} BPM'),
                  ],
                ),
              ],
            ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  const _Chip(this.text);

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: col.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: col.border),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: col.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _StatsStrip extends StatelessWidget {
  final AbletonState state;
  final (int, int)? locatorTimeSig;
  const _StatsStrip({required this.state, this.locatorTimeSig});

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    final n = locatorTimeSig?.$1;
    final d = locatorTimeSig?.$2;
    final sig = (n ?? state.timeSigNumerator).clamp(1, 16);
    final beat = (state.currentBeat % sig).toInt() + 1;
    final playing = state.isPlaying;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: col.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: col.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _StatItem(n != null && d != null ? '$n/$d' : '--/--', 'SIG'),
          _VertDivider(),
          _StatItem('$beat', 'BEAT'),
          _VertDivider(),
          _StatItem(state.bpm.toStringAsFixed(1), 'BPM'),
          _VertDivider(),
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: playing ? AppTheme.success : col.textMuted,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                playing ? 'LIVE' : 'STOPPED',
                style: TextStyle(
                  color: playing ? AppTheme.success : col.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VertDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 20,
      color: context.col.border,
    );
  }
}

class _StatItem extends StatelessWidget {
  final String value;
  final String label;
  const _StatItem(this.value, this.label);

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            color: col.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: col.textMuted,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

class _ConnectionPill extends StatelessWidget {
  final ConnectionStatus status;
  const _ConnectionPill(this.status);

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    final (color, label) = switch (status) {
      ConnectionStatus.connected => (AppTheme.success, 'LIVE LINK'),
      ConnectionStatus.connecting => (AppTheme.warning, 'CONNECTING'),
      ConnectionStatus.disconnected => (col.textMuted, 'OFFLINE'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}
