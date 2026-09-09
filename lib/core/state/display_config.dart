import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'controllers.dart';

/// Persisted display preferences, mirroring the web's localStorage
/// `mosona-config` (defaultUserConfig).
class DisplayConfig {
  DisplayConfig({
    this.defaultTimeFrame = '1h',
    this.autoRefresh = true,
    this.monitorMode = 'avg',
    this.minMaxMode = 'min-auto',
    this.monitorLayout = 'grid-2',
    this.dashboardLayout = 'grid',
    this.showDetails = false,
    this.terminalRenderer = 'xterm',
  });

  String defaultTimeFrame; // real-time | 1h | 12h | 24h | 7d | 30d | 365d
  bool autoRefresh;
  String monitorMode; // avg | max | raw
  String minMaxMode; // min-auto | 0-auto | 0-max
  String monitorLayout; // grid-3 | grid-2 | list
  String dashboardLayout; // grid | list | list2
  bool showDetails;
  String terminalRenderer; // xterm (ghostty-web is a WASM renderer, web-only)

  Map<String, dynamic> toJson() => {
        'defaultTimeFrame': defaultTimeFrame,
        'autoRefresh': autoRefresh,
        'defaultMonitorMode': monitorMode,
        'defaultMinMaxMode': minMaxMode,
        'defaultLayout': monitorLayout,
        'dashboardLayout': dashboardLayout,
        'dashboardShowDetails': showDetails,
        'terminalRenderer': terminalRenderer,
      };

  factory DisplayConfig.fromJson(Map<String, dynamic> m) => DisplayConfig(
        defaultTimeFrame: m['defaultTimeFrame'] as String? ?? '1h',
        autoRefresh: m['autoRefresh'] as bool? ?? true,
        monitorMode: m['defaultMonitorMode'] as String? ?? 'avg',
        minMaxMode: m['defaultMinMaxMode'] as String? ?? 'min-auto',
        monitorLayout: m['defaultLayout'] as String? ?? 'grid-2',
        dashboardLayout: m['dashboardLayout'] as String? ?? 'grid',
        showDetails: m['dashboardShowDetails'] as bool? ?? false,
        terminalRenderer: m['terminalRenderer'] as String? ?? 'xterm',
      );
}

const _kConfig = 'mosona-config';

class DisplayConfigController extends Notifier<DisplayConfig> {
  @override
  DisplayConfig build() {
    final raw = ref.read(sharedPrefsProvider).getString(_kConfig);
    if (raw == null) return DisplayConfig();
    try {
      return DisplayConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return DisplayConfig();
    }
  }

  Future<void> update(DisplayConfig cfg) async {
    state = cfg;
    await ref
        .read(sharedPrefsProvider)
        .setString(_kConfig, jsonEncode(cfg.toJson()));
  }
}

final displayConfigProvider =
    NotifierProvider<DisplayConfigController, DisplayConfig>(DisplayConfigController.new);
