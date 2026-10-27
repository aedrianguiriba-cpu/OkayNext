/// One device currently watching through the phone monitor.
class MonitorClient {
  final int id;
  final String ip;
  final String userAgent;
  final DateTime since;

  /// True when it connected from this same PC (e.g. a browser tab here).
  final bool isThisPc;

  MonitorClient({
    required this.id,
    required this.ip,
    required this.userAgent,
    required this.since,
    required this.isThisPc,
  });

  String get device => describeDevice(userAgent, isThisPc: isThisPc);

  /// "iPhone", "Android (SM-S908B)", "Windows PC", ...
  DeviceKind get kind => deviceKind(userAgent, isThisPc: isThisPc);
}

enum DeviceKind { phone, tablet, computer, unknown }

DeviceKind deviceKind(String ua, {bool isThisPc = false}) {
  final u = ua.toLowerCase();
  if (isThisPc && !u.contains('iphone') && !u.contains('android')) {
    return DeviceKind.computer;
  }
  if (u.contains('ipad') || (u.contains('android') && !u.contains('mobile'))) {
    return DeviceKind.tablet;
  }
  if (u.contains('iphone') || u.contains('android') || u.contains('mobile')) {
    return DeviceKind.phone;
  }
  if (u.contains('windows') || u.contains('macintosh') || u.contains('linux') ||
      u.contains('cros')) {
    return DeviceKind.computer;
  }
  return DeviceKind.unknown;
}

/// A short, human label from the browser's User-Agent text.
String describeDevice(String ua, {bool isThisPc = false}) {
  if (isThisPc) return 'This PC';
  final u = ua.toLowerCase();
  String browser() {
    if (u.contains('edg/') || u.contains('edga/') || u.contains('edgios/')) return 'Edge';
    if (u.contains('opr/') || u.contains('opera')) return 'Opera';
    if (u.contains('samsungbrowser')) return 'Samsung Internet';
    if (u.contains('firefox') || u.contains('fxios')) return 'Firefox';
    if (u.contains('crios') || u.contains('chrome')) return 'Chrome';
    if (u.contains('safari')) return 'Safari';
    return '';
  }

  String base;
  if (u.contains('iphone')) {
    base = 'iPhone';
  } else if (u.contains('ipad')) {
    base = 'iPad';
  } else if (u.contains('android')) {
    // "... (Linux; Android 13; SM-S908B) ..." -> model
    final m = RegExp(r'android[ \d.]*;\s*([^;)]+)', caseSensitive: false).firstMatch(ua);
    final model = m?.group(1)?.trim() ?? '';
    final tablet = !u.contains('mobile');
    final kind = tablet ? 'Android tablet' : 'Android phone';
    base = (model.isEmpty || model.toLowerCase() == 'k') ? kind : '$kind ($model)';
  } else if (u.contains('windows')) {
    base = 'Windows PC';
  } else if (u.contains('macintosh') || u.contains('mac os')) {
    base = 'Mac';
  } else if (u.contains('cros')) {
    base = 'Chromebook';
  } else if (u.contains('linux')) {
    base = 'Linux PC';
  } else {
    base = 'Unknown device';
  }
  final b = browser();
  return b.isEmpty ? base : '$base · $b';
}

/// "just now", "4 min", "1 h 05 min".
String connectedFor(DateTime since, [DateTime? now]) {
  final d = (now ?? DateTime.now()).difference(since);
  if (d.inSeconds < 10) return 'just now';
  if (d.inMinutes < 1) return '${d.inSeconds} s';
  if (d.inHours < 1) return '${d.inMinutes} min';
  final m = (d.inMinutes % 60).toString().padLeft(2, '0');
  return '${d.inHours} h $m min';
}
