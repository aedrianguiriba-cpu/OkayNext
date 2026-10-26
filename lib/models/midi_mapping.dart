import 'dart:convert';
import 'package:flutter/material.dart';

enum MidiMsgType { cc, noteOn }

enum MidiAction {
  play,
  stop,
  nextSong,
  previousSong,
  record,
  loop,
  masterVolume,
  cueVolume,
  nextScene,
  previousScene,
  scene1,
  scene2,
  scene3,
  scene4,
  scene5,
  scene6,
  scene7,
  scene8,
  scene9,
  scene10,
  scene11,
  scene12,
}

extension MidiActionInfo on MidiAction {
  /// Fader-style actions follow the CC value (0–127) instead of firing once.
  /// They can only be mapped to a CC message.
  /// 0-based scene number for the "Scene N" actions, null for all others.
  int? get sceneIndex {
    final m = RegExp(r'^scene(\d+)$').firstMatch(name);
    return m == null ? null : int.parse(m.group(1)!) - 1;
  }

  bool get isContinuous =>
      this == MidiAction.masterVolume || this == MidiAction.cueVolume;

  String get label {
    switch (this) {
      case MidiAction.play:
        return 'Play';
      case MidiAction.stop:
        return 'Stop';
      case MidiAction.nextSong:
        return 'Next Song';
      case MidiAction.previousSong:
        return 'Prev Song';
      case MidiAction.record:
        return 'Record';
      case MidiAction.loop:
        return 'Loop';
      case MidiAction.masterVolume:
        return 'Master Fader';
      case MidiAction.cueVolume:
        return 'Cue Fader';
      case MidiAction.nextScene:
        return 'Next Scene';
      case MidiAction.previousScene:
        return 'Prev Scene';
      default:
        return 'Scene ${sceneIndex! + 1}';
    }
  }

  IconData get icon {
    switch (this) {
      case MidiAction.play:
        return Icons.play_arrow_rounded;
      case MidiAction.stop:
        return Icons.stop_rounded;
      case MidiAction.nextSong:
        return Icons.skip_next_rounded;
      case MidiAction.previousSong:
        return Icons.skip_previous_rounded;
      case MidiAction.record:
        return Icons.fiber_manual_record_rounded;
      case MidiAction.loop:
        return Icons.loop_rounded;
      case MidiAction.masterVolume:
        return Icons.tune_rounded;
      case MidiAction.cueVolume:
        return Icons.headphones_rounded;
      case MidiAction.nextScene:
        return Icons.arrow_forward_rounded;
      case MidiAction.previousScene:
        return Icons.arrow_back_rounded;
      default:
        return Icons.grid_view_rounded;
    }
  }
}

class MidiMapping {
  final MidiMsgType msgType;
  final int channel;  // 0–15
  final int number;   // 0–127 (CC# or note#)
  final MidiAction action;

  const MidiMapping({
    required this.msgType,
    required this.channel,
    required this.number,
    required this.action,
  });

  String get displayName {
    final typeName = msgType == MidiMsgType.cc ? 'CC' : 'Note';
    return '$typeName $number  Ch ${channel + 1}';
  }

  Map<String, dynamic> toJson() => {
        'msgType': msgType.name,
        'channel': channel,
        'number': number,
        'action': action.name,
      };

  factory MidiMapping.fromJson(Map<String, dynamic> json) => MidiMapping(
        msgType: MidiMsgType.values.byName(json['msgType'] as String),
        channel: json['channel'] as int,
        number: json['number'] as int,
        action: MidiAction.values.byName(json['action'] as String),
      );

  static List<MidiMapping> listFromJson(String raw) {
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => MidiMapping.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static String listToJson(List<MidiMapping> mappings) =>
      jsonEncode(mappings.map((m) => m.toJson()).toList());

  /// Default CC assignments on Channel 1.
  /// Program your controller to send these to use OkayNext without LEARN.
  static List<MidiMapping> get defaults => [
        const MidiMapping(msgType: MidiMsgType.cc, channel: 0, number: 20, action: MidiAction.play),
        const MidiMapping(msgType: MidiMsgType.cc, channel: 0, number: 21, action: MidiAction.stop),
        const MidiMapping(msgType: MidiMsgType.cc, channel: 0, number: 22, action: MidiAction.nextSong),
        const MidiMapping(msgType: MidiMsgType.cc, channel: 0, number: 23, action: MidiAction.previousSong),
        const MidiMapping(msgType: MidiMsgType.cc, channel: 0, number: 24, action: MidiAction.record),
        const MidiMapping(msgType: MidiMsgType.cc, channel: 0, number: 25, action: MidiAction.loop),
        const MidiMapping(msgType: MidiMsgType.cc, channel: 0, number: 26, action: MidiAction.masterVolume),
        const MidiMapping(msgType: MidiMsgType.cc, channel: 0, number: 27, action: MidiAction.cueVolume),
      ];
}
