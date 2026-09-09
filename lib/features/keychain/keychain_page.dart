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
                title: t(context, 'Keychain', '密钥'),
                description:
                    t(context, 'SSH private keys shared in this team', '团队共享的 SSH 私钥'),
                actions: [
                  FilledButton.tonalIcon(
                    onPressed: () => _showAddSheet(context),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(t(context, 'Add', '添加')),
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
                      '还没有密钥，点击"添加"导入一个。'),
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
                                    '${t(context, 'Added on', '添加于')} '
                                    '${DateFormat('yyyy-MM-dd').format(key.createdAt.toLocal())}',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: theme.colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: t(context, 'Edit', '编辑'),
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
              title: Text(t(context, 'Edit', '编辑')),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _showEditSheet(context, ref, key);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: MColors.offline),
              title: Text(t(context, 'Delete', '删除'),
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
      title: t(context, 'Delete key', '删除密钥'),
      message: t(context, 'Delete "${key.name}"? This cannot be undone.',
          '删除"${key.name}"吗？此操作无法撤销。'),
      okLabel: t(context, 'Delete', '删除'),
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
      title: t(context, 'Add key', '添加密钥'),
      child: const _KeyFormSheet(),
    );
  }

  Future<void> _showEditSheet(
      BuildContext context, WidgetRef ref, SshKey key) async {
    await showMSheet(
      context: context,
      title: t(context, 'Edit key', '编辑密钥'),
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
        toastWarn(context, t(context, 'Could not read the file.', '无法读取文件。'));
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
              '名称与私钥内容不能为空。'));
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
            labelText: t(context, 'Name', '名称'),
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
            labelText: t(context, 'Private key', '私钥'),
            alignLabelWithHint: true,
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          decoration: InputDecoration(
            labelText: t(context, 'Password (optional)', '密码（可选）'),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _loading ? null : _importFile,
          icon: const Icon(Icons.upload_file, size: 18),
          label: Text(t(context, 'Import file', '导入文件')),
        ),
        const SizedBox(height: 16),
        LoadingButton(
          label: t(context, 'Save', '保存'),
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

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      toastWarn(context, t(context, 'Name is required.', '名称不能为空。'));
      return;
    }
    setState(() => _loading = true);
    try {
      await ref.read(apiProvider).keyEdit(widget.sshKey.id, name, _password.text);
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
            labelText: t(context, 'Name', '名称'),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          decoration: InputDecoration(
            labelText: t(context, 'Password (optional)', '密码（可选）'),
            isDense: true,
          ),
        ),
        const SizedBox(height: 16),
        LoadingButton(
          label: t(context, 'Save', '保存'),
          loading: _loading,
          onPressed: _submit,
        ),
      ],
    );
  }
}
