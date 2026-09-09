/// Chart building helpers for the monitor page (fl_chart 1.2).
///
/// Series share a time axis (x = epoch seconds). Samples can be downsampled
/// into buckets (`avg` / `max` / `raw` aggregation, web parity), and the line
/// breaks (via [FlSpot.nullSpot]) wherever the distance between consecutive
/// valid samples exceeds 2.5x the median sampling gap.
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// Visual style + value formatter of one plotted series.
class ChartSeriesStyle {
  const ChartSeriesStyle({
    required this.label,
    required this.color,
    required this.format,
    this.strokeWidth = 2,
    this.dashArray,
  });

  final String label;
  final Color color;
  final double strokeWidth;
  final List<int>? dashArray;
  final String Function(double) format;
}

/// Time-aligned multi-series samples.
class SeriesData {
  SeriesData(this.xs, this.columns);

  /// Epoch seconds, ascending.
  final List<double> xs;

  /// One column per series, aligned index-wise with [xs] (null = missing).
  final List<List<double?>> columns;

  bool get isEmpty => xs.isEmpty;
}

/// Evenly chunks the samples into at most [buckets] groups and aggregates each
/// group into a single point: `avg` -> mean, `max` -> peak. `raw` keeps every
/// sample un-bucketed (web parity: raw draws the full data without windowing).
SeriesData downsampleSeries(SeriesData d, int buckets, String mode) {
  final n = d.xs.length;
  if (mode == 'raw' || buckets <= 0 || n <= buckets) return d;
  final xs = <double>[];
  final cols = List.generate(d.columns.length, (_) => <double?>[]);
  for (var b = 0; b < buckets; b++) {
    final start = (b * n / buckets).floor();
    final end = ((b + 1) * n / buckets).floor().clamp(start + 1, n);
    var sum = 0.0;
    for (var i = start; i < end; i++) {
      sum += d.xs[i];
    }
    xs.add(sum / (end - start));
    for (var c = 0; c < d.columns.length; c++) {
      cols[c].add(_aggregate(d.columns[c], start, end, mode));
    }
  }
  return SeriesData(xs, cols);
}

double? _aggregate(List<double?> col, int start, int end, String mode) {
  switch (mode) {
    case 'max':
      double? max;
      for (var i = start; i < end; i++) {
        final v = col[i];
        if (v != null && (max == null || v > max)) max = v;
      }
      return max;
    case 'raw':
      double? last;
      for (var i = start; i < end; i++) {
        final v = col[i];
        if (v != null) last = v;
      }
      return last;
    default: // avg
      var sum = 0.0;
      var cnt = 0;
      for (var i = start; i < end; i++) {
        final v = col[i];
        if (v != null) {
          sum += v;
          cnt++;
        }
      }
      return cnt == 0 ? null : sum / cnt;
  }
}

/// Builds spots, inserting [FlSpot.nullSpot] (line break) where the gap
/// between consecutive valid samples exceeds 2.5x the median gap.
List<FlSpot> buildSpots(List<double> xs, List<double?> ys) {
  final gaps = <double>[];
  for (var i = 1; i < xs.length; i++) {
    final g = xs[i] - xs[i - 1];
    if (g > 0) gaps.add(g);
  }
  gaps.sort();
  final median = gaps.isEmpty ? 0.0 : gaps[gaps.length ~/ 2];
  final threshold = median <= 0 ? double.infinity : median * 2.5;

  final spots = <FlSpot>[];
  double? lastX;
  var broken = false;
  for (var i = 0; i < xs.length; i++) {
    final y = ys[i];
    if (y == null) {
      broken = true;
      continue;
    }
    final lx = lastX;
    if (lx != null && (broken || xs[i] - lx > threshold)) {
      spots.add(FlSpot.nullSpot);
    }
    spots.add(FlSpot(xs[i], y));
    lastX = xs[i];
    broken = false;
  }
  return spots;
}

/// Placeholder chart for empty data.
LineChartData emptyChart() => LineChartData(
      minY: 0,
      maxY: 1,
      titlesData: const FlTitlesData(show: false),
      gridData: const FlGridData(show: false),
      borderData: FlBorderData(show: false),
      lineTouchData: const LineTouchData(enabled: false),
    );

/// Renders a multi-series time chart: formatted axis titles, light dashed
/// horizontal grid, optional reference lines and a labeled touch tooltip.
LineChartData buildTimeChart(
  BuildContext context, {
  required SeriesData data,
  required List<ChartSeriesStyle> styles,
  String minMaxMode = '0-auto',
  double? fixedMinY,
  double? fixedMaxY,
  double? fixedMinX,
  double? fixedMaxX,
  required String Function(double) yFormat,
  required String Function(double) xFormat,
  double? xInterval,
  List<HorizontalLine> extraHorizontalLines = const [],
}) {
  if (data.isEmpty) return emptyChart();
  final theme = Theme.of(context);
  final titleStyle =
      TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant);
  final gridColor = theme.dividerColor;

  var dataMax = 0.0;
  var dataMin = 0.0;
  var first = true;
  for (final col in data.columns) {
    for (final v in col) {
      if (v == null) continue;
      if (first) {
        dataMin = v;
        dataMax = v;
        first = false;
      } else {
        if (v > dataMax) dataMax = v;
        if (v < dataMin) dataMin = v;
      }
    }
  }

  final minY = fixedMinY ?? (minMaxMode == 'min-auto' ? null : 0.0);
  final maxY =
      fixedMaxY ?? (minMaxMode == '0-max' ? (dataMax <= 0 ? 1.0 : dataMax) : null);
  // Fixed time window (web: [now - windowLength, now]) keeps the axis from
  // collapsing onto the data when samples are sparse.
  final minX = fixedMinX ?? data.xs.first;
  final maxX = fixedMaxX ?? data.xs.last;
  final span = maxX - minX;

  return LineChartData(
    minX: minX,
    maxX: maxX,
    minY: minY,
    maxY: maxY,
    lineBarsData: [
      for (var c = 0; c < data.columns.length; c++)
        LineChartBarData(
          spots: buildSpots(data.xs, data.columns[c]),
          color: styles[c].color,
          barWidth: styles[c].strokeWidth,
          dashArray: styles[c].dashArray,
          isCurved: false,
          dotData: const FlDotData(show: false),
        ),
    ],
    titlesData: FlTitlesData(
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 56,
          getTitlesWidget: (v, meta) => SideTitleWidget(
            meta: meta,
            child: Text(yFormat(v), style: titleStyle),
          ),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 22,
          interval: xInterval ?? (span > 0 ? span / 4 : null),
          getTitlesWidget: (v, meta) => SideTitleWidget(
            meta: meta,
            child: Text(xFormat(v), style: titleStyle),
          ),
        ),
      ),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    ),
    gridData: FlGridData(
      drawVerticalLine: false,
      getDrawingHorizontalLine: (_) =>
          FlLine(color: gridColor, strokeWidth: 0.5, dashArray: const [4, 4]),
    ),
    borderData: FlBorderData(show: false),
    extraLinesData: ExtraLinesData(horizontalLines: extraHorizontalLines),
    lineTouchData: LineTouchData(
      enabled: true,
      touchTooltipData: LineTouchTooltipData(
        fitInsideHorizontally: true,
        maxContentWidth: 200,
        getTooltipItems: (touched) => [
          for (final s in touched)
            LineTooltipItem(
              '${styles[s.barIndex].label} ${styles[s.barIndex].format(s.y)}',
              TextStyle(
                color: styles[s.barIndex].color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    ),
  );
}
