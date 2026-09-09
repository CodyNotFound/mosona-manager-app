import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mosona_manager/core/state/session.dart';
import 'package:mosona_manager/core/theme/mcolors.dart';
import 'package:mosona_manager/core/widgets/widgets.dart';
import '../../core/terminal/terminal.dart'
    show TerminalPhase, TerminalSession;
import '../../core/terminal/terminal.dart' show terminalManagerProvider;

/// "More" tab: the mobile nav hub replacing the web sidebar groups —
/// account/team card plus open terminal sessions, Security / Manage / Other
/// sections.
class MorePage extends ConsumerWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sess = ref.watch(sessionProvider);
    final theme = Theme.of(context);
    final mgr = ref.watch(terminalManagerProvider);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            PageHeader(
              title: t(context, 'More', '更多'),
              description: t(context, 'Account, security and settings', '账户、安全与设置'),
            ),
            FadeSlideIn(child: _userCard(context, ref, sess)),
            const SizedBox(height: 16),
            // Open terminal sessions quick list (web sidebar parity).
            ListenableBuilder(
              listenable: mgr,
              builder: (context, _) {
                final sessions = mgr.list;
                if (sessions.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label(theme, t(context, 'Open sessions', '打开的会话')),
                    const SizedBox(height: 8),
                    MCard(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      child: Column(
                        children: [
                          for (var i = 0; i < sessions.length; i++) ...[
                            if (i > 0)
                              Divider(
                                  height: 1,
                                  indent: 46,
                                  color: theme.dividerColor),
                            _sessionTile(context, ref, sessions[i]),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                );
              },
            ),
            _label(theme, t(context, 'Security', '安全')),
            const SizedBox(height: 8),
            FadeSlideIn(
              delay: 60,
              child: _group(context, [
                _navTile(context, Icons.receipt_long_outlined,
                    t(context, 'Logs', '日志'),
                    route: '/logs'),
              ]),
            ),
            const SizedBox(height: 16),
            _label(theme, t(context, 'Manage', '管理')),
            const SizedBox(height: 8),
            FadeSlideIn(
              delay: 120,
              child: _group(context, [
                _navTile(context, Icons.groups_outlined, t(context, 'Team', '团队'),
                    route: '/team'),
                _navTile(context, Icons.public,
                    t(context, 'Public Page', '公开页'),
                    route: '/public-page'),
                _navTile(context, Icons.person_outline,
                    t(context, 'Profile', '个人资料'),
                    route: '/profile'),
                _navTile(context, Icons.settings_outlined,
                    t(context, 'Settings', '设置'),
                    route: '/settings'),
              ]),
            ),
            const SizedBox(height: 16),
            _label(theme, t(context, 'Other', '其他')),
            const SizedBox(height: 8),
            FadeSlideIn(
              delay: 180,
              child: _group(context, [
                _navTile(context, Icons.info_outline, t(context, 'About', '关于'),
                    route: '/about'),
                if (sess.user?.isAdmin ?? false)
                  _navTile(context, Icons.admin_panel_settings_outlined,
                      t(context, 'Admin Dashboard', '管理后台'),
                      route: '/admin'),
                _navTile(context, Icons.code, 'GitHub',
                    url: 'https://github.com/mosona-labs/mosona-manager'),
                _navTile(context, Icons.menu_book_outlined,
                    t(context, 'Documentation', '文档'),
                    url: 'https://manager.mosona.cc/docs/quickstart'),
                _navTile(context, Icons.bug_report_outlined,
                    t(context, 'Report Issue', '反馈问题'),
                    url: 'https://github.com/mosona-labs/mosona-manager/issues'),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------ terminal sessions

  (String, Color) _phaseLabel(BuildContext context, TerminalPhase phase) => switch (phase) {
        TerminalPhase.connected =>
          (t(context, 'connected', '已连接'), MColors.online),
        TerminalPhase.connecting =>
          (t(context, 'connecting…', '连接中…'), MColors.warning),
        TerminalPhase.reconnecting =>
          (t(context, 'reconnecting…', '重连中…'), MColors.warning),
        TerminalPhase.disconnected =>
          (t(context, 'disconnected', '已断开'), MColors.offline),
        TerminalPhase.revoked =>
          (t(context, 'revoked', '已吊销'), MColors.offline),
        TerminalPhase.failed =>
          (t(context, 'failed', '失败'), MColors.offline),
      };

  Widget _sessionTile(BuildContext context, WidgetRef ref, TerminalSession session) {
    final theme = Theme.of(context);
    final (phaseLabel, phaseColor) = _phaseLabel(context, session.phase);
    return ListTile(
      dense: true,
      leading: Stack(
        alignment: Alignment.bottomRight,
        children: [
          const Icon(Icons.terminal_outlined, size: 22),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: phaseColor,
            ),
          ),
        ],
      ),
      title: Text(
        session.server.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14),
      ),
      subtitle: Text(phaseLabel, style: TextStyle(fontSize: 11, color: phaseColor)),
      trailing: IconButton(
        visualDensity: VisualDensity.compact,
        tooltip: t(context, 'Close session', '关闭会话'),
        icon: Icon(Icons.close, size: 18, color: theme.colorScheme.onSurfaceVariant),
        onPressed: () => ref.read(terminalManagerProvider).close(session.id),
      ),
      onTap: () => context.push('/session/${session.id}'),
    );
  }

  // -------------------------------------------------------------- user card

  Widget _userCard(BuildContext context, WidgetRef ref, SessionState sess) {
    final theme = Theme.of(context);
    final user = sess.user;
    final email = user?.email ?? '';
    final team = sess.team;
    final teams = sess.teams;
    final currentId = team?.id;
    final hasCurrent = currentId != null && teams.any((tm) => tm.id == currentId);

    return MCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Gravatar(email: email, size: 46),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.username ?? '--',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        email,
                        style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: theme.dividerColor),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.groups_outlined,
                  size: 16, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: hasCurrent ? currentId : null,
                    isDense: true,
                    isExpanded: true,
                    borderRadius: BorderRadius.circular(10),
                    hint: Text(
                      t(context, 'No team', '无团队'),
                      style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                    icon: Icon(Icons.expand_more,
                        size: 18, color: theme.colorScheme.onSurfaceVariant),
                    items: [
                      for (final tm in teams)
                        DropdownMenuItem<int>(
                          value: tm.id,
                          child: Text(
                            tm.name,
                            style: const TextStyle(fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      DropdownMenuItem<int>(
                        value: -1,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.add, size: 16, color: MColors.link),
                            const SizedBox(width: 6),
                            Text(
                              t(context, 'Create new team', '创建新团队'),
                              style: const TextStyle(
                                  fontSize: 13, color: MColors.link),
                            ),
                          ],
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      if (v == -1) {
                        context.push('/create-team');
                        return;
                      }
                      _switchTeam(context, ref, v);
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _switchTeam(BuildContext context, WidgetRef ref, int teamId) async {
    try {
      await ref.read(sessionProvider.notifier).switchTeam(teamId);
      await ref.read(teamDataProvider.notifier).refresh();
      if (context.mounted) toastSuccess(context);
    } catch (e) {
      if (context.mounted) showApiError(context, e);
    }
  }

  // --------------------------------------------------------------- sections

  Widget _label(ThemeData theme, String text) {
    return Text(
      text,
      style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
    );
  }

  Widget _group(BuildContext context, List<Widget> tiles) {
    final theme = Theme.of(context);
    final children = <Widget>[];
    for (var i = 0; i < tiles.length; i++) {
      children.add(tiles[i]);
      if (i < tiles.length - 1) {
        children.add(Divider(height: 1, indent: 46, color: theme.dividerColor));
      }
    }
    return MCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(children: children),
    );
  }

  Widget _navTile(
    BuildContext context,
    IconData icon,
    String label, {
    String? route,
    String? url,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 22),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      trailing: Icon(
        route != null ? Icons.chevron_right : Icons.open_in_new,
        size: route != null ? 20 : 14,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      onTap: () {
        if (route != null) {
          context.push(route);
        } else if (url != null) {
          launchExternal(url);
        }
      },
    );
  }
}
