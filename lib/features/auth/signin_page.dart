import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_services.dart';
import '../../core/models/models.dart' show AuthKeys, AuthProvider;
import '../../core/state/controllers.dart';
import '../../core/state/session.dart';
import '../../core/theme/mcolors.dart';
import '../../core/widgets/widgets.dart';

/// /auth — sign in / register against a self-hosted instance.
/// Mobile-specific: a server base-URL section on top (persisted).
class SignInPage extends ConsumerStatefulWidget {
  const SignInPage({super.key});

  @override
  ConsumerState<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends ConsumerState<SignInPage> {
  final _serverCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _regUserCtrl = TextEditingController();
  final _regEmailCtrl = TextEditingController();
  final _regPwdCtrl = TextEditingController();
  final _regConfirmCtrl = TextEditingController();

  bool _loginMode = true;
  bool _rememberMe = false;
  bool _obscure = true;
  bool _regObscure = true;
  bool _probing = false;
  bool _savingUrl = false;
  bool _submitting = false;
  String? _serverError;
  AuthKeys? _keys;

  @override
  void initState() {
    super.initState();
    _serverCtrl.text = ref.read(serverConfigProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) => _probe());
  }

  @override
  void dispose() {
    for (final c in [
      _serverCtrl,
      _emailCtrl,
      _passwordCtrl,
      _regUserCtrl,
      _regEmailCtrl,
      _regPwdCtrl,
      _regConfirmCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool _validBaseUrl(String url) {
    if (url.startsWith('https://')) return url.length > 'https://'.length;
    if (url.startsWith('http://')) return url.length > 'http://'.length;
    return false;
  }

  /// Entry probe: init check -> session bootstrap -> oauth provider list.
  Future<void> _probe() async {
    if (ref.read(serverConfigProvider).isEmpty) return;
    setState(() => _probing = true);
    final api = ref.read(apiProvider);
    try {
      final ready = await api.initStatus();
      if (!mounted) return;
      if (!ready) {
        context.go('/init');
        return;
      }
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
    try {
      await ref.read(sessionProvider.notifier).bootstrap();
      if (!mounted) return;
      if (ref.read(sessionProvider).isLoggedIn) {
        context.go('/');
        return;
      }
    } catch (_) {}
    try {
      final keys = await api.authKeys();
      if (mounted) setState(() => _keys = keys);
    } catch (_) {}
    if (mounted) setState(() => _probing = false);
  }

  Future<void> _saveServerUrl() async {
    final url = _serverCtrl.text.trim();
    if (!_validBaseUrl(url)) {
      setState(() => _serverError =
          t(context, 'Must start with http:// or https://', '必须以 http:// 或 https:// 开头'));
      return;
    }
    setState(() {
      _savingUrl = true;
      _serverError = null;
    });
    ref.read(serverConfigProvider.notifier).set(url);
    try {
      await ref.read(sessionProvider.notifier).bootstrap();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _savingUrl = false);
    await _probe();
  }

  Future<void> _submitLogin() async {
    if (ref.read(serverConfigProvider).isEmpty) {
      toastWarn(context, t(context, 'Configure the server address first', '请先配置服务器地址'));
      return;
    }
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (email.isEmpty || password.isEmpty) {
      toastWarn(context, t(context, 'Please fill in email and password', '请填写邮箱和密码'));
      return;
    }
    setState(() => _submitting = true);
    try {
      final e = await ref
          .read(apiProvider)
          .login(email, password, rememberMe: _rememberMe);
      if (!mounted) return;
      if (e.code == 'ok') {
        await ref.read(sessionProvider.notifier).afterLogin();
        if (!mounted) return;
        context.go('/');
      } else if (e.code == '2fa_required' || e.code == 'verify') {
        context.go('/2fa');
      } else {
        showApiError(context, ApiException(e.code, e.msg));
      }
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _submitRegister() async {
    if (ref.read(serverConfigProvider).isEmpty) {
      toastWarn(context, t(context, 'Configure the server address first', '请先配置服务器地址'));
      return;
    }
    final username = _regUserCtrl.text.trim();
    final email = _regEmailCtrl.text.trim();
    final password = _regPwdCtrl.text;
    if (username.isEmpty || email.isEmpty) {
      toastWarn(context, t(context, 'Please fill in all fields', '请填写所有字段'));
      return;
    }
    if (!_pwdChecks(context, password).every((c) => c.$1)) {
      toastWarn(context, t(context, 'Password does not meet the requirements', '密码未满足下方要求'));
      return;
    }
    if (password != _regConfirmCtrl.text) {
      toastWarn(context, t(context, 'Passwords do not match', '两次输入的密码不一致'));
      return;
    }
    setState(() => _submitting = true);
    try {
      // Captcha-protected registration is web-only: send empty token.
      await ref.read(apiProvider).register(username, email, password);
      if (!mounted) return;
      toastSuccess(context, t(context, 'Account created, please sign in', '注册成功，请登录'));
      setState(() {
        _loginMode = true;
        _emailCtrl.text = email;
      });
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _oauthLogin(AuthProvider p) async {
    try {
      final r = await ref.read(apiProvider).oauthLogin(p.id);
      await launchExternal(r.url);
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keep the text field in sync if the URL is changed elsewhere.
    ref.listen(serverConfigProvider, (_, next) {
      if (_serverCtrl.text.trim() != next) _serverCtrl.text = next;
    });
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FadeSlideIn(child: _serverCard()),
                  const SizedBox(height: 24),
                  FadeSlideIn(
                    delay: 60,
                    child: _branding(muted),
                  ),
                  const SizedBox(height: 20),
                  FadeSlideIn(delay: 120, child: _authCard()),
                  if ((_keys?.oauth.isNotEmpty ?? false)) ...[
                    const SizedBox(height: 18),
                    FadeSlideIn(delay: 180, child: _oauthSection(muted)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------- sections

  Widget _serverCard() {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return MCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.dns_outlined, size: 15, color: muted),
              const SizedBox(width: 6),
              Text(t(context, 'Server address', '服务器地址'),
                  style: TextStyle(fontSize: 12, color: muted)),
              const Spacer(),
              if (_probing)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _serverCtrl,
                  keyboardType: TextInputType.url,
                  autofillHints: const [AutofillHints.url],
                  decoration: InputDecoration(
                    hintText: 'https://manager.example.com',
                    isDense: true,
                    errorText: _serverError,
                  ),
                  onChanged: (_) {
                    if (_serverError != null) setState(() => _serverError = null);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: LoadingButton(
                  label: t(context, 'Save', '保存'),
                  loading: _savingUrl,
                  onPressed: _saveServerUrl,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _branding(Color muted) {
    return Column(
      children: [
        Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            color: MColors.logoFallback,
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Center(
            child: Text(
              'M',
              style: TextStyle(
                  fontSize: 34, fontWeight: FontWeight.w800, color: Color(0xFF15803D)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text('Mosona Manager',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
          t(context, 'Server monitor & terminal management', '服务器监控与终端管理'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: muted),
        ),
      ],
    );
  }

  Widget _authCard() {
    return MCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loginMode) ..._loginForm() else ..._registerForm(),
          const SizedBox(height: 6),
          Center(
            child: TextButton(
              onPressed: () => setState(() => _loginMode = !_loginMode),
              child: Text(_loginMode
                  ? t(context, 'No account? Create one', '没有账号？去注册')
                  : t(context, 'Already have an account? Sign in', '已有账号？去登录')),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _loginForm() {
    return [
      TextField(
        controller: _emailCtrl,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        decoration: InputDecoration(labelText: t(context, 'Email', '邮箱')),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _passwordCtrl,
        obscureText: _obscure,
        autofillHints: const [AutofillHints.password],
        decoration: InputDecoration(
          labelText: t(context, 'Password', '密码'),
          suffixIcon: IconButton(
            icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 4),
      Row(
        children: [
          Checkbox(
            value: _rememberMe,
            onChanged: (v) => setState(() => _rememberMe = v ?? false),
          ),
          GestureDetector(
            onTap: () => setState(() => _rememberMe = !_rememberMe),
            child: Text(t(context, 'Remember me', '记住我')),
          ),
        ],
      ),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: LoadingButton(
          label: t(context, 'Sign in', '登录'),
          loading: _submitting,
          onPressed: _submitLogin,
        ),
      ),
    ];
  }

  List<Widget> _registerForm() {
    final captcha = _keys?.captcha ?? '';
    return [
      TextField(
        controller: _regUserCtrl,
        decoration: InputDecoration(labelText: t(context, 'Username', '用户名')),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _regEmailCtrl,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        decoration: InputDecoration(labelText: t(context, 'Email', '邮箱')),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _regPwdCtrl,
        obscureText: _regObscure,
        autofillHints: const [AutofillHints.newPassword],
        decoration: InputDecoration(
          labelText: t(context, 'Password', '密码'),
          suffixIcon: IconButton(
            icon:
                Icon(_regObscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
            onPressed: () => setState(() => _regObscure = !_regObscure),
          ),
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 6),
      _PwdChecklist(password: _regPwdCtrl.text),
      const SizedBox(height: 10),
      TextField(
        controller: _regConfirmCtrl,
        obscureText: _regObscure,
        decoration: InputDecoration(
          labelText: t(context, 'Confirm password', '确认密码'),
          errorText: _regConfirmCtrl.text.isNotEmpty && _regConfirmCtrl.text != _regPwdCtrl.text
              ? t(context, 'Passwords do not match', '两次输入的密码不一致')
              : null,
        ),
        onChanged: (_) => setState(() {}),
      ),
      if (captcha.isNotEmpty) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline,
                  size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t(context, 'Captcha-protected registration is web-only',
                      '注册验证码仅支持网页端'),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 14),
      SizedBox(
        width: double.infinity,
        child: LoadingButton(
          label: t(context, 'Create account', '注册账号'),
          loading: _submitting,
          onPressed: _submitRegister,
        ),
      ),
    ];
  }

  Widget _oauthSection(Color muted) {
    final providers = _keys?.oauth ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Text(t(context, 'Or continue with', '或使用以下方式登录'),
              style: TextStyle(fontSize: 12, color: muted)),
        ),
        const SizedBox(height: 10),
        for (final p in providers)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: FilledButton.tonal(
              onPressed: _submitting ? null : () => _oauthLogin(p),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _providerIcon(p),
                  const SizedBox(width: 8),
                  Text(t(context, 'Continue with ${p.name}', '使用 ${p.name} 登录')),
                ],
              ),
            ),
          ),
        const SizedBox(height: 2),
        Center(
          child: Text(
            t(context, 'OAuth callback is completed on the web client for now.',
                'OAuth 回调暂由网页端完成。'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: muted),
          ),
        ),
      ],
    );
  }

  Widget _providerIcon(AuthProvider p) {
    final icon = p.icon;
    if (icon.startsWith('http')) {
      return Image.network(
        icon,
        width: 18,
        height: 18,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );
    }
    return const SizedBox.shrink();
  }
}

// ---------------------------------------------------------------- checklist

/// Live password strength checklist (web parity): >=8 chars, upper, lower,
/// digit, special.
List<(bool, String)> _pwdChecks(BuildContext context, String p) => [
      (p.length >= 8, t(context, 'At least 8 characters', '至少 8 个字符')),
      (RegExp(r'[A-Z]').hasMatch(p), t(context, 'Contains an uppercase letter', '包含大写字母')),
      (RegExp(r'[a-z]').hasMatch(p), t(context, 'Contains a lowercase letter', '包含小写字母')),
      (RegExp(r'[0-9]').hasMatch(p), t(context, 'Contains a digit', '包含数字')),
      (
        RegExp(r'[^A-Za-z0-9]').hasMatch(p),
        t(context, 'Contains a special character', '包含特殊字符')
      ),
    ];

class _PwdChecklist extends StatelessWidget {
  const _PwdChecklist({required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (ok, label) in _pwdChecks(context, password))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Icon(
                  ok ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 14,
                  color: ok ? MColors.online : muted,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: ok ? MColors.online : muted),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
