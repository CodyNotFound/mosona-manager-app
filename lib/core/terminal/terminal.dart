import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:xterm/xterm.dart';

import '../api/api_client.dart';
import '../models/models.dart';

enum TerminalPhase { connecting, connected, reconnecting, disconnected, revoked, failed }

/// One live SSH terminal session bound to an xterm [Terminal].
///
/// Protocol (see docs/backend-api-spec.md):
/// - client -> server text frames: {"type":"input","data":...} / {"type":"resize",...}
/// - server -> client binary frames: raw terminal output bytes
/// - reconnect with exponential backoff capped at 12s; close code 1008 = revoked
class TerminalSession extends ChangeNotifier {
  TerminalSession({
    required this.id,
    required this.server,
    required this.client,
  }) {
    terminal = Terminal(maxLines: 5000);
    terminal.onOutput = _onTerminalOutput;
  }

  final String id; // "{serverId}-{timestamp}"
  final TerminalServer server;
  final ApiClient client;

  late final Terminal terminal;

  TerminalPhase phase = TerminalPhase.connecting;
  String lastError = '';
  int reconnectAttempt = 0;

  IOWebSocketChannel? _ws;
  StreamSubscription? _sub;
  Timer? _reconnectTimer;
  bool _manuallyClosed = false;
  final List<String> _pendingInput = [];
  int _pendingBytes = 0;
  static const _maxPendingBytes = 64 * 1024;
  int _cols = 80;
  int _rows = 24;

  /// Streaming UTF-8 decoder so multi-byte characters split across WS frames
  /// are reassembled correctly (per-frame decode would garble them).
  late final ChunkedConversionSink<List<int>> _outputSink =
      const Utf8Codec(allowMalformed: true)
          .decoder
          .startChunkedConversion(_TerminalStringSink(terminal.write));

  void _setPhase(TerminalPhase p) {
    phase = p;
    notifyListeners();
  }

  Future<void> connect() async {
    if (_manuallyClosed) return;
    _setPhase(reconnectAttempt > 0 ? TerminalPhase.reconnecting : TerminalPhase.connecting);
    try {
      final uri = client.wsUri('/api/v1/server/terminal/${server.id}/ws');
      final cookie = client.cookies.headerFor(uri);
      _ws = IOWebSocketChannel.connect(
        uri,
        headers: {
          'user-agent': kUserAgent,
          'cookie': ?cookie,
        },
      );
      await _ws!.ready;
      _sub = _ws!.stream.listen(
        (data) {
          if (data is String) {
            // human-readable connection errors from the hub
            terminal.write(data);
            lastError = data;
          } else if (data is List<int>) {
            _outputSink.add(Uint8List.fromList(data));
          }
        },
        onDone: _onDone,
        onError: (_) => _onDone(),
      );
      reconnectAttempt = 0;
      _setPhase(TerminalPhase.connected);
      _flushPending();
      resize(_cols, _rows);
    } catch (e) {
      lastError = e.toString();
      _onDone();
    }
  }

  void _onTerminalOutput(String data) {
    if (_ws != null && phase == TerminalPhase.connected) {
      _ws!.sink.add(jsonEncode({'type': 'input', 'data': data}));
    } else if (_pendingBytes < _maxPendingBytes) {
      _pendingInput.add(data);
      _pendingBytes += utf8.encode(data).length;
    }
  }

  void _flushPending() {
    for (final data in _pendingInput) {
      _ws?.sink.add(jsonEncode({'type': 'input', 'data': data}));
    }
    _pendingInput.clear();
    _pendingBytes = 0;
  }

  void resize(int cols, int rows) {
    _cols = cols;
    _rows = rows;
    terminal.resize(cols, rows);
    if (phase == TerminalPhase.connected && _ws != null) {
      _ws!.sink.add(jsonEncode({'type': 'resize', 'rows': rows, 'cols': cols}));
    }
  }

  void write(String text) => terminal.write(text);

  void _onDone() {
    // capture the close code before tearing down the channel
    final code = _ws?.closeCode;
    _sub?.cancel();
    _sub = null;
    _ws?.sink.close();
    _ws = null;

    // 1008 = policy violation: session revoked (team removed / logged out).
    if (code == 1008) {
      terminal.write('\r\n[Access revoked]\r\n');
      _setPhase(TerminalPhase.revoked);
      return;
    }
    if (_manuallyClosed) {
      _setPhase(TerminalPhase.disconnected);
      return;
    }
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    reconnectAttempt++;
    final delayMs = (1000 * (1 << (reconnectAttempt - 1))).clamp(1000, 12000);
    terminal.write('\r\n[Connection lost. Reconnecting in ${(delayMs / 1000).ceil()}s]\r\n');
    _setPhase(TerminalPhase.reconnecting);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () async {
      await connect();
      if (phase == TerminalPhase.connected) {
        terminal.write('\r\n[Reconnected]\r\n');
      }
    });
  }

  void manualClose() {
    _manuallyClosed = true;
    _reconnectTimer?.cancel();
    _sub?.cancel();
    _ws?.sink.close();
    _ws = null;
    _setPhase(TerminalPhase.disconnected);
  }

  @override
  void dispose() {
    manualClose();
    super.dispose();
  }
}

/// Central registry of open terminal sessions (web parity: multi-session map).
class TerminalManager extends ChangeNotifier {
  final Map<String, TerminalSession> _sessions = {};

  List<TerminalSession> get list => _sessions.values.toList();

  TerminalSession? byId(String id) => _sessions[id];

  TerminalSession create({required TerminalServer server, required ApiClient client}) {
    final id = '${server.id}-${DateTime.now().millisecondsSinceEpoch}';
    final s = TerminalSession(id: id, server: server, client: client);
    _sessions[id] = s;
    s.addListener(notifyListeners);
    s.connect();
    notifyListeners();
    return s;
  }

  void close(String id) {
    final s = _sessions.remove(id);
    s?.removeListener(notifyListeners);
    s?.manualClose();
    notifyListeners();
  }

  /// First remaining session id after closing one, for auto-navigation.
  String? firstId() => _sessions.keys.isEmpty ? null : _sessions.keys.first;
}

/// Forwards decoded chunks straight into the terminal emulator.
class _TerminalStringSink extends StringConversionSinkBase {
  _TerminalStringSink(this._write);

  final void Function(String) _write;

  @override
  void add(String str) => _write(str);

  @override
  void addSlice(String str, int start, int end, bool isLast) =>
      _write(str.substring(start, end));

  @override
  void close() {}
}
