import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/models.dart';
import '../../core/sse/sse_client.dart'
    show MonitorConn, MonitorController, monitorProvider;
import '../../core/state/display_config.dart';
import '../../core/state/session.dart' show teamDataProvider;
import '../../core/theme/mcolors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/widgets.dart';
import 'widgets.dart';

/// Dashboard tab (web 3.4): overview stats, category filters, live SSE
/// server list grouped by category, add-server entry.
/// Lives inside the bottom-nav shell (the shell owns the AppBar).
class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  int _filter = -1; // -1 = All
  bool _expanded = false;
  bool _lostToastShown = false;

  late final ValueNotifier<MonitorConn> _conn =
      ref.read(monitorProvider.notifier).conn;

  @override
  void initState() {
    super.initState();
    _conn.addListener(_onConnChanged);
  }

  @override
  void dispose() {
    _conn.removeListener(_onConnChanged);
    super.dispose();
  }

  /// "Connection lost" toast once per transition into the lost state.
  void _onConnChanged() {
    final v = _conn.value;
    if (!mounted) return;
    if (v == MonitorConn.lost) {
      if (!_lostToastShown) {
        _lostToastShown = true;
        toastWarn(context, t(context, 'Connection lost', '连接已断开'));
      }
    } else {
      _lostToastShown = false;
    }
  }

  Future<void> _refresh() async {
    await ref.read(teamDataProvider.notifier).refresh();
    ref.read(monitorProvider.notifier).subscribe();
  }

  DisplayConfig _copyCfg(DisplayConfig c) {
    final n = DisplayConfig()
      ..defaultTimeFrame = c.defaultTimeFrame
      ..autoRefresh = c.autoRefresh
      ..monitorMode = c.monitorMode
      ..minMaxMode = c.minMaxMode
      ..monitorLayout = c.monitorLayout
      ..dashboardLayout = c.dashboardLayout
      ..showDetails = c.showDetails;
    return n;
  }

  void _setLayout(String layout) {
    final n = _copyCfg(ref.read(displayConfigProvider))..dashboardLayout = layout;
    ref.read(displayConfigProvider.notifier).update(n);
  }

  void _toggleDetails() {
    final n = _copyCfg(ref.read(displayConfigProvider))
      ..showDetails = !ref.read(displayConfigProvider).showDetails;
    ref.read(displayConfigProvider.notifier).update(n);
  }

  @override
  Widget build(BuildContext context) {
    final snap = ref.watch(monitorProvider);
    final team = ref.watch(teamDataProvider);
    final cfg = ref.watch(displayConfigProvider);
    final cats = [...team.categories]..sort((a, b) => a.sort.compareTo(b.sort));
    final grid = cfg.dashboardLayout != 'list';

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'dashboard-add-server',
        onPressed: () => context.push('/server-form'),
        icon: const Icon(Icons.add),
        label: Text(t(context, 'Add Server', '添加服务器')),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: PageHeader(
                    title: t(context, 'Dashboard', '概览'),
                    actions: [_connBadge()],
                  ),
                ),
              ),
              if (snap == null)
                _conn.value == MonitorConn.connecting
                    ? SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: _skeletonList(grid),
                        ),
                      )
                    : SliverFillRemaining(
                        hasScrollBody: false,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            EmptyState(
                              text: t(context, 'Connection lost', '连接已断开'),
                              icon: Icons.wifi_off_outlined,
                            ),
                            TextButton(
                              onPressed: _refresh,
                              child: Text(t(context, 'Retry', '重试')),
                            ),
                          ],
                        ),
                      )
              else ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: _stats(context, snap),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: _filterBar(context, cats, cfg),
                  ),
                ),
                ..._groupSlivers(context, snap, cats, grid, cfg.showDetails),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 88)),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- conn

  Widget _connBadge() {
    return ValueListenableBuilder<MonitorConn>(
      valueListenable: _conn,
      builder: (context, v, _) {
        final (label, color) = switch (v) {
          MonitorConn.live => (t(context, 'Live', '实时'), MColors.online),
          MonitorConn.connecting =>
            (t(context, 'Snapshot', '快照'), MColors.warning),
          MonitorConn.lost => (t(context, 'Lost', '断开'), MColors.offline),
        };
        return MBadge(
          small: true,
          color: color,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 4),
              Text(label),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------- stats

  Widget _stats(BuildContext context, MonitorSnapshot snap) {
    final servers = snap.servers;
    final online =
        servers.where((s) => MonitorController.isOnline(snap, s.id)).toList();
    final sts = [
      for (final s in online)
        if (snap.status[s.id] != null) snap.status[s.id]!,
    ];

    var avgCpu = 0.0;
    var avgMem = 0.0;
    var tx = 0.0;
    var rx = 0.0;
    var storage = 0.0;
    var memTotal = 0.0;
    var bw = 0.0;
    var cores = 0;
    if (sts.isNotEmpty) {
      for (final st in sts) {
        avgCpu += st.cpu;
        avgMem += st.memPercent;
        tx += st.txKibS;
        rx += st.rxKibS;
        memTotal += st.memTotalMb;
        bw += st.rxTotalMb + st.txTotalMb;
        final disks = st.disks;
        if (disks != null && disks.isNotEmpty) storage += disks.first.totalGb;
      }
      avgCpu /= sts.length;
      avgMem /= sts.length;
    }
    for (final s in online) {
      cores += (s.coreT ?? s.coreC) ?? 0;
    }

    Widget tile({
      required String label,
      required String value,
      required IconData icon,
      Color? color,
      String? subtitle,
    }) =>
        StatTile(
          label: label,
          value: value,
          icon: icon,
          color: color,
          subtitle: subtitle,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _grid2([
          tile(
            label: t(context, 'Servers', '服务器'),
            value: '${online.length}/${servers.length}',
            icon: Icons.dns_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          tile(
            label: t(context, 'Avg CPU', '平均 CPU'),
            value: '${avgCpu.toStringAsFixed(1)}%',
            icon: Icons.memory_outlined,
            color: MColors.chartBlue2,
          ),
          tile(
            label: t(context, 'Avg Memory', '平均内存'),
            value: '${avgMem.toStringAsFixed(1)}%',
            icon: Icons.storage_outlined,
            color: MColors.chartGreen2,
          ),
          tile(
            label: t(context, 'Traffic', '网络流量'),
            value: '↑ ${netRate(tx)}',
            subtitle: '↓ ${netRate(rx)}',
            icon: Icons.swap_vert,
            color: MColors.chartViolet2,
          ),
        ]),
        Center(
          child: TextButton.icon(
            onPressed: () => setState(() => _expanded = !_expanded),
            icon: Icon(_expanded
                ? Icons.keyboard_arrow_up
                : Icons.keyboard_arrow_down),
            label: Text(t(context, 'Totals', '合计')),
          ),
        ),
        if (_expanded)
          _grid2([
            tile(
              label: t(context, 'Total Storage', '总磁盘'),
              value: gb(storage),
              icon: Icons.save_outlined,
              color: MColors.chartYellow2,
            ),
            tile(
              label: t(context, 'Total Cores', '总核数'),
              value: compactNumber(cores),
              icon: Icons.developer_board_outlined,
              color: MColors.chartOrange2,
            ),
            tile(
              label: t(context, 'Total Memory', '总内存'),
              value: mbTotal(memTotal),
              icon: Icons.memory,
              color: MColors.chartBlue1,
            ),
            tile(
              label: t(context, 'Total Bandwidth', '总带宽'),
              value: mbTotal(bw),
              icon: Icons.speed_outlined,
              color: MColors.chartRed1,
            ),
          ]),
      ],
    );
  }

  Widget _grid2(List<Widget> children) => GridView(
        padding: EdgeInsets.zero,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          mainAxisExtent: 132,
        ),
        children: children,
      );

  // ---------------------------------------------------------------- filter

  Widget _filterBar(BuildContext context, List<Category> cats, DisplayConfig cfg) {
    final validFilter =
        _filter == -1 || cats.any((c) => c.id == _filter) ? _filter : -1;
    return SizedBox(
      height: 38,
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                FilterChip(
                  label: Text(t(context, 'All', '全部')),
                  selected: validFilter == -1,
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(() => _filter = -1),
                ),
                for (final c in cats) ...[
                  const SizedBox(width: 6),
                  FilterChip(
                    label: Text(c.name),
                    selected: validFilter == c.id,
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() => _filter = c.id),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: t(context, 'Manage categories', '管理分类'),
            icon: const Icon(Icons.category_outlined, size: 20),
            onPressed: () => showCategoryManageSheet(context, ref),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: t(context, 'Toggle layout', '切换布局'),
            icon: Icon(
              cfg.dashboardLayout == 'grid'
                  ? Icons.view_list_outlined
                  : Icons.grid_view_outlined,
              size: 20,
            ),
            onPressed: () => _setLayout(cfg.dashboardLayout == 'grid' ? 'list' : 'grid'),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: t(context, 'Show details', '显示详情'),
            icon: Icon(
              cfg.showDetails ? Icons.visibility : Icons.visibility_outlined,
              size: 20,
              color: cfg.showDetails ? MColors.link : null,
            ),
            onPressed: _toggleDetails,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- list

  List<Widget> _groupSlivers(
    BuildContext context,
    MonitorSnapshot snap,
    List<Category> cats,
    bool grid,
    bool showDetails,
  ) {
    final servers = snap.servers;
    if (servers.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
            child: Column(
              children: [
                EmptyState(
                  text: t(context, 'No servers yet', '暂无服务器'),
                  icon: Icons.dns_outlined,
                ),
                FilledButton.icon(
                  onPressed: () => context.push('/server-form'),
                  icon: const Icon(Icons.add),
                  label: Text(t(context, 'Add Server', '添加服务器')),
                ),
              ],
            ),
          ),
        ),
      ];
    }

    final filtered = _filter == -1
        ? servers
        : servers.where((s) => s.category == _filter).toList();
    if (filtered.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
            child: EmptyState(
              text: t(context, 'No servers in this category', '该分类下暂无服务器'),
              icon: Icons.folder_off_outlined,
            ),
          ),
        ),
      ];
    }

    final groups = <int, List<MonitorList>>{};
    for (final s in filtered) {
      groups.putIfAbsent(s.category, () => []).add(s);
    }
    for (final list in groups.values) {
      list.sort((a, b) => b.weight.compareTo(a.weight));
    }
    final catIds = cats.map((c) => c.id).toSet();
    final orderedIds = [
      ...cats.map((c) => c.id).where(groups.containsKey),
      ...groups.keys.where((id) => !catIds.contains(id)),
    ];
    final catNames = {for (final c in cats) c.id: c.name};

    return [
      for (final id in orderedIds) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
            child: Text(
              (id == 0 ? t(context, 'Default', '默认') : (catNames[id] ?? t(context, 'Default', '默认')))
                  .toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final list = groups[id]!;
                if (grid) {
                  final w = (constraints.maxWidth - 10) / 2;
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (var i = 0; i < list.length; i++)
                        SizedBox(
                          width: w,
                          child: FadeSlideIn(
                            delay: (i * 60).clamp(0, 600).toInt(),
                            child: ServerCard(
                              server: list[i],
                              snap: snap,
                              showDetails: showDetails,
                              onTap: () => context.push('/monitor/${list[i].id}'),
                              onMenu: () =>
                                  showServerMenu(context, ref, list[i], snap),
                            ),
                          ),
                        ),
                    ],
                  );
                }
                return Column(
                  children: [
                    for (var i = 0; i < list.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: FadeSlideIn(
                          delay: (i * 60).clamp(0, 600).toInt(),
                          child: ServerCard(
                            server: list[i],
                            snap: snap,
                            showDetails: showDetails,
                            onTap: () => context.push('/monitor/${list[i].id}'),
                            onMenu: () =>
                                showServerMenu(context, ref, list[i], snap),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    ];
  }

  // ---------------------------------------------------------------- skeleton

  Widget _skeletonList(bool grid) {
    Widget skeletonCard() => MCard(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Skeleton(width: 26, height: 26, radius: 8),
                  const SizedBox(width: 8),
                  const Skeleton(width: 90),
                  const Spacer(),
                  const Skeleton(width: 42, height: 18, radius: 999),
                ],
              ),
              const SizedBox(height: 14),
              const Skeleton(height: 4),
              const SizedBox(height: 8),
              const Skeleton(height: 4),
              const SizedBox(height: 14),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: const [
                  Skeleton(width: 56, height: 20, radius: 999),
                  Skeleton(width: 64, height: 20, radius: 999),
                ],
              ),
            ],
          ),
        );
    if (!grid) {
      return Column(
        children: [
          for (var i = 0; i < 4; i++) ...[
            skeletonCard(),
            const SizedBox(height: 10),
          ],
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = (constraints.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var i = 0; i < 4; i++)
              SizedBox(width: w, child: skeletonCard()),
          ],
        );
      },
    );
  }
}
