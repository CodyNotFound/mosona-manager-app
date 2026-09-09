import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../models/models.dart';

/// A parsed SSE frame.
class SseEvent {
  SseEvent(this.event, this.data);

  final String event;
  final String data;
}

/// Minimal SSE client over dio's streaming response with auto-reconnect and
/// a stale watchdog, matching the web client's behavior:
/// - reconnect after [reconnectDelay] on connection loss
/// - [staleTimeout] without any traffic => close + reconnect
class SseClient {
  SseClient({
    required this.client,
    required this.path,
    this.reconnectDelay = const Duration(seconds: 5),
    this.staleTimeout = const Duration(seconds: 30),
  });

  final ApiClient client;
  final String path;
  final Duration reconnectDelay;
  final Duration staleTimeout;

  final _events = StreamController<SseEvent>.broadcast();
  Stream<SseEvent> get events => _events.stream;

  Timer? _staleTimer;
  Timer? _reconnectTimer;
  StreamSubscription<Uint8List>? _sub;
  bool _closed = false;

  Future<void> start() async {
    if (_closed) return;
    _resetStale();
    try {
      final res = await client.dio.get<ResponseBody>(
        path,
        options: Options(
          responseType: ResponseType.stream,
          headers: {'accept': 'text/event-stream'},
        ),
      );
      final stream = res.data?.stream;
      // closed while awaiting headers, or a non-200 body (e.g. 401 after
      // logout): stop instead of parsing an error page as an event stream
      if (_closed || (res.statusCode ?? 500) != 200) {
        _staleTimer?.cancel();
        return;
      }
      if (stream == null) {
        _scheduleReconnect();
        return;
      }
      final lines = <String>[];
      _sub = stream.listen(
        (chunk) {
          _resetStale();
          // decode chunk and split into complete lines
          final text = utf8.decode(chunk, allowMalformed: true);
          for (var i = 0; i < text.length; i++) {
            final ch = text[i];
            if (ch == '\n') {
              _handleLine(lines.join(), lines);
              lines.clear();
            } else {
              lines.add(ch);
            }
          }
        },
        onError: (_) => _scheduleReconnect(),
        onDone: () => _scheduleReconnect(),
        cancelOnError: true,
      );
    } on DioException {
      _scheduleReconnect();
    }
  }

  String _pendingEvent = '';
  final StringBuffer _pendingData = StringBuffer();

  void _handleLine(String line, List<String> buffer) {
    if (line.isEmpty) {
      // dispatch
      if (_pendingData.isNotEmpty) {
        _events.add(SseEvent(_pendingEvent, _pendingData.toString()));
      }
      _pendingEvent = '';
      _pendingData.clear();
      return;
    }
    if (line.startsWith(':')) return; // keepalive comment
    if (line.startsWith('event:')) {
      _pendingEvent = line.substring(6).trim();
    } else if (line.startsWith('data:')) {
      _pendingData.write(line.substring(5).trimStartSpace());
    }
  }

  void _resetStale() {
    _staleTimer?.cancel();
    _staleTimer = Timer(staleTimeout, () {
      _sub?.cancel();
      _scheduleReconnect();
    });
  }

  void _scheduleReconnect() {
    if (_closed) return;
    _sub?.cancel();
    _sub = null;
    _staleTimer?.cancel();
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(reconnectDelay, start);
  }

  void close() {
    _closed = true;
    _sub?.cancel();
    _staleTimer?.cancel();
    _reconnectTimer?.cancel();
    if (!_events.isClosed) _events.close();
  }
}

extension on String {
  String trimStartSpace() {
    var i = 0;
    while (i < length && this[i] == ' ') {
      i++;
    }
    return substring(i);
  }
}

/// Connectivity state surfaced to the UI.
enum MonitorConn { connecting, live, lost }

/// Realtime monitor snapshot state: subscribes to the team SSE stream,
/// throttles commits to 1/s (web parity) and exposes derived stats.
class MonitorController extends Notifier<MonitorSnapshot?> {
  final _conn = ValueNotifier<MonitorConn>(MonitorConn.connecting);
  final _revoked = ValueNotifier<bool>(false);
  SseClient? _sse;
  Timer? _throttle;
  MonitorSnapshot? _pending;

  ValueNotifier<MonitorConn> get conn => _conn;

  /// True after the hub pushed `revoked` (team access removed) — the shell
  /// listens and forces re-login, mirroring the web client's redirect.
  ValueNotifier<bool> get revoked => _revoked;

  @override
  MonitorSnapshot? build() {
    ref.onDispose(() {
      _sse?.close();
      _throttle?.cancel();
      _conn.dispose();
      _revoked.dispose();
    });
    subscribe();
    return null;
  }

  void subscribe() {
    _sse?.close();
    _conn.value = MonitorConn.connecting;
    _revoked.value = false; // re-arm so a future revoke fires again
    final client = ref.read(apiClientProvider);
    _sse = SseClient(client: client, path: '/api/v1/server/monitor/sse')
      ..events.listen((e) {
        if (e.event == 'update') {
          _conn.value = MonitorConn.live;
          try {
            _pending = MonitorSnapshot.fromJson(jsonDecode(e.data));
          } catch (_) {}
          _commitThrottled();
        } else if (e.event == 'revoked') {
          _conn.value = MonitorConn.lost;
          _revoked.value = true;
          _sse?.close();
        } else if (e.event == 'error') {
          // fatal auth errors carry a code: stop reconnecting (the session
          // is gone); transient load failures keep the reconnect loop
          try {
            final code = (jsonDecode(e.data)
                    as Map<String, dynamic>)['code']
                ?.toString() ??
                '';
            if (code == 'login' || code == 'team_access_revoked') {
              _conn.value = MonitorConn.lost;
              _revoked.value = true;
              _sse?.close();
            }
          } catch (_) {}
        }
      });
    _sse!.start();
  }

  void _commitThrottled() {
    if (_throttle?.isActive ?? false) return;
    _throttle = Timer(const Duration(seconds: 1), () {
      if (_pending != null) state = _pending;
    });
  }

  /// Servers considered online: status.time within 5s of snapshot.now.
  static bool isOnline(MonitorSnapshot snap, int serverId) {
    final st = snap.status[serverId];
    if (st == null || st.time == null) return false;
    final nowMs = snap.nowSec * 1000;
    return nowMs - st.time!.millisecondsSinceEpoch < 5000;
  }
}

final monitorProvider =
    NotifierProvider<MonitorController, MonitorSnapshot?>(MonitorController.new);
