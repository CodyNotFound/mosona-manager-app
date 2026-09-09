import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosona_manager/app.dart';
import 'package:mosona_manager/core/state/controllers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('app boots and lands on the sign-in screen when logged out',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
        child: const MosonaManagerApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mosona Manager'), findsWidgets);
  });

  test('locale controller persists and reports zh', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    final initial = container.read(localeControllerProvider);
    expect(initial, anyOf('en', 'zh-CN'));

    container.read(localeControllerProvider.notifier).set('zh-CN');
    expect(container.read(localeControllerProvider), 'zh-CN');
    expect(container.read(localeControllerProvider.notifier).isZh, isTrue);
    expect(prefs.getString('mosona-app-locale'), 'zh-CN');

    container.read(localeControllerProvider.notifier).toggle();
    expect(container.read(localeControllerProvider), 'en');
  });

  test('theme + server config controllers persist values', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    container.read(themeControllerProvider.notifier).set(ThemeMode.dark);
    expect(container.read(themeControllerProvider), ThemeMode.dark);
    expect(prefs.getString('mosona-app-theme'), 'dark');

    container.read(serverConfigProvider.notifier).set('https://mgr.example.com/');
    expect(container.read(serverConfigProvider), 'https://mgr.example.com');
  });
}
