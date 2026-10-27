// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:setlistmanager/services/monitor_client.dart';
import 'package:setlistmanager/services/monitor_server_io.dart';

/// A stand-in Ableton that records the `type` of every message it receives.
class FakeAbleton {
  late HttpServer server;
  final received = <String>[];
  final rawBytes = <int>[];

  Future<void> start(int port) async {
    server = await HttpServer.bind('127.0.0.1', port);
    server.listen((req) async {
      final ws = await WebSocketTransformer.upgrade(req);
      ws.add(jsonEncode({'type': 'hello', 'from': 'fake-ableton'}));
      ws.listen((m) {
        try {
          received.add((jsonDecode(m as String) as Map)['type'] as String);
        } catch (_) {
          received.add('<undecodable>');
        }
      });
    });
  }
}

Uint8List maskedFrame(int firstByte, List<int> payload) {
  final key = [0x11, 0x22, 0x33, 0x44];
  final b = BytesBuilder();
  b.addByte(firstByte);
  final len = payload.length;
  if (len < 126) {
    b.addByte(0x80 | len);
  } else {
    b.addByte(0x80 | 126);
    b.addByte(len >> 8);
    b.addByte(len & 0xFF);
  }
  b.add(key);
  for (var i = 0; i < len; i++) {
    b.addByte(payload[i] ^ key[i % 4]);
  }
  return b.toBytes();
}

Uint8List textFrame(String s, {bool fin = true}) =>
    maskedFrame((fin ? 0x80 : 0x00) | 0x1, utf8.encode(s));

void main() {
  late FakeAbleton fake;
  late MonitorServer monitor;
  const monitorPort = 18091, abletonPort = 18766;

  setUpAll(() async {
    fake = FakeAbleton();
    await fake.start(abletonPort);
    monitor = MonitorServer.custom(
      port: monitorPort,
      abletonPort: abletonPort,
      webRoot: Directory('build/web'),
    );
    expect(await monitor.start(), isTrue, reason: monitor.error);
  });

  tearDownAll(() async {
    await monitor.stop();
    await fake.server.close(force: true);
  });

  final haveWebBuild = File('build/web/index.html').existsSync();

  test('serves the web page and keeps files inside the web root', skip: haveWebBuild ? null : 'run flutter build web first', () async {
    final c = HttpClient();
    Future<HttpClientResponse> get(String path) async {
      final req = await c.getUrl(Uri.parse('http://127.0.0.1:$monitorPort$path'));
      return req.close();
    }

    final index = await get('/');
    expect(index.statusCode, 200);
    final body = await utf8.decodeStream(index);
    expect(body, contains('<html'));
    print('GET /               -> 200 (${body.length} bytes)');

    final js = await get('/main.dart.js');
    expect(js.statusCode, 200);
    expect(js.headers.contentType?.mimeType, 'application/javascript');
    await js.drain();
    print('GET /main.dart.js   -> 200 application/javascript');

    for (final evil in [
      '/../pubspec.yaml',
      '/%2e%2e/pubspec.yaml',
      '/..%5Cpubspec.yaml',
      '/..%2F..%2FWindows/win.ini',
      '/nope.html',
    ]) {
      final r = await get(evil);
      expect(r.statusCode, 404, reason: evil);
      await r.drain();
    }
    print('path traversal attempts (5) -> all 404');

    final post = await (await c.postUrl(Uri.parse('http://127.0.0.1:$monitorPort/')))
        .close();
    expect(post.statusCode, 405);
    await post.drain();
    print('POST /              -> 405');
    c.close();
  });

  test('phone can read, but no command ever reaches Ableton', () async {
    fake.received.clear();
    final ws = await WebSocket.connect('ws://127.0.0.1:$monitorPort');
    final fromAbleton = <String>[];
    ws.listen((m) => fromAbleton.add(m as String));

    // Ableton -> phone still works.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(fromAbleton.any((m) => m.contains('fake-ableton')), isTrue);
    print('Ableton -> phone: received "hello" through the monitor');

    // Allowed queries.
    for (final t in ['get_state', 'get_locators', 'get_tracks', 'ping']) {
      ws.add(jsonEncode({'type': t}));
    }
    // Every command the app can send, plus some sneaky ones.
    final blocked = [
      'play', 'stop', 'record', 'set_bpm', 'set_setlist', 'set_active_song',
      'enable_loop', 'disable_loop', 'jump_to_bar', 'jump_to_locator',
      'mute_track', 'solo_track', 'set_master_volume', 'set_cue_volume',
      'set_track_volume', 'debug', 'set_midi_mappings', 'start_midi_learn',
      'set_midi_device', 'clear_debug_log',
      'get_midi_mappings', // a read, but not on the monitor's allow-list
      'GET_STATE', 'get_state ', ' get_state', 'get_state\u0000',
    ];
    for (final t in blocked) {
      ws.add(jsonEncode({'type': t, 'volume': 1.0, 'name': 'x', 'bar': 1}));
    }
    ws.add(jsonEncode({'no_type': true}));
    ws.add(jsonEncode({'type': 5}));
    ws.add(jsonEncode([1, 2, 3]));
    ws.add('not json at all');
    ws.add(Uint8List.fromList(utf8.encode(jsonEncode({'type': 'play'})))); // binary frame

    await Future<void>.delayed(const Duration(milliseconds: 600));
    await ws.close();

    print('reached Ableton: ${fake.received}');
    expect(fake.received, ['get_state', 'get_locators', 'get_tracks', 'ping']);
    print('${blocked.length + 5} command/odd messages sent -> 0 reached Ableton');
  });

  test('raw frames: fragmented, oversized and mixed are all handled safely',
      () async {
    fake.received.clear();
    final sock = await Socket.connect('127.0.0.1', monitorPort);
    final key = base64.encode(List<int>.generate(16, (_) => Random().nextInt(256)));
    sock.add(latin1.encode('GET / HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\n'
        'Connection: Upgrade\r\nSec-WebSocket-Key: $key\r\n'
        'Sec-WebSocket-Version: 13\r\n\r\n'));
    await Future<void>.delayed(const Duration(milliseconds: 400));

    // A command split into two fragments (FIN=0 text, then FIN=1 continuation).
    sock.add(textFrame('{"type":"pl', fin: false));
    sock.add(maskedFrame(0x80 | 0x0, utf8.encode('ay"}')));
    // An allowed query split across TCP packets (partial frame delivery).
    final q = textFrame('{"type":"get_state"}');
    sock.add(q.sublist(0, 5));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    sock.add(q.sublist(5));
    // Two frames in one packet: a command then a query.
    final both = BytesBuilder()
      ..add(textFrame('{"type":"stop"}'))
      ..add(textFrame('{"type":"get_tracks"}'));
    sock.add(both.toBytes());
    // Oversized frame (> 64 KB) with a command inside.
    sock.add(textFrame('{"type":"play","pad":"${'a' * 70000}"}'));

    await Future<void>.delayed(const Duration(milliseconds: 600));
    sock.destroy();
    print('reached Ableton: ${fake.received}');
    expect(fake.received, ['get_state', 'get_tracks']);
  });


  group('device names', () {
    const cases = {
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1':
          ('iPhone · Safari', DeviceKind.phone),
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/124.0.6367.88 Mobile/15E148 Safari/604.1':
          ('iPhone · Chrome', DeviceKind.phone),
      'Mozilla/5.0 (iPad; CPU OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1':
          ('iPad · Safari', DeviceKind.tablet),
      'Mozilla/5.0 (Linux; Android 13; SM-S908B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36':
          ('Android phone (SM-S908B) · Chrome', DeviceKind.phone),
      'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36':
          ('Android phone · Chrome', DeviceKind.phone),
      'Mozilla/5.0 (Linux; Android 13; SM-X700) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36':
          ('Android tablet (SM-X700) · Chrome', DeviceKind.tablet),
      'Mozilla/5.0 (Linux; Android 14; SAMSUNG SM-A546B) AppleWebKit/537.36 (KHTML, like Gecko) SamsungBrowser/24.0 Chrome/117.0.0.0 Mobile Safari/537.36':
          ('Android phone (SAMSUNG SM-A546B) · Samsung Internet', DeviceKind.phone),
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 Edg/124.0.0.0':
          ('Windows PC · Edge', DeviceKind.computer),
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15':
          ('Mac · Safari', DeviceKind.computer),
      'Mozilla/5.0 (X11; Linux x86_64; rv:125.0) Gecko/20100101 Firefox/125.0':
          ('Linux PC · Firefox', DeviceKind.computer),
      '': ('Unknown device', DeviceKind.unknown),
    };
    test('real browser strings are named sensibly', () {
      cases.forEach((ua, want) {
        expect(describeDevice(ua), want.$1, reason: ua);
        expect(deviceKind(ua), want.$2, reason: ua);
        print('  ${want.$1.padRight(52)} <- ${ua.isEmpty ? '(empty)' : ua.substring(0, ua.length.clamp(0, 52))}');
      });
      expect(describeDevice('anything', isThisPc: true), 'This PC');
    });

    test('"connected for" text', () {
      final t = DateTime(2026, 1, 1, 12);
      expect(connectedFor(t, t.add(const Duration(seconds: 3))), 'just now');
      expect(connectedFor(t, t.add(const Duration(seconds: 42))), '42 s');
      expect(connectedFor(t, t.add(const Duration(minutes: 7))), '7 min');
      expect(connectedFor(t, t.add(const Duration(hours: 1, minutes: 5))), '1 h 05 min');
    });
  });

  test('the server lists devices as they connect and leave', () async {
    final m = MonitorServer.custom(
        port: 18094, abletonPort: abletonPort, webRoot: Directory('build/web'));
    expect(await m.start(), isTrue);
    var changes = 0;
    final sub = m.changes.listen((_) => changes++);
    expect(m.clients, isEmpty);

    const iphone =
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1';
    const pixel =
        'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

    final a = await WebSocket.connect('ws://127.0.0.1:18094',
        headers: {'User-Agent': iphone});
    final b = await WebSocket.connect('ws://127.0.0.1:18094',
        headers: {'User-Agent': pixel});
    final c = await WebSocket.connect('ws://127.0.0.1:18094');
    for (final w in [a, b, c]) {
      w.listen((_) {});
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));

    print('connected: ${m.clients.map((x) => '${x.device} @ ${x.ip}').toList()}');
    expect(m.clients.length, 3);
    expect(m.clients.map((x) => x.device),
        containsAll(['This PC', 'This PC', 'This PC'])); // all from this machine
    expect(m.clients.every((x) => x.isThisPc), isTrue);
    expect(m.clients.map((x) => x.userAgent).toSet().length, 3);

    await a.close();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(m.clients.length, 2);
    print('one leaves -> ${m.clients.length} listed');

    await b.close();
    await c.close();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(m.clients, isEmpty);
    expect(changes, greaterThanOrEqualTo(6)); // 3 joins + 3 leaves
    print('all gone -> ${m.clients.length} listed; $changes change events');
    await sub.cancel();
    await m.stop();
  });

  test('turning it off closes the port', () async {
    final m = MonitorServer.custom(
        port: 18092, abletonPort: abletonPort, webRoot: Directory('build/web'));
    expect(await m.start(), isTrue);
    await m.stop();
    expect(m.running, isFalse);
    expect(() => Socket.connect('127.0.0.1', 18092,
        timeout: const Duration(milliseconds: 500)), throwsA(anything));
    print('stopped -> port closed');
  });

  test('a busy port is reported, not a crash', () async {
    final blocker = await HttpServer.bind('0.0.0.0', 18093);
    final m = MonitorServer.custom(
        port: 18093, abletonPort: abletonPort, webRoot: Directory('build/web'));
    expect(await m.start(), isFalse);
    expect(m.error, contains('already in use'));
    print('busy port -> "${m.error}"');
    await blocker.close(force: true);
  });
}
