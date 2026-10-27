import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/monitor_server.dart';
import '../theme/app_theme.dart';
import '../utils/lan_info.dart';

/// Port that `serve_web.bat` serves the phone monitor page on.
const int kMonitorPort = 8090;

/// Shows a QR code that opens the phone monitor page when scanned.
Future<void> showPhoneMonitorDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const PhoneMonitorDialog(),
);

class PhoneMonitorDialog extends StatefulWidget {
  /// Lookups are parameters so tests can simulate network changes.
  final Future<LanAddress?> Function() fetchAddress;
  final MonitorServer? server;
  final Duration pollEvery;

  const PhoneMonitorDialog({
    super.key,
    this.fetchAddress = primaryLanAddress,
    this.server,
    this.pollEvery = const Duration(seconds: 3),
  });

  @override
  State<PhoneMonitorDialog> createState() => _PhoneMonitorDialogState();
}

class _PhoneMonitorDialogState extends State<PhoneMonitorDialog> {
  LanAddress? _addr;
  bool _loading = true;
  bool _addressChanged = false;
  StreamSubscription<void>? _serverSub;

  MonitorServer get _server => widget.server ?? MonitorServer.instance;
  Timer? _poll;
  Timer? _noticeTimer;

  String? get _url =>
      _addr == null ? null : 'http://${_addr!.ip}:$kMonitorPort';

  @override
  void initState() {
    super.initState();
    _refresh();
    _serverSub = _server.changes.listen((_) {
      if (mounted) setState(() {});
    });
    // Follow the network: if the PC's address changes (Wi-Fi switched, cable
    // plugged in, router gave a new lease) the QR code updates by itself.
    _poll = Timer.periodic(widget.pollEvery, (_) => _pollNetwork());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _noticeTimer?.cancel();
    _serverSub?.cancel();
    super.dispose();
  }

  /// Quiet background check; no spinner.
  bool _polling = false;

  Future<void> _pollNetwork() async {
    if (_polling) return; // the previous check is still running
    _polling = true;
    try {
      await _pollOnce();
    } finally {
      _polling = false;
    }
  }

  Future<void> _pollOnce() async {
    final addr = await widget.fetchAddress();
    if (!mounted) return;
    final changed = addr != _addr;
    final oldUrl = _url;
    // Always rebuild: keeps the "connected for ..." times current.
    setState(() {
      if (changed) _addr = addr;
    });
    if (changed && _url != oldUrl) {
      setState(() => _addressChanged = true);
      _noticeTimer?.cancel();
      _noticeTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _addressChanged = false);
      });
    }
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final addr = await widget.fetchAddress();
    if (!mounted) return;
    setState(() {
      _addr = addr;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    final url = _url;

    return AlertDialog(
      backgroundColor: col.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          const Icon(Icons.qr_code_2_rounded, color: AppTheme.accent),
          const SizedBox(width: 10),
          Text(
            'Phone monitor',
            style: TextStyle(color: col.textPrimary, fontSize: 17),
          ),
        ],
      ),
      content: SizedBox(
        width: 320,
        // Scrolls on short windows (QR + several devices is tall). Done here
        // rather than with AlertDialog(scrollable: true), which breaks the
        // layout of this content and leaves the dialog blank.
        child: SingleChildScrollView(
          child: _loading
              ? const SizedBox(
                  height: 200,
                  child: Center(child: CircularProgressIndicator()),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (url == null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          "Couldn't find this PC's network address. Connect to "
                          'Wi-Fi or Ethernet and try again.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: col.textSecondary),
                        ),
                      )
                    else ...[
                      Center(
                        // QR codes need a light background to scan reliably.
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: QrImageView(
                            key: ValueKey(url),
                            data: url,
                            size: 200,
                            backgroundColor: Colors.white,
                            eyeStyle: const QrEyeStyle(
                              eyeShape: QrEyeShape.square,
                              color: Colors.black,
                            ),
                            dataModuleStyle: const QrDataModuleStyle(
                              dataModuleShape: QrDataModuleShape.square,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SelectableText(
                        url,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: col.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'via ${_addr!.interfaceName}',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: col.textMuted, fontSize: 12),
                      ),
                      if (_addressChanged) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Network changed. The link and code were updated.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppTheme.accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      _ServerStatus(server: _server),
                      const SizedBox(height: 12),
                      _DevicesList(clients: _server.clients),
                      const SizedBox(height: 10),
                      Text(
                        'Phone and PC must be on the same Wi-Fi. Scan with the '
                        'phone camera. Any number of phones can watch at once.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: col.textMuted,
                          fontSize: 11,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ),
      actions: [
        if (url != null)
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                const SnackBar(
                  content: Text('Link copied'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Copy link'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close', style: TextStyle(color: AppTheme.accent)),
        ),
      ],
    );
  }
}

/// On/off switch for the built-in phone monitor, with what it's doing.
class _ServerStatus extends StatelessWidget {
  final MonitorServer server;
  const _ServerStatus({required this.server});

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    final (color, text) = server.running
        ? (AppTheme.success, 'Phone monitor is on')
        : server.enabled
        ? (AppTheme.warning, server.error ?? 'Starting the phone monitor…')
        : (col.textMuted, 'Phone monitor is off');
    return Container(
      padding: const EdgeInsets.only(left: 12, right: 4, top: 2, bottom: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Switch(
            value: server.enabled,
            activeThumbColor: AppTheme.accent,
            onChanged: server.setEnabled,
          ),
        ],
      ),
    );
  }
}

/// Who is watching right now.
class _DevicesList extends StatelessWidget {
  final List<MonitorClient> clients;
  const _DevicesList({required this.clients});

  IconData _icon(DeviceKind k) => switch (k) {
    DeviceKind.phone => Icons.smartphone_rounded,
    DeviceKind.tablet => Icons.tablet_android_rounded,
    DeviceKind.computer => Icons.computer_rounded,
    DeviceKind.unknown => Icons.devices_other_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'CONNECTED DEVICES',
              style: TextStyle(
                color: col.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: clients.isEmpty
                    ? col.surfaceElevated
                    : AppTheme.accent.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${clients.length}',
                style: TextStyle(
                  color: clients.isEmpty ? col.textMuted : AppTheme.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (clients.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No devices connected yet. Scan the code with a phone.',
              style: TextStyle(color: col.textMuted, fontSize: 12),
            ),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final c in clients)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: col.surfaceVariant,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: col.border),
                    ),
                    child: Row(
                      children: [
                        Icon(_icon(c.kind), size: 18, color: AppTheme.accent),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c.device,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: col.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '${c.ip}  ·  ${connectedFor(c.since)}',
                                style: TextStyle(
                                  color: col.textMuted,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: AppTheme.success,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
