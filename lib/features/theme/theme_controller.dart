import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'theme_controller.g.dart';

/// Controls the app's overall [Brightness] (light / dark).
///
@Riverpod(keepAlive: true)
class ThemeController extends _$ThemeController {
  @override
  Brightness build() => Brightness.light;

  /// Switches between light and dark mode.
  void toggle() =>
      state = state == Brightness.light ? Brightness.dark : Brightness.light;
}
