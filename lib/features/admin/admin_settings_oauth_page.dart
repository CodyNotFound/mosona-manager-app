import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_services.dart';
import '../../core/models/models.dart';
import '../../core/theme/mcolors.dart';
import '../../core/widgets/widgets.dart';

/// /admin/settings/oauth — OAuth2/OIDC provider management.
class AdminSettingsOauthPage extends ConsumerStatefulWidget {
  const AdminSettingsOauthPage({super.key});

  @override
  ConsumerState<AdminSettingsOauthPage> createState() =>
      _AdminSettingsOauthPageState();
}

class _AdminSettingsOauthPageState
    extends ConsumerState<AdminSettingsOauthPage> {
  List<OAuthProvider> _items = [];
  bool _loading = true;

  ApiServices get _api => ref.read(apiProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final page = await _api.adminOAuthList(page: 1, size: 100);
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showApiError(context, e);
    }
  }

  /// Up/down arrow reorder: optimistic local swap then persist the id order.
  Future<void> _move(int index, int delta) async {
    final j = index + delta;
    if (j < 0 || j >= _items.length) return;
    setState(() {
      final it = _items.removeAt(index);
      _items.insert(j, it);
    });
    try {
      await _api.adminOAuthSort(_items.map((e) => e.id).toList());
    } catch (e) {
      if (!mounted) return;
      showApiError(context, e);
      _load();
    }
  }

  void _openSheet([OAuthProvider? existing]) {
    showMSheet(
      context: context,
      title: existing == null
          ? t(context, 'Add Provider', '添加提供商')
          : t(context, 'Edit Provider', '编辑提供商'),
      child: _ProviderFormSheet(
        existing: existing,
        onSaved: () {
          toastSuccess(context);
          _load();
        },
      ),
    );
  }

  Future<void> _delete(OAuthProvider p) async {
    final ok = await confirmDialog(
      context,
      title: t(context, 'Delete Provider', '删除提供商'),
      message: t(context,
          'Delete OAuth provider "${p.name}"? Users will no longer be able to sign in with it.',
          '删除 OAuth 提供商“${p.name}”？用户将无法再通过它登录。'),
      okLabel: t(context, 'Delete', '删除'),
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await _api.adminOAuthDelete(p.id);
      if (!mounted) return;
      toastSuccess(context);
      _load();
    } catch (e) {
      if (!mounted) return;
      showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t(context, 'OAuth2', 'OAuth2')),
        actions: [
          IconButton(
            tooltip: t(context, 'Add Provider', '添加提供商'),
            onPressed: () => _openSheet(),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: _loading && _items.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: const [
                    Skeleton(height: 92, radius: 12),
                    SizedBox(height: 10),
                    Skeleton(height: 92, radius: 12),
                  ],
                )
              : _items.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.5,
                          child: EmptyState(
                            text: t(context, 'No OAuth providers yet',
                                '还没有 OAuth 提供商'),
                            icon: Icons.fingerprint,
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      itemCount: _items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => FadeSlideIn(
                        delay: (i > 8 ? 8 : i) * 60,
                        child: _providerCard(context, _items[i], i),
                      ),
                    ),
        ),
      ),
    );
  }

  Widget _providerCard(BuildContext context, OAuthProvider p, int index) {
    final theme = Theme.of(context);
    final df = DateFormat('yyyy-MM-dd HH:mm');
    return MCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MBadge(
                small: true,
                color: theme.colorScheme.onSurfaceVariant,
                backgroundColor:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.1),
                child: Text('#${p.id}'),
              ),
              const SizedBox(width: 8),
              if (p.icon.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.network(
                    p.icon,
                    width: 20,
                    height: 20,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.fingerprint, size: 20),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              MBadge(
                small: true,
                color: p.isEnabled ? MColors.online : MColors.offline,
                child: Text(p.isEnabled
                    ? t(context, 'enabled', '已启用')
                    : t(context, 'disabled', '已停用')),
              ),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                icon: const Icon(Icons.more_vert, size: 20),
                onSelected: (v) {
                  if (v == 'edit') _openSheet(p);
                  if (v == 'delete') _delete(p);
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: Row(children: [
                      const Icon(Icons.edit_outlined, size: 18),
                      const SizedBox(width: 10),
                      Text(t(context, 'Edit', '编辑')),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(children: [
                      const Icon(Icons.delete_outline,
                          size: 18, color: MColors.offline),
                      const SizedBox(width: 10),
                      Text(t(context, 'Delete', '删除'),
                          style: const TextStyle(color: MColors.offline)),
                    ]),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${p.protocol.toUpperCase()} · ${t(context, 'Updated', '更新于')} '
            '${p.updatedAt == null ? '--' : df.format(p.updatedAt!)} · '
            '${t(context, 'Created', '创建于')} '
            '${p.createdAt == null ? '--' : df.format(p.createdAt!)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: t(context, 'Move up', '上移'),
                onPressed: index == 0 ? null : () => _move(index, -1),
                icon: const Icon(Icons.arrow_upward, size: 18),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: t(context, 'Move down', '下移'),
                onPressed:
                    index == _items.length - 1 ? null : () => _move(index, 1),
                icon: const Icon(Icons.arrow_downward, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------- sheet

/// Well-known provider templates (web §3.24) used to prefill the form.
const _templates = <String, ({String icon, String auth, String token, String userinfo, String scopes, String subject})>{
  'Github': (
    icon: 'https://github.githubassets.com/favicons/favicon.svg',
    auth: 'https://github.com/login/oauth/authorize',
    token: 'https://github.com/login/oauth/access_token',
    userinfo: 'https://api.github.com/user',
    scopes: 'read:user user:email',
    subject: 'login',
  ),
  'Gitlab': (
    icon: 'https://gitlab.com/favicon.ico',
    auth: 'https://gitlab.com/oauth/authorize',
    token: 'https://gitlab.com/oauth/token',
    userinfo: 'https://gitlab.com/api/v4/user',
    scopes: 'read_user',
    subject: 'id',
  ),
  'Google': (
    icon: 'https://www.google.com/favicon.ico',
    auth: 'https://accounts.google.com/o/oauth2/v2/auth',
    token: 'https://oauth2.googleapis.com/token',
    userinfo: 'https://openidconnect.googleapis.com/v1/userinfo',
    scopes: 'openid email profile',
    subject: 'sub',
  ),
  'Discord': (
    icon: 'https://discord.com/favicon.ico',
    auth: 'https://discord.com/oauth2/authorize',
    token: 'https://discord.com/api/oauth2/token',
    userinfo: 'https://discord.com/api/users/@me',
    scopes: 'identify email',
    subject: 'id',
  ),
  'Microsoft': (
    icon: 'https://www.microsoft.com/favicon.ico',
    auth: 'https://login.microsoftonline.com/common/oauth2/v2.0/authorize',
    token: 'https://login.microsoftonline.com/common/oauth2/v2.0/token',
    userinfo: 'https://graph.microsoft.com/oidc/userinfo',
    scopes: 'openid email profile',
    subject: 'sub',
  ),
  'Meta Facebook': (
    icon: 'https://www.facebook.com/favicon.ico',
    auth: 'https://www.facebook.com/v19.0/dialog/oauth',
    token: 'https://graph.facebook.com/v19.0/oauth/access_token',
    userinfo: 'https://graph.facebook.com/me',
    scopes: 'email public_profile',
    subject: 'id',
  ),
  'X (Twitter)': (
    icon: 'https://abs.twimg.com/favicons/twitter.3.ico',
    auth: 'https://twitter.com/i/oauth2/authorize',
    token: 'https://api.twitter.com/2/oauth2/token',
    userinfo: 'https://api.twitter.com/2/users/me',
    scopes: 'users.read tweet.read',
    subject: 'id',
  ),
  'LinkedIn': (
    icon: 'https://www.linkedin.com/favicon.ico',
    auth: 'https://www.linkedin.com/oauth/v2/authorization',
    token: 'https://www.linkedin.com/oauth/v2/accessToken',
    userinfo: 'https://api.linkedin.com/v2/userinfo',
    scopes: 'openid profile email',
    subject: 'sub',
  ),
  'Custom': (
    icon: '',
    auth: '',
    token: '',
    userinfo: '',
    scopes: '',
    subject: 'login',
  ),
};

class _ProviderFormSheet extends ConsumerStatefulWidget {
  const _ProviderFormSheet({this.existing, required this.onSaved});

  final OAuthProvider? existing;
  final VoidCallback onSaved;

  @override
  ConsumerState<_ProviderFormSheet> createState() => _ProviderFormSheetState();
}

class _ProviderFormSheetState extends ConsumerState<_ProviderFormSheet> {
  late final OAuthProvider? _existing = widget.existing;

  late final _name = TextEditingController(text: _existing?.name ?? '');
  late final _icon = TextEditingController(text: _existing?.icon ?? '');
  late final _auth = TextEditingController(text: _existing?.authUrl ?? '');
  late final _token = TextEditingController(text: _existing?.tokenUrl ?? '');
  late final _userinfo =
      TextEditingController(text: _existing?.userinfoUrl ?? '');
  late final _issuer =
      TextEditingController(text: _existing?.issuerUrl ?? '');
  late final _scopes = TextEditingController(text: _existing?.scopes ?? '');
  late final _clientId =
      TextEditingController(text: _existing?.clientId ?? '');
  late final _clientSecret =
      TextEditingController(text: _existing?.clientSecret ?? '');

  late String _protocol = _existing?.protocol ?? 'oauth2'; // oauth2 | oidc
  late String _subject = _initSubject();
  late bool _skip2fa = _existing?.skip2fa ?? true;
  late bool _enabled = _existing?.isEnabled ?? true;
  String? _template;
  bool _saving = false;

  ApiServices get _api => ref.read(apiProvider);

  String _initSubject() {
    final f = widget.existing?.subjectField ?? '';
    return f.isEmpty ? 'login' : f;
  }

  @override
  void dispose() {
    _name.dispose();
    _icon.dispose();
    _auth.dispose();
    _token.dispose();
    _userinfo.dispose();
    _issuer.dispose();
    _scopes.dispose();
    _clientId.dispose();
    _clientSecret.dispose();
    super.dispose();
  }

  void _applyTemplate(String name) {
    setState(() => _template = name);
    final tpl = _templates[name];
    if (tpl == null) return;
    _icon.text = tpl.icon;
    _auth.text = tpl.auth;
    _token.text = tpl.token;
    _userinfo.text = tpl.userinfo;
    _scopes.text = tpl.scopes;
    _subject = tpl.subject;
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final clientId = _clientId.text.trim();
    final clientSecret = _clientSecret.text.trim();
    if (name.isEmpty || clientId.isEmpty || clientSecret.isEmpty) {
      toastWarn(
          context, t(context, 'Name / Client ID / Secret are required', '名称 / Client ID / Secret 必填'));
      return;
    }
    final form = <String, dynamic>{
      'name': name,
      'icon': _icon.text.trim(),
      'protocol': _protocol,
      'issuer_url': _protocol == 'oidc' ? _issuer.text.trim() : '',
      'auth_url': _protocol == 'oauth2' ? _auth.text.trim() : '',
      'token_url': _protocol == 'oauth2' ? _token.text.trim() : '',
      'userinfo_url': _protocol == 'oauth2' ? _userinfo.text.trim() : '',
      'scopes': _scopes.text.trim(),
      'subject_field': _protocol == 'oauth2' ? _subject : 'sub',
      'client_id': clientId,
      'client_secret': clientSecret,
      'skip_2fa': _skip2fa ? 'true' : 'false',
      'is_enabled': _enabled ? 'true' : 'false',
    };
    setState(() => _saving = true);
    try {
      if (_existing == null) {
        await _api.adminOAuthAdd(form);
      } else {
        await _api.adminOAuthUpdate(_existing.id, form);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onSaved();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOauth2 = _protocol == 'oauth2';
    Widget field(String label, TextEditingController c,
            {String? hint, bool obscure = false}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            controller: c,
            obscureText: obscure,
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              isDense: true,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        field(t(context, 'Name *', '名称 *'), _name, hint: 'Github'),
        DropdownButtonFormField<String>(
          key: ValueKey(_template),
          initialValue: _template,
          isDense: true,
          decoration: InputDecoration(
            labelText: t(context, 'Provider template', '提供商模板'),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          items: _templates.keys
              .map((k) => DropdownMenuItem(
                  value: k,
                  child: Text(k, style: const TextStyle(fontSize: 13))))
              .toList(),
          onChanged: (v) {
            if (v != null) _applyTemplate(v);
          },
        ),
        const SizedBox(height: 16),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'oauth2', label: Text('OAuth2')),
            ButtonSegment(value: 'oidc', label: Text('OIDC')),
          ],
          selected: {_protocol},
          onSelectionChanged: (s) => setState(() => _protocol = s.first),
        ),
        const SizedBox(height: 12),
        if (isOauth2) ...[
          field('Auth URL', _auth),
          field('Token URL', _token),
          field('Userinfo URL', _userinfo),
          DropdownButtonFormField<String>(
            key: ValueKey(_subject),
            initialValue: _subject,
            isDense: true,
            decoration: InputDecoration(
              labelText: t(context, 'Subject field', 'Subject 字段'),
              isDense: true,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            items: const ['login', 'id', 'email', 'sub']
                .map((s) =>
                    DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: (v) => setState(() => _subject = v ?? 'login'),
          ),
          const SizedBox(height: 12),
        ] else ...[
          field('Issuer URL', _issuer, hint: 'https://accounts.example.com'),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Text('${t(context, 'Subject field', 'Subject 字段')}: ',
                    style: const TextStyle(fontSize: 13)),
                const Text('sub',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
        field(t(context, 'Icon URL', '图标 URL'), _icon),
        field(t(context, 'Scopes', 'Scopes'), _scopes, hint: 'read:user user:email'),
        field('Client ID *', _clientId),
        field('Client Secret *', _clientSecret, obscure: true),
        CheckboxListTile(
          value: _skip2fa,
          onChanged: (v) => setState(() => _skip2fa = v ?? true),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(
              t(context, 'Skip 2FA for OAuth login', 'OAuth 登录跳过两步验证'),
              style: const TextStyle(fontSize: 13)),
        ),
        SwitchListTile(
          value: _enabled,
          onChanged: (v) => setState(() => _enabled = v),
          contentPadding: EdgeInsets.zero,
          title: Text(t(context, 'Enabled', '启用'),
              style: const TextStyle(fontSize: 13)),
        ),
        const SizedBox(height: 8),
        LoadingButton(
          label: _existing == null
              ? t(context, 'Add', '添加')
              : t(context, 'Save', '保存'),
          loading: _saving,
          onPressed: _submit,
        ),
      ],
    );
  }
}
