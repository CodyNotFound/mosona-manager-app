import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:xterm/xterm.dart';

import '../../core/terminal/terminal.dart';
import '../../core/theme/mcolors.dart';
import '../../core/widgets/widgets.dart';

/// `/session/{id}` — full-screen black xterm view for one live session
/// (web parity §3.7).
class SessionPage extends ConsumerStatefulWidget {
  const SessionPage({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<SessionPage> createState() => _SessionPageState();
}

class _SessionPageState extends ConsumerState<SessionPage> {
  TerminalSession? _session;
  int _lastCols = 0;
  int _lastRows = 0;

  @override
  void initState() {
    super.initState();
    _session = ref.read(terminalManagerProvider).byId(widget.sessionId);
    if (_session == null) {
      Future.microtask(() {
        if (mounted) context.pop();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session == null) {
      // Unknown/already-closed session: empty black screen, auto-pop above.
      return const Scaffold(backgroundColor: Colors.black, body: SizedBox.shrink());
    }
    final mgr = ref.read(terminalManagerProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            OsIcon(os: session.server.os, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                session.server.name,
                style: monoStyle(context, size: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          AnimatedBuilder(animation: session, builder: _statusWidget),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            tooltip: t(context, 'Close session', '关闭会话', zhHk: '關閉工作階段'),
            onPressed: () {
              mgr.close(session.id);
              if (!mounted) return;
              // Web parity: closing a session jumps to the first remaining one,
              // or back to the terminal list when none are left.
              final next = mgr.firstId();
              if (next != null) {
                context.pushReplacement('/session/$next');
              } else {
                context.pop();
              }
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([session, mgr]),
        builder: (context, _) {
          if (mgr.byId(widget.sessionId) == null) {
            // Closed elsewhere (e.g. terminal list): pop back once.
            scheduleMicrotask(() {
              if (mounted) context.pop();
            });
            return const SizedBox.shrink();
          }
          if (session.phase == TerminalPhase.revoked) return _revokedBody();
          return _terminalBody(session);
        },
      ),
    );
  }

  // ---------------------------------------------------------------- status

  Widget _statusWidget(BuildContext context, _) {
    final session = _session!;
    final (label, color, dot) = switch (session.phase) {
      TerminalPhase.connected => (
          t(context, 'Connected', '已连接', zhHk: '已連線'),
          MColors.terminalConnected,
          '●',
        ),
      TerminalPhase.connecting => (
          t(context, 'Connecting', '连接中', zhHk: '連線中'),
          MColors.terminalConnecting,
          '○',
        ),
      TerminalPhase.reconnecting => (
          '${t(context, 'Reconnecting', '重连中', zhHk: '重新連線中')} #${session.reconnectAttempt}',
          MColors.terminalConnecting,
          '○',
        ),
      TerminalPhase.revoked => (
          t(context, 'Revoked', '已吊销', zhHk: '已註銷'),
          MColors.terminalDisconnected,
          '●',
        ),
      _ => (
          t(context, 'Disconnected', '已断开', zhHk: '未連線'),
          MColors.terminalDisconnected,
          '●',
        ),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$dot $label', style: TextStyle(fontSize: 12, color: color)),
        if (session.phase == TerminalPhase.disconnected)
          TextButton(
            onPressed: () => session.connect(),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 6),
            ),
            child: Text(
              t(context, 'Reconnect', '重连', zhHk: '重新連線'),
              style: TextStyle(fontSize: 12, color: color),
            ),
          ),
      ],
    );
  }

  // ----------------------------------------------------------------- body

  Widget _terminalBody(TerminalSession session) {
    return LayoutBuilder(builder: (context, constraints) {
      // ~9x18px per cell at fontSize 14; pty resize follows the viewport.
      final cols = (constraints.maxWidth / 9).floor().clamp(20, 500).toInt();
      final rows = (constraints.maxHeight / 18).floor().clamp(10, 200).toInt();
      if (cols != _lastCols || rows != _lastRows) {
        _lastCols = cols;
        _lastRows = rows;
        scheduleMicrotask(() {
          if (mounted) session.resize(cols, rows);
        });
      }
      return TerminalView(
        session.terminal,
        autofocus: true,
        autoResize: false, // resize is driven by session.resize (sends WS frame)
        backgroundOpacity: 1,
        deleteDetection: true, // better backspace handling on mobile IMEs
        padding: const EdgeInsets.all(8),
        theme: TerminalThemes.whiteOnBlack,
        textStyle: const TerminalStyle(fontSize: 14),
      );
    });
  }

  Widget _revokedBody() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.gpp_bad_outlined,
                color: MColors.terminalDisconnected, size: 44),
            const SizedBox(height: 14),
            Text(
              t(context, 'Team access revoked', '团队访问已被吊销', zhHk: '團隊存取已被註銷'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              t(context, 'This terminal session is no longer authorized.',
                  '当前终端会话已无访问权限。', zhHk: '目前終端機工作階段已無存取權限。'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () => context.pop(),
              child: Text(t(context, 'Back', '返回', zhHk: '返回')),
            ),
          ],
        ),
      ),
    );
  }
}
