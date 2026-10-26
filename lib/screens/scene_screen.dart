import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/ableton_provider.dart';
import '../providers/locator_groups_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/tap_scale.dart';

/// Scene mode: big tiles, each assigned to a setlist. Tapping a tile switches
/// to its setlist. Keys 1–9 activate scenes, Esc goes back.
class SceneScreen extends StatefulWidget {
  const SceneScreen({super.key});

  @override
  State<SceneScreen> createState() => _SceneScreenState();
}

class _SceneScreenState extends State<SceneScreen> {
  final FocusNode _focus = FocusNode(debugLabel: 'SceneScreen');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    const digits = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9,
    ];
    const pad = [
      LogicalKeyboardKey.numpad1,
      LogicalKeyboardKey.numpad2,
      LogicalKeyboardKey.numpad3,
      LogicalKeyboardKey.numpad4,
      LogicalKeyboardKey.numpad5,
      LogicalKeyboardKey.numpad6,
      LogicalKeyboardKey.numpad7,
      LogicalKeyboardKey.numpad8,
      LogicalKeyboardKey.numpad9,
    ];
    var i = digits.indexOf(key);
    if (i == -1) i = pad.indexOf(key);
    final count = context.read<LocatorGroupsProvider>().scenes.length;
    if (i != -1 && i < count) {
      _activate(i);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _activate(int i) async {
    final groups = context.read<LocatorGroupsProvider>();
    final ableton = context.read<AbletonProvider>();
    if (groups.setlistForScene(i) == null) {
      await _edit(i);
      return;
    }
    if (groups.isSceneActive(i)) return;
    await groups.activateScene(i);
    ableton.selectStartOfSetlist();
  }

  Future<void> _edit(int i) async {
    final groups = context.read<LocatorGroupsProvider>();
    final ableton = context.read<AbletonProvider>();
    final allNames = ableton.state.locators.map((l) => l.name).toList();
    final r = await showDialog<_SceneEdit>(
      context: context,
      builder: (_) => _SceneEditDialog(
        index: i,
        scene: groups.scenes[i],
        setlists: groups.setlists,
        songCount: (id) => groups.songCount(id, allNames),
        canRemove: groups.scenes.length > 1,
      ),
    );
    if (r == null) return;
    if (r.remove) {
      await groups.removeScene(i);
      return;
    }
    await groups.renameScene(i, r.name);
    await groups.assignScene(i, r.setlistId);
  }

  @override
  Widget build(BuildContext context) {
    final groups = context.watch<LocatorGroupsProvider>();
    final ableton = context.read<AbletonProvider>();
    final allNames = ableton.state.locators.map((l) => l.name).toList();
    final col = context.col;
    final scenes = groups.scenes;

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: col.background,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Top bar ──────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 16, 6),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      color: col.textSecondary,
                      tooltip: 'Back',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 4),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'SCENES',
                          style: TextStyle(
                            color: AppTheme.accent,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.6,
                          ),
                        ),
                        Text(
                          'Now: ${groups.activeSetlistName}',
                          style:
                              TextStyle(color: col.textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: scenes.length >= LocatorGroupsProvider.maxScenes
                          ? null
                          : groups.addScene,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add scene'),
                      style: TextButton.styleFrom(
                          foregroundColor: AppTheme.accent),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: col.border),

              // ── Tiles ────────────────────────────────────────────────────
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 300,
                    mainAxisExtent: 160,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                  ),
                  itemCount: scenes.length,
                  itemBuilder: (_, i) {
                    final list = groups.setlistForScene(i);
                    return _SceneTile(
                      index: i,
                      scene: scenes[i],
                      setlistName: list?.name,
                      songCount:
                          list == null ? null : groups.songCount(list.id, allNames),
                      active: groups.isSceneActive(i),
                      onTap: () => _activate(i),
                      onEdit: () => _edit(i),
                    );
                  },
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Text(
                  'Tap a scene to switch setlist  ·  keys 1–9  ·  ✎ to assign',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: col.textMuted, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SceneTile extends StatelessWidget {
  final int index;
  final SceneSlot scene;
  final String? setlistName;
  final int? songCount;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  const _SceneTile({
    required this.index,
    required this.scene,
    required this.setlistName,
    required this.songCount,
    required this.active,
    required this.onTap,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    final assigned = setlistName != null;
    final color = AppTheme.songColors[index % AppTheme.songColors.length];

    return TapScale(
      onTap: onTap,
      pressedScale: 0.97,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              (active ? AppTheme.accent : color)
                  .withValues(alpha: active ? 0.22 : assigned ? 0.1 : 0.04),
              col.surfaceVariant,
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active
                ? AppTheme.accent
                : assigned
                    ? color.withValues(alpha: 0.35)
                    : col.border,
            width: active ? 2 : 1,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                      color: AppTheme.accent.withValues(alpha: 0.25),
                      blurRadius: 22),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: active
                        ? AppTheme.accent
                        : assigned
                            ? color
                            : col.textMuted,
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                const Spacer(),
                if (active)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.accent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'ACTIVE',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                IconButton(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_rounded, size: 16),
                  color: col.textMuted,
                  tooltip: 'Assign setlist',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const Spacer(),
            Text(
              scene.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: col.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            if (assigned)
              Row(
                children: [
                  Icon(Icons.library_music_rounded,
                      size: 13,
                      color: active ? AppTheme.accent : col.textSecondary),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      '$setlistName  ·  $songCount songs',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(color: col.textSecondary, fontSize: 12),
                    ),
                  ),
                ],
              )
            else
              Text(
                'Tap to assign a setlist',
                style: TextStyle(
                  color: col.textMuted,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SceneEdit {
  final String name;
  final String? setlistId;
  final bool remove;
  const _SceneEdit(this.name, this.setlistId, {this.remove = false});
}

class _SceneEditDialog extends StatefulWidget {
  final int index;
  final SceneSlot scene;
  final List<SetlistInfo> setlists;
  final int Function(String id) songCount;
  final bool canRemove;

  const _SceneEditDialog({
    required this.index,
    required this.scene,
    required this.setlists,
    required this.songCount,
    required this.canRemove,
  });

  @override
  State<_SceneEditDialog> createState() => _SceneEditDialogState();
}

class _SceneEditDialogState extends State<_SceneEditDialog> {
  late final TextEditingController _name;
  String? _setlistId;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.scene.name);
    _setlistId = widget.scene.setlistId;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    Navigator.pop(
      context,
      _SceneEdit(name.isEmpty ? 'Scene ${widget.index + 1}' : name, _setlistId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    return AlertDialog(
      backgroundColor: col.surface,
      title: Text('Scene ${widget.index + 1}',
          style: TextStyle(color: col.textPrimary, fontSize: 16)),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              style: TextStyle(color: col.textPrimary),
              decoration: InputDecoration(
                labelText: 'Scene name',
                labelStyle: TextStyle(color: col.textMuted),
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 16),
            Text('SETLIST',
                style: TextStyle(
                  color: col.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                )),
            const SizedBox(height: 4),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: RadioGroup<String?>(
                  groupValue: _setlistId,
                  onChanged: (v) => setState(() => _setlistId = v),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final l in widget.setlists)
                        RadioListTile<String?>(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          activeColor: AppTheme.accent,
                          value: l.id,
                          title: Text(l.name,
                              style: TextStyle(
                                  color: col.textPrimary, fontSize: 14)),
                          subtitle: Text('${widget.songCount(l.id)} songs',
                              style: TextStyle(
                                  color: col.textMuted, fontSize: 11)),
                        ),
                      RadioListTile<String?>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        activeColor: AppTheme.accent,
                        value: null,
                        title: Text('None',
                            style: TextStyle(
                                color: col.textSecondary, fontSize: 14)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.canRemove)
          TextButton(
            onPressed: () =>
                Navigator.pop(context, const _SceneEdit('', null, remove: true)),
            style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
            child: const Text('Remove scene'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: col.textSecondary)),
        ),
        TextButton(
          onPressed: _save,
          child: const Text('Save', style: TextStyle(color: AppTheme.accent)),
        ),
      ],
    );
  }
}
