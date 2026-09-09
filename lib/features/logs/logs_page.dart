import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, File;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mosona_manager/core/api/api_services.dart';
import 'package:mosona_manager/core/models/models.dart' as m;
import 'package:mosona_manager/core/theme/mcolors.dart';
import 'package:mosona_manager/core/utils/format.dart';
import 'package:mosona_manager/core/widgets/widgets.dart';
import 'package:share_plus/share_plus.dart';

/// Audit logs (team at /logs, admin at /admin/logs via [admin]).
/// Cursor pagination with filter + debounced search controls.
class LogsPage extends ConsumerStatefulWidget {
  const LogsPage({super.key, this.admin = false});

  final bool admin;

  @override
  ConsumerState<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends ConsumerState<LogsPage> {
  static const _userCategories = ['all', 'team', 'server', 'terminal', 'category'];
  static const _adminCategories = ['all', 'user', 'oauth', 'settings'];
  static const _levels = ['all', 'low', 'medium', 'high'];
  static const _ranges = [1, 7, 30, 90, 365];
  static const _pageSizes = [20, 50, 100, 500, 1000];

  final _emailCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  Timer? _debounce;

  String _category = 'all';
  String _level = 'all';
  int _days = 30;
  int _pageSize = 20;
  bool _filtersOpen = true;

  final List<String> _cursorStack = [];
  int _pageNumber = 1;

  List<m.AuditLog>? _logs;
  String _nextCursor = '';
  bool _hasMore = false;
  bool _loading = true;

  bool get _messageActive => _messageCtrl.text.trim().isNotEmpty;

  /// Backend rejects a >30-day span combined with a message filter.
  int get _effectiveDays => _messageActive ? math.min(_days, 30) : _days;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _emailCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      if (_messageActive && _days > 30) setState(() => _days = 30);
      _resetAndLoad();
    });
  }

  Future<void> _resetAndLoad() async {
    _cursorStack.clear();
    _pageNumber = 1;
    await _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final page = await _fetchPage(
          cursor: _cursorStack.isEmpty ? null : _cursorStack.last,
          pageSize: _pageSize);
      if (!mounted) return;
      setState(() {
        _logs = page.logs;
        _nextCursor = page.nextCursor;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _logs ??= const [];
        _loading = false;
      });
      showApiError(context, e);
    }
  }

  Future<m.LogsPage> _fetchPage({String? cursor, required int pageSize}) {
    final now = DateTime.now();
    return _fetchPageRange(cursor: cursor, pageSize: pageSize, end: now);
  }

  Future<m.LogsPage> _fetchPageRange({
    String? cursor,
    required int pageSize,
    required DateTime end,
  }) {
    final now = end;
    return ref.read(apiProvider).logsList(
          cursor: cursor,
          pageSize: pageSize,
          category: _category,
          level: _level,
          email: _emailCtrl.text.trim(),
          message: _messageCtrl.text.trim(),
          start: now.subtract(Duration(days: _effectiveDays)),
          end: now,
          admin: widget.admin,
        );
  }

  Map<String, dynamic> _logJson(m.AuditLog l) => {
        'user_id': l.userId,
        'username': l.username,
        'email': l.email,
        'category': l.category,
        'message': l.message,
        'ip': l.ip,
        'ip_country': l.ipCountry,
        'ip_country_code': l.ipCountryCode,
        'user_agent': l.userAgent,
        'level': l.level,
        'time': l.time?.toIso8601String(),
      };

  // ------------------------------------------------------------------ export

  Future<void> _export() async {
    final limit = await showDialog<int>(
      context: context,
      builder: (dialogContext) => const _ExportDialog(),
    );
    if (limit == null || !mounted) return;

    final navigator = Navigator.of(context);
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5)),
            const SizedBox(width: 16),
            Text(t(context, 'Exporting…', '导出中…')),
          ],
        ),
      ),
    ));
    try {
      // Keep one range end for both fetching and the exported filters
      // (web uses its mount-time rangeEnd, logs/index.tsx:143-158).
      final end = DateTime.now();
      final rawLogs = <Map<String, dynamic>>[];
      String? cursor;
      var hasMore = true;
      while (rawLogs.length < limit && hasMore) {
        final remaining = limit - rawLogs.length;
        final page = await _fetchPageRange(
            cursor: cursor, pageSize: math.min(remaining, 1000), end: end);
        for (final l in page.logs) {
          rawLogs.add(_logJson(l));
        }
        if (page.logs.isEmpty) break;
        hasMore = page.hasMore && page.nextCursor.isNotEmpty;
        cursor = page.nextCursor.isEmpty ? null : page.nextCursor;
      }
      final bundle = {
        'exported_at': DateTime.now().toUtc().toIso8601String(),
        'source': widget.admin ? 'admin' : 'team',
        'requested_limit': limit,
        'exported_count': rawLogs.length,
        'filters': {
          'category': _category,
          'level': _level,
          'email': _emailCtrl.text.trim(),
          'message': _messageCtrl.text.trim(),
          'range_days': _effectiveDays,
          'range_end': end.toUtc().toIso8601String(),
        },
        'logs': rawLogs,
      };
      final payload =
          '${const JsonEncoder.withIndent('  ').convert(bundle)}\n';
      final fileName =
          '${widget.admin ? 'admin-' : ''}logs-export-${DateFormat('yyyy-MM-dd').format(end)}.json';
      navigator.pop();
      // Land the export as a real .json file (web downloads
      // logs-export-YYYY-MM-DD.json); the share sheet receives the file.
      final file = File(
          '${Directory.systemTemp.path}/$fileName');
      await file.writeAsString(payload, flush: true);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        subject: fileName,
      ));
      try {
        await file.delete();
      } catch (_) {}
    } catch (e) {
      navigator.pop();
      if (mounted) showApiError(context, e);
    }
  }

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final logs = _logs;

    return Scaffold(
      appBar: AppBar(
        title: Text(t(context, widget.admin ? 'Admin Logs' : 'Logs',
            widget.admin ? '管理日志' : '日志')),
        actions: [
          IconButton(
            tooltip: t(context, 'Export', '导出'),
            onPressed: _export,
            icon: const Icon(Icons.ios_share),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _resetAndLoad,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _filtersCard(theme),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  t(context, 'Page $_pageNumber', '第 $_pageNumber 页'),
                  style:
                      const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (_loading)
                  const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
            const SizedBox(height: 10),
            if (logs == null)
              ...List.generate(
                5,
                (_) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: MCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: const [
                        Row(
                          children: [
                            Skeleton(width: 44, height: 18, radius: 9),
                            Spacer(),
                            Skeleton(width: 110, height: 11),
                          ],
                        ),
                        SizedBox(height: 8),
                        Skeleton(height: 13),
                        SizedBox(height: 6),
                        Skeleton(height: 13),
                        SizedBox(height: 8),
                        Skeleton(width: 180, height: 11),
                      ],
                    ),
                  ),
                ),
              )
            else if (logs.isEmpty)
              EmptyState(
                text: t(context, 'No logs match the current filters.',
                    '没有符合当前筛选条件的日志。'),
                icon: Icons.receipt_long_outlined,
              )
            else
              ...List.generate(
                logs.length,
                (i) => _logCard(theme, logs[i], i),
              ),
            const SizedBox(height: 16),
            _pager(theme),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------------- filters

  Widget _filtersCard(ThemeData theme) {
    final categories = widget.admin ? _adminCategories : _userCategories;
    return MCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _filtersOpen = !_filtersOpen),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(Icons.filter_alt_outlined,
                      size: 16, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Text(t(context, 'Filters', '筛选'),
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  AnimatedRotation(
                    turns: _filtersOpen ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.keyboard_arrow_down,
                        size: 18, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          if (_filtersOpen) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _dropdown<String>(
                    value: _category,
                    items: [
                      for (final c in categories)
                        (
                          c,
                          Text(_catLabel(c),
                              style: const TextStyle(fontSize: 13),
                              overflow: TextOverflow.ellipsis)
                        ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _category = v);
                      _resetAndLoad();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _dropdown<String>(
                    value: _level,
                    items: [
                      for (final lv in _levels) (lv, _levelItem(theme, lv)),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _level = v);
                      _resetAndLoad();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _dropdown<int>(
                    value: _effectiveDays,
                    items: [
                      for (final d in _ranges)
                        (
                          d,
                          Text(
                            t(context, '$d days', '$d 天'),
                            style: TextStyle(
                              fontSize: 13,
                              color: !_messageActive || d <= 30
                                  ? null
                                  : theme.disabledColor,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _days = v);
                      _resetAndLoad();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _dropdown<int>(
                    value: _pageSize,
                    items: [
                      for (final s in _pageSizes)
                        (
                          s,
                          Text(t(context, '$s / page', '$s 条/页'),
                              style: const TextStyle(fontSize: 13),
                              overflow: TextOverflow.ellipsis)
                        ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _pageSize = v);
                      _resetAndLoad();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _emailCtrl,
              onChanged: (_) => _onSearchChanged(),
              decoration: _searchInput(theme, Icons.alternate_email,
                  t(context, 'Search by email', '按邮箱搜索')),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _messageCtrl,
              onChanged: (_) => _onSearchChanged(),
              decoration: _searchInput(theme, Icons.search,
                  t(context, 'Search in message', '搜索消息内容')),
            ),
          ],
        ],
      ),
    );
  }

  InputDecoration _searchInput(
      ThemeData theme, IconData icon, String hint) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, size: 18),
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      prefixIconColor: theme.colorScheme.onSurfaceVariant,
    );
  }

  Widget _dropdown<T>({
    required T value,
    required List<(T, Widget)> items,
    required ValueChanged<T?> onChanged,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          isDense: true,
          borderRadius: BorderRadius.circular(10),
          padding: const EdgeInsets.symmetric(vertical: 10),
          icon: Icon(Icons.expand_more,
              size: 18, color: theme.colorScheme.onSurfaceVariant),
          items: [
            for (final (v, child) in items)
              DropdownMenuItem<T>(value: v, child: child),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  String _catLabel(String c) {
    if (c == 'all') return t(context, 'All', '全部');
    return c[0].toUpperCase() + c.substring(1);
  }

  Widget _levelItem(ThemeData theme, String level) {
    final color = switch (level) {
      'low' => MColors.logLow,
      'medium' => MColors.logMedium,
      'high' => MColors.logHigh,
      _ => null,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: color == null
                ? Border.all(color: theme.colorScheme.onSurfaceVariant)
                : null,
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(_catLabel(level),
              style: const TextStyle(fontSize: 13),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  // -------------------------------------------------------------- log cards

  Color _levelColor(String level) => switch (level) {
        'high' => MColors.logHigh,
        'medium' => MColors.logMedium,
        _ => MColors.logLow,
      };

  String _levelLabel(String level) {
    if (level.isEmpty) return 'Low';
    return level[0].toUpperCase() + level.substring(1);
  }

  Widget _logCard(ThemeData theme, m.AuditLog log, int index) {
    final time = log.time == null
        ? '--'
        : DateFormat('yyyy-MM-dd HH:mm').format(log.time!.toLocal());
    final (browser, osName) = uaSummary(log.userAgent);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: FadeSlideIn(
        delay: math.min(index * 30, 300),
        child: MCard(
          onLongPress:
              log.userAgent.isEmpty ? null : () => _showUaDialog(log),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  MBadge(
                    small: true,
                    color: _levelColor(log.level),
                    child: Text(_levelLabel(log.level)),
                  ),
                  const SizedBox(width: 8),
                  MBadge(
                    small: true,
                    color: theme.colorScheme.onSurfaceVariant,
                    child: Text(log.category,
                        overflow: TextOverflow.ellipsis),
                  ),
                  const Spacer(),
                  Text(time,
                      style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
              if (log.email.isNotEmpty || log.username.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  log.email.isEmpty
                      ? log.username
                      : '${log.email} (${log.username})',
                  style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 6),
              Text(log.message, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 8),
              Divider(height: 1, color: theme.dividerColor),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.public,
                      size: 12, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  FlagIcon(countryCode: log.ipCountryCode, size: 12),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      log.ipCountry.isEmpty
                          ? log.ip
                          : '${log.ip}  ${log.ipCountry}',
                      style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.computer,
                      size: 12, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text('$browser · $osName',
                        style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showUaDialog(m.AuditLog log) => showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(t(context, 'User Agent', '用户代理')),
          content: SelectableText(
            log.userAgent,
            style: monoStyle(context, size: 11)
                .copyWith(fontWeight: FontWeight.w400),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(t(context, 'Close', '关闭')),
            ),
          ],
        ),
      );

  // ------------------------------------------------------------------- pager

  Widget _pager(ThemeData theme) {
    final canPrev = _cursorStack.isNotEmpty && !_loading;
    final canNext = _hasMore && _nextCursor.isNotEmpty && !_loading;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: !canPrev
                ? null
                : () {
                    setState(() {
                      _cursorStack.removeLast();
                      _pageNumber--;
                    });
                    _load();
                  },
            icon: const Icon(Icons.chevron_left, size: 18),
            label: Text(t(context, 'Previous', '上一页')),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Icon(Icons.more_horiz,
              size: 18, color: theme.colorScheme.onSurfaceVariant),
        ),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: !canNext
                ? null
                : () {
                    setState(() {
                      _cursorStack.add(_nextCursor);
                      _pageNumber++;
                    });
                    _load();
                  },
            icon: const Icon(Icons.chevron_right, size: 18),
            label: Text(t(context, 'Next', '下一页')),
          ),
        ),
      ],
    );
  }
}

/// Export dialog: count input validated in [1,1000]; pops with the parsed
/// limit, or shows a warning toast and stays open on invalid values
/// (web page/logs/index.tsx:174-179).
class _ExportDialog extends StatefulWidget {
  const _ExportDialog();

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  final _controller = TextEditingController(text: '100');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final v = int.tryParse(_controller.text.trim());
    if (v == null || v <= 0 || v > 1000) {
      toastWarn(context,
          t(context, 'Please enter a valid number of records.', '请输入有效的记录数'));
      return;
    }
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t(context, 'Export logs', '导出日志')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t(context,
                'Fetch the most recent entries matching the current filters and share them as JSON.',
                '按当前筛选条件获取最近的记录，并以 JSON 分享。'),
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: t(context, 'Count (1-1000)', '数量（1-1000）'),
              isDense: true,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(t(context, 'Cancel', '取消')),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(t(context, 'Export', '导出')),
        ),
      ],
    );
  }
}
