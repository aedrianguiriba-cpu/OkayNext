import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/ableton_state.dart';
import '../providers/ableton_provider.dart';
import '../providers/key_bindings_provider.dart';
import '../providers/locator_groups_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/setlist_selector.dart';
import '../widgets/tap_scale.dart';
import '../widgets/transport_controls.dart';
import 'performance_screen.dart';
import 'scene_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'HomeScreen');
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final p = context.read<AbletonProvider>();
    if (!p.isConnected) return KeyEventResult.ignored;

    final kb = context.read<KeyBindingsProvider>();
    final key = event.logicalKey;

    if (key == kb.keyFor(KeyAction.playStop)) {
      p.isPlaying ? p.stop() : p.play();
      return KeyEventResult.handled;
    }
    if (key == kb.keyFor(KeyAction.play)) {
      if (!p.isPlaying) p.play();
      return KeyEventResult.handled;
    }
    if (key == kb.keyFor(KeyAction.next)) {
      p.goToNext();
      return KeyEventResult.handled;
    }
    if (key == kb.keyFor(KeyAction.previous)) {
      p.goToPrevious();
      return KeyEventResult.handled;
    }
    if (key == kb.keyFor(KeyAction.record)) {
      p.record();
      return KeyEventResult.handled;
    }
    if (key == kb.keyFor(KeyAction.loop)) {
      p.setLoop(!p.loopEnabled);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final ableton = context.watch<AbletonProvider>();
    final state = ableton.state;
    final locators = ableton.locators;
    final selectedIdx = ableton.selectedIndex;
    final col = context.col;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: col.background,
        appBar: _HomeAppBar(
          ableton: ableton,
          locatorCount: locators.length,
          onPerformance: locators.isNotEmpty
              ? () => Navigator.push(context,
                    MaterialPageRoute(
                        builder: (_) => const PerformanceScreen(),
                        fullscreenDialog: true))
              : null,
          onSettings: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SettingsScreen())),
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: !ableton.isConnected
                  ? _DisconnectedState(ableton: ableton)
                  : locators.isEmpty
                      ? _NoLocatorsState(projectName: state.projectName)
                      : _LocatorList(
                          locators: locators,
                          selectedIdx: selectedIdx,
                          currentBeat: state.currentBeat,
                          isPlaying: ableton.isPlaying,
                          bpm: state.bpm,
                        ),
            ),
            const Positioned(
              top: 0,
              right: 0,
              bottom: 0,
              child: SidebarTransport(),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _LocatorList extends StatefulWidget {
  final List<AbletonLocator> locators;
  final int? selectedIdx;
  final double currentBeat;
  final bool isPlaying;
  final double bpm;

  const _LocatorList({
    required this.locators,
    required this.selectedIdx,
    required this.currentBeat,
    required this.isPlaying,
    required this.bpm,
  });

  @override
  State<_LocatorList> createState() => _LocatorListState();
}

class _LocatorListState extends State<_LocatorList> {
  final Set<String> _selected = {};
  bool _selecting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<LocatorGroupsProvider>().addListener(_syncOrderToAbleton);
      // Locators just arrived (this state is only created when locators are
      // non-empty). Groups may have loaded before the listener was registered,
      // so call _syncOrderToAbleton immediately to push the correct order now.
      _syncOrderToAbleton();
    });
  }

  @override
  void dispose() {
    context.read<LocatorGroupsProvider>().removeListener(_syncOrderToAbleton);
    super.dispose();
  }

  void _syncOrderToAbleton() {
    final gp = context.read<LocatorGroupsProvider>();
    final ableton = context.read<AbletonProvider>();
    // Use raw state locators (not the ordered list) so the source of truth
    // for existence is always Ableton's actual track list.
    final rawNames = ableton.state.locators.map((l) => l.name).toList();
    // Locators haven't arrived from Ableton yet — skip to avoid overwriting
    // _locatorOrder with an empty list before we know the full locator set.
    if (rawNames.isEmpty) return;
    // Songs left out of the active setlist are excluded everywhere.
    final hidden = gp.hiddenNames;
    final allNames = rawNames.where((n) => !hidden.contains(n)).toList();
    final slots = gp.topSlots(List.from(allNames));
    final ordered = <String>[];
    for (final slot in slots) {
      if (slot.isGroup) {
        try {
          final g = gp.groups.firstWhere((g) => g.name == slot.id);
          ordered.addAll(g.locatorNames
              .where((n) => allNames.contains(n)));
        } catch (_) {}
      } else {
        if (allNames.contains(slot.id)) ordered.add(slot.id);
      }
    }
    // Add any locators not yet in ordered (safety net)
    for (final n in allNames) {
      if (!ordered.contains(n)) ordered.add(n);
    }
    ableton.setLocatorOrder(ordered, hidden: Set.of(hidden));
  }

  void _enterSelect(String locatorName) {
    setState(() {
      _selecting = true;
      _selected.add(locatorName);
    });
  }

  void _toggleSelect(String locatorName) {
    setState(() {
      if (_selected.contains(locatorName)) {
        _selected.remove(locatorName);
      } else {
        _selected.add(locatorName);
      }
    });
  }

  void _cancelSelect() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  Future<void> _groupSelected() async {
    final names = List<String>.from(_selected);
    if (names.isEmpty) return;
    final gp = context.read<LocatorGroupsProvider>();
    final existingGroups = gp.groups;

    if (existingGroups.isNotEmpty) {
      // Let user pick: new group or add to existing
      final choice = await _showGroupPickerDialog(existingGroups);
      if (!mounted || choice == null) return;
      if (choice == '__new__') {
        final groupName = await _showNameDialog(context, 'Name this group');
        if (!mounted || groupName == null || groupName.trim().isEmpty) return;
        await gp.createGroup(groupName.trim(), names);
      } else {
        await gp.addToGroup(choice, names);
      }
    } else {
      final groupName = await _showNameDialog(context, 'Name this group');
      if (!mounted || groupName == null || groupName.trim().isEmpty) return;
      await gp.createGroup(groupName.trim(), names);
    }
    _cancelSelect();
  }

  Future<String?> _showGroupPickerDialog(List<LocatorGroup> groups) async {
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        final col = ctx.col;
        return AlertDialog(
          backgroundColor: col.surface,
          title: Text('Add to…',
              style: TextStyle(color: col.textPrimary, fontSize: 16)),
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                ...groups.map((g) => ListTile(
                      leading: const Icon(Icons.folder_rounded,
                          color: AppTheme.accent, size: 20),
                      title: Text(g.name,
                          style: TextStyle(color: col.textPrimary)),
                      subtitle: Text('${g.locatorNames.length} parts',
                          style: TextStyle(color: col.textMuted, fontSize: 11)),
                      onTap: () => Navigator.pop(ctx, g.name),
                    )),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.create_new_folder_rounded,
                      color: AppTheme.accent, size: 20),
                  title: Text('New group…',
                      style: TextStyle(color: col.textPrimary)),
                  onTap: () => Navigator.pop(ctx, '__new__'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel',
                  style: TextStyle(color: col.textSecondary)),
            ),
          ],
        );
      },
    );
  }

  Future<String?> _showNameDialog(BuildContext context, String title,
      {String initial = ''}) async {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        final col = ctx.col;
        return AlertDialog(
          backgroundColor: col.surface,
          title: Text(title,
              style: TextStyle(color: col.textPrimary, fontSize: 16)),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            style: TextStyle(color: col.textPrimary),
            decoration: InputDecoration(
              hintText: 'Group name…',
              hintStyle: TextStyle(color: col.textMuted),
              enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: col.border)),
              focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: AppTheme.accent)),
            ),
            onSubmitted: (_) => Navigator.pop(ctx, ctrl.text),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel',
                  style: TextStyle(color: col.textSecondary)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('OK',
                  style: TextStyle(color: AppTheme.accent)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ableton = context.read<AbletonProvider>();
    final groups = context.watch<LocatorGroupsProvider>();
    final locatorNames = widget.locators.map((l) => l.name).toList();
    final slots = groups.topSlots(locatorNames);

    return Column(
      children: [
        // ── Selection toolbar ──────────────────────────────────────────────
        if (_selecting)
          _SelectionBar(
            count: _selected.length,
            onGroup: _selected.length >= 2 ? _groupSelected : null,
            onCancel: _cancelSelect,
          ),

        // ── Reorderable list (one item per top-level slot) ─────────────────
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.only(top: 8, bottom: 8, right: 126),
            buildDefaultDragHandles: false,
            // ignore: deprecated_member_use
            onReorder: (oldIdx, newIdx) =>
                groups.reorderTopSlots(oldIdx, newIdx),
            proxyDecorator: (child, index, animation) => Material(
              color: Colors.transparent,
              child: ScaleTransition(
                scale: animation.drive(
                    Tween(begin: 1.0, end: 1.03)
                        .chain(CurveTween(curve: Curves.easeOut))),
                child: child,
              ),
            ),
            itemCount: slots.length,
            itemBuilder: (ctx, slotIdx) {
              final slot = slots[slotIdx];
              if (slot.isGroup) {
                final group = groups.groups
                    .firstWhere((g) => g.name == slot.id,
                        orElse: () => LocatorGroup(
                            name: slot.id, locatorNames: const []));
                return _GroupSlotWidget(
                  key: ValueKey(slot.key),
                  slotIndex: slotIdx,
                  group: group,
                  groups: groups,
                  locators: widget.locators,
                  selectedIdx: widget.selectedIdx,
                  currentBeat: widget.currentBeat,
                  isPlaying: widget.isPlaying,
                  bpm: widget.bpm,
                  selecting: _selecting,
                  selected: _selected,
                  ableton: ableton,
                  onLongPress: _enterSelect,
                  onToggleSelect: _toggleSelect,
                  onShowNameDialog: (title, {initial = ''}) =>
                      _showNameDialog(ctx, title, initial: initial),
                  onGroupReordered: _syncOrderToAbleton,
                );
              } else {
                final loc = widget.locators.firstWhere(
                    (l) => l.name == slot.id,
                    orElse: () =>
                        AbletonLocator(name: slot.id, position: 0, bar: 0));
                final i = widget.locators.indexWhere((l) => l.name == slot.id);
                return _StandaloneLocatorSlot(
                  key: ValueKey(slot.key),
                  slotIndex: slotIdx,
                  locator: loc,
                  locatorIndex: i,
                  locators: widget.locators,
                  selectedIdx: widget.selectedIdx,
                  currentBeat: widget.currentBeat,
                  isPlaying: widget.isPlaying,
                  bpm: widget.bpm,
                  selecting: _selecting,
                  selected: _selected,
                  ableton: ableton,
                  onLongPress: _enterSelect,
                  onToggleSelect: _toggleSelect,
                );
              }
            },
          ),
        ),
      ],
    );
  }
}

// ── Group slot: header + children as one reorderable unit ────────────────────

class _GroupSlotWidget extends StatelessWidget {
  final int slotIndex;
  final LocatorGroup group;
  final LocatorGroupsProvider groups;
  final List<AbletonLocator> locators;
  final int? selectedIdx;
  final double currentBeat;
  final bool isPlaying;
  final double bpm;
  final bool selecting;
  final Set<String> selected;
  final AbletonProvider ableton;
  final void Function(String) onLongPress;
  final void Function(String) onToggleSelect;
  final Future<String?> Function(String, {String initial}) onShowNameDialog;
  final VoidCallback onGroupReordered;

  const _GroupSlotWidget({
    super.key,
    required this.slotIndex,
    required this.group,
    required this.groups,
    required this.locators,
    required this.selectedIdx,
    required this.currentBeat,
    required this.isPlaying,
    required this.bpm,
    required this.selecting,
    required this.selected,
    required this.ableton,
    required this.onLongPress,
    required this.onToggleSelect,
    required this.onShowNameDialog,
    required this.onGroupReordered,
  });

  @override
  Widget build(BuildContext context) {
    final children = group.locatorNames;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GroupHeader(
          group: group,
          groups: groups,
          slotIndex: slotIndex,
          onShowNameDialog: onShowNameDialog,
        ),
        if (!group.collapsed)
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            // ignore: deprecated_member_use
            onReorder: (oldIdx, newIdx) {
              groups.reorderWithinGroup(group.name, oldIdx, newIdx);
              onGroupReordered();
            },
            proxyDecorator: (child, index, animation) => Material(
              color: Colors.transparent,
              child: ScaleTransition(
                scale: animation.drive(Tween(begin: 1.0, end: 1.03)
                    .chain(CurveTween(curve: Curves.easeOut))),
                child: child,
              ),
            ),
            itemCount: children.length,
            itemBuilder: (ctx, idx) {
              final lname = children[idx];
              final loc = locators.firstWhere((l) => l.name == lname,
                  orElse: () =>
                      AbletonLocator(name: lname, position: 0, bar: 0));
              final i = locators.indexWhere((l) => l.name == lname);
              return Stack(
                key: ValueKey(lname),
                children: [
                  _LocatorRow(
                    locator: loc,
                    locatorIndex: i,
                    locators: locators,
                    selectedIdx: selectedIdx,
                    currentBeat: currentBeat,
                    isPlaying: isPlaying,
                    bpm: bpm,
                    inGroup: true,
                    selecting: selecting,
                    selected: selected,
                    ableton: ableton,
                    onLongPress: onLongPress,
                    onToggleSelect: onToggleSelect,
                  ),
                  if (!selecting)
                    Positioned(
                      right: 20,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: ReorderableDragStartListener(
                          index: idx,
                          child: Icon(Icons.drag_indicator_rounded,
                              size: 18, color: ctx.col.borderBright),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

// ── Standalone locator slot ───────────────────────────────────────────────────

class _StandaloneLocatorSlot extends StatelessWidget {
  final int slotIndex;
  final AbletonLocator locator;
  final int locatorIndex;
  final List<AbletonLocator> locators;
  final int? selectedIdx;
  final double currentBeat;
  final bool isPlaying;
  final double bpm;
  final bool selecting;
  final Set<String> selected;
  final AbletonProvider ableton;
  final void Function(String) onLongPress;
  final void Function(String) onToggleSelect;

  const _StandaloneLocatorSlot({
    super.key,
    required this.slotIndex,
    required this.locator,
    required this.locatorIndex,
    required this.locators,
    required this.selectedIdx,
    required this.currentBeat,
    required this.isPlaying,
    required this.bpm,
    required this.selecting,
    required this.selected,
    required this.ableton,
    required this.onLongPress,
    required this.onToggleSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _LocatorRow(
          locator: locator,
          locatorIndex: locatorIndex,
          locators: locators,
          selectedIdx: selectedIdx,
          currentBeat: currentBeat,
          isPlaying: isPlaying,
          bpm: bpm,
          inGroup: false,
          selecting: selecting,
          selected: selected,
          ableton: ableton,
          onLongPress: onLongPress,
          onToggleSelect: onToggleSelect,
        ),
        // Drag handle on the right (only when not in selection mode)
        if (!selecting)
          Positioned(
            right: 20,
            top: 0,
            bottom: 0,
            child: Center(
              child: ReorderableDragStartListener(
                index: slotIndex,
                child: Icon(Icons.drag_indicator_rounded,
                    size: 18, color: context.col.borderBright),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Time-signature picker (shared by locator rows and group headers) ──────────

/// Shows a picker dialog and writes the result to [LocatorGroupsProvider].
/// [locatorNames] is the list of locators to update (one for a single locator,
/// multiple for an entire group). [currentSig] is used to pre-select the chip;
/// pass null when locators may have mixed sigs.
Future<void> showTimeSigDialog(
  BuildContext context, {
  required String headerLabel,
  required List<String> locatorNames,
  (int, int)? currentSig,
}) async {
  const presets = [(4, 4), (3, 4), (2, 4), (6, 8), (5, 4), (7, 8)];

  final result = await showDialog<(int, int)?>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (ctx) {
      final dcol = ctx.col;
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        child: Container(
          decoration: BoxDecoration(
            color: dcol.surfaceElevated,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: dcol.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Time Signature',
                        style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.1)),
                    const SizedBox(height: 2),
                    Text(headerLabel,
                        style:
                            TextStyle(color: dcol.textSecondary, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GridView.count(
                  shrinkWrap: true,
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 1.7,
                  physics: const NeverScrollableScrollPhysics(),
                  children: presets.map((p) {
                    final isSelected = currentSig != null &&
                        currentSig.$1 == p.$1 &&
                        currentSig.$2 == p.$2;
                    return GestureDetector(
                      onTap: () => Navigator.pop(ctx, (p.$1, p.$2)),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppTheme.accent.withValues(alpha: 0.13)
                              : dcol.surfaceVariant,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? AppTheme.accent
                                : dcol.borderBright,
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '${p.$1}/${p.$2}',
                            style: TextStyle(
                              color: isSelected
                                  ? AppTheme.accent
                                  : dcol.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              if (currentSig != null) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Divider(height: 1, color: dcol.border),
                ),
                InkWell(
                  onTap: () => Navigator.pop(ctx, (0, 0)),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    child: Row(
                      children: [
                        const Icon(Icons.clear_rounded,
                            color: AppTheme.danger, size: 17),
                        const SizedBox(width: 10),
                        const Text('Clear time signature',
                            style: TextStyle(
                                color: AppTheme.danger,
                                fontSize: 13,
                                fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ),
              ] else
                const SizedBox(height: 20),
            ],
          ),
        ),
      );
    },
  );

  if (!context.mounted || result == null) return;
  final gp = context.read<LocatorGroupsProvider>();
  for (final name in locatorNames) {
    if (result.$1 == 0) {
      await gp.clearLocatorSig(name);
    } else {
      await gp.setLocatorSig(name, result.$1, result.$2);
    }
  }
}

// ── Shared locator row ────────────────────────────────────────────────────────

class _LocatorRow extends StatelessWidget {
  final AbletonLocator locator;
  final int locatorIndex;
  final List<AbletonLocator> locators;
  final int? selectedIdx;
  final double currentBeat;
  final bool isPlaying;
  final double bpm;
  final bool inGroup;
  final bool selecting;
  final Set<String> selected;
  final AbletonProvider ableton;
  final void Function(String) onLongPress;
  final void Function(String) onToggleSelect;

  const _LocatorRow({
    required this.locator,
    required this.locatorIndex,
    required this.locators,
    required this.selectedIdx,
    required this.currentBeat,
    required this.isPlaying,
    required this.bpm,
    required this.inGroup,
    required this.selecting,
    required this.selected,
    required this.ableton,
    required this.onLongPress,
    required this.onToggleSelect,
  });

  Future<void> _onLongPress(BuildContext context, String name, int i) async {
    final gp = context.read<LocatorGroupsProvider>();
    final alreadyGrouped = gp.isGrouped(name);
    final existingGroups = gp.groups;
    final hasSig = gp.getLocatorSig(name) != null;
    final sig = hasSig ? gp.getLocatorSig(name) : null;

    // Locator is inside a group → offer time sig, remove, move
    if (alreadyGrouped) {
      final action = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (ctx) => _LocatorSheet(
          name: name,
          children: [
            _SheetAction(
              icon: Icons.music_note_rounded,
              label: hasSig ? 'Change time signature' : 'Set time signature',
              badge: sig != null ? '${sig.$1}/${sig.$2}' : null,
              iconColor: hasSig ? AppTheme.accent : null,
              onTap: () => Navigator.pop(ctx, '__timesig__'),
            ),
            _SheetDivider(),
            _SheetAction(
              icon: Icons.folder_off_outlined,
              label: 'Remove from group',
              onTap: () => Navigator.pop(ctx, '__remove__'),
            ),
            if (existingGroups.length > 1) ...[
              _SheetDivider(),
              _SheetSectionLabel('Move to…'),
              ...existingGroups
                  .where((g) => !g.locatorNames.contains(name))
                  .map((g) => _SheetAction(
                        icon: Icons.folder_rounded,
                        label: g.name,
                        subtitle: '${g.locatorNames.length} songs',
                        onTap: () => Navigator.pop(ctx, g.name),
                      )),
            ],
          ],
        ),
      );
      if (!context.mounted) return;
      if (action == '__timesig__') {
        await showTimeSigDialog(context,
            headerLabel: name,
            locatorNames: [name],
            currentSig: sig);
      } else if (action == '__remove__') {
        await gp.removeFromGroup([name]);
      } else if (action != null) {
        await gp.addToGroup(action, [name]);
      }
      return;
    }

    // Locator is ungrouped → offer time sig, add to group, select mode
    if (existingGroups.isEmpty) {
      final action = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (ctx) => _LocatorSheet(
          name: name,
          children: [
            _SheetAction(
              icon: Icons.music_note_rounded,
              label: hasSig ? 'Change time signature' : 'Set time signature',
              badge: sig != null ? '${sig.$1}/${sig.$2}' : null,
              iconColor: hasSig ? AppTheme.accent : null,
              onTap: () => Navigator.pop(ctx, '__timesig__'),
            ),
            _SheetDivider(),
            _SheetAction(
              icon: Icons.check_box_outlined,
              label: 'Select mode',
              onTap: () => Navigator.pop(ctx, '__select__'),
            ),
          ],
        ),
      );
      if (!context.mounted) return;
      if (action == '__timesig__') {
        await showTimeSigDialog(context,
            headerLabel: name,
            locatorNames: [name],
            currentSig: sig);
      } else if (action == '__select__') {
        onLongPress(name);
      }
      return;
    }

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _LocatorSheet(
        name: name,
        children: [
          _SheetAction(
            icon: Icons.music_note_rounded,
            label: hasSig ? 'Change time signature' : 'Set time signature',
            badge: sig != null ? '${sig.$1}/${sig.$2}' : null,
            iconColor: hasSig ? AppTheme.accent : null,
            onTap: () => Navigator.pop(ctx, '__timesig__'),
          ),
          _SheetDivider(),
          _SheetSectionLabel('Add to group…'),
          ...existingGroups.map((g) => _SheetAction(
                icon: Icons.folder_rounded,
                label: g.name,
                subtitle: '${g.locatorNames.length} songs',
                onTap: () => Navigator.pop(ctx, g.name),
              )),
          _SheetDivider(),
          _SheetAction(
            icon: Icons.check_box_outlined,
            label: 'Select mode',
            onTap: () => Navigator.pop(ctx, '__select__'),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    if (action == '__timesig__') {
      await showTimeSigDialog(context,
          headerLabel: name,
          locatorNames: [name],
          currentSig: sig);
    } else if (action == '__select__') {
      onLongPress(name);
    } else if (action != null) {
      await gp.addToGroup(action, [name]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i = locatorIndex;
    final isActiveSelected = selectedIdx == i;
    final isNext = selectedIdx != null && i == selectedIdx! + 1;
    final nextPosition =
        i + 1 < locators.length ? locators[i + 1].position : null;
    final isChecked = selected.contains(locator.name);
    final timeSig = context.watch<LocatorGroupsProvider>().getLocatorSig(locator.name);

    return GestureDetector(
      onLongPress: selecting
          ? null
          : () => _onLongPress(context, locator.name, i),
      child: TapScale(
        onTap: selecting
            ? () => onToggleSelect(locator.name)
            : i >= 0
                ? () => ableton.selectLocator(i)
                : null,
        child: Padding(
          padding: EdgeInsets.only(left: inGroup ? 12 : 0),
          child: Stack(
            children: [
              _LocatorTile(
                locator: locator,
                index: i >= 0 ? i : 0,
                isSelected: isActiveSelected,
                isNext: isNext,
                currentBeat: currentBeat,
                nextPosition: nextPosition,
                isPlaying: isPlaying,
                bpm: bpm,
                dimmed: selecting && !isChecked,
                timeSig: timeSig,
              ),
              if (selecting)
                Positioned(
                  top: 10,
                  right: 18,
                  child: IgnorePointer(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: isChecked
                            ? AppTheme.accent
                            : Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isChecked
                              ? AppTheme.accent
                              : context.col.borderBright,
                          width: 2,
                        ),
                      ),
                      child: isChecked
                          ? const Icon(Icons.check,
                              size: 14, color: Colors.black)
                          : null,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Group header widget ───────────────────────────────────────────────────────

class _GroupHeader extends StatelessWidget {
  final LocatorGroup group;
  final LocatorGroupsProvider groups;
  final int slotIndex;
  final Future<String?> Function(String, {String initial}) onShowNameDialog;

  const _GroupHeader({
    required this.group,
    required this.groups,
    required this.slotIndex,
    required this.onShowNameDialog,
  });

  void _showMenu(BuildContext context) async {
    // Determine if all locators in the group share the same time sig
    final sigs = group.locatorNames
        .map((n) => groups.getLocatorSig(n))
        .toList();
    final allSame = sigs.isNotEmpty &&
        sigs.every((s) =>
            s != null && s.$1 == sigs.first!.$1 && s.$2 == sigs.first!.$2);
    final groupSig = allSame ? sigs.first : null;
    final anyHasSig = sigs.any((s) => s != null);

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _LocatorSheet(
        name: group.name,
        children: [
          _SheetAction(
            icon: Icons.music_note_rounded,
            label: anyHasSig
                ? 'Change time signature'
                : 'Set time signature',
            subtitle: 'Applies to all songs in group',
            badge: groupSig != null ? '${groupSig.$1}/${groupSig.$2}' : null,
            iconColor: anyHasSig ? AppTheme.accent : null,
            onTap: () => Navigator.pop(ctx, '__timesig__'),
          ),
          _SheetDivider(),
          _SheetAction(
            icon: Icons.drive_file_rename_outline_rounded,
            label: 'Rename group',
            onTap: () => Navigator.pop(ctx, 'rename'),
          ),
          _SheetDivider(),
          _SheetAction(
            icon: Icons.folder_off_outlined,
            label: 'Ungroup',
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
        ],
      ),
    );

    if (!context.mounted) return;
    if (action == '__timesig__') {
      await showTimeSigDialog(
        context,
        headerLabel: '${group.name} · ${group.locatorNames.length} songs',
        locatorNames: group.locatorNames,
        currentSig: groupSig,
      );
    } else if (action == 'rename') {
      final newName =
          await onShowNameDialog('Rename group', initial: group.name);
      if (newName != null && newName.trim().isNotEmpty) {
        await groups.renameGroup(group.name, newName.trim());
      }
    } else if (action == 'delete') {
      await groups.deleteGroup(group.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    const panelW = 52.0;

    return GestureDetector(
      onLongPress: () => _showMenu(context),
      child: TapScale(
        onTap: () => groups.toggleCollapsed(group.name),
        child: Container(
          height: 56,
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 2),
          decoration: BoxDecoration(
            color: AppTheme.accent.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppTheme.accent.withValues(alpha: 0.30),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left panel — folder icon
                Container(
                  width: panelW,
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.12),
                    border: Border(
                      right: BorderSide(
                        color: AppTheme.accent.withValues(alpha: 0.22),
                      ),
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.folder_rounded,
                      color: AppTheme.accent.withValues(alpha: 0.85),
                      size: 20,
                    ),
                  ),
                ),
                // Group name
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        group.name,
                        style: const TextStyle(
                          color: AppTheme.accent,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.1,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
                // Song count
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${group.locatorNames.length}',
                        style: TextStyle(
                          color: AppTheme.accent.withValues(alpha: 0.75),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ),
                // Collapse chevron
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Center(
                    child: AnimatedRotation(
                      turns: group.collapsed ? -0.25 : 0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      child: Icon(
                        Icons.expand_more_rounded,
                        color: AppTheme.accent.withValues(alpha: 0.6),
                        size: 20,
                      ),
                    ),
                  ),
                ),
                // Drag handle
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Center(
                    child: ReorderableDragStartListener(
                      index: slotIndex,
                      child: Icon(Icons.drag_indicator_rounded,
                          size: 18,
                          color: AppTheme.accent.withValues(alpha: 0.35)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Selection toolbar ─────────────────────────────────────────────────────────

class _SelectionBar extends StatelessWidget {
  final int count;
  final VoidCallback? onGroup;
  final VoidCallback onCancel;

  const _SelectionBar({
    required this.count,
    required this.onGroup,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    return Container(
      // Right inset clears the 116px sidebar (+10px margin) that overlays the
      // right edge, so the Group button isn't hidden behind it.
      padding: const EdgeInsets.fromLTRB(14, 8, 136, 8),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.08),
        border: Border(
          bottom: BorderSide(color: AppTheme.accent.withValues(alpha: 0.25)),
        ),
      ),
      child: Row(
        children: [
          TapScale(
            onTap: onCancel,
            child: Icon(Icons.close_rounded,
                size: 20, color: col.textSecondary),
          ),
          const SizedBox(width: 10),
          Text(
            '$count selected',
            style: TextStyle(
              color: col.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          if (onGroup != null)
            TapScale(
              onTap: onGroup,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: AppTheme.accent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.folder_rounded,
                        size: 15, color: Colors.black),
                    SizedBox(width: 6),
                    Text(
                      'Group',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Text(
              'Select 2+ to group',
              style: TextStyle(color: col.textMuted, fontSize: 12),
            ),
        ],
      ),
    );
  }
}

// ── Tile ──────────────────────────────────────────────────────────────────────

class _LocatorTile extends StatefulWidget {
  final AbletonLocator locator;
  final int index;
  final bool isSelected;
  final bool isNext;
  final double currentBeat;
  final double? nextPosition;
  final bool isPlaying;
  final double bpm;
  final bool dimmed;
  final (int, int)? timeSig;

  const _LocatorTile({
    required this.locator,
    required this.index,
    required this.isSelected,
    required this.isNext,
    required this.currentBeat,
    required this.nextPosition,
    required this.isPlaying,
    required this.bpm,
    this.dimmed = false,
    this.timeSig,
  });

  @override
  State<_LocatorTile> createState() => _LocatorTileState();
}

class _LocatorTileState extends State<_LocatorTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;

  static const List<Color> _palette = AppTheme.songColors;
  Color get _color => _palette[widget.index % _palette.length];

  double _span() {
    final next = widget.nextPosition;
    if (next == null) return 0;
    return (next - widget.locator.position).clamp(0, double.infinity);
  }

  double _toValue(double beat) {
    final s = _span();
    if (s <= 0) return 0;
    return ((beat - widget.locator.position) / s).clamp(0.0, 1.0);
  }

  Duration _spanDuration() {
    final s = _span();
    if (s <= 0 || widget.bpm <= 0) return const Duration(minutes: 5);
    return Duration(milliseconds: (s / widget.bpm * 60000).round());
  }

  void _syncAnim(_LocatorTile old) {
    final target = _toValue(widget.currentBeat);
    final shouldRun = widget.isPlaying && widget.isSelected;
    final trackChanged = widget.locator.position != old.locator.position ||
        widget.nextPosition != old.nextPosition;
    final newlySelected = widget.isSelected && !old.isSelected;
    final bpmChanged = widget.bpm != old.bpm;
    final beatDrift = widget.currentBeat != old.currentBeat &&
        (_anim.value - target).abs() > 0.03;

    if (shouldRun) {
      if (newlySelected || trackChanged || bpmChanged || beatDrift ||
          !_anim.isAnimating) {
        _anim.duration = _spanDuration();
        _anim.forward(from: target);
      }
    } else {
      _anim.stop();
      _anim.value = target;
    }
  }

  String _fmt(double beats) {
    final secs = (beats / widget.bpm * 60).abs().round();
    return '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: _spanDuration());
    _anim.value = _toValue(widget.currentBeat);
    if (widget.isPlaying && widget.isSelected) {
      _anim.forward(from: _anim.value);
    }
  }

  @override
  void didUpdateWidget(covariant _LocatorTile old) {
    super.didUpdateWidget(old);
    final changed = widget.isSelected != old.isSelected ||
        widget.isPlaying != old.isPlaying ||
        widget.currentBeat != old.currentBeat ||
        widget.locator.position != old.locator.position ||
        widget.nextPosition != old.nextPosition ||
        widget.bpm != old.bpm;
    if (changed) _syncAnim(old);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final badgeColor = widget.isSelected ? AppTheme.accent : _color;
    final showBar = widget.isSelected && widget.nextPosition != null;

    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) {
        final prog = showBar ? _anim.value : 0.0;
        final totalBeats = _span();
        final elapsedBeats = prog * totalBeats;
        final elapsed = showBar ? _fmt(elapsedBeats) : '';
        final remaining =
            showBar ? '-${_fmt((totalBeats - elapsedBeats).clamp(0, totalBeats))}' : '';

        return _buildTile(
            context, badgeColor, showBar, prog, elapsed, remaining);
      },
    );
  }

  Widget _buildTile(BuildContext context, Color badgeColor, bool showBar,
      double prog, String elapsed, String remaining) {
    final col = context.col;
    const panelW = 52.0;

    return AnimatedOpacity(
      opacity: widget.dimmed ? 0.4 : 1.0,
      duration: const Duration(milliseconds: 150),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 72,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: widget.isSelected
              ? AppTheme.accent.withValues(alpha: 0.06)
              : col.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: widget.isSelected
                ? AppTheme.accent.withValues(alpha: 0.5)
                : col.border,
            width: widget.isSelected ? 1.5 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: Stack(
            children: [
              // ── Left number panel ─────────────────────────────────────
              Positioned(
                left: 0, top: 0, bottom: 0,
                width: panelW,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: badgeColor
                        .withValues(alpha: widget.isSelected ? 0.15 : 0.08),
                    border: Border(
                      right: BorderSide(
                        color: badgeColor.withValues(
                            alpha: widget.isSelected ? 0.28 : 0.15),
                      ),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      (widget.index + 1).toString().padLeft(2, '0'),
                      style: TextStyle(
                        color: badgeColor,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ),

              // ── Background progress tint ──────────────────────────────
              if (showBar && prog > 0)
                Positioned(
                  left: panelW, top: 0, right: 0, bottom: 0,
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: prog,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            AppTheme.accent.withValues(alpha: 0.10),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // ── Main content row ──────────────────────────────────────
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                top: 0,
                left: panelW,
                right: 0,
                bottom: showBar ? 22 : 0,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.locator.name,
                            style: TextStyle(
                              color: col.textPrimary,
                              fontSize: 15,
                              fontWeight: widget.isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              letterSpacing: widget.isSelected ? -0.2 : 0,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Time signature badge
                        if (widget.timeSig != null) ...[
                          const SizedBox(width: 7),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: badgeColor.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                  color: badgeColor.withValues(alpha: 0.25)),
                            ),
                            child: Text(
                              '${widget.timeSig!.$1}/${widget.timeSig!.$2}',
                              style: TextStyle(
                                color: badgeColor.withValues(alpha: 0.85),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                          ),
                        ],
                        // NEXT badge
                        if (widget.isNext) ...[
                          const SizedBox(width: 7),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.accent.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                  color: AppTheme.accent.withValues(alpha: 0.38)),
                            ),
                            child: const Text(
                              'NEXT',
                              style: TextStyle(
                                color: AppTheme.accent,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),

              // ── Progress section ──────────────────────────────────────
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                bottom: showBar ? 0 : -22,
                left: panelW,
                right: 0,
                height: 22,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: showBar ? 1.0 : 0.0,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              elapsed,
                              style: const TextStyle(
                                color: AppTheme.accent,
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                            Text(
                              remaining,
                              style: TextStyle(
                                color: AppTheme.accent.withValues(alpha: 0.5),
                                fontSize: 9,
                                fontWeight: FontWeight.w500,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Stack(
                          children: [
                            Container(
                              height: 3,
                              decoration: BoxDecoration(
                                color: col.border,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: prog,
                              child: Container(
                                height: 3,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFFD97706),
                                      Color(0xFFF59E0B),
                                      Color(0xFFFFD060),
                                    ],
                                    stops: [0.0, 0.6, 1.0],
                                  ),
                                  borderRadius: BorderRadius.circular(2),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          AppTheme.accent.withValues(alpha: 0.9),
                                      blurRadius: 8,
                                      spreadRadius: 1,
                                    ),
                                    BoxShadow(
                                      color:
                                          AppTheme.accent.withValues(alpha: 0.4),
                                      blurRadius: 18,
                                      spreadRadius: 0,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────

class _DisconnectedState extends StatelessWidget {
  final AbletonProvider ableton;
  const _DisconnectedState({required this.ableton});

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/icon/app_icon.png',
              width: 96,
              height: 96,
              filterQuality: FilterQuality.high,
              cacheWidth: 384,
            ),
            const SizedBox(height: 20),
            const Text(
              'OkayNext',
              style: TextStyle(
                color: AppTheme.accent,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Not connected to Ableton',
              style: TextStyle(
                color: col.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Make sure the OkayNext script is active in Ableton.\n'
              'If connecting remotely, set the host IP in Settings.',
              style: TextStyle(
                  color: col.textSecondary, fontSize: 13, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
              icon: const Icon(Icons.settings_outlined, size: 16),
              label: const Text('Open Settings'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.accent,
                side: const BorderSide(color: AppTheme.accent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── App Bar ───────────────────────────────────────────────────────────────────

class _HomeAppBar extends StatelessWidget implements PreferredSizeWidget {
  final AbletonProvider ableton;
  final int locatorCount;
  final VoidCallback? onPerformance;
  final VoidCallback? onSettings;

  const _HomeAppBar({
    required this.ableton,
    required this.locatorCount,
    this.onPerformance,
    required this.onSettings,
  });

  @override
  Size get preferredSize => const Size.fromHeight(66);

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    final state = ableton.state;
    final isPlaying = ableton.isPlaying;
    final connected = ableton.isConnected;

    return Container(
      color: col.surfaceVariant,
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 64,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    // ── Logo mark ─────────────────────────────────────────
                    Image.asset(
                      'assets/icon/app_icon.png',
                      width: 34,
                      height: 34,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      cacheWidth: 136, // 34 × 4× for retina headroom
                    ),
                    const SizedBox(width: 10),

                    // ── Brand + project info ───────────────────────────────
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'OkayNext',
                            style: TextStyle(
                              color: AppTheme.accent,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                              height: 1.1,
                            ),
                          ),
                          if (state.projectName != null && state.projectName!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              state.projectName!,
                              style: TextStyle(
                                color: col.textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),

                    // ── Setlist selector ───────────────────────────────────
                    if (connected) ...[
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 180),
                        child: const SetlistSelector(),
                      ),
                      const SizedBox(width: 8),
                    ],

                    // ── Locator count ──────────────────────────────────────
                    if (connected && locatorCount > 0) ...[
                      Tooltip(
                        message: '$locatorCount locators',
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: AppTheme.accent.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Icon(Icons.queue_music_rounded,
                                  size: 15, color: AppTheme.accent),
                              const SizedBox(width: 6),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$locatorCount',
                                    style: const TextStyle(
                                      color: AppTheme.accent,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      height: 1.0,
                                      fontFeatures: [FontFeature.tabularFigures()],
                                    ),
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    locatorCount == 1 ? 'SONG' : 'SONGS',
                                    style: TextStyle(
                                      color: col.textMuted,
                                      fontSize: 7,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.8,
                                      height: 1.0,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],

                    // ── MIDI device ────────────────────────────────────────
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 150),
                      child: const MidiSelector(),
                    ),
                    const SizedBox(width: 8),

                    // ── Connection status ──────────────────────────────────
                    _AppBarConnPill(status: state.connectionStatus),

                    // ── Scene mode ─────────────────────────────────────────
                    if (connected) ...[
                      const SizedBox(width: 8),
                      _AppBarBtn(
                        icon: Icons.grid_view_rounded,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const SceneScreen()),
                        ),
                      ),
                    ],

                    // ── Performance mode ───────────────────────────────────
                    if (onPerformance != null) ...[
                      const SizedBox(width: 8),
                      _AppBarBtn(
                        icon: Icons.fullscreen_rounded,
                        accentColor: AppTheme.accent,
                        onTap: onPerformance!,
                      ),
                    ],

                    // ── Settings ───────────────────────────────────────────
                    const SizedBox(width: 6),
                    _AppBarBtn(
                      icon: Icons.settings_outlined,
                      onTap: onSettings!,
                    ),
                  ],
                ),
              ),
            ),

            // ── Bottom playing indicator ───────────────────────────────────
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              height: isPlaying ? 2 : 1,
              decoration: BoxDecoration(
                gradient: isPlaying
                    ? const LinearGradient(
                        colors: [
                          Colors.transparent,
                          AppTheme.accent,
                          AppTheme.accent,
                          Colors.transparent,
                        ],
                        stops: [0.0, 0.25, 0.75, 1.0],
                      )
                    : null,
                color: isPlaying ? null : col.border,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppBarConnPill extends StatelessWidget {
  final ConnectionStatus status;
  const _AppBarConnPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    final (color, label) = switch (status) {
      ConnectionStatus.connected => (AppTheme.success, 'Live'),
      ConnectionStatus.connecting => (AppTheme.warning, 'Sync…'),
      ConnectionStatus.disconnected => (col.textMuted, 'Offline'),
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: status == ConnectionStatus.connected
                  ? [BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 6)]
                  : null,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _AppBarBtn extends StatelessWidget {
  final IconData icon;
  final Color? accentColor;
  final VoidCallback onTap;
  const _AppBarBtn({required this.icon, required this.onTap, this.accentColor});

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    final iconColor = accentColor ?? col.textSecondary;

    return TapScale(
      onTap: onTap,
      pressedScale: 0.88,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: accentColor != null
              ? accentColor!.withValues(alpha: 0.10)
              : col.surfaceElevated,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: accentColor != null
                ? accentColor!.withValues(alpha: 0.30)
                : col.border,
          ),
        ),
        child: Icon(icon, size: 17, color: iconColor),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _NoLocatorsState extends StatelessWidget {
  final String? projectName;
  const _NoLocatorsState({this.projectName});

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/icon/app_icon.png',
              width: 80,
              height: 80,
              filterQuality: FilterQuality.high,
              cacheWidth: 320,
            ),
            const SizedBox(height: 20),
            Text(
              projectName != null ? '"$projectName"' : 'No locators found',
              style: TextStyle(
                  color: col.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Add locators in Ableton\'s arrangement view\n(Ctrl-click the ruler) to see them here.',
              style: TextStyle(
                  color: col.textSecondary, fontSize: 13, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Bottom-sheet helpers ──────────────────────────────────────────────────────

class _LocatorSheet extends StatelessWidget {
  final String name;
  final List<Widget> children;

  const _LocatorSheet({required this.name, required this.children});

  @override
  Widget build(BuildContext context) {
    final dcol = context.col;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Container(
          decoration: BoxDecoration(
            color: dcol.surfaceElevated,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: dcol.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 4),
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: dcol.borderBright,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              // Locator name header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
                child: Text(
                  name,
                  style: TextStyle(
                    color: dcol.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Actions
              ...children,
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final String? badge;
  final Color? iconColor;
  final VoidCallback onTap;

  const _SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.badge,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final dcol = context.col;
    final ic = iconColor ?? dcol.textSecondary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: ic == AppTheme.accent
                    ? AppTheme.accent.withValues(alpha: 0.1)
                    : dcol.surfaceVariant,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, color: ic, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      style: TextStyle(
                          color: dcol.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500)),
                  if (subtitle != null)
                    Text(subtitle!,
                        style:
                            TextStyle(color: dcol.textSecondary, fontSize: 11)),
                ],
              ),
            ),
            if (badge != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: AppTheme.accent.withValues(alpha: 0.3)),
                ),
                child: Text(badge!,
                    style: const TextStyle(
                        color: AppTheme.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
          ],
        ),
      ),
    );
  }
}

class _SheetDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Divider(
        height: 1,
        indent: 20,
        endIndent: 20,
        color: context.col.border,
      );
}

class _SheetSectionLabel extends StatelessWidget {
  final String label;
  const _SheetSectionLabel(this.label);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
        child: Text(label,
            style: TextStyle(
                color: context.col.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8)),
      );
}
