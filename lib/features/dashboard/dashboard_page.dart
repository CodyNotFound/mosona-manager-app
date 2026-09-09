import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/models.dart';
import '../../core/sse/sse_client.dart' show MonitorConn, monitorProvider;
import '../../core/state/display_config.dart';
import '../../core/state/session.dart'
    show MutationBus, mutationBusProvider, sessionProvider, teamDataProvider;
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

  /// Page-level heartbeat (web hook.ts:9,317-329): when no SSE frame arrives
  /// for 30s while live, warn the user and resubscribe after 5s.
  static const _staleTimeout = Duration(seconds: 30);
  static const _reconnectDelay = Duration(seconds: 5);
  Timer? _heartbeat;
  Timer? _reconnect;
  bool _stale = false;

  late final ValueNotifier<MonitorConn> _conn =
      ref.read(monitorProvider.notifier).conn;
  late final ValueNotifier<bool> _revoked =
      ref.read(monitorProvider.notifier).revoked;
  /// Captured in initState-time so dispose() can detach without touching ref.
  late final MutationBus _bus = ref.read(mutationBusProvider);

  @override
  void initState() {
    super.initState();
    _conn.addListener(_onConnChanged);
    _revoked.addListener(_onRevoked);
    // web hook.ts:365-370 — resubscribe SSE after any server mutation.
    _bus.addListener(_onServersMutated);
  }

  @override
  void dispose() {
    _bus.removeListener(_onServersMutated);
    _conn.removeListener(_onConnChanged);
    _revoked.removeListener(_onRevoked);
    _heartbeat?.cancel();
    _reconnect?.cancel();
    super.dispose();
  }

  /// Team access revoked mid-stream (web hook.ts:340-345): force re-login.
  void _onRevoked() {
    if (!_revoked.value || !mounted) return;
    ref.read(sessionProvider.notifier).logout();
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

  void _onServersMutated() {
    ref.read(monitorProvider.notifier).subscribe();
  }

  void _armHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer(_staleTimeout, _onStale);
  }

  void _onStale() {
    if (!mounted) return;
    if (_conn.value != MonitorConn.live) return;
    if (!_lostToastShown) {
      _lostToastShown = true;
      toastWarn(context, t(context, 'Connection lost', '连接已断开'));
    }
    if (!_stale) setState(() => _stale = true);
    _reconnect?.cancel();
    _reconnect = Timer(_reconnectDelay, () {
      if (mounted) ref.read(monitorProvider.notifier).subscribe();
    });
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

  /// web layout-btn.tsx:30-39 — grid -> list -> list2 -> grid cycle.
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
    // Reset the stale flag as soon as frames flow again.
    ref.listen<MonitorSnapshot?>(monitorProvider, (prev, next) {
      if (next != null) {
        _armHeartbeat();
        if (_stale || _lostToastShown) {
          setState(() {
            _stale = false;
            _lostToastShown = false;
          });
        }
      }
    });

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
                // wrap in a listener so a first-connection failure can leave
                // the skeleton state (the value is read at build time only)
                ListenableBuilder(
                  listenable: _conn,
                  builder: (context, _) => _conn.value == MonitorConn.connecting
                      ? SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: _skeletonPage(cats, cfg.dashboardLayout),
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
                ..._groupSlivers(context, snap, cats, cfg.dashboardLayout,
                    cfg.showDetails),
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
        final lost = _stale || v == MonitorConn.lost;
        final (label, color) = lost
            ? (t(context, 'Lost', '断开'), MColors.offline)
            : v == MonitorConn.live
                ? (t(context, 'Live', '实时'), MColors.online)
                : _conn.value == MonitorConn.connecting
                    ? (t(context, 'Connecting', '连接中'), MColors.warning)
                    : (t(context, 'Snapshot', '快照'), MColors.warning);
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

  /// Servers visible under the current category filter (web hook.ts:220-223).
  List<MonitorList> _visibleServers(MonitorSnapshot snap) => _filter == -1
      ? snap.servers
      : snap.servers.where((s) => s.category == _filter).toList();

  Widget _stats(BuildContext context, MonitorSnapshot snap) {
    final servers = _visibleServers(snap);
    final nowMs = snap.nowSec * 1000;

    // web hook.ts:210-247 — "with status" counts any server with a report
    // (online or stale), only the online ones contribute to the averages.
    var onlineCount = 0;
    var cpuAcc = 0.0;
    var memAcc = 0.0;
    var rxAcc = 0.0;
    var txAcc = 0.0;
    for (final s in servers) {
      final st = snap.status[s.id];
      if (st == null) continue;
      final live =
          st.time != null && nowMs - st.time!.millisecondsSinceEpoch < 5000;
      if (!live) continue;
      onlineCount++;
      cpuAcc += st.cpu;
      memAcc += st.memPercent;
      rxAcc += st.rxKibS;
      txAcc += st.txKibS;
    }
    // averages divide by ONLINE servers only (web hook.ts:210-247); a server
    // reporting mem_total_mb == 0 is skipped so the average cannot go NaN.
    var memCount = 0;
    for (final s in servers) {
      final st = snap.status[s.id];
      if (st == null || st.time == null) continue;
      final live = nowMs - st.time!.millisecondsSinceEpoch < 5000;
      if (live && st.memTotalMb > 0) memCount++;
    }
    final avgCpu = onlineCount > 0 ? cpuAcc / onlineCount : 0.0;
    final avgMem = memCount > 0 ? memAcc / memCount : 0.0;

    // Totals — web index.tsx:86-103: all filtered servers with a report
    // (online or not); cores come from the server row itself, storage sums
    // every disk, bandwidth keeps RX / TX separate.
    var cores = 0;
    var hasCores = false;
    var memTotal = 0.0;
    var storage = 0.0;
    var bwRx = 0.0;
    var bwTx = 0.0;
    for (final s in servers) {
      final c = s.coreT ?? s.coreC;
      if (c != null) {
        cores += c;
        hasCores = true;
      }
      final st = snap.status[s.id];
      if (st == null) continue;
      memTotal += st.memTotalMb;
      final disks = st.disks;
      if (disks != null) {
        for (final d in disks) {
          storage += d.totalGb;
        }
      }
      bwRx += st.rxTotalMb;
      bwTx += st.txTotalMb;
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
            value: '$onlineCount/${servers.length}',
            icon: Icons.dns_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          tile(
            label: t(context, 'Avg CPU', '平均 CPU'),
            value: '${avgCpu.toStringAsFixed(2)}%',
            icon: Icons.memory_outlined,
            color: MColors.chartBlue2,
          ),
          tile(
            label: t(context, 'Avg Memory', '平均内存'),
            value: '${avgMem.toStringAsFixed(2)}%',
            icon: Icons.storage_outlined,
            color: MColors.chartGreen2,
          ),
          tile(
            label: t(context, 'Traffic', '网络流量'),
            value: '↑ ${netRate(txAcc)}',
            subtitle: '↓ ${netRate(rxAcc)}',
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
              value: hasCores ? '$cores' : '--',
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
              value: '↑ ${mbTotal(bwTx)}',
              subtitle: '↓ ${mbTotal(bwRx)}',
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
    // web index.tsx:68 — the first (default) category is hidden from chips.
    final chipCats = cats.length > 1 ? cats.sublist(1) : <Category>[];
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
                for (final c in chipCats) ...[
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
              switch (cfg.dashboardLayout) {
                'grid' => Icons.view_list_outlined,
                'list' => Icons.grid_view_outlined,
                _ => Icons.view_module_outlined,
              },
              size: 20,
            ),
            onPressed: () => _setLayout(switch (cfg.dashboardLayout) {
              'grid' => 'list',
              'list' => 'list2',
              _ => 'grid',
            }),
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
    String layout,
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

    final filtered = _visibleServers(snap);
    // web index.tsx:640-680 — render one section per category; categories
    // without servers get an inline "No servers in this category." note,
    // except the default category which stays hidden when unfiltered.
    final visibleCats = _filter == -1
        ? cats
        : cats.where((c) => c.id == _filter).toList();
    final groups = <int, List<MonitorList>>{};
    for (final s in filtered) {
      groups.putIfAbsent(s.category, () => []).add(s);
    }
    for (final list in groups.values) {
      list.sort((a, b) => b.weight.compareTo(a.weight));
    }
    final catIds = cats.map((c) => c.id).toSet();

    final slivers = <Widget>[];
    void addGroup(String name, List<MonitorList> list) {
      slivers.add(_groupHeader(context, name));
      slivers.add(_groupBody(context, snap, list, layout, showDetails));
    }

    for (var i = 0; i < visibleCats.length; i++) {
      final cat = visibleCats[i];
      final list = groups.remove(cat.id);
      if (list == null || list.isEmpty) {
        if (_filter == -1 && i == 0) continue; // hide empty default category
        slivers.add(_groupHeader(context, cat.name));
        slivers.add(_emptyCategoryNote(context));
        continue;
      }
      addGroup(cat.name, list);
    }
    // Servers in deleted / ungrouped categories (id 0 or stale ids).
    for (final entry in groups.entries) {
      addGroup(
        entry.key == 0
            ? t(context, 'Default', '默认')
            : (catIds.contains(entry.key)
                ? (cats.where((c) => c.id == entry.key).firstOrNull?.name ??
                    t(context, 'Default', '默认'))
                : t(context, 'Default', '默认')),
        entry.value,
      );
    }
    if (slivers.isEmpty) {
      slivers.add(_emptyCategoryNote(context));
    }
    return slivers;
  }

  Widget _groupHeader(BuildContext context, String name) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
          child: Text(
            name.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );

  Widget _emptyCategoryNote(BuildContext context) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
          child: Text(
            t(context, 'No servers in this category.', '该分类下暂无服务器。'),
            style: TextStyle(
              fontSize: 12,
              color:
                  Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        ),
      );

  Widget _groupBody(
    BuildContext context,
    MonitorSnapshot snap,
    List<MonitorList> list,
    String layout,
    bool showDetails,
  ) {
    Widget card(int i) => FadeSlideIn(
          delay: (i * 60).clamp(0, 600).toInt(),
          child: ServerCard(
            server: list[i],
            snap: snap,
            showDetails: showDetails,
            onTap: () => context.push('/monitor/${list[i].id}'),
            onMenu: () => showServerMenu(context, ref, list[i], snap),
          ),
        );

    // 'list' is the single-column layout; 'grid' and 'list2' both render
    // two columns on phone widths (web list2 = md:grid-cols-2).
    if (layout == 'list') {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Column(
            children: [
              for (var i = 0; i < list.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: card(i),
                ),
            ],
          ),
        ),
      );
    }
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = (constraints.maxWidth - 10) / 2;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < list.length; i++)
                  SizedBox(width: w, child: card(i)),
              ],
            );
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- skeleton

  /// Full-page skeleton (web index.tsx:223-277): header + 4 overview tiles,
  /// filter chips and a batch of server cards.
  Widget _skeletonPage(List<Category> cats, String layout) {
    Widget statSkeleton() => MCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Skeleton(width: 34, height: 34, radius: 8),
              const SizedBox(height: 12),
              const Skeleton(width: 70),
              const SizedBox(height: 6),
              const Skeleton(width: 52, height: 11),
            ],
          ),
        );
    Widget chipSkeleton(double w) => Skeleton(width: w, height: 30, radius: 15);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _grid2([
          statSkeleton(),
          statSkeleton(),
          statSkeleton(),
          statSkeleton(),
        ]),
        const SizedBox(height: 16),
        Row(
          children: [
            chipSkeleton(52),
            const SizedBox(width: 8),
            chipSkeleton(72),
            const SizedBox(width: 8),
            chipSkeleton(64),
            const SizedBox(width: 8),
            chipSkeleton(80),
          ],
        ),
        const SizedBox(height: 20),
        ..._skeletonCards(layout == 'list' ? 4 : 8, layout == 'list'),
      ],
    );
  }

  List<Widget> _skeletonCards(int count, bool singleColumn) {
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
    if (singleColumn) {
      return [
        for (var i = 0; i < count; i++) ...[
          skeletonCard(),
          const SizedBox(height: 10),
        ],
      ];
    }
    return [
      LayoutBuilder(
        builder: (context, constraints) {
          final w = (constraints.maxWidth - 10) / 2;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var i = 0; i < count; i++)
                SizedBox(width: w, child: skeletonCard()),
            ],
          );
        },
      ),
    ];
  }
}
