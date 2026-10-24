import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/ableton_state.dart';
import '../providers/ableton_provider.dart';
import '../providers/locator_groups_provider.dart';
import '../theme/app_theme.dart';
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
            // Top bar
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
                    ),
                    const Spacer(),
                    Column(
                      children: [
                        Text(
                          state.projectName ?? '',
                          style: TextStyle(
                              color: col.textSecondary, fontSize: 12),
                        ),
                        if (locators.isNotEmpty && selectedIdx != null)
                          Text(
                            '${selectedIdx + 1} / ${locators.length}',
                            style: TextStyle(
                                color: col.textMuted, fontSize: 11),
                          ),
                      ],
                    ),
                    const Spacer(),
                    _ConnectionDot(state.connectionStatus),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),

            // Progress bar
            if (locators.isNotEmpty && selectedIdx != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: LinearProgressIndicator(
                  value: (selectedIdx + 1) / locators.length,
                  backgroundColor: col.border,
                  valueColor: const AlwaysStoppedAnimation(AppTheme.accent),
                  minHeight: 2,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
          Expanded(
          child: Column(
          children: [
            const Spacer(flex: 1),

            // Beat indicator dots
            if (ableton.isConnected)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Builder(builder: (ctx) {
                  final groups = ctx.watch<LocatorGroupsProvider>();
                  final activeName = ableton.selectedLocator?.name
                      ?? ableton.state.currentLocatorName;
                  final sig = groups.getLocatorSig(activeName)
                      ?? ableton.locatorTimeSig;
                  return _BeatIndicator(state: state, locatorTimeSig: sig);
                }),
              ),

            const SizedBox(height: 6),

            // Previous hint
            if (prev != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  '↑  ${prev.name}',
                  style: TextStyle(
                    color: col.textMuted.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

            const SizedBox(height: 10),

            // Current locator card
            _CurrentCard(locator: selected, index: selectedIdx),

            const SizedBox(height: 14),

            // Next locator
            if (next != null)
              GestureDetector(
                onTap: () => ableton.goToNext(),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 28),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: col.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: col.border),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: col.textSecondary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'NEXT  ${next.name}',
                        style: TextStyle(
                          color: col.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const Spacer(),
                      Icon(Icons.chevron_right_rounded,
                          color: col.textMuted, size: 16),
                    ],
                  ),
                ),
              ),

            const Spacer(flex: 2),

            // Stats strip
            if (ableton.isConnected)
              Builder(builder: (ctx) {
                final groups = ctx.watch<LocatorGroupsProvider>();
                final activeName = ableton.selectedLocator?.name
                    ?? ableton.state.currentLocatorName;
                final sig = groups.getLocatorSig(activeName)
                    ?? ableton.locatorTimeSig;
                return _StatsStrip(state: state, locatorTimeSig: sig);
              }),

            const SizedBox(height: 10),
          ],
          ),  // Column
          ),  // Expanded
          const SafeArea(
            top: false,
            left: false,
            child: SidebarTransport(),
          ),
                ],
              ),  // Row
            ),  // Expanded
          ],
        ),  // Column
      ),
    ),  // Scaffold
    );  // Focus
  }
}

// ─────────────────────────────────────────────────────────────────────────────

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
      height: 20,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(sig, (i) {
          final isActive = state.isPlaying && beat == i + 1;
          final isDown = i == 0;
          final dotSize = isActive
              ? 14.0
              : isDown
                  ? 7.0
                  : 5.0;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            margin: const EdgeInsets.symmetric(horizontal: 5),
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
  const _CurrentCard({required this.locator, required this.index});

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    final color = index != null
        ? AppTheme.songColors[index! % AppTheme.songColors.length]
        : AppTheme.accent;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: locator == null
          ? Center(
              child: Text(
                'Tap a locator to begin',
                style: TextStyle(color: col.textMuted, fontSize: 15),
              ),
            )
          : Center(
              child: FittedBox(
                child: Text(
                  locator!.name,
                  style: TextStyle(
                    color: col.textPrimary,
                    fontSize: 52,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
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
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: col.surface,
        borderRadius: BorderRadius.circular(12),
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
            fontSize: 15,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: col.textMuted,
            fontSize: 8,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}

class _ConnectionDot extends StatelessWidget {
  final ConnectionStatus status;
  const _ConnectionDot(this.status);

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    final color = switch (status) {
      ConnectionStatus.connected => AppTheme.success,
      ConnectionStatus.connecting => AppTheme.warning,
      ConnectionStatus.disconnected => col.textMuted,
    };
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
