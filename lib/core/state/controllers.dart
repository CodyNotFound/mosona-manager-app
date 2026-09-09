import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-level controllers: theme mode, locale (en / zh-CN), server base URL.

const _kTheme = 'mosona-app-theme';
const _kLocale = 'mosona-app-locale';
const _kServerUrl = 'mosona-app-server-url';

class ThemeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final raw = _prefs().getString(_kTheme);
    return switch (raw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  SharedPreferences _prefs() => ref.read(sharedPrefsProvider);

  void set(ThemeMode mode) {
    state = mode;
    _prefs().setString(_kTheme, mode.name);
  }

  void toggle() {
    set(state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
  }
}

class LocaleController extends Notifier<String> {
  @override
  String build() {
    final raw = _prefs().getString(_kLocale);
    if (raw != null && (raw == 'en' || raw == 'zh-CN')) return raw;
    final platform = PlatformDispatcher.instance.locale.toLanguageTag();
    return platform.toLowerCase().startsWith('zh') ? 'zh-CN' : 'en';
  }

  SharedPreferences _prefs() => ref.read(sharedPrefsProvider);

  void set(String code) {
    state = code;
    _prefs().setString(_kLocale, code);
  }

  void toggle() => set(state == 'en' ? 'zh-CN' : 'en');

  bool get isZh => state == 'zh-CN';
}

class ServerConfigController extends Notifier<String> {
  @override
  String build() => _prefs().getString(_kServerUrl) ?? '';

  SharedPreferences _prefs() => ref.read(sharedPrefsProvider);

  /// Normalizes and persists the base URL (no trailing slash, keep scheme).
  void set(String url) {
    var v = url.trim();
    while (v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }
    state = v;
    _prefs().setString(_kServerUrl, v);
  }
}

final sharedPrefsProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('overridden in main bootstrap');
});

final themeControllerProvider =
    NotifierProvider<ThemeController, ThemeMode>(ThemeController.new);

final localeControllerProvider =
    NotifierProvider<LocaleController, String>(LocaleController.new);

final serverConfigProvider =
    NotifierProvider<ServerConfigController, String>(ServerConfigController.new);

/// Inline bilingual string helper: `t(context, 'Hello', '你好')`.
String t(BuildContext context, String en, String zh) {
  final scope = ProviderScope.containerOf(context, listen: false);
  return scope.read(localeControllerProvider) == 'zh-CN' ? zh : en;
}
