import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_services.dart';
import '../../core/widgets/widgets.dart';

/// /admin/settings/register-login — registration & captcha settings.
class AdminSettingsRegisterPage extends ConsumerStatefulWidget {
  const AdminSettingsRegisterPage({super.key});

  @override
  ConsumerState<AdminSettingsRegisterPage> createState() =>
      _AdminSettingsRegisterPageState();
}

class _AdminSettingsRegisterPageState
    extends ConsumerState<AdminSettingsRegisterPage> {
  final _siteKey = TextEditingController();
  final _secret = TextEditingController();

  // loaded values for diffing (secret submits as `captcha_secret` but the
  // GET payload exposes it as `captcha_secret_key`).
  String _oSiteKey = '';
  String _oSecret = '';

  late bool _regEnabled = false;
  late bool _regVerifyEmail = false;
  late bool _emailVerifyLogin = false;

  bool _loading = true;
  bool _saving = false;

  ApiServices get _api => ref.read(apiProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _siteKey.dispose();
    _secret.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await _api.adminSettingsGet();
      if (!mounted) return;
      setState(() {
        _regEnabled = s.registrationEnabled;
        _regVerifyEmail = s.registrationVerifyEmail;
        _emailVerifyLogin = s.emailVerifyLogin;
        _siteKey.text = s.captchaSiteKey;
        _secret.text = s.captchaSecretKey;
        _oSiteKey = s.captchaSiteKey;
        _oSecret = s.captchaSecretKey;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showApiError(context, e);
    }
  }

  /// Toggle switches save immediately.
  Future<void> _setFlag(String key, bool v) async {
    try {
      await _api.adminSettingsSet([(key: key, value: v ? 'true' : 'false')]);
      if (!mounted) return;
      toastSuccess(context);
    } catch (e) {
      if (!mounted) return;
      showApiError(context, e);
      _load(); // revert UI to server state
    }
  }

  Future<void> _saveCaptcha() async {
    final siteKey = _siteKey.text.trim();
    final secret = _secret.text.trim();
    final entries = <({String key, String value})>[
      if (siteKey != _oSiteKey) (key: 'captcha_site_key', value: siteKey),
      if (secret != _oSecret) (key: 'captcha_secret', value: secret),
    ];
    if (entries.isEmpty) {
      toastWarn(context, t(context, 'No changes', '没有变更'));
      return;
    }
    setState(() => _saving = true);
    try {
      await _api.adminSettingsSet(entries);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _oSiteKey = siteKey;
        _oSecret = secret;
      });
      toastSuccess(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showApiError(context, e);
    }
  }

  /// Dangerous switches act immediately on the server — confirm first and
  /// revert the UI if the user backs out.
  Future<void> _confirmToggle(
      bool v, String title, void Function() apply) async {
    final ok = await confirmDialog(context,
        title: title, okLabel: t(context, 'Enable', '开启', zhHk: '開啟'));
    if (ok) {
      apply();
    } else {
      setState(() {}); // revert visual state
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(t(context, 'Register & Login', '注册与登录'))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(t(context, 'Register & Login', '注册与登录'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            FadeSlideIn(
              delay: 0,
              child: MCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: SwitchListTile(
                  value: _regEnabled,
                  onChanged: (v) => _confirmToggle(
                    v,
                    t(context, 'Enable public registration?', '开启公开注册？',
                        zhHk: '開啟公開註冊？'),
                    () {
                      setState(() => _regEnabled = v);
                      _setFlag('registration_enabled', v);
                    },
                  ),
                  contentPadding: EdgeInsets.zero,
                  title: Text(t(context, 'Registration enabled', '开放注册'),
                      style: const TextStyle(fontSize: 14)),
                  subtitle: Text(
                      t(context,
                          'Allow visitors to create accounts', '允许访客创建账号'),
                      style: const TextStyle(fontSize: 11)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            FadeSlideIn(
              delay: 60,
              child: MCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t(context, 'Email verification', '邮箱验证'),
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    SwitchListTile(
                      value: _regVerifyEmail,
                      onChanged: (v) {
                        setState(() => _regVerifyEmail = v);
                        _setFlag('registration_verify_email', v);
                      },
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                          t(context, 'Verify email on register', '注册时验证邮箱'),
                          style: const TextStyle(fontSize: 13)),
                    ),
                    SwitchListTile(
                      value: _emailVerifyLogin,
                      onChanged: (v) {
                        setState(() => _emailVerifyLogin = v);
                        _setFlag('email_verify_login', v);
                      },
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                          t(context, 'Verify email on login', '登录时验证邮箱'),
                          style: const TextStyle(fontSize: 13)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            FadeSlideIn(
              delay: 120,
              child: MCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t(context, 'Captcha', '人机验证'),
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: 'turnstile',
                      items: const [
                        DropdownMenuItem(
                            value: 'turnstile',
                            child: Text('Cloudflare Turnstile')),
                      ],
                      decoration: InputDecoration(
                        labelText: t(context, 'Provider', '提供商'),
                        isDense: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onChanged: null, // Turnstile is the only provider
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _siteKey,
                      decoration: InputDecoration(
                        labelText: t(context, 'Site Key', 'Site Key'),
                        isDense: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _secret,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: t(context, 'Secret', 'Secret'),
                        isDense: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    LoadingButton(
                      label: t(context, 'Save', '保存'),
                      loading: _saving,
                      onPressed: _saveCaptcha,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
