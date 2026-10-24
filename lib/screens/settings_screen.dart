import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/ableton_state.dart';
import '../providers/ableton_provider.dart';
import '../providers/key_bindings_provider.dart';
import '../providers/midi_provider.dart';
import '../theme/app_theme.dart';
import '../theme/theme_provider.dart';
import '../widgets/connection_indicator.dart';
import 'midi_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late TextEditingController _hostCtrl;
  late TextEditingController _portCtrl;
  Map<String, dynamic>? _debugResult;
  bool _debugLoading = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    final p = context.read<AbletonProvider>();
    _hostCtrl = TextEditingController(text: p.host);
    _portCtrl = TextEditingController(text: p.port.toString());
  }

  @override
  void dispose() {
    _tabs.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  Future<void> _runDiagnostics() async {
    final ableton = context.read<AbletonProvider>();
    setState(() { _debugLoading = true; _debugResult = null; });
    ableton.sendDebug();
    final result = await ableton.debugStream.first
        .timeout(const Duration(seconds: 5), onTimeout: () => {'error': 'Timeout — no response from Ableton'});
    if (mounted) setState(() { _debugResult = result; _debugLoading = false; });
  }

  Future<void> _save() async {
    final port = int.tryParse(_portCtrl.text) ?? 9000;
    final ableton = context.read<AbletonProvider>();
    await ableton.saveSettings(_hostCtrl.text.trim(), port);
    ableton.connect();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Connecting…'),
        backgroundColor: AppTheme.accentDark,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ableton = context.watch<AbletonProvider>();
    final col = context.col;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          const Padding(padding: EdgeInsets.only(right: 16), child: ConnectionIndicator()),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: AppTheme.accent,
          labelColor: AppTheme.accent,
          unselectedLabelColor: col.textSecondary,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          tabs: const [
            Tab(icon: Icon(Icons.wifi_rounded, size: 18), text: 'General'),
            Tab(icon: Icon(Icons.tune_rounded, size: 18), text: 'Controls'),
            Tab(icon: Icon(Icons.help_outline_rounded, size: 18), text: 'Help'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _generalTab(ableton, col),
          _controlsTab(),
          _helpTab(ableton, col),
        ],
      ),
    );
  }

  // ── Tab: General ────────────────────────────────────────────────────────────

  Widget _generalTab(AbletonProvider ableton, AppColors col) {
    final state = ableton.state;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        _StatusCard(ableton: ableton),
        const SizedBox(height: 24),

        _Section(
          title: 'Connection',
          icon: Icons.wifi_rounded,
          children: [
            Text(
              'Use 127.0.0.1 if Ableton is on the same machine.',
              style: TextStyle(color: col.textSecondary, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _hostCtrl,
              decoration: const InputDecoration(
                labelText: 'Ableton Host',
                hintText: '127.0.0.1',
                prefixIcon: Icon(Icons.computer_rounded),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _portCtrl,
              decoration: const InputDecoration(
                labelText: 'Port',
                hintText: '9000',
                prefixIcon: Icon(Icons.router_rounded),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save_rounded),
                    label: const Text('Save & Connect'),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: ableton.isConnected ? ableton.disconnect : null,
                  icon: const Icon(Icons.link_off_rounded),
                  label: const Text('Disconnect'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.danger,
                    side: const BorderSide(color: AppTheme.danger),
                  ),
                ),
              ],
            ),
            if (state.errorMessage != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 14, color: AppTheme.warning),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      state.errorMessage!,
                      style: const TextStyle(color: AppTheme.warning, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        const SizedBox(height: 24),

        _Section(
          title: 'Appearance',
          icon: Icons.palette_outlined,
          children: [const _ThemeToggle()],
        ),
      ],
    );
  }

  // ── Tab: Controls ───────────────────────────────────────────────────────────

  Widget _controlsTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        _Section(
          title: 'MIDI',
          icon: Icons.piano_rounded,
          children: [_MidiCard()],
        ),
        const SizedBox(height: 24),

        _Section(
          title: 'Keyboard Shortcuts',
          icon: Icons.keyboard_rounded,
          children: [const _KeyBindingsSection()],
        ),
      ],
    );
  }

  // ── Tab: Help ───────────────────────────────────────────────────────────────

  Widget _helpTab(AbletonProvider ableton, AppColors col) {
    final state = ableton.state;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        _Section(
          title: 'Setup Guide',
          icon: Icons.integration_instructions_outlined,
          children: [
            _Step(
              number: '1',
              title: 'Copy the MIDI Remote Script',
              body: 'Copy the OkNext folder from ableton_remote_script/ '
                  'into Ableton\'s User Remote Scripts folder:\n\n'
                  'Windows: %APPDATA%\\Ableton\\Live x.x.x\\Preferences\\User Remote Scripts\\\n'
                  'macOS: ~/Library/Preferences/Ableton/Live x.x.x/User Remote Scripts/',
            ),
            const SizedBox(height: 12),
            _Step(
              number: '2',
              title: 'Select it in Ableton',
              body: 'Ableton → Preferences → Link / Tempo / MIDI\n'
                  'Under Control Surface, pick OkNext.\n'
                  'Input and Output can be left as "None".',
            ),
            const SizedBox(height: 12),
            _Step(
              number: '3',
              title: 'Connect from the app',
              body: 'Enter your Ableton computer\'s IP above and tap '
                  '"Save & Connect". The app reconnects automatically on every launch.',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.accent.withValues(alpha: 0.28)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: AppTheme.accent),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No extra software needed — the WebSocket server runs directly inside Ableton.',
                      style: TextStyle(color: AppTheme.accent, fontSize: 12, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        _Section(
          title: 'Diagnostics',
          icon: Icons.bug_report_outlined,
          children: [
            ElevatedButton.icon(
              onPressed: ableton.isConnected && !_debugLoading ? _runDiagnostics : null,
              icon: _debugLoading
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Icon(Icons.bug_report_rounded, size: 16),
              label: Text(_debugLoading ? 'Waiting…' : 'Run Diagnostics'),
            ),
            if (_debugResult != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: col.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: col.border),
                ),
                child: _debugResult!.containsKey('error')
                    ? Text(_debugResult!['error'].toString(),
                        style: const TextStyle(color: AppTheme.danger, fontSize: 12))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _InfoRow('Project', _debugResult!['project']?.toString() ?? '—'),
                          _InfoRow('Cue points', '${_debugResult!['cue_count'] ?? 0}'),
                          _InfoRow('Tracks', '${_debugResult!['track_count'] ?? 0}'),
                          _InfoRow('Groups detected', '${_debugResult!['group_count'] ?? '—'}'),
                          _InfoRow('sig_numerator', '${_debugResult!['sig_numerator'] ?? '—'}'),
                          _InfoRow('sig_denominator', '${_debugResult!['sig_denominator'] ?? '—'}'),
                          if (_debugResult!['beat_time'] != null)
                            _InfoRow('BeatTime', _debugResult!['beat_time'].toString()),
                          if ((_debugResult!['groups'] as List?)?.isNotEmpty == true) ...[
                            const SizedBox(height: 8),
                            Text('Groups:', style: TextStyle(color: col.textMuted, fontSize: 11)),
                            const SizedBox(height: 4),
                            ...(_debugResult!['groups'] as List).map((n) => Padding(
                                  padding: const EdgeInsets.only(left: 8, bottom: 2),
                                  child: Text('• $n', style: TextStyle(color: AppTheme.accent, fontSize: 12)),
                                )),
                            const SizedBox(height: 8),
                          ],
                          if ((_debugResult!['cue_names'] as List?)?.isNotEmpty == true) ...[
                            const SizedBox(height: 4),
                            Text('Locator names:', style: TextStyle(color: col.textMuted, fontSize: 11)),
                            const SizedBox(height: 4),
                            ...(_debugResult!['cue_names'] as List).map((n) => Padding(
                                  padding: const EdgeInsets.only(left: 8, bottom: 2),
                                  child: Text('• $n', style: TextStyle(color: col.textSecondary, fontSize: 12)),
                                )),
                          ],
                        ],
                      ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 24),

        _Section(
          title: 'About',
          icon: Icons.info_outline_rounded,
          children: [
            _InfoRow('App', 'OkNext'),
            _InfoRow('Version', '1.0.0'),
            _InfoRow('Protocol', 'WebSocket JSON'),
            _InfoRow('Locators', '${state.locators.length} found'),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ThemeToggle extends StatelessWidget {
  const _ThemeToggle();

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final col = context.col;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: col.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: col.border),
      ),
      child: Row(
        children: [
          _ThemeBtn(
            icon: Icons.brightness_auto_rounded,
            label: 'System',
            selected: themeProvider.mode == ThemeMode.system,
            onTap: () => themeProvider.setMode(ThemeMode.system),
          ),
          _ThemeBtn(
            icon: Icons.light_mode_rounded,
            label: 'Light',
            selected: themeProvider.mode == ThemeMode.light,
            onTap: () => themeProvider.setMode(ThemeMode.light),
          ),
          _ThemeBtn(
            icon: Icons.dark_mode_rounded,
            label: 'Dark',
            selected: themeProvider.mode == ThemeMode.dark,
            onTap: () => themeProvider.setMode(ThemeMode.dark),
          ),
        ],
      ),
    );
  }
}

class _ThemeBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeBtn({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppTheme.accent.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            border: selected
                ? Border.all(color: AppTheme.accent.withValues(alpha: 0.5))
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? AppTheme.accent : col.textSecondary,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: selected ? AppTheme.accent : col.textSecondary,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
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

class _StatusCard extends StatelessWidget {
  final AbletonProvider ableton;
  const _StatusCard({required this.ableton});

  @override
  Widget build(BuildContext context) {
    final s = ableton.state;
    final connected = ableton.isConnected;
    final col = context.col;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: col.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: col.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const ConnectionIndicator(),
              const Spacer(),
              if (connected)
                Text(
                  '${ableton.host}:${ableton.port}',
                  style: TextStyle(color: col.textMuted, fontSize: 11),
                ),
            ],
          ),
          if (connected) ...[
            const SizedBox(height: 12),
            Divider(color: col.border),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatChip('BPM', s.bpm.toStringAsFixed(1)),
                _StatChip('TIME SIG', '${s.timeSigNumerator}/${s.timeSigDenominator}'),
                _StatChip(
                  'STATUS',
                  s.isPlaying ? 'PLAYING' : 'STOPPED',
                  valueColor: s.isPlaying ? AppTheme.success : col.textSecondary,
                ),
                _StatChip('LOCATORS', '${s.locators.length}'),
              ],
            ),
          ] else ...[
            const SizedBox(height: 10),
            if (s.connectionStatus == ConnectionStatus.connecting)
              Text('Connecting to ${ableton.host}:${ableton.port}…',
                  style: TextStyle(color: col.textMuted, fontSize: 12))
            else
              Text(
                'Not connected — retrying…',
                style: TextStyle(color: col.textMuted, fontSize: 12),
              ),
          ],
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _StatChip(this.label, this.value, {this.valueColor});

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? col.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(label,
            style: TextStyle(color: col.textMuted, fontSize: 9)),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  final String number;
  final String title;
  final String body;
  const _Step({required this.number, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: const BoxDecoration(
            color: AppTheme.accent,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(number,
                style: const TextStyle(
                    color: Colors.black,
                    fontSize: 13,
                    fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      color: col.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(body,
                  style: TextStyle(
                      color: col.textSecondary,
                      fontSize: 12,
                      height: 1.5)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  const _Section({required this.title, required this.icon, required this.children});

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row
        Row(
          children: [
            Icon(icon, size: 13, color: AppTheme.accent),
            const SizedBox(width: 6),
            Text(
              title.toUpperCase(),
              style: const TextStyle(
                color: AppTheme.accent,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Card container
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: col.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: col.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(color: col.textSecondary, fontSize: 13)),
          Text(value,
              style: TextStyle(
                  color: col.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// ── Keyboard Shortcuts ────────────────────────────────────────────────────────

class _KeyBindingsSection extends StatelessWidget {
  const _KeyBindingsSection();

  @override
  Widget build(BuildContext context) {
    final kb = context.watch<KeyBindingsProvider>();
    final col = context.col;

    return Column(
      children: [
        for (final action in KeyAction.values) ...[
          _KeyBindingRow(action: action, kb: kb),
          if (action != KeyAction.values.last)
            Divider(height: 1, color: col.border),
        ],
      ],
    );
  }
}

class _KeyBindingRow extends StatelessWidget {
  final KeyAction action;
  final KeyBindingsProvider kb;
  const _KeyBindingRow({required this.action, required this.kb});

  Future<void> _capture(BuildContext context) async {
    final captured = await showDialog<LogicalKeyboardKey>(
      context: context,
      builder: (_) => _KeyCaptureDialog(
        action: action,
        current: kb.keyFor(action),
        isConflict: (key) => KeyAction.values
            .where((a) => a != action)
            .any((a) => kb.keyFor(a) == key),
      ),
    );
    if (captured != null && context.mounted) {
      context.read<KeyBindingsProvider>().setBinding(action, captured);
    }
  }

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    final isCustom = kb.isCustom(action);
    final keyName = KeyBindingsProvider.displayName(kb.keyFor(action));

    return InkWell(
      onTap: () => _capture(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            Icon(action.icon, size: 18, color: col.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                action.label,
                style: TextStyle(color: col.textPrimary, fontSize: 13),
              ),
            ),
            // Key badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isCustom
                    ? AppTheme.accent.withValues(alpha: 0.1)
                    : col.surfaceElevated,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isCustom
                      ? AppTheme.accent.withValues(alpha: 0.4)
                      : col.border,
                ),
              ),
              child: Text(
                keyName,
                style: TextStyle(
                  color: isCustom ? AppTheme.accent : col.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            if (isCustom) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => context.read<KeyBindingsProvider>().resetBinding(action),
                child: Icon(Icons.refresh_rounded, size: 16, color: col.textMuted),
              ),
            ],
            const SizedBox(width: 4),
            Icon(Icons.edit_rounded, size: 14, color: col.textMuted),
          ],
        ),
      ),
    );
  }
}

class _KeyCaptureDialog extends StatefulWidget {
  final KeyAction action;
  final LogicalKeyboardKey current;
  final bool Function(LogicalKeyboardKey) isConflict;
  const _KeyCaptureDialog({
    required this.action,
    required this.current,
    required this.isConflict,
  });

  @override
  State<_KeyCaptureDialog> createState() => _KeyCaptureDialogState();
}

class _KeyCaptureDialogState extends State<_KeyCaptureDialog> {
  final _focus = FocusNode();
  LogicalKeyboardKey? _pending;
  bool _conflict = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;
    // Ignore pure modifiers
    if (key == LogicalKeyboardKey.shift ||
        key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight ||
        key == LogicalKeyboardKey.control ||
        key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight ||
        key == LogicalKeyboardKey.alt ||
        key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight ||
        key == LogicalKeyboardKey.meta ||
        key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight) return;
    // Escape cancels
    if (key == LogicalKeyboardKey.escape) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _pending = key;
      _conflict = widget.isConflict(key);
    });
  }

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    final hasCapture = _pending != null;

    return AlertDialog(
      backgroundColor: col.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(widget.action.icon, size: 20, color: AppTheme.accent),
          const SizedBox(width: 10),
          Text(widget.action.label,
              style: TextStyle(color: col.textPrimary, fontSize: 16)),
        ],
      ),
      content: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: (_, event) {
          _onKey(event);
          return KeyEventResult.handled;
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              hasCapture ? 'Press Confirm to apply, or keep pressing keys.' : 'Press any key to assign it.',
              style: TextStyle(color: col.textSecondary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                color: _conflict
                    ? AppTheme.danger.withValues(alpha: 0.08)
                    : hasCapture
                        ? AppTheme.accent.withValues(alpha: 0.08)
                        : col.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _conflict
                      ? AppTheme.danger.withValues(alpha: 0.5)
                      : hasCapture
                          ? AppTheme.accent.withValues(alpha: 0.5)
                          : col.borderBright,
                ),
              ),
              child: Text(
                hasCapture
                    ? KeyBindingsProvider.displayName(_pending!)
                    : '— waiting —',
                style: TextStyle(
                  color: _conflict
                      ? AppTheme.danger
                      : hasCapture
                          ? AppTheme.accent
                          : col.textMuted,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            if (_conflict) ...[
              const SizedBox(height: 8),
              Text(
                'This key is already assigned to another action.',
                style: TextStyle(color: AppTheme.danger, fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            context.read<KeyBindingsProvider>().resetBinding(widget.action);
            Navigator.pop(context);
          },
          child: Text('Reset', style: TextStyle(color: col.textMuted)),
        ),
        FilledButton(
          onPressed: hasCapture && !_conflict
              ? () => Navigator.pop(context, _pending)
              : null,
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _MidiCard extends StatelessWidget {
  const _MidiCard();

  @override
  Widget build(BuildContext context) {
    final midi = context.watch<MidiProvider>();
    final mappingCount = midi.mappings.length;
    final deviceName = midi.connectedDevice?.name;
    final col = context.col;

    return InkWell(
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const MidiScreen())),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: col.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: deviceName != null
                ? AppTheme.accent.withValues(alpha: 0.4)
                : col.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.piano_rounded,
              size: 22,
              color: deviceName != null ? AppTheme.accent : col.textMuted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    deviceName ?? 'No device connected',
                    style: TextStyle(
                      color: deviceName != null ? col.textPrimary : col.textMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    mappingCount == 0
                        ? 'No mappings — tap to set up'
                        : '$mappingCount button mapping${mappingCount == 1 ? '' : 's'} configured',
                    style: TextStyle(color: col.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: col.textMuted, size: 20),
          ],
        ),
      ),
    );
  }
}
