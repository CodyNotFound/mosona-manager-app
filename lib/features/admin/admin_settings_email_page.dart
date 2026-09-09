import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_services.dart';
import '../../core/widgets/widgets.dart';

/// /admin/settings/email — test email + SMTP provider settings.
class AdminSettingsEmailPage extends ConsumerStatefulWidget {
  const AdminSettingsEmailPage({super.key});

  @override
  ConsumerState<AdminSettingsEmailPage> createState() =>
      _AdminSettingsEmailPageState();
}

class _AdminSettingsEmailPageState
    extends ConsumerState<AdminSettingsEmailPage> {
  final _host = TextEditingController();
  final _port = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _tls = false;

  // loaded values for diffing
  String _oHost = '';
  String _oPort = '';
  String _oUsername = '';
  String _oPassword = '';
  bool _oTls = false;

  bool _loading = true;
  bool _saving = false;
  bool _testing = false;

  ApiServices get _api => ref.read(apiProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await _api.adminSettingsGet();
      if (!mounted) return;
      setState(() {
        _host.text = s.smtpHost;
        _port.text = s.smtpPort <= 0 ? '' : s.smtpPort.toString();
        _username.text = s.smtpUsername;
        _password.text = s.smtpPassword;
        _tls = s.smtpTls;
        _oHost = s.smtpHost;
        _oPort = s.smtpPort.toString();
        _oUsername = s.smtpUsername;
        _oPassword = s.smtpPassword;
        _oTls = s.smtpTls;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showApiError(context, e);
    }
  }

  // "test" sends whatever is saved server-side — require a clean form so the
  // user cannot be misled by testing unsaved edits
  bool get _dirty =>
      _host.text != _oHost ||
      _port.text != _oPort ||
      _username.text != _oUsername ||
      _password.text != _oPassword ||
      _tls != _oTls;

  Future<void> _testEmail() async {
    if (_dirty) {
      toastWarn(
          context,
          t(context, 'Save before testing: test sends the saved config',
              '请先保存：测试发送的是已保存的配置',
              zhHk: '請先儲存：測試發送的是已儲存的設定'));
      return;
    }
    setState(() => _testing = true);
    try {
      await _api.adminTestEmail();
      if (!mounted) return;
      setState(() => _testing = false);
      toastSuccess(context,
          t(context, 'Test email sent', '测试邮件已发送'));
    } catch (e) {
      if (!mounted) return;
      setState(() => _testing = false);
      showApiError(context, e);
    }
  }

  Future<void> _save() async {
    final host = _host.text.trim();
    final username = _username.text.trim();
    final password = _password.text;
    final port = _port.text.trim().isEmpty ? '0' : _port.text.trim();
    final entries = <({String key, String value})>[
      // email_provider is fixed to smtp but still part of the settings set.
      (key: 'email_provider', value: 'smtp'),
      if (host != _oHost) (key: 'smtp_host', value: host),
      if (port != _oPort) (key: 'smtp_port', value: port),
      if (username != _oUsername) (key: 'smtp_username', value: username),
      if (password != _oPassword) (key: 'smtp_password', value: password),
      if (_tls != _oTls)
        (key: 'smtp_tls', value: _tls ? 'true' : 'false'),
    ];
    if (entries.length <= 1) {
      toastWarn(context, t(context, 'No changes', '没有变更'));
      return;
    }
    setState(() => _saving = true);
    try {
      await _api.adminSettingsSet(entries);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _oHost = host;
        _oPort = port;
        _oUsername = username;
        _oPassword = password;
        _oTls = _tls;
      });
      toastSuccess(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(t(context, 'Email', '邮件设置'))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(t(context, 'Email', '邮件设置'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            FadeSlideIn(
              delay: 0,
              child: MCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t(context, 'Test Email', '测试邮件'),
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(
                              t(context,
                                  'Send a test email to your own address',
                                  '发送一封测试邮件到你的邮箱'),
                              style: TextStyle(
                                  fontSize: 11,
                                  color:
                                      Theme.of(context).colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    LoadingButton(
                      label: t(context, 'Send', '发送'),
                      loading: _testing,
                      onPressed: _testEmail,
                    ),
                  ],
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
                    DropdownButtonFormField<String>(
                      initialValue: 'smtp',
                      items: const [
                        DropdownMenuItem(
                            value: 'smtp', child: Text('SMTP')),
                      ],
                      decoration: InputDecoration(
                        labelText: t(context, 'Provider', '提供商'),
                        isDense: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onChanged: null, // SMTP is the only provider
                    ),
                    const SizedBox(height: 12),
                    _field(t(context, 'Host', '主机'), _host,
                        hint: 'smtp.example.com'),
                    const SizedBox(height: 12),
                    _field(
                      t(context, 'Port', '端口'),
                      _port,
                      hint: '587',
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    _field(t(context, 'Username', '用户名'), _username),
                    const SizedBox(height: 12),
                    _field(t(context, 'Password', '密码'), _password,
                        obscure: true),
                    const SizedBox(height: 4),
                    SwitchListTile(
                      value: _tls,
                      onChanged: (v) => setState(() => _tls = v),
                      contentPadding: EdgeInsets.zero,
                      title: Text(t(context, 'TLS', 'TLS'),
                          style: const TextStyle(fontSize: 14)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            FadeSlideIn(
              delay: 120,
              child: LoadingButton(
                label: t(context, 'Save', '保存'),
                loading: _saving,
                onPressed: _save,
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    String? hint,
    bool obscure = false,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
