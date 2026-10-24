import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/ableton_provider.dart';
import '../providers/locator_groups_provider.dart';
import '../theme/app_theme.dart';
import 'tap_scale.dart';

// ── Public sidebar widget — reusable across screens ────────────────────────────

class SidebarTransport extends StatelessWidget {
  const SidebarTransport({super.key});

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    const radius = BorderRadius.all(Radius.circular(24));
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 10, 10, 10),
      child: Container(
        width: 116,
        decoration: BoxDecoration(
          color: col.surface,
          borderRadius: radius,
          border: Border.all(color: col.border),
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: const TransportControls(vertical: true),
        ),
      ),
    );
  }
}

class TransportControls extends StatelessWidget {
  final bool vertical;
  const TransportControls({super.key, this.vertical = false});

  @override
  Widget build(BuildContext context) {
    return vertical ? _buildVertical(context) : _buildHorizontal(context);
  }

  Widget _buildHorizontal(BuildContext context) {
    final ableton = context.watch<AbletonProvider>();
    final state = ableton.state;
    final connected = ableton.isConnected;
    final col = context.col;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
      decoration: BoxDecoration(
        color: col.surface,
        border: Border(top: BorderSide(color: col.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: _BpmTimeSigBlock(),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _NavBtn(
                    icon: Icons.skip_previous_rounded,
                    onTap: connected ? ableton.goToPrevious : null,
                  ),
                  const SizedBox(width: 10),
                  _StopBtn(isPlaying: ableton.isPlaying, onTap: connected ? ableton.stop : null),
                  const SizedBox(width: 8),
                  _PlayBtn(isPlaying: ableton.isPlaying, connected: connected),
                  const SizedBox(width: 8),
                  _RecordBtn(
                    isRecording: state.isRecording,
                    onTap: connected ? ableton.record : null,
                  ),
                  const SizedBox(width: 10),
                  _NavBtn(
                    icon: Icons.skip_next_rounded,
                    onTap: connected ? ableton.goToNext : null,
                  ),
                ],
              ),
              const Align(
                alignment: Alignment.centerRight,
                child: _LoopBtn(),
              ),
            ],
          ),
          if (connected) ...[
            const SizedBox(height: 10),
            _VolumeFaderRow(
              masterVolume: state.masterVolume,
              masterVolStr: state.masterVolStr,
              cueVolume: state.cueVolume,
              cueVolStr: state.cueVolStr,
              onMasterChanged: ableton.setMasterVolume,
              onCueChanged: ableton.setCueVolume,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVertical(BuildContext context) {
    final ableton = context.watch<AbletonProvider>();
    final state = ableton.state;
    final connected = ableton.isConnected;
    final col = context.col;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      child: Column(
        mainAxisSize: MainAxisSize.max,
        children: [
          // ── BPM + time sig ──────────────────────────────────────────────
          _BpmTimeSigBlock(centered: true),

          const SizedBox(height: 14),
          _divider(col),
          const SizedBox(height: 14),

          // ── Prev / Play / Next ──────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _NavBtn(
                icon: Icons.skip_previous_rounded,
                onTap: connected ? ableton.goToPrevious : null,
                size: 20,
                color: AppTheme.accent,
              ),
              _PlayBtn(isPlaying: ableton.isPlaying, connected: connected),
              _NavBtn(
                icon: Icons.skip_next_rounded,
                onTap: connected ? ableton.goToNext : null,
                size: 20,
                color: AppTheme.accent,
              ),
            ],
          ),

          const SizedBox(height: 10),

          // ── Stop + Record grouped ───────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: col.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: col.border),
            ),
            padding: const EdgeInsets.all(4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _StopBtn(
                  isPlaying: ableton.isPlaying,
                  onTap: connected ? ableton.stop : null,
                  size: 36,
                  color: AppTheme.danger,
                ),
                Container(width: 1, height: 24, color: col.border),
                _RecordBtn(
                  isRecording: state.isRecording,
                  onTap: connected ? ableton.record : null,
                  size: 36,
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // ── Loop full-width ─────────────────────────────────────────────
          const _LoopBtnWide(),

          // ── Faders fill remaining space ─────────────────────────────────
          if (connected) ...[
            const SizedBox(height: 14),
            _divider(col),
            const SizedBox(height: 8),
            Expanded(
              child: _VerticalFaders(
                masterVolume: state.masterVolume,
                masterVolStr: state.masterVolStr,
                cueVolume: state.cueVolume,
                cueVolStr: state.cueVolStr,
                onMasterChanged: ableton.setMasterVolume,
                onCueChanged: ableton.setCueVolume,
              ),
            ),
          ] else
            const Spacer(),
        ],
      ),
    );
  }

  Widget _divider(AppColors col) => Container(
        height: 1,
        color: col.border,
      );
}

// ─────────────────────────────────────────────────────────────────────────────

class _BpmTimeSigBlock extends StatelessWidget {
  final bool centered;
  const _BpmTimeSigBlock({this.centered = false});

  @override
  Widget build(BuildContext context) {
    final ableton = context.watch<AbletonProvider>();
    final groups  = context.watch<LocatorGroupsProvider>();
    final connected = ableton.isConnected;
    final bpm = ableton.state.bpm;
    final activeName = ableton.selectedLocator?.name ?? ableton.state.currentLocatorName;
    final locSig = groups.getLocatorSig(activeName) ?? ableton.locatorTimeSig;
    final col = context.col;

    return Column(
      crossAxisAlignment: centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          connected ? bpm.toStringAsFixed(1) : '---',
          style: TextStyle(
            color: connected ? AppTheme.accent : col.textMuted,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        Text(
          connected
              ? (locSig != null ? '${locSig.$1}/${locSig.$2}' : '--/--')
              : '--/--',
          style: TextStyle(
            color: col.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w500,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

// ── Vertical Faders ───────────────────────────────────────────────────────────

class _VerticalFaders extends StatelessWidget {
  final double masterVolume;
  final String masterVolStr;
  final double cueVolume;
  final String cueVolStr;
  final ValueChanged<double> onMasterChanged;
  final ValueChanged<double> onCueChanged;

  const _VerticalFaders({
    required this.masterVolume,
    required this.masterVolStr,
    required this.cueVolume,
    required this.cueVolStr,
    required this.onMasterChanged,
    required this.onCueChanged,
  });

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _MiniSlider(
            label: 'M',
            value: masterVolume,
            volStr: masterVolStr,
            color: AppTheme.accent,
            col: col,
            onChanged: onMasterChanged,
          ),
        ),
        Expanded(
          child: _MiniSlider(
            label: 'C',
            value: cueVolume,
            volStr: cueVolStr,
            color: Colors.blueAccent,
            col: col,
            onChanged: onCueChanged,
          ),
        ),
      ],
    );
  }
}

class _MiniSlider extends StatelessWidget {
  final String label;
  final double value;
  final String volStr;
  final Color color;
  final AppColors col;
  final ValueChanged<double> onChanged;

  const _MiniSlider({
    required this.label,
    required this.value,
    required this.volStr,
    required this.color,
    required this.col,
    required this.onChanged,
  });

  // Normalized positions (0=top=loud, 1=bottom=silent) for scale marks
  static const _marks = [
    ('+6',  0.00),
    ('0',   0.22),
    ('-6',  0.44),
    ('-12', 0.66),
    ('-∞',  1.00),
  ];

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: () => onChanged(0.85),
      child: Column(
      mainAxisSize: MainAxisSize.max,
      children: [
        Text(
          label,
          style: TextStyle(
            color: col.textMuted,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          volStr.isEmpty ? '' : volStr,
          style: TextStyle(
            color: color.withValues(alpha: 0.85),
            fontSize: 9,
            fontWeight: FontWeight.w500,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: Row(
            children: [
              // Scale ruler
              SizedBox(
                width: 16,
                child: LayoutBuilder(
                  builder: (_, constraints) {
                    final h = constraints.maxHeight;
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (final (db, pos) in _marks)
                          Positioned(
                            top: pos * h - 5,
                            right: 0,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  db,
                                  style: TextStyle(
                                    color: col.textMuted.withValues(alpha: 0.6),
                                    fontSize: 7,
                                    fontWeight: FontWeight.w500,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                ),
                                const SizedBox(width: 2),
                                Container(
                                  width: 3,
                                  height: 1,
                                  color: col.border,
                                ),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
              // Slider
              Expanded(
                child: RotatedBox(
                  quarterTurns: 3,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                      overlayShape: SliderComponentShape.noOverlay,
                      activeTrackColor: color,
                      inactiveTrackColor: col.border,
                      thumbColor: color,
                    ),
                    child: Slider(value: value.clamp(0.0, 1.0), onChanged: onChanged),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
      ),
    );
  }
}

// ── Play ──────────────────────────────────────────────────────────────────────

class _PlayBtn extends StatefulWidget {
  final bool isPlaying;
  final bool connected;
  const _PlayBtn({required this.isPlaying, required this.connected});

  @override
  State<_PlayBtn> createState() => _PlayBtnState();
}

class _PlayBtnState extends State<_PlayBtn>
    with TickerProviderStateMixin {
  late final AnimationController _pulse;
  late final AnimationController _flash;
  late final Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    _flash = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _glow = Tween<double>(begin: 10.0, end: 28.0).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
    if (widget.isPlaying) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_PlayBtn old) {
    super.didUpdateWidget(old);
    if (widget.isPlaying && !old.isPlaying) {
      _pulse.repeat(reverse: true);
    } else if (!widget.isPlaying && old.isPlaying) {
      _pulse.animateTo(0.0, duration: const Duration(milliseconds: 200))
          .then((_) => _pulse.stop());
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _flash.dispose();
    super.dispose();
  }

  void _onTap() {
    context.read<AbletonProvider>().play();
    _flash.forward().then((_) => _flash.reverse());
  }

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    return TapScale(
      onTap: widget.connected ? _onTap : null,
      pressedScale: 0.88,
      child: AnimatedBuilder(
        animation: Listenable.merge([_glow, _flash]),
        builder: (_, _) => Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: widget.isPlaying
                ? AppTheme.accent
                : Color.lerp(
                    col.surfaceVariant,
                    AppTheme.accent.withValues(alpha: 0.25),
                    _flash.value,
                  ),
            shape: BoxShape.circle,
            border: widget.isPlaying
                ? null
                : Border.all(
                    color: Color.lerp(
                      col.border,
                      AppTheme.accent.withValues(alpha: 0.6),
                      _flash.value,
                    )!,
                  ),
            boxShadow: widget.isPlaying
                ? [
                    BoxShadow(
                      color: AppTheme.accent.withValues(alpha: 0.45),
                      blurRadius: _glow.value,
                      spreadRadius: 0,
                    ),
                  ]
                : _flash.value > 0
                    ? [
                        BoxShadow(
                          color: AppTheme.accent
                              .withValues(alpha: 0.3 * _flash.value),
                          blurRadius: 14 * _flash.value,
                        ),
                      ]
                    : null,
          ),
          child: Icon(
            Icons.play_arrow_rounded,
            color: widget.isPlaying ? Colors.black : col.textSecondary,
            size: 30,
          ),
        ),
      ),
    );
  }
}

// ── Stop ──────────────────────────────────────────────────────────────────────

class _StopBtn extends StatefulWidget {
  final bool isPlaying;
  final VoidCallback? onTap;
  final double size;
  final Color? color;
  const _StopBtn({required this.isPlaying, this.onTap, this.size = 42, this.color});

  @override
  State<_StopBtn> createState() => _StopBtnState();
}

class _StopBtnState extends State<_StopBtn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flash;

  @override
  void initState() {
    super.initState();
    _flash = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  void didUpdateWidget(_StopBtn old) {
    super.didUpdateWidget(old);
    if (old.isPlaying && !widget.isPlaying) {
      _flash.forward().then((_) => _flash.reverse());
    }
  }

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  void _onTap() {
    widget.onTap?.call();
    _flash.forward().then((_) => _flash.reverse());
  }

  @override
  Widget build(BuildContext context) {
    return TapScale(
      onTap: widget.onTap != null ? _onTap : null,
      child: AnimatedBuilder(
        animation: _flash,
        builder: (_, _) => Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: Color.lerp(
              (widget.color ?? AppTheme.accent).withValues(alpha: 0.08),
              (widget.color ?? AppTheme.accent).withValues(alpha: 0.22),
              _flash.value,
            ),
            borderRadius: BorderRadius.circular(widget.size * 0.24),
            border: Border.all(
              color: Color.lerp(
                (widget.color ?? AppTheme.accent).withValues(alpha: 0.35),
                (widget.color ?? AppTheme.accent).withValues(alpha: 0.8),
                _flash.value,
              )!,
            ),
          ),
          child: Icon(
            Icons.stop_rounded,
            color: Color.lerp(
              widget.color ?? AppTheme.accent,
              (widget.color ?? AppTheme.accent).withValues(alpha: 0.6),
              _flash.value,
            ),
            size: widget.size * 0.55,
          ),
        ),
      ),
    );
  }
}

// ── Record ────────────────────────────────────────────────────────────────────

class _RecordBtn extends StatefulWidget {
  final bool isRecording;
  final VoidCallback? onTap;
  final double size;
  const _RecordBtn({required this.isRecording, this.onTap, this.size = 42});

  @override
  State<_RecordBtn> createState() => _RecordBtnState();
}

class _RecordBtnState extends State<_RecordBtn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink;

  @override
  void initState() {
    super.initState();
    _blink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );
    if (widget.isRecording) _blink.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_RecordBtn old) {
    super.didUpdateWidget(old);
    if (widget.isRecording && !old.isRecording) {
      _blink.repeat(reverse: true);
    } else if (!widget.isRecording && old.isRecording) {
      _blink.animateTo(1.0, duration: const Duration(milliseconds: 150))
          .then((_) => _blink.stop());
    }
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TapScale(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _blink,
        builder: (_, _) {
          final alpha = widget.isRecording
              ? 0.45 + 0.55 * _blink.value
              : 1.0;
          return Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: AppTheme.danger.withValues(
                  alpha: widget.isRecording ? 0.12 + 0.08 * _blink.value : 0.07),
              borderRadius: BorderRadius.circular(widget.size * 0.24),
              border: Border.all(
                color: AppTheme.danger.withValues(
                    alpha: widget.isRecording ? alpha : 0.30),
              ),
            ),
            child: Icon(
              Icons.fiber_manual_record_rounded,
              color: AppTheme.danger.withValues(
                  alpha: widget.isRecording ? alpha : 0.55),
              size: widget.size * 0.52,
            ),
          );
        },
      ),
    );
  }
}

// ── Nav ───────────────────────────────────────────────────────────────────────

class _NavBtn extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final Color? color;
  const _NavBtn({required this.icon, this.onTap, this.size = 30, this.color});

  @override
  State<_NavBtn> createState() => _NavBtnState();
}

class _NavBtnState extends State<_NavBtn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flash;

  @override
  void initState() {
    super.initState();
    _flash = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  void _onTap() {
    widget.onTap?.call();
    _flash.forward().then((_) => _flash.reverse());
  }

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    return TapScale(
      onTap: widget.onTap != null ? _onTap : null,
      pressedScale: 0.85,
      child: AnimatedBuilder(
        animation: _flash,
        builder: (_, _) => Icon(
          widget.icon,
          color: widget.onTap != null
              ? Color.lerp(widget.color ?? col.textSecondary, AppTheme.accent, _flash.value)
              : col.border,
          size: widget.size,
        ),
      ),
    );
  }
}

// ── Volume Faders ─────────────────────────────────────────────────────────────

class _VolumeFaderRow extends StatelessWidget {
  final double masterVolume;
  final String masterVolStr;
  final double cueVolume;
  final String cueVolStr;
  final ValueChanged<double> onMasterChanged;
  final ValueChanged<double> onCueChanged;

  const _VolumeFaderRow({
    required this.masterVolume,
    required this.masterVolStr,
    required this.cueVolume,
    required this.cueVolStr,
    required this.onMasterChanged,
    required this.onCueChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _FaderCol(
            label: 'MASTER',
            value: masterVolume,
            volStr: masterVolStr,
            onChanged: onMasterChanged,
            color: AppTheme.accent,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _FaderCol(
            label: 'CUE',
            value: cueVolume,
            volStr: cueVolStr,
            onChanged: onCueChanged,
            color: Colors.blueAccent,
          ),
        ),
      ],
    );
  }
}

class _FaderCol extends StatelessWidget {
  final String label;
  final double value;
  final String volStr;
  final ValueChanged<double> onChanged;
  final Color color;

  const _FaderCol({
    required this.label,
    required this.value,
    required this.volStr,
    required this.onChanged,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    return GestureDetector(
      onDoubleTap: () => onChanged(0.85),
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: col.textMuted,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            const Spacer(),
            Text(
              volStr.isEmpty ? '' : volStr,
              style: TextStyle(
                color: color.withValues(alpha: 0.85),
                fontSize: 9,
                fontWeight: FontWeight.w500,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            activeTrackColor: color,
            inactiveTrackColor: col.border,
            thumbColor: color,
            overlayColor: color.withValues(alpha: 0.15),
          ),
          child: Slider(
            value: value.clamp(0.0, 1.0),
            onChanged: onChanged,
          ),
        ),
      ],
      ),
    );
  }
}

// ── Loop ──────────────────────────────────────────────────────────────────────

class _LoopBtn extends StatelessWidget {
  const _LoopBtn();

  @override
  Widget build(BuildContext context) {
    final ableton = context.watch<AbletonProvider>();
    final enabled = ableton.loopEnabled;
    final connected = ableton.isConnected;
    final col = context.col;
    return TapScale(
      onTap: connected
          ? () {
              final current = context.read<AbletonProvider>().loopEnabled;
              context.read<AbletonProvider>().setLoop(!current);
            }
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: enabled
              ? AppTheme.accent.withValues(alpha: 0.12)
              : col.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: enabled
                ? AppTheme.accent.withValues(alpha: 0.5)
                : col.border,
          ),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: AppTheme.accent.withValues(alpha: 0.2),
                    blurRadius: 8,
                  ),
                ]
              : null,
        ),
        child: Icon(
          Icons.loop_rounded,
          size: 18,
          color: enabled ? AppTheme.accent : col.textSecondary,
        ),
      ),
    );
  }
}

class _LoopBtnWide extends StatelessWidget {
  const _LoopBtnWide();

  @override
  Widget build(BuildContext context) {
    final ableton = context.watch<AbletonProvider>();
    final enabled = ableton.loopEnabled;
    final connected = ableton.isConnected;
    final col = context.col;
    return TapScale(
      onTap: connected
          ? () {
              final current = context.read<AbletonProvider>().loopEnabled;
              context.read<AbletonProvider>().setLoop(!current);
            }
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: enabled
              ? AppTheme.accent.withValues(alpha: 0.12)
              : col.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: enabled ? AppTheme.accent.withValues(alpha: 0.5) : col.border,
          ),
          boxShadow: enabled
              ? [BoxShadow(color: AppTheme.accent.withValues(alpha: 0.2), blurRadius: 8)]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.loop_rounded, size: 16,
                color: enabled ? AppTheme.accent : col.textSecondary),
            const SizedBox(width: 5),
            Text(
              'LOOP',
              style: TextStyle(
                color: enabled ? AppTheme.accent : col.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
