import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_services.dart';
import '../../core/models/models.dart';
import '../../core/state/display_config.dart';
import '../../core/theme/mcolors.dart';
import '../../core/widgets/widgets.dart';

final _emailRe =
    RegExp(r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  // notification settings
  bool _loadingNotif = true;
  bool _savingNotif = false;
  List<String> _emails = [];
  final _emailCtrl = TextEditingController();
  List<_PushRow> _pushes = [];

  // display settings (local editable copy)
  late final DisplayConfig _display;
  bool _savingDisplay = false;

  ApiServices get _api => ref.read(apiProvider);

  @override
  void initState() {
    super.initState();
    final cfg = ref.read(displayConfigProvider);
    _display = DisplayConfig()
      ..defaultTimeFrame = cfg.defaultTimeFrame
      ..autoRefresh = cfg.autoRefresh
      ..monitorMode = cfg.monitorMode
      ..minMaxMode = cfg.minMaxMode
      ..monitorLayout = cfg.monitorLayout
      ..dashboardLayout = cfg.dashboardLayout
      ..showDetails = cfg.showDetails
      ..terminalRenderer = cfg.terminalRenderer;
    _loadNotifications();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    for (final p in _pushes) {
      p.dispose();
    }
    super.dispose();
  }

  Future<void> _loadNotifications() async {
    try {
      final list = await _api.notificationList();
      if (!mounted) return;
      setState(() {
        _emails = [
          for (final n in list)
            if (n.module == 'email') n.target,
        ];
        _pushes = [
          for (final n in list)
            if (n.module == 'shoutrrr') _PushRow(n.target),
        ];
        _loadingNotif = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingNotif = false);
    }
  }

  // -------------------------------------------------------- email targets

  void _addEmail(String value) {
    final email = value.trim();
    if (email.isEmpty) return;
    if (!_emailRe.hasMatch(email)) {
      toastWarn(context, t(context, 'Invalid email address', '邮箱格式不正确',
          zhHk: '電郵地址無效'));
      return;
    }
    if (_emails.contains(email)) {
      toastWarn(context, t(context, 'Already added', '已添加', zhHk: '已新增'));
      return;
    }
    setState(() {
      _emails = [..._emails, email];
      _emailCtrl.clear();
    });
  }

  // ----------------------------------------------------------- push (shoutrrr)

  Future<void> _addPush() async {
    // Template strings must match the web verbatim
    // (notification-settings.tsx:233-244) so users can follow web docs.
    final templates = <(String, String)>[
      ('Telegram', 'telegram://[TOKEN]@telegram?chats=[@channel-1]'),
      ('Discord', 'discord://[token]@[id]'),
      ('Slack', 'slack://[botname@][token-a]/[token-b]/[token-c]'),
      (
        'Teams',
        'teams://[group]@[tenant]/[altId]/[groupOwner]?host=[organization].webhook.office.com'
      ),
      (t(context, 'Custom URL', '自定义 URL', zhHk: '自訂 URL'), ''),
    ];
    final template = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(t(context, 'Choose a template', '选择模板', zhHk: '選擇範本')),
        children: [
          for (final tp in templates)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(tp.$2),
              child: Text(tp.$1),
            ),
        ],
      ),
    );
    if (template == null || !mounted) return;
    setState(() => _pushes = [..._pushes, _PushRow(template)]);
  }

  void _removePush(_PushRow row) {
    setState(() {
      _pushes = [..._pushes]..remove(row);
    });
    row.dispose();
  }

  Future<void> _testPush(String url) async {
    try {
      await _api.notificationTest(url);
      if (mounted) {
        toastSuccess(context,
            t(context, 'Test sent', '测试已发送', zhHk: '測試已傳送'));
      }
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _saveNotifications() async {
    if (_savingNotif) return;
    if (_pushes.any((p) => p.controller.text.trim().isEmpty)) {
      toastWarn(context, t(context, 'Push URL cannot be empty', '推送 URL 不能为空',
          zhHk: '推送 URL 不能為空'));
      return;
    }
    final targets = <NotificationTarget>[
      for (final e in _emails) NotificationTarget(module: 'email', target: e),
      for (final p in _pushes)
        NotificationTarget(module: 'shoutrrr', target: p.controller.text.trim()),
    ];
    setState(() => _savingNotif = true);
    try {
      for (final tg in targets) {
        await _api.notificationValidate(tg);
      }
      await _api.notificationUpdate(targets);
      if (!mounted) return;
      toastSuccess(context);
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _savingNotif = false);
    }
  }

  // ----------------------------------------------------------- display save

  Future<void> _saveDisplay() async {
    if (_savingDisplay) return;
    setState(() => _savingDisplay = true);
    try {
      await ref.read(displayConfigProvider.notifier).update(_display);
      if (mounted) toastSuccess(context);
    } catch (_) {
      if (mounted) {
        toastError(context,
            t(context, 'Failed to save', '保存失败', zhHk: '儲存失敗'));
      }
    } finally {
      if (mounted) setState(() => _savingDisplay = false);
    }
  }

  // ----------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t(context, 'Settings', '设置', zhHk: '設定'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            PageHeader(
                title: t(context, 'Settings', '设置', zhHk: '設定'),
                description: t(context, 'Notifications and display preferences',
                    '通知与显示偏好', zhHk: '通知與顯示偏好')),
            FadeSlideIn(child: _notificationCard()),
            const SizedBox(height: 16),
            FadeSlideIn(delay: 60, child: _displayCard()),
          ],
        ),
      ),
    );
  }

  // 1. notifications
  Widget _notificationCard() {
    final theme = Theme.of(context);
    return MCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: MColors.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.notifications_outlined,
                    size: 18, color: MColors.warning),
              ),
              const SizedBox(width: 10),
              Text(t(context, 'Notification Settings', '通知设置',
                      zhHk: '通知設定'),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            t(context,
                'Get notified when a server goes offline or recovers. On the web client, right-click a card in the Monitor Dashboard to add an alert.',
                '服务器离线或恢复时接收通知。在网页端可右键监控仪表盘卡片添加告警。',
                zhHk: '伺服器離線或恢復時接收通知。在網頁端可右鍵點擊總覽卡片以新增警示。'),
            style: TextStyle(
                fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          // Web parity (notification-settings.tsx:133-140): the global email
          // prerequisite is key setup information.
          Text(
            t(context,
                'Before configuring alerts, make sure this instance has a global email configuration — otherwise alerts cannot be sent.',
                '配置告警前，请确保实例已配置全局邮件，否则告警将无法发送。',
                zhHk: '設定警示前，請確保實例已設定全域電郵，否則警示將無法傳送。'),
            style: TextStyle(
                fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          Text(t(context, 'Email targets', '邮件目标', zhHk: '電郵目標'),
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (_emails.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final email in _emails)
                  InputChip(
                    label: Text(email, style: const TextStyle(fontSize: 12)),
                    onDeleted: () =>
                        setState(() => _emails = [..._emails]..remove(email)),
                  ),
              ],
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            onSubmitted: _addEmail,
            decoration: InputDecoration(
              labelText: t(context, 'Add email address', '添加邮箱地址',
                  zhHk: '新增電郵地址'),
              hintText: 'you@example.com',
              isDense: true,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.add, size: 20),
                onPressed: () => _addEmail(_emailCtrl.text),
              ),
            ),
          ),
          const Divider(height: 24),
          Row(
            children: [
              Text(t(context, 'Push (Shoutrrr)', '推送（Shoutrrr）',
                      zhHk: '推送（Shoutrrr）'),
                  style:
                      const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton.icon(
                onPressed: _addPush,
                icon: const Icon(Icons.add, size: 18),
                label: Text(t(context, 'Add', '添加', zhHk: '新增'),
                    style: const TextStyle(fontSize: 13)),
              ),
            ],
          ),
          if (_loadingNotif)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Center(
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            )
          else if (_pushes.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                t(context, 'No push targets yet — add one with a template.',
                    '还没有推送目标 — 使用模板添加一个。',
                    zhHk: '還沒有推送目標 — 使用範本新增一個。'),
                style: TextStyle(
                    fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
              ),
            )
          else
            for (final row in _pushes)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: row.controller,
                        style: monoStyle(context, size: 12),
                        decoration: InputDecoration(
                          isDense: true,
                          border: const OutlineInputBorder(),
                          hintText: 'telegram://[TOKEN]@telegram?chats=[@channel-1]',
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact),
                      onPressed: () => _testPush(row.controller.text.trim()),
                      child: Text(t(context, 'Test', '测试', zhHk: '測試'),
                          style: const TextStyle(fontSize: 12)),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.delete_outline,
                          size: 20, color: theme.colorScheme.error),
                      onPressed: () => _removePush(row),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: 8),
          LoadingButton(
            label: t(context, 'Save', '保存', zhHk: '儲存'),
            loading: _savingNotif,
            onPressed: _saveNotifications,
          ),
        ],
      ),
    );
  }

  // 2. display
  Widget _displayCard() {
    final theme = Theme.of(context);
    return MCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.tune,
                    size: 18, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 10),
              Text(t(context, 'Display Settings', '显示设置', zhHk: '顯示設定'),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 14),
          _label(t(context, 'Monitor layout', '监控页布局', zhHk: '監察頁面版面')),
          SegmentedButton<String>(
            selected: {_display.monitorLayout},
            segments: [
              ButtonSegment(
                  value: 'grid-3',
                  label: Text(t(context, 'Grid 3', '3 列', zhHk: '3 欄'))),
              ButtonSegment(
                  value: 'grid-2',
                  label: Text(t(context, 'Grid 2', '2 列', zhHk: '2 欄'))),
              ButtonSegment(
                  value: 'list',
                  label: Text(t(context, 'List', '列表', zhHk: '清單'))),
            ],
            onSelectionChanged: (s) =>
                setState(() => _display.monitorLayout = s.first),
          ),
          const SizedBox(height: 14),
          _label(t(context, 'Default time frame', '默认时间范围',
              zhHk: '預設時間範圍')),
          DropdownButtonFormField<String>(
            initialValue: _display.defaultTimeFrame,
            isDense: true,
            decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'real-time', child: Text('Real-time')),
              DropdownMenuItem(value: '1h', child: Text('1H')),
              DropdownMenuItem(value: '12h', child: Text('12H')),
              DropdownMenuItem(value: '24h', child: Text('24H')),
              DropdownMenuItem(value: '7d', child: Text('7D')),
              DropdownMenuItem(value: '30d', child: Text('30D')),
              DropdownMenuItem(value: '365d', child: Text('365D')),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() => _display.defaultTimeFrame = v);
            },
          ),
          const SizedBox(height: 14),
          _label(t(context, 'Aggregation', '聚合方式', zhHk: '匯總方式')),
          SegmentedButton<String>(
            selected: {_display.monitorMode},
            segments: [
              ButtonSegment(
                  value: 'avg',
                  label: Text(t(context, 'Avg', '平均', zhHk: '平均'))),
              ButtonSegment(
                  value: 'max',
                  label: Text(t(context, 'Max', '最大', zhHk: '最大'))),
              ButtonSegment(
                  value: 'raw',
                  label: Text(t(context, 'Raw', '原始', zhHk: '原始'))),
            ],
            onSelectionChanged: (s) =>
                setState(() => _display.monitorMode = s.first),
          ),
          const SizedBox(height: 14),
          _label(t(context, 'Y-axis', 'Y 轴范围', zhHk: 'Y 軸範圍')),
          SegmentedButton<String>(
            selected: {_display.minMaxMode},
            segments: const [
              ButtonSegment(value: 'min-auto', label: Text('Min-Auto')),
              ButtonSegment(value: '0-auto', label: Text('0-Auto')),
              ButtonSegment(value: '0-max', label: Text('0-Max')),
            ],
            onSelectionChanged: (s) =>
                setState(() => _display.minMaxMode = s.first),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(t(context, 'Auto refresh', '自动刷新',
                zhHk: '自動重新整理'),
                style: const TextStyle(fontSize: 13)),
            value: _display.autoRefresh,
            onChanged: (v) => setState(() => _display.autoRefresh = v),
          ),
          const SizedBox(height: 14),
          _label(t(context, 'Dashboard layout', '仪表盘布局', zhHk: '總覽版面')),
          SegmentedButton<String>(
            selected: {_display.dashboardLayout},
            segments: [
              ButtonSegment(
                  value: 'grid',
                  label: Text(t(context, 'Grid', '网格', zhHk: '網格'))),
              ButtonSegment(
                  value: 'list',
                  label: Text(t(context, 'List', '列表', zhHk: '清單'))),
              ButtonSegment(
                  value: 'list2',
                  label: Text(t(context, 'List 2', '列表 2', zhHk: '清單 2'))),
            ],
            onSelectionChanged: (s) =>
                setState(() => _display.dashboardLayout = s.first),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(t(context, 'Always show details', '始终显示详情',
                zhHk: '一律顯示詳情'),
                style: const TextStyle(fontSize: 13)),
            value: _display.showDetails,
            onChanged: (v) => setState(() => _display.showDetails = v),
          ),
          const SizedBox(height: 14),
          // Web parity (display-settings.tsx:171-190): terminal renderer
          // choice. The app terminal only implements xterm, so ghostty-web is
          // not selectable here — an honest mobile limitation.
          _label(t(context, 'Terminal renderer', '终端渲染器',
              zhHk: '終端機渲染器')),
          SegmentedButton<String>(
            selected: {_display.terminalRenderer},
            segments: const [
              ButtonSegment(value: 'xterm', label: Text('xterm.js')),
            ],
            onSelectionChanged: null,
          ),
          const SizedBox(height: 4),
          Text(
            t(context,
                'The app always uses xterm. The Ghostty Web renderer is web-only (WebAssembly).',
                'App 固定使用 xterm 渲染；Ghostty Web 渲染器为网页端专属（WebAssembly）。',
                zhHk: 'App 固定使用 xterm 渲染；Ghostty Web 渲染器為網頁端專屬（WebAssembly）。'),
            style: TextStyle(
                fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          LoadingButton(
            label: t(context, 'Save', '保存', zhHk: '儲存'),
            loading: _savingDisplay,
            onPressed: _saveDisplay,
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      );
}

class _PushRow {
  _PushRow(String text) : controller = TextEditingController(text: text);

  final TextEditingController controller;

  void dispose() => controller.dispose();
}
