import 'dart:async';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_midi_command_ble/flutter_midi_command_ble.dart';
import 'package:universal_ble/universal_ble.dart' show UniversalBle;

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

  /// BLE MIDI devices already paired with the OS. Pads like the M-Vave SMC-Pad
  /// stop advertising once paired, so a scan never finds them; the OS list
  /// does. The plugin can connect to these by id without a prior scan.
  Future<List<MidiDevice>> getPairedBleDevices() async {
    try {
      final list = await UniversalBle.getSystemDevices(withServices: [midiServiceId])
          .timeout(const Duration(seconds: 15));
      return [
        for (final d in list)
          if (d.name != null && d.name!.isNotEmpty)
            MidiDevice(d.deviceId, d.name!, MidiDeviceType.ble, false),
      ];
    } catch (_) {
      return [];
    }
  }

  /// Returns an error message on failure, null on success.
  Future<String?> connectToDevice(MidiDevice device) async {
    try {
      await _mc.connectToDevice(device);
      return null;
    } catch (e) {
      return e.toString();
    }
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
