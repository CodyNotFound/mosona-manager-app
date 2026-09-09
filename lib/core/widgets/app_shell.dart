import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/api_services.dart';
import '../sse/sse_client.dart' show MonitorConn, monitorProvider;
import '../state/controllers.dart';
import '../state/session.dart';
import '../theme/mcolors.dart';
import 'widgets.dart';

/// App shell: top header (branding + connection status + language/theme/
/// avatar menu) and the bottom navigation with 4 tabs
/// (Dashboard / Terminal / Keychain / More).
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (ref.read(sessionProvider).status == SessionStatus.bootstrapping) {
        ref.read(sessionProvider.notifier).bootstrap();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final shell = widget.shell;
    final sess = ref.watch(sessionProvider);
    final bootstrapping = sess.status == SessionStatus.bootstrapping;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Mosona Manager',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        actions: [
          // Server connection indicator (web app/connect-checker.tsx).
          const _ConnectChecker(),
          IconButton(
            tooltip: ref.watch(localeControllerProvider),
            onPressed: () => ref.read(localeControllerProvider.notifier).toggle(),
            icon: Text(
              switch (ref.watch(localeControllerProvider)) {
                'zh-CN' => '简',
                'zh-HK' => '繁',
                _ => 'EN',
              },
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            tooltip: 'Theme',
            onPressed: () => ref.read(themeControllerProvider.notifier).toggle(),
            icon: Icon(theme.brightness == Brightness.dark
                ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined),
          ),
          if (!bootstrapping && sess.isLoggedIn)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: PopupMenuButton<String>(
                offset: const Offset(0, 48),
                icon: Gravatar(email: sess.user?.email ?? '', size: 30),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onSelected: (value) async {
                  switch (value) {
                    case 'profile':
                      context.push('/profile');
                    case 'settings':
                      context.push('/settings');
                    case 'about':
                      context.push('/about');
                    case 'github':
                      launchExternal(
                          'https://github.com/mosona-labs/mosona-manager');
                    case 'docs':
                      launchExternal('https://manager.mosona.cc/docs/quickstart');
                    case 'issue':
                      launchExternal(
                          'https://github.com/mosona-labs/mosona-manager/issues');
                    case 'admin':
                      context.push('/admin');
                    case 'logout':
                      await ref.read(sessionProvider.notifier).logout();
                  }
                },
                itemBuilder: (context) => [
                  _item('profile', Icons.person_outline,
                      t(context, 'Profile', '个人资料', zhHk: '個人檔案')),
                  // web parity: API tokens placeholder (user.tsx "Coming Soon")
                  PopupMenuItem<String>(
                    enabled: false,
                    child: Row(
                      children: [
                        const Icon(Icons.api_outlined, size: 18),
                        const SizedBox(width: 10),
                        Text(t(context, 'API (Coming Soon)', 'API（即将推出）',
                            zhHk: 'API（即將推出）')),
                      ],
                    ),
                  ),
                  _item('settings', Icons.settings_outlined,
                      t(context, 'Settings', '设置', zhHk: '設定')),
                  _item('about', Icons.info_outline,
                      t(context, 'About', '关于', zhHk: '關於')),
                  const PopupMenuDivider(),
                  _item('github', Icons.code, 'GitHub'),
                  _item('docs', Icons.menu_book_outlined,
                      t(context, 'Documentation', '文档', zhHk: '文件')),
                  _item('issue', Icons.bug_report_outlined,
                      t(context, 'Report Issue', '反馈问题', zhHk: '回報問題')),
                  if (sess.user?.isAdmin ?? false) ...[
                    const PopupMenuDivider(),
                    _item('admin', Icons.admin_panel_settings_outlined,
                        t(context, 'Admin Dashboard', '管理后台', zhHk: '管理後台')),
                  ],
                  const PopupMenuDivider(),
                  PopupMenuItem<String>(
                    value: 'logout',
                    child: Row(
                      children: [
                        const Icon(Icons.logout, size: 18, color: MColors.offline),
                        const SizedBox(width: 10),
                        Text(t(context, 'Sign Out', '退出登录', zhHk: '登出'),
                            style: const TextStyle(color: MColors.offline)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      body: bootstrapping
          ? const Center(child: CircularProgressIndicator())
          : shell,
      bottomNavigationBar: bootstrapping
          ? null
          : NavigationBar(
              selectedIndex: shell.currentIndex,
              onDestinationSelected: (i) => shell.goBranch(
                i,
                initialLocation: i == shell.currentIndex,
              ),
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.dashboard_outlined),
                  selectedIcon: const Icon(Icons.dashboard),
                  label: t(context, 'Dashboard', '概览', zhHk: '總覽'),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.terminal_outlined),
                  selectedIcon: const Icon(Icons.terminal),
                  label: t(context, 'Terminal', '终端', zhHk: '終端機'),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.key_outlined),
                  selectedIcon: const Icon(Icons.key),
                  label: t(context, 'Keychain', '密钥', zhHk: '密鑰庫'),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.menu),
                  label: t(context, 'More', '更多', zhHk: '更多'),
                ),
              ],
            ),
    );
  }

  PopupMenuItem<String> _item(String value, IconData icon, String label) =>
      PopupMenuItem<String>(
        value: value,
        child: Row(
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 10),
            Text(label),
          ],
        ),
      );
}

/// Server connection indicator, mirroring web app/connect-checker.tsx:
/// pings /api/ping every 15s, keeps the last 10 latencies and shows a bar
/// chart popover. The dot also turns red when the monitor SSE stream is lost.
class _ConnectChecker extends ConsumerStatefulWidget {
  const _ConnectChecker();

  @override
  ConsumerState<_ConnectChecker> createState() => _ConnectCheckerState();
}

class _ConnectCheckerState extends ConsumerState<_ConnectChecker> {
  /// Latency history; 0 = not measured yet, -1 = failed, >0 = milliseconds.
  static const _historyLength = 10;
  final List<int> _pings = List.filled(_historyLength, 0, growable: true);
  bool _pingOk = false;
  Timer? _timer;

  /// Captured in initState so dispose() never touches ref (unsafe unmounted).
  late final ValueNotifier<MonitorConn> _conn;

  @override
  void initState() {
    super.initState();
    // Touching the notifier starts the monitor SSE subscription whose conn
    // state feeds the dot (green on live events, red when lost/revoked).
    _conn = ref.read(monitorProvider.notifier).conn;
    _conn.addListener(_onConnChanged);
    unawaited(_ping());
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _ping());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _conn.removeListener(_onConnChanged);
    super.dispose();
  }

  void _onConnChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _ping() async {
    final watch = Stopwatch()..start();
    var ok = false;
    try {
      await ref.read(apiProvider).ping();
      ok = true;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _pingOk = ok;
      _pings.add(ok ? watch.elapsedMilliseconds : -1);
      while (_pings.length > _historyLength) {
        _pings.removeAt(0);
      }
    });
  }

  bool get _connected {
    final sse = ref.read(monitorProvider.notifier).conn.value;
    return _pingOk && sse != MonitorConn.lost;
  }

  int get _latest => _pings.isEmpty ? 0 : _pings.last;

  double? get _averageMs {
    final ok = _pings.where((p) => p > 0).toList();
    if (ok.isEmpty) return null;
    return ok.reduce((a, b) => a + b) / ok.length;
  }

  void _showSheet() {
    showMSheet(
      context: context,
      title: t(context, 'Network Status', '网络状态', zhHk: '網絡狀態'),
      child: _buildSheetBody(Theme.of(context)),
    );
  }

  Widget _buildSheetBody(ThemeData theme) {
    final latest = _latest;
    final avg = _averageMs;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          latest < 0
              ? t(context, 'Ping failed', 'Ping 失败', zhHk: 'Ping 失敗')
              : latest == 0
                  ? 'N/A'
                  : '$latest ms',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Text(
          avg == null
              ? t(context, 'Failed', '失败', zhHk: '失敗')
              : '${avg.toStringAsFixed(2)} ms',
          style: TextStyle(
              fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            for (final p in _pings) ...[
              Container(
                width: 7,
                height: p >= 0
                    ? (p / 10).clamp(4.0, 40.0).toDouble()
                    : 4,
                decoration: BoxDecoration(
                  color: p > 0
                      ? MColors.online
                      : p == 0
                          ? theme.colorScheme.onSurfaceVariant
                          : MColors.offline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 4),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _connected
              ? t(context, 'Connected', '已连接', zhHk: '已連線')
              : t(context, 'Disconnected', '连接断开', zhHk: '連線中斷'),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _connected ? MColors.online : MColors.offline,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final connected = _connected;
    return IconButton(
      tooltip: connected
          ? t(context, 'Connected', '已连接', zhHk: '已連線')
          : t(context, 'Disconnected', '连接断开', zhHk: '連線中斷'),
      onPressed: _showSheet,
      icon: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: connected ? MColors.online : MColors.offline,
          boxShadow: [
            BoxShadow(
              color: (connected ? MColors.online : MColors.offline)
                  .withValues(alpha: 0.4),
              blurRadius: 6,
            ),
          ],
        ),
      ),
    );
  }
}
