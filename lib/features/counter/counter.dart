import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'counter.g.dart';

/// A small counter [Notifier] used to demonstrate Riverpod state management.
@Riverpod(keepAlive: true)
class Counter extends _$Counter {
  @override
  int build() => 0;

  /// Increases the counter by one.
  void increment() => state++;

  /// Resets the counter back to zero.
  void reset() => state = 0;
}
