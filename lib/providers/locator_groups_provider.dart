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

/// Lightweight view of a setlist for menus.
class SetlistInfo {
  final String id;
  final String name;
  const SetlistInfo(this.id, this.name);
}

/// A scene slot: a labelled tile that, when activated, switches to the setlist
/// assigned to it.
class SceneSlot {
  final String name;
  final String? setlistId;
  const SceneSlot(this.name, [this.setlistId]);

  SceneSlot copyWith({String? name, String? setlistId, bool clearSetlist = false}) =>
      SceneSlot(name ?? this.name, clearSetlist ? null : (setlistId ?? this.setlistId));

  Map<String, dynamic> toJson() => {'name': name, 'setlist': setlistId};

  factory SceneSlot.fromJson(Map<String, dynamic> json) =>
      SceneSlot(json['name'] as String, json['setlist'] as String?);
}

/// A named layout: which songs are included, their order and folders.
class _SetlistData {
  String id;
  String name;
  List<LocatorGroup> groups;
  List<String> topOrder;

  /// Locators excluded from this setlist. Anything not hidden is included, so
  /// songs added later in Ableton show up everywhere until removed.
  Set<String> hidden;

  _SetlistData({
    required this.id,
    required this.name,
    List<LocatorGroup>? groups,
    List<String>? topOrder,
    Set<String>? hidden,
  })  : groups = groups ?? [],
        topOrder = topOrder ?? [],
        hidden = hidden ?? {};

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'groups': groups.map((g) => g.toJson()).toList(),
        'order': topOrder,
        'hidden': hidden.toList(),
      };

  factory _SetlistData.fromJson(Map<String, dynamic> json) => _SetlistData(
        id: json['id'] as String,
        name: json['name'] as String,
        groups: (json['groups'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .map(LocatorGroup.fromJson)
            .toList(),
        topOrder: (json['order'] as List? ?? []).cast<String>(),
        hidden: (json['hidden'] as List? ?? []).cast<String>().toSet(),
      );

  _SetlistData copyAs(String newId, String newName) => _SetlistData(
        id: newId,
        name: newName,
        groups: groups.map((g) => g.copyWith()).toList(),
        topOrder: List.of(topOrder),
        hidden: Set.of(hidden),
      );
}

class LocatorGroupsProvider extends ChangeNotifier {
  static const _kGroupsKey = 'locator_groups_v1'; // legacy (pre-setlists)
  static const _kOrderKey  = 'locator_top_order_v1'; // legacy (pre-setlists)
  static const _kSigsKey   = 'locator_time_sigs_v1';
  static const _kSetlistsKey = 'setlists_v1';
  static const _kScenesKey = 'scenes_v1';
  static const _defaultId = 'default';
  static const maxScenes = 12;

  // Working copy of the ACTIVE setlist. Every existing group/order method
  // operates on these; they're written back to [_lists] on save/switch.
  List<LocatorGroup> _groups = [];
  /// Ordered list of top-level slot keys ('group:…' or 'loc:…').
  List<String> _topOrder = [];
  Set<String> _hidden = {};

  /// Per-locator time signature: locator name → 'N/D' string. Shared by all
  /// setlists, since a song's signature doesn't depend on where it's played.
  Map<String, String> _locatorSigs = {};

  final List<_SetlistData> _lists = [
    _SetlistData(id: _defaultId, name: 'Main Setlist'),
  ];
  String _activeId = _defaultId;

  List<LocatorGroup> get groups => _groups;

  // ── Scenes ───────────────────────────────────────────────────────────────

  List<SceneSlot> _scenes = [
    for (var i = 1; i <= 4; i++) SceneSlot('Scene $i'),
  ];

  List<SceneSlot> get scenes => _scenes;

  /// The setlist assigned to scene [i], or null.
  SetlistInfo? setlistForScene(int i) {
    final id = _scenes[i].setlistId;
    for (final l in _lists) {
      if (l.id == id) return SetlistInfo(l.id, l.name);
    }
    return null;
  }

  /// The scene whose setlist is currently in use (first match), or null.
  int? get activeSceneIndex {
    for (var i = 0; i < _scenes.length; i++) {
      if (isSceneActive(i)) return i;
    }
    return null;
  }

  /// Name to show for "what's live": the active scene's name, falling back to
  /// the setlist's name when no scene is assigned to it.
  String get activeDisplayName {
    final i = activeSceneIndex;
    return i == null ? activeSetlistName : _scenes[i].name;
  }

  /// True when scene [i]'s setlist is the one currently in use.
  bool isSceneActive(int i) =>
      _scenes[i].setlistId != null && _scenes[i].setlistId == _activeId;

  Future<void> assignScene(int i, String? setlistId) async {
    _scenes[i] = setlistId == null
        ? _scenes[i].copyWith(clearSetlist: true)
        : _scenes[i].copyWith(setlistId: setlistId);
    notifyListeners();
    await _saveScenes();
  }

  Future<void> renameScene(int i, String name) async {
    _scenes[i] = _scenes[i].copyWith(name: name.trim());
    notifyListeners();
    await _saveScenes();
  }

  Future<void> addScene() async {
    if (_scenes.length >= maxScenes) return;
    _scenes = [..._scenes, SceneSlot('Scene ${_scenes.length + 1}')];
    notifyListeners();
    await _saveScenes();
  }

  Future<void> removeScene(int i) async {
    if (_scenes.length <= 1) return;
    _scenes = List.of(_scenes)..removeAt(i);
    notifyListeners();
    await _saveScenes();
  }

  /// Switches to scene [i]'s setlist. Returns false if nothing is assigned.
  Future<bool> activateScene(int i) async {
    final l = setlistForScene(i);
    if (l == null) return false;
    await switchSetlist(l.id);
    return true;
  }

  // ── Setlists ─────────────────────────────────────────────────────────────

  List<SetlistInfo> get setlists =>
      _lists.map((l) => SetlistInfo(l.id, l.name)).toList();
  String get activeSetlistId => _activeId;
  String get activeSetlistName =>
      _lists.firstWhere((l) => l.id == _activeId).name;
  bool get canDeleteSetlist => _lists.length > 1;

  /// Locator names excluded from the active setlist.
  Set<String> get hiddenNames => _hidden;

  /// Number of songs in [id] given the project's full locator list.
  int songCount(String id, List<String> allNames) {
    _commitActive();
    final l = _lists.firstWhere((l) => l.id == id);
    return allNames.where((n) => !l.hidden.contains(n)).length;
  }

  bool setlistNameTaken(String name, {String? exceptId}) => _lists.any((l) =>
      l.id != exceptId && l.name.toLowerCase() == name.trim().toLowerCase());

  void _commitActive() {
    final l = _lists.firstWhere((l) => l.id == _activeId);
    l.groups = _groups;
    l.topOrder = _topOrder;
    l.hidden = _hidden;
  }

  void _activate(String id) {
    final l = _lists.firstWhere((l) => l.id == id);
    _activeId = id;
    _groups = l.groups;
    _topOrder = l.topOrder;
    _hidden = l.hidden;
  }

  String _newId() => 'sl_${DateTime.now().microsecondsSinceEpoch}';

  /// Creates a setlist containing only [included] and switches to it.
  /// With [keepFolders], the active setlist's folders and order are carried
  /// over, limited to the included songs (folders left empty are dropped).
  Future<void> createSetlist(
      String name, Set<String> included, List<String> allNames,
      {bool keepFolders = false}) async {
    _commitActive();
    final id = _newId();
    var newGroups = <LocatorGroup>[];
    var newOrder = <String>[];
    if (keepFolders) {
      newGroups = [
        for (final g in _groups)
          if (g.locatorNames.any(included.contains))
            g.copyWith(
                locatorNames:
                    g.locatorNames.where(included.contains).toList()),
      ];
      final groupNames = newGroups.map((g) => g.name).toSet();
      newOrder = [
        for (final k in _topOrder)
          if (k.startsWith('group:')
              ? groupNames.contains(k.substring(6))
              : included.contains(k.substring(4)))
            k,
      ];
    }
    _lists.add(_SetlistData(
      id: id,
      name: name.trim(),
      groups: newGroups,
      topOrder: newOrder,
      hidden: allNames.where((n) => !included.contains(n)).toSet(),
    ));
    _activate(id);
    notifyListeners();
    await _save();
  }

  /// Copies [sourceId] (songs, order and folders) under a new name and
  /// switches to the copy.
  Future<void> duplicateSetlist(String sourceId, String name) async {
    _commitActive();
    final src = _lists.firstWhere((l) => l.id == sourceId);
    final copy = src.copyAs(_newId(), name.trim());
    _lists.add(copy);
    _activate(copy.id);
    notifyListeners();
    await _save();
  }

  Future<void> switchSetlist(String id) async {
    if (id == _activeId || !_lists.any((l) => l.id == id)) return;
    _commitActive();
    _activate(id);
    notifyListeners();
    await _save();
  }

  Future<void> renameSetlist(String id, String name) async {
    _lists.firstWhere((l) => l.id == id).name = name.trim();
    notifyListeners();
    await _save();
  }

  Future<void> deleteSetlist(String id) async {
    if (_lists.length <= 1) return;
    _commitActive();
    _lists.removeWhere((l) => l.id == id);
    if (_activeId == id) _activate(_lists.first.id);
    // Scenes that pointed at it become unassigned.
    _scenes = [
      for (final s in _scenes)
        s.setlistId == id ? s.copyWith(clearSetlist: true) : s,
    ];
    notifyListeners();
    await _save();
    await _saveScenes();
  }

  /// Sets which songs the ACTIVE setlist contains. Removed songs also leave
  /// any folders (empty folders are dropped).
  Future<void> setActiveSongs(Set<String> included, List<String> allNames) async {
    _hidden = allNames.where((n) => !included.contains(n)).toSet();
    _groups = _groups
        .map((g) => g.copyWith(
            locatorNames:
                g.locatorNames.where((n) => !_hidden.contains(n)).toList()))
        .where((g) => g.locatorNames.isNotEmpty)
        .toList();
    _topOrder.removeWhere(
        (k) => k.startsWith('loc:') && _hidden.contains(k.substring(4)));
    notifyListeners();
    await _save();
  }

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
  List<TopLevelSlot> topSlots(List<String> allNames) {
    // Songs excluded from the active setlist never get a slot.
    final allLocatorNames =
        allNames.where((n) => !_hidden.contains(n)).toList();
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

      // Pre-setlist data: one global layout. It becomes the first setlist.
      var legacyGroups = <LocatorGroup>[];
      var legacyOrder = <String>[];
      final raw = prefs.getString(_kGroupsKey);
      if (raw != null) {
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        legacyGroups = list.map(LocatorGroup.fromJson).toList();
      }
      final orderRaw = prefs.getString(_kOrderKey);
      if (orderRaw != null) {
        legacyOrder = (jsonDecode(orderRaw) as List).cast<String>();
      }

      final setlistsRaw = prefs.getString(_kSetlistsKey);
      if (setlistsRaw != null) {
        final map = jsonDecode(setlistsRaw) as Map<String, dynamic>;
        final loaded = (map['lists'] as List)
            .cast<Map<String, dynamic>>()
            .map(_SetlistData.fromJson)
            .toList();
        if (loaded.isNotEmpty) {
          _lists
            ..clear()
            ..addAll(loaded);
          final active = map['active'] as String?;
          _activeId = _lists.any((l) => l.id == active)
              ? active!
              : _lists.first.id;
        }
      }

      // Import legacy layout into the main setlist if that setlist is still
      // empty (first run after upgrade, or old settings restored later).
      final main = _lists.where((l) => l.id == _defaultId).firstOrNull;
      if (main != null &&
          main.groups.isEmpty &&
          main.topOrder.isEmpty &&
          (legacyGroups.isNotEmpty || legacyOrder.isNotEmpty)) {
        main.groups = legacyGroups;
        main.topOrder = legacyOrder;
      }
      _activate(_activeId);

      final scenesRaw = prefs.getString(_kScenesKey);
      if (scenesRaw != null) {
        final loaded = (jsonDecode(scenesRaw) as List)
            .cast<Map<String, dynamic>>()
            .map(SceneSlot.fromJson)
            .toList();
        if (loaded.isNotEmpty) _scenes = loaded;
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
      _commitActive();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kSetlistsKey,
        jsonEncode({
          'active': _activeId,
          'lists': _lists.map((l) => l.toJson()).toList(),
        }),
      );
    } catch (_) {}
  }

  Future<void> _saveScenes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _kScenesKey, jsonEncode(_scenes.map((s) => s.toJson()).toList()));
    } catch (_) {}
  }

  Future<void> _saveSigs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kSigsKey, jsonEncode(_locatorSigs));
    } catch (_) {}
  }
}
