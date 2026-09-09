import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router.dart';
import 'core/state/controllers.dart';
import 'core/theme/theme.dart';

/// Parses 'zh-CN' into Locale(zh, CN) — Locale('zh-CN') would create a
/// malformed locale whose languageCode is the literal string 'zh-CN'.
Locale parseLocale(String code) {
  final parts = code.split('-');
  return parts.length > 1 && parts[1].isNotEmpty
      ? Locale(parts[0], parts[1])
      : Locale(parts[0]);
}

class MosonaManagerApp extends ConsumerWidget {
  const MosonaManagerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeControllerProvider);
    final locale = parseLocale(ref.watch(localeControllerProvider));

    return MaterialApp.router(
      title: 'Mosona Manager',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: MosunaTheme.light(),
      darkTheme: MosunaTheme.dark(),
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('zh', 'CN'), Locale('zh', 'HK')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: ref.watch(routerProvider),
    );
  }
}
