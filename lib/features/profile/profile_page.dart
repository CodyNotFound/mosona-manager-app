import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_services.dart';
import '../../core/models/models.dart';
import '../../core/state/session.dart';
import '../../core/theme/mcolors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/widgets.dart';
import '../team/avatar.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  List<AuthIdentity>? _identities;
  ({String current, List<UserSession> list})? _sessions;

  final _username = TextEditingController();
  bool _savingUsername = false;

  ApiServices get _api => ref.read(apiProvider);

  @override
  void initState() {
    super.initState();
    final user = ref.read(sessionProvider).user;
    _username.text = user?.username ?? '';
    _loadIdentities();
    _loadSessions();
  }

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  Future<void> _loadIdentities() async {
    try {
      final list = await _api.oauthIdentities();
      if (!mounted) return;
      setState(() => _identities = list);
    } catch (_) {
      if (mounted) setState(() => _identities = []);
    }
  }

  Future<void> _loadSessions() async {
    try {
      final s = await _api.sessions();
      if (!mounted) return;
      setState(() => _sessions = s);
    } catch (_) {
      if (mounted) setState(() => _sessions = null);
    }
  }

  Future<void> _refresh() => ref.read(sessionProvider.notifier).refresh();

  // -------------------------------------------------------------- username

  Future<void> _saveUsername() async {
    if (_savingUsername) return;
    final name = _username.text.trim();
    if (name.isEmpty || name == ref.read(sessionProvider).user?.username) return;
    setState(() => _savingUsername = true);
    try {
      await _api.changeUsername(name);
      if (!mounted) return;
      await _refresh();
      if (mounted) toastSuccess(context);
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _savingUsername = false);
    }
  }

  // ------------------------------------------------------------------ totp

  Future<void> _toggleTotp(bool enable) async {
    if (enable) {
      await _enableTotp();
    } else {
      await _disableTotp();
    }
  }

  Future<void> _enableTotp() async {
    try {
      final setup = await _api.totpEnable();
      if (!mounted) return;
      final ok = await showMSheet<bool>(
        context: context,
        title: t(context, 'Enable two-factor authentication', '开启两步验证'),
        child: _TotpEnableSheet(
          setup: setup,
          onConfirm: (code) => _api.totpConfirm(setup.secret, code),
        ),
      );
      if (ok == true && mounted) {
        await _refresh();
        if (mounted) toastSuccess(context);
      }
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _disableTotp() async {
    final first = await _askCode(t(context, 'Two-factor authentication', '两步验证'),
        t(context, 'Enter your authenticator code', '输入验证器代码'));
    if (first == null || !mounted) return;
    try {
      try {
        await _api.totpDisable(first);
      } on ApiException catch (e) {
        if (e.code != 'verify') {
          if (mounted) showApiError(context, e);
          return;
        }
        if (!mounted) return;
        final emailCode = await _askCode(
            t(context, 'Email verification required', '需要邮箱验证'),
            t(context, 'Enter the code sent to your email', '输入邮件验证码'));
        if (emailCode == null || !mounted) return;
        await _api.totpDisable(emailCode);
      }
      await _refresh();
      if (mounted) toastSuccess(context);
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<String?> _askCode(String title, String label) {
    return showMSheet<String>(
      context: context,
      title: title,
      child: _CodeInputSheet(label: label),
    );
  }

  // ----------------------------------------------------------------- oauth

  Future<void> _connectIdentity(AuthIdentity identity) async {
    try {
      final login = await _api.oauthLogin(identity.id);
      await launchExternal(login.url);
      if (!mounted) return;
      toastWarn(context, t(context, 'Complete linking in the browser', '在浏览器中完成绑定'));
      await _loadIdentities();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _disconnectIdentity(AuthIdentity identity) async {
    final ok = await confirmDialog(
      context,
      title: t(context, 'Unlink ${identity.name}', '解绑 ${identity.name}'),
      message: t(context,
          'This removes the link between your account and ${identity.name}.',
          '这将解除账号与 ${identity.name} 的绑定。'),
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await _api.revokeOAuthIdentity(identity.id);
      if (!mounted) return;
      await _loadIdentities();
      if (mounted) toastSuccess(context);
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  // ----------------------------------------------------------------- teams

  Future<void> _leaveTeam(Team team) async {
    final wasActive = ref.read(sessionProvider).team?.id == team.id;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmNameDialog(
        title: t(context, 'Leave team', '退出团队'),
        message: t(
          context,
          'Type the team name "${team.name}" to confirm leaving this team.',
          '输入团队名称 "${team.name}" 以确认退出该团队。',
        ),
        name: team.name,
        confirmLabel: t(context, 'Leave', '退出'),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _api.leaveTeam(team.id);
      await _refresh();
      if (!mounted) return;
      toastSuccess(context);
      if (wasActive) context.go('/create-team');
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  // -------------------------------------------------------------- sessions

  Future<void> _revokeAll() async {
    final ok = await confirmDialog(
      context,
      title: t(context, 'Revoke all sessions', '吊销全部会话'),
      message: t(context,
          'Every signed-in session (including this device) will be logged out.',
          '所有已登录会话（包括本设备）都将被注销。'),
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await _api.revokeAllSessions();
      await ref.read(sessionProvider.notifier).bootstrap();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _revokeSession(UserSession s) async {
    final ok = await confirmDialog(
      context,
      title: t(context, 'Revoke session', '吊销会话'),
      message: t(context, 'This device will be signed out.', '该设备将被注销登录。'),
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await _api.revokeSession(s.id);
      if (s.id == _sessions?.current) {
        await ref.read(sessionProvider.notifier).bootstrap();
        return;
      }
      if (!mounted) return;
      await _loadSessions();
      if (mounted) toastSuccess(context);
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  // ----------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = ref.watch(sessionProvider).user;
    return Scaffold(
      appBar: AppBar(title: Text(t(context, 'Profile', '个人资料'))),
      body: SafeArea(
        child: user == null
            ? ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  EmptyState(text: t(context, 'Not signed in', '未登录')),
                ],
              )
            : RefreshIndicator(
                onRefresh: () async {
                  await _refresh();
                  await _loadIdentities();
                  await _loadSessions();
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    PageHeader(
                        title: t(context, 'Profile', '个人资料'),
                        description: user.email),
                    FadeSlideIn(child: _userCard(theme, user)),
                    const SizedBox(height: 16),
                    FadeSlideIn(delay: 60, child: _accountCard(theme, user)),
                    const SizedBox(height: 16),
                    FadeSlideIn(delay: 120, child: _securityCard(theme, user)),
                    const SizedBox(height: 16),
                    FadeSlideIn(delay: 180, child: _oauthCard(theme)),
                    const SizedBox(height: 16),
                    FadeSlideIn(delay: 240, child: _teamsCard(theme)),
                    const SizedBox(height: 16),
                    FadeSlideIn(delay: 300, child: _sessionsCard(theme)),
                  ],
                ),
              ),
      ),
    );
  }

  // 1. user
  Widget _userCard(ThemeData theme, User user) {
    return MCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Gravatar(email: user.email, size: 64),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.username,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(user.email,
                        style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Text(
                      t(context,
                          'Joined ${DateFormat('yyyy-MM-dd').format(user.createdAt)}',
                          '注册于 ${DateFormat('yyyy-MM-dd').format(user.createdAt)}'),
                      style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          InkWell(
            onTap: () => launchExternal('https://gravatar.com'),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 16, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Text(
                    t(context,
                        'Avatar is served from gravatar.com — change it there',
                        '头像来自 gravatar.com — 可在该网站修改'),
                    style: TextStyle(
                        fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const Spacer(),
                  const Icon(Icons.open_in_new, size: 14, color: MColors.link),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 2. account
  Widget _accountCard(ThemeData theme, User user) {
    return MCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t(context, 'Account', '账户'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _username,
                  decoration: InputDecoration(
                    labelText: t(context, 'Username', '用户名'),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: LoadingButton(
                  label: t(context, 'Save', '保存'),
                  loading: _savingUsername,
                  onPressed: _saveUsername,
                ),
              ),
            ],
          ),
          const Divider(height: 22),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t(context, 'Password', '密码'),
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      t(
                          context,
                          'Changed ${user.pwdAt == null ? '--' : DateFormat('yyyy-MM-dd').format(user.pwdAt!)}',
                          '修改于 ${user.pwdAt == null ? '--' : DateFormat('yyyy-MM-dd').format(user.pwdAt!)}'),
                      style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              MBadge(
                color: MColors.warning,
                small: true,
                child: Text(t(context, 'Coming Soon', '即将上线')),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: null,
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(t(context, 'Change Password', '修改密码'),
                    style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 3. security
  Widget _securityCard(ThemeData theme, User user) {
    final enabled = user.totpEnabled == true;
    return MCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t(context, 'Security', '安全'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t(context, 'Two-factor authentication (TOTP)', '两步验证（TOTP）'),
                        style: const TextStyle(fontSize: 13)),
                    Text(
                      t(context,
                          'Require a one-time code in addition to your password.',
                          '登录与敏感操作需输入一次性验证码。'),
                      style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Switch(value: enabled, onChanged: (v) => _toggleTotp(v)),
            ],
          ),
        ],
      ),
    );
  }

  // 4. oauth
  Widget _oauthCard(ThemeData theme) {
    final identities = _identities;
    return MCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t(context, 'Connected accounts', '第三方账号'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (identities == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            )
          else if (identities.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                t(context, 'No OAuth providers configured on this server.',
                    '本服务器未配置第三方登录。'),
                style: TextStyle(
                    fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
              ),
            )
          else
            for (var i = 0; i < identities.length; i++) ...[
              if (i > 0) const Divider(height: 18),
              _identityRow(theme, identities[i]),
            ],
        ],
      ),
    );
  }

  Widget _identityRow(ThemeData theme, AuthIdentity identity) {
    return Row(
      children: [
        SizedBox(
          width: 32,
          height: 32,
          child: identity.icon.startsWith('http')
              ? Image.network(
                  identity.icon,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.link, size: 24),
                )
              : const Icon(Icons.link, size: 24),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(identity.name,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              Text(
                identity.linked
                    ? identity.linkedEmail
                    : t(context, 'Not linked', '未绑定'),
                style: TextStyle(
                    fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        if (identity.linked)
          TextButton(
            style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
            onPressed: () => _disconnectIdentity(identity),
            child: Text(t(context, 'Disconnect', '解绑'),
                style: const TextStyle(fontSize: 13)),
          )
        else
          OutlinedButton(
            onPressed: () => _connectIdentity(identity),
            child: Text(t(context, 'Connect', '绑定'),
                style: const TextStyle(fontSize: 13)),
          ),
      ],
    );
  }

  // 5. teams
  Widget _teamsCard(ThemeData theme) {
    final teams = ref.watch(sessionProvider).teams;
    return MCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t(context, 'Teams', '团队'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (teams.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(t(context, 'No teams yet.', '暂无团队。'),
                  style: TextStyle(
                      fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
            )
          else
            for (var i = 0; i < teams.length; i++) ...[
              if (i > 0) const Divider(height: 18),
              Row(
                children: [
                  TeamAvatar(name: teams[i].name, colorHex: teams[i].color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(teams[i].name,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        Text(
                          t(context,
                              'Created ${DateFormat('yyyy-MM-dd').format(teams[i].createdAt)}',
                              '创建于 ${DateFormat('yyyy-MM-dd').format(teams[i].createdAt)}'),
                          style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.error),
                    onPressed: () => _leaveTeam(teams[i]),
                    child: Text(t(context, 'Leave', '退出'),
                        style: const TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ],
        ],
      ),
    );
  }

  // 6. sessions
  Widget _sessionsCard(ThemeData theme) {
    final sessions = _sessions;
    return MCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(t(context, 'Sessions', '会话'),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton(
                style:
                    TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                onPressed: _revokeAll,
                child: Text(t(context, 'Revoke all', '全部吊销'),
                    style: const TextStyle(fontSize: 13)),
              ),
            ],
          ),
          if (sessions == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            )
          else
            for (var i = 0; i < sessions.list.length; i++) ...[
              if (i > 0) const Divider(height: 18),
              _sessionRow(theme, sessions.list[i], sessions.current),
            ],
        ],
      ),
    );
  }

  Widget _sessionRow(ThemeData theme, UserSession s, String current) {
    final (browser, os) = uaSummary(s.userAgent);
    final isCurrent = s.id == current;
    return Row(
      children: [
        Icon(_deviceIcon(os), size: 22, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Icon(Icons.language, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text('$browser ($os)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                  if (isCurrent) ...[
                    const SizedBox(width: 6),
                    MBadge(
                      color: MColors.online,
                      small: true,
                      child: Text(t(context, 'Current', '当前')),
                    ),
                  ],
                ],
              ),
              Text(
                '${DateFormat('yyyy-MM-dd HH:mm').format(s.time.toLocal())}'
                '${s.clientIp.isEmpty ? '' : ' · ${s.clientIp}'}',
                style: TextStyle(
                    fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.logout,
              size: 18, color: theme.colorScheme.error),
          onPressed: () => _revokeSession(s),
        ),
      ],
    );
  }

  IconData _deviceIcon(String os) => switch (os) {
        'iOS' || 'Android' => Icons.smartphone,
        'macOS' || 'Windows' || 'Linux' => Icons.computer,
        _ => Icons.devices_other,
      };
}

class _TotpEnableSheet extends StatefulWidget {
  const _TotpEnableSheet({required this.setup, required this.onConfirm});

  final ({String secret, String url}) setup;
  final Future<void> Function(String code) onConfirm;

  @override
  State<_TotpEnableSheet> createState() => _TotpEnableSheetState();
}

class _TotpEnableSheetState extends State<_TotpEnableSheet> {
  final _code = TextEditingController();
  bool _loading = false;

  bool get _valid => RegExp(r'^\d{6}$').hasMatch(_code.text.trim());

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_loading || !_valid) return;
    setState(() => _loading = true);
    try {
      await widget.onConfirm(_code.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showApiError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t(context,
              '1. Scan this QR code with your authenticator app, or add the secret manually.',
              '1. 用验证器 App 扫描二维码，或手动输入密钥。'),
          style: TextStyle(
              fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 14),
        Center(
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: QrImageView(
              data: widget.setup.url,
              size: 180,
              backgroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                widget.setup.secret,
                style: monoStyle(context, size: 13),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.copy_outlined, size: 18),
              onPressed: () async {
                await Clipboard.setData(
                    ClipboardData(text: widget.setup.secret));
                if (context.mounted) {
                  toastSuccess(context, t(context, 'Copied', '已复制'));
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          t(context,
              '2. Enter the 6-digit code from your authenticator app to confirm.',
              '2. 输入验证器 App 中的 6 位验证码以确认。'),
          style: TextStyle(
              fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _code,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: t(context, '6-digit code', '6 位验证码'),
            isDense: true,
            border: const OutlineInputBorder(),
            counterText: '',
          ),
        ),
        const SizedBox(height: 14),
        LoadingButton(
          label: t(context, 'Confirm', '确认'),
          loading: _loading,
          onPressed: _valid ? _confirm : null,
        ),
      ],
    );
  }
}

class _CodeInputSheet extends StatefulWidget {
  const _CodeInputSheet({required this.label});

  final String label;

  @override
  State<_CodeInputSheet> createState() => _CodeInputSheetState();
}

class _CodeInputSheetState extends State<_CodeInputSheet> {
  final _code = TextEditingController();

  bool get _valid => _code.text.trim().isNotEmpty;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _code,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 8,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: widget.label,
            isDense: true,
            border: const OutlineInputBorder(),
            counterText: '',
          ),
        ),
        const SizedBox(height: 14),
        LoadingButton(
          label: t(context, 'Confirm', '确认'),
          onPressed:
              _valid ? () => Navigator.of(context).pop(_code.text.trim()) : null,
        ),
      ],
    );
  }
}
