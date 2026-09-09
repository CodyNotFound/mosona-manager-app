import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_services.dart';
import '../../core/models/models.dart';
import '../../core/state/controllers.dart';
import '../../core/state/session.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/widgets.dart';
import 'avatar.dart';

class TeamPage extends ConsumerStatefulWidget {
  const TeamPage({super.key});

  @override
  ConsumerState<TeamPage> createState() => _TeamPageState();
}

class _TeamPageState extends ConsumerState<TeamPage> {
  bool _loading = true;
  String? _error;
  Team? _team;
  List<TeamMember> _members = [];

  final _name = TextEditingController();
  final _desc = TextEditingController();
  String _color = kDefaultTeamColor;
  Uint8List? _avatarBytes;

  bool _saving = false;

  ApiServices get _api => ref.read(apiProvider);

  User? get _me => ref.read(sessionProvider).user;

  bool get _isOwner =>
      _team != null && _me != null && _me!.id == _team!.ownerId;

  int get _myRole {
    final uid = _me?.id;
    for (final m in _members) {
      if (m.user.id == uid) return m.role;
    }
    return 2;
  }

  bool get _canEdit => _isOwner || _myRole == 0;

  String? get _teamImageUrl {
    final path = _team?.image ?? '';
    if (path.isEmpty) return null;
    if (path.startsWith('http')) return path;
    final base = ref.read(serverConfigProvider);
    if (base.isEmpty) return null;
    return path.startsWith('/') ? '$base$path' : '$base/$path';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final info = await _api.teamInfo();
      if (!mounted) return;
      setState(() {
        _team = info.team;
        _members = info.members;
        _name.text = info.team.name;
        _desc.text = info.team.description;
        if (info.team.color.isNotEmpty) _color = info.team.color;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // ------------------------------------------------------------- find user

  Future<void> _findUser() async {
    final ctrl = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t(context, 'Find user', '查找用户')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: t(context, 'Email', '邮箱'),
            isDense: true,
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: Text(t(context, 'Cancel', '取消'))),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: Text(t(context, 'Search', '搜索')),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (email == null || email.isEmpty || !mounted) return;
    try {
      final user = await _api.findUser(email);
      if (!mounted) return;
      if (user == null) {
        toastWarn(context, t(context, 'User not found', '未找到该用户'));
        return;
      }
      if (_members.any((m) => m.user.id == user.id)) {
        toastWarn(context, t(context, 'Already a member', '已是团队成员'));
        return;
      }
      setState(() => _members = [..._members, TeamMember(user: user, role: 1)]);
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  // ---------------------------------------------------------------- export

  Future<void> _exportTeam() async {
    final creds = await showCredsDialog(
      context,
      title: t(context, 'Export team', '导出团队'),
      needPassword: true,
      message: t(
        context,
        'Set a password (min 8 chars) to encrypt the export file, then enter your TOTP code.',
        '设置导出文件加密密码（至少 8 位），并输入 TOTP 验证码。',
      ),
    );
    if (creds == null || !mounted) return;
    var skip = false;
    while (true) {
      final Envelope res;
      try {
        res = await _api.exportTeam(
          totpCode: creds.$2,
          exportPassword: creds.$1,
          skipUnreadableServers: skip,
        );
      } catch (e) {
        if (mounted) showApiError(context, e);
        return;
      }
      if (res.isOk) {
        final skippedServers = res.extras['skipped_servers'] as List?;
        final skippedKeys = res.extras['skipped_keys'] as List?;
        final nSrv = skippedServers?.length ?? 0;
        final nKey = skippedKeys?.length ?? 0;
        if ((nSrv > 0 || nKey > 0) && mounted) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(t(context, 'Skipped credentials', '已跳过的凭证')),
              content: Text(
                t(
                  context,
                  'Skipped $nSrv servers and $nKey keys with unreadable credentials.',
                  '已跳过 $nSrv 台服务器和 $nKey 个密钥（凭证不可读）。',
                ),
                style: const TextStyle(fontSize: 13),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(t(context, 'OK', '好的')),
                ),
              ],
            ),
          );
        }
        final teamName = _team?.name ?? 'team';
        final fileName =
            '$teamName-export-${DateFormat('yyyy-MM-dd').format(DateTime.now())}.json';
        try {
          await SharePlus.instance
              .share(ShareParams(text: jsonEncode(res.data), subject: fileName));
        } catch (_) {}
        if (mounted) toastSuccess(context);
        return;
      }
      if (res.code == 'unreadable_server_credential' ||
          res.code == 'unreadable_key_credential') {
        if (skip || !mounted) {
          if (mounted) {
            showApiError(
                context, ApiException(res.code, res.msg, data: res.data));
          }
          return;
        }
        final m = res.data is Map<String, dynamic>
            ? res.data as Map<String, dynamic>
            : null;
        final what =
            m == null ? '' : ' ${m['server_name'] ?? m['key_name'] ?? ''}'.trimRight();
        final ok = await confirmDialog(
          context,
          title: t(context, 'Skip unreadable credentials?', '跳过无法读取的凭证？'),
          message: '${res.msg}${what.isEmpty ? '' : '\n$what'}',
          okLabel: t(context, 'Skip & continue', '跳过并继续'),
        );
        if (!ok || !mounted) return;
        skip = true;
        continue;
      }
      if (!mounted) return;
      showApiError(context, ApiException(res.code, res.msg, data: res.data));
      return;
    }
  }

  // ---------------------------------------------------------------- import

  Future<void> _importTeam() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (!mounted) return;
    if (files.isEmpty) return;
    final Uint8List bytes;
    try {
      bytes = await files.first.readAsBytes();
    } catch (_) {
      if (mounted) toastWarn(context, t(context, 'Could not read the file', '无法读取文件'));
      return;
    }
    if (!mounted) return;
    dynamic parsed;
    try {
      parsed = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      toastWarn(context, t(context, 'Invalid JSON file', 'JSON 文件无效'));
      return;
    }

    Map<String, dynamic>? encrypted;
    dynamic data;
    String? password;
    (String, String)? creds;
    if (parsed is Map<String, dynamic> &&
        parsed['encrypted'] is Map<String, dynamic>) {
      encrypted = parsed['encrypted'] as Map<String, dynamic>;
      creds = await showCredsDialog(
        context,
        title: t(context, 'Import team', '导入团队'),
        needPassword: true,
        message: t(
          context,
          'This export is encrypted. Enter the export password and your TOTP code.',
          '该导出文件已加密，请输入导出密码与 TOTP 验证码。',
        ),
      );
    } else {
      data = parsed;
      creds = await showCredsDialog(
        context,
        title: t(context, 'Import team', '导入团队'),
        needPassword: false,
        message: t(context, 'Enter your TOTP code to import.', '输入 TOTP 验证码以导入。'),
      );
    }
    if (creds == null || !mounted) return;
    password = creds.$1.isEmpty ? null : creds.$1;
    final totp = creds.$2;

    var trust = false;
    while (true) {
      final Envelope res;
      try {
        res = await _api.importTeam(
          totpCode: totp,
          exportPassword: password,
          encrypted: encrypted,
          data: data,
          trustLegacySshHostKeys: trust,
        );
      } catch (e) {
        if (mounted) showApiError(context, e);
        return;
      }
      if (res.isOk) {
        if (!mounted) return;
        toastSuccess(context, t(context, 'Team imported', '导入成功'));
        await ref.read(sessionProvider.notifier).refresh();
        ref.read(teamDataProvider.notifier).refresh();
        return;
      }
      if (res.code == 'legacy_ssh_host_key_confirmation_required') {
        final m = res.data is Map<String, dynamic>
            ? res.data as Map<String, dynamic>
            : <String, dynamic>{};
        final servers =
            (m['servers'] as List? ?? []).map((e) => e.toString()).join(', ');
        if (!mounted) return;
        final ok = await confirmDialog(
          context,
          title: t(context, 'Trust legacy SSH host keys?', '信任旧版 SSH 主机密钥？'),
          message: servers.isEmpty
              ? res.msg
              : '${res.msg}\n${m['count'] ?? ''}: $servers',
          okLabel: t(context, 'Trust & continue', '信任并继续'),
          danger: true,
        );
        if (!ok || !mounted) return;
        trust = true;
        continue;
      }
      if (res.code == 'agent_uid_conflict' && mounted) {
        final m = res.data is Map<String, dynamic>
            ? res.data as Map<String, dynamic>
            : <String, dynamic>{};
        toastError(context, m.isEmpty ? res.msg : '${res.msg}\n$m');
        return;
      }
      if (!mounted) return;
      showApiError(context, ApiException(res.code, res.msg, data: res.data));
      return;
    }
  }

  // ----------------------------------------------------------------- leave

  Future<void> _leaveTeam() async {
    final team = _team;
    if (team == null) return;
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
      await ref.read(sessionProvider.notifier).refresh();
      if (mounted) context.go('/create-team');
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  // ------------------------------------------------------------------ save

  Future<void> _save() async {
    final team = _team;
    if (team == null || _saving) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      toastWarn(context, t(context, 'Team name is required', '请输入团队名称'));
      return;
    }
    setState(() => _saving = true);
    final members = [
      for (final m in _members)
        (id: m.user.id, role: m.user.id == _me?.id ? 0 : m.role),
    ];
    try {
      await _api.editTeam(
        id: team.id,
        name: name,
        description: _desc.text.trim(),
        avatarColor: _color,
        members: members,
        avatarImage: _avatarBytes,
      );
      if (!mounted) return;
      toastSuccess(context);
      await ref.read(sessionProvider.notifier).refresh();
      if (mounted) _load();
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ----------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t(context, 'Team', '团队'))),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? ListView(
                  padding: const EdgeInsets.all(16),
                  children: const [
                    Skeleton(height: 180, radius: 12),
                    SizedBox(height: 16),
                    Skeleton(height: 120, radius: 12),
                    SizedBox(height: 16),
                    Skeleton(height: 160, radius: 12),
                  ],
                )
              : _error != null
                  ? ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        EmptyState(
                          text: t(context, 'Failed to load team', '团队加载失败'),
                          icon: Icons.group_off_outlined,
                        ),
                        Center(
                          child: TextButton(
                            onPressed: _load,
                            child: Text(t(context, 'Retry', '重试')),
                          ),
                        ),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      children: [
                        PageHeader(
                          title: t(context, 'Team', '团队'),
                          description: _canEdit
                              ? t(context, 'Manage your team profile and members',
                                  '管理团队资料与成员')
                              : t(context, 'You have read-only access', '你只有只读权限'),
                        ),
                        FadeSlideIn(
                          child: MCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AvatarEditor(
                                  initialColor: _color,
                                  initialImageUrl: _teamImageUrl,
                                  onChanged: (hex, bytes) {
                                    _color = hex;
                                    _avatarBytes = bytes;
                                  },
                                ),
                                const SizedBox(height: 16),
                                TextField(
                                  controller: _name,
                                  enabled: _canEdit,
                                  decoration: InputDecoration(
                                    labelText: t(context, 'Name', '名称'),
                                    isDense: true,
                                    border: const OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _desc,
                                  enabled: _canEdit,
                                  maxLines: 2,
                                  decoration: InputDecoration(
                                    labelText: t(context, 'Description', '描述'),
                                    isDense: true,
                                    border: const OutlineInputBorder(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        FadeSlideIn(
                          delay: 60,
                          child: MCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(t(context, 'Members', '成员'),
                                        style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600)),
                                    const Spacer(),
                                    if (_canEdit)
                                      OutlinedButton.icon(
                                        onPressed: _findUser,
                                        icon:
                                            const Icon(Icons.person_add_alt_1, size: 18),
                                        label: Text(t(context, 'Find user', '查找用户'),
                                            style: const TextStyle(fontSize: 13)),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                for (var i = 0; i < _members.length; i++) ...[
                                  if (i > 0) const Divider(height: 20),
                                  _memberTile(_members[i], theme),
                                ],
                              ],
                            ),
                          ),
                        ),
                        if (_isOwner) ...[
                          const SizedBox(height: 16),
                          FadeSlideIn(delay: 120, child: _importExportCard(theme)),
                        ],
                        const SizedBox(height: 24),
                        FadeSlideIn(
                          delay: 180,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_canEdit)
                                LoadingButton(
                                  label: t(context, 'Save', '保存'),
                                  onPressed: _save,
                                  loading: _saving,
                                ),
                              if (_canEdit) const SizedBox(height: 10),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: theme.colorScheme.error,
                                  side: BorderSide(color: theme.colorScheme.error),
                                ),
                                onPressed: _leaveTeam,
                                icon: const Icon(Icons.logout, size: 18),
                                label: Text(t(context, 'Leave Team', '退出团队')),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
        ),
      ),
    );
  }

  Widget _memberTile(TeamMember m, ThemeData theme) {
    final isOwnerRow = m.user.id == _team?.ownerId;
    final isSelf = m.user.id == _me?.id;
    final roleLocked = !_canEdit || isOwnerRow || isSelf;
    return Row(
      children: [
        Gravatar(email: m.user.email, size: 36),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      m.user.username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ),
                  if (isOwnerRow) ...[
                    const SizedBox(width: 6),
                    MBadge(
                      color: theme.colorScheme.primary,
                      small: true,
                      child: Text(t(context, 'Owner', '所有者')),
                    ),
                  ],
                ],
              ),
              Text(
                m.user.email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        DropdownButton<int>(
          value: m.role.clamp(0, 2),
          isDense: true,
          underline: const SizedBox.shrink(),
          items: [
            for (var r = 0; r <= 2; r++)
              DropdownMenuItem<int>(
                value: r,
                child: Text(roleLabel(r), style: const TextStyle(fontSize: 12)),
              ),
          ],
          onChanged: roleLocked
              ? null
              : (r) {
                  if (r == null) return;
                  final idx = _members.indexOf(m);
                  if (idx < 0) return;
                  setState(() {
                    _members[idx] = TeamMember(user: m.user, role: r);
                  });
                },
        ),
        if (_canEdit && !isOwnerRow && !isSelf)
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.delete_outline,
                size: 20, color: theme.colorScheme.error),
            onPressed: () => setState(
                () => _members.removeWhere((x) => x.user.id == m.user.id)),
          ),
      ],
    );
  }

  Widget _importExportCard(ThemeData theme) {
    return MCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.ios_share,
                  size: 18, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(t(context, 'Import / Export', '导入 / 导出'),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            t(
              context,
              'Export all servers and keys encrypted with a password, or restore from an export file.',
              '使用密码加密导出全部服务器与密钥，或从导出文件恢复。',
            ),
            style: TextStyle(
                fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _exportTeam,
                  child: Text(t(context, 'Export', '导出')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: _importTeam,
                  child: Text(t(context, 'Import', '导入')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Password + TOTP prompt shared by the import/export flows.
Future<(String, String)?> showCredsDialog(
  BuildContext context, {
  required String title,
  required bool needPassword,
  String? message,
}) {
  return showDialog<(String, String)>(
    context: context,
    builder: (_) => _CredsDialog(
      title: title,
      needPassword: needPassword,
      message: message,
    ),
  );
}

class _CredsDialog extends StatefulWidget {
  const _CredsDialog({
    required this.title,
    required this.needPassword,
    this.message,
  });

  final String title;
  final bool needPassword;
  final String? message;

  @override
  State<_CredsDialog> createState() => _CredsDialogState();
}

class _CredsDialogState extends State<_CredsDialog> {
  final _pwd = TextEditingController();
  final _totp = TextEditingController();

  bool get _totpValid => RegExp(r'^\d{6}$').hasMatch(_totp.text.trim());
  bool get _pwdValid => !widget.needPassword || _pwd.text.length >= 8;

  @override
  void dispose() {
    _pwd.dispose();
    _totp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.message != null)
            Text(widget.message!, style: const TextStyle(fontSize: 13)),
          if (widget.message != null) const SizedBox(height: 12),
          if (widget.needPassword) ...[
            TextField(
              controller: _pwd,
              obscureText: true,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: t(context, 'Export password (min 8)', '导出密码（至少 8 位）'),
                isDense: true,
                border: const OutlineInputBorder(),
                errorText: _pwd.text.isEmpty || _pwdValid
                    ? null
                    : t(context, 'Too short', '太短'),
              ),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _totp,
            keyboardType: TextInputType.number,
            maxLength: 6,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: t(context, 'TOTP code', 'TOTP 验证码'),
              isDense: true,
              border: const OutlineInputBorder(),
              counterText: '',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(t(context, 'Cancel', '取消')),
        ),
        FilledButton(
          onPressed: (_pwdValid && _totpValid)
              ? () => Navigator.of(context).pop((_pwd.text, _totp.text.trim()))
              : null,
          child: Text(t(context, 'Continue', '继续')),
        ),
      ],
    );
  }
}
