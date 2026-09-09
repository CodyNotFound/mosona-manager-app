import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_services.dart';
import '../../core/models/models.dart';
import '../../core/theme/mcolors.dart';
import '../../core/widgets/widgets.dart';

/// /admin/users — user management with filters, CRUD and pagination.
class AdminUsersPage extends ConsumerStatefulWidget {
  const AdminUsersPage({super.key});

  @override
  ConsumerState<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends ConsumerState<AdminUsersPage> {
  /// Per-page options mirror the web BottomPagination select.
  static const _perPageOptions = [20, 50, 100, 500, 1000];

  final _searchController = TextEditingController();
  Timer? _debounce;

  List<User> _users = [];
  int _total = 0;
  int _page = 1;
  int _perPage = 20;
  String _verify = 'all'; // all | true | false
  bool _loading = true;

  ApiServices get _api => ref.read(apiProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final pageData = await _api.adminUsersList(
        page: _page,
        size: _perPage,
        search: _searchController.text.trim(),
        verify: _verify,
      );
      if (!mounted) return;
      setState(() {
        _users = pageData.users;
        _total = pageData.total;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showApiError(context, e);
    }
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _page = 1;
      _load();
    });
  }

  int get _totalPages => _total <= 0 ? 1 : (_total / _perPage).ceil();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t(context, 'Users', '用户管理'))),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 128,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(_verify),
                      initialValue: _verify,
                      isDense: true,
                      decoration: InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                      ),
                      items: [
                        DropdownMenuItem(
                            value: 'all',
                            child: Text(t(context, 'All', '全部'),
                                style: const TextStyle(fontSize: 13))),
                        DropdownMenuItem(
                            value: 'true',
                            child: Text(t(context, 'Verified', '已验证'),
                                style: const TextStyle(fontSize: 13))),
                        DropdownMenuItem(
                            value: 'false',
                            child: Text(t(context, 'Unverified', '未验证'),
                                style: const TextStyle(fontSize: 13))),
                      ],
                      onChanged: (v) {
                        setState(() => _verify = v ?? 'all');
                        _page = 1;
                        _load();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: t(context, 'Search email / name', '搜索邮箱 / 名称'),
                        prefixIcon: const Icon(Icons.search, size: 20),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: t(context, 'Add User', '添加用户'),
                    onPressed: _openAdd,
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: _loading && _users.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        children: const [
                          Skeleton(height: 84, radius: 12),
                          SizedBox(height: 10),
                          Skeleton(height: 84, radius: 12),
                          SizedBox(height: 10),
                          Skeleton(height: 84, radius: 12),
                        ],
                      )
                    : _users.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(
                                height: MediaQuery.of(context).size.height * 0.5,
                                child: EmptyState(
                                    text: t(context, 'No users found', '没有找到用户'),
                                    icon: Icons.person_off_outlined),
                              ),
                            ],
                          )
                        : ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                            itemCount: _users.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, i) => FadeSlideIn(
                              delay: math.min(i, 8) * 60,
                              child: _userCard(context, _users[i]),
                            ),
                          ),
              ),
            ),
            Padding(
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
                    t(context,
                        'Page $_page / $_totalPages',
                        '第 $_page / $_totalPages 页'),
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
                  // Per-page selector (web BottomPagination).
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
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------- user card

  Widget _userCard(BuildContext context, User u) {
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
                child: Text('#${u.id}'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  u.username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: monoStyle(context),
                ),
              ),
              _verifiedBadge(context, u.verified == true),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                icon: const Icon(Icons.more_vert, size: 20),
                onSelected: (v) {
                  if (v == 'edit') _openEdit(u);
                  if (v == 'delete') _delete(u);
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
          const SizedBox(height: 4),
          Text(u.email,
              style: TextStyle(
                  fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          Text(
            '${t(context, 'Created', '创建于')} ${df.format(u.createdAt)}'
            '  ·  ${t(context, 'Last login', '最近登录')} '
            '${u.loginAt == null ? '--' : df.format(u.loginAt!)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _verifiedBadge(BuildContext context, bool verified) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: verified ? MColors.online : MColors.warning),
        ),
        child: Text(
          verified
              ? t(context, 'verified', '已验证')
              : t(context, 'unverified', '未验证'),
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: verified ? MColors.online : MColors.warning),
        ),
      );

  // ------------------------------------------------------------ add / edit

  void _openAdd() {
    showMSheet(
      context: context,
      title: t(context, 'Add User', '添加用户'),
      child: _UserFormSheet(onSaved: _onSaved),
    );
  }

  void _openEdit(User u) {
    showMSheet(
      context: context,
      title: t(context, 'Edit User', '编辑用户'),
      child: _UserFormSheet(existing: u, onSaved: _onSaved),
    );
  }

  void _onSaved() {
    toastSuccess(context);
    _load();
  }

  // ---------------------------------------------------------------- delete

  Future<void> _delete(User u) async {
    final password = await showDialog<String>(
      context: context,
      builder: (_) => ConfirmNameDialog(
        title: t(context, 'Delete User', '删除用户'),
        message: t(context,
            'Type "${u.username}" to confirm. Also enter your (admin) current password.',
            '输入 "${u.username}" 以确认删除，并输入管理员当前密码。'),
        name: u.username,
        confirmLabel: t(context, 'Delete', '删除'),
        extraLabel: t(context, 'Your password', '管理员密码'),
      ),
    );
    if (password == null || password.isEmpty || !mounted) return;
    try {
      final e = await _api.adminUserDelete(
        u.id,
        confirm: u.username,
        currentPassword: password,
      );
      if (!mounted) return;
      if (e.isOk) {
        toastSuccess(context);
        _load();
        return;
      }
      final data = e.data;
      final teams =
          data is Map<String, dynamic> ? data['teams'] : null;
      if (teams is List && teams.isNotEmpty) {
        final names = [
          for (final t0 in teams)
            t0 is Map<String, dynamic> ? (t0['name'] ?? '').toString() : '$t0'
        ].where((s) => s.isNotEmpty).join(', ');
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(t(context, 'User owns teams', '该用户拥有团队')),
            content: Text(
              t(context,
                  'This user owns the following teams: $names. Handle them before deleting.',
                  '该用户拥有以下团队：$names。删除前请先处理。'),
              style: const TextStyle(fontSize: 13),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(t(context, 'OK', '好的')),
              ),
            ],
          ),
        );
        if (!mounted) return;
        toastWarn(context, t(context, 'Deletion blocked', '删除被阻止'));
      } else {
        showApiError(context, ApiException(e.code, e.msg, data: e.data));
      }
    } catch (err) {
      if (!mounted) return;
      showApiError(context, err);
    }
  }
}

// ------------------------------------------------------------------- sheet

class _UserFormSheet extends ConsumerStatefulWidget {
  const _UserFormSheet({this.existing, required this.onSaved});

  final User? existing;
  final VoidCallback onSaved;

  @override
  ConsumerState<_UserFormSheet> createState() => _UserFormSheetState();
}

class _UserFormSheetState extends ConsumerState<_UserFormSheet> {
  late final User? _existing = widget.existing;
  late final TextEditingController _username =
      TextEditingController(text: _existing?.username ?? '');
  late final TextEditingController _email =
      TextEditingController(text: _existing?.email ?? '');
  late final TextEditingController _password =
      TextEditingController(text: _existing == null ? randomPassword(10) : '');
  late final TextEditingController _currentPassword = TextEditingController();
  late bool _verified = _existing?.verified ?? true;
  late bool _admin = _existing?.isAdmin ?? false;
  bool _saving = false;

  ApiServices get _api => ref.read(apiProvider);

  /// Web parity (admin/page/users/edit.tsx:150-162): the admin's current
  /// password is required when changing the password OR the admin flag.
  bool get _needsCurrentPassword =>
      _password.text.isNotEmpty || _admin != (_existing?.isAdmin ?? false);

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    _currentPassword.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _username.text.trim();
    final email = _email.text.trim();
    if (username.isEmpty || email.isEmpty) {
      toastWarn(context, t(context, 'Username and email are required', '用户名和邮箱必填'));
      return;
    }
    if (_existing == null && _password.text.isEmpty) {
      toastWarn(context, t(context, 'Password is required', '密码必填'));
      return;
    }
    if (_existing != null &&
        _needsCurrentPassword &&
        _currentPassword.text.isEmpty) {
      toastWarn(
        context,
        t(context,
            'Your (admin) password is required to change the password or admin flag.',
            '修改密码或管理员标志时需要输入管理员当前密码。'),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      if (_existing == null) {
        await _api.adminUserAdd(
          username: username,
          email: email,
          password: _password.text,
          verified: _verified,
          admin: _admin,
        );
      } else {
        await _api.adminUserUpdate(
          id: _existing.id,
          username: username,
          email: email,
          password: _password.text,
          verified: _verified,
          admin: _admin,
          currentPassword: _currentPassword.text,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onSaved();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      if (e.code == 'exists') {
        toastWarn(context,
            t(context, 'User already exists: ', '用户已存在：') + e.msg);
      } else {
        showApiError(context, e);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _username,
          decoration: InputDecoration(
            labelText: t(context, 'Username *', '用户名 *'),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: t(context, 'Email *', '邮箱 *'),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          decoration: InputDecoration(
            labelText: _existing == null
                ? t(context, 'Password *', '密码 *')
                : t(context, 'New password', '新密码'),
            helperText: _existing == null
                ? null
                : t(context, 'Leave empty to keep current password', '留空则不修改密码'),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            suffixIcon: IconButton(
              tooltip: t(context, 'Random password', '随机密码'),
              onPressed: () =>
                  setState(() => _password.text = randomPassword(10)),
              icon: const Icon(Icons.casino_outlined, size: 20),
            ),
          ),
        ),
        if (_existing != null) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _currentPassword,
            obscureText: true,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: t(context, 'Current password', '当前密码'),
              helperText: _needsCurrentPassword
                  ? t(context, 'Required', '必填')
                  : t(context, 'Required only to change password',
                      '仅修改密码时需要填写'),
              isDense: true,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
        const SizedBox(height: 12),
        DropdownButtonFormField<bool>(
          initialValue: _verified,
          isDense: true,
          decoration: InputDecoration(
            labelText: t(context, 'Verified', '已验证'),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          items: [
            DropdownMenuItem(
                value: true, child: Text(t(context, 'Yes', '是'))),
            DropdownMenuItem(
                value: false, child: Text(t(context, 'No', '否'))),
          ],
          onChanged: (v) => setState(() => _verified = v ?? false),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<bool>(
          initialValue: _admin,
          isDense: true,
          decoration: InputDecoration(
            labelText: t(context, 'Administrator', '管理员'),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          items: [
            DropdownMenuItem(
                value: true, child: Text(t(context, 'Yes', '是'))),
            DropdownMenuItem(
                value: false, child: Text(t(context, 'No', '否'))),
          ],
          onChanged: (v) => setState(() => _admin = v ?? false),
        ),
        const SizedBox(height: 16),
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
