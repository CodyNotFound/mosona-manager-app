import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mosona_manager/core/api/api_services.dart';
import 'package:mosona_manager/core/models/models.dart';
import 'package:mosona_manager/core/state/session.dart';
import 'package:mosona_manager/core/theme/mcolors.dart';
import 'package:mosona_manager/core/widgets/widgets.dart';

/// Keychain tab: team SSH keys with add / edit / delete.
class KeychainPage extends ConsumerWidget {
  const KeychainPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teamData = ref.watch(teamDataProvider);
    final keys = teamData.keys;
    final loading = !teamData.loaded;
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(teamDataProvider.notifier).refresh(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              PageHeader(
                title: t(context, 'Keychain', '密钥', zhHk: '密鑰庫'),
                description: t(context, 'SSH private keys shared in this team',
                    '团队共享的 SSH 私钥', zhHk: '團隊共享的 SSH 私鑰'),
                actions: [
                  FilledButton.tonalIcon(
                    onPressed: () => _showAddSheet(context),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(t(context, 'Add', '添加', zhHk: '新增')),
                  ),
                ],
              ),
              if (loading)
                ...List.generate(
                  4,
                  (i) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: MCard(
                      child: Row(
                        children: [
                          const Skeleton(width: 40, height: 40, radius: 10),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Skeleton(width: 150, height: 14),
                                SizedBox(height: 6),
                                Skeleton(width: 100, height: 11),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else if (keys.isEmpty)
                EmptyState(
                  text: t(context, 'No keys yet. Tap "Add" to import one.',
                      '还没有密钥，点击"添加"导入一个。', zhHk: '還沒有密鑰，按「新增」匯入一個。'),
                  icon: Icons.key_outlined,
                )
              else
                ...List.generate(keys.length, (i) {
                  final key = keys[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: FadeSlideIn(
                      delay: i * 60,
                      child: MCard(
                        onLongPress: () => _showKeyMenu(context, ref, key),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: MColors.brand.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(Icons.vpn_key_outlined,
                                  size: 20, color: MColors.link),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    key.name,
                                    style: monoStyle(context, size: 14),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${t(context, 'Added on', '添加于', zhHk: '新增於')} '
                                    '${DateFormat('yyyy-MM-dd').format(key.createdAt.toLocal())}',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: theme.colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: t(context, 'Edit', '编辑', zhHk: '編輯'),
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _showEditSheet(context, ref, key),
                              icon: const Icon(Icons.edit_outlined, size: 18),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }

  void _showKeyMenu(BuildContext context, WidgetRef ref, SshKey key) {
    showMSheet(
      context: context,
      title: key.name,
      child: Builder(
        builder: (sheetContext) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(t(context, 'Edit', '编辑', zhHk: '編輯')),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _showEditSheet(context, ref, key);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: MColors.offline),
              title: Text(t(context, 'Delete', '删除', zhHk: '刪除'),
                  style: const TextStyle(color: MColors.offline)),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _confirmDelete(context, ref, key);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, SshKey key) async {
    final ok = await confirmDialog(
      context,
      title: t(context, 'Delete key', '删除密钥', zhHk: '刪除密鑰'),
      message: t(
        context,
        'Delete "${key.name}"? This cannot be undone. If servers are still '
            'using this key, deleting it will fail — remove all dependencies '
            'first.',
        '删除"${key.name}"吗？此操作无法撤销。如果仍有服务器在使用此密钥，删除将失败。'
            '请先移除所有依赖。',
        zhHk: '刪除「${key.name}」嗎？此操作無法復原。如仍有伺服器使用此密鑰，刪除將會失敗。'
            '請先移除所有依賴項目。',
      ),
      okLabel: t(context, 'Delete', '删除', zhHk: '刪除'),
      danger: true,
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(apiProvider).keyDelete(key.id);
      await ref.read(teamDataProvider.notifier).refresh();
      if (context.mounted) toastSuccess(context);
    } catch (e) {
      if (context.mounted) showApiError(context, e);
    }
  }

  Future<void> _showAddSheet(BuildContext context) async {
    await showMSheet(
      context: context,
      title: t(context, 'Add key', '添加密钥', zhHk: '新增密鑰'),
      child: const _KeyFormSheet(),
    );
  }

  Future<void> _showEditSheet(
      BuildContext context, WidgetRef ref, SshKey key) async {
    await showMSheet(
      context: context,
      title: t(context, 'Edit key', '编辑密钥', zhHk: '編輯密鑰'),
      child: _KeyEditSheet(sshKey: key),
    );
  }
}

// ------------------------------------------------------------------ add form

class _KeyFormSheet extends ConsumerStatefulWidget {
  const _KeyFormSheet();

  @override
  ConsumerState<_KeyFormSheet> createState() => _KeyFormSheetState();
}

class _KeyFormSheetState extends ConsumerState<_KeyFormSheet> {
  final _name = TextEditingController();
  final _content = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    _content.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _importFile() async {
    try {
      final file = await FilePicker.pickFile(type: FileType.any);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final text = utf8.decode(bytes, allowMalformed: true);
      if (!mounted) return;
      setState(() {
        _content.text = text;
        final n = file.name;
        _name.text = n.contains('.') ? n.substring(0, n.lastIndexOf('.')) : n;
      });
    } catch (_) {
      if (mounted) {
        toastWarn(context,
            t(context, 'Could not read the file.', '无法读取文件。', zhHk: '無法讀取檔案。'));
      }
    }
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final content = _content.text.trim();
    if (name.isEmpty || content.isEmpty) {
      toastWarn(
          context,
          t(context, 'Name and key content are required.',
              '名称与私钥内容不能为空。', zhHk: '名稱與私鑰內容不能為空。'));
      return;
    }
    setState(() => _loading = true);
    try {
      await ref.read(apiProvider).keyAdd(name, content, _password.text);
      await ref.read(teamDataProvider.notifier).refresh();
      if (!mounted) return;
      Navigator.of(context).pop();
      toastSuccess(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
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
          controller: _name,
          decoration: InputDecoration(
            labelText: t(context, 'Name', '名称', zhHk: '名稱'),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _content,
          minLines: 6,
          maxLines: 12,
          keyboardType: TextInputType.multiline,
          style: monoStyle(context, size: 12)
              .copyWith(fontWeight: FontWeight.w400),
          decoration: InputDecoration(
            labelText: t(context, 'Private key', '私钥', zhHk: '私鑰'),
            alignLabelWithHint: true,
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          decoration: InputDecoration(
            labelText: t(context, 'Password (optional)', '密码（可选）', zhHk: '密碼（可選）'),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _loading ? null : _importFile,
          icon: const Icon(Icons.upload_file, size: 18),
          label: Text(t(context, 'Import file', '导入文件', zhHk: '匯入檔案')),
        ),
        const SizedBox(height: 16),
        LoadingButton(
          label: t(context, 'Save', '保存', zhHk: '儲存'),
          loading: _loading,
          onPressed: _submit,
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------- edit form

class _KeyEditSheet extends ConsumerStatefulWidget {
  const _KeyEditSheet({required this.sshKey});

  final SshKey sshKey;

  @override
  ConsumerState<_KeyEditSheet> createState() => _KeyEditSheetState();
}

class _KeyEditSheetState extends ConsumerState<_KeyEditSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.sshKey.name);
  final _password = TextEditingController();
  bool _loading = false;

  /// "Reset to empty" toggle: submit the `!msn!empty!` sentinel so the backend
  /// clears the key's passphrase (web edit.tsx emptyPassword).
  bool _emptyPassword = false;
  static const _emptySentinel = '!msn!empty!';

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      toastWarn(context, t(context, 'Name is required.', '名称不能为空。', zhHk: '名稱不能為空。'));
      return;
    }
    setState(() => _loading = true);
    try {
      await ref.read(apiProvider).keyEdit(
            widget.sshKey.id,
            name,
            _emptyPassword ? _emptySentinel : _password.text,
          );
      await ref.read(teamDataProvider.notifier).refresh();
      if (!mounted) return;
      Navigator.of(context).pop();
      toastSuccess(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showApiError(context, e);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      title: t(context, 'Delete key', '删除密钥', zhHk: '刪除密鑰'),
      message: t(
        context,
        'Delete "${widget.sshKey.name}"? This cannot be undone. If servers are '
            'still using this key, deleting it will fail — remove all '
            'dependencies first.',
        '删除"${widget.sshKey.name}"吗？此操作无法撤销。如果仍有服务器在使用此密钥，'
            '删除将失败。请先移除所有依赖。',
        zhHk: '刪除「${widget.sshKey.name}」嗎？此操作無法復原。如仍有伺服器使用此密鑰，'
            '刪除將會失敗。請先移除所有依賴項目。',
      ),
      okLabel: t(context, 'Delete', '删除', zhHk: '刪除'),
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _loading = true);
    try {
      await ref.read(apiProvider).keyDelete(widget.sshKey.id);
      await ref.read(teamDataProvider.notifier).refresh();
      if (!mounted) return;
      Navigator.of(context).pop();
      toastSuccess(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _name,
          decoration: InputDecoration(
            labelText: t(context, 'Name', '名称', zhHk: '名稱'),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(t(context, 'Password', '密码', zhHk: '密碼'),
                  style: const TextStyle(fontSize: 12)),
            ),
            // "Reset to empty" toggle (web edit.tsx Badge).
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _emptyPassword = !_emptyPassword),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: _emptyPassword
                      ? theme.colorScheme.primary
                      : Colors.transparent,
                  border: Border.all(
                    color: _emptyPassword
                        ? theme.colorScheme.primary
                        : theme.dividerColor,
                  ),
                ),
                child: Text(
                  t(context, 'Reset to empty', '重置为空', zhHk: '重設為空白'),
                  style: TextStyle(
                    fontSize: 11,
                    color: _emptyPassword
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _password,
          obscureText: true,
          enabled: !_emptyPassword,
          decoration: InputDecoration(
            labelText: t(context, 'Password (optional)', '密码（可选）', zhHk: '密碼（可選）'),
            hintText: t(context,
                'Empty to keep the key\'s current password', '留空则保留密钥当前密码',
                zhHk: '留空則保留密鑰目前密碼'),
            isDense: true,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            // Destructive delete embedded in the edit sheet (web edit.tsx).
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: MColors.offline,
                side: const BorderSide(color: MColors.offline),
              ),
              onPressed: _loading ? null : _delete,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: Text(t(context, 'Delete', '删除', zhHk: '刪除')),
            ),
            const Spacer(),
            LoadingButton(
              label: t(context, 'Save', '保存', zhHk: '儲存'),
              loading: _loading,
              onPressed: _submit,
            ),
          ],
        ),
      ],
    );
  }
}
