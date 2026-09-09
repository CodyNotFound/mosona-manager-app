import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_services.dart';
import '../../core/models/models.dart';
import '../../core/state/session.dart';
import '../../core/terminal/terminal.dart';
import '../../core/theme/mcolors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/widgets.dart';

/// Shared terminal session registry (contract imported by other features).


/// `/terminal` — terminal-enabled servers grouped by category, live sessions
/// on top (web parity §3.6). Rendered inside the bottom-nav shell.
class TerminalPage extends ConsumerStatefulWidget {
  const TerminalPage({super.key});

  @override
  ConsumerState<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends ConsumerState<TerminalPage> {
  List<TerminalServer>? _servers;
  String _query = '';
  int? _category;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    try {
      final list = await ref.read(apiProvider).terminalList();
      if (!mounted) return;
      setState(() => _servers = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _servers = const []);
      showApiError(context, e);
    }
  }

  void _open(TerminalServer ts) {
    final session = ref.read(terminalManagerProvider).create(
          server: ts,
          client: ref.read(apiClientProvider),
        );
    context.push('/session/${session.id}');
  }

  List<TerminalServer> get _filtered {
    final all = _servers ?? const <TerminalServer>[];
    final q = _query.trim().toLowerCase();
    return [
      for (final s in all)
        if ((_category == null || s.category == _category) &&
            (q.isEmpty ||
                s.name.toLowerCase().contains(q) ||
                (s.address ?? '').toLowerCase().contains(q)))
          s,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cats = ref.watch(teamDataProvider).categories;

    return Scaffold(
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  prefixText: '\$',
                  prefixStyle: monoStyle(context),
                  hintText: t(context, 'Filter by name or address', '按名称或地址过滤',
                      zhHk: '按名稱或地址篩選'),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _categoryBar(cats),
              if (_servers == null)
                ...List.generate(
                  4,
                  (i) => const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Skeleton(width: double.infinity, height: 64),
                  ),
                )
              else ...[
                _activeSessions(theme),
                ..._groupSections(_filtered, cats, theme),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- filter bar

  Widget _categoryBar(List<Category> cats) {
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _chip(
                  t(context, 'All', '全部', zhHk: '全部'),
                  _category == null,
                  () => setState(() => _category = null),
                ),
                // Web excludes the first (default) category from the filter bar.
                for (final c in cats.skip(1))
                  _chip(
                    c.name,
                    _category == c.id,
                    () => setState(() => _category = c.id),
                  ),
              ],
            ),
          ),
        ),
        IconButton(
          tooltip: t(context, 'Manage categories', '分类管理', zhHk: '管理分類'),
          icon: const Icon(Icons.category_outlined, size: 20),
          onPressed: _manageCategories,
        ),
        IconButton(
          tooltip: t(context, 'Add server', '添加服务器', zhHk: '新增伺服器'),
          icon: const Icon(Icons.add, size: 22),
          onPressed: () => context.push('/server-form'),
        ),
      ],
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          visualDensity: VisualDensity.compact,
          onSelected: (_) => onTap(),
        ),
      );

  Future<void> _manageCategories() => showMSheet(
        context: context,
        title: t(context, 'Categories', '分类管理', zhHk: '管理分類'),
        child: const _CategoryManageSheet(),
      );

  // -------------------------------------------------------- active sessions

  Widget _activeSessions(ThemeData theme) {
    final mgr = ref.watch(terminalManagerProvider);
    return AnimatedBuilder(
      animation: mgr,
      builder: (context, _) {
        final sessions = mgr.list;
        if (sessions.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 8),
              child: Text(
                t(context, 'Active sessions', '活动会话', zhHk: '進行中的工作階段'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            for (final s in sessions)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: MCard(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  onTap: () => context.push('/session/${s.id}'),
                  child: Row(
                    children: [
                      OsIcon(os: s.server.os, size: 26),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          s.server.name,
                          style: monoStyle(context),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: t(context, 'Close', '关闭', zhHk: '關閉'),
                        onPressed: () => mgr.close(s.id),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------- groups

  List<Widget> _groupSections(
    List<TerminalServer> items,
    List<Category> cats,
    ThemeData theme,
  ) {
    if (items.isEmpty && cats.isEmpty) {
      final filtering = _query.trim().isNotEmpty || _category != null;
      return [
        EmptyState(
          icon: Icons.terminal_outlined,
          text: filtering
              ? t(context, 'No matching servers', '没有匹配的服务器', zhHk: '沒有符合的伺服器')
              : t(context, 'No terminal-enabled servers', '暂无支持终端的服务器',
                  zhHk: '暫無支援終端機的伺服器'),
        ),
      ];
    }

    final names = {for (final c in cats) c.id: c.name};
    final groups = <int, List<TerminalServer>>{};
    for (final s in items) {
      groups.putIfAbsent(s.category, () => []).add(s);
    }

    // Web: unfiltered view walks every category (empty non-default ones show
    // an explicit "No servers in this category." note, empty default is
    // hidden); a selected category renders on its own with the same note.
    final visibleIds = _category != null
        ? [_category!]
        : [
            ...cats.map((c) => c.id),
            ...groups.keys.where((id) => !names.containsKey(id)),
          ];

    final widgets = <Widget>[];
    var rendered = false;
    for (final id in visibleIds) {
      final list = groups[id] ?? const <TerminalServer>[];
      final isDefault =
          names.containsKey(id) && (names[id] ?? '').trim().toLowerCase() == 'default';
      if (list.isEmpty && isDefault && _category == null) continue;
      rendered = true;
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(
          names[id] ?? t(context, 'Uncategorized', '未分类', zhHk: '未分類'),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ));
      if (list.isEmpty) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            t(context, 'No servers in this category.', '该分类下暂无服务器。', zhHk: '該分類下暫無伺服器。'),
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        ));
        continue;
      }
      for (var i = 0; i < list.length; i++) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: FadeSlideIn(
            delay: 60 * i,
            child: _serverCard(list[i], theme),
          ),
        ));
      }
    }
    if (!rendered) {
      return [
        EmptyState(
          icon: Icons.terminal_outlined,
          text: _query.trim().isNotEmpty || _category != null
              ? t(context, 'No matching servers', '没有匹配的服务器', zhHk: '沒有符合的伺服器')
              : t(context, 'No terminal-enabled servers', '暂无支持终端的服务器',
                  zhHk: '暫無支援終端機的伺服器'),
        ),
      ];
    }
    return widgets;
  }

  Widget _serverCard(TerminalServer s, ThemeData theme) {
    final username = (s.username?.isNotEmpty ?? false) ? s.username! : '--';
    return MCard(
      onTap: () => _open(s),
      onLongPress: () => _showServerMenu(s),
      child: Row(
        children: [
          OsIcon(os: s.os, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.name,
                  style: monoStyle(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  username,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Pencil shortcut to the server edit form (web card.tsx).
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: t(context, 'Edit server', '编辑服务器', zhHk: '編輯伺服器'),
            icon: Icon(
              Icons.edit_outlined,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            onPressed: () => context.push('/server-form?id=${s.id}'),
          ),
          MBadge(
            color: MColors.link,
            child: Text(serverTypeLabel(s.type)),
          ),
        ],
      ),
    );
  }

  /// Long-press card menu (mobile stand-in for the web context menu):
  /// edit server / move to category. Web's delete entry is a stub on both sides.
  void _showServerMenu(TerminalServer s) {
    showMSheet(
      context: context,
      title: s.name,
      child: Builder(
        builder: (sheetContext) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(t(context, 'Edit', '编辑', zhHk: '編輯')),
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.push('/server-form?id=${s.id}');
              },
            ),
            ListTile(
              leading: const Icon(Icons.label_outline),
              title: Text(t(context, 'Move to category', '移动到分类', zhHk: '移動至分類')),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _showMoveCategory(s);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showMoveCategory(TerminalServer s) {
    showMSheet(
      context: context,
      title: t(context, 'Move to category', '移动到分类', zhHk: '移動至分類'),
      child: _MoveCategorySheet(serverId: s.id, current: s.category, onChanged: _load),
    );
  }
}

// ------------------------------------------------------------ category sheet

/// Category management sheet: add / rename / delete / up-down sort
/// (mobile parity of the web drag-sort dialog).
class _CategoryManageSheet extends ConsumerStatefulWidget {
  const _CategoryManageSheet();

  @override
  ConsumerState<_CategoryManageSheet> createState() =>
      _CategoryManageSheetState();
}

class _CategoryManageSheetState extends ConsumerState<_CategoryManageSheet> {
  final _addCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _addCtrl.dispose();
    super.dispose();
  }

  List<Category> get _cats => ref.watch(teamDataProvider).categories;

  Future<void> _run(Future<void> Function() op) async {
    setState(() => _busy = true);
    try {
      await op();
      await ref.read(teamDataProvider.notifier).refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final name = _addCtrl.text.trim();
    if (name.isEmpty) return;
    _addCtrl.clear();
    await _run(() => ref.read(apiProvider).categoryCreate(name));
  }

  Future<void> _rename(Category c) async {
    final ctrl = TextEditingController(text: c.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t(context, 'Rename category', '重命名分类', zhHk: '重新命名分類')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(isDense: true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t(context, 'Cancel', '取消', zhHk: '取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(ctrl.text.trim()),
            child: Text(t(context, 'Save', '保存', zhHk: '儲存')),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (!mounted || name == null || name.isEmpty || name == c.name) return;
    await _run(() => ref.read(apiProvider).categoryUpdate(c.id, name));
  }

  Future<void> _delete(Category c) async {
    final ok = await confirmDialog(
      context,
      title: t(context, 'Delete category', '删除分类', zhHk: '刪除分類'),
      message: t(
        context,
        'Delete "${c.name}"? Servers in it will become uncategorized.',
        '删除“${c.name}”？其中的服务器将变为未分类。',
        zhHk: '刪除「${c.name}」嗎？其中的伺服器將變為未分類。',
      ),
      danger: true,
    );
    if (!mounted || !ok) return;
    await _run(() => ref.read(apiProvider).categoryDelete(c.id));
  }

  void _move(int index, int delta) {
    final ids = _cats.map((c) => c.id).toList();
    final j = index + delta;
    if (j < 0 || j >= ids.length) return;
    final tmp = ids[index];
    ids[index] = ids[j];
    ids[j] = tmp;
    _run(() => ref.read(apiProvider).categorySort(ids));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cats = _cats;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _addCtrl,
                enabled: !_busy,
                onSubmitted: (_) => _add(),
                decoration: InputDecoration(
                  hintText: t(context, 'New category name', '新分类名称', zhHk: '新分類名稱'),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              tooltip: t(context, 'Add', '新增', zhHk: '新增'),
              onPressed: _busy ? null : _add,
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < cats.length; i++)
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    cats[i].name,
                    style: const TextStyle(fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.arrow_upward, size: 18),
                tooltip: t(context, 'Move up', '上移', zhHk: '上移'),
                onPressed: _busy || i == 0 ? null : () => _move(i, -1),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.arrow_downward, size: 18),
                tooltip: t(context, 'Move down', '下移', zhHk: '下移'),
                onPressed:
                    _busy || i == cats.length - 1 ? null : () => _move(i, 1),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.edit_outlined,
                    size: 18, color: theme.colorScheme.onSurfaceVariant),
                tooltip: t(context, 'Rename', '重命名', zhHk: '重新命名'),
                onPressed: _busy ? null : () => _rename(cats[i]),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: MColors.offline),
                tooltip: t(context, 'Delete', '删除', zhHk: '刪除'),
                onPressed: _busy ? null : () => _delete(cats[i]),
              ),
            ],
          ),
      ],
    );
  }
}

// ------------------------------------------------------- move category sheet

/// Move one server to another category (mobile parity of the web EditCategory
/// dialog): pick an existing category or create a new one in place.
class _MoveCategorySheet extends ConsumerStatefulWidget {
  const _MoveCategorySheet({
    required this.serverId,
    required this.current,
    this.onChanged,
  });

  final int serverId;
  final int current;

  /// Invoked after a successful move (e.g. reload the terminal list).
  final VoidCallback? onChanged;

  @override
  ConsumerState<_MoveCategorySheet> createState() => _MoveCategorySheetState();
}

class _MoveCategorySheetState extends ConsumerState<_MoveCategorySheet> {
  final _addCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _addCtrl.dispose();
    super.dispose();
  }

  Future<void> _set(int categoryId) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).serverSetCategory(widget.serverId, categoryId);
      if (!mounted) return;
      Navigator.of(context).pop();
      toastSuccess(context);
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createAndSet() async {
    final name = _addCtrl.text.trim();
    if (name.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).categoryCreate(name);
      await ref.read(teamDataProvider.notifier).refresh();
      if (!mounted) return;
      Category? created;
      for (final c in ref.read(teamDataProvider).categories) {
        if (c.name == name) {
          created = c;
          break;
        }
      }
      if (created == null) {
        Navigator.of(context).pop();
        toastSuccess(context);
        widget.onChanged?.call();
        return;
      }
      await ref.read(apiProvider).serverSetCategory(widget.serverId, created.id);
      if (!mounted) return;
      Navigator.of(context).pop();
      toastSuccess(context);
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(teamDataProvider).categories;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          leading: const Icon(Icons.label_outline, size: 20),
          title: Text(t(context, 'Default (no category)', '默认（未分组）', zhHk: '預設（未分組）'),
              style: const TextStyle(fontSize: 14)),
          trailing:
              widget.current == 0 ? Icon(Icons.check, size: 18, color: MColors.online) : null,
          onTap: _busy ? null : () => _set(0),
        ),
        for (final c in cats)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            leading: const Icon(Icons.folder_outlined, size: 20),
            title: Text(c.name, style: const TextStyle(fontSize: 14)),
            trailing: c.id == widget.current
                ? Icon(Icons.check, size: 18, color: MColors.online)
                : null,
            onTap: _busy ? null : () => _set(c.id),
          ),
        const Divider(height: 24),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _addCtrl,
                enabled: !_busy,
                onSubmitted: (_) => _createAndSet(),
                decoration: InputDecoration(
                  labelText: t(context, 'New category', '新增分类', zhHk: '新增分類'),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _busy ? null : _createAndSet,
              icon: const Icon(Icons.add),
              tooltip: t(context, 'Create & move', '创建并移动', zhHk: '建立並移動'),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            t(context, 'Create a category and move this server into it.',
                '创建分类并将该服务器移入。', zhHk: '建立分類並將該伺服器移入。'),
            style: TextStyle(fontSize: 11, color: muted),
          ),
        ),
      ],
    );
  }
}
