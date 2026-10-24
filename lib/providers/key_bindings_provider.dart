import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Actions ───────────────────────────────────────────────────────────────────

enum KeyAction { playStop, play, next, previous, record, loop }

extension KeyActionX on KeyAction {
  String get label => switch (this) {
        KeyAction.playStop => 'Play / Stop',
        KeyAction.play => 'Play (when stopped)',
        KeyAction.next => 'Next locator',
        KeyAction.previous => 'Previous locator',
        KeyAction.record => 'Toggle record',
        KeyAction.loop => 'Toggle loop',
      };

  IconData get icon => switch (this) {
        KeyAction.playStop => Icons.play_arrow_rounded,
        KeyAction.play => Icons.play_circle_outline_rounded,
        KeyAction.next => Icons.skip_next_rounded,
        KeyAction.previous => Icons.skip_previous_rounded,
        KeyAction.record => Icons.fiber_manual_record_rounded,
        KeyAction.loop => Icons.loop_rounded,
      };

  LogicalKeyboardKey get defaultKey => switch (this) {
        KeyAction.playStop => LogicalKeyboardKey.space,
        KeyAction.play => LogicalKeyboardKey.enter,
        KeyAction.next => LogicalKeyboardKey.arrowRight,
        KeyAction.previous => LogicalKeyboardKey.arrowLeft,
        KeyAction.record => LogicalKeyboardKey.keyR,
        KeyAction.loop => LogicalKeyboardKey.keyL,
      };
}

// ── Provider ──────────────────────────────────────────────────────────────────

class KeyBindingsProvider extends ChangeNotifier {
  final Map<KeyAction, LogicalKeyboardKey> _custom = {};

  KeyBindingsProvider() {
    _load();
  }

  /// The currently bound key for [action] (custom or default).
  LogicalKeyboardKey keyFor(KeyAction action) =>
      _custom[action] ?? action.defaultKey;

  /// Whether [action] has a custom (non-default) binding.
  bool isCustom(KeyAction action) => _custom.containsKey(action);

  /// Returns the action whose current key equals [key], or null.
  KeyAction? actionFor(LogicalKeyboardKey key) {
    for (final a in KeyAction.values) {
      if (keyFor(a) == key) return a;
    }
    return null;
  }

  Future<void> setBinding(KeyAction action, LogicalKeyboardKey key) async {
    // Prevent assigning a key already used by another action.
    for (final a in KeyAction.values) {
      if (a != action && keyFor(a) == key) return;
    }
    _custom[action] = key;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('keybind_${action.name}', key.keyId);
  }

  Future<void> resetBinding(KeyAction action) async {
    _custom.remove(action);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('keybind_${action.name}');
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    bool any = false;
    for (final action in KeyAction.values) {
      final saved = prefs.getInt('keybind_${action.name}');
      if (saved != null) {
        _custom[action] = LogicalKeyboardKey(saved);
        any = true;
      }
    }
    if (any) notifyListeners();
  }

  // ── Display helper ──────────────────────────────────────────────────────────

  static String displayName(LogicalKeyboardKey key) {
    final names = <LogicalKeyboardKey, String>{
      LogicalKeyboardKey.space: 'Space',
      LogicalKeyboardKey.enter: 'Enter',
      LogicalKeyboardKey.numpadEnter: 'Numpad Enter',
      LogicalKeyboardKey.arrowLeft: '← Left',
      LogicalKeyboardKey.arrowRight: '→ Right',
      LogicalKeyboardKey.arrowUp: '↑ Up',
      LogicalKeyboardKey.arrowDown: '↓ Down',
      LogicalKeyboardKey.escape: 'Escape',
      LogicalKeyboardKey.tab: 'Tab',
      LogicalKeyboardKey.backspace: 'Backspace',
      LogicalKeyboardKey.delete: 'Delete',
      LogicalKeyboardKey.home: 'Home',
      LogicalKeyboardKey.end: 'End',
      LogicalKeyboardKey.pageUp: 'Page Up',
      LogicalKeyboardKey.pageDown: 'Page Down',
      LogicalKeyboardKey.f1: 'F1',
      LogicalKeyboardKey.f2: 'F2',
      LogicalKeyboardKey.f3: 'F3',
      LogicalKeyboardKey.f4: 'F4',
      LogicalKeyboardKey.f5: 'F5',
      LogicalKeyboardKey.f6: 'F6',
      LogicalKeyboardKey.f7: 'F7',
      LogicalKeyboardKey.f8: 'F8',
      LogicalKeyboardKey.f9: 'F9',
      LogicalKeyboardKey.f10: 'F10',
      LogicalKeyboardKey.f11: 'F11',
      LogicalKeyboardKey.f12: 'F12',
    };
    if (names.containsKey(key)) return names[key]!;
    final label = key.keyLabel;
    if (label.isEmpty) return 'Key(${key.keyId})';
    return label.length == 1 ? label.toUpperCase() : label;
  }
}
