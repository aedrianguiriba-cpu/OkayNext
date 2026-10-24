import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ableton_state.dart';
import '../services/ableton_service.dart';

class AbletonProvider extends ChangeNotifier {
  final AbletonService _service;

  AbletonState _state = const AbletonState();
  String _host = '';
  int _port = 9000;

  // Performance navigation — which locator is selected by the user
  int? _selectedIndex;

  // When the user explicitly navigates (Next/Previous/tap), we lock the
  // selection to this name until Ableton confirms the jump. This prevents
  // a late-arriving position broadcast (still reporting the old locator)
  // from overwriting the explicit choice before the jump lands.
  String? _pendingLocatorName;

  // Custom display order — list of locator names in user-defined sequence
  List<String> _locatorOrder = [];

  // Last setlist sent to Python (to avoid redundant sends)
  List<String> _lastSentSetlist = [];

  // Safety timer: clears _pendingLocatorName if Ableton never confirms the jump
  Timer? _pendingClearTimer;

  // Set to true when Flutter's stop() is pressed. Python's stop handler jumps
  // the playhead back to _active_name (possibly a different song) within
  // milliseconds; _postStopTimer releases the block after 800 ms so that
  // session-view clips, a subsequent Ableton play, or any other advance still
  // triggers auto-follow without waiting for Flutter's play button.
  bool _blockAutoFollowWhenStopped = false;
  Timer? _postStopTimer;

  // Optimistic states — set immediately on tap, cleared once server confirms
  bool? _localLoopEnabled;
  bool? _localIsPlaying;

  AbletonProvider(this._service) {
    _service.stateStream.listen(_onStateUpdate);
    _init();
  }

  void _onStateUpdate(AbletonState s) {
    final prevProject = _state.projectName;
    _state = s;

    if (s.projectName != null && s.projectName != prevProject) {
      _selectedIndex = null;
      _locatorOrder = [];
      _lastSentSetlist = [];
    }
    _syncOrder(s.locators);

    final orderedNames = locators.map((l) => l.name).toList();
    if (!_listEquals(orderedNames, _lastSentSetlist)) {
      _lastSentSetlist = orderedNames;
      _service.setSetlist(orderedNames);
    }

    // Follow Ableton's position, but honour explicit user navigation:
    // if the user pressed Next/Previous, hold the selection until Ableton
    // confirms the jump (currentLocatorName matches what we jumped to).
    // _blockAutoFollowWhenStopped is set by stop() and cleared by play(); it
    // blocks the one or two position messages Python sends after stop (jump-back
    // to _active_name) without blocking session-view clips or MIDI-triggered
    // advances.
    if (s.isPlaying) _blockAutoFollowWhenStopped = false;
    if (s.currentLocatorName != null) {
      if (_pendingLocatorName != null) {
        if (s.currentLocatorName == _pendingLocatorName) {
          _pendingClearTimer?.cancel();
          _pendingClearTimer = null;
          _pendingLocatorName = null; // jump confirmed, resume auto-follow
        }
        // else: still waiting for confirmation — don't touch _selectedIndex
      } else if (!_blockAutoFollowWhenStopped) {
        // Auto-follow: update the display whenever the locator changes and we're
        // not in the post-stop window (where Python jumps back to _active_name).
        final idx = locators.indexWhere((l) => l.name == s.currentLocatorName);
        if (idx != -1) _selectedIndex = idx;
      }
    }

    if (_selectedIndex == null &&
        s.currentLocatorName == null &&
        locators.isNotEmpty) {
      _selectedIndex = 0;
      _service.setActiveSong(locators[0].name);
    }

    if (_localLoopEnabled != null && s.loopEnabled == _localLoopEnabled) {
      _localLoopEnabled = null;
    }
    if (_localIsPlaying != null && s.isPlaying == _localIsPlaying) {
      _localIsPlaying = null;
    }

    notifyListeners();
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _syncOrder(List<AbletonLocator> incoming) {
    if (_locatorOrder.isEmpty) return;
    _locatorOrder = _locatorOrder
        .where((n) => incoming.any((l) => l.name == n))
        .toList();
    for (final loc in incoming) {
      if (!_locatorOrder.contains(loc.name)) _locatorOrder.add(loc.name);
    }
  }

  AbletonState get state => _state;
  bool get loopEnabled => _localLoopEnabled ?? _state.loopEnabled;
  bool get isPlaying => _localIsPlaying ?? _state.isPlaying;
  String get host => _host;
  int get port => _port;
  bool get isConnected => _state.connectionStatus == ConnectionStatus.connected;

  List<AbletonLocator> get locators {
    final raw = _state.locators;
    if (_locatorOrder.isEmpty) return raw;
    final ordered = <AbletonLocator>[];
    for (final name in _locatorOrder) {
      try {
        ordered.add(raw.firstWhere((l) => l.name == name));
      } catch (_) {}
    }
    for (final loc in raw) {
      if (!ordered.any((l) => l.name == loc.name)) ordered.add(loc);
    }
    return ordered;
  }

  List<AbletonTrack> get tracks => _state.tracks;

  /// Directly set the locator order (e.g. after group reorder).
  void setLocatorOrder(List<String> orderedNames) {
    _locatorOrder = List<String>.from(orderedNames);
    _lastSentSetlist = _locatorOrder;
    _service.setSetlist(_locatorOrder);
    // The initialization fallback in _onStateUpdate runs before groups load,
    // so it may have told Python the wrong active song (Ableton's first
    // locator by position rather than the user's first group song).
    // When the correct order arrives for the first time and the display is
    // still at the default position (index 0), re-send the correct first song
    // so Python's _active_name is updated before the user presses play.
    if (_selectedIndex == 0 && orderedNames.isNotEmpty) {
      _service.setActiveSong(orderedNames[0]);
    }
    notifyListeners();
  }

  void reorderLocators(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final current = List<AbletonLocator>.from(locators);
    final moved = current.removeAt(oldIndex);
    current.insert(newIndex, moved);
    _locatorOrder = current.map((l) => l.name).toList();
    if (_selectedIndex == oldIndex) {
      _selectedIndex = newIndex;
    } else if (_selectedIndex != null) {
      if (oldIndex < _selectedIndex! && newIndex >= _selectedIndex!) {
        _selectedIndex = _selectedIndex! - 1;
      } else if (oldIndex > _selectedIndex! && newIndex <= _selectedIndex!) {
        _selectedIndex = _selectedIndex! + 1;
      }
    }
    final orderedNames = locators.map((l) => l.name).toList();
    _lastSentSetlist = orderedNames;
    _service.setSetlist(orderedNames);
    notifyListeners();
  }

  int? get currentLocatorIndex {
    final name = _state.currentLocatorName;
    if (name == null) return null;
    final idx = locators.indexWhere((l) => l.name == name);
    return idx == -1 ? null : idx;
  }

  int? get selectedIndex => _selectedIndex ?? currentLocatorIndex;

  AbletonLocator? get selectedLocator {
    final idx = selectedIndex;
    if (idx == null || idx >= locators.length) return null;
    return locators[idx];
  }

  /// Time signature parsed from the active locator's name, e.g. "Verse 6/8"
  /// returns (6, 8). Returns null if the name contains no N/D pattern.
  /// This is the only reliable source for per-section time signatures because
  /// Ableton's Python API does not update signature_numerator from arrangement
  /// Time Signature Markers during playback.
  (int, int)? get locatorTimeSig {
    final name = selectedLocator?.name ?? _state.currentLocatorName;
    if (name == null) return null;
    final m = RegExp(r'(\d+)/(\d+)').firstMatch(name);
    if (m == null) return null;
    final n = int.tryParse(m.group(1)!);
    final d = int.tryParse(m.group(2)!);
    if (n != null && n > 0 && d != null && d > 0) return (n, d);
    return null;
  }

  AbletonLocator? get nextLocator {
    final idx = selectedIndex;
    if (idx == null) return locators.isNotEmpty ? locators[0] : null;
    if (idx + 1 >= locators.length) return null;
    return locators[idx + 1];
  }

  AbletonLocator? get previousLocator {
    final idx = selectedIndex;
    if (idx == null || idx == 0) return null;
    return locators[idx - 1];
  }

  void selectLocator(int index) {
    _selectedIndex = index;
    final name = locators[index].name;
    _pendingLocatorName = name; // hold selection until Ableton confirms jump
    _pendingClearTimer?.cancel();
    // If Ableton never confirms the jump (e.g. race condition), release the
    // guard after 1.5 s so auto-follow can resume normally during playback.
    _pendingClearTimer = Timer(const Duration(milliseconds: 1500), () {
      if (_pendingLocatorName != null) {
        _pendingLocatorName = null;
        notifyListeners();
      }
    });
    notifyListeners();
    _service.jumpToLocator(name);
    _service.setActiveSong(name);
  }

  bool goToNext() {
    final idx = selectedIndex ?? -1;
    final next = idx + 1;
    if (next >= locators.length) return false;
    selectLocator(next);
    return true;
  }

  bool goToPrevious() {
    final idx = selectedIndex ?? 0;
    if (idx <= 0) return false;
    selectLocator(idx - 1);
    return true;
  }

  // ── Connection ────────────────────────────────────────────────────────

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _host = prefs.getString('ableton_host') ?? '127.0.0.1';
    _port = prefs.getInt('ableton_port') ?? 9000;
    notifyListeners();
    _service.connect(_host, _port);
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ableton_host', _host);
    await prefs.setInt('ableton_port', _port);
  }

  Future<void> saveSettings(String host, int port) async {
    _host = host;
    _port = port;
    notifyListeners();
    await _saveSettings();
    _service.connect(_host, _port);
  }

  void connect() => _service.connect(_host, _port);
  void disconnect() => _service.disconnect();
  void play() {
    _postStopTimer?.cancel();
    _postStopTimer = null;
    _blockAutoFollowWhenStopped = false; // resume auto-follow on play
    _localIsPlaying = true;
    notifyListeners();
    // Sync Python's active locator before playing so it doesn't jump back to
    // a stale position (e.g. after clicking Next while playing).
    final sel = selectedLocator;
    if (sel != null) _service.setActiveSong(sel.name);
    _service.play();
  }
  void stop() {
    // Guard: if already stopped, don't send another stop — Ableton would
    // reset the playhead to position 0 on a second stop command.
    final alreadyStopped = !(_localIsPlaying ?? _state.isPlaying);
    if (alreadyStopped) return;
    _localIsPlaying = false;
    // Block auto-follow briefly. Python's stop handler jumps the playhead to
    // _active_name (may be a different song); the 800 ms timer lets that
    // jump-back position land and be ignored, then releases the block so that
    // any subsequent Ableton play or session-view clip triggers auto-follow.
    _postStopTimer?.cancel();
    _blockAutoFollowWhenStopped = true;
    _postStopTimer = Timer(const Duration(milliseconds: 800), () {
      _blockAutoFollowWhenStopped = false;
      _postStopTimer = null;
      notifyListeners();
    });
    _pendingClearTimer?.cancel();
    _pendingClearTimer = null;
    _pendingLocatorName = null;
    notifyListeners();
    _service.stop();
  }
  void record() => _service.record();
  void setBpm(double bpm) => _service.setBpm(bpm);
  void setLoop(bool enabled) {
    _localLoopEnabled = enabled;
    notifyListeners();
    _service.setLoop(enabled);
  }
  void sendDebug() => _service.sendDebug();
  Stream<Map<String, dynamic>> get debugStream => _service.debugStream;
  Stream<Map<String, dynamic>> get volLabelStream => _service.volLabelStream;
  Stream<String> get masterVolLabelStream => _service.masterVolLabelStream;
  Stream<String> get cueVolLabelStream => _service.cueVolLabelStream;
  void setMasterVolume(double volume) => _service.setMasterVolume(volume);
  void setCueVolume(double volume) => _service.setCueVolume(volume);
  void getVolLabel(int index, double volume) => _service.getVolLabel(index, volume);
  void muteTrack(int index) => _service.muteTrack(index);
  void setTrackVolume(int index, double volume) =>
      _service.setTrackVolume(index, volume);
  void soloTrack(int index) => _service.soloTrack(index);
  void refresh() => _service.refreshState();
  void jumpToBar(int bar) => _service.jumpToBar(bar);

  @override
  void dispose() {
    _pendingClearTimer?.cancel();
    _postStopTimer?.cancel();
    _service.dispose();
    super.dispose();
  }
}
