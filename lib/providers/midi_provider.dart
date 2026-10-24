import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/midi_mapping.dart';
import '../services/midi_service.dart';
import 'ableton_provider.dart';

class MidiProvider extends ChangeNotifier {
  final MidiService _midi;
  AbletonProvider _ableton;

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

  MidiProvider(this._midi, this._ableton) {
    _init();
  }

  void updateAbleton(AbletonProvider ableton) {
    _ableton = ableton;
  }

  Future<void> _init() async {
    await _loadMappings();
    await refreshDevices();
    _midiSub = _midi.packetStream?.listen(_onMidiPacket);
    _deviceSub = _midi.setupChangedStream?.listen((_) => refreshDevices());
  }

  // ── Devices ───────────────────────────────────────────────────────────

  Future<void> refreshDevices() async {
    _devices = await _midi.getDevices();
    final prev = _connectedDevice;
    if (prev != null) {
      _connectedDevice = _devices.where((d) => d.id == prev.id).firstOrNull;
    }
    notifyListeners();
  }

  Future<void> connectToDevice(MidiDevice device) async {
    await _midi.connectToDevice(device);
    _connectedDevice = device;
    await refreshDevices();
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

    // Accept CC (0xB0), Note On (0x90), and Note Off (0x80)
    // Match on type+channel+number only — ignore value/velocity entirely
    // so any controller style (toggle, momentary, any value) triggers correctly.
    if (msgType == 0xB0 && data.length >= 2) {
      type = MidiMsgType.cc;
      number = data[1];
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
        _executeAction(m.action);
        break;
      }
    }
  }

  void _executeAction(MidiAction action) {
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
