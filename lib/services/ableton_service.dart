import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/ableton_state.dart';

/// WebSocket client for the OkayNext MIDI Remote Script running inside
/// Ableton Live. Auto-reconnects every 5 s when disconnected.
class AbletonService {
  /// A read-only service (the phone/browser monitor) only ever asks Ableton
  /// for information. Anything that could change a song, fader, transport or
  /// the setlist is dropped before it reaches the socket.
  final bool readOnly;
  AbletonService({this.readOnly = false});

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  Timer? _syncTimer;

  String? _lastHost;
  int? _lastPort;
  bool _userDisconnected = false;

  final _stateController = StreamController<AbletonState>.broadcast();
  final _debugController = StreamController<Map<String, dynamic>>.broadcast();
  final _volLabelController = StreamController<Map<String, dynamic>>.broadcast();
  final _masterVolLabelController = StreamController<String>.broadcast();
  final _cueVolLabelController = StreamController<String>.broadcast();
  final _setlistController = StreamController<List<String>>.broadcast();

  Stream<AbletonState> get stateStream => _stateController.stream;
  Stream<Map<String, dynamic>> get debugStream => _debugController.stream;
  Stream<Map<String, dynamic>> get volLabelStream => _volLabelController.stream;
  Stream<String> get masterVolLabelStream => _masterVolLabelController.stream;
  Stream<String> get cueVolLabelStream => _cueVolLabelController.stream;

  /// The setlist order the controlling app (PC) last sent to Ableton.
  Stream<List<String>> get setlistStream => _setlistController.stream;

  AbletonState _state = const AbletonState();
  AbletonState get state => _state;
  Map<String, dynamic>? _lastDebugInfo;
  Map<String, dynamic>? get lastDebugInfo => _lastDebugInfo;

  void connect(String host, int port) {
    _userDisconnected = false;
    _lastHost = host;
    _lastPort = port;
    _reconnectTimer?.cancel();
    _doConnect(host, port);
  }

  Future<void> _doConnect(String host, int port) async {
    _closeChannel();
    _emit(_state.copyWith(
      connectionStatus: ConnectionStatus.connecting,
      errorMessage: null,
    ));

    try {
      final uri = Uri.parse('ws://$host:$port');
      _channel = WebSocketChannel.connect(uri);

      // A blocked port (firewall) never answers; don't sit on "connecting".
      await _channel!.ready.timeout(const Duration(seconds: 8));

      _sub = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: true,
      );
      _emit(_state.copyWith(connectionStatus: ConnectionStatus.connected));
      _pingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        _send({'type': 'ping'});
      });
      _syncTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        _send({'type': 'get_state'});
        _send({'type': 'get_tracks'});
        _send({'type': 'get_locators'});
      });
      _send({'type': 'get_state'});
      _send({'type': 'get_locators'});
      _send({'type': 'get_tracks'});
      Future.delayed(const Duration(seconds: 2), () {
        _send({'type': 'get_state'});
        _send({'type': 'get_locators'});
        _send({'type': 'get_tracks'});
      });
    } catch (e) {
      _closeChannel();
      _emit(_state.copyWith(
        connectionStatus: ConnectionStatus.disconnected,
        errorMessage: e.toString(),
      ));
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_userDisconnected || _lastHost == null) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (!_userDisconnected && _lastHost != null) {
        _doConnect(_lastHost!, _lastPort!);
      }
    });
  }

  void _closeChannel() {
    _pingTimer?.cancel();
    _syncTimer?.cancel();
    _sub?.cancel();
    try { _channel?.sink.close(); } catch (_) {}
    _channel = null;
  }

  void disconnect() {
    _userDisconnected = true;
    _reconnectTimer?.cancel();
    _closeChannel();
    _emit(_state.copyWith(connectionStatus: ConnectionStatus.disconnected));
  }

  void _onMessage(dynamic raw) {
    try {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = msg['type'] as String?;
      switch (type) {
        case 'state':
          final data = msg['data'] as Map<String, dynamic>;
          _emit(_state.copyWith(
            connectionStatus: ConnectionStatus.connected,
            isPlaying: data['playing'] as bool?,
            isRecording: data['recording'] as bool?,
            bpm: (data['bpm'] as num?)?.toDouble(),
            currentBeat: (data['current_beat'] as num?)?.toDouble(),
            currentBar: data['current_bar'] as int?,
            currentMeasure: data['current_measure'] as int?,
            loopEnabled: data['loop_enabled'] as bool?,
            loopStart: (data['loop_start'] as num?)?.toDouble(),
            loopEnd: (data['loop_end'] as num?)?.toDouble(),
            currentLocatorName: data['current_locator'] as String?,
            projectName: data['project_name'] as String?,
            timeSigNumerator: data['time_sig_numerator'] as int?,
            timeSigDenominator: data['time_sig_denominator'] as int?,
            masterVolume: (data['master_volume'] as num?)?.toDouble(),
            masterVolStr: data['master_vol_str'] as String?,
            cueVolume: (data['cue_volume'] as num?)?.toDouble(),
            cueVolStr: data['cue_vol_str'] as String?,
          ));
        case 'locators':
          final list = (msg['data'] as List<dynamic>)
              .map((e) => AbletonLocator.fromJson(e as Map<String, dynamic>))
              .toList();
          _emit(_state.copyWith(locators: list));
        case 'tracks':
          final list = (msg['data'] as List<dynamic>)
              .map((e) => AbletonTrack.fromJson(e as Map<String, dynamic>))
              .toList();
          _emit(_state.copyWith(tracks: list));
        case 'position':
          _emit(_state.copyWith(
            isPlaying: msg['playing'] as bool?,
            currentLocatorName: msg['locator'] as String?,
            currentBeat: (msg['beat'] as num?)?.toDouble(),
            timeSigNumerator: msg['time_sig_numerator'] as int?,
            timeSigDenominator: msg['time_sig_denominator'] as int?,
            currentBar: msg['current_bar'] as int?,
          ));
        case 'time_sig':
          _emit(_state.copyWith(
            timeSigNumerator: msg['numerator'] as int?,
            timeSigDenominator: msg['denominator'] as int?,
            currentBar: msg['current_bar'] as int?,
          ));
        case 'bpm':
          final v = (msg['bpm'] as num?)?.toDouble();
          if (v != null) _emit(_state.copyWith(bpm: v));
        case 'master_volume':
          final v = (msg['value'] as num?)?.toDouble();
          final lbl = msg['label'] as String?;
          if (v != null) _emit(_state.copyWith(masterVolume: v, masterVolStr: lbl));
        case 'master_vol_label':
          _masterVolLabelController.add(msg['label'] as String? ?? '');
        case 'cue_volume':
          final v = (msg['value'] as num?)?.toDouble();
          final lbl = msg['label'] as String?;
          if (v != null) _emit(_state.copyWith(cueVolume: v, cueVolStr: lbl));
        case 'cue_vol_label':
          _cueVolLabelController.add(msg['label'] as String? ?? '');
        case 'setlist':
          final names = (msg['names'] as List?)?.whereType<String>().toList();
          if (names != null) _setlistController.add(names);
        case 'vol_label':
          _volLabelController.add(msg);
        case 'debug':
          _lastDebugInfo = msg;
          _debugController.add(msg);
        case 'midi_nav':
          // MIDI hardware triggered next/previous — update locator immediately
          // rather than waiting up to one full beat for the next position tick.
          final active = msg['active'] as String?;
          if (active != null) {
            _emit(_state.copyWith(currentLocatorName: active));
          }
        case 'pong':
          break;
        case 'error':
          _emit(_state.copyWith(errorMessage: msg['message'] as String?));
      }
    } catch (_) {}
  }

  void _onError(Object err) {
    _pingTimer?.cancel();
    _emit(_state.copyWith(
      connectionStatus: ConnectionStatus.disconnected,
      errorMessage: err.toString(),
    ));
    _scheduleReconnect();
  }

  void _onDone() {
    _pingTimer?.cancel();
    _emit(_state.copyWith(connectionStatus: ConnectionStatus.disconnected));
    _scheduleReconnect();
  }

  void _send(Map<String, dynamic> msg) {
    if (readOnly) {
      // Only pure queries may pass.
      final type = msg['type'] as String? ?? '';
      if (type != 'ping' && !type.startsWith('get_')) return;
    }
    try { _channel?.sink.add(jsonEncode(msg)); } catch (_) {}
  }

  void _emit(AbletonState newState) {
    _state = newState;
    if (!_stateController.isClosed) _stateController.add(_state);
  }

  // Transport commands
  void play() => _send({'type': 'play'});
  void stop() => _send({'type': 'stop'});
  void record() => _send({'type': 'record'});
  void jumpToBar(int bar) => _send({'type': 'jump_to_bar', 'bar': bar});
  void jumpToLocator(String name) =>
      _send({'type': 'jump_to_locator', 'name': name});
  void setBpm(double bpm) => _send({'type': 'set_bpm', 'bpm': bpm});
  void setLoop(bool enabled) =>
      _send({'type': enabled ? 'enable_loop' : 'disable_loop'});
  void setSetlist(List<String> names) =>
      _send({'type': 'set_setlist', 'names': names});
  void setActiveSong(String? name) =>
      _send({'type': 'set_active_song', 'name': name});
  void sendDebug() => _send({'type': 'debug'});
  void getVolLabel(int index, double volume) =>
      _send({'type': 'get_vol_label', 'index': index, 'volume': volume});
  void muteTrack(int index) => _send({'type': 'mute_track', 'index': index});
  void setTrackVolume(int index, double volume) =>
      _send({'type': 'set_track_volume', 'index': index, 'volume': volume});
  void soloTrack(int index) => _send({'type': 'solo_track', 'index': index});
  void setMasterVolume(double volume) =>
      _send({'type': 'set_master_volume', 'volume': volume});
  void setCueVolume(double volume) =>
      _send({'type': 'set_cue_volume', 'volume': volume});
  void refreshState() {
    _send({'type': 'get_state'});
    _send({'type': 'get_locators'});
    _send({'type': 'get_tracks'});
  }

  void dispose() {
    _userDisconnected = true;
    _reconnectTimer?.cancel();
    _closeChannel();
    _stateController.close();
    _debugController.close();
    _volLabelController.close();
    _masterVolLabelController.close();
    _cueVolLabelController.close();
    _setlistController.close();
  }
}

