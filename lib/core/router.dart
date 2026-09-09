import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/about/about_page.dart';
import '../features/admin/admin_dashboard_page.dart';
import '../features/admin/admin_home_page.dart';
import '../features/admin/admin_logs_stub_page.dart';
import '../features/admin/admin_settings_email_page.dart';
import '../features/admin/admin_settings_general_page.dart';
import '../features/admin/admin_settings_oauth_page.dart';
import '../features/admin/admin_settings_register_page.dart';
import '../features/admin/admin_users_page.dart';
import '../features/auth/init_page.dart';
import '../features/auth/signin_page.dart';
import '../features/auth/twofa_page.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/dashboard/server_form_page.dart';
import '../features/keychain/keychain_page.dart';
import '../features/logs/logs_page.dart';
import '../features/monitor/monitor_page.dart';
import '../features/more/more_page.dart';
import '../features/profile/profile_page.dart';
import '../features/public_page/public_page_page.dart';
import '../features/settings/settings_page.dart';
import '../features/team/create_team_page.dart';
import '../features/team/team_page.dart';
import '../features/terminal/session_page.dart';
import '../features/terminal/terminal_page.dart';
import 'state/session.dart';
import 'widgets/app_shell.dart';

/// Public (auth-free) routes.
const _publicRoutes = {'/auth', '/2fa', '/init'};

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(sessionProvider.select((s) => s.status), (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    refreshListenable: refresh,
    initialLocation: '/',
    redirect: (context, state) {
      final sess = ref.read(sessionProvider);
      final path = state.matchedLocation;
      final isPublic = _publicRoutes.any(path.startsWith);

      if (sess.status == SessionStatus.bootstrapping) {
        return isPublic ? null : '/';
      }
      if (sess.needsInit) return path == '/init' ? null : '/init';
      if (!sess.isLoggedIn) return isPublic ? null : '/auth';
      if (isPublic && path != '/2fa') return '/';
      if (!sess.hasTeam &&
          !_publicRoutes.contains(path) &&
          path != '/create-team' &&
          path != '/profile' &&
          path != '/settings' &&
          path != '/about' &&
          !path.startsWith('/admin')) {
        return '/create-team';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/auth',
        builder: (context, state) => const SignInPage(),
      ),
      GoRoute(
        path: '/2fa',
        builder: (context, state) => const TwoFaPage(),
      ),
      GoRoute(
        path: '/init',
        builder: (context, state) => const InitPage(),
      ),
      GoRoute(
        path: '/session/:id',
        builder: (context, state) => SessionPage(sessionId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/monitor/:id',
        builder: (context, state) =>
            MonitorPage(serverId: int.parse(state.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/server-form',
        builder: (context, state) {
          final serverId = state.uri.queryParameters['id'];
          return ServerFormPage(
            editServerId: serverId == null ? null : int.tryParse(serverId),
            copyFrom: state.extra as Map<String, dynamic>?,
          );
        },
      ),
      GoRoute(path: '/create-team', builder: (c, s) => const CreateTeamPage()),
      GoRoute(path: '/team', builder: (c, s) => const TeamPage()),
      GoRoute(path: '/public-page', builder: (c, s) => const PublicPagePage()),
      GoRoute(path: '/profile', builder: (c, s) => const ProfilePage()),
      GoRoute(path: '/settings', builder: (c, s) => const SettingsPage()),
      GoRoute(path: '/about', builder: (c, s) => const AboutPage()),
      GoRoute(
        path: '/logs',
        builder: (c, s) => LogsPage(admin: s.uri.queryParameters['admin'] == '1'),
      ),
      // admin section
      GoRoute(path: '/admin', builder: (c, s) => const AdminHomePage()),
      GoRoute(path: '/admin/dashboard', builder: (c, s) => const AdminDashboardPage()),
      GoRoute(path: '/admin/users', builder: (c, s) => const AdminUsersPage()),
      GoRoute(path: '/admin/logs', builder: (c, s) => const AdminLogsPage()),
      GoRoute(
          path: '/admin/settings/general',
          builder: (c, s) => const AdminSettingsGeneralPage()),
      GoRoute(
          path: '/admin/settings/email',
          builder: (c, s) => const AdminSettingsEmailPage()),
      GoRoute(
          path: '/admin/settings/register-login',
          builder: (c, s) => const AdminSettingsRegisterPage()),
      GoRoute(
          path: '/admin/settings/oauth',
          builder: (c, s) => const AdminSettingsOauthPage()),
      // bottom-tab shell (kept last so deeper paths match earlier routes first)
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/', builder: (c, s) => const DashboardPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/terminal', builder: (c, s) => const TerminalPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/keychain', builder: (c, s) => const KeychainPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/more', builder: (c, s) => const MorePage()),
          ]),
        ],
      ),
    ],
  );
});
