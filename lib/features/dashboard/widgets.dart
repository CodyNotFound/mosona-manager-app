import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart' show apiClientProvider;
import '../../core/api/api_services.dart' show ApiServices, apiProvider;
import '../../core/models/models.dart';
import '../../core/sse/sse_client.dart'
    show MonitorController, monitorProvider;
import '../../core/state/session.dart' show mutationBusProvider, teamDataProvider;
import '../../core/theme/mcolors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/widgets.dart';
import '../terminal/terminal_page.dart' show terminalManagerProvider;

/// Dashboard-only shared widgets: server card, server action menu,
/// alerts bottom sheet and category management sheets.
/// Used exclusively by DashboardPage / ServerFormPage feature files.

// Badge foregrounds matching the web badge palette (bg from MColors badge*).
const _kEmeraldFg = Color(0xFF10B981);
const _kIndigoFg = Color(0xFF6366F1);
const _kVioletFg = Color(0xFF8B5CF6);
const _kYellowFg = Color(0xFFCA8A04);

// ------------------------------------------------------------------ card

ServerLifeStatus _lifeStatus(bool online, ServerStatus? st) {
  if (online) return ServerLifeStatus.online;
  final time = st?.time;
  if (time != null) {
    final diff = DateTime.now().difference(time);
    if (!diff.isNegative && diff.inSeconds <= 30) return ServerLifeStatus.warning;
  }
  return ServerLifeStatus.offline;
}

/// One server card for the dashboard list (web 3.4 parity).
class ServerCard extends ConsumerStatefulWidget {
  const ServerCard({
    super.key,
    required this.server,
    required this.snap,
    this.showDetails = false,
    this.onTap,
    this.onMenu,
  });

  final MonitorList server;
  final MonitorSnapshot snap;
  final bool showDetails;
  final VoidCallback? onTap;
  final VoidCallback? onMenu;

  @override
  ConsumerState<ServerCard> createState() => _ServerCardState();
}

class _ServerCardState extends ConsumerState<ServerCard> {
  /// Per-card expand toggle (web card.tsx:238-242) — follows the global
  /// showDetails switch until toggled locally from the footer row.
  late bool _showMore = widget.showDetails;

  @override
  void didUpdateWidget(ServerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showDetails != widget.showDetails) {
      _showMore = widget.showDetails;
    }
  }

  void _toggleMore() => setState(() => _showMore = !_showMore);

  /// Valid disks ('/' mount first, stable order, invalid entries dropped)
  /// mirroring web utils/disk.ts getStatusDisks.
  List<DiskInfo> _statusDisks(ServerStatus? st) {
    final disks = st?.disks;
    if (disks == null) return const [];
    final indexed = <(DiskInfo, int)>[
      for (var i = 0; i < disks.length; i++)
        if (disks[i].mp.isNotEmpty) (disks[i], i),
    ];
    indexed.sort((a, b) {
      final am = a.$1.mp;
      final bm = b.$1.mp;
      if (am == bm) return a.$2.compareTo(b.$2);
      if (am == '/') return -1;
      if (bm == '/') return 1;
      return a.$2.compareTo(b.$2);
    });
    return [for (final e in indexed) e.$1];
  }

  /// Usage percent rounded to 2 decimals (web getDiskUsagePercentage).
  double _diskPct(DiskInfo d) {
    if (d.totalGb <= 0) return 0;
    return (d.usedGb / d.totalGb * 10000).roundToDouble() / 100;
  }

  /// parseFloat(x.toFixed(2)) parity — trims trailing zeros ("12.50" -> "12.5").
  String _num2(double v) {
    var s = v.toStringAsFixed(2);
    if (s.contains('.')) {
      s = s.replaceAll(RegExp(r'0+$'), '');
      if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final server = widget.server;
    final snap = widget.snap;
    final st = snap.status[server.id];
    final online = MonitorController.isOnline(snap, server.id);
    final status = _lifeStatus(online, st);
    // The web dashboard only distinguishes online/offline for metric values.
    final offlineView = !online;
    final disks = _statusDisks(st);
    final expanded = _showMore;

    return MCard(
      padding: const EdgeInsets.all(12),
      onTap: widget.onTap,
      onLongPress: widget.onMenu,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // header: OS icon + name + status + menu
          Row(
            children: [
              OsIcon(os: server.os, size: 26),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  server.name,
                  style: monoStyle(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              StatusBadge(status: status),
              SizedBox(
                width: 26,
                height: 26,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.more_vert, size: 18),
                  tooltip: t(context, 'Menu', '菜单'),
                  onPressed: widget.onMenu,
                ),
              ),
            ],
          ),
          _progressRow(
            context,
            label: 'CPU',
            percent: offlineView ? 0 : st?.cpu ?? 0,
            right: offlineView || st == null ? '--' : '${_num2(st.cpu)}%',
          ),
          _progressRow(
            context,
            label: t(context, 'MEM', '内存'),
            percent: offlineView ? 0 : st?.memPercent ?? 0,
            right: offlineView || st == null
                ? '--'
                : '${_num2(st.memPercent)}%'
                    '${expanded ? ' (${mbTotal(st.memUsedMb)} / ${mbTotal(st.memTotalMb)})' : ''}',
          ),
          if (expanded && st != null && st.swapTotalMb > 0)
            _progressRow(
              context,
              label: 'SWAP',
              percent: offlineView ? 0 : st.swapPercent,
              right: offlineView
                  ? '--'
                  : '${_num2(st.swapPercent)}%'
                      ' (${mbTotal(st.swapUsedMb)} / ${mbTotal(st.swapTotalMb)})',
            ),
          // Disk: first only collapsed; all mount points when expanded.
          if (disks.isEmpty)
            _progressRow(context, label: t(context, 'DISK', '磁盘'),
                percent: 0, right: '--')
          else
            for (final d in expanded ? disks : disks.sublist(0, 1))
              _progressRow(
                context,
                label: expanded
                    ? '${t(context, 'DISK', '磁盘')} ${d.mp}'
                    : t(context, 'DISK', '磁盘'),
                percent: offlineView ? 0 : _diskPct(d),
                right: offlineView
                    ? '--'
                    : '${_num2(_diskPct(d))}%'
                        '${expanded ? ' (${gb(d.usedGb)} / ${gb(d.totalGb)})' : ''}',
              ),
          _remainingRow(context),
          _badges(context, online, st),
          if (expanded && st != null) _details(context, st),
          _bottomRow(context, online, st),
        ],
      ),
    );
  }

  Widget _progressRow(
    BuildContext context, {
    required String label,
    required double percent,
    String? right,
    Color? color,
  }) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              if (right != null)
                Text(right,
                    style: TextStyle(fontSize: 11, color: muted)),
            ],
          ),
          const SizedBox(height: 3),
          MProgress(percent: percent, color: color),
        ],
      ),
    );
  }

  /// Remaining-period bar (web card.tsx:200-236): works from end_time with
  /// cycle-based start inference (cycle 1 -> 1 month back, else (cycle-1)*3
  /// months); bar length = remaining, color from the elapsed share.
  Widget _remainingRow(BuildContext context) {
    final end = widget.server.endTime;
    final cycle = widget.server.cycle;
    final hasStart = widget.server.startTime != null;
    final hasCycle = cycle != null && cycle > 0;
    if (end == null || !(hasStart || hasCycle)) {
      return const SizedBox.shrink();
    }
    DateTime start;
    if (hasCycle) {
      final months = cycle == 1 ? 1 : (cycle - 1) * 3;
      start = end.subtract(Duration(days: 30 * months));
    } else {
      start = widget.server.startTime!;
    }
    final totalMs = end.difference(start).inMilliseconds;
    if (totalMs <= 0) return const SizedBox.shrink();
    final remainMsRaw = end.difference(DateTime.now()).inMilliseconds;
    final remainMs = remainMsRaw < 0 ? 0 : remainMsRaw;
    final progress = (remainMs / totalMs * 100).clamp(0.0, 100.0);
    final days = remainMs ~/ 86400000;
    final hours = (remainMs % 86400000) ~/ 3600000;
    final minutes = (remainMs % 3600000) ~/ 60000;
    var timeText = '';
    if (days > 0) timeText += '$days ';
    if (hours > 0) timeText += '$hours ';
    if (minutes > 0) timeText += '$minutes';
    timeText = timeText.trim();
    if (timeText.isEmpty) return const SizedBox.shrink();
    return _progressRow(
      context,
      label: t(context, 'Remaining', '剩余周期'),
      percent: progress,
      right: timeText,
      color: MColors.progressColor(100 - progress),
    );
  }

  Widget _badges(BuildContext context, bool online, ServerStatus? st) {
    final server = widget.server;
    final area = (server.area ?? '').trim();
    final county = (server.county ?? '').trim();
    final provider = (server.provider ?? '').trim();
    final amount = (server.amount ?? '').trim();
    final bandwidth = (server.bandwidth ?? '').trim();
    final traffic = (server.traffic ?? '').trim();
    final notePublic = (server.notePublic ?? '').trim();
    final tt = trafficTypeLabel(server.trafficType);

    // web card.tsx:675-692 — expiry badge: >7d green, >3d orange, else red.
    Widget expiryBadge() {
      final end = server.endTime!;
      final days = end.difference(DateTime.now()).inDays;
      final (Color fg, Color bg) = days > 7
          ? (MColors.online, MColors.badgeGreen)
          : days > 3
              ? (MColors.warning, MColors.badgeOrange)
              : (MColors.offline, MColors.badgeRed);
      return MBadge(
        small: true,
        color: fg,
        backgroundColor: bg,
        child: Text(days < 0
            ? t(context, 'Expired', '已过期')
            : '${t(context, 'Expired', '到期')}: ${days}d'),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          if (area.isNotEmpty || county.isNotEmpty)
            MBadge(
              small: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FlagIcon(countryCode: server.county, size: 12),
                  if (area.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    Text(area),
                  ],
                ],
              ),
            ),
          MBadge(
            small: true,
            child: Text(
              online && server.openTime != null
                  ? formatUptime(DateTime.now().difference(server.openTime!))
                  : t(context, 'Offline', '离线'),
            ),
          ),
          if (provider.isNotEmpty)
            MBadge(
              small: true,
              color: _kEmeraldFg,
              backgroundColor: MColors.badgeEmerald,
              child: Text(provider),
            ),
          if (amount.isNotEmpty)
            MBadge(
              small: true,
              color: _kIndigoFg,
              backgroundColor: MColors.badgeIndigo,
              child: Text(amountLabel(server.amount, server.cycle)),
            ),
          if (bandwidth.isNotEmpty)
            MBadge(
              small: true,
              color: _kVioletFg,
              backgroundColor: MColors.badgeViolet,
              child: Text(bandwidth),
            ),
          if (traffic.isNotEmpty)
            MBadge(
              small: true,
              child: Text(tt.isEmpty ? traffic : '$traffic $tt'),
            ),
          if (server.endTime != null) expiryBadge(),
          if (notePublic.isNotEmpty)
            MBadge(
              small: true,
              color: _kYellowFg,
              backgroundColor: MColors.badgeYellow,
              child: Text(notePublic, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
        ],
      ),
    );
  }

  Widget _details(BuildContext context, ServerStatus st) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              SizedBox(
                width: 76,
                child: Text(label,
                    style: TextStyle(fontSize: 11, color: muted)),
              ),
              Expanded(
                child: Text(value,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w500)),
              ),
            ],
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            row(
                t(context, 'Disk IO', '磁盘 IO'),
                'R ${netRate(st.diskReadKibS)} · W ${netRate(st.diskWriteKibS)}'),
            row(
                'IOPS',
                'R ${st.diskReadIops.toStringAsFixed(1)} · '
                'W ${st.diskWriteIops.toStringAsFixed(1)}'),
            row('TCP / UDP',
                '${compactNumber(st.tcpTotal)} / ${compactNumber(st.udpTotal)}'),
            row(t(context, 'Total', '累计'),
                '↑ ${mbTotal(st.txTotalMb)} · ↓ ${mbTotal(st.rxTotalMb)}'),
          ],
        ),
      ),
    );
  }

  Widget _bottomRow(BuildContext context, bool online, ServerStatus? st) {
    final server = widget.server;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final String left;
    if (online && server.openTime != null) {
      left =
          '${t(context, 'UP', '开机')} ${formatUptime(DateTime.now().difference(server.openTime!))}';
    } else if (st?.time != null) {
      left = '${t(context, 'Last seen', '最后在线')} '
          '${DateFormat('yyyy-MM-dd HH:mm').format(st!.time!)}';
    } else {
      left = t(context, 'Offline', '离线');
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      // Tapping the footer toggles this card's detail area (web card.tsx:436-481).
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleMore,
        child: Row(
          children: [
            Expanded(
              child: Text(left,
                  style: TextStyle(fontSize: 10, color: muted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 8),
            Text(
              '↑ ${netRate(st?.txKibS ?? 0)}  ↓ ${netRate(st?.rxKibS ?? 0)}',
              style: TextStyle(fontSize: 10, color: muted),
            ),
            const SizedBox(width: 4),
            Icon(
              _showMore ? Icons.expand_less : Icons.expand_more,
              size: 14,
              color: muted,
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ menu

/// Long-press / "⋮" action sheet (web right-click menu parity).
Future<void> showServerMenu(
  BuildContext context,
  WidgetRef ref,
  MonitorList server,
  MonitorSnapshot snap,
) {
  return showMSheet(
    context: context,
    title: server.name,
    child: Builder(
      builder: (sheetCtx) {
        void close() => Navigator.of(sheetCtx).pop();
        return Column(
          children: [
            _MenuTile(
              icon: Icons.query_stats_outlined,
              label: t(context, 'View details', '查看详情'),
              onTap: () {
                final router = GoRouter.of(context);
                close();
                router.push('/monitor/${server.id}');
              },
            ),
            if (server.allowTerminal)
              _MenuTile(
                icon: Icons.terminal_outlined,
                label: t(context, 'Terminal', '终端'),
                onTap: () {
                  final mgr = ref.read(terminalManagerProvider);
                  final client = ref.read(apiClientProvider);
                  final s = mgr.create(
                    server: TerminalServer(
                      id: server.id,
                      name: server.name,
                      type: server.type,
                      category: server.category,
                    ),
                    client: client,
                  );
                  final router = GoRouter.of(context);
                  close();
                  router.push('/session/${s.id}');
                },
              ),
            _MenuTile(
              icon: Icons.notifications_outlined,
              label: t(context, 'Notifications', '通知提醒'),
              onTap: () {
                close();
                showAlertSheet(context, ref,
                    serverId: server.id, serverName: server.name);
              },
            ),
            _MenuTile(
              icon: Icons.edit_outlined,
              label: t(context, 'Edit', '编辑'),
              onTap: () {
                final router = GoRouter.of(context);
                close();
                router.push('/server-form?id=${server.id}');
              },
            ),
            _MenuTile(
              icon: Icons.folder_outlined,
              label: t(context, 'Category', '分类'),
              onTap: () {
                close();
                showMoveCategorySheet(context, ref, server);
              },
            ),
            _MenuTile(
              icon: Icons.delete_outline,
              label: t(context, 'Delete', '删除'),
              danger: true,
              onTap: () => _deleteServer(context, sheetCtx, ref, server),
            ),
          ],
        );
      },
    ),
  );
}

Future<void> _deleteServer(
  BuildContext pageCtx,
  BuildContext sheetCtx,
  WidgetRef ref,
  MonitorList server,
) async {
  final res = await showDialog(
    context: pageCtx,
    builder: (_) => ConfirmNameDialog(
      title: t(pageCtx, 'Delete Server', '删除服务器'),
      message: t(pageCtx,
          'Type the server name to confirm deletion:', '输入服务器名称以确认删除：'),
      name: server.name,
      confirmLabel: t(pageCtx, 'Delete', '删除'),
    ),
  );
  if (res == null || !pageCtx.mounted) return;
  try {
    await ref.read(apiProvider).serverDelete(server.id);
    ref.read(mutationBusProvider).notifyServersChanged();
    ref.read(teamDataProvider.notifier).refresh();
    ref.read(monitorProvider.notifier).subscribe();
    if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
    if (pageCtx.mounted) {
      toastSuccess(pageCtx, t(pageCtx, 'Server deleted', '服务器已删除'));
    }
  } catch (e) {
    if (pageCtx.mounted) showApiError(pageCtx, e);
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.label,
    this.danger = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool danger;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = danger ? MColors.offline : null;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      leading: Icon(icon, size: 20, color: color),
      title: Text(label, style: TextStyle(fontSize: 14, color: color)),
      onTap: onTap,
    );
  }
}

// ------------------------------------------------------------------ alerts

/// Alerts bottom sheet (web 3.4 parity): this-server / all-servers tabs,
/// config-driven slider rows, per-row save/delete, team-level override.
Future<void> showAlertSheet(
  BuildContext context,
  WidgetRef ref, {
  required int serverId,
  required String serverName,
}) {
  return showMSheet(
    context: context,
    title: '${t(context, 'Notifications', '通知提醒')} · $serverName',
    child: _AlertSheetBody(serverId: serverId),
  );
}

class _AlertSheetBody extends ConsumerStatefulWidget {
  const _AlertSheetBody({required this.serverId});

  final int serverId;

  @override
  ConsumerState<_AlertSheetBody> createState() => _AlertSheetBodyState();
}

class _AlertSheetBodyState extends ConsumerState<_AlertSheetBody> {
  int _tab = 0; // 0 = this server, 1 = all servers (team, id -1)
  bool _overrideTeam = false;
  AlertsData? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ref.read(apiProvider).alertsList();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Column(
        children: [
          for (var i = 0; i < 4; i++) ...[
            const Skeleton(height: 76, radius: 10),
            const SizedBox(height: 10),
          ],
        ],
      );
    }
    if (_error != null || _data == null) {
      return Column(
        children: [
          EmptyState(text: t(context, 'Failed to load alerts', '加载提醒失败')),
          TextButton(onPressed: _load, child: Text(t(context, 'Retry', '重试'))),
        ],
      );
    }
    final data = _data!;
    final isTeamTab = _tab == 1;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // web alerts.tsx:57-70 — description with a link to notification settings.
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text.rich(
            TextSpan(
              style: TextStyle(fontSize: 11.5, color: muted),
              children: [
                TextSpan(text: t(context, 'See ', '请前往')),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: GestureDetector(
                    onTap: () => context.push('/settings'),
                    child: Text(
                      ' ${t(context, 'notification settings', '通知设置')} ',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: MColors.link,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
                TextSpan(
                    text: t(context,
                        'to configure how you receive alerts.',
                        '，配置告警的接收方式。')),
              ],
            ),
          ),
        ),
        SegmentedButton<int>(
          segments: [
            ButtonSegment(
              value: 0,
              label: Text(t(context, 'This server', '本服务器')),
            ),
            ButtonSegment(
              value: 1,
              label: Text(t(context, 'All servers', '全部服务器')),
            ),
          ],
          selected: {_tab},
          onSelectionChanged: (s) => setState(() => _tab = s.first),
        ),
        // web alerts.tsx:90-111 — override toggle exists on the team tab only
        // and applies the alert to every server in the team.
        if (isTeamTab) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox(
                width: 40,
                height: 24,
                child: Switch(
                  value: _overrideTeam,
                  activeThumbColor: MColors.offline,
                  onChanged: (v) => setState(() => _overrideTeam = v),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  t(context, 'Override Team Alerts', '覆盖团队告警'),
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: MColors.offline),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        if (data.itemConfigs.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              t(context,
                  'No configurable alerts are available right now.',
                  '当前没有可配置的告警。'),
              style: TextStyle(fontSize: 12, color: muted),
            ),
          )
        else
          for (final cfg in data.itemConfigs) ...[
            _AlertRow(
              key: ValueKey('$_tab-${cfg.item}'),
              cfg: cfg,
              serverId: widget.serverId,
              isTeamTab: isTeamTab,
              teamOverride: isTeamTab && _overrideTeam,
              existing: isTeamTab
                  ? data.teamAlerts[cfg.item]
                  // web item.tsx:35 — server scope never falls back to team.
                  : data.alerts[widget.serverId]?[cfg.item],
              onChanged: _load,
            ),
            const SizedBox(height: 10),
          ],
        SizedBox(height: MediaQuery.paddingOf(context).bottom),
      ],
    );
  }
}

class _AlertRow extends ConsumerStatefulWidget {
  const _AlertRow({
    super.key,
    required this.cfg,
    required this.serverId,
    required this.isTeamTab,
    required this.teamOverride,
    required this.existing,
    required this.onChanged,
  });

  final AlertItemConfig cfg;
  final int serverId;
  final bool isTeamTab;

  /// web item.tsx:51 — only meaningful on the team tab.
  final bool teamOverride;
  final ServerAlert? existing;
  final VoidCallback onChanged;

  @override
  ConsumerState<_AlertRow> createState() => _AlertRowState();
}

class _AlertRowState extends ConsumerState<_AlertRow> {
  late int _threshold =
      _initial(widget.cfg.threshold, widget.existing?.threshold);
  late int _duration =
      _initial(widget.cfg.forDuration, widget.existing?.forDuration);
  bool _busy = false;

  int _initial(AlertFieldConfig cfg, int? existing) {
    if (existing != null) return existing;
    return cfg.defaultValue ?? cfg.min ?? 0;
  }

  int get _targetId => widget.isTeamTab ? -1 : widget.serverId;

  bool get _effectiveOverride => widget.isTeamTab && widget.teamOverride;

  int _min(AlertFieldConfig cfg) => cfg.min ?? 0;

  int _max(AlertFieldConfig cfg) => cfg.max ?? cfg.defaultValue ?? _min(cfg);

  /// web item.tsx:284-289 — stepped slider ranges.
  int _step(AlertFieldConfig cfg) {
    final range = (_max(cfg) - _min(cfg)).abs();
    if (range >= 10000) return 1000;
    if (range >= 1000) return 10;
    return 1;
  }

  /// web item.tsx:263-282 — human readable value + unit.
  String _fmtValue(int value, String unit) {
    switch (unit) {
      case 'percent':
        return '$value%';
      case 'minute':
        return t(context, value == 1 ? '1 minute' : '$value minutes',
            '$value 分钟');
      case 'day':
        return t(context, value == 1 ? '1 day' : '$value days', '$value 天');
      default:
        return unit.isEmpty ? '$value' : '$value $unit';
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final count = await ref.read(apiProvider).alertSet(
            _targetId,
            widget.cfg.item,
            _threshold,
            _duration,
            override: _effectiveOverride,
          );
      if (!mounted) return;
      if (widget.isTeamTab) {
        toastSuccess(
            context,
            t(context, 'Team alert enabled', '团队告警已启用', zhHk: '團隊警報已啟用'));
      } else {
        toastSuccess(
            context,
            count > 1
                ? t(context, '$count servers', '$count 台服务器', zhHk: '$count 台伺服器')
                : null);
      }
      widget.onChanged();
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final count = await ref.read(apiProvider).alertDelete(
            widget.cfg.item,
            _targetId,
            override: _effectiveOverride,
          );
      if (!mounted) return;
      if (widget.isTeamTab) {
        toastSuccess(
            context,
            t(context, 'Team alert disabled', '团队告警已禁用', zhHk: '團隊警報已停用'));
      } else {
        toastSuccess(
            context,
            count > 1
                ? t(context, '$count servers', '$count 台服务器', zhHk: '$count 台伺服器')
                : null);
      }
      widget.onChanged();
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cfg = widget.cfg;
    final muted = theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(cfg.label,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              if (widget.existing != null)
                MBadge(
                  small: true,
                  color: MColors.online,
                  backgroundColor: MColors.badgeGreen,
                  child: Text(t(context, 'Active', '已设置')),
                ),
            ],
          ),
          if (cfg.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                cfg.description,
                style: TextStyle(fontSize: 11, color: muted),
              ),
            ),
          if (widget.existing != null && cfg.notifyOnce)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                t(context,
                    'This alert is sent once per matching window.',
                    '此告警在每个匹配窗口内仅发送一次。'),
                style: TextStyle(fontSize: 10.5, color: muted),
              ),
            ),
          const SizedBox(height: 8),
          if (cfg.threshold.enabled)
            _slider(
              context,
              t(context, 'Threshold', '阈值'),
              _threshold,
              _min(cfg.threshold),
              _max(cfg.threshold),
              _step(cfg.threshold),
              _fmtValue(_threshold, cfg.threshold.unit),
              (v) => setState(() => _threshold = v.round()),
            ),
          if (cfg.forDuration.enabled)
            _slider(
              context,
              t(context, 'Duration', '持续'),
              _duration,
              _min(cfg.forDuration),
              _max(cfg.forDuration),
              _step(cfg.forDuration),
              _fmtValue(_duration, cfg.forDuration.unit),
              (v) => setState(() => _duration = v.round()),
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.delete_outline,
                    size: 20,
                    color: widget.existing == null
                        ? muted.withValues(alpha: 0.4)
                        : MColors.offline),
                tooltip: t(context, 'Delete', '删除'),
                onPressed: (_busy || widget.existing == null) ? null : _delete,
              ),
              const Spacer(),
              LoadingButton(
                label: t(context, 'Save', '保存'),
                loading: _busy,
                onPressed: _save,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Min/max/step-constrained slider (web item.tsx:226-256).
  Widget _slider(
    BuildContext context,
    String label,
    int value,
    int min,
    int max,
    int step,
    String formatted,
    ValueChanged<double> onChanged,
  ) {
    final theme = Theme.of(context);
    final lo = min.toDouble();
    final hi = max > min ? max.toDouble() : min.toDouble() + 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label,
                style:
                    TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text(formatted,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary)),
          ],
        ),
        Slider(
          value: value.toDouble().clamp(lo, hi).toDouble(),
          min: lo,
          max: hi,
          divisions: max > min ? ((max - min) / step).round() : null,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ categories

/// Category management sheet: rename / delete / up-down reorder / add new.
Future<void> showCategoryManageSheet(BuildContext context, WidgetRef ref) {
  return showMSheet(
    context: context,
    title: t(context, 'Manage Categories', '管理分类'),
    child: const _CategoryManageBody(),
  );
}

class _CategoryManageBody extends ConsumerStatefulWidget {
  const _CategoryManageBody();

  @override
  ConsumerState<_CategoryManageBody> createState() =>
      _CategoryManageBodyState();
}

class _CategoryManageBodyState extends ConsumerState<_CategoryManageBody> {
  final _addCtrl = TextEditingController();
  bool _busy = false;
  late List<Category> _cats;

  @override
  void initState() {
    super.initState();
    _cats = _manageable();
  }

  @override
  void dispose() {
    _addCtrl.dispose();
    super.dispose();
  }

  /// web manage.tsx:151-155 — the default (first) category is not listed.
  List<Category> _manageable() {
    final all = [...ref.read(teamDataProvider).categories]
      ..sort((a, b) => a.sort.compareTo(b.sort));
    return all.length > 1 ? all.sublist(1) : <Category>[];
  }

  ApiServices get _api => ref.read(apiProvider);

  Future<void> _reload() async {
    await ref.read(teamDataProvider.notifier).refresh();
    if (!mounted) return;
    setState(() {
      _cats = _manageable();
    });
  }

  Future<void> _rename(Category cat, String name) async {
    try {
      await _api.categoryUpdate(cat.id, name);
      if (!mounted) return;
      toastSuccess(context);
      await _reload();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _delete(Category cat) async {
    final ok = await confirmDialog(
      context,
      title: t(context, 'Delete category', '删除分类'),
      message: t(context, 'Delete "${cat.name}"? Servers in it become ungrouped.', '删除“${cat.name}”？其中的服务器将变为未分组。'),
      danger: true,
      okLabel: t(context, 'Delete', '删除'),
    );
    if (!ok || !mounted) return;
    try {
      await _api.categoryDelete(cat.id);
      if (!mounted) return;
      toastSuccess(context);
      await _reload();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _move(int index, int delta) async {
    final swapped = [..._cats];
    final tmp = swapped[index];
    swapped[index] = swapped[index + delta];
    swapped[index + delta] = tmp;
    setState(() => _cats = swapped);
    try {
      await _api.categorySort(swapped.map((c) => c.id).toList());
      await ref.read(teamDataProvider.notifier).refresh();
      if (!mounted) return;
      toastSuccess(
          context,
          t(context, 'Category order updated', '分类排序已更新'));
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  /// web add.tsx:36-38 — case-insensitive duplicate-name pre-check.
  bool get _addExists {
    final name = _addCtrl.text.trim().toLowerCase();
    if (name.isEmpty) return false;
    return ref
        .read(teamDataProvider)
        .categories
        .any((c) => c.name.trim().toLowerCase() == name);
  }

  Future<void> _add() async {
    final name = _addCtrl.text.trim();
    if (name.isEmpty || _addExists || _busy) return;
    setState(() => _busy = true);
    try {
      await _api.categoryCreate(name);
      _addCtrl.clear();
      if (!mounted) return;
      toastSuccess(context);
      await _reload();
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final addEmpty = _addCtrl.text.trim().isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _cats.length; i++)
          _CatRow(
            key: ValueKey(_cats[i].id),
            cat: _cats[i],
            canUp: i > 0,
            canDown: i < _cats.length - 1,
            onUp: () => _move(i, -1),
            onDown: () => _move(i, 1),
            onRename: (name) => _rename(_cats[i], name),
            onDelete: () => _delete(_cats[i]),
          ),
        if (_cats.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              t(context, 'No categories yet', '暂无分类'),
              style: TextStyle(
                  fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        const Divider(height: 24),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _addCtrl,
                decoration: InputDecoration(
                  labelText: t(context, 'New category', '新增分类'),
                  isDense: true,
                  border:
                      OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _add(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: (addEmpty || _addExists || _busy) ? null : _add,
              icon: const Icon(Icons.add),
              tooltip: t(context, 'Add', '添加'),
            ),
          ],
        ),
        if (_addExists)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              t(context, 'Category name already exists', '分类名称已存在'),
              style: const TextStyle(
                  fontSize: 11, color: MColors.offline),
            ),
          ),
      ],
    );
  }
}

class _CatRow extends StatefulWidget {
  const _CatRow({
    super.key,
    required this.cat,
    required this.canUp,
    required this.canDown,
    required this.onUp,
    required this.onDown,
    required this.onRename,
    required this.onDelete,
  });

  final Category cat;
  final bool canUp;
  final bool canDown;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final ValueChanged<String> onRename;
  final VoidCallback onDelete;

  @override
  State<_CatRow> createState() => _CatRowState();
}

class _CatRowState extends State<_CatRow> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.cat.name);

  bool get _dirty => _ctrl.text.trim() != widget.cat.name;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.folder_outlined, size: 18),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (v) {
                if (_dirty && v.trim().isNotEmpty) widget.onRename(v.trim());
              },
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.check, size: 20,
                color: _dirty ? MColors.online : muted.withValues(alpha: 0.4)),
            tooltip: t(context, 'Rename', '重命名'),
            onPressed: !_dirty || _ctrl.text.trim().isEmpty
                ? null
                : () => widget.onRename(_ctrl.text.trim()),
          ),
          SizedBox(
            width: 34,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 18,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.keyboard_arrow_up, size: 18),
                    onPressed: widget.canUp ? widget.onUp : null,
                  ),
                ),
                SizedBox(
                  height: 18,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.keyboard_arrow_down, size: 18),
                    onPressed: widget.canDown ? widget.onDown : null,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.delete_outline, size: 20, color: MColors.offline),
            tooltip: t(context, 'Delete', '删除'),
            onPressed: widget.onDelete,
          ),
        ],
      ),
    );
  }
}

/// Move-server-to-category sheet (pick or create new).
Future<void> showMoveCategorySheet(
  BuildContext context,
  WidgetRef ref,
  MonitorList server,
) {
  return showMSheet(
    context: context,
    title: t(context, 'Move to category', '移动到分类'),
    child: _MoveCategoryBody(server: server),
  );
}

class _MoveCategoryBody extends ConsumerStatefulWidget {
  const _MoveCategoryBody({required this.server});

  final MonitorList server;

  @override
  ConsumerState<_MoveCategoryBody> createState() => _MoveCategoryBodyState();
}

class _MoveCategoryBodyState extends ConsumerState<_MoveCategoryBody> {
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
      await ref.read(apiProvider).serverSetCategory(widget.server.id, categoryId);
      ref.read(monitorProvider.notifier).subscribe();
      if (!mounted) return;
      Navigator.of(context).pop();
      toastSuccess(context);
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
      final cats = ref.read(teamDataProvider).categories;
      final created = cats.where((c) => c.name == name).firstOrNull;
      if (created == null) {
        toastSuccess(context);
        Navigator.of(context).pop();
        return;
      }
      await ref.read(apiProvider).serverSetCategory(widget.server.id, created.id);
      ref.read(monitorProvider.notifier).subscribe();
      if (!mounted) return;
      Navigator.of(context).pop();
      toastSuccess(context);
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
      children: [
        // web category/edit.tsx:74-90 — pick among real categories only;
        // there is no separate "ungrouped" target.
        for (final c in cats)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            leading: const Icon(Icons.folder_outlined, size: 20),
            title: Text(c.name, style: const TextStyle(fontSize: 14)),
            trailing: c.id == widget.server.category
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
                decoration: InputDecoration(
                  labelText: t(context, 'New category', '新增分类'),
                  isDense: true,
                  border:
                      OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onSubmitted: (_) => _createAndSet(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _busy ? null : _createAndSet,
              icon: const Icon(Icons.add),
              tooltip: t(context, 'Create & move', '创建并移动'),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            t(context, 'Create a category and move this server into it.',
                '创建分类并将该服务器移入。'),
            style: TextStyle(fontSize: 11, color: muted),
          ),
        ),
      ],
    );
  }
}
