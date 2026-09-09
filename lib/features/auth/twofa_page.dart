import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_services.dart';
import '../../core/models/models.dart' show TwoFaStatus;
import '../../core/state/session.dart';
import '../../core/widgets/widgets.dart';

/// /2fa — second factor gate after a half-logged-in session.
/// TOTP (verified + totp enabled) or 6-digit email code, 3+3 input groups,
/// auto-submit, full-screen spinner while verifying.
class TwoFaPage extends ConsumerStatefulWidget {
  const TwoFaPage({super.key});

  @override
  ConsumerState<TwoFaPage> createState() => _TwoFaPageState();
}

class _TwoFaPageState extends ConsumerState<TwoFaPage> {
  final _digits = List<TextEditingController>.generate(
      6, (_) => TextEditingController());
  final _focus = List<FocusNode>.generate(6, (_) => FocusNode());

  TwoFaStatus? _status;
  bool _loading = true;
  bool _loadError = false;
  bool _submitting = false;
  bool _sending = false;
  int _cooldown = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _digits) {
      c.dispose();
    }
    for (final f in _focus) {
      f.dispose();
    }
    super.dispose();
  }

  bool get _totpMode {
    final s = _status;
    return s != null && s.verified && s.totp == true;
  }

  /// Email-code mode: '2fa' for already-verified sessions, 'activation' otherwise.
  String get _sendMode => (_status?.verified ?? false) ? '2fa' : 'activation';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = false;
    });
    try {
      final s = await ref.read(apiProvider).twoFaStatus();
      if (!mounted) return;
      setState(() => _status = s);
      if (s.cooling > 0) {
        _startCooldown(s.cooling);
      } else if (!_totpMode) {
        await _sendCode();
      }
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = true;
      });
    }
  }

  void _startCooldown(int seconds) {
    _timer?.cancel();
    setState(() => _cooldown = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_cooldown <= 1) {
        t.cancel();
        setState(() => _cooldown = 0);
      } else {
        setState(() => _cooldown -= 1);
      }
    });
  }

  Future<void> _sendCode() async {
    if (_sending || _cooldown > 0) return;
    setState(() => _sending = true);
    try {
      await ref.read(apiProvider).twoFaSendCode(_sendMode);
      if (!mounted) return;
      toastSuccess(context, t(context, 'Verification code sent', '验证码已发送'));
      _startCooldown(60);
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String get _code => [for (final c in _digits) c.text].join();

  Future<void> _submit() async {
    if (_submitting || _code.length != 6) return;
    setState(() => _submitting = true);
    final api = ref.read(apiProvider);
    try {
      if (_totpMode) {
        await api.twoFaVerifyTotp(_code);
      } else {
        await api.twoFaVerifyCode(_code);
      }
      if (!mounted) return;
      await ref.read(sessionProvider.notifier).afterLogin();
      if (!mounted) return;
      context.go('/');
    } catch (e) {
      if (!mounted) return;
      showApiError(context, e);
      for (final c in _digits) {
        c.clear();
      }
      _focus.first.requestFocus();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _onChanged(int i, String v) {
    if (v.length > 1) {
      // Pasted (or fast-typed) multiple digits: spread them across boxes.
      final chars = [for (final ch in v.runes) String.fromCharCode(ch)];
      var idx = i;
      for (final ch in chars) {
        if (idx > 5) break;
        _digits[idx].text = ch;
        idx += 1;
      }
      _focus[(idx - 1).clamp(0, 5)].requestFocus();
      _maybeSubmit();
      return;
    }
    if (v.isNotEmpty && i < 5) _focus[i + 1].requestFocus();
    _maybeSubmit();
  }

  void _maybeSubmit() {
    if (_code.length == 6 && !_submitting) _submit();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t(context, 'Two-Factor Verification', '两步验证')),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: () => context.go('/auth'),
            child: Text(t(context, 'Back to sign in', '返回登录')),
          ),
        ],
      ),
      body: Stack(
        children: [
          SafeArea(child: _body()),
          if (_submitting) ...[
            const ModalBarrier(dismissible: false, color: Colors.black26),
            const Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            EmptyState(
              text: t(context, 'Failed to load verification status', '获取验证状态失败'),
              icon: Icons.cloud_off_outlined,
            ),
            FilledButton.tonal(
              onPressed: _load,
              child: Text(t(context, 'Retry', '重试')),
            ),
          ],
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.secondary,
            ),
            child: Icon(
              _totpMode ? Icons.password_outlined : Icons.mark_email_read_outlined,
              size: 30,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _totpMode
                ? t(context, 'Enter the 6-digit code from your authenticator app',
                    '请输入验证器 App 中的 6 位代码')
                : t(context, 'We sent a 6-digit code to your email', '验证码已发送至您的邮箱'),
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _box(0),
              const SizedBox(width: 6),
              _box(1),
              const SizedBox(width: 6),
              _box(2),
              const SizedBox(width: 16),
              _box(3),
              const SizedBox(width: 6),
              _box(4),
              const SizedBox(width: 6),
              _box(5),
            ],
          ),
          if (!_totpMode) ...[
            const SizedBox(height: 20),
            Center(
              child: OutlinedButton.icon(
                onPressed: (_cooldown > 0 || _sending) ? null : _sendCode,
                icon: _sending
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh, size: 16),
                label: Text(_cooldown > 0
                    ? t(context, 'Resend (${_cooldown}s)', '重新发送 (${_cooldown}s)')
                    : t(context, 'Resend code', '重新发送验证码')),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _box(int i) {
    return Focus(
      onKeyEvent: (node, event) {
        // Backspace on an empty box moves focus to the previous one.
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.backspace &&
            _digits[i].text.isEmpty &&
            i > 0) {
          _focus[i - 1].requestFocus();
          final prev = _digits[i - 1];
          prev.selection =
              TextSelection(baseOffset: 0, extentOffset: prev.text.length);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: SizedBox(
        width: 42,
        child: TextField(
          controller: _digits[i],
          focusNode: _focus[i],
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          decoration: const InputDecoration(isDense: true),
          onChanged: (v) => _onChanged(i, v),
        ),
      ),
    );
  }
}
