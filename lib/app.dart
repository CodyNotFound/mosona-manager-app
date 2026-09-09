import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router.dart';
import 'core/state/controllers.dart';
import 'core/theme/theme.dart';

/// Root widget: wires theme mode + locale into MaterialApp.router.
class MosonaManagerApp extends ConsumerWidget {
  const MosonaManagerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeControllerProvider);
    final locale = ref.watch(localeControllerProvider);

    return MaterialApp.router(
      title: 'Mosona Manager',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: MosunaTheme.light(),
      darkTheme: MosunaTheme.dark(),
      locale: Locale(locale),
      supportedLocales: const [Locale('en'), Locale('zh-CN')],
      routerConfig: ref.watch(routerProvider),
    );
  }
}
