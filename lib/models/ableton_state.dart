enum ConnectionStatus { disconnected, connecting, connected }

class AbletonState {
  final bool isPlaying;
  final bool isRecording;
  final double bpm;
  final double currentBeat;
  final int currentBar;
  final int currentMeasure;
  final bool loopEnabled;
  final double? loopStart;
  final double? loopEnd;
  final String? currentLocatorName;
  final int? currentLocatorBar;
  final List<AbletonLocator> locators;
  final List<AbletonTrack> tracks;
  final ConnectionStatus connectionStatus;
  final String? errorMessage;
  final String? projectName;
  final int timeSigNumerator;
  final int timeSigDenominator;
  final double masterVolume;
  final String masterVolStr;
  final double cueVolume;
  final String cueVolStr;

  const AbletonState({
    this.isPlaying = false,
    this.isRecording = false,
    this.bpm = 120.0,
    this.currentBeat = 0.0,
    this.currentBar = 1,
    this.currentMeasure = 1,
    this.loopEnabled = false,
    this.loopStart,
    this.loopEnd,
    this.currentLocatorName,
    this.currentLocatorBar,
    this.locators = const [],
    this.tracks = const [],
    this.connectionStatus = ConnectionStatus.disconnected,
    this.errorMessage,
    this.projectName,
    this.timeSigNumerator = 4,
    this.timeSigDenominator = 4,
    this.masterVolume = 1.0,
    this.masterVolStr = '',
    this.cueVolume = 1.0,
    this.cueVolStr = '',
  });

  AbletonState copyWith({
    bool? isPlaying,
    bool? isRecording,
    double? bpm,
    double? currentBeat,
    int? currentBar,
    int? currentMeasure,
    bool? loopEnabled,
    double? loopStart,
    double? loopEnd,
    String? currentLocatorName,
    int? currentLocatorBar,
    List<AbletonLocator>? locators,
    List<AbletonTrack>? tracks,
    ConnectionStatus? connectionStatus,
    String? errorMessage,
    String? projectName,
    int? timeSigNumerator,
    int? timeSigDenominator,
    double? masterVolume,
    String? masterVolStr,
    double? cueVolume,
    String? cueVolStr,
  }) {
    return AbletonState(
      isPlaying: isPlaying ?? this.isPlaying,
      isRecording: isRecording ?? this.isRecording,
      bpm: bpm ?? this.bpm,
      currentBeat: currentBeat ?? this.currentBeat,
      currentBar: currentBar ?? this.currentBar,
      currentMeasure: currentMeasure ?? this.currentMeasure,
      loopEnabled: loopEnabled ?? this.loopEnabled,
      loopStart: loopStart ?? this.loopStart,
      loopEnd: loopEnd ?? this.loopEnd,
      currentLocatorName: currentLocatorName ?? this.currentLocatorName,
      currentLocatorBar: currentLocatorBar ?? this.currentLocatorBar,
      locators: locators ?? this.locators,
      tracks: tracks ?? this.tracks,
      connectionStatus: connectionStatus ?? this.connectionStatus,
      errorMessage: errorMessage ?? this.errorMessage,
      projectName: projectName ?? this.projectName,
      timeSigNumerator: timeSigNumerator ?? this.timeSigNumerator,
      timeSigDenominator: timeSigDenominator ?? this.timeSigDenominator,
      masterVolume: masterVolume ?? this.masterVolume,
      masterVolStr: masterVolStr ?? this.masterVolStr,
      cueVolume: cueVolume ?? this.cueVolume,
      cueVolStr: cueVolStr ?? this.cueVolStr,
    );
  }
}

class AbletonLocator {
  final String name;
  final double position;
  final int bar;

  const AbletonLocator({
    required this.name,
    required this.position,
    required this.bar,
  });

  factory AbletonLocator.fromJson(Map<String, dynamic> json) => AbletonLocator(
        name: json['name'] as String,
        position: (json['position'] as num).toDouble(),
        bar: json['bar'] as int? ?? 1,
      );
}

class AbletonTrack {
  final int index;
  final String name;
  final bool mute;
  final bool solo;
  final bool arm;
  final bool isGroup;
  /// Index of the parent group track in the flat track list, or -1 if top-level.
  final int groupIndex;
  // 0.0–1.0 normalized (server maps Ableton's internal range); 1.0 = fader max (+6 dB)
  final double volume;
  // Ableton's own formatted label, e.g. "0.00 dB" or "-6.02 dB"
  final String volStr;

  const AbletonTrack({
    required this.index,
    required this.name,
    required this.mute,
    required this.solo,
    required this.arm,
    required this.isGroup,
    this.groupIndex = -1,
    this.volume = 1.0,
    this.volStr = '',
  });

  factory AbletonTrack.fromJson(Map<String, dynamic> json) => AbletonTrack(
        index: json['index'] as int? ?? 0,
        name: json['name'] as String? ?? '',
        mute: json['mute'] as bool? ?? false,
        solo: json['solo'] as bool? ?? false,
        arm: json['arm'] as bool? ?? false,
        isGroup: json['is_group'] as bool? ?? false,
        groupIndex: json['group_index'] as int? ?? -1,
        volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
        volStr: json['vol_str'] as String? ?? '',
      );
}
