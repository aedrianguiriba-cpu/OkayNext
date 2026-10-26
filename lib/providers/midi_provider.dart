import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/midi_mapping.dart';
import '../services/midi_service.dart';
import 'ableton_provider.dart';
import 'locator_groups_provider.dart';

class MidiProvider extends ChangeNotifier {
  final MidiService _midi;
  AbletonProvider _ableton;
  LocatorGroupsProvider _groups;

  List<MidiDevice> _devices = [];
  MidiDevice? _connectedDevice;
  List<MidiMapping> _mappings = [];
  MidiAction? _learningFor;

  StreamSubscription? _midiSub;
  StreamSubscription? _deviceSub;

  // ── Getters ───────────────────────────────────────────────────────────
  List<MidiDevice> get devices => _devices;
  MidiDevice? get connectedDevice => _connectedDevice;
  List<MidiMapping> get mappings => _mappings;
  MidiAction? get learningFor => _learningFor;

  MidiMapping? mappingFor(MidiAction action) {
    try {
      return _mappings.firstWhere((m) => m.action == action);
    } catch (_) {
      return null;
    }
  }

  MidiProvider(this._midi, this._ableton, this._groups) {
    _init();
  }

  void updateAbleton(AbletonProvider ableton) {
    _ableton = ableton;
  }

  void updateGroups(LocatorGroupsProvider groups) {
    _groups = groups;
  }

  Future<void> _init() async {
    await _loadMappings();
    await refreshDevices();
    unawaited(_loadPaired());
    _midiSub =_midi.packetStream?.listen(_onMidiPacket);
    _deviceSub = _midi.setupChangedStream?.listen((_) => refreshDevices());
  }

  // ── Devices ───────────────────────────────────────────────────────────

  Future<void> refreshDevices() async {
    final live = await _midi.getDevices();
    final liveIds = live.map((d) => d.id).toSet();
    _devices = [...live, ..._paired.where((d) => !liveIds.contains(d.id))];
    final prev = _connectedDevice;
    if (prev != null) {
      _connectedDevice = _devices.where((d) => d.id == prev.id).firstOrNull;
    }
    notifyListeners();
  }

  List<MidiDevice> _paired = [];

  Future<void> _loadPaired() async {
    _paired = await _midi.getPairedBleDevices();
    await refreshDevices();
  }

  bool _scanning = false;
  bool get scanning => _scanning;
  String? scanError;

  /// Scans for nearby BLE MIDI devices for [duration], refreshing the list as
  /// they are discovered. Devices not yet paired with the OS only appear
  /// while a scan is running.
  Future<void> scanBluetooth({Duration duration = const Duration(seconds: 8)}) async {
    if (_scanning) return;
    _scanning = true;
    scanError = null;
    notifyListeners();

    unawaited(_loadPaired());
    scanError = await _midi.startBleScan();
    if (scanError == null) {
      final end = DateTime.now().add(duration);
      while (DateTime.now().isBefore(end)) {
        await Future.delayed(const Duration(seconds: 1));
        await refreshDevices();
      }
      _midi.stopBleScan();
    }
    _scanning = false;
    await refreshDevices();
  }

  /// Returns an error message if the connection failed, null on success.
  Future<String?> connectToDevice(MidiDevice device) async {
    final error = await _midi.connectToDevice(device);
    if (error != null) {
      _connectedDevice = null;
      await refreshDevices();
      return error;
    }
    _connectedDevice = device;
    await refreshDevices();
    return null;
  }

  void disconnectDevice() {
    final device = _connectedDevice;
    if (device != null) {
      _midi.disconnectDevice(device);
      _connectedDevice = null;
      notifyListeners();
    }
  }

  // ── MIDI Learn ────────────────────────────────────────────────────────

  void startLearning(MidiAction action) {
    _learningFor = action;
    notifyListeners();
  }

  void cancelLearning() {
    _learningFor = null;
    notifyListeners();
  }

  // ── MIDI Packet Handling ──────────────────────────────────────────────

  void _onMidiPacket(MidiPacket packet) {
    final data = packet.data;
    if (data.isEmpty) return;

    final statusByte = data[0];
    // Ignore system messages (0xF0+)
    if (statusByte >= 0xF0) return;

    final channel = statusByte & 0x0F;
    final msgType = statusByte & 0xF0;

    MidiMsgType type;
    int number;
    int value = 0;

    // Accept CC (0xB0), Note On (0x90), and Note Off (0x80)
    // Match on type+channel+number only — ignore value/velocity entirely
    // so any controller style (toggle, momentary, any value) triggers correctly.
    if (msgType == 0xB0 && data.length >= 2) {
      type = MidiMsgType.cc;
      number = data[1];
      value = data.length >= 3 ? data[2] : 0;
    } else if (msgType == 0x90 && data.length >= 3 && data[2] > 0) {
      // Note On only; Note Off (0x80 or velocity 0) is ignored so a
      // press/release pair doesn't fire the action twice.
      type = MidiMsgType.noteOn;
      number = data[1];
    } else {
      return;
    }

    // Learn mode: save this message as the mapping for the pending action
    if (_learningFor != null) {
      final action = _learningFor!;
      // Faders follow a CC value, so a note can't be assigned to them —
      // keep listening until a CC (knob/fader move) arrives.
      if (action.isContinuous && type != MidiMsgType.cc) return;
      _learningFor = null;
      _mappings.removeWhere((m) => m.action == action);
      _mappings.add(MidiMapping(
          msgType: type, channel: channel, number: number, action: action));
      _saveMappings();
      notifyListeners();
      return;
    }

    // Normal: dispatch to Ableton on every matching message
    for (final m in _mappings) {
      if (m.msgType == type && m.channel == channel && m.number == number) {
        _executeAction(m.action, value);
        break;
      }
    }
  }

  // ── Scenes ────────────────────────────────────────────────────────────

  /// Switches to scene [i]'s setlist. Ignored if the scene doesn't exist, has
  /// no setlist, or is already the active one.
  Future<void> _activateScene(int i) async {
    if (i >= _groups.scenes.length || _groups.isSceneActive(i)) return;
    if (await _groups.activateScene(i)) _ableton.selectStartOfSetlist();
  }

  /// Moves to the next/previous scene that has a setlist, wrapping around.
  void _stepScene(int delta) {
    final n = _groups.scenes.length;
    var current = -1;
    for (var i = 0; i < n; i++) {
      if (_groups.isSceneActive(i)) {
        current = i;
        break;
      }
    }
    for (var k = 1; k <= n; k++) {
      final i = ((current + delta * k) % n + n) % n;
      if (i != current && _groups.setlistForScene(i) != null) {
        _activateScene(i);
        return;
      }
    }
  }

  // Last CC value sent per fader, so a controller streaming repeated values
  // doesn't flood Ableton.
  final Map<MidiAction, int> _lastFaderValue = {};

  void _executeAction(MidiAction action, int value) {
    if (action.isContinuous) {
      if (_lastFaderValue[action] == value) return;
      _lastFaderValue[action] = value;
    }
    final level = (value / 127.0).clamp(0.0, 1.0);
    switch (action) {
      case MidiAction.play:
        _ableton.play();
      case MidiAction.stop:
        _ableton.stop();
      case MidiAction.nextSong:
        _ableton.goToNext();
      case MidiAction.previousSong:
        _ableton.goToPrevious();
      case MidiAction.record:
        _ableton.record();
      case MidiAction.loop:
        _ableton.setLoop(!_ableton.loopEnabled);
      case MidiAction.masterVolume:
        _ableton.setMasterVolume(level);
      case MidiAction.cueVolume:
        _ableton.setCueVolume(level);
      case MidiAction.nextScene:
        _stepScene(1);
      case MidiAction.previousScene:
        _stepScene(-1);
      case MidiAction.scene1:
      case MidiAction.scene2:
      case MidiAction.scene3:
      case MidiAction.scene4:
      case MidiAction.scene5:
      case MidiAction.scene6:
      case MidiAction.scene7:
      case MidiAction.scene8:
      case MidiAction.scene9:
      case MidiAction.scene10:
      case MidiAction.scene11:
      case MidiAction.scene12:
        _activateScene(action.sceneIndex!);
    }
  }

  // ── Mapping Management ────────────────────────────────────────────────

  void setMapping(MidiMapping mapping) {
    _mappings.removeWhere((m) => m.action == mapping.action);
    _mappings.add(mapping);
    _saveMappings();
    notifyListeners();
  }

  void removeMapping(MidiAction action) {
    _mappings.removeWhere((m) => m.action == action);
    _saveMappings();
    notifyListeners();
  }

  void clearAllMappings() {
    _mappings.clear();
    _saveMappings();
    notifyListeners();
  }

  void resetToDefaults() {
    _mappings = List.of(MidiMapping.defaults);
    _saveMappings();
    notifyListeners();
  }

  // ── Persistence ───────────────────────────────────────────────────────

  Future<void> _loadMappings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('midi_mappings_v2');
    if (raw != null) {
      try {
        _mappings = MidiMapping.listFromJson(raw);
      } catch (_) {
        _mappings = List.of(MidiMapping.defaults);
      }
    } else {
      // First run — load defaults so the controller can be used immediately
      _mappings = List.of(MidiMapping.defaults);
      await _saveMappings();
    }
  }

  Future<void> _saveMappings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('midi_mappings_v2', MidiMapping.listToJson(_mappings));
  }

  @override
  void dispose() {
    _midiSub?.cancel();
    _deviceSub?.cancel();
    _midi.dispose();
    super.dispose();
  }
}
