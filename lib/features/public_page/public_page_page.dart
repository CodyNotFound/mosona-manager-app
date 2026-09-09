import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_services.dart';
import '../../core/models/models.dart';
import '../../core/state/session.dart';
import '../../core/widgets/widgets.dart';

/// Lowercase, non [a-z0-9] -> '-', collapse repeats, trim from edges.
String slugify(String input) {
  var s = input.toLowerCase().trim();
  s = s.replaceAll(RegExp('[^a-z0-9]+'), '-');
  s = s.replaceAll(RegExp('-{2,}'), '-');
  while (s.startsWith('-')) {
    s = s.substring(1);
  }
  while (s.endsWith('-')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

final _nameRe = RegExp(r'^(?!-)[a-z0-9-]{3,32}(?<!-)$');
final _labelRe = RegExp(r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?$');

class PublicPagePage extends ConsumerStatefulWidget {
  const PublicPagePage({super.key});

  @override
  ConsumerState<PublicPagePage> createState() => _PublicPagePageState();
}

class _PublicPagePageState extends ConsumerState<PublicPagePage> {
  bool _loading = true;
  String? _error;
  PublicPageConfig? _cfg;
  bool _enabled = false;
  bool _saving = false;

  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _domain = TextEditingController();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _css = TextEditingController();
  String? _nameError;
  String? _domainError;

  ApiServices get _api => ref.read(apiProvider);

  String get _teamName => ref.read(sessionProvider).team?.name ?? 'team';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _domain.dispose();
    _title.dispose();
    _description.dispose();
    _css.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cfg = await _api.getPublicPage();
      if (!mounted) return;
      setState(() {
        _cfg = cfg;
        _enabled = cfg.enabled;
        _name.text = cfg.name ?? '';
        _domain.text = cfg.domain ?? '';
        _title.text = cfg.title ?? '';
        _description.text = cfg.description ?? '';
        _css.text = cfg.customCss ?? '';
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

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) toastSuccess(context, t(context, 'Copied', '已复制'));
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _nameError = null;
      _domainError = null;
    });
    if (!_formKey.currentState!.validate()) return;
    final cfg = PublicPageConfig(
      enabled: _enabled,
      name: _name.text.trim(),
      domain: _domain.text.trim(),
      title: _title.text.trim(),
      description: _description.text.trim(),
      customCss: _css.text,
    );
    setState(() => _saving = true);
    try {
      await _api.updatePublicPage(cfg);
      if (!mounted) return;
      toastSuccess(context);
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'conflict') {
        final msg = e.msg.toLowerCase();
        setState(() {
          if (msg.contains('domain')) {
            _domainError = e.msg;
          } else {
            _nameError = e.msg;
          }
        });
      }
      showApiError(context, e);
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _nameValidator(String? v) {
    final s = (v ?? '').trim();
    if (!_nameRe.hasMatch(s)) {
      return t(context,
          '3-32 chars: lowercase letters, digits, hyphen (no leading/trailing hyphen)',
          '3-32 位小写字母、数字或连字符（首尾不能是连字符）');
    }
    return null;
  }

  String? _domainValidator(String? v) {
    final s = (v ?? '').trim().toLowerCase();
    if (s.isEmpty) return null; // optional
    final labels = s.split('.');
    if (labels.length < 2 ||
        labels.any((l) => l.isEmpty || !_labelRe.hasMatch(l))) {
      return t(context, 'Enter a valid hostname (e.g. status.example.com)',
          '请输入有效主机名（如 status.example.com）');
    }
    return null;
  }

  String? _titleValidator(String? v) {
    if ((v ?? '').length > 255) {
      return t(context, 'Max 255 characters', '最多 255 个字符');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t(context, 'Public Page', '公开页')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: (_loading || _error != null || _saving) ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(t(context, 'Save', '保存')),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? ListView(
                padding: const EdgeInsets.all(16),
                children: const [
                  Skeleton(height: 90, radius: 12),
                  SizedBox(height: 16),
                  Skeleton(height: 320, radius: 12),
                ],
              )
            : _error != null
                ? ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      EmptyState(
                        text: t(context, 'Failed to load configuration', '配置加载失败'),
                        icon: Icons.link_off,
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
                        title: t(context, 'Public Page', '公开页'),
                        description: t(
                            context,
                            'Publish a read-only status page for your team servers',
                            '发布团队服务器的只读状态页'),
                      ),
                      if (_enabled) ...[
                        if ((_cfg?.urlByName ?? '').isNotEmpty)
                          FadeSlideIn(child: _urlCard(
                            label: t(context, 'By name', '按名称'),
                            url: _cfg!.urlByName!,
                          )),
                        if ((_cfg?.urlByDomain ?? '').isNotEmpty) ...[
                          const SizedBox(height: 12),
                          FadeSlideIn(
                            delay: 60,
                            child: _urlCard(
                              label: t(context, 'By domain', '按域名'),
                              url: _cfg!.urlByDomain!,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                      ],
                      FadeSlideIn(
                        delay: _enabled ? 120 : 0,
                        child: MCard(
                          child: Form(
                            key: _formKey,
                            autovalidateMode: AutovalidateMode.onUserInteraction,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(t(context, 'Enabled', '启用'),
                                        style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600)),
                                    const Spacer(),
                                    Switch(
                                      value: _enabled,
                                      onChanged: (v) {
                                        setState(() {
                                          _enabled = v;
                                          if (v) {
                                            if (_name.text.trim().isEmpty) {
                                              _name.text =
                                                  '${slugify(_teamName)}-${randomHex(6)}';
                                            }
                                            if (_title.text.trim().isEmpty) {
                                              _title.text = '$_teamName Status';
                                            }
                                          }
                                        });
                                      },
                                    ),
                                  ],
                                ),
                                Text(
                                  t(
                                      context,
                                      'Expose a public status page for this team. When enabled a default path and title are generated for you.',
                                      '公开本团队的状态页。启用时会自动生成默认路径与标题。'),
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: theme.colorScheme.onSurfaceVariant),
                                ),
                                const SizedBox(height: 14),
                                TextFormField(
                                  controller: _name,
                                  enabled: true,
                                  validator: _nameValidator,
                                  decoration: InputDecoration(
                                    labelText: t(context, 'Path', '路径'),
                                    hintText: 'my-status-page',
                                    isDense: true,
                                    border: const OutlineInputBorder(),
                                    errorText: _nameError,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _domain,
                                  validator: _domainValidator,
                                  decoration: InputDecoration(
                                    labelText:
                                        t(context, 'Custom domain (optional)', '自定义域名（可选）'),
                                    hintText: 'status.example.com',
                                    isDense: true,
                                    border: const OutlineInputBorder(),
                                    errorText: _domainError,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _title,
                                  validator: _titleValidator,
                                  decoration: InputDecoration(
                                    labelText: t(context, 'Title', '标题'),
                                    isDense: true,
                                    border: const OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _description,
                                  decoration: InputDecoration(
                                    labelText: t(context, 'Description', '描述'),
                                    isDense: true,
                                    border: const OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _css,
                                  maxLines: 5,
                                  style: monoStyle(context, size: 12),
                                  decoration: InputDecoration(
                                    labelText: t(context, 'Custom CSS', '自定义 CSS'),
                                    isDense: true,
                                    border: const OutlineInputBorder(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _urlCard({required String label, required String url}) {
    final theme = Theme.of(context);
    return MCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  url,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: monoStyle(context, size: 12),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: t(context, 'Copy', '复制'),
                icon: const Icon(Icons.copy_outlined, size: 18),
                onPressed: () => _copy(url),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: t(context, 'Open', '打开'),
                icon: const Icon(Icons.open_in_new, size: 18),
                onPressed: () => launchExternal(url),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
