// Full-app walk-through against the live local demo hub.
// Run: flutter test integration_test/app_walk_test.dart -d <simulator-udid>
//
// Covers: manual login -> live dashboard (SSE) -> monitor charts -> terminal
// session (WS connect) -> keychain/logs/team/profile/settings pages ->
// admin section -> logout -> login again.
//
// Extended coverage: server-form reachability, category manage sheet,
// keychain add/delete round-trip, team switcher, logs filters + pager,
// admin users list, trilingual toggle and the 404 page.
//
// Assertions rely on backend data (server names, emails, team name) and
// widget types (charts, switches) instead of page-specific label strings.
@Timeout(Duration(minutes: 8))
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mosona_manager/app.dart';
import 'package:mosona_manager/core/state/controllers.dart';
import 'package:mosona_manager/core/widgets/widgets.dart'
    show Gravatar, PageHeader;
import 'package:shared_preferences/shared_preferences.dart';

const _email = String.fromEnvironment('MOSONA_DEMO_EMAIL',
    defaultValue: 'admin@mosona.local');
const _pass = String.fromEnvironment('MOSONA_DEMO_PASS',
    defaultValue: 'Mosona-Demo-2026!');
const _url =
    String.fromEnvironment('MOSONA_DEMO_URL', defaultValue: 'http://localhost:3214');

Future<void> _boot(WidgetTester tester) async {
  // fresh logged-out state per test (mock values reset the cached instance)
  SharedPreferences.setMockInitialValues({
    'mosona-app-locale': 'en',
    'mosona-app-server-url': _url,
  });
  await tester.pumpWidget(const MosonaManagerAppRoot());
  await tester.pump(const Duration(seconds: 5));
}

/// Types email/password into the sign-in form and submits.
Future<void> _login(WidgetTester tester) async {
  final fields = find.byType(TextField);
  expect(fields, findsAtLeastNWidgets(3)); // url + email + password
  await tester.enterText(fields.at(1), _email);
  await tester.pump();
  await tester.enterText(fields.at(2), _pass);
  await tester.pump();

  final button = find.byType(FilledButton).first;
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pump(const Duration(seconds: 6));
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('login -> dashboard shows live SSE data', (tester) async {
    await _boot(tester);

    // cold start lands on sign-in (email field present, no server cards)
    expect(find.text('probe-alpine-1'), findsNothing);

    await _login(tester);

    await tester.pump(const Duration(seconds: 6));
    expect(find.text('probe-alpine-1'), findsWidgets);
    expect(find.text('probe-alpine-2'), findsWidgets);
    expect(find.text('online'), findsWidgets);
    expect(find.text('Live'), findsWidgets);
  });

  testWidgets('monitor detail renders info card + charts', (tester) async {
    await _boot(tester);
    await _login(tester);
    await tester.pump(const Duration(seconds: 6));

    await tester.tap(find.text('probe-alpine-2').first);
    await tester.pump(const Duration(seconds: 10));

    expect(find.byType(LineChart), findsAtLeastNWidgets(4));
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);

    await tester.pageBack();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('terminal tab opens a live SSH session', (tester) async {
    await _boot(tester);
    await _login(tester);
    await tester.pump(const Duration(seconds: 6));

    await tester.tap(find.text('Terminal').first);
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('probe-alpine-1'), findsWidgets);

    await tester.tap(find.text('probe-alpine-1').first);
    await tester.pump(const Duration(seconds: 12));
    expect(find.textContaining('Connected'), findsWidgets);

    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('keychain / more hub / logs / team / profile / settings / admin',
      (tester) async {
    await _boot(tester);
    await _login(tester);
    await tester.pump(const Duration(seconds: 6));

    // Keychain tab renders (add affordance + empty state or key cards)
    await tester.tap(find.text('Keychain').first);
    await tester.pump(const Duration(seconds: 3));
    expect(find.byIcon(Icons.add), findsWidgets);

    // More hub lists team switcher and section entries
    await tester.tap(find.text('More').first);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Demo Team'), findsWidgets);

    // Logs page shows entries from the backend (email on log cards)
    await tester.tap(find.text('Logs'));
    await tester.pump(const Duration(seconds: 6));
    expect(find.textContaining('@mosona.local'), findsWidgets);
    await tester.pageBack();
    await tester.pump(const Duration(seconds: 1));

    // Team page shows the team and its member
    await tester.tap(find.text('More').first);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Team'));
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Demo Team'), findsWidgets);
    expect(find.text('admin@mosona.local'), findsWidgets);
    await tester.pageBack();
    await tester.pump(const Duration(seconds: 1));

    // Profile shows the account
    await tester.tap(find.text('More').first);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Profile'));
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('admin@mosona.local'), findsWidgets);
    await tester.pageBack();
    await tester.pump(const Duration(seconds: 1));

    // Settings renders switches (notification + display)
    await tester.tap(find.text('More').first);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Settings'));
    await tester.pump(const Duration(seconds: 4));
    expect(find.byType(Switch), findsWidgets);
    await tester.pageBack();
    await tester.pump(const Duration(seconds: 1));

    // Admin dashboard renders stats + charts (admin-only entry)
    await tester.tap(find.text('More').first);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Admin Dashboard'));
    await tester.pump(const Duration(seconds: 5));
    expect(find.byType(LineChart), findsAtLeastNWidgets(1));
  });

  testWidgets('logout returns to sign-in; login again works', (tester) async {
    await _boot(tester);
    await _login(tester);
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('probe-alpine-1'), findsWidgets); // logged in

    await tester.tap(find.byType(Gravatar).first);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Sign Out'));
    await tester.pump(const Duration(seconds: 8));

    // back on the sign-in screen: email field is back
    expect(find.byType(TextField), findsAtLeastNWidgets(2));

    // login again
    await _login(tester);
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('probe-alpine-1'), findsWidgets);
  });

  testWidgets('dashboard FAB opens the server form (no submit)', (tester) async {
    await _boot(tester);
    await _login(tester);
    await tester.pump(const Duration(seconds: 6));

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump(const Duration(seconds: 8));

    // Add-mode form shows the SSH connection section (mode defaults to SSH).
    expect(find.text('Add Server'), findsWidgets);
    expect(find.text('Connection'), findsOneWidget);
    expect(find.text('Address'), findsOneWidget);
    expect(find.text('Port'), findsOneWidget);
    expect(find.text('SSH key'), findsOneWidget);

    // Leave without creating anything; back on the dashboard.
    await tester.pageBack();
    await tester.pump(const Duration(seconds: 4));
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('probe-alpine-1'), findsWidgets);
  });

  testWidgets('category manage sheet lists the Probes category', (tester) async {
    await _boot(tester);
    await _login(tester);
    await tester.pump(const Duration(seconds: 6));

    await tester.tap(find.byTooltip('Manage categories'));
    await tester.pump(const Duration(seconds: 4));

    expect(find.text('Manage Categories'), findsOneWidget);
    // Demo hub ships "Default" (hidden first) + "Probes" rows.
    expect(find.text('Probes'), findsAtLeastNWidgets(1));
    expect(find.text('New category'), findsOneWidget);

    // Close via the barrier without mutating any category.
    await tester.tapAt(const Offset(20, 120));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Manage Categories'), findsNothing);
  });

  testWidgets('keychain adds and deletes a real ssh key', (tester) async {
    await _boot(tester);
    await _login(tester);
    await tester.pump(const Duration(seconds: 6));

    await tester.tap(find.text('Keychain').first);
    await tester.pump(const Duration(seconds: 4));

    final keyName = 'e2e-key-${DateTime.now().millisecondsSinceEpoch}';
    const fakeKey = '-----BEGIN OPENSSH PRIVATE KEY-----b3BlbnNzaC1rZXktdjEA'
        'AAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAABFwAAAAdzc2gtcnNhAAAAAwEAAQAAAQEA'
        'tEstTestContentNotARealKey0123456789abcdefghij'
        '-----END OPENSSH PRIVATE KEY-----';

    // Add-sheet: name + fake key content, then save.
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Add key'), findsOneWidget);

    final fields = find.byType(TextField);
    expect(fields, findsAtLeastNWidgets(3)); // name + content + password
    await tester.enterText(fields.at(0), keyName);
    await tester.pump();
    await tester.enterText(fields.at(1), fakeKey);
    await tester.pump();

    final save = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pump(const Duration(seconds: 10));

    // The new key shows up in the list.
    expect(find.text(keyName), findsWidgets);

    // Delete via long-press menu -> confirm dialog (repeat in case an
    // earlier run left a key with the same name behind).
    for (var i = 0; i < 3 && find.text(keyName).evaluate().isNotEmpty; i++) {
      await tester.longPress(find.text(keyName).first);
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.text('Delete').first); // menu tile
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.widgetWithText(FilledButton, 'Delete')); // confirm
      await tester.pump(const Duration(seconds: 10));
    }
    expect(find.text(keyName), findsNothing);
  });

  testWidgets('more page team switcher shows Demo Team', (tester) async {
    await _boot(tester);
    await _login(tester);
    await tester.pump(const Duration(seconds: 6));

    await tester.tap(find.text('More').first);
    await tester.pump(const Duration(seconds: 4));

    // The account card embeds the team dropdown with the current team.
    expect(find.byType(DropdownButton<int>), findsOneWidget);
    expect(find.text('Demo Team'), findsAtLeastNWidgets(1));
  });

  testWidgets('logs filters card, page-size switch and pager states',
      (tester) async {
    await _boot(tester);
    await _login(tester);
    await tester.pump(const Duration(seconds: 6));

    await tester.tap(find.text('More').first);
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.text('Logs'));
    await tester.pump(const Duration(seconds: 8));

    // Filter card expanded by default, four controls + search fields.
    expect(find.text('Filters'), findsOneWidget);
    expect(find.text('20 / page'), findsOneWidget);
    expect(find.text('Page 1'), findsOneWidget);

    final prev = find.widgetWithText(OutlinedButton, 'Previous');
    final next = find.widgetWithText(OutlinedButton, 'Next');
    expect(prev, findsOneWidget);
    expect(next, findsOneWidget);
    // Page 1 with an empty cursor stack: Previous must be disabled.
    expect(tester.widget<OutlinedButton>(prev).onPressed, isNull);

    // Switch page size 20 -> 50; stays on page 1 and reloads.
    final size = find.text('20 / page');
    await tester.ensureVisible(size);
    await tester.tap(size);
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.text('50 / page').last);
    await tester.pump(const Duration(seconds: 10));
    expect(find.text('50 / page'), findsOneWidget);
    expect(find.text('Page 1'), findsOneWidget);

    // Next is disabled when the backend has no more entries; otherwise it
    // flips to page 2 (and Previous becomes enabled) and back.
    if (tester.widget<OutlinedButton>(next).onPressed != null) {
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.pump(const Duration(seconds: 10));
      expect(find.text('Page 2'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(prev).onPressed, isNotNull);
      await tester.tap(prev);
      await tester.pump(const Duration(seconds: 10));
      expect(find.text('Page 1'), findsOneWidget);
    } else {
      expect(tester.widget<OutlinedButton>(prev).onPressed, isNull);
    }

    await tester.pageBack();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('admin users page lists the admin account', (tester) async {
    await _boot(tester);
    await _login(tester);
    await tester.pump(const Duration(seconds: 6));

    await tester.tap(find.text('More').first);
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.text('Admin Dashboard'));
    await tester.pump(const Duration(seconds: 5));
    await tester.tap(find.text('Users'));
    await tester.pump(const Duration(seconds: 8));

    // The demo hub has a single (admin) user; its row shows the email.
    expect(find.text('admin@mosona.local'), findsAtLeastNWidgets(1));
    expect(find.text('Page 1 / 1'), findsOneWidget);

    await tester.pageBack();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('language button cycles EN -> 简 -> 繁 -> EN', (tester) async {
    await _boot(tester);
    await _login(tester);
    await tester.pump(const Duration(seconds: 6));

    // EN baseline: bottom-nav label and page title both say "Dashboard".
    expect(find.text('EN'), findsOneWidget);
    expect(find.text('Dashboard'), findsAtLeastNWidgets(1));
    expect(find.text('概览'), findsNothing);

    // -> zh-CN
    await tester.tap(find.text('EN'));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('简'), findsOneWidget);
    expect(find.text('概览'), findsAtLeastNWidgets(1));
    expect(find.text('Dashboard'), findsNothing);
    expect(find.text('Keychain'), findsNothing); // now 密钥

    // -> zh-HK (t() falls back to zh unless zhHk is given; the button text
    // '繁' itself proves the zh-HK locale is active)
    await tester.tap(find.text('简'));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('繁'), findsOneWidget);
    expect(find.text('概览'), findsAtLeastNWidgets(1));

    // -> back to EN
    await tester.tap(find.text('繁'));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('EN'), findsOneWidget);
    expect(find.text('Dashboard'), findsAtLeastNWidgets(1));
    expect(find.text('概览'), findsNothing);
  });

  testWidgets('unknown route shows the 404 page and can go back',
      (tester) async {
    await _boot(tester);
    await _login(tester);
    await tester.pump(const Duration(seconds: 6));

    // Push an unmatched location through the real router.
    final router = GoRouter.of(tester.element(find.byType(PageHeader).first));
    router.push('/no-such-route');
    await tester.pump(const Duration(seconds: 5));

    expect(find.text('404'), findsOneWidget);
    expect(find.text('Page not found / 页面不存在'), findsOneWidget);

    await tester.tap(find.text('Go back / 返回'));
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('probe-alpine-1'), findsWidgets);
  });
}

/// Wraps the real app with a ProviderScope over the mock SharedPreferences.
class MosonaManagerAppRoot extends StatelessWidget {
  const MosonaManagerAppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SharedPreferences>(
      future: SharedPreferences.getInstance(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const MaterialApp(
              home: Scaffold(body: Center(child: CircularProgressIndicator())));
        }
        return ProviderScope(
          overrides: [sharedPrefsProvider.overrideWithValue(snap.data!)],
          child: const MosonaManagerApp(),
        );
      },
    );
  }
}
