import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/ableton_state.dart';
import '../providers/ableton_provider.dart';
import '../theme/app_theme.dart';
import 'performance_screen.dart';

/// Root screen of the browser build: a view-only mirror of what Ableton is
/// doing. Shows the performance view when connected, otherwise a small form to
/// point at the PC running Ableton.
class MonitorScreen extends StatelessWidget {
  const MonitorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ableton = context.watch<AbletonProvider>();
    if (ableton.isConnected) {
      return const PerformanceScreen(monitor: true);
    }
    return const _MonitorConnect();
  }
}

class _MonitorConnect extends StatefulWidget {
  const _MonitorConnect();

  @override
  State<_MonitorConnect> createState() => _MonitorConnectState();
}

class _MonitorConnectState extends State<_MonitorConnect> {
  late final TextEditingController _host;
  late final TextEditingController _port;

  @override
  void initState() {
    super.initState();
    final p = context.read<AbletonProvider>();
    _host = TextEditingController(text: p.host);
    _port = TextEditingController(text: '${p.port}');
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  void _connect() {
    final port = int.tryParse(_port.text.trim()) ?? 9000;
    context.read<AbletonProvider>().saveSettings(_host.text.trim(), port);
  }

  // The provider loads its default host a moment after startup; fill the
  // field once it's known, but never overwrite what the user typed.
  bool _seeded = false;

  @override
  Widget build(BuildContext context) {
    final ableton = context.watch<AbletonProvider>();
    final col = context.col;
    final connecting =
        ableton.state.connectionStatus == ConnectionStatus.connecting;

    if (!_seeded && ableton.host.isNotEmpty) {
      _seeded = true;
      if (_host.text.isEmpty) _host.text = ableton.host;
      _port.text = '${ableton.port}';
    }

    return Scaffold(
      backgroundColor: col.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.visibility_outlined,
                      size: 44, color: AppTheme.accent),
                  const SizedBox(height: 14),
                  Text(
                    'OkayNext Monitor',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: col.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    connecting
                        ? 'Connecting to ${ableton.host}:${ableton.port}…'
                        : "Can't reach Ableton at ${ableton.host}:${ableton.port}",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: connecting ? AppTheme.warning : col.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 22),
                  TextField(
                    controller: _host,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    style: TextStyle(color: col.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'PC address (IP)',
                      hintText: '192.168.1.20',
                    ),
                    onSubmitted: (_) => _connect(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _port,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: col.textPrimary),
                    decoration: const InputDecoration(labelText: 'Port'),
                    onSubmitted: (_) => _connect(),
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: _connect,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Connect',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Make sure Ableton is open and this phone is on the same '
                    'Wi-Fi as the PC. If the page loads but never connects, '
                    "Windows Firewall may be blocking Ableton's port 9000 "
                    '(see the README). This view is read-only.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: col.textMuted, fontSize: 12, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
