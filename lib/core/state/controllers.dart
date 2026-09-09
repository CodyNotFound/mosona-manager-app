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

/// Supported UI languages: English, Simplified Chinese, Traditional Chinese.
const kLocales = ['en', 'zh-CN', 'zh-HK'];

class LocaleController extends Notifier<String> {
  @override
  String build() {
    final raw = _prefs().getString(_kLocale);
    if (raw != null && kLocales.contains(raw)) return raw;
    return _fromPlatform();
  }

  static String _fromPlatform() {
    final tag = PlatformDispatcher.instance.locale.toLanguageTag().toLowerCase();
    if (tag.startsWith('zh-tw') || tag.startsWith('zh-hk') || tag.startsWith('zh-mo')) {
      return 'zh-HK';
    }
    if (tag.startsWith('zh')) return 'zh-CN';
    return 'en';
  }

  SharedPreferences _prefs() => ref.read(sharedPrefsProvider);

  void set(String code) {
    state = kLocales.contains(code) ? code : 'en';
    _prefs().setString(_kLocale, state);
  }

  /// Cycles EN -> 简体中文 -> 繁體中文 -> EN.
  void toggle() => set(kLocales[(kLocales.indexOf(state) + 1) % kLocales.length]);

  bool get isZh => state.startsWith('zh');
}

class ServerConfigController extends Notifier<String> {
  @override
  String build() =>
      _prefs().getString(_kServerUrl) ??
      (const bool.fromEnvironment('dart.vm.product')
          ? ''
          : const String.fromEnvironment('MOSONA_DEMO_URL'));

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

/// Inline trilingual string helper:
/// `t(context, 'Hello', '你好', zhHk: '你好')` — [zhHk] falls back to [zh].
String t(BuildContext context, String en, String zh, {String? zhHk}) {
  final code =
      ProviderScope.containerOf(context, listen: false).read(localeControllerProvider);
  if (code == 'zh-CN') return zh;
  if (code == 'zh-HK') return zhHk ?? zh;
  return en;
}
