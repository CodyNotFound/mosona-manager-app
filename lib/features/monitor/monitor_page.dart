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

  /// Transient per-chart aggregation overrides for the CPU / IO / bandwidth
  /// card headers (web `monitor-chart.tsx` local mode select; reset when the
  /// global default changes, never persisted).
  final Map<String, String> _chartModes = {};

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
    // Persist as the user's default (web index.tsx: updateConfig({defaultTimeFrame})).
    _updateConfig((c) => c.defaultTimeFrame = f);
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
      f == 'real-time' ? t(context, 'Real-time', '实时', zhHk: '即時') : f.toUpperCase();

  /// Length of the fixed X window per time frame (web monitor-chart startTime).
  Duration get _windowLength => switch (_timeFrame) {
        '1h' => const Duration(hours: 1),
        '12h' => const Duration(hours: 12),
        '24h' => const Duration(hours: 24),
        '7d' => const Duration(days: 7),
        '30d' => const Duration(days: 30),
        '365d' => const Duration(days: 365),
        _ => Duration.zero,
      };

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
    if (detail == null) return Text(t(context, 'Monitor', '监控', zhHk: '監察'));
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
                  child: Text(t(context, online ? 'online' : 'offline', online ? '在线' : '离线',
                      zhHk: online ? '在線' : '離線')),
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
                child: Text(t(context, 'stale', '过期', zhHk: '過期')),
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
              text: t(context, 'Failed to load monitor data', '监控数据加载失败',
                  zhHk: '監察數據載入失敗'),
              icon: Icons.error_outline,
            ),
            const SizedBox(height: 8),
            LoadingButton(
              label: t(context, 'Retry', '重试', zhHk: '重試'),
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
      rows.add(InfoRow(label: t(context, 'Hostname', '主机名', zhHk: '主機名稱'), value: d.hostname));
    }
    if (os.isNotEmpty) {
      rows.add(InfoRow(
        label: t(context, 'System', '系统', zhHk: '系統'),
        child: Row(children: [
          OsIcon(os: d.list.os, size: 16),
          const SizedBox(width: 6),
          Expanded(child: Text(os, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
        ]),
      ));
    }
    if (d.arch != null && d.arch!.isNotEmpty) {
      rows.add(InfoRow(label: t(context, 'Arch', '架构', zhHk: '架構'), value: d.arch));
    }
    if (d.kernel != null && d.kernel!.isNotEmpty) {
      rows.add(InfoRow(label: t(context, 'Kernel', '内核', zhHk: '核心'), value: d.kernel));
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
        label: t(context, 'Total up/down', '累计上传/下载', zhHk: '上載/下載總量'),
        value: '↑ ${mbTotal(live.txTotalMb)} · ↓ ${mbTotal(live.rxTotalMb)}',
      ));
      rows.add(InfoRow(
        label: t(context, 'CPU usage', 'CPU 占用', zhHk: 'CPU 使用率'),
        value: '${live.cpu.toStringAsFixed(1)}%',
      ));
      rows.add(InfoRow(
        label: t(context, 'Memory', '内存', zhHk: '記憶體'),
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
        label: t(context, 'Disk IO', '磁盘 IO', zhHk: '磁碟 I/O'),
        value: 'R ${netRate(live.diskReadKibS)} · W ${netRate(live.diskWriteKibS)}',
      ));
      rows.add(InfoRow(
        label: t(context, 'Network', '实时网速', zhHk: '即時網速'),
        value: '↑ ${netRate(live.txKibS)} · ↓ ${netRate(live.rxKibS)}',
      ));
      rows.add(InfoRow(
        label: t(context, 'TCP/UDP', '连接数', zhHk: '連線數'),
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
          tooltip: t(context, 'Chart settings', '图表设置', zhHk: '圖表設定'),
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
      title: t(context, 'Chart settings', '图表设置', zhHk: '圖表設定'),
      child: Consumer(builder: (context, sheetRef, _) {
        final cfg = sheetRef.watch(displayConfigProvider);
        final mode = ['avg', 'max', 'raw'].contains(cfg.monitorMode) ? cfg.monitorMode : 'avg';
        final yMode = ['min-auto', '0-auto', '0-max'].contains(cfg.minMaxMode)
            ? cfg.minMaxMode
            : 'min-auto';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t(context, 'Aggregation', '聚合方式', zhHk: '匯總方式'),
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'avg', label: Text(t(context, 'Avg', '平均', zhHk: '平均值'))),
                ButtonSegment(value: 'max', label: Text(t(context, 'Max', '最大', zhHk: '最大值'))),
                ButtonSegment(value: 'raw', label: Text(t(context, 'Raw', '原始', zhHk: '原始數據'))),
              ],
              selected: {mode},
              showSelectedIcon: false,
              onSelectionChanged: (s) {
                // Web resets the per-chart mode selects when the default changes.
                setState(() => _chartModes.clear());
                _updateConfig((c) => c.monitorMode = s.first);
              },
            ),
            const SizedBox(height: 16),
            Text(t(context, 'Y axis', 'Y 轴', zhHk: 'Y 軸'),
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(
                    value: 'min-auto',
                    label: Text(t(context, 'Min auto', '最小自动', zhHk: '最小值 - 自動'))),
                ButtonSegment(
                    value: '0-auto', label: Text(t(context, '0 auto', '0 自动', zhHk: '0 自動'))),
                ButtonSegment(
                    value: '0-max', label: Text(t(context, '0 max', '0 最大', zhHk: '0 最大'))),
              ],
              selected: {yMode},
              showSelectedIcon: false,
              onSelectionChanged: (s) => _updateConfig((c) => c.minMaxMode = s.first),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t(context, 'Auto refresh', '自动刷新', zhHk: '自動重新整理'),
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

    // Fixed X window (web: domain = [now - windowLength, now]) so sparse data
    // still spans the whole frame; real-time pins to the buffer start.
    final nowMs = DateTime.now().millisecondsSinceEpoch / 1000;
    double? fixedMinX;
    final fixedMaxX = nowMs;
    if (historical) {
      fixedMinX = nowMs - _windowLength.inSeconds;
    } else if (pts.isNotEmpty && pts.first.time != null) {
      fixedMinX = pts.first.time!.millisecondsSinceEpoch / 1000;
    }

    // Per-chart transient aggregation (CPU/IO/bandwidth card headers, web only
    // exposes them outside real-time; memory/SWAP/disk are always raw).
    String chartAgg(String key) => historical ? (_chartModes[key] ?? agg) : agg;

    var delay = 60;
    Widget card(String title, List<Widget> legend, LineChartData? data,
        {String? modeKey}) {
      final interactive = historical && modeKey != null;
      final w = FadeSlideIn(
        delay: delay,
        child: _ChartCard(
          title: title,
          legend: legend,
          data: data,
          loading: loading,
          mode: interactive ? chartAgg(modeKey) : null,
          onModeChanged: interactive
              ? (m) => setState(() => _chartModes[modeKey] = m)
              : null,
        ),
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
        // web domain: [min-auto ? 'min' : 0, 0-max ? chartMaxValue : 'auto']
        fixedMinY: yMode == 'min-auto' ? null : (fMin ?? 0),
        fixedMaxY: yMode == '0-max' ? fMax : null,
        fixedMinX: fixedMinX,
        fixedMaxX: fixedMaxX,
        yFormat: yFmt,
        xFormat: _xLabel,
        extraHorizontalLines: extra,
      );
    }

    // 1. CPU % (0-max cap = 100)
    final cpu = mk(
      _extract(pts, [(s) => s.cpu]),
      [ChartSeriesStyle(label: 'CPU', color: MColors.chartBlue2, format: (v) => '${v.toStringAsFixed(0)}%')],
      mode: chartAgg('cpu'),
      fMin: 0,
      fMax: 100,
      yFmt: (v) => '${v.toStringAsFixed(0)}%',
    );

    // 2. Memory used (raw; 0-max cap = total, dashed reference line)
    double? memTotal;
    for (final p in pts.reversed) {
      if (p.memTotalMb > 0) {
        memTotal = p.memTotalMb;
        break;
      }
    }
    final mem = mk(
      _extract(pts, [(s) => s.memUsedMb]),
      [ChartSeriesStyle(label: t(context, 'Used', '已用', zhHk: '已用'), color: MColors.chartGreen2, format: mbTotal)],
      mode: 'raw',
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

    // 3. Disk IO split into two charts: throughput (KiB/s) and IOPS — they
    // need different Y axes, one shared axis labels IOPS in byte units
    final io = mk(
      _extract(pts, [
        (s) => s.diskReadKibS,
        (s) => s.diskWriteKibS,
      ]),
      [
        ChartSeriesStyle(label: t(context, 'Read', '读取', zhHk: '讀取'), color: MColors.chartBlue2, format: netRate),
        ChartSeriesStyle(label: t(context, 'Write', '写入', zhHk: '寫入'), color: MColors.chartYellow2, format: netRate),
      ],
      mode: chartAgg('io'),
      yFmt: netRate,
    );
    final ioIops = mk(
      _extract(pts, [
        (s) => s.diskReadIops,
        (s) => s.diskWriteIops,
      ]),
      [
        ChartSeriesStyle(
            label: t(context, 'R IOPS', '读 IOPS', zhHk: '讀 IOPS'),
            color: MColors.chartBlue1,
            format: (v) => compactNumber(v.round())),
        ChartSeriesStyle(
            label: t(context, 'W IOPS', '写 IOPS', zhHk: '寫 IOPS'),
            color: MColors.chartYellow1,
            format: (v) => compactNumber(v.round())),
      ],
      mode: chartAgg('io'),
      yFmt: (v) => compactNumber(v.round()),
    );

    // 4. Bandwidth rx/tx
    final net = mk(
      _extract(pts, [(s) => s.rxKibS, (s) => s.txKibS]),
      [
        ChartSeriesStyle(label: '↓ ${t(context, 'Down', '下行', zhHk: '下行')}', color: MColors.chartViolet2, format: netRate),
        ChartSeriesStyle(label: '↑ ${t(context, 'Up', '上行', zhHk: '上行')}', color: MColors.chartRed1, format: netRate),
      ],
      mode: chartAgg('net'),
      yFmt: netRate,
    );

    // 5. SWAP used (raw; 0-max cap = swap total)
    double? swapTotal;
    for (final p in pts.reversed) {
      if (p.swapTotalMb > 0) {
        swapTotal = p.swapTotalMb;
        break;
      }
    }
    final swap = mk(
      _extract(pts, [(s) => s.swapUsedMb]),
      [ChartSeriesStyle(label: 'SWAP', color: MColors.chartGreen2, format: mbTotal)],
      mode: 'raw',
      fMin: 0,
      fMax: swapTotal,
      yFmt: mbTotal,
    );

    // 6. Per-mount disk usage: one chart per mount point (web diskChartData),
    // discovered realtime-first then newest-history-first; 0-max cap is that
    // disk's total_gb. History merges the newest realtime sample so the charts
    // stay live.
    var diskPts = pts;
    final rt = _realtime.value;
    if (historical && rt != null) {
      final lastT = pts.isEmpty ? null : pts.last.time;
      if (rt.time != null && (lastT == null || rt.time!.isAfter(lastT))) {
        diskPts = [...pts, rt];
      }
    }
    final diskDefs = <DiskInfo>[];
    void addDisk(DiskInfo d) {
      if (!diskDefs.any((e) => e.mp == d.mp)) diskDefs.add(d);
    }

    if (rt != null) {
      for (final d in rt.disks ?? const <DiskInfo>[]) {
        addDisk(d);
      }
    }
    for (final p in pts.reversed) {
      for (final d in p.disks ?? const <DiskInfo>[]) {
        addDisk(d);
      }
    }

    final diskCards = <Widget>[];
    for (var i = 0; i < diskDefs.length; i++) {
      final def = diskDefs[i];
      final data = mk(
        _extract(diskPts, [
          (s) {
            for (final d in s.disks ?? const <DiskInfo>[]) {
              if (d.mp == def.mp) return d.usedGb;
            }
            return null;
          }
        ]),
        [ChartSeriesStyle(label: 'Disk ${i + 1}', color: MColors.chartOrange2, format: gb)],
        mode: 'raw',
        fMin: 0,
        fMax: def.totalGb,
        yFmt: gb,
      );
      diskCards.add(card('Disk ${i + 1} · ${def.mp}', [], data));
    }
    if (diskDefs.isEmpty) {
      diskCards.add(card(t(context, 'Disk usage', '磁盘用量', zhHk: '磁碟用量'), [], null));
    }

    return [
      card(t(context, 'CPU', 'CPU', zhHk: 'CPU'), [], cpu, modeKey: 'cpu'),
      card(
          t(context, 'Memory', '内存', zhHk: '記憶體'),
          [
            _legendChip(MColors.chartGreen2, t(context, 'Used', '已用', zhHk: '已用')),
            _legendChip(MColors.chartGreen1, t(context, 'Total', '总量', zhHk: '總量')),
          ],
          mem),
      card(
          t(context, 'Disk IO', '磁盘 IO', zhHk: '磁碟 I/O'),
          [
            _legendChip(MColors.chartBlue2, t(context, 'Read', '读取', zhHk: '讀取')),
            _legendChip(MColors.chartYellow2, t(context, 'Write', '写入', zhHk: '寫入')),
          ],
          io,
          modeKey: 'io'),
      card(
          t(context, 'Disk IOPS', '磁盘 IOPS', zhHk: '磁碟 IOPS'),
          [
            _legendChip(MColors.chartBlue1, t(context, 'R IOPS', '读 IOPS', zhHk: '讀 IOPS')),
            _legendChip(MColors.chartYellow1, t(context, 'W IOPS', '写 IOPS', zhHk: '寫 IOPS')),
          ],
          ioIops,
          modeKey: 'io'),
      card(
          t(context, 'Bandwidth', '带宽', zhHk: '頻寬'),
          [
            _legendChip(MColors.chartViolet2, t(context, 'Down', '下行', zhHk: '下行')),
            _legendChip(MColors.chartRed1, t(context, 'Up', '上行', zhHk: '上行')),
          ],
          net,
          modeKey: 'net'),
      card(t(context, 'SWAP', 'SWAP', zhHk: 'SWAP'), [], swap),
      ...diskCards,
    ];
  }
}

/// One chart card: title with optional per-chart aggregation selector
/// (web monitor-chart.tsx header select), 160-high line chart, legend chips.
class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.legend,
    required this.data,
    this.loading = false,
    this.mode,
    this.onModeChanged,
  });

  final String title;
  final List<Widget> legend;
  final LineChartData? data;
  final bool loading;

  /// Current per-chart aggregation; null hides the selector.
  final String? mode;
  final ValueChanged<String>? onModeChanged;

  static const _modeLabels = {
    'avg': ['Avg', '平均', '平均值'],
    'max': ['Max', '最大', '最大值'],
    'raw': ['Raw', '原始', '原始數據'],
  };

  @override
  Widget build(BuildContext context) {
    final header = Row(
      children: [
        Expanded(
          child: Text(title,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ),
        if (mode != null && onModeChanged != null) _modeSelector(context),
      ],
    );
    return MCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: 10),
          loading
              ? const SizedBox(height: 160, child: Center(child: Skeleton(width: double.infinity, height: 140, radius: 8)))
              : SizedBox(
                  height: 160,
                  child: data == null
                      ? EmptyState(
                          text: t(context, 'No data yet', '暂无数据', zhHk: '暫無數據'),
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

  Widget _modeSelector(BuildContext context) {
    final current = _modeLabels.containsKey(mode) ? mode! : 'avg';
    return PopupMenuButton<String>(
      initialValue: current,
      tooltip: t(context, 'Aggregation', '聚合方式', zhHk: '匯總方式'),
      padding: EdgeInsets.zero,
      onSelected: onModeChanged,
      itemBuilder: (context) => [
        for (final entry in _modeLabels.entries)
          PopupMenuItem(
            value: entry.key,
            height: 38,
            child: Text(t(context, entry.value[0], entry.value[1], zhHk: entry.value[2]),
                style: const TextStyle(fontSize: 13)),
          ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            t(context, _modeLabels[current]![0], _modeLabels[current]![1],
                zhHk: _modeLabels[current]![2]),
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const Icon(Icons.arrow_drop_down, size: 18),
        ],
      ),
    );
  }
}
