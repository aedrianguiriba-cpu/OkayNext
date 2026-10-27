import 'dart:io';
import 'lan_address.dart';

/// Adapters a phone can't reach us through (virtual machines, VPNs, ...).
final _virtualAdapter = RegExp(
  r'vethernet|virtualbox|vmware|hyper-v|vbox|wsl|docker|loopback|'
  r'bluetooth|tap-|tun|vpn|tailscale|zerotier|npcap',
  caseSensitive: false,
);

final _wireless = RegExp(r'wi-?fi|wireless|wlan|wlp', caseSensitive: false);

/// Error codes meaning "the machine answered, but nothing listens on that
/// port". That still proves the network link works.
const _refusedCodes = {10061, 111, 61, 10054};

/// Can traffic actually leave through [ip]'s adapter? An unplugged adapter
/// can keep a stale address, so the address alone proves nothing. We try to
/// connect *from* [ip]: first to a public address, then to the likely router
/// (x.x.x.1). Connected, or refused, both mean the link is alive.
Future<bool> _isLinkAlive(String ip) async {
  Future<bool> tryTarget(String host, int port) async {
    try {
      final s = await Socket.connect(host, port,
          sourceAddress: InternetAddress(ip),
          timeout: const Duration(milliseconds: 1500));
      s.destroy();
      return true;
    } on SocketException catch (e) {
      return _refusedCodes.contains(e.osError?.errorCode);
    } catch (_) {
      return false;
    }
  }

  if (await tryTarget('1.1.1.1', 443)) return true;
  final parts = ip.split('.');
  if (parts.length == 4) {
    final gateway = '${parts[0]}.${parts[1]}.${parts[2]}.1';
    if (gateway != ip && await tryTarget(gateway, 80)) return true;
  }
  return false;
}

/// The address the phone should use: one on a network connection that is
/// really up right now.
///
/// Addresses are tested individually (see [_isLinkAlive]), so a leftover
/// address on an unplugged cable or a switched-off adapter is ignored. If
/// Ethernet and Wi-Fi are both genuinely up, wired is preferred, as Windows
/// itself does.
Future<LanAddress?> primaryLanAddress() async {
  final candidates = <LanAddress>[];
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (final i in interfaces) {
      if (_virtualAdapter.hasMatch(i.name)) continue;
      for (final a in i.addresses) {
        if (a.address.startsWith('169.254.')) continue; // link-local
        candidates.add(LanAddress(a.address, i.name));
      }
    }
  } catch (_) {}
  if (candidates.isEmpty) return null;

  int rank(LanAddress a) {
    var r = _wireless.hasMatch(a.interfaceName) ? 10 : 0; // wired first
    if (a.ip.startsWith('192.168.')) {
      r += 0;
    } else if (a.ip.startsWith('10.')) {
      r += 1;
    } else {
      r += 2;
    }
    return r;
  }

  final alive = await Future.wait(candidates.map((c) => _isLinkAlive(c.ip)));
  final working = [
    for (var i = 0; i < candidates.length; i++)
      if (alive[i]) candidates[i],
  ];

  // If nothing answers at all (fully offline), still offer the best-looking
  // address rather than nothing.
  final pool = working.isNotEmpty ? working : candidates;
  pool.sort((a, b) => rank(a).compareTo(rank(b)));
  return pool.first;
}

/// Whether something is accepting connections on this PC at [port].
Future<bool> isLocalPortOpen(int port) async {
  try {
    final s = await Socket.connect('127.0.0.1', port,
        timeout: const Duration(milliseconds: 800));
    s.destroy();
    return true;
  } catch (_) {
    return false;
  }
}
