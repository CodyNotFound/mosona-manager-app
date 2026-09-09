import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_services.dart';
import '../../core/models/models.dart';
import '../../core/theme/mcolors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/widgets.dart';

/// /admin/dashboard — site stats + host CPU/memory charts, 5s polling.
class AdminDashboardPage extends ConsumerStatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  ConsumerState<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends ConsumerState<AdminDashboardPage> {
  static const _cpuWindow = 90; // aggregated points across the 24h window
  static const _memWindow = 10; // raw points

  Timer? _timer;
  AdminDashboardStats? _stats;
  Object? _error;
  String _agg = 'avg';

  ApiServices get _api => ref.read(apiProvider);

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final stats = await _api.adminDashboard();
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error ??= e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t(context, 'Admin Dashboard', '管理后台'))),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_stats == null && _error != null) ...[
                EmptyState(
                  text: t(context, 'Failed to load dashboard', '加载失败'),
                  icon: Icons.error_outline,
                ),
                Center(
                  child: TextButton(
                    onPressed: () {
                      setState(() => _error = null);
                      _load();
                    },
                    child: Text(t(context, 'Retry', '重试')),
                  ),
                ),
              ] else if (_stats == null) ...[
                const Row(children: [
                  Expanded(child: Skeleton(height: 96)),
                  SizedBox(width: 10),
                  Expanded(child: Skeleton(height: 96)),
                ]),
                const SizedBox(height: 10),
                const Row(children: [
                  Expanded(child: Skeleton(height: 96)),
                  SizedBox(width: 10),
                  Expanded(child: Skeleton(height: 96)),
                ]),
                const SizedBox(height: 16),
                const Skeleton(height: 220, radius: 12),
                const SizedBox(height: 12),
                const Skeleton(height: 220, radius: 12),
              ] else ...[
                _statGrid(context, _stats!),
                const SizedBox(height: 16),
                FadeSlideIn(
                  delay: 60,
                  child: MCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                t(context, 'Host CPU % (24h)', '主机 CPU%（24h）'),
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w600),
                              ),
                            ),
                            SegmentedButton<String>(
                              segments: [
                                ButtonSegment(
                                    value: 'avg',
                                    label: Text(t(context, 'Avg', '平均'),
                                        style: const TextStyle(fontSize: 12))),
                                ButtonSegment(
                                    value: 'max',
                                    label: Text(t(context, 'Max', '最大'),
                                        style: const TextStyle(fontSize: 12))),
                              ],
                              selected: {_agg},
                              showSelectedIcon: false,
                              style: const ButtonStyle(
                                  visualDensity: VisualDensity.compact,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                              onSelectionChanged: (s) =>
                                  setState(() => _agg = s.first),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 170,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: Center(
                                    child: Text(
                                      '%',
                                      style: TextStyle(
                                        fontSize: 96,
                                        fontWeight: FontWeight.w800,
                                        color: theme.colorScheme.onSurface
                                            .withValues(alpha: 0.06),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              _percentChart(
                                _cpuSpots(_stats!.system),
                                MColors.chartBlue2,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FadeSlideIn(
                  delay: 120,
                  child: MCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t(context, 'Memory %', '内存%'),
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 170,
                          child: _percentChart(
                            _memSpots(_stats!.system),
                            MColors.chartGreen2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- stats grid

  Widget _statGrid(BuildContext context, AdminDashboardStats s) {
    final tiles = [
      (
        icon: Icons.group,
        color: MColors.chartBlue2,
        label: t(context, 'Total Users', '用户总数'),
        value: compactNumber(s.users),
      ),
      (
        icon: Icons.workspaces_outlined,
        color: MColors.chartBlue1,
        label: t(context, 'Total Teams', '团队总数'),
        value: compactNumber(s.teams),
      ),
      (
        icon: Icons.dns_outlined,
        color: MColors.online,
        label: t(context, 'Total Servers', '服务器总数'),
        value: compactNumber(s.servers),
      ),
      (
        icon: Icons.description_outlined,
        color: MColors.chartOrange2,
        label: t(context, 'Total Records', '记录总数'),
        value: compactNumber(s.records),
      ),
    ];
    return LayoutBuilder(builder: (context, box) {
      const gap = 10.0;
      final w = (box.maxWidth - gap) / 2;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (var i = 0; i < tiles.length; i++)
            SizedBox(
              width: w,
              child: FadeSlideIn(
                delay: i * 60,
                child: StatTile(
                  icon: tiles[i].icon,
                  color: tiles[i].color,
                  label: tiles[i].label,
                  value: tiles[i].value,
                ),
              ),
            ),
        ],
      );
    });
  }

  // ---------------------------------------------------------------- charts

  /// Window + aggregation: raw when few points, otherwise aggregate the
  /// whole 24h series into [_cpuWindow] buckets (avg / max).
  List<FlSpot> _cpuSpots(List<SystemUsagePoint> system) {
    if (system.isEmpty) return const [];
    final spots = <FlSpot>[];
    if (system.length <= _cpuWindow) {
      for (final p in system) {
        spots.add(FlSpot(_epoch(p), p.cpuUsage.clamp(0, 100).toDouble()));
      }
      return spots;
    }
    final chunk = system.length / _cpuWindow;
    for (var i = 0; i < _cpuWindow; i++) {
      final start = (i * chunk).floor();
      var end = ((i + 1) * chunk).ceil();
      if (end <= start) end = start + 1;
      if (end > system.length) end = system.length;
      var sum = 0.0;
      var maxV = double.negativeInfinity;
      for (var j = start; j < end; j++) {
        final v = system[j].cpuUsage;
        sum += v;
        if (v > maxV) maxV = v;
      }
      final y = _agg == 'avg'
          ? sum / math.max(1, end - start)
          : (maxV.isNegative ? 0.0 : maxV);
      spots.add(FlSpot(_epoch(system[end - 1]), y.clamp(0, 100).toDouble()));
    }
    return spots;
  }

  /// Memory: raw last 10 points.
  List<FlSpot> _memSpots(List<SystemUsagePoint> system) {
    if (system.isEmpty) return const [];
    final from = system.length > _memWindow ? system.length - _memWindow : 0;
    return [
      for (final p in system.sublist(from))
        FlSpot(_epoch(p), p.memory.clamp(0, 100).toDouble()),
    ];
  }

  double _epoch(SystemUsagePoint p) =>
      (p.time?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch) /
      1000;

  Widget _percentChart(List<FlSpot> spots, Color color) {
    final theme = Theme.of(context);
    var minX = 0.0;
    var maxX = 1.0;
    if (spots.isNotEmpty) {
      minX = spots.first.x;
      maxX = spots.last.x;
      if (maxX <= minX) maxX = minX + 60;
    }
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: 100,
        minX: minX,
        maxX: maxX,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            color: color,
            barWidth: 2,
            isCurved: false,
            dotData: const FlDotData(show: false),
          ),
        ],
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              interval: 25,
              getTitlesWidget: (v, _) => Text(v.toInt().toString(),
                  style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurfaceVariant)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: math.max((maxX - minX) / 4, 30),
              getTitlesWidget: (v, _) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  DateFormat('HH:mm')
                      .format(DateTime.fromMillisecondsSinceEpoch(
                          (v * 1000).toInt()))
                      .toString(),
                  style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ),
          ),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: const FlGridData(drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: true),
      ),
    );
  }
}
