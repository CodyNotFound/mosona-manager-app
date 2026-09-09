import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_services.dart';
import '../../core/models/models.dart';
import '../../core/sse/sse_client.dart';
import '../../core/state/display_config.dart';
import '../../core/theme/mcolors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/widgets.dart';
import 'charts.dart';

/// Monitor page for one server (web `/{id}/monitor` parity): info card,
/// time-frame toolbar with settings, and 6 charts fed by the chart API or a
/// local ring buffer in real-time mode.
class MonitorPage extends ConsumerStatefulWidget {
  const MonitorPage({super.key, required this.serverId});

  final int serverId;

  @override
  ConsumerState<MonitorPage> createState() => _MonitorPageState();
}

class _MonitorPageState extends ConsumerState<MonitorPage> {
  static const _frameOptions = ['real-time', '1h', '12h', '24h', '7d', '30d', '365d'];
  static const _diskPalette = [
    MColors.chartOrange2,
    MColors.chartYellow2,
    MColors.chartRed2,
    MColors.chartBlue2,
    MColors.chartViolet2,
    MColors.chartGreen2,
    MColors.chartOrange1,
    MColors.chartYellow1,
    MColors.chartRed1,
    MColors.chartBlue1,
    MColors.chartViolet1,
    MColors.chartGreen1,
  ];

  MonitorInfoResult? _info;
  bool _loading = true;
  bool _failed = false;

  /// Latest realtime sample (3s polling) + tick to refresh derived live UI.
  final ValueNotifier<ServerStatus?> _realtime = ValueNotifier(null);
  final ValueNotifier<int> _uiTick = ValueNotifier(0);

  /// Ring buffer of realtime samples (real-time frame, max 60 points).
  List<ServerStatus> _buffer = [];
  List<ServerStatus>? _chart;
  bool _chartLoading = false;

  late String _timeFrame;
  Timer? _pollTimer;
  Timer? _refreshTimer;
  int _gen = 0; // chart request race protection

  @override
  void initState() {
    super.initState();
    _timeFrame = ref.read(displayConfigProvider).defaultTimeFrame;
    if (!_frameOptions.contains(_timeFrame)) _timeFrame = '1h';
    _loadInfo();
    if (_timeFrame != 'real-time') {
      _chartLoading = true;
      _fetchChart();
    }
    _pollRealtime();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _pollRealtime());
    _syncRefreshTimer();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _refreshTimer?.cancel();
    _realtime.dispose();
    _uiTick.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------- data loading

  Future<void> _loadInfo() async {
    try {
      final res = await ref.read(apiProvider).monitorInfo(widget.serverId);
      if (!mounted) return;
      setState(() {
        _info = res;
        _loading = false;
        _failed = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
      showApiError(context, e);
    }
  }

  Future<void> _pollRealtime() async {
    try {
      final st = await ref.read(apiProvider).monitorRealtime(widget.serverId);
      if (!mounted) return;
      _realtime.value = st;
      if (_timeFrame == 'real-time') {
        setState(() {
          _buffer = [..._buffer, st];
          if (_buffer.length > 60) {
            _buffer = _buffer.sublist(_buffer.length - 60);
          }
        });
      }
    } catch (_) {
      // keep last value; online badge freshness decays on the next tick
    } finally {
      if (mounted) _uiTick.value++;
    }
  }

  Future<void> _fetchChart() async {
    final tf = _timeFrame;
    if (tf == 'real-time') return;
    final gen = ++_gen;
    try {
      final res = await ref.read(apiProvider).monitorChart(widget.serverId, tf);
      if (!mounted || gen != _gen) return; // drop stale responses
      setState(() {
        _chart = res;
        _chartLoading = false;
      });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() => _chartLoading = false);
      showApiError(context, e);
    }
  }

  Future<void> _refresh() async {
    await _loadInfo();
    _pollRealtime();
    if (_timeFrame != 'real-time') await _fetchChart();
  }

  void _setFrame(String f) {
    if (f == _timeFrame) return;
    setState(() {
      _timeFrame = f;
      _chart = null;
      _chartLoading = f != 'real-time';
    });
    _syncRefreshTimer();
    if (f != 'real-time') _fetchChart();
  }

  void _syncRefreshTimer() {
    final active = _timeFrame != 'real-time' && ref.read(displayConfigProvider).autoRefresh;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    if (active) {
      _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) => _fetchChart());
    }
  }

  void _updateConfig(void Function(DisplayConfig c) mutate) {
    final cfg = ref.read(displayConfigProvider);
    mutate(cfg);
    ref.read(displayConfigProvider.notifier).update(cfg);
    _syncRefreshTimer();
  }

  // ------------------------------------------------------------------ derived

  bool _isOnline() {
    final rt = _realtime.value;
    final rtTime = rt?.time;
    if (rtTime != null &&
        DateTime.now().difference(rtTime).inMilliseconds.abs() < 5000) {
      return true;
    }
    final snap = ref.read(monitorProvider);
    return snap != null && MonitorController.isOnline(snap, widget.serverId);
  }

  String _frameLabel(String f) =>
      f == 'real-time' ? t(context, 'Real-time', '实时') : f.toUpperCase();

  String _xLabel(double v) {
    final dt = DateTime.fromMillisecondsSinceEpoch((v * 1000).round());
    final long = _timeFrame == '7d' || _timeFrame == '30d' || _timeFrame == '365d';
    return long ? DateFormat('MM-dd').format(dt) : DateFormat('HH:mm').format(dt);
  }

  SeriesData _extract(List<ServerStatus> pts, List<double? Function(ServerStatus)> pickers) {
    final xs = <double>[];
    final cols = List.generate(pickers.length, (_) => <double?>[]);
    for (final p in pts) {
      final ts = p.time;
      if (ts == null) continue;
      xs.add(ts.millisecondsSinceEpoch / 1000);
      for (var i = 0; i < pickers.length; i++) {
        cols[i].add(pickers[i](p));
      }
    }
    return SeriesData(xs, cols);
  }

  // --------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(displayConfigProvider);
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        centerTitle: false,
        title: _appBarTitle(),
      ),
      body: _loading
          ? _skeletonBody()
          : _failed
              ? _errorBody()
              : SafeArea(
                  child: RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _infoCard(),
                        const SizedBox(height: 12),
                        _toolbar(),
                        const SizedBox(height: 12),
                        ..._charts(cfg),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _appBarTitle() {
    final detail = _info?.info;
    if (detail == null) return Text(t(context, 'Monitor', '监控'));
    final list = detail.list;
    final area = (list.area ?? '').trim();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                list.name,
                style: monoStyle(context, size: 15),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            ValueListenableBuilder<int>(
              valueListenable: _uiTick,
              builder: (context, _, _) {
                final online = _isOnline();
                return MBadge(
                  color: online ? MColors.online : MColors.offline,
                  small: true,
                  child: Text(t(context, online ? 'online' : 'offline', online ? '在线' : '离线')),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FlagIcon(countryCode: list.county, size: 12),
            if (area.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(area,
                  style: TextStyle(
                      fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
            const SizedBox(width: 8),
            Text(formatUptimeDays(list.openTime),
                style: TextStyle(
                    fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            if (_info!.stale) ...[
              const SizedBox(width: 6),
              MBadge(
                color: MColors.warning,
                small: true,
                child: Text(t(context, 'stale', '过期')),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _skeletonBody() => SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Skeleton(width: double.infinity, height: 230, radius: 12),
            const SizedBox(height: 16),
            const Skeleton(height: 36, radius: 999),
            for (var i = 0; i < 3; i++) ...[
              const SizedBox(height: 16),
              const Skeleton(width: double.infinity, height: 240, radius: 12),
            ],
          ],
        ),
      );

  Widget _errorBody() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            EmptyState(
              text: t(context, 'Failed to load monitor data', '监控数据加载失败'),
              icon: Icons.error_outline,
            ),
            const SizedBox(height: 8),
            LoadingButton(
              label: t(context, 'Retry', '重试'),
              onPressed: () {
                setState(() => _loading = true);
                _loadInfo();
                if (_timeFrame != 'real-time') _fetchChart();
              },
            ),
          ],
        ),
      );

  // ---------------------------------------------------------------- info card

  Widget _infoCard() {
    return MCard(
      child: ValueListenableBuilder<int>(
        valueListenable: _uiTick,
        builder: (context, _, _) {
          final live = _realtime.value;
          return LayoutBuilder(builder: (context, c) {
            final rows = _infoRows(live);
            final twoCol = c.maxWidth >= 560;
            if (!twoCol) {
              return Column(children: rows);
            }
            final paired = <Widget>[];
            for (var i = 0; i < rows.length; i += 2) {
              final second = i + 1 < rows.length ? rows[i + 1] : const SizedBox();
              paired.add(Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: rows[i]),
                  const SizedBox(width: 16),
                  Expanded(child: second),
                ],
              ));
            }
            return Column(children: paired);
          });
        },
      ),
    );
  }

  List<Widget> _infoRows(ServerStatus? live) {
    final d = _info?.info;
    final rows = <Widget>[];
    if (d == null) return rows;
    final os = (d.list.os ?? '').trim();

    if (d.ip != null && d.ip!.isNotEmpty) {
      rows.add(InfoRow(label: 'IP', value: d.ip));
    }
    if (d.hostname != null && d.hostname!.isNotEmpty) {
      rows.add(InfoRow(label: t(context, 'Hostname', '主机名'), value: d.hostname));
    }
    if (os.isNotEmpty) {
      rows.add(InfoRow(
        label: t(context, 'System', '系统'),
        child: Row(children: [
          OsIcon(os: d.list.os, size: 16),
          const SizedBox(width: 6),
          Expanded(child: Text(os, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
        ]),
      ));
    }
    if (d.arch != null && d.arch!.isNotEmpty) {
      rows.add(InfoRow(label: t(context, 'Arch', '架构'), value: d.arch));
    }
    if (d.kernel != null && d.kernel!.isNotEmpty) {
      rows.add(InfoRow(label: t(context, 'Kernel', '内核'), value: d.kernel));
    }
    if (d.cpuName != null && d.cpuName!.isNotEmpty) {
      final cores = '(${d.coreC ?? '?'}C/${d.coreT ?? '?'}T)';
      rows.add(InfoRow(
        label: 'CPU',
        child: Text(
          '${d.cpuName} $cores',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ));
    }
    if (live != null) {
      rows.add(InfoRow(
        label: t(context, 'Total up/down', '累计上传/下载'),
        value: '↑ ${mbTotal(live.txTotalMb)} · ↓ ${mbTotal(live.rxTotalMb)}',
      ));
      rows.add(InfoRow(
        label: t(context, 'CPU usage', 'CPU 占用'),
        value: '${live.cpu.toStringAsFixed(1)}%',
      ));
      rows.add(InfoRow(
        label: t(context, 'Memory', '内存'),
        value:
            '${mbTotal(live.memUsedMb)} / ${mbTotal(live.memTotalMb)} · ${live.memPercent.toStringAsFixed(1)}%',
      ));
      for (final disk in live.disks ?? const <DiskInfo>[]) {
        rows.add(InfoRow(
          label: disk.mp,
          child: Text(
            '${gb(disk.usedGb)} / ${gb(disk.totalGb)} · ${disk.usedPercent.toStringAsFixed(1)}%',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ));
      }
      rows.add(InfoRow(
        label: t(context, 'Disk IO', '磁盘 IO'),
        value: 'R ${netRate(live.diskReadKibS)} · W ${netRate(live.diskWriteKibS)}',
      ));
      rows.add(InfoRow(
        label: t(context, 'Network', '实时网速'),
        value: '↑ ${netRate(live.txKibS)} · ↓ ${netRate(live.rxKibS)}',
      ));
      rows.add(InfoRow(
        label: t(context, 'TCP/UDP', '连接数'),
        value: 'TCP ${compactNumber(live.tcpTotal)} · UDP ${compactNumber(live.udpTotal)}',
      ));
    }
    return rows;
  }

  // ------------------------------------------------------------------ toolbar

  Widget _toolbar() {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final f in _frameOptions) ...[
                  _frameChip(f, theme),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ),
        IconButton(
          tooltip: t(context, 'Chart settings', '图表设置'),
          icon: const Icon(Icons.tune, size: 20),
          onPressed: _openSettings,
        ),
      ],
    );
  }

  Widget _frameChip(String f, ThemeData theme) {
    final selected = f == _timeFrame;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => _setFrame(f),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? theme.colorScheme.primary : theme.dividerColor,
          ),
        ),
        child: Text(
          _frameLabel(f),
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Future<void> _openSettings() {
    return showMSheet(
      context: context,
      title: t(context, 'Chart settings', '图表设置'),
      child: Consumer(builder: (context, sheetRef, _) {
        final cfg = sheetRef.watch(displayConfigProvider);
        final mode = ['avg', 'max', 'raw'].contains(cfg.monitorMode) ? cfg.monitorMode : 'avg';
        final yMode = ['min-auto', '0-auto', '0-max'].contains(cfg.minMaxMode)
            ? cfg.minMaxMode
            : 'min-auto';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t(context, 'Aggregation', '聚合方式'),
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'avg', label: Text(t(context, 'Avg', '平均'))),
                ButtonSegment(value: 'max', label: Text(t(context, 'Max', '最大'))),
                ButtonSegment(value: 'raw', label: Text(t(context, 'Raw', '原始'))),
              ],
              selected: {mode},
              showSelectedIcon: false,
              onSelectionChanged: (s) => _updateConfig((c) => c.monitorMode = s.first),
            ),
            const SizedBox(height: 16),
            Text(t(context, 'Y axis', 'Y 轴'),
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'min-auto', label: Text(t(context, 'Min auto', '最小自动'))),
                ButtonSegment(value: '0-auto', label: Text(t(context, '0 auto', '0 自动'))),
                ButtonSegment(value: '0-max', label: Text(t(context, '0 max', '0 最大'))),
              ],
              selected: {yMode},
              showSelectedIcon: false,
              onSelectionChanged: (s) => _updateConfig((c) => c.minMaxMode = s.first),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t(context, 'Auto refresh', '自动刷新'),
                  style: const TextStyle(fontSize: 14)),
              value: cfg.autoRefresh,
              onChanged: (v) => _updateConfig((c) => c.autoRefresh = v),
            ),
          ],
        );
      }),
    );
  }

  // ------------------------------------------------------------------- charts

  Widget _legendChip(Color color, String label) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }

  List<Widget> _charts(DisplayConfig cfg) {
    final historical = _timeFrame != 'real-time';
    final pts = historical ? (_chart ?? const <ServerStatus>[]) : _buffer;
    final loading = historical && _chart == null && _chartLoading;
    final buckets = historical ? timeFrameWindowSize(_timeFrame) : 60;
    final agg = ['avg', 'max', 'raw'].contains(cfg.monitorMode) ? cfg.monitorMode : 'avg';
    final yMode = ['min-auto', '0-auto', '0-max'].contains(cfg.minMaxMode)
        ? cfg.minMaxMode
        : 'min-auto';

    var delay = 60;
    Widget card(String title, List<Widget> legend, LineChartData? data) {
      final w = FadeSlideIn(
        delay: delay,
        child: _ChartCard(title: title, legend: legend, data: data, loading: loading),
      );
      delay += 60;
      return w;
    }

    LineChartData? mk(
      SeriesData d,
      List<ChartSeriesStyle> styles, {
      String? mode,
      double? fMin,
      double? fMax,
      required String Function(double) yFmt,
      List<HorizontalLine> extra = const [],
    }) {
      final ds = downsampleSeries(d, buckets, mode ?? agg);
      if (ds.xs.length < 2) return null;
      return buildTimeChart(
        context,
        data: ds,
        styles: styles,
        minMaxMode: yMode,
        fixedMinY: fMin,
        fixedMaxY: fMax,
        yFormat: yFmt,
        xFormat: _xLabel,
        extraHorizontalLines: extra,
      );
    }

    // 1. CPU %
    final cpu = mk(
      _extract(pts, [(s) => s.cpu]),
      [ChartSeriesStyle(label: 'CPU', color: MColors.chartBlue2, format: (v) => '${v.toStringAsFixed(0)}%')],
      fMin: 0,
      fMax: 100,
      yFmt: (v) => '${v.toStringAsFixed(0)}%',
    );

    // 2. Memory used (cap = total, dashed reference line)
    double? memTotal;
    for (final p in pts.reversed) {
      if (p.memTotalMb > 0) {
        memTotal = p.memTotalMb;
        break;
      }
    }
    final mem = mk(
      _extract(pts, [(s) => s.memUsedMb]),
      [ChartSeriesStyle(label: t(context, 'Used', '已用'), color: MColors.chartGreen2, format: mbTotal)],
      fMin: 0,
      fMax: memTotal,
      yFmt: mbTotal,
      extra: memTotal == null
          ? const []
          : [
              HorizontalLine(
                y: memTotal,
                color: MColors.chartGreen1,
                strokeWidth: 1,
                dashArray: const [5, 4],
              ),
            ],
    );

    // 3. Disk IO: read/write rates (thick) + IOPS (thin)
    final io = mk(
      _extract(pts, [
        (s) => s.diskReadKibS,
        (s) => s.diskWriteKibS,
        (s) => s.diskReadIops,
        (s) => s.diskWriteIops,
      ]),
      [
        ChartSeriesStyle(label: t(context, 'Read', '读取'), color: MColors.chartBlue2, format: netRate),
        ChartSeriesStyle(label: t(context, 'Write', '写入'), color: MColors.chartYellow2, format: netRate),
        ChartSeriesStyle(
            label: t(context, 'R IOPS', '读 IOPS'),
            color: MColors.chartBlue1,
            strokeWidth: 1,
            format: (v) => compactNumber(v.round())),
        ChartSeriesStyle(
            label: t(context, 'W IOPS', '写 IOPS'),
            color: MColors.chartYellow1,
            strokeWidth: 1,
            format: (v) => compactNumber(v.round())),
      ],
      yFmt: netRate,
    );

    // 4. Bandwidth rx/tx
    final net = mk(
      _extract(pts, [(s) => s.rxKibS, (s) => s.txKibS]),
      [
        ChartSeriesStyle(label: '↓ ${t(context, 'Down', '下行')}', color: MColors.chartViolet2, format: netRate),
        ChartSeriesStyle(label: '↑ ${t(context, 'Up', '上行')}', color: MColors.chartRed1, format: netRate),
      ],
      yFmt: netRate,
    );

    // 5. SWAP used
    final swap = mk(
      _extract(pts, [(s) => s.swapUsedMb]),
      [ChartSeriesStyle(label: 'SWAP', color: MColors.chartGreen2, format: mbTotal)],
      fMin: 0,
      yFmt: mbTotal,
    );

    // 6. Per-mount disk usage (dedupe by mp, merge latest realtime point)
    var diskPts = pts;
    final rt = _realtime.value;
    if (historical && rt != null) {
      final lastT = pts.isEmpty ? null : pts.last.time;
      if (rt.time != null && (lastT == null || rt.time!.isAfter(lastT))) {
        diskPts = [...pts, rt];
      }
    }
    final mps = <String>[];
    for (final p in diskPts) {
      for (final d in p.disks ?? const <DiskInfo>[]) {
        if (!mps.contains(d.mp)) mps.add(d.mp);
      }
    }
    LineChartData? disks;
    final diskLegend = <Widget>[];
    if (mps.isNotEmpty) {
      final styles = <ChartSeriesStyle>[];
      final pickers = <double? Function(ServerStatus)>[];
      for (var i = 0; i < mps.length; i++) {
        final mp = mps[i];
        final color = _diskPalette[i % _diskPalette.length];
        styles.add(ChartSeriesStyle(label: 'Disk ${i + 1}', color: color, format: gb));
        pickers.add((s) {
          for (final d in s.disks ?? const <DiskInfo>[]) {
            if (d.mp == mp) return d.usedGb;
          }
          return null;
        });
        diskLegend.add(_legendChip(color, 'Disk ${i + 1}'));
      }
      disks = mk(_extract(diskPts, pickers), styles, fMin: 0, yFmt: gb);
    }

    return [
      card(t(context, 'CPU', 'CPU'), [], cpu),
      card(
          t(context, 'Memory', '内存'),
          [
            _legendChip(MColors.chartGreen2, t(context, 'Used', '已用')),
            _legendChip(MColors.chartGreen1, t(context, 'Total', '总量')),
          ],
          mem),
      card(
          t(context, 'Disk IO', '磁盘 IO'),
          [
            _legendChip(MColors.chartBlue2, t(context, 'Read', '读取')),
            _legendChip(MColors.chartYellow2, t(context, 'Write', '写入')),
            _legendChip(MColors.chartBlue1, t(context, 'R IOPS', '读 IOPS')),
            _legendChip(MColors.chartYellow1, t(context, 'W IOPS', '写 IOPS')),
          ],
          io),
      card(
          t(context, 'Bandwidth', '带宽'),
          [
            _legendChip(MColors.chartViolet2, t(context, 'Down', '下行')),
            _legendChip(MColors.chartRed1, t(context, 'Up', '上行')),
          ],
          net),
      card(t(context, 'SWAP', 'SWAP'), [], swap),
      card(t(context, 'Disk usage', '磁盘用量'), diskLegend, disks),
    ];
  }
}

/// One chart card: title, 160-high line chart, optional legend chips.
class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.legend,
    required this.data,
    this.loading = false,
  });

  final String title;
  final List<Widget> legend;
  final LineChartData? data;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return MCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          loading
              ? const SizedBox(height: 160, child: Center(child: Skeleton(width: double.infinity, height: 140, radius: 8)))
              : SizedBox(
                  height: 160,
                  child: data == null
                      ? EmptyState(
                          text: t(context, 'No data yet', '暂无数据'),
                          icon: Icons.show_chart,
                        )
                      : LineChart(data!),
                ),
          if (legend.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 12, runSpacing: 4, children: legend),
          ],
        ],
      ),
    );
  }
}
