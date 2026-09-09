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

  final _name = TextEditingController();
  final _domain = TextEditingController();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _css = TextEditingController();
  String? _nameError;
  String? _domainError;
  String? _generalError;

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
        _nameError = null;
        _domainError = null;
        _generalError = null;
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

  // ------------------------------------------------------------ generation

  /// Web parity (page/publicPage/index.tsx:42-46): slug of the team name
  /// (max 20 chars, fallback "status") + 6 random chars, capped at 32.
  String _generateRandomPathName() {
    var slug = slugify(_teamName);
    if (slug.length > 20) slug = slug.substring(0, 20);
    final base = slug.isEmpty ? 'status' : slug;
    var path = '$base-${randomHex(6)}';
    if (path.length > 32) path = path.substring(0, 32);
    while (path.endsWith('-')) {
      path = path.substring(0, path.length - 1);
    }
    return path;
  }

  String _generateDefaultTitle() {
    final base = _teamName.trim().isEmpty
        ? t(context, 'Status Page', '状态页')
        : _teamName.trim();
    return t(context, '$base Status', '$base 状态');
  }

  String _generateDefaultDescription() {
    final base = _teamName.trim().isEmpty
        ? t(context, 'This team', '当前团队')
        : _teamName.trim();
    return t(context, 'The public status page for $base.', '$base 的公开状态页。');
  }

  // ------------------------------------------------------------ validation

  String get _nameInvalidMsg => t(
      context,
      'Use 3-32 lowercase letters, numbers, or hyphens. Hyphens cannot be at the start or end.',
      '使用 3-32 个小写字母、数字或连字符。连字符不能出现在开头或结尾。');

  String? _validateName(String value) {
    if (value.isEmpty) return null; // optional when a domain is set
    if (!_nameRe.hasMatch(value)) return _nameInvalidMsg;
    return null;
  }

  String? _validateDomain(String value) {
    if (value.isEmpty) return null; // optional
    if (value.contains('://') ||
        RegExp(r'[/?#@]').hasMatch(value) ||
        RegExp(r'\s').hasMatch(value)) {
      return t(context,
          'Enter a host only, without https://, paths, queries, fragments, or @.',
          '仅填写主机名。不要包含 https://、路径、查询参数或 @。');
    }
    final labels = value.split('.');
    if (labels.any((l) => l.isEmpty || !_labelRe.hasMatch(l))) {
      return t(context, 'Enter a valid hostname, such as status.example.com.',
          '请输入有效主机名，如 status.example.com。');
    }
    return null;
  }

  /// Web parity (page/publicPage/index.tsx:84-98): map known server messages
  /// onto the matching form field; unmapped errors go to the toast.
  ({String? name, String? domain, String? general})? _mapApiError(String msg) {
    switch (msg) {
      case 'Invalid public page name':
      case 'Public page name is already in use':
        return (name: msg, domain: null, general: null);
      case 'Invalid public page domain':
      case 'Public page domain is already in use':
        return (name: null, domain: msg, general: null);
      case 'At least one of name or domain is required when public page is enabled':
      case 'Invalid request format':
        return (name: null, domain: null, general: msg);
      default:
        return null;
    }
  }

  // ------------------------------------------------------------ submission

  Future<void> _save({String? nameOverride, String? domainOverride}) async {
    if (_saving) return;
    // Normalize like the web submit (page/publicPage/index.tsx:214-250):
    // lowercase + trim for name/domain, trim for title/description, and the
    // page is forced off when both identifiers are empty.
    final nextName = (nameOverride ?? _name.text).trim().toLowerCase();
    final nextDomain = (domainOverride ?? _domain.text).trim().toLowerCase();
    final nextTitle = _title.text.trim();
    final nextDescription = _description.text.trim();
    final nextEnabled =
        _enabled && (nextName.isNotEmpty || nextDomain.isNotEmpty);

    // Web only validates while the page is enabled, so a disabled config can
    // always be saved (page/publicPage/index.tsx:222-238).
    String? nameError;
    String? domainError;
    if (nextEnabled) {
      nameError = _validateName(nextName);
      domainError = _validateDomain(nextDomain);
    }

    if (nameError != null || domainError != null) {
      setState(() {
        _nameError = nameError;
        _domainError = domainError;
        _generalError = null;
      });
      return;
    }

    setState(() {
      _nameError = null;
      _domainError = null;
      _generalError = null;
      _saving = true;
    });
    try {
      await _api.updatePublicPage(PublicPageConfig(
        enabled: nextEnabled,
        name: nextName,
        domain: nextDomain,
        title: nextTitle,
        description: nextDescription,
        customCss: _css.text.trim().isEmpty ? '' : _css.text,
      ));
      if (!mounted) return;
      toastSuccess(context);
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      final mapped = _mapApiError(e.msg);
      if (mapped != null) {
        setState(() {
          _nameError = mapped.name;
          _domainError = mapped.domain;
          _generalError = mapped.general;
        });
        return;
      }
      showApiError(context, e);
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// One-tap clear for path/domain that immediately persists the change
  /// (web page/publicPage/index.tsx:272-280,436-445,477-485).
  Future<void> _clearField({required bool isName}) async {
    setState(() {
      if (isName) {
        _name.text = '';
        _nameError = null;
      } else {
        _domain.text = '';
        _domainError = null;
      }
    });
    await _save(nameOverride: isName ? '' : null, domainOverride: isName ? null : '');
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(t(context, 'Enabled', '启用'),
                                            style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600)),
                                        const SizedBox(height: 2),
                                        Text(
                                          t(
                                              context,
                                              'Expose a public status page for this team. When enabled a default path and title are generated for you.',
                                              '公开本团队的状态页。启用时会自动生成默认路径与标题。'),
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: theme
                                                  .colorScheme.onSurfaceVariant),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Switch(
                                    value: _enabled,
                                    onChanged: (v) {
                                      setState(() {
                                        _enabled = v;
                                        _nameError = null;
                                        _domainError = null;
                                        _generalError = null;
                                        if (v) {
                                          if (_name.text.trim().isEmpty) {
                                            _name.text = _generateRandomPathName();
                                          }
                                          if (_title.text.trim().isEmpty) {
                                            _title.text = _generateDefaultTitle();
                                          }
                                          if (_description.text.trim().isEmpty) {
                                            _description.text =
                                                _generateDefaultDescription();
                                          }
                                        }
                                      });
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _name,
                                enabled: true,
                                onChanged: (_) => setState(() {
                                  _nameError = null;
                                  _generalError = null;
                                }),
                                decoration: InputDecoration(
                                  labelText: t(context, 'Path', '路径'),
                                  hintText: 'my-status-page',
                                  helperText: t(context,
                                      '3-32 chars, lowercase letters, numbers, and hyphens only.',
                                      '3-32 个字符，仅限小写字母、数字和连字符。'),
                                  isDense: true,
                                  border: const OutlineInputBorder(),
                                  errorText: _nameError,
                                  suffixIcon: IconButton(
                                    tooltip: t(context, 'Clear path', '清空路径'),
                                    icon: const Icon(Icons.delete_outline, size: 20),
                                    onPressed:
                                        _name.text.isEmpty ? null : () => _clearField(isName: true),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _domain,
                                onChanged: (_) => setState(() {
                                  _domainError = null;
                                  _generalError = null;
                                }),
                                decoration: InputDecoration(
                                  labelText:
                                      t(context, 'Custom domain (optional)', '自定义域名（可选）'),
                                  hintText: 'status.example.com',
                                  helperText: t(context,
                                      'Host only. Do not include https://, paths, query strings, or @.',
                                      '仅填写主机名。不要包含 https://、路径、查询参数或 @。'),
                                  isDense: true,
                                  border: const OutlineInputBorder(),
                                  errorText: _domainError,
                                  suffixIcon: IconButton(
                                    tooltip: t(context, 'Clear domain', '清空域名'),
                                    icon: const Icon(Icons.delete_outline, size: 20),
                                    onPressed: _domain.text.isEmpty
                                        ? null
                                        : () => _clearField(isName: false),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _title,
                                maxLength: 255,
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                  labelText: t(context, 'Title', '标题'),
                                  counterText: '',
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
                              if (_generalError != null) ...[
                                const SizedBox(height: 10),
                                Text(
                                  _generalError!,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: theme.colorScheme.error),
                                ),
                              ],
                            ],
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
