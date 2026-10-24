import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocatorGroup {
  final String name;
  final List<String> locatorNames; // ordered
  final bool collapsed;

  const LocatorGroup({
    required this.name,
    required this.locatorNames,
    this.collapsed = false,
  });

  LocatorGroup copyWith({
    String? name,
    List<String>? locatorNames,
    bool? collapsed,
  }) =>
      LocatorGroup(
        name: name ?? this.name,
        locatorNames: locatorNames ?? this.locatorNames,
        collapsed: collapsed ?? this.collapsed,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'locators': locatorNames,
      };

  factory LocatorGroup.fromJson(Map<String, dynamic> json) => LocatorGroup(
        name: json['name'] as String,
        locatorNames: (json['locators'] as List).cast<String>(),
      );
}

// A top-level slot in the visible list: either a named group or a lone locator.
class TopLevelSlot {
  /// 'group:Name' or 'loc:LocatorName'
  final String key;
  const TopLevelSlot(this.key);

  bool get isGroup => key.startsWith('group:');
  String get id => isGroup ? key.substring(6) : key.substring(4);
}

class LocatorGroupsProvider extends ChangeNotifier {
  static const _kGroupsKey = 'locator_groups_v1';
  static const _kOrderKey  = 'locator_top_order_v1';
  static const _kSigsKey   = 'locator_time_sigs_v1';

  List<LocatorGroup> _groups = [];
  /// Ordered list of top-level slot keys ('group:…' or 'loc:…').
  List<String> _topOrder = [];
  /// Per-locator time signature: locator name → 'N/D' string.
  Map<String, String> _locatorSigs = {};

  List<LocatorGroup> get groups => _groups;

  LocatorGroupsProvider() {
    _load();
  }

  // ── Queries ──────────────────────────────────────────────────────────────

  LocatorGroup? groupOf(String locatorName) {
    for (final g in _groups) {
      if (g.locatorNames.contains(locatorName)) return g;
    }
    return null;
  }

  bool isGrouped(String locatorName) => groupOf(locatorName) != null;

  /// Ordered top-level slots reconciled against current locators + groups.
  List<TopLevelSlot> topSlots(List<String> allLocatorNames) {
    final grouped = <String>{
      for (final g in _groups) ...g.locatorNames,
    };

    // Keys that should exist
    final validGroupKeys = {for (final g in _groups) 'group:${g.name}'};
    final validLocKeys   = {
      for (final n in allLocatorNames)
        if (!grouped.contains(n)) 'loc:$n',
    };
    final validKeys = {...validGroupKeys, ...validLocKeys};

    // Remove stale, keep order
    _topOrder = _topOrder.where(validKeys.contains).toList();

    // Append anything new (preserving Ableton order for ungrouped locators)
    final existing = Set<String>.from(_topOrder);
    for (final n in allLocatorNames) {
      final k = grouped.contains(n) ? null : 'loc:$n';
      if (k != null && !existing.contains(k)) {
        _topOrder.add(k);
        existing.add(k);
      }
    }
    for (final g in _groups) {
      final k = 'group:${g.name}';
      if (!existing.contains(k)) {
        _topOrder.add(k);
        existing.add(k);
      }
    }

    return _topOrder.map(TopLevelSlot.new).toList();
  }

  // ── Mutations ─────────────────────────────────────────────────────────────

  Future<void> createGroup(String name, List<String> locatorNames) async {
    _groups = _groups.map((g) {
      final remaining =
          g.locatorNames.where((l) => !locatorNames.contains(l)).toList();
      return g.copyWith(locatorNames: remaining);
    }).where((g) => g.locatorNames.isNotEmpty).toList();

    _groups.add(LocatorGroup(name: name, locatorNames: locatorNames));
    // Remove individual loc slots; group slot will be appended by topSlots()
    _topOrder.removeWhere((k) =>
        k.startsWith('loc:') && locatorNames.contains(k.substring(4)));
    notifyListeners();
    await _save();
  }

  /// Add [locatorNames] to an existing group by name.
  Future<void> addToGroup(String groupName, List<String> locatorNames) async {
    // Remove from any current group first
    _groups = _groups.map((g) {
      final remaining =
          g.locatorNames.where((l) => !locatorNames.contains(l)).toList();
      return g.copyWith(locatorNames: remaining);
    }).where((g) => g.locatorNames.isNotEmpty).toList();

    _groups = _groups.map((g) {
      if (g.name != groupName) return g;
      final merged = [
        ...g.locatorNames,
        ...locatorNames.where((l) => !g.locatorNames.contains(l)),
      ];
      return g.copyWith(locatorNames: merged);
    }).toList();

    // Remove individual loc slots for moved locators
    _topOrder.removeWhere((k) =>
        k.startsWith('loc:') && locatorNames.contains(k.substring(4)));
    notifyListeners();
    await _save();
  }

  /// Reorder items within a group.
  Future<void> reorderWithinGroup(
      String groupName, int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    _groups = _groups.map((g) {
      if (g.name != groupName) return g;
      final list = List<String>.from(g.locatorNames);
      final item = list.removeAt(oldIndex);
      list.insert(newIndex, item);
      return g.copyWith(locatorNames: list);
    }).toList();
    notifyListeners();
    await _save();
  }

  /// Remove specific locators from whatever group they belong to.
  Future<void> removeFromGroup(List<String> locatorNames) async {
    _groups = _groups.map((g) {
      final remaining =
          g.locatorNames.where((l) => !locatorNames.contains(l)).toList();
      return g.copyWith(locatorNames: remaining);
    }).where((g) => g.locatorNames.isNotEmpty).toList();
    // Individual loc slots will be re-added by topSlots()
    notifyListeners();
    await _save();
  }

  Future<void> renameGroup(String oldName, String newName) async {
    _groups = _groups.map((g) =>
        g.name == oldName ? g.copyWith(name: newName) : g).toList();
    final i = _topOrder.indexOf('group:$oldName');
    if (i >= 0) _topOrder[i] = 'group:$newName';
    notifyListeners();
    await _save();
  }

  Future<void> deleteGroup(String name) async {
    _groups = _groups.where((g) => g.name != name).toList();
    _topOrder.remove('group:$name');
    // Individual loc slots will be re-added by topSlots()
    notifyListeners();
    await _save();
  }

  void toggleCollapsed(String groupName) {
    _groups = _groups.map((g) =>
        g.name == groupName ? g.copyWith(collapsed: !g.collapsed) : g).toList();
    notifyListeners();
  }

  /// Reorder top-level slots (groups and ungrouped locators).
  Future<void> reorderTopSlots(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    final item = _topOrder.removeAt(oldIndex);
    _topOrder.insert(newIndex, item);
    notifyListeners();
    await _save();
  }

  // ── Time signature per locator ───────────────────────────────────────────

  /// Returns the user-set time signature for [locatorName], or null.
  (int, int)? getLocatorSig(String? locatorName) {
    if (locatorName == null) return null;
    final raw = _locatorSigs[locatorName];
    if (raw == null) return null;
    final parts = raw.split('/');
    if (parts.length != 2) return null;
    final n = int.tryParse(parts[0]);
    final d = int.tryParse(parts[1]);
    if (n == null || d == null || n <= 0 || d <= 0) return null;
    return (n, d);
  }

  Future<void> setLocatorSig(String locatorName, int n, int d) async {
    _locatorSigs[locatorName] = '$n/$d';
    notifyListeners();
    await _saveSigs();
  }

  Future<void> clearLocatorSig(String locatorName) async {
    _locatorSigs.remove(locatorName);
    notifyListeners();
    await _saveSigs();
  }

  // ── Persistence ──────────────────────────────────────────────────────────

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kGroupsKey);
      if (raw != null) {
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        _groups = list.map(LocatorGroup.fromJson).toList();
      }
      final orderRaw = prefs.getString(_kOrderKey);
      if (orderRaw != null) {
        _topOrder = (jsonDecode(orderRaw) as List).cast<String>();
      }
      final sigsRaw = prefs.getString(_kSigsKey);
      if (sigsRaw != null) {
        _locatorSigs = (jsonDecode(sigsRaw) as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, v as String));
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _kGroupsKey, jsonEncode(_groups.map((g) => g.toJson()).toList()));
      await prefs.setString(_kOrderKey, jsonEncode(_topOrder));
    } catch (_) {}
  }

  Future<void> _saveSigs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kSigsKey, jsonEncode(_locatorSigs));
    } catch (_) {}
  }
}
