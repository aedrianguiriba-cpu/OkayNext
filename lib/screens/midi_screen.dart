import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:provider/provider.dart';
import '../models/midi_mapping.dart';
import '../providers/locator_groups_provider.dart';
import '../providers/midi_provider.dart';
import '../theme/app_theme.dart';

class MidiScreen extends StatefulWidget {
  const MidiScreen({super.key});

  @override
  State<MidiScreen> createState() => _MidiScreenState();
}

class _MidiScreenState extends State<MidiScreen> {
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final midi = context.read<MidiProvider>();
      midi.refreshDevices();
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        if (mounted) midi.refreshDevices();
      });
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final midi = context.watch<MidiProvider>();
    final col = context.col;
    final sceneCount = context.watch<LocatorGroupsProvider>().scenes.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('MIDI'),
        actions: [
          IconButton(
            onPressed: () => _showReferenceSheet(context, midi),
            icon: const Icon(Icons.list_alt_rounded),
            tooltip: 'MIDI Reference',
          ),
          IconButton(
            onPressed: midi.refreshDevices,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh devices',
          ),
          if (midi.learningFor != null)
            TextButton(
              onPressed: midi.cancelLearning,
              child: const Text('Cancel',
                  style: TextStyle(color: AppTheme.danger)),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Devices ────────────────────────────────────────────────────
          _label(context, 'MIDI DEVICES'),
          const SizedBox(height: 8),
          if (midi.devices.isEmpty)
            _empty(context, 'No MIDI devices found.\nConnect a USB or Bluetooth MIDI device and tap ↻.')
          else
            ...midi.devices.map((d) => _DeviceTile(device: d)),

          const SizedBox(height: 24),

          // ── Mappings ───────────────────────────────────────────────────
          Row(
            children: [
              _label(context, 'MAPPINGS'),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _confirmReset(context, midi),
                icon: const Icon(Icons.restore_rounded, size: 14),
                label: const Text('Defaults', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(foregroundColor: col.textMuted),
              ),
              if (midi.mappings.isNotEmpty)
                TextButton(
                  onPressed: () => _confirmClear(context, midi),
                  child: const Text('Clear All',
                      style: TextStyle(color: AppTheme.danger, fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (midi.learningFor != null) _LearnBanner(action: midi.learningFor!),
          const SizedBox(height: 4),
          ...MidiAction.values
              .where((a) => a.sceneIndex == null || a.sceneIndex! < sceneCount)
              .map((a) => _MappingRow(action: a)),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _label(BuildContext context, String text) => Text(
        text,
        style: const TextStyle(
          color: AppTheme.accent,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      );

  Widget _empty(BuildContext context, String msg) {
    final col = context.col;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: col.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: col.border),
      ),
      child: Column(children: [
        Icon(Icons.piano_off_rounded, size: 34, color: col.textMuted),
        const SizedBox(height: 10),
        Text(msg,
            textAlign: TextAlign.center,
            style: TextStyle(color: col.textMuted, fontSize: 12, height: 1.5)),
      ]),
    );
  }

  // ── Reference sheet ───────────────────────────────────────────────────

  void _showReferenceSheet(BuildContext context, MidiProvider midi) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.col.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _ReferenceSheet(
        mappings: midi.mappings,
        sceneCount: context.read<LocatorGroupsProvider>().scenes.length,
      ),
    );
  }

  // ── Confirm dialogs ───────────────────────────────────────────────────

  Future<void> _confirmReset(BuildContext context, MidiProvider midi) async {
    final col = context.col;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: col.surface,
        title: const Text('Reset to defaults?'),
        content: Text(
          'Mappings will be reset to:\n'
          'Play → CC 20  •  Stop → CC 21\n'
          'Next → CC 22  •  Prev → CC 23\n'
          'Record → CC 24  •  Loop → CC 25\n'
          'Master Fader → CC 26  •  Cue Fader → CC 27\n'
          '(all on Channel 1)',
          style: TextStyle(color: col.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Reset')),
        ],
      ),
    );
    if (ok == true) midi.resetToDefaults();
  }

  Future<void> _confirmClear(BuildContext context, MidiProvider midi) async {
    final col = context.col;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: col.surface,
        title: const Text('Clear all mappings?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
              child: const Text('Clear All')),
        ],
      ),
    );
    if (ok == true) midi.clearAllMappings();
  }
}

// ── Reference sheet ───────────────────────────────────────────────────────────

class _ReferenceSheet extends StatelessWidget {
  final List<MidiMapping> mappings;
  final int sceneCount;
  const _ReferenceSheet({required this.mappings, required this.sceneCount});

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'MIDI REFERENCE',
                style: TextStyle(
                  color: AppTheme.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, size: 20),
                color: col.textMuted,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Program your MIDI controller to send these messages:',
            style: TextStyle(color: col.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 16),
          if (mappings.isEmpty)
            Text(
              'No mappings set. Tap "Defaults" to load the default assignments.',
              style: TextStyle(color: col.textMuted, fontSize: 13),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(flex: 3, child: _ColHeader('ACTION')),
                  Expanded(flex: 2, child: _ColHeader('TYPE')),
                  Expanded(flex: 2, child: _ColHeader('NUMBER')),
                  Expanded(flex: 2, child: _ColHeader('CHANNEL')),
                ],
              ),
            ),
            Divider(color: col.border),
            ...MidiAction.values
                .where((a) => a.sceneIndex == null || a.sceneIndex! < sceneCount)
                .map((action) {
              final m = mappings.where((x) => x.action == action).firstOrNull;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Row(
                        children: [
                          Icon(action.icon, size: 14, color: col.textMuted),
                          const SizedBox(width: 6),
                          Text(action.label,
                              style: TextStyle(
                                  color: col.textPrimary, fontSize: 13)),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        m == null
                            ? '—'
                            : m.msgType == MidiMsgType.cc ? 'CC' : 'Note',
                        style: TextStyle(
                          color: m == null ? col.textMuted : AppTheme.accent,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        m == null ? '—' : '${m.number}',
                        style: TextStyle(
                          color: m == null ? col.textMuted : col.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        m == null ? '—' : '${m.channel + 1}',
                        style: TextStyle(
                          color: m == null ? col.textMuted : col.textPrimary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _ColHeader extends StatelessWidget {
  final String text;
  const _ColHeader(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          color: context.col.textMuted,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      );
}

// ── Device tile ───────────────────────────────────────────────────────────────

class _DeviceTile extends StatelessWidget {
  final MidiDevice device;
  const _DeviceTile({required this.device});

  @override
  Widget build(BuildContext context) {
    final midi = context.watch<MidiProvider>();
    final active = device.connected || midi.connectedDevice?.id == device.id;
    final isBle = device.type == MidiDeviceType.ble;
    final col = context.col;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: active
            ? AppTheme.accent.withValues(alpha: 0.08)
            : col.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: active
                ? AppTheme.accent.withValues(alpha: 0.4)
                : col.border),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Icon(
          isBle ? Icons.bluetooth_rounded : Icons.piano_rounded,
          color: active ? AppTheme.accent : col.textMuted,
          size: 22,
        ),
        title: Text(device.name,
            style: TextStyle(
              color: active ? AppTheme.accent : col.textPrimary,
              fontSize: 14,
              fontWeight: active ? FontWeight.w600 : FontWeight.normal,
            )),
        subtitle: Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: active ? AppTheme.success : col.textMuted,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${device.type.name.toUpperCase()}  ·  ${active ? 'Connected' : 'Available'}',
              style: TextStyle(
                  color: active
                      ? AppTheme.accent.withValues(alpha: 0.7)
                      : col.textMuted,
                  fontSize: 11),
            ),
          ],
        ),
        trailing: active
            ? OutlinedButton(
                onPressed: midi.disconnectDevice,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.danger,
                  side: const BorderSide(color: AppTheme.danger),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Disconnect', style: TextStyle(fontSize: 12)),
              )
            : ElevatedButton(
                onPressed: () =>
                    context.read<MidiProvider>().connectToDevice(device),
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Connect', style: TextStyle(fontSize: 12)),
              ),
      ),
    );
  }
}

// ── Mapping row ───────────────────────────────────────────────────────────────

class _MappingRow extends StatelessWidget {
  final MidiAction action;
  const _MappingRow({required this.action});

  @override
  Widget build(BuildContext context) {
    final midi = context.watch<MidiProvider>();
    final mapping = midi.mappingFor(action);
    final learning = midi.learningFor == action;
    final col = context.col;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: learning
            ? AppTheme.accent.withValues(alpha: 0.1)
            : col.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: learning
              ? AppTheme.accent
              : mapping != null
                  ? AppTheme.accent.withValues(alpha: 0.25)
                  : col.border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(action.icon,
                size: 20,
                color: learning ? AppTheme.accent : col.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(action.label,
                      style: TextStyle(
                        color: learning ? AppTheme.accent : col.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      )),
                  const SizedBox(height: 2),
                  Text(
                    learning
                        ? (action.isContinuous
                            ? 'Move a knob or fader on your device…'
                            : 'Press a button on your device…')
                        : mapping?.displayName ?? 'Not assigned',
                    style: TextStyle(
                      color: learning
                          ? AppTheme.accent.withValues(alpha: 0.8)
                          : mapping != null
                              ? col.textSecondary
                              : col.textMuted,
                      fontSize: 11,
                      fontStyle: mapping == null && !learning
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                  ),
                ],
              ),
            ),
            if (learning)
              TextButton(
                onPressed: midi.cancelLearning,
                style: TextButton.styleFrom(foregroundColor: col.textMuted),
                child: const Text('Cancel', style: TextStyle(fontSize: 12)),
              )
            else ...[
              IconButton(
                onPressed: () => _showEditDialog(context, action, mapping),
                icon: const Icon(Icons.edit_rounded, size: 15),
                color: col.textMuted,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                tooltip: 'Enter manually',
              ),
              const SizedBox(width: 2),
              if (mapping != null)
                IconButton(
                  onPressed: () => midi.removeMapping(action),
                  icon: const Icon(Icons.clear_rounded, size: 15),
                  color: col.textMuted,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                  tooltip: 'Remove',
                ),
              const SizedBox(width: 4),
              OutlinedButton(
                onPressed: () => midi.startLearning(action),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.accent,
                  side: BorderSide(
                      color: AppTheme.accent.withValues(alpha: 0.5)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('LEARN',
                    style:
                        TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showEditDialog(
      BuildContext context, MidiAction action, MidiMapping? current) async {
    var selectedType = current?.msgType ?? MidiMsgType.cc;
    var numberCtrl =
        TextEditingController(text: '${current?.number ?? 20}');
    var channelCtrl =
        TextEditingController(text: '${(current?.channel ?? 0) + 1}');
    final col = context.col;

    final result = await showDialog<MidiMapping>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: col.surface,
          title: Row(
            children: [
              Icon(action.icon, size: 18, color: AppTheme.accent),
              const SizedBox(width: 8),
              Text(action.label),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text('Type', style: TextStyle(color: col.textSecondary, fontSize: 13)),
                  const SizedBox(width: 12),
                  _TypeChip(
                    label: 'CC',
                    selected: selectedType == MidiMsgType.cc,
                    onTap: () => setSt(() => selectedType = MidiMsgType.cc),
                  ),
                  if (!action.isContinuous) ...[
                    const SizedBox(width: 8),
                    _TypeChip(
                      label: 'Note',
                      selected: selectedType == MidiMsgType.noteOn,
                      onTap: () => setSt(() => selectedType = MidiMsgType.noteOn),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: numberCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        _RangeFormatter(0, 127),
                      ],
                      decoration: InputDecoration(
                        labelText: selectedType == MidiMsgType.cc
                            ? 'CC Number  (0–127)'
                            : 'Note Number  (0–127)',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 80,
                    child: TextField(
                      controller: channelCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        _RangeFormatter(1, 16),
                      ],
                      decoration: const InputDecoration(labelText: 'Channel'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final num = int.tryParse(numberCtrl.text) ?? 0;
                final ch = (int.tryParse(channelCtrl.text) ?? 1).clamp(1, 16) - 1;
                Navigator.pop(
                    ctx,
                    MidiMapping(
                        msgType: selectedType,
                        channel: ch,
                        number: num,
                        action: action));
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (result != null && context.mounted) {
      context.read<MidiProvider>().setMapping(result);
    }
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TypeChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.accent.withValues(alpha: 0.15)
              : col.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: selected ? AppTheme.accent : col.border),
        ),
        child: Text(label,
            style: TextStyle(
              color: selected ? AppTheme.accent : col.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            )),
      ),
    );
  }
}

class _RangeFormatter extends TextInputFormatter {
  final int min, max;
  const _RangeFormatter(this.min, this.max);

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue old, TextEditingValue value) {
    if (value.text.isEmpty) return value;
    final n = int.tryParse(value.text);
    if (n == null) return old;
    if (n < min) return value.copyWith(text: '$min');
    if (n > max) return value.copyWith(text: '$max');
    return value;
  }
}

// ── Learn banner ──────────────────────────────────────────────────────────────

class _LearnBanner extends StatefulWidget {
  final MidiAction action;
  const _LearnBanner({required this.action});

  @override
  State<_LearnBanner> createState() => _LearnBannerState();
}

class _LearnBannerState extends State<_LearnBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _alpha;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _alpha = Tween<double>(begin: 0.5, end: 1.0)
        .animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));
    _pulse.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _alpha,
      builder: (_, _) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.accent.withValues(alpha: 0.08 * _alpha.value),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: AppTheme.accent.withValues(alpha: 0.6 * _alpha.value)),
        ),
        child: Row(
          children: [
            Icon(Icons.hearing_rounded,
                size: 18,
                color: AppTheme.accent.withValues(alpha: _alpha.value)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.action.isContinuous
                    ? 'Listening… move a knob or fader on your device to assign it to "${widget.action.label}".'
                    : 'Listening… press a button on your device to assign it to "${widget.action.label}".',
                style: TextStyle(
                    color: AppTheme.accent.withValues(alpha: _alpha.value),
                    fontSize: 12,
                    height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
