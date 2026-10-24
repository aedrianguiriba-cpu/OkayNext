import 'dart:async' show StreamSubscription;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/ableton_state.dart';
import '../providers/ableton_provider.dart';
import '../theme/app_theme.dart';
import 'tap_scale.dart';

// ── Group model ───────────────────────────────────────────────────────────────

class _TrackSection {
  /// The group track itself (null = a batch of ungrouped tracks).
  final AbletonTrack? group;
  final List<AbletonTrack> children;
  const _TrackSection({this.group, required this.children});
}

List<_TrackSection> _buildSections(List<AbletonTrack> all) {
  // Map from group-track index → its direct children (in order)
  final childrenOf = <int, List<AbletonTrack>>{};
  for (final t in all) {
    if (t.groupIndex >= 0) {
      childrenOf.putIfAbsent(t.groupIndex, () => []).add(t);
    }
  }

  final sections = <_TrackSection>[];
  final ungrouped = <AbletonTrack>[];
  final seen = <int>{};

  void flushUngrouped() {
    if (ungrouped.isNotEmpty) {
      sections.add(_TrackSection(children: List.of(ungrouped)));
      ungrouped.clear();
    }
  }

  for (final t in all) {
    if (seen.contains(t.index)) continue;
    if (t.isGroup && t.groupIndex < 0) {
      // Top-level group — flush pending ungrouped first
      flushUngrouped();
      final kids = childrenOf[t.index] ?? [];
      for (final k in kids) seen.add(k.index);
      seen.add(t.index);
      sections.add(_TrackSection(group: t, children: kids));
    } else if (t.groupIndex < 0) {
      // Top-level non-group
      seen.add(t.index);
      ungrouped.add(t);
    }
    // Children with groupIndex >= 0 are handled when their group is visited
  }
  flushUngrouped();
  return sections;
}

// ── TrackMixer ────────────────────────────────────────────────────────────────

class TrackMixer extends StatefulWidget {
  const TrackMixer({super.key});

  @override
  State<TrackMixer> createState() => _TrackMixerState();
}

class _TrackMixerState extends State<TrackMixer> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ableton = context.watch<AbletonProvider>();
    final all = ableton.tracks;
    final col = context.col;

    if (all.isEmpty) return const SizedBox.shrink();

    final sections = _buildSections(all);
    final trackCount = all.where((t) => !t.isGroup).length;

    return Container(
      decoration: BoxDecoration(
        color: col.surface,
        border: Border(top: BorderSide(color: col.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 2),
            child: Row(
              children: [
                Icon(Icons.tune_rounded, size: 13, color: col.textMuted),
                const SizedBox(width: 5),
                Text(
                  'STEMS  $trackCount tracks',
                  style: TextStyle(
                    color: col.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
          // Mixer row
          SizedBox(
            height: 156,
            child: Row(
              children: [
                Expanded(
                  child: Scrollbar(
                    controller: _scroll,
                    thumbVisibility: false,
                    radius: const Radius.circular(4),
                    child: SingleChildScrollView(
                      controller: _scroll,
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final sec in sections)
                            sec.group != null
                                ? _GroupSection(group: sec.group!, children: sec.children)
                                : Row(
                                    children: sec.children.map((t) => _TrackCell(track: t)).toList(),
                                  ),
                        ],
                      ),
                    ),
                  ),
                ),
                Container(width: 1, margin: const EdgeInsets.symmetric(vertical: 12), color: col.border),
                const _MasterCell(),
                Container(width: 1, margin: const EdgeInsets.symmetric(vertical: 12), color: col.border),
                const _CueCell(),
              ],
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// ── Group section ─────────────────────────────────────────────────────────────

class _GroupSection extends StatelessWidget {
  final AbletonTrack group;
  final List<AbletonTrack> children;
  const _GroupSection({required this.group, required this.children});

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    final isMuted = group.mute;
    final borderColor = isMuted
        ? col.border.withValues(alpha: 0.4)
        : AppTheme.accent.withValues(alpha: 0.35);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Group label
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 5, 8, 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.folder_rounded, size: 10,
                    color: isMuted ? col.textMuted : AppTheme.accent),
                const SizedBox(width: 4),
                ConstrainedBox(
                  constraints: BoxConstraints(
                      maxWidth: (children.length * 72.0).clamp(60, 200)),
                  child: Text(
                    group.name.toUpperCase(),
                    style: TextStyle(
                      color: isMuted ? col.textMuted : AppTheme.accent,
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          // Child track cells
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children.isEmpty
                ? [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Text('empty',
                          style: TextStyle(color: col.textMuted, fontSize: 9)),
                    )
                  ]
                : children.map((t) => _TrackCell(track: t)).toList(),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _TrackCell extends StatefulWidget {
  final AbletonTrack track;
  const _TrackCell({required this.track});

  @override
  State<_TrackCell> createState() => _TrackCellState();
}

class _TrackCellState extends State<_TrackCell> {
  double? _localVolume;
  bool _dragging = false;
  String? _liveLabel;
  StreamSubscription<Map<String, dynamic>>? _labelSub;

  double get _volume => _localVolume ?? widget.track.volume;

  String get _displayLabel => _dragging
      ? (_liveLabel ?? widget.track.volStr)
      : widget.track.volStr;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _labelSub?.cancel();
    _labelSub = context
        .read<AbletonProvider>()
        .volLabelStream
        .where((m) => m['index'] == widget.track.index)
        .listen((m) {
      if (mounted) setState(() => _liveLabel = m['label'] as String?);
    });
  }

  @override
  void didUpdateWidget(_TrackCell old) {
    super.didUpdateWidget(old);
    if (!_dragging) {
      _localVolume = null;
      _liveLabel = null;
    }
  }

  @override
  void dispose() {
    _labelSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ableton = context.read<AbletonProvider>();
    final isMuted = widget.track.mute;
    final isSolo = widget.track.solo;
    final col = context.col;

    return Container(
      width: 66,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: col.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSolo
              ? AppTheme.warning
              : isMuted
                  ? col.border.withValues(alpha: 0.4)
                  : col.border,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              widget.track.name,
              style: TextStyle(
                color: isMuted ? col.textMuted : col.textSecondary,
                fontSize: 8,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 2),
          SizedBox(
            height: 72,
            width: 52,
            child: RotatedBox(
              quarterTurns: 3,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2.5,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 5),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 12),
                  activeTrackColor: isMuted
                      ? col.textMuted.withValues(alpha: 0.3)
                      : AppTheme.accent,
                  inactiveTrackColor: col.border,
                  thumbColor: isMuted ? col.textMuted : AppTheme.accent,
                  overlayColor: AppTheme.accent.withValues(alpha: 0.15),
                ),
                child: Slider(
                  value: _volume.clamp(0.0, 1.0),
                  min: 0.0,
                  max: 1.0,
                  onChanged: (v) {
                    setState(() {
                      _dragging = true;
                      _localVolume = v;
                    });
                    ableton.setTrackVolume(widget.track.index, v);
                  },
                  onChangeEnd: (v) {
                    setState(() {
                      _dragging = false;
                      _localVolume = v;
                    });
                    ableton.setTrackVolume(widget.track.index, v);
                  },
                ),
              ),
            ),
          ),
          Text(
            _displayLabel,
            style: TextStyle(
              color: isMuted ? col.textMuted : AppTheme.accent,
              fontSize: 9,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _MiniBtn(
                label: 'M',
                active: isMuted,
                activeColor: AppTheme.danger,
                onTap: () => ableton.muteTrack(widget.track.index),
              ),
              const SizedBox(width: 3),
              _MiniBtn(
                label: 'S',
                active: isSolo,
                activeColor: AppTheme.warning,
                onTap: () => ableton.soloTrack(widget.track.index),
              ),
            ],
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _MiniBtn extends StatelessWidget {
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  const _MiniBtn({
    required this.label,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    return TapScale(
      onTap: onTap,
      pressedScale: 0.85,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 24,
        height: 16,
        decoration: BoxDecoration(
          color: active ? activeColor : col.surfaceElevated,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: active ? activeColor : col.border,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.black : col.textMuted,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _MasterCell extends StatefulWidget {
  const _MasterCell();

  @override
  State<_MasterCell> createState() => _MasterCellState();
}

class _MasterCellState extends State<_MasterCell> {
  double? _localVolume;
  bool _dragging = false;
  String? _liveLabel;
  StreamSubscription<String>? _labelSub;

  String get _displayLabel {
    final raw = _dragging
        ? (_liveLabel ?? context.read<AbletonProvider>().state.masterVolStr)
        : context.read<AbletonProvider>().state.masterVolStr;
    return raw.isEmpty ? '--- dB' : raw;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _labelSub?.cancel();
    _labelSub = context
        .read<AbletonProvider>()
        .masterVolLabelStream
        .listen((label) {
      if (mounted) setState(() => _liveLabel = label);
    });
  }

  @override
  void dispose() {
    _labelSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ableton = context.watch<AbletonProvider>();
    final vol = _localVolume ?? ableton.state.masterVolume;
    final label = _displayLabel;

    return Container(
      width: 70,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 4),
          const Text(
            'MASTER',
            style: TextStyle(
              color: AppTheme.accent,
              fontSize: 7,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 2),
          SizedBox(
            height: 72,
            width: 52,
            child: RotatedBox(
              quarterTurns: 3,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2.5,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  activeTrackColor: AppTheme.accent,
                  inactiveTrackColor: context.col.border,
                  thumbColor: AppTheme.accent,
                  overlayColor: AppTheme.accent.withValues(alpha: 0.15),
                ),
                child: Slider(
                  value: vol.clamp(0.0, 1.0),
                  min: 0.0,
                  max: 1.0,
                  onChanged: (v) {
                    setState(() {
                      _dragging = true;
                      _localVolume = v;
                    });
                    ableton.setMasterVolume(v);
                  },
                  onChangeEnd: (v) {
                    setState(() {
                      _dragging = false;
                      _localVolume = v;
                    });
                    ableton.setMasterVolume(v);
                  },
                ),
              ),
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.accent,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            '${(vol * 100).round()}%',
            style: TextStyle(
              color: context.col.textSecondary,
              fontSize: 8,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _CueCell extends StatefulWidget {
  const _CueCell();

  @override
  State<_CueCell> createState() => _CueCellState();
}

class _CueCellState extends State<_CueCell> {
  double? _localVolume;
  bool _dragging = false;
  String? _liveLabel;
  StreamSubscription<String>? _labelSub;

  static const _color = Color(0xFF7C3AED);

  String get _displayLabel {
    final raw = _dragging
        ? (_liveLabel ?? context.read<AbletonProvider>().state.cueVolStr)
        : context.read<AbletonProvider>().state.cueVolStr;
    return raw.isEmpty ? '--- dB' : raw;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _labelSub?.cancel();
    _labelSub = context.read<AbletonProvider>().cueVolLabelStream.listen((label) {
      if (mounted) setState(() => _liveLabel = label);
    });
  }

  @override
  void dispose() {
    _labelSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ableton = context.watch<AbletonProvider>();
    final vol = _localVolume ?? ableton.state.cueVolume;

    return Container(
      width: 70,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _color.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 4),
          const Text(
            'CUE OUT',
            style: TextStyle(
              color: _color,
              fontSize: 7,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 2),
          SizedBox(
            height: 72,
            width: 52,
            child: RotatedBox(
              quarterTurns: 3,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2.5,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  activeTrackColor: _color,
                  inactiveTrackColor: context.col.border,
                  thumbColor: _color,
                  overlayColor: _color.withValues(alpha: 0.15),
                ),
                child: Slider(
                  value: vol.clamp(0.0, 1.0),
                  min: 0.0,
                  max: 1.0,
                  onChanged: (v) {
                    setState(() {
                      _dragging = true;
                      _localVolume = v;
                    });
                    ableton.setCueVolume(v);
                  },
                  onChangeEnd: (v) {
                    setState(() {
                      _dragging = false;
                      _localVolume = v;
                    });
                    ableton.setCueVolume(v);
                  },
                ),
              ),
            ),
          ),
          Text(
            _displayLabel,
            style: const TextStyle(
              color: _color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            '${(vol * 100).round()}%',
            style: TextStyle(
              color: _color.withValues(alpha: 0.6),
              fontSize: 8,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
