import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
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
class ServerCard extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final st = snap.status[server.id];
    final online = MonitorController.isOnline(snap, server.id);
    final status = _lifeStatus(online, st);

    return MCard(
      padding: const EdgeInsets.all(12),
      onTap: onTap,
      onLongPress: onMenu,
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
                  onPressed: onMenu,
                ),
              ),
            ],
          ),
          if (st != null) ...[
            _progressRow(
              context,
              label: 'CPU',
              percent: st.cpu,
              right: '${st.cpu.toStringAsFixed(1)}%',
            ),
            _progressRow(
              context,
              label: t(context, 'MEM', '内存'),
              percent: st.memPercent,
              right: '${mbTotal(st.memUsedMb)} / ${mbTotal(st.memTotalMb)}',
            ),
            if (st.swapTotalMb > 0)
              _progressRow(
                context,
                label: 'SWAP',
                percent: st.swapPercent,
                right: '${mbTotal(st.swapUsedMb)} / ${mbTotal(st.swapTotalMb)}',
              ),
            // Disk: first only collapsed; all mount points when expanded.
            if (st.disks != null && st.disks!.isNotEmpty)
              for (final d in (showDetails ? st.disks! : st.disks!.take(1)))
                _progressRow(
                  context,
                  label: showDetails
                      ? '${t(context, 'DISK', '磁盘')} ${d.mp}'
                      : t(context, 'DISK', '磁盘'),
                  percent: d.usedPercent,
                  right: '${gb(d.usedGb)} / ${gb(d.totalGb)}',
                ),
            _cycleRow(context),
          ],
          _badges(context, online, st),
          if (showDetails && st != null) _details(context, st),
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

  /// Remaining-cycle bar; expiry color: >7d green, >3d orange, else red.
  Widget _cycleRow(BuildContext context) {
    final cycle = server.cycle;
    if (server.endTime == null || cycle == null || cycleDays(cycle) <= 0) {
      return const SizedBox.shrink();
    }
    final dr = daysRemaining(server.endTime);
    if (dr == null) return const SizedBox.shrink();
    final Color color;
    if (dr > 7) {
      color = MColors.online;
    } else if (dr > 3) {
      color = MColors.warning;
    } else {
      color = MColors.offline;
    }
    final suffix = cycleLabel(cycle, suffixMode: true);
    final right = dr < 0
        ? t(context, 'Expired', '已过期')
        : '${dr}d${suffix.isEmpty ? '' : ' $suffix'}';
    return _progressRow(
      context,
      label: t(context, 'Cycle', '周期'),
      percent: remainingPercent(server.startTime, server.endTime, cycle),
      right: right,
      color: color,
    );
  }

  Widget _badges(BuildContext context, bool online, ServerStatus? st) {
    final area = (server.area ?? '').trim();
    final county = (server.county ?? '').trim();
    final provider = (server.provider ?? '').trim();
    final amount = (server.amount ?? '').trim();
    final bandwidth = (server.bandwidth ?? '').trim();
    final traffic = (server.traffic ?? '').trim();
    final notePublic = (server.notePublic ?? '').trim();
    final tt = trafficTypeLabel(server.trafficType);

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
        ],
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
/// numeric threshold + duration rows, per-row save/delete, override switch.
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
        const SizedBox(height: 12),
        for (final cfg in data.itemConfigs) ...[
          _AlertRow(
            key: ValueKey('$_tab-${cfg.item}'),
            cfg: cfg,
            serverId: widget.serverId,
            isTeamTab: isTeamTab,
            existing: isTeamTab
                ? data.teamAlerts[cfg.item]
                : (data.alerts[widget.serverId]?[cfg.item] ??
                    data.teamAlerts[cfg.item]),
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
    required this.existing,
    required this.onChanged,
  });

  final AlertItemConfig cfg;
  final int serverId;
  final bool isTeamTab;
  final ServerAlert? existing;
  final VoidCallback onChanged;

  @override
  ConsumerState<_AlertRow> createState() => _AlertRowState();
}

class _AlertRowState extends ConsumerState<_AlertRow> {
  late final TextEditingController _threshold = TextEditingController(
    text: (widget.existing?.threshold ??
            widget.cfg.threshold.defaultValue ??
            0)
        .toString(),
  );
  late final TextEditingController _duration = TextEditingController(
    text: (widget.existing?.forDuration ??
            widget.cfg.forDuration.defaultValue ??
            0)
        .toString(),
  );
  bool _override = false;
  bool _busy = false;

  @override
  void dispose() {
    _threshold.dispose();
    _duration.dispose();
    super.dispose();
  }

  int get _targetId => widget.isTeamTab ? -1 : widget.serverId;

  Future<void> _save() async {
    final thr = int.tryParse(_threshold.text.trim());
    final dur = int.tryParse(_duration.text.trim());
    if (thr == null || dur == null) {
      toastWarn(context, t(context, 'Invalid number', '数字无效'));
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).alertSet(
            _targetId,
            widget.cfg.item,
            thr,
            dur,
            override: !widget.isTeamTab && _override,
          );
      if (!mounted) return;
      toastSuccess(context);
      widget.onChanged();
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).alertDelete(
            widget.cfg.item,
            _targetId,
            override: !widget.isTeamTab && _override,
          );
      if (!mounted) return;
      toastSuccess(context);
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
                style: TextStyle(
                    fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (cfg.threshold.enabled)
                Expanded(
                  child: _numField(_threshold, t(context, 'Threshold', '阈值'),
                      cfg.threshold.unit),
                ),
              if (cfg.threshold.enabled && cfg.forDuration.enabled)
                const SizedBox(width: 8),
              if (cfg.forDuration.enabled)
                Expanded(
                  child: _numField(_duration, t(context, 'Duration', '持续'),
                      cfg.forDuration.unit),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (!widget.isTeamTab) ...[
                SizedBox(
                  width: 36,
                  height: 24,
                  child: Switch(value: _override, onChanged: (v) => setState(() => _override = v)),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    t(context, 'Override team default', '覆盖团队默认'),
                    style: TextStyle(
                        fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ] else
                const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.delete_outline,
                    size: 20,
                    color: widget.existing == null
                        ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4)
                        : MColors.offline),
                tooltip: t(context, 'Delete', '删除'),
                onPressed: (_busy || widget.existing == null) ? null : _delete,
              ),
              const SizedBox(width: 8),
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

  Widget _numField(TextEditingController ctrl, String label, String unit) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        suffixText: unit.isEmpty ? null : unit,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
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
  late List<Category> _cats =
      List<Category>.from(ref.read(teamDataProvider).categories);
  final _addCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _addCtrl.dispose();
    super.dispose();
  }

  ApiServices get _api => ref.read(apiProvider);

  Future<void> _reload() async {
    await ref.read(teamDataProvider.notifier).refresh();
    if (!mounted) return;
    setState(() {
      _cats = List<Category>.from(ref.read(teamDataProvider).categories);
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
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _add() async {
    final name = _addCtrl.text.trim();
    if (name.isEmpty || _busy) return;
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
                onSubmitted: (_) => _add(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _busy ? null : _add,
              icon: const Icon(Icons.add),
              tooltip: t(context, 'Add', '添加'),
            ),
          ],
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
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          leading: const Icon(Icons.label_outline, size: 20),
          title: Text(t(context, 'Default (no category)', '默认（未分组）'),
              style: const TextStyle(fontSize: 14)),
          onTap: _busy ? null : () => _set(0),
        ),
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
