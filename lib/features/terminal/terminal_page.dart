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
final terminalManagerProvider = Provider<TerminalManager>((ref) {
  final m = TerminalManager();
  ref.onDispose(m.dispose);
  return m;
});

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
                  hintText: t(context, 'Filter by name or address', '按名称或地址过滤'),
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
                  t(context, 'All', '全部'),
                  _category == null,
                  () => setState(() => _category = null),
                ),
                for (final c in cats)
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
          tooltip: t(context, 'Manage categories', '分类管理'),
          icon: const Icon(Icons.category_outlined, size: 20),
          onPressed: _manageCategories,
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
        title: t(context, 'Categories', '分类管理'),
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
                t(context, 'Active sessions', '活动会话'),
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
                        tooltip: t(context, 'Close', '关闭'),
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
    if (items.isEmpty) {
      final filtering = _query.trim().isNotEmpty || _category != null;
      return [
        EmptyState(
          icon: Icons.terminal_outlined,
          text: filtering
              ? t(context, 'No matching servers', '没有匹配的服务器')
              : t(context, 'No terminal-enabled servers', '暂无支持终端的服务器'),
        ),
      ];
    }

    final names = {for (final c in cats) c.id: c.name};
    final groups = <int, List<TerminalServer>>{};
    for (final s in items) {
      groups.putIfAbsent(s.category, () => []).add(s);
    }
    final ordered = [
      ...cats.map((c) => c.id).where(groups.containsKey),
      ...groups.keys.where((id) => !names.containsKey(id)),
    ];

    final widgets = <Widget>[];
    for (final id in ordered) {
      final list = groups[id]!;
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(
          names[id] ?? t(context, 'Uncategorized', '未分类'),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ));
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
    return widgets;
  }

  Widget _serverCard(TerminalServer s, ThemeData theme) {
    final username = (s.username?.isNotEmpty ?? false) ? s.username! : '--';
    return MCard(
      onTap: () => _open(s),
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
          MBadge(
            color: MColors.link,
            child: Text(serverTypeLabel(s.type)),
          ),
        ],
      ),
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
        title: Text(t(context, 'Rename category', '重命名分类')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(isDense: true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t(context, 'Cancel', '取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(ctrl.text.trim()),
            child: Text(t(context, 'Save', '保存')),
          ),
        ],
      ),
    );
    if (!mounted || name == null || name.isEmpty || name == c.name) return;
    await _run(() => ref.read(apiProvider).categoryUpdate(c.id, name));
  }

  Future<void> _delete(Category c) async {
    final ok = await confirmDialog(
      context,
      title: t(context, 'Delete category', '删除分类'),
      message: t(
        context,
        'Delete "${c.name}"? Servers in it will become uncategorized.',
        '删除“${c.name}”？其中的服务器将变为未分类。',
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
                  hintText: t(context, 'New category name', '新分类名称'),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              tooltip: t(context, 'Add', '新增'),
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
                tooltip: t(context, 'Move up', '上移'),
                onPressed: _busy || i == 0 ? null : () => _move(i, -1),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.arrow_downward, size: 18),
                tooltip: t(context, 'Move down', '下移'),
                onPressed:
                    _busy || i == cats.length - 1 ? null : () => _move(i, 1),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.edit_outlined,
                    size: 18, color: theme.colorScheme.onSurfaceVariant),
                tooltip: t(context, 'Rename', '重命名'),
                onPressed: _busy ? null : () => _rename(cats[i]),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: MColors.offline),
                tooltip: t(context, 'Delete', '删除'),
                onPressed: _busy ? null : () => _delete(cats[i]),
              ),
            ],
          ),
      ],
    );
  }
}
