import 'dart:async';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_midi_command_ble/flutter_midi_command_ble.dart';

/// Thin wrapper around flutter_midi_command (v1.x) with BLE MIDI support.
///
/// USB MIDI works natively on Android.
/// BLE MIDI is enabled by passing UniversalBleMidiTransport to MidiCommand.
class MidiService {
  late final MidiCommand _mc;

  MidiService() {
    _mc = MidiCommand(bleTransport: UniversalBleMidiTransport());
  }

  /// Raw MIDI packet stream (bytes per packet).
  Stream<MidiPacket>? get packetStream => _mc.onMidiPacketReceived;

  /// Fires whenever the MIDI setup changes (device added / removed).
  Stream<MidiSetupChange>? get setupChangedStream => _mc.onMidiSetupChanged;

  Future<List<MidiDevice>> getDevices() async {
    try {
      final list = await _mc.devices;
      return list ?? [];
    } catch (_) {
      return [];
    }
  }

  Future<void> connectToDevice(MidiDevice device) async {
    try {
      await _mc.connectToDevice(device);
    } catch (_) {}
  }

  void disconnectDevice(MidiDevice device) {
    try {
      _mc.disconnectDevice(device);
    } catch (_) {}
  }

  /// Returns an error message string on failure, null on success.
  Future<String?> startBleScan() async {
    try {
      await _mc.startScanningForBluetoothDevices();
      return null;
    } on StateError catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  void stopBleScan() {
    try {
      _mc.stopScanningForBluetoothDevices();
    } catch (_) {}
  }

  void dispose() {
    stopBleScan();
  }
}
