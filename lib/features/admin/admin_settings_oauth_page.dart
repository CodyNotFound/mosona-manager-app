import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_services.dart';
import '../../core/models/models.dart';
import '../../core/state/controllers.dart';
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
  /// Per-page options mirror the web BottomPagination select.
  static const _perPageOptions = [20, 50, 100, 500, 1000];

  List<OAuthProvider> _items = [];
  int _total = 0;
  int _page = 1;
  int _perPage = 20;
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
      final page = await _api.adminOAuthList(page: _page, size: _perPage);
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _total = page.total;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showApiError(context, e);
    }
  }

  int get _totalPages => _total <= 0 ? 1 : (_total / _perPage).ceil();

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
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      itemCount: _items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => FadeSlideIn(
                        delay: (i > 8 ? 8 : i) * 60,
                        child: _providerCard(context, _items[i], i),
                      ),
                    ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: _page > 1
                    ? () {
                        _page--;
                        _load();
                      }
                    : null,
                icon: const Icon(Icons.chevron_left),
              ),
              const SizedBox(width: 8),
              Text(
                t(context, 'Page $_page / $_totalPages', '第 $_page / $_totalPages 页'),
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _page < _totalPages
                    ? () {
                        _page++;
                        _load();
                      }
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
              const SizedBox(width: 8),
              DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _perPage,
                  isDense: true,
                  borderRadius: BorderRadius.circular(10),
                  items: [
                    for (final s in _perPageOptions)
                      DropdownMenuItem<int>(
                        value: s,
                        child: Text(t(context, '$s / page', '$s 条/页'),
                            style: const TextStyle(fontSize: 13)),
                      ),
                  ],
                  onChanged: (v) {
                    if (v == null || v == _perPage) return;
                    setState(() {
                      _perPage = v;
                      _page = 1;
                    });
                    _load();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Resolves a provider icon for display (web OAuthIcon): full URLs render
  /// directly, known short names map to /icons/{name}.svg on the hub.
  Widget _providerIcon(BuildContext context, String icon, {double size = 20}) {
    if (icon.isEmpty) {
      return Icon(Icons.fingerprint, size: size);
    }
    if (icon.startsWith('http')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.network(
          icon,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Icon(Icons.fingerprint, size: size),
        ),
      );
    }
    const known = ['google', 'github', 'discord', 'gitlab', 'microsoft', 'meta', 'x', 'linkedin'];
    if (known.contains(icon.toLowerCase())) {
      final base = ref.read(serverConfigProvider);
      if (base.isNotEmpty) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.network(
            '$base/icons/${icon.toLowerCase()}.svg',
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Icon(Icons.fingerprint, size: size),
          ),
        );
      }
    }
    return Icon(Icons.fingerprint, size: size);
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
                _providerIcon(context, p.icon),
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

/// Well-known provider templates, values mirror the web built-in list
/// (admin/page/settings/oauth/oauth.ts): the icon is a short provider name
/// rendered from /icons/{name}.svg, not a URL.
const _templates = <String, ({String icon, String auth, String token, String userinfo, String scopes, String subject})>{
  'Github': (
    icon: 'github',
    auth: 'https://github.com/login/oauth/authorize',
    token: 'https://github.com/login/oauth/access_token',
    userinfo: 'https://api.github.com/user',
    scopes: 'read:user read:email',
    subject: 'id',
  ),
  'Gitlab': (
    icon: 'gitlab',
    auth: 'https://gitlab.com/oauth/authorize',
    token: 'https://gitlab.com/oauth/token',
    userinfo: 'https://gitlab.com/api/v4/user',
    scopes: 'read:user read:email',
    subject: 'id',
  ),
  'Google': (
    icon: 'google',
    auth: 'https://accounts.google.com/o/oauth2/v2/auth',
    token: 'https://oauth2.googleapis.com/token',
    userinfo: 'https://www.googleapis.com/oauth2/v2/userinfo',
    scopes: 'read:user read:email',
    subject: 'id',
  ),
  'Discord': (
    icon: 'discord',
    auth: 'https://discord.com/api/oauth2/authorize',
    token: 'https://discord.com/api/oauth2/token',
    userinfo: 'https://discord.com/api/users/@me',
    scopes: 'read:user read:email',
    subject: 'id',
  ),
  'Microsoft': (
    icon: 'microsoft',
    auth: 'https://login.microsoftonline.com/common/oauth2/v2.0/authorize',
    token: 'https://login.microsoftonline.com/common/oauth2/v2.0/token',
    userinfo: 'https://graph.microsoft.com/v1.0/me',
    scopes: 'read:user read:email',
    subject: 'id',
  ),
  'Meta Facebook': (
    icon: 'meta',
    auth: 'https://www.facebook.com/v19.0/dialog/oauth',
    token: 'https://graph.facebook.com/v19.0/oauth/access_token',
    userinfo: 'https://graph.facebook.com/me?fields=id,name,email,picture',
    scopes: 'read:user read:email',
    subject: 'id',
  ),
  'X (Twitter)': (
    icon: 'x',
    auth: 'https://twitter.com/i/oauth2/authorize',
    token: 'https://api.twitter.com/2/oauth2/token',
    userinfo: 'https://api.twitter.com/2/users/me',
    scopes: 'read:user read:email',
    subject: 'id',
  ),
  'LinkedIn': (
    icon: 'linkedin',
    auth: 'https://www.linkedin.com/oauth/v2/authorization',
    token: 'https://www.linkedin.com/oauth/v2/accessToken',
    userinfo: 'https://api.linkedin.com/v2/me',
    scopes: 'read:user read:email',
    subject: 'id',
  ),
  'Custom': (
    icon: '',
    auth: '',
    token: '',
    userinfo: '',
    scopes: 'read:user read:email',
    subject: 'id',
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
  late final _subjectCtrl = TextEditingController(text: _initSubject());

  late String _protocol = _existing?.protocol ?? 'oauth2'; // oauth2 | oidc
  late String _subject = _initSubject();
  late bool _skip2fa = _existing?.skip2fa ?? true;
  late bool _enabled = _existing?.isEnabled ?? true;
  String? _template;
  bool _saving = false;

  ApiServices get _api => ref.read(apiProvider);

  String _initSubject() {
    final f = widget.existing?.subjectField ?? '';
    return f.isEmpty ? 'id' : f;
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
    _subjectCtrl.dispose();
    super.dispose();
  }

  void _applyTemplate(String name) {
    setState(() => _template = name);
    final tpl = _templates[name];
    if (tpl == null) return;
    // Web resets the whole form section on template selection
    // (admin/page/settings/oauth/components/add.tsx:53-65).
    _name.text = name;
    _icon.text = tpl.icon;
    _auth.text = tpl.auth;
    _token.text = tpl.token;
    _userinfo.text = tpl.userinfo;
    _issuer.text = '';
    _protocol = 'oauth2';
    _scopes.text = tpl.scopes;
    _subject = tpl.subject;
    _subjectCtrl.text = _subject;
  }

  void _switchProtocol(String protocol) {
    setState(() {
      _protocol = protocol;
      // Web parity: protocol switch updates the scope/subject defaults
      // (add.tsx:224-234).
      _scopes.text =
          protocol == 'oidc' ? 'openid profile email' : 'read:user read:email';
      _subject = protocol == 'oidc' ? 'sub' : 'id';
      _subjectCtrl.text = _subject;
    });
  }

  Future<void> _submit() async {
    // Required fields mirror the web form's HTML `required` attributes
    // (add.tsx:154-346).
    final name = _name.text.trim();
    final icon = _icon.text.trim();
    final clientId = _clientId.text.trim();
    final clientSecret = _clientSecret.text.trim();
    final missing = <String>[];
    if (name.isEmpty) missing.add(t(context, 'Name', '名称'));
    if (icon.isEmpty) missing.add(t(context, 'Icon', '图标'));
    if (_protocol == 'oidc') {
      if (_issuer.text.trim().isEmpty) missing.add('Issuer URL');
    } else {
      if (_auth.text.trim().isEmpty) missing.add('Auth URL');
      if (_token.text.trim().isEmpty) missing.add('Token URL');
      if (_userinfo.text.trim().isEmpty) missing.add('Userinfo URL');
    }
    if (_scopes.text.trim().isEmpty) missing.add(t(context, 'Scopes', 'Scopes'));
    if (clientId.isEmpty) missing.add('Client ID');
    if (clientSecret.isEmpty) missing.add('Client Secret');
    if (missing.isNotEmpty) {
      toastWarn(
        context,
        t(context,
            'Required fields missing: ${missing.join(', ')}',
            '必填项缺失：${missing.join('、')}'),
      );
      return;
    }
    final form = <String, dynamic>{
      'name': name,
      'icon': icon,
      'protocol': _protocol,
      'issuer_url': _protocol == 'oidc' ? _issuer.text.trim() : '',
      'auth_url': _protocol == 'oauth2' ? _auth.text.trim() : '',
      'token_url': _protocol == 'oauth2' ? _token.text.trim() : '',
      'userinfo_url': _protocol == 'oauth2' ? _userinfo.text.trim() : '',
      'scopes': _scopes.text.trim(),
      'subject_field': _protocol == 'oauth2' ? _subject.trim() : 'sub',
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
          onSelectionChanged: (s) => _switchProtocol(s.first),
        ),
        const SizedBox(height: 12),
        if (isOauth2) ...[
          field('Auth URL *', _auth),
          field('Token URL *', _token),
          field('Userinfo URL *', _userinfo),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              controller: _subjectCtrl,
              decoration: InputDecoration(
                labelText: '${t(context, 'Subject field', 'Subject 字段')} *',
                helperText:
                    t(context, 'Field of the userinfo response used as the subject.',
                        '用作 subject 的 userinfo 响应字段。'),
                isDense: true,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: (v) => _subject = v,
            ),
          ),
        ] else ...[
          field('Issuer URL *', _issuer, hint: 'https://accounts.example.com'),
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
        field('${t(context, 'Icon URL / name', '图标 URL / 名称')} *', _icon),
        field('${t(context, 'Scopes', 'Scopes')} *', _scopes,
            hint: 'read:user read:email'),
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
