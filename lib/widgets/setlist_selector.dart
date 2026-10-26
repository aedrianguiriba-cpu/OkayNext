import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/ableton_provider.dart';
import '../providers/locator_groups_provider.dart';
import '../theme/app_theme.dart';

/// App-bar control for switching between, creating and managing setlists.
class SetlistSelector extends StatelessWidget {
  const SetlistSelector({super.key});

  static const _kNew = '__new__';
  static const _kEdit = '__edit__';
  static const _kRename = '__rename__';
  static const _kDuplicate = '__dup__';
  static const _kDelete = '__delete__';

  @override
  Widget build(BuildContext context) {
    final groups = context.watch<LocatorGroupsProvider>();
    final ableton = context.read<AbletonProvider>();
    final col = context.col;
    final allNames = ableton.state.locators.map((l) => l.name).toList();
    final lists = groups.setlists;

    final sceneActive = groups.activeSceneIndex != null;

    return PopupMenuButton<String>(
      tooltip: sceneActive
          ? '${groups.activeDisplayName} → ${groups.activeSetlistName}'
          : 'Setlists',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      onSelected: (v) => _onSelected(context, v),
      itemBuilder: (_) => [
        for (final l in lists)
          PopupMenuItem<String>(
            value: l.id,
            child: Row(
              children: [
                Icon(
                  l.id == groups.activeSetlistId
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 16,
                  color: l.id == groups.activeSetlistId
                      ? AppTheme.accent
                      : col.textMuted,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    l.name,
                    overflow: TextOverflow.ellipsis,
                    style: l.id == groups.activeSetlistId
                        ? const TextStyle(
                            color: AppTheme.accent, fontWeight: FontWeight.w700)
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${groups.songCount(l.id, allNames)} songs',
                  style: TextStyle(color: col.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: _kNew,
          child: _MenuRow(Icons.add_rounded, 'New setlist…'),
        ),
        const PopupMenuItem<String>(
          value: _kEdit,
          child: _MenuRow(Icons.checklist_rounded, 'Choose songs…'),
        ),
        const PopupMenuItem<String>(
          value: _kRename,
          child: _MenuRow(Icons.edit_rounded, 'Rename…'),
        ),
        const PopupMenuItem<String>(
          value: _kDuplicate,
          child: _MenuRow(Icons.copy_rounded, 'Duplicate…'),
        ),
        PopupMenuItem<String>(
          value: _kDelete,
          enabled: groups.canDeleteSetlist,
          child: _MenuRow(Icons.delete_outline_rounded, 'Delete',
              color: groups.canDeleteSetlist ? AppTheme.danger : null),
        ),
      ],
      child: Container(
        constraints: const BoxConstraints(minHeight: 34),
        padding: const EdgeInsets.only(left: 10, right: 4),
        decoration: BoxDecoration(
          color: col.surfaceElevated,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: col.border),
        ),
        child: Row(
          children: [
            Icon(
                sceneActive
                    ? Icons.grid_view_rounded
                    : Icons.library_music_rounded,
                size: 15,
                color: AppTheme.accent),
            const SizedBox(width: 6),
            Expanded(
              // Scene name (bold) · assigned setlist (muted), one line.
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: groups.activeDisplayName,
                      style: TextStyle(
                        color: col.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (sceneActive)
                      TextSpan(
                        text: '  ·  ${groups.activeSetlistName}',
                        style: TextStyle(
                          color: col.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.arrow_drop_down_rounded, size: 18, color: col.textMuted),
          ],
        ),
      ),
    );
  }

  Future<void> _onSelected(BuildContext context, String value) async {
    final groups = context.read<LocatorGroupsProvider>();
    final ableton = context.read<AbletonProvider>();
    final allNames = ableton.state.locators.map((l) => l.name).toList();
    final activeId = groups.activeSetlistId;

    switch (value) {
      case _kNew:
        final r = await showDialog<_EditorResult>(
          context: context,
          builder: (_) => _SetlistEditorDialog(
            title: 'New setlist',
            confirmLabel: 'Create',
            askName: true,
            initialName: '',
            allNames: allNames,
            initiallySelected: allNames.toSet(),
            groups: groups,
          ),
        );
        if (r == null) return;
        await groups.createSetlist(r.name, r.songs, allNames,
            keepFolders: r.keepFolders);
        ableton.selectStartOfSetlist();

      case _kEdit:
        final visible =
            allNames.where((n) => !groups.hiddenNames.contains(n)).toSet();
        final r = await showDialog<_EditorResult>(
          context: context,
          builder: (_) => _SetlistEditorDialog(
            title: 'Songs in "${groups.activeSetlistName}"',
            confirmLabel: 'Save',
            askName: false,
            initialName: groups.activeSetlistName,
            allNames: allNames,
            initiallySelected: visible,
            groups: groups,
          ),
        );
        if (r == null) return;
        await groups.setActiveSongs(r.songs, allNames);

      case _kRename:
        final name = await _askName(context, groups,
            title: 'Rename setlist',
            initial: groups.activeSetlistName,
            exceptId: activeId);
        if (name != null) await groups.renameSetlist(activeId, name);

      case _kDuplicate:
        final name = await _askName(context, groups,
            title: 'Duplicate setlist',
            initial: '${groups.activeSetlistName} copy');
        if (name == null) return;
        await groups.duplicateSetlist(activeId, name);
        ableton.selectStartOfSetlist();

      case _kDelete:
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: ctx.col.surface,
            title: Text('Delete "${groups.activeSetlistName}"?'),
            content: Text(
              'The setlist and its folders and order are removed. Your songs '
              'stay in Ableton and in other setlists.',
              style: TextStyle(color: ctx.col.textSecondary, height: 1.4),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style:
                      TextButton.styleFrom(foregroundColor: AppTheme.danger),
                  child: const Text('Delete')),
            ],
          ),
        );
        if (ok != true) return;
        await groups.deleteSetlist(activeId);
        ableton.selectStartOfSetlist();

      default: // a setlist id
        if (value == activeId) return;
        await groups.switchSetlist(value);
        ableton.selectStartOfSetlist();
    }
  }

  Future<String?> _askName(
    BuildContext context,
    LocatorGroupsProvider groups, {
    required String title,
    required String initial,
    String? exceptId,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => _SetlistEditorDialog.nameOnly(
        title: title,
        initialName: initial,
        groups: groups,
        exceptId: exceptId,
      ),
    ).then((r) => r);
  }
}

/// Switch-only setlist button (no create/edit/delete) for performance mode.
class SetlistSwitchButton extends StatelessWidget {
  const SetlistSwitchButton({super.key});

  @override
  Widget build(BuildContext context) {
    final groups = context.watch<LocatorGroupsProvider>();
    final ableton = context.read<AbletonProvider>();
    final col = context.col;
    final allNames = ableton.state.locators.map((l) => l.name).toList();
    final lists = groups.setlists;
    final multiple = lists.length > 1;

    return PopupMenuButton<String>(
      tooltip: 'Switch setlist',
      enabled: multiple,
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      onSelected: (id) async {
        if (id == groups.activeSetlistId) return;
        await groups.switchSetlist(id);
        ableton.selectStartOfSetlist();
      },
      itemBuilder: (_) => [
        for (final l in lists)
          PopupMenuItem<String>(
            value: l.id,
            height: 48,
            child: Row(
              children: [
                Icon(
                  l.id == groups.activeSetlistId
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 18,
                  color: l.id == groups.activeSetlistId
                      ? AppTheme.accent
                      : col.textMuted,
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    l.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: l.id == groups.activeSetlistId
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: l.id == groups.activeSetlistId
                          ? AppTheme.accent
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Text(
                  '${groups.songCount(l.id, allNames)} songs',
                  style: TextStyle(color: col.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppTheme.accent.withValues(alpha: multiple ? 0.1 : 0.04),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: AppTheme.accent.withValues(alpha: multiple ? 0.4 : 0.15)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.swap_horiz_rounded,
                size: 16,
                color: multiple ? AppTheme.accent : col.textMuted),
            const SizedBox(width: 5),
            Text(
              'SETLIST',
              style: TextStyle(
                color: multiple ? AppTheme.accent : col.textMuted,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  const _MenuRow(this.icon, this.label, {this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.col.textSecondary;
    return Row(
      children: [
        Icon(icon, size: 16, color: c),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: color)),
      ],
    );
  }
}

class _EditorResult {
  final String name;
  final Set<String> songs;
  final bool keepFolders;
  const _EditorResult(this.name, this.songs, {this.keepFolders = false});
}

/// One row of the picker: a folder with its songs, or a single loose song.
class _Entry {
  /// Folder name, or null for a loose song (then [songs] has exactly one).
  final String? folder;
  final List<String> songs;
  const _Entry(this.folder, this.songs);
}

/// Name field and/or checklist of the project's songs.
class _SetlistEditorDialog extends StatefulWidget {
  final String title;
  final String confirmLabel;
  final bool askName;
  final String initialName;
  final List<String> allNames;
  final Set<String> initiallySelected;
  final LocatorGroupsProvider groups;
  final String? exceptId;
  final bool nameOnly;

  const _SetlistEditorDialog({
    required this.title,
    required this.confirmLabel,
    required this.askName,
    required this.initialName,
    required this.allNames,
    required this.initiallySelected,
    required this.groups,
  })  : exceptId = null,
        nameOnly = false;

  const _SetlistEditorDialog.nameOnly({
    required this.title,
    required this.initialName,
    required this.groups,
    this.exceptId,
  })  : confirmLabel = 'OK',
        askName = true,
        allNames = const [],
        initiallySelected = const {},
        nameOnly = true;

  @override
  State<_SetlistEditorDialog> createState() => _SetlistEditorDialogState();
}

class _SetlistEditorDialogState extends State<_SetlistEditorDialog> {
  late final TextEditingController _name;
  late Set<String> _selected;
  String? _error;
  bool _keepFolders = true;
  List<_Entry> _entries = const [];

  bool get _hasFolders => _entries.any((e) => e.folder != null);

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName);
    _selected = Set.of(widget.initiallySelected);
    if (!widget.nameOnly) _buildEntries();
  }

  /// Lays the songs out the way the active setlist does: folders (with their
  /// songs) and loose songs in list order, then songs the active setlist has
  /// left out.
  void _buildEntries() {
    final g = widget.groups;
    final all = widget.allNames;
    final entries = <_Entry>[];
    final shown = <String>{};
    for (final slot in g.topSlots(all)) {
      if (slot.isGroup) {
        final grp = g.groups.where((x) => x.name == slot.id).firstOrNull;
        final members = grp == null
            ? <String>[]
            : grp.locatorNames.where(all.contains).toList();
        if (members.isEmpty) continue;
        entries.add(_Entry(slot.id, members));
        shown.addAll(members);
      } else if (all.contains(slot.id)) {
        entries.add(_Entry(null, [slot.id]));
        shown.add(slot.id);
      }
    }
    for (final n in all) {
      if (!shown.contains(n)) entries.add(_Entry(null, [n]));
    }
    _entries = entries;
  }

  void _toggleSong(String n, bool on) => setState(() {
        on ? _selected.add(n) : _selected.remove(n);
        _error = null;
      });

  void _toggleFolder(_Entry e, bool on) => setState(() {
        on ? _selected.addAll(e.songs) : _selected.removeAll(e.songs);
        _error = null;
      });

  Widget _folderTile(_Entry e) {
    final col = context.col;
    final count = e.songs.where(_selected.contains).length;
    final bool? value = count == 0
        ? false
        : count == e.songs.length
            ? true
            : null; // some selected
    return CheckboxListTile(
      dense: true,
      tristate: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      activeColor: AppTheme.accent,
      checkColor: Colors.black,
      value: value,
      title: Row(
        children: [
          const Icon(Icons.folder_rounded, size: 16, color: AppTheme.accent),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              e.folder!,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: col.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text('$count/${e.songs.length}',
              style: TextStyle(color: col.textMuted, fontSize: 11)),
        ],
      ),
      // Tapping a half-selected folder selects all of it.
      onChanged: (v) => _toggleFolder(e, v ?? true),
    );
  }

  Widget _songTile(String n, {required bool indented}) {
    final col = context.col;
    return Padding(
      padding: EdgeInsets.only(left: indented ? 28 : 0),
      child: CheckboxListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        activeColor: AppTheme.accent,
        checkColor: Colors.black,
        value: _selected.contains(n),
        title: Text(n,
            style: TextStyle(color: col.textPrimary, fontSize: 13)),
        onChanged: (v) => _toggleSong(n, v == true),
      ),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (widget.askName) {
      if (name.isEmpty) {
        setState(() => _error = 'Enter a name');
        return;
      }
      if (widget.groups.setlistNameTaken(name, exceptId: widget.exceptId)) {
        setState(() => _error = 'A setlist with that name already exists');
        return;
      }
    }
    if (!widget.nameOnly && _selected.isEmpty) {
      setState(() => _error = 'Pick at least one song');
      return;
    }
    if (widget.nameOnly) {
      Navigator.pop(context, name);
    } else {
      Navigator.pop(context,
          _EditorResult(name, _selected, keepFolders: _keepFolders && _hasFolders));
    }
  }

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    return AlertDialog(
      backgroundColor: col.surface,
      title: Text(widget.title,
          style: TextStyle(color: col.textPrimary, fontSize: 16)),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.askName)
              TextField(
                controller: _name,
                autofocus: true,
                style: TextStyle(color: col.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Setlist name…',
                  hintStyle: TextStyle(color: col.textMuted),
                  errorText: widget.nameOnly ? _error : null,
                ),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: (_) => widget.nameOnly ? _submit() : null,
              ),
            if (!widget.nameOnly) ...[
              if (widget.askName) const SizedBox(height: 14),
              Row(
                children: [
                  Text(
                    '${_selected.length} of ${widget.allNames.length} songs',
                    style: TextStyle(color: col.textSecondary, fontSize: 12),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () =>
                        setState(() => _selected = widget.allNames.toSet()),
                    child: const Text('All', style: TextStyle(fontSize: 12)),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _selected = {}),
                    child: const Text('None', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: widget.allNames.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text('Connect to Ableton to load songs.',
                              style: TextStyle(color: col.textMuted)),
                        )
                      : ListView(
                          shrinkWrap: true,
                          children: [
                            for (final e in _entries)
                              if (e.folder != null) ...[
                                _folderTile(e),
                                for (final n in e.songs)
                                  _songTile(n, indented: true),
                              ] else
                                _songTile(e.songs.first, indented: false),
                          ],
                        ),
                ),
              ),
              if (widget.askName && _hasFolders)
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: AppTheme.accent,
                  value: _keepFolders,
                  onChanged: (v) => setState(() => _keepFolders = v),
                  title: Text('Keep folders',
                      style: TextStyle(color: col.textPrimary, fontSize: 13)),
                  subtitle: Text(
                    'Carry the current folders and order into the new setlist',
                    style: TextStyle(color: col.textMuted, fontSize: 11),
                  ),
                ),
            ],
            if (_error != null && !widget.nameOnly) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: col.textSecondary)),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(widget.confirmLabel,
              style: const TextStyle(color: AppTheme.accent)),
        ),
      ],
    );
  }
}
