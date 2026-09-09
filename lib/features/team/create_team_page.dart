import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_services.dart';
import '../../core/models/models.dart';
import '../../core/state/session.dart';
import '../../core/theme/mcolors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/widgets.dart';
import 'avatar.dart';

class CreateTeamPage extends ConsumerStatefulWidget {
  const CreateTeamPage({super.key});

  @override
  ConsumerState<CreateTeamPage> createState() => _CreateTeamPageState();
}

class _CreateTeamPageState extends ConsumerState<CreateTeamPage> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  String _color = kDefaultTeamColor;
  Uint8List? _avatarBytes;
  List<TeamMember> _members = const [];
  bool _creating = false;

  ApiServices get _api => ref.read(apiProvider);

  @override
  void initState() {
    super.initState();
    final me = ref.read(sessionProvider).user;
    _members = me == null ? [] : [TeamMember(user: me, role: 0)];
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

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

  Future<void> _create() async {
    if (_creating) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      toastWarn(context, t(context, 'Team name is required', '请输入团队名称'));
      return;
    }
    setState(() => _creating = true);
    final members = [
      for (final m in _members) (id: m.user.id, role: m.role),
    ];
    try {
      await _api.createTeam(
        name: name,
        description: _desc.text.trim(),
        avatarColor: _color,
        members: members,
        avatarImage: _avatarBytes,
      );
      if (!mounted) return;
      toastSuccess(context, t(context, 'Team created', '团队已创建'));
      // Backend switches the active team on create; refresh both stores.
      await ref.read(sessionProvider.notifier).refresh();
      ref.read(teamDataProvider.notifier).refresh();
      if (mounted) context.go('/');
    } catch (e) {
      if (mounted) showApiError(context, e);
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t(context, 'Create Team', '创建团队'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            PageHeader(
              title: t(context, 'Create Team', '创建团队'),
              description:
                  t(context, 'Group servers and share them with members', '汇聚服务器并与成员共享'),
            ),
            FadeSlideIn(
              child: MCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, size: 18, color: MColors.warning),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        t(
                          context,
                          'The new team becomes your active team right away. Existing servers stay in their current team.',
                          '新团队将立即成为当前活跃团队，现有服务器仍保留在原团队中。',
                        ),
                        style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant),
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
                    AvatarEditor(
                      initialColor: _color,
                      onChanged: (hex, bytes) {
                        _color = hex;
                        _avatarBytes = bytes;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _name,
                      decoration: InputDecoration(
                        labelText: t(context, 'Name *', '名称 *'),
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _desc,
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
              delay: 120,
              child: MCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(t(context, 'Members', '成员'),
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        OutlinedButton.icon(
                          onPressed: _findUser,
                          icon: const Icon(Icons.person_add_alt_1, size: 18),
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
            const SizedBox(height: 24),
            FadeSlideIn(
              delay: 180,
              child: LoadingButton(
                label: t(context, 'Create Team', '创建团队'),
                onPressed: _create,
                loading: _creating,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _memberTile(TeamMember m, ThemeData theme) {
    final me = ref.read(sessionProvider).user;
    final isSelf = me != null && m.user.id == me.id;
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
                  if (isSelf) ...[
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
          onChanged: isSelf
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
        if (!isSelf)
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.delete_outline,
                size: 20, color: theme.colorScheme.error),
            onPressed: () =>
                setState(() => _members.removeWhere((x) => x.user.id == m.user.id)),
          ),
      ],
    );
  }
}
