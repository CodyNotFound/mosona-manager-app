import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import 'features/counter/counter_screen.dart';
import 'features/theme/theme_controller.dart';

/// The root widget of the application.
///
/// Wires together Riverpod state ([themeControllerProvider]) with the forui
/// [FTheme]. The material [ThemeData] is derived from the forui theme via
/// [FThemeData.toApproximateMaterialTheme] so regular Material widgets stay
/// visually consistent with forui widgets.
class MosonaManagerApp extends ConsumerWidget {
  const MosonaManagerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brightness = ref.watch(themeControllerProvider);
    final theme = brightness == Brightness.light
        ? FTheme.neutral.light.touch
        : FTheme.neutral.dark.touch;

    return MaterialApp(
      title: 'Mosona Manager',
      debugShowCheckedModeBanner: false,
      // The app is English only for now.
      locale: const Locale('en', 'US'),
      supportedLocales: FLocalizations.supportedLocales,
      localizationsDelegates: FLocalizations.localizationsDelegates,
      theme: theme.toApproximateMaterialTheme(),
      // Provide the forui theme + global overlays (toasts, etc.) to the tree.
      builder: (context, child) => FTheme(
        data: theme,
        child: FToaster(child: child!),
      ),
      home: const CounterScreen(),
    );
  }
}
