import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/controllers.dart';
import '../state/session.dart';
import '../theme/mcolors.dart';
import 'widgets.dart';

/// App shell: top header (branding + language/theme/avatar menu) and the
/// bottom navigation with 4 tabs (Dashboard / Terminal / Keychain / More).
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
          IconButton(
            tooltip: 'Language',
            onPressed: () => ref.read(localeControllerProvider.notifier).toggle(),
            icon: Text(
              ref.watch(localeControllerProvider) == 'en' ? 'EN' : '中',
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
                      t(context, 'Profile', '个人资料')),
                  _item('settings', Icons.settings_outlined,
                      t(context, 'Settings', '设置')),
                  _item('about', Icons.info_outline,
                      t(context, 'About', '关于')),
                  const PopupMenuDivider(),
                  _item('github', Icons.code, 'GitHub'),
                  _item('docs', Icons.menu_book_outlined,
                      t(context, 'Documentation', '文档')),
                  _item('issue', Icons.bug_report_outlined,
                      t(context, 'Report Issue', '反馈问题')),
                  if (sess.user?.isAdmin ?? false) ...[
                    const PopupMenuDivider(),
                    _item('admin', Icons.admin_panel_settings_outlined,
                        t(context, 'Admin Dashboard', '管理后台')),
                  ],
                  const PopupMenuDivider(),
                  PopupMenuItem<String>(
                    value: 'logout',
                    child: Row(
                      children: [
                        const Icon(Icons.logout, size: 18, color: MColors.offline),
                        const SizedBox(width: 10),
                        Text(t(context, 'Sign Out', '退出登录'),
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
                  label: t(context, 'Dashboard', '概览'),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.terminal_outlined),
                  selectedIcon: const Icon(Icons.terminal),
                  label: t(context, 'Terminal', '终端'),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.key_outlined),
                  selectedIcon: const Icon(Icons.key),
                  label: t(context, 'Keychain', '密钥'),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.menu),
                  label: t(context, 'More', '更多'),
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
