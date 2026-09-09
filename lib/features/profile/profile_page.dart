import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_services.dart';
import '../../core/models/models.dart';
import '../../core/state/controllers.dart' show serverConfigProvider;
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
    // Web parity (info.tsx:32-55): empty / unchanged both give feedback.
    if (name.isEmpty) {
      toastWarn(context, t(context, 'Username cannot be empty', '用户名不能为空',
          zhHk: '用戶名稱不能為空'));
      return;
    }
    if (name == ref.read(sessionProvider).user?.username) {
      toastWarn(context, t(context, 'Username unchanged', '用户名未变更',
          zhHk: '用戶名稱未變更'));
      return;
    }
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
        title: t(context, 'Enable two-factor authentication', '开启两步验证',
            zhHk: '啟用雙重驗證'),
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
    final first = await _askCode(
        t(context, 'Two-factor authentication', '两步验证', zhHk: '雙重驗證'),
        t(context, 'Enter your authenticator code', '输入验证器代码',
            zhHk: '輸入驗證器應用程式的驗證碼'));
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
        // Web parity (components/2fa.tsx:96-110): the email-code dialog has a
        // resend button with a 60s cooldown.
        final emailCode = await _askCode(
            t(context, 'Email verification required', '需要邮箱验证',
                zhHk: '需要電郵驗證'),
            t(context, 'Enter the code sent to your email', '输入邮件验证码',
                zhHk: '輸入傳送至你電郵的驗證碼'),
            resendMode: '2fa');
        if (emailCode == null || !mounted) return;
        await _api.totpDisable(emailCode);
      }
      await _refresh();
      if (mounted) toastSuccess(context);
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<String?> _askCode(String title, String label, {String? resendMode}) {
    return showMSheet<String>(
      context: context,
      title: title,
      child: _CodeInputSheet(label: label, resendMode: resendMode),
    );
  }

  // ----------------------------------------------------------------- oauth

  // 🔵 Connect stays disabled on mobile: like OAuth sign-in, the linking
  // callback lands in the browser and there is no deep-link channel to
  // return to the app, so the flow cannot be completed here.

  Future<void> _disconnectIdentity(AuthIdentity identity) async {
    final ok = await confirmDialog(
      context,
      title: t(context, 'Unlink ${identity.name}', '解绑 ${identity.name}',
          zhHk: '中斷連結 ${identity.name}'),
      message: t(context,
          'This removes the link between your account and ${identity.name}.',
          '这将解除账号与 ${identity.name} 的绑定。',
          zhHk: '這將解除帳戶與 ${identity.name} 的連結。'),
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
        title: t(context, 'Leave team', '退出团队', zhHk: '離開團隊'),
        message: t(
          context,
          'Type the team name "${team.name}" to confirm leaving this team.',
          '输入团队名称 "${team.name}" 以确认退出该团队。',
          zhHk: '輸入團隊名稱「${team.name}」以確認離開該團隊。',
        ),
        name: team.name,
        confirmLabel: t(context, 'Leave', '退出', zhHk: '離開'),
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
      title: t(context, 'Revoke all sessions', '吊销全部会话',
          zhHk: '註銷所有工作階段'),
      message: t(context,
          'Every signed-in session (including this device) will be logged out.',
          '所有已登录会话（包括本设备）都将被注销。',
          zhHk: '所有已登入的工作階段（包括本裝置）都將會登出。'),
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
      title: t(context, 'Revoke session', '吊销会话', zhHk: '註銷工作階段'),
      message: t(context, 'This device will be signed out.', '该设备将被注销登录。',
          zhHk: '此裝置將會登出。'),
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
      appBar: AppBar(title: Text(t(context, 'Profile', '个人资料', zhHk: '個人檔案'))),
      body: SafeArea(
        child: user == null
            ? ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  EmptyState(
                      text: t(context, 'Not signed in', '未登录', zhHk: '未登入')),
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
                        title: t(context, 'Profile', '个人资料', zhHk: '個人檔案'),
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
                          '注册于 ${DateFormat('yyyy-MM-dd').format(user.createdAt)}',
                          zhHk:
                              '加入於 ${DateFormat('yyyy-MM-dd').format(user.createdAt)}'),
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
                        '头像来自 gravatar.com — 可在该网站修改',
                        zhHk: '頭像來自 gravatar.com — 可在該網站更改'),
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
          Text(t(context, 'Account', '账户', zhHk: '帳戶'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _username,
                  decoration: InputDecoration(
                    labelText: t(context, 'Username', '用户名', zhHk: '用戶名稱'),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: LoadingButton(
                  label: t(context, 'Save', '保存', zhHk: '儲存'),
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
                    Text(t(context, 'Password', '密码', zhHk: '密碼'),
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      t(
                          context,
                          'Changed ${user.pwdAt == null ? '--' : DateFormat('yyyy-MM-dd').format(user.pwdAt!)}',
                          '修改于 ${user.pwdAt == null ? '--' : DateFormat('yyyy-MM-dd').format(user.pwdAt!)}',
                          zhHk:
                              '更改於 ${user.pwdAt == null ? '--' : DateFormat('yyyy-MM-dd').format(user.pwdAt!)}'),
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
                child: Text(t(context, 'Coming Soon', '即将上线', zhHk: '即將推出')),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: null,
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(t(context, 'Change Password', '修改密码', zhHk: '更改密碼'),
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
          Text(t(context, 'Security', '安全', zhHk: '保安'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t(context, 'Two-factor authentication (TOTP)', '两步验证（TOTP）',
                        zhHk: '雙重驗證（TOTP）'),
                        style: const TextStyle(fontSize: 13)),
                    Text(
                      t(context,
                          'Require a one-time code in addition to your password.',
                          '登录与敏感操作需输入一次性验证码。',
                          zhHk: '登入與敏感操作需輸入一次性驗證碼。'),
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
          Text(t(context, 'Connected accounts', '第三方账号', zhHk: '已連結帳戶'),
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
                    '本服务器未配置第三方登录。',
                    zhHk: '此伺服器未設定任何 OAuth 供應商。'),
                style: TextStyle(
                    fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
              ),
            )
          else
            for (var i = 0; i < identities.length; i++) ...[
              if (i > 0) const Divider(height: 18),
              _identityRow(theme, identities[i]),
            ],
          if (identities != null && identities.any((e) => !e.linked)) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                MBadge(
                  color: MColors.warning,
                  small: true,
                  child: Text(t(context, '🔵 Limited', '🔵 受限', zhHk: '🔵 受限')),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    t(context,
                        'Linking a provider needs a browser callback the app cannot receive yet — please link it on the web client.',
                        '绑定第三方账号的授权回调暂无法返回 App，请在网页端完成绑定。',
                        zhHk: '連結第三方帳戶的授權回調暫無法返回 App，請在網頁端完成連結。'),
                    style: TextStyle(
                        fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
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
                    : t(context, 'Not linked', '未绑定', zhHk: '未連結'),
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
            child: Text(t(context, 'Disconnect', '解绑', zhHk: '中斷連結'),
                style: const TextStyle(fontSize: 13)),
          )
        else
          // 🔵 Disabled on mobile: no deep-link callback channel (see note
          // at the bottom of this card).
          OutlinedButton(
            onPressed: null,
            child: Text(t(context, 'Connect', '绑定', zhHk: '連結'),
                style: const TextStyle(fontSize: 13)),
          ),
      ],
    );
  }

  // 5. teams

  /// Team avatar: image when the team has one (web TeamAvatar parity),
  /// otherwise the colored initial circle. Same URL resolution as TeamPage.
  Widget _teamAvatar(Team team) {
    final path = team.image;
    if (path.isEmpty) {
      return TeamAvatar(name: team.name, colorHex: team.color);
    }
    String? url;
    if (path.startsWith('http')) {
      url = path;
    } else {
      final base = ref.read(serverConfigProvider);
      if (base.isNotEmpty) {
        url = path.startsWith('/') ? '$base$path' : '$base/$path';
      }
    }
    if (url == null) {
      return TeamAvatar(name: team.name, colorHex: team.color);
    }
    return ClipOval(
      child: Image.network(
        url,
        width: 36,
        height: 36,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) =>
            TeamAvatar(name: team.name, colorHex: team.color),
      ),
    );
  }

  Widget _teamsCard(ThemeData theme) {
    final teams = ref.watch(sessionProvider).teams;
    return MCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t(context, 'Teams', '团队', zhHk: '團隊'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (teams.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(t(context, 'No teams yet.', '暂无团队。',
                  zhHk: '尚未加入任何團隊。'),
                  style: TextStyle(
                      fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
            )
          else
            for (var i = 0; i < teams.length; i++) ...[
              if (i > 0) const Divider(height: 18),
              Row(
                children: [
                  _teamAvatar(teams[i]),
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
                              '创建于 ${DateFormat('yyyy-MM-dd').format(teams[i].createdAt)}',
                              zhHk:
                                  '建立於 ${DateFormat('yyyy-MM-dd').format(teams[i].createdAt)}'),
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
                    child: Text(t(context, 'Leave', '退出', zhHk: '離開'),
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
              Text(t(context, 'Sessions', '会话', zhHk: '工作階段'),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton(
                style:
                    TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                onPressed: _revokeAll,
                child: Text(t(context, 'Revoke all', '全部吊销', zhHk: '全部註銷'),
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
    // Web parity (session.tsx:75): "Chrome 126" style version suffix.
    final version = _uaVersion(s.userAgent, browser);
    final title = version == null ? '$browser ($os)' : '$browser $version ($os)';
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
                    child: Text(title,
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
                      child: Text(t(context, 'Current', '当前', zhHk: '目前')),
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

  /// Extracts the browser version from a raw user-agent, matching the
  /// browser name chosen by [uaSummary] (null when it cannot be parsed).
  String? _uaVersion(String ua, String browser) {
    final token = switch (browser) {
      'Edge' => 'Edg',
      'Opera' => 'OPR',
      'Chrome' => 'Chrome',
      'Chromium' => 'Chromium',
      'Firefox' => 'Firefox',
      'Safari' => 'Version',
      'Mosona App' => 'MosonaManagerApp',
      _ => null,
    };
    if (token == null) return null;
    return RegExp('$token/([0-9][0-9.]*)').firstMatch(ua)?.group(1);
  }
}

/// Web parity (enable.tsx:84-105 DownloadsTOTP): popular authenticator apps
/// with per-platform store links (Google Play / App Store).
const _authenticatorApps = <(String, String, String)>[
  (
    'Google Authenticator',
    'https://play.google.com/store/apps/details?id=com.google.android.apps.authenticator2',
    'https://apps.apple.com/us/app/google-authenticator/id388497605',
  ),
  (
    'Authy',
    'https://play.google.com/store/apps/details?id=com.authy.authy',
    'https://apps.apple.com/us/app/twilio-authy/id494168017',
  ),
];

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
              '1. 用验证器 App 扫描二维码，或手动输入密钥。',
              zhHk: '1. 使用驗證器應用程式掃描二維碼，或手動輸入密鑰。'),
          style: TextStyle(
              fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        // Web parity (enable.tsx:84-105 DownloadsTOTP): store links for
        // authenticator apps, picking the store matching the platform.
        Wrap(
          spacing: 4,
          runSpacing: 0,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(t(context, 'Get an app:', '获取验证器 App：',
                    zhHk: '取得驗證器應用程式：'),
                style: TextStyle(
                    fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
            for (final (name, play, ios) in _authenticatorApps)
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  textStyle: const TextStyle(fontSize: 12),
                ),
                onPressed: () => launchExternal(
                    Theme.of(context).platform == TargetPlatform.iOS
                        ? ios
                        : play,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(name),
                    const SizedBox(width: 2),
                    const Icon(Icons.open_in_new, size: 12, color: MColors.link),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
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
                  toastSuccess(context, t(context, 'Copied', '已复制', zhHk: '已複製'));
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          t(context,
              '2. Enter the 6-digit code from your authenticator app to confirm.',
              '2. 输入验证器 App 中的 6 位验证码以确认。',
              zhHk: '2. 輸入驗證器應用程式中的 6 位驗證碼以確認。'),
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
            labelText: t(context, '6-digit code', '6 位验证码', zhHk: '6 位驗證碼'),
            isDense: true,
            border: const OutlineInputBorder(),
            counterText: '',
          ),
        ),
        const SizedBox(height: 14),
        LoadingButton(
          label: t(context, 'Confirm', '确认', zhHk: '確認'),
          loading: _loading,
          onPressed: _valid ? _confirm : null,
        ),
      ],
    );
  }
}

class _CodeInputSheet extends ConsumerStatefulWidget {
  const _CodeInputSheet({required this.label, this.resendMode});

  final String label;

  /// Email-code mode: when set, a "resend code" entry with a 60s cooldown is
  /// shown below the input — web parity (components/2fa.tsx:96-110). Null for
  /// TOTP mode, where resending makes no sense.
  final String? resendMode;

  @override
  ConsumerState<_CodeInputSheet> createState() => _CodeInputSheetState();
}

class _CodeInputSheetState extends ConsumerState<_CodeInputSheet> {
  final _code = TextEditingController();
  bool _sending = false;
  int _cooldown = 0;
  Timer? _timer;

  bool get _valid => _code.text.trim().isNotEmpty;

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  // Web parity (components/2fa.tsx:53-73): a successful resend starts a 60s
  // cooldown; failures surface the backend error.
  Future<void> _resend() async {
    if (_sending || _cooldown > 0) return;
    setState(() => _sending = true);
    try {
      await ref.read(apiProvider).twoFaSendCode(widget.resendMode!);
      if (!mounted) return;
      toastSuccess(context,
          t(context, 'Verification code sent', '验证码已发送', zhHk: '驗證碼已傳送'));
      _startCooldown();
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = 60);
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
        if (widget.resendMode != null) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              style: TextButton.styleFrom(textStyle: const TextStyle(fontSize: 12)),
              onPressed: (_sending || _cooldown > 0) ? null : _resend,
              child: _sending
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_cooldown > 0
                      ? t(context, 'Resend (${_cooldown}s)', '重新发送 (${_cooldown}s)',
                          zhHk: '重新傳送 (${_cooldown}s)')
                      : t(context, 'Resend code', '重新发送验证码',
                          zhHk: '重新傳送驗證碼')),
            ),
          ),
        ],
        const SizedBox(height: 14),
        LoadingButton(
          label: t(context, 'Confirm', '确认', zhHk: '確認'),
          onPressed:
              _valid ? () => Navigator.of(context).pop(_code.text.trim()) : null,
        ),
      ],
    );
  }
}
