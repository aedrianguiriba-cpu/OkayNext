import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import 'monitor_client.dart';
export 'monitor_client.dart';

/// The phone monitor, built into the desktop app.
///
/// Serves the web build and forwards each phone's WebSocket to Ableton, all on
/// one port, so the phone never touches Ableton's own port. It is READ-ONLY by
/// construction: every message a phone sends is inspected, and only a short
/// list of queries is passed on. A phone, or anyone else on the network,
/// cannot play, stop, change a fader or alter the setlist through it.
class MonitorServer {
  MonitorServer._();
  static final MonitorServer instance = MonitorServer._();

  /// For tests / custom setups.
  MonitorServer.custom({
    this.port = 8090,
    this.abletonPort = 9000,
    this.webRoot,
  });

  static const _prefKey = 'monitor_server_enabled';

  int port = 8090;
  int abletonPort = 9000;

  /// Folder holding the web build (index.html, main.dart.js, ...).
  Directory? webRoot;

  HttpServer? _server;
  bool get running => _server != null;

  /// Why it isn't running, when it should be (shown in the UI).
  String? error;

  /// User switch (persisted). Default on.
  bool enabled = true;

  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;

  /// Devices watching right now (each open phone page is one).
  final List<MonitorClient> _clients = [];
  List<MonitorClient> get clients => List.unmodifiable(_clients);
  int _nextClientId = 1;

  /// Lets UI tests show devices without real network connections.
  @visibleForTesting
  void debugAddClient(MonitorClient c) {
    _clients.add(c);
    _changes.add(null);
  }

  /// Loads the saved on/off choice and starts the server if enabled.
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled = prefs.getBool(_prefKey) ?? true;
    } catch (_) {}
    webRoot ??= _findWebRoot();
    if (enabled) await start();
  }

  Future<void> setEnabled(bool value) async {
    enabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, value);
    } catch (_) {}
    if (value) {
      await start();
    } else {
      await stop();
    }
    _changes.add(null);
  }

  /// `monitor_web` next to the exe (installed app), or `build/web` found by
  /// walking up from the exe / working directory (development).
  static Directory? _findWebRoot() {
    bool ok(Directory d) => File('${d.path}/index.html').existsSync();
    final exeDir = File(Platform.resolvedExecutable).parent;
    final installed = Directory('${exeDir.path}/monitor_web');
    if (ok(installed)) return installed;
    for (final start in [exeDir, Directory.current]) {
      var d = start;
      for (var i = 0; i < 8; i++) {
        final candidate = Directory('${d.path}/build/web');
        if (ok(candidate)) return candidate;
        if (d.parent.path == d.path) break;
        d = d.parent;
      }
    }
    return null;
  }

  Future<bool> start() async {
    if (_server != null) return true;
    final root = webRoot ?? _findWebRoot();
    if (root == null) {
      error = 'The phone monitor files (monitor_web) were not found.';
      _changes.add(null);
      return false;
    }
    webRoot = root;
    try {
      final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      server.listen(_handle, onError: (_) {});
      _server = server;
      error = null;
    } on SocketException {
      error = 'Port $port is already in use by another program.';
    } catch (e) {
      error = e.toString();
    }
    _changes.add(null);
    return _server != null;
  }

  Future<void> stop() async {
    final s = _server;
    _server = null;
    await s?.close(force: true);
    // Open phone connections are separate sockets; they end with the app or
    // when the phone leaves, but don't list them as watching once we're off.
    _clients.clear();
    _changes.add(null);
  }

  // ── Requests ───────────────────────────────────────────────────────────

  Future<void> _handle(HttpRequest request) async {
    try {
      final upgrade = request.headers.value('upgrade')?.toLowerCase();
      if (upgrade == 'websocket') {
        await _proxyWebSocket(request);
      } else {
        await _serveFile(request);
      }
    } catch (_) {
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  static const _types = {
    '.html': 'text/html; charset=utf-8',
    '.js': 'application/javascript',
    '.mjs': 'application/javascript',
    '.json': 'application/json',
    '.css': 'text/css',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.ico': 'image/x-icon',
    '.svg': 'image/svg+xml',
    '.wasm': 'application/wasm',
    '.ttf': 'font/ttf',
    '.otf': 'font/otf',
    '.woff2': 'font/woff2',
    '.map': 'application/json',
    '.txt': 'text/plain; charset=utf-8',
  };

  Future<void> _serveFile(HttpRequest request) async {
    final res = request.response;
    if (request.method != 'GET' && request.method != 'HEAD') {
      res.statusCode = HttpStatus.methodNotAllowed;
      await res.close();
      return;
    }
    final root = webRoot!.absolute.path.replaceAll('\\', '/');
    var rel = Uri.decodeComponent(request.uri.path);
    if (rel.endsWith('/')) rel += 'index.html';
    // Resolve and make sure we never leave the web root.
    final target = File('$root/$rel').absolute;
    final normalized = target.uri.normalizePath().toFilePath(windows: Platform.isWindows)
        .replaceAll('\\', '/');
    final rootNorm = Directory(root).uri.normalizePath()
        .toFilePath(windows: Platform.isWindows).replaceAll('\\', '/');
    final inside = normalized.toLowerCase().startsWith(
        rootNorm.toLowerCase().endsWith('/') ? rootNorm.toLowerCase() : '${rootNorm.toLowerCase()}/');
    if (!inside || !await File(normalized).exists()) {
      res.statusCode = HttpStatus.notFound;
      await res.close();
      return;
    }
    final file = File(normalized);
    final dot = normalized.lastIndexOf('.');
    final ext = dot == -1 ? '' : normalized.substring(dot).toLowerCase();
    res.headers
      ..set('Content-Type', _types[ext] ?? 'application/octet-stream')
      ..set('Cache-Control', 'no-cache'); // the page changes when rebuilt
    res.contentLength = await file.length();
    if (request.method == 'HEAD') {
      await res.close();
      return;
    }
    await res.addStream(file.openRead());
    await res.close();
  }

  // ── WebSocket proxy (read-only) ────────────────────────────────────────

  Future<void> _proxyWebSocket(HttpRequest request) async {
    Socket upstream;
    try {
      upstream = await Socket.connect('127.0.0.1', abletonPort,
          timeout: const Duration(seconds: 5));
    } catch (_) {
      request.response.statusCode = HttpStatus.badGateway;
      await request.response.close();
      return;
    }
    upstream.setOption(SocketOption.tcpNoDelay, true);

    // Give Ableton the original upgrade request.
    final head = StringBuffer('GET ${request.uri} HTTP/1.1\r\n');
    request.headers.forEach((name, values) {
      // Never negotiate extensions (e.g. compression) with Ableton: messages
      // must stay plain so every one can be inspected before it is forwarded.
      if (name.toLowerCase() == 'sec-websocket-extensions') return;
      for (final v in values) {
        head.write('$name: $v\r\n');
      }
    });
    head.write('\r\n');
    upstream.add(latin1.encode(head.toString()));

    final info = request.connectionInfo;
    final remoteIp = info?.remoteAddress.address ?? '?';
    var isThisPc = info?.remoteAddress.isLoopback ?? false;
    if (!isThisPc && info != null) {
      // Connecting to this PC's own LAN address from this PC shows up as that
      // address, not as loopback.
      try {
        final mine = await NetworkInterface.list(type: InternetAddressType.IPv4);
        isThisPc = mine.any((i) => i.addresses.any((a) => a.address == remoteIp));
      } catch (_) {}
    }
    final client = MonitorClient(
      id: _nextClientId++,
      ip: remoteIp,
      userAgent: request.headers.value('user-agent') ?? '',
      since: DateTime.now(),
      isThisPc: isThisPc,
    );
    final phone = await request.response.detachSocket(writeHeaders: false);
    phone.setOption(SocketOption.tcpNoDelay, true);
    _clients.add(client);
    _changes.add(null);

    var closed = false;
    void closeBoth() {
      if (closed) return;
      closed = true;
      phone.destroy();
      upstream.destroy();
      _clients.removeWhere((c) => c.id == client.id);
      _changes.add(null);
    }

    // Ableton -> phone: pass everything through (it only ever sends data out).
    upstream.listen(
      (data) {
        try {
          phone.add(data);
        } catch (_) {
          closeBoth();
        }
      },
      onDone: closeBoth,
      onError: (_) => closeBoth(),
      cancelOnError: true,
    );

    // Phone -> Ableton: only whole, allowed messages get through.
    final filter = _ClientFrameFilter(
      forward: (bytes) => upstream.add(bytes),
      onViolation: () {}, // dropped silently; the phone page never sends these
    );
    // A phone that goes silent (the page pings every 5 s) is dropped.
    Timer? idle;
    void rearm() {
      idle?.cancel();
      idle = Timer(const Duration(seconds: 45), closeBoth);
    }

    rearm();
    phone.listen(
      (data) {
        rearm();
        filter.add(data);
      },
      onDone: () {
        idle?.cancel();
        closeBoth();
      },
      onError: (_) {
        idle?.cancel();
        closeBoth();
      },
      cancelOnError: true,
    );
  }
}

/// Parses a stream of client->server WebSocket frames and forwards only:
///  * complete single-frame text messages whose JSON `type` is on the short
///    allow-list below (the pure queries the monitor needs), and
///  * control frames (ping, pong, close).
/// Everything else (any command, binary, fragmented or malformed data) is
/// discarded.
class _ClientFrameFilter {
  /// The only message types a phone may send. Explicit, so a command added to
  /// Ableton's script later can never slip through by being named `get_...`.
  static const allowedTypes = {'ping', 'get_state', 'get_locators', 'get_tracks'};

  final void Function(Uint8List frame) forward;
  final void Function() onViolation;
  _ClientFrameFilter({required this.forward, required this.onViolation});

  static const _maxFrame = 64 * 1024;
  Uint8List _pending = Uint8List(0);

  void add(List<int> chunk) {
    final merged = Uint8List(_pending.length + chunk.length)
      ..setRange(0, _pending.length, _pending)
      ..setRange(_pending.length, _pending.length + chunk.length, chunk);
    _pending = merged;
    _drain();
  }

  void _drain() {
    while (true) {
      if (_pending.length < 2) return;
      final b0 = _pending[0];
      final b1 = _pending[1];
      final fin = (b0 & 0x80) != 0;
      final opcode = b0 & 0x0F;
      final masked = (b1 & 0x80) != 0;
      var len = b1 & 0x7F;
      var offset = 2;
      if (len == 126) {
        if (_pending.length < 4) return;
        len = (_pending[2] << 8) | _pending[3];
        offset = 4;
      } else if (len == 127) {
        if (_pending.length < 10) return;
        // Anything over the cap is refused outright (also avoids 64-bit math).
        for (var i = 2; i < 6; i++) {
          if (_pending[i] != 0) {
            _pending = Uint8List(0);
            onViolation();
            return;
          }
        }
        len = (_pending[6] << 24) | (_pending[7] << 16) | (_pending[8] << 8) | _pending[9];
        offset = 10;
      }
      if (len > _maxFrame) {
        _pending = Uint8List(0);
        onViolation();
        return;
      }
      final maskLen = masked ? 4 : 0;
      final total = offset + maskLen + len;
      if (_pending.length < total) return;

      final frame = Uint8List.sublistView(_pending, 0, total);
      final isControl = (opcode & 0x08) != 0; // close, ping, pong
      var allow = false;
      if (isControl) {
        allow = true;
      } else if (opcode == 0x1 && fin && masked) {
        final key = frame.sublist(offset, offset + 4);
        final payload = Uint8List(len);
        for (var i = 0; i < len; i++) {
          payload[i] = frame[offset + 4 + i] ^ key[i % 4];
        }
        try {
          final msg = jsonDecode(utf8.decode(payload));
          final type = msg is Map ? msg['type'] : null;
          allow = type is String && allowedTypes.contains(type);
        } catch (_) {
          allow = false;
        }
      }
      if (allow) {
        forward(Uint8List.fromList(frame));
      } else {
        onViolation();
      }
      _pending = Uint8List.fromList(_pending.sublist(total));
    }
  }
}
