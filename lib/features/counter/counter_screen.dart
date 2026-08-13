import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../theme/theme_controller.dart';
import 'counter.dart';

/// The home screen: a counter that showcases Riverpod state + forui widgets.
class CounterScreen extends ConsumerWidget {
  const CounterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(counterProvider);
    final brightness = ref.watch(themeControllerProvider);
    final theme = Theme.of(context);

    return FScaffold(
      header: FHeader(
        title: const Text('Mosona Manager'),
        suffixes: [
          FHeaderAction(
            icon: Icon(
              brightness == Brightness.dark
                  ? FLucideIcons.sun
                  : FLucideIcons.moon,
            ),
            onPress: ref.read(themeControllerProvider.notifier).toggle,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FCard(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    Text(
                      'Counter',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Powered by Riverpod & forui',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '$count',
                      style: theme.textTheme.displayMedium,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FButton(
              onPress: ref.read(counterProvider.notifier).increment,
              child: const Text('Increment'),
            ),
            const SizedBox(height: 8),
            FButton(
              variant: .secondary,
              onPress:
                  count > 0 ? ref.read(counterProvider.notifier).reset : null,
              child: const Text('Reset'),
            ),
          ],
        ),
      ),
    );
  }
}
