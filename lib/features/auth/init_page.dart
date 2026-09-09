import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_services.dart';
import '../../core/state/controllers.dart';
import '../../core/state/session.dart';
import '../../core/theme/mcolors.dart';
import '../../core/widgets/widgets.dart';

/// /init — first-run installation wizard (admin account + site settings),
/// and the post-install success view.
class InitPage extends ConsumerStatefulWidget {
  const InitPage({super.key});

  @override
  ConsumerState<InitPage> createState() => _InitPageState();
}

class _InitPageState extends ConsumerState<InitPage> {
  final _usernameCtrl = TextEditingController(text: 'admin');
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  late final TextEditingController _websiteCtrl;

  bool _checking = true;
  bool? _initialized; // null = probing, true = done, false = wizard
  int _step = 0;
  bool _submitting = false;
  bool _registration = true;
  bool _obscure = true;
  String? _formError;

  @override
  void initState() {
    super.initState();
    _websiteCtrl =
        TextEditingController(text: ref.read(serverConfigProvider));
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    for (final c in [
      _usernameCtrl,
      _emailCtrl,
      _passwordCtrl,
      _confirmCtrl,
      _websiteCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    try {
      final ok = await ref.read(apiProvider).initStatus();
      if (!mounted) return;
      setState(() {
        _initialized = ok;
        _checking = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _checking = false);
      showApiError(context, e);
    }
  }

  void _nextFromStep1() {
    final username = _usernameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (username.isEmpty) {
      setState(() =>
          _formError = t(context, 'Username is required', '请填写用户名'));
      return;
    }
    if (!email.contains('@') || !email.contains('.')) {
      setState(() =>
          _formError = t(context, 'Enter a valid email address', '请输入有效的邮箱地址'));
      return;
    }
    if (!_pwdStrong(password)) {
      setState(() => _formError =
          t(context, 'Password does not meet the checklist below', '密码未满足下方清单要求'));
      return;
    }
    if (password != _confirmCtrl.text) {
      setState(() =>
          _formError = t(context, 'Passwords do not match', '两次输入的密码不一致'));
      return;
    }
    setState(() {
      _step = 1;
      _formError = null;
    });
  }

  Future<void> _finish() async {
    var url = _websiteCtrl.text.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      setState(() => _formError = t(
          context, 'Website URL must start with http:// or https://', '站点地址必须以 http:// 或 https:// 开头'));
      return;
    }
    setState(() {
      _submitting = true;
      _formError = null;
    });
    try {
      await ref.read(apiProvider).initSetup(
            username: _usernameCtrl.text.trim(),
            email: _emailCtrl.text.trim(),
            password: _passwordCtrl.text,
            websiteUrl: url,
            registrationEnable: _registration,
          );
      // Refresh session so needsInit / login state reflects reality.
      await ref.read(sessionProvider.notifier).bootstrap();
      if (!mounted) return;
      setState(() {
        _initialized = true;
        _submitting = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      if (e.code == 'already_initialized') {
        setState(() => _initialized = true);
      } else {
        showApiError(context, e);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t(context, 'Setup', '初始化安装')),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_checking) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_initialized == true) return _successView();
    return _wizard();
  }

  // ---------------------------------------------------------------- success

  Widget _successView() {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
      children: [
        const Icon(Icons.check_circle, size: 72, color: MColors.online),
        const SizedBox(height: 16),
        Text(
          t(context, 'Installation complete', '安装完成'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          t(context, 'Your Mosona Manager instance is ready to use.',
              'Mosona Manager 实例已就绪，可以开始使用了。'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: muted),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: LoadingButton(
            label: t(context, 'Go Dashboard', '进入控制台'),
            onPressed: () => context.go('/'),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: () => context.push('/admin'),
          child: Text(t(context, 'Go Admin', '进入管理后台')),
        ),
      ],
    );
  }

  // ----------------------------------------------------------------- wizard

  Widget _wizard() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: LinearProgressIndicator(
                value: (_step + 1) / 2,
                minHeight: 4,
                backgroundColor:
                    Theme.of(context).colorScheme.secondary,
              ),
            ),
            const SizedBox(width: 12),
            Text('${_step + 1} / 2',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 16),
        FadeSlideIn(
          key: ValueKey(_step),
          delay: 0,
          child: _step == 0 ? _step1Card() : _step2Card(),
        ),
      ],
    );
  }

  Widget _step1Card() {
    return MCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: MColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 18, color: MColors.warning),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    t(context,
                        'This creates the administrator account for this instance. It can only be done once.',
                        '将创建本实例的管理员账号，此操作仅可执行一次。'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _usernameCtrl,
            decoration: InputDecoration(labelText: t(context, 'Username', '用户名')),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
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
            autofillHints: const [AutofillHints.newPassword],
            decoration: InputDecoration(
              labelText: t(context, 'Password', '密码'),
              suffixIcon: IconButton(
                icon: Icon(_obscure
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 6),
          _PwdChecklist(password: _passwordCtrl.text),
          const SizedBox(height: 10),
          TextField(
            controller: _confirmCtrl,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: t(context, 'Confirm password', '确认密码'),
              errorText: _confirmCtrl.text.isNotEmpty &&
                      _confirmCtrl.text != _passwordCtrl.text
                  ? t(context, 'Passwords do not match', '两次输入的密码不一致')
                  : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (_formError != null) ...[
            const SizedBox(height: 10),
            Text(
              _formError!,
              style: const TextStyle(fontSize: 12, color: MColors.offline),
            ),
          ],
          const SizedBox(height: 16),
          LoadingButton(
            label: t(context, 'Next', '下一步'),
            onPressed: _nextFromStep1,
          ),
        ],
      ),
    );
  }

  Widget _step2Card() {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return MCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _websiteCtrl,
            keyboardType: TextInputType.url,
            autofillHints: const [AutofillHints.url],
            decoration: InputDecoration(
              labelText: t(context, 'Website URL', '站点地址'),
              hintText: 'https://manager.example.com',
            ),
            onChanged: (_) {
              if (_formError != null) setState(() => _formError = null);
            },
          ),
          const SizedBox(height: 4),
          Text(
            t(context, 'Public base URL of this instance, no trailing slash.',
                '实例的公开访问地址，不带末尾斜杠。'),
            style: TextStyle(fontSize: 11, color: muted),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _registration,
            onChanged: (v) => setState(() => _registration = v),
            title: Text(t(context, 'Enable registration', '开放注册'),
                style: const TextStyle(fontSize: 14)),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: MColors.warning.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.gavel_outlined, size: 14, color: MColors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t(context,
                        'Public registration is subject to local laws and regulations; enabling it is at your own risk.',
                        '公开注册需遵守当地法律法规，开启风险自担。'),
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
          if (_formError != null) ...[
            const SizedBox(height: 10),
            Text(
              _formError!,
              style: const TextStyle(fontSize: 12, color: MColors.offline),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      _submitting ? null : () => setState(() => _step = 0),
                  child: Text(t(context, 'Back', '上一步')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: LoadingButton(
                  label: t(context, 'Finish', '完成'),
                  loading: _submitting,
                  onPressed: _finish,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- checklist

bool _pwdStrong(String p) =>
    p.length >= 8 &&
    RegExp(r'[A-Z]').hasMatch(p) &&
    RegExp(r'[a-z]').hasMatch(p) &&
    RegExp(r'[0-9]').hasMatch(p) &&
    RegExp(r'[^A-Za-z0-9]').hasMatch(p);

class _PwdChecklist extends StatelessWidget {
  const _PwdChecklist({required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final checks = <(bool, String)>[
      (password.length >= 8, t(context, 'At least 8 characters', '至少 8 个字符')),
      (
        RegExp(r'[A-Z]').hasMatch(password),
        t(context, 'Contains an uppercase letter', '包含大写字母')
      ),
      (
        RegExp(r'[a-z]').hasMatch(password),
        t(context, 'Contains a lowercase letter', '包含小写字母')
      ),
      (
        RegExp(r'[0-9]').hasMatch(password),
        t(context, 'Contains a digit', '包含数字')
      ),
      (
        RegExp(r'[^A-Za-z0-9]').hasMatch(password),
        t(context, 'Contains a special character', '包含特殊字符')
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (ok, label) in checks)
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
                  style:
                      TextStyle(fontSize: 12, color: ok ? MColors.online : muted),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
