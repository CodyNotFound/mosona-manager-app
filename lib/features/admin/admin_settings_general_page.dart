import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../../core/api/api_services.dart';
import '../../core/state/controllers.dart';
import '../../core/widgets/widgets.dart';

/// /admin/settings/general — title, base URL, favicon, security switches.
class AdminSettingsGeneralPage extends ConsumerStatefulWidget {
  const AdminSettingsGeneralPage({super.key});

  @override
  ConsumerState<AdminSettingsGeneralPage> createState() =>
      _AdminSettingsGeneralPageState();
}

class _AdminSettingsGeneralPageState
    extends ConsumerState<AdminSettingsGeneralPage> {
  final _title = TextEditingController();
  final _domain = TextEditingController();
  bool _bindIp = false;
  bool _trustProxy = false;
  bool _debug = false;

  // loaded values for diffing
  String _oTitle = '';
  String _oDomain = '';
  bool _oBindIp = false;
  bool _oTrustProxy = false;
  bool _oDebug = false;

  String _favicon = '';
  int _faviconVersion = 0;
  bool _loading = true;
  bool _saving = false;
  bool _uploading = false;

  ApiServices get _api => ref.read(apiProvider);
  String get _base => ref.read(serverConfigProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _domain.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await _api.adminSettingsGet();
      if (!mounted) return;
      setState(() {
        _title.text = s.title;
        _domain.text = s.domain;
        _bindIp = s.sessionBindIp;
        _trustProxy = s.trustProxy;
        _debug = s.debug;
        _oTitle = s.title;
        _oDomain = s.domain;
        _oBindIp = s.sessionBindIp;
        _oTrustProxy = s.trustProxy;
        _oDebug = s.debug;
        _favicon = s.favicon;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showApiError(context, e);
    }
  }

  /// Resolves the favicon to an absolute URL (base + path fallback).
  String? get _faviconUrl {
    final f = _favicon.trim();
    if (f.isEmpty) return null;
    if (f.startsWith('http://') ||
        f.startsWith('https://') ||
        f.startsWith('data:')) {
      return f;
    }
    final base = _base;
    if (base.isEmpty) return null;
    final path = f.startsWith('/') ? f : '/$f';
    final bust = _faviconVersion > 0 ? '?v=$_faviconVersion' : '';
    return '$base$path$bust';
  }

  Future<void> _pickAndUploadFavicon() async {
    try {
      final picked =
          await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      final raw = await picked.readAsBytes();
      final decoded = img.decodeImage(raw);
      if (!mounted) return;
      if (decoded == null) {
        toastError(context, t(context, 'Unsupported image', '不支持的图片格式'));
        return;
      }
      final square = img.copyResizeCropSquare(decoded,
          size: 256, interpolation: img.Interpolation.average);
      final Uint8List bytes = img.encodeJpg(square);
      setState(() => _uploading = true);
      await _api.adminFaviconUpload(bytes);
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _faviconVersion++;
      });
      toastSuccess(context);
      _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      showApiError(context, e);
    }
  }

  Future<void> _save() async {
    final entries = <({String key, String value})>[];
    final title = _title.text.trim();
    final domain = _domain.text.trim();
    if (title != _oTitle) {
      entries.add((key: 'title', value: title));
    }
    if (domain != _oDomain) {
      entries.add((key: 'domain', value: domain));
    }
    if (_bindIp != _oBindIp) {
      entries.add((key: 'session_bind_ip', value: _bindIp ? 'true' : 'false'));
    }
    if (_trustProxy != _oTrustProxy) {
      entries.add((key: 'trust_proxy', value: _trustProxy ? 'true' : 'false'));
    }
    if (_debug != _oDebug) {
      entries.add((key: 'debug', value: _debug ? 'true' : 'false'));
    }
    if (entries.isEmpty) {
      toastWarn(context, t(context, 'No changes', '没有变更'));
      return;
    }
    setState(() => _saving = true);
    try {
      await _api.adminSettingsSet(entries);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _oTitle = title;
        _oDomain = domain;
        _oBindIp = _bindIp;
        _oTrustProxy = _trustProxy;
        _oDebug = _debug;
      });
      toastSuccess(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(t(context, 'General', '通用设置'))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final faviconUrl = _faviconUrl;
    return Scaffold(
      appBar: AppBar(title: Text(t(context, 'General', '通用设置'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            FadeSlideIn(
              delay: 0,
              child: MCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _field(
                      label: t(context, 'Site Title', '站点标题'),
                      controller: _title,
                      maxLength: 255,
                    ),
                    const SizedBox(height: 12),
                    _field(
                      label: t(context, 'Base URL (domain)', '基础 URL（域名）'),
                      controller: _domain,
                      hint: 'manager.example.com',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            FadeSlideIn(
              delay: 60,
              child: MCard(
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      clipBehavior: Clip.antiAlias,
                      alignment: Alignment.center,
                      child: faviconUrl == null ||
                              faviconUrl.startsWith('data:')
                          ? Icon(Icons.image_outlined,
                              color: theme.colorScheme.onSurfaceVariant)
                          : Image.network(
                              faviconUrl,
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Icon(
                                  Icons.image_outlined,
                                  color: theme.colorScheme.onSurfaceVariant),
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t(context, 'Favicon', '站点图标'),
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(
                              t(context,
                                  'PNG/JPG, square, resized to 256x256',
                                  'PNG/JPG，方形，自动裁剪为 256x256'),
                              style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _uploading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : FilledButton.tonal(
                            onPressed: _pickAndUploadFavicon,
                            child: Text(t(context, 'Upload', '上传')),
                          ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            FadeSlideIn(
              delay: 120,
              child: MCard(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: Column(
                  children: [
                    _switchRow(
                      t(context, 'Session Bind IP', '会话绑定 IP'),
                      t(context, 'Bind sessions to the login IP', '会话与登录 IP 绑定'),
                      _bindIp,
                      (v) => setState(() => _bindIp = v),
                    ),
                    const Divider(height: 1),
                    _switchRow(
                      t(context, 'Trust Proxy', '信任代理'),
                      t(context, 'Trust X-Forwarded-* headers', '信任 X-Forwarded-* 头'),
                      _trustProxy,
                      (v) => setState(() => _trustProxy = v),
                    ),
                    const Divider(height: 1),
                    _switchRow(
                      t(context, 'Debug', '调试模式'),
                      t(context, 'Verbose server errors', '服务端输出详细错误'),
                      _debug,
                      (v) => setState(() => _debug = v),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            FadeSlideIn(
              delay: 180,
              child: LoadingButton(
                label: t(context, 'Save', '保存'),
                loading: _saving,
                onPressed: _save,
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    String? hint,
    int? maxLength,
  }) {
    return TextField(
      controller: controller,
      maxLength: maxLength,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        counterText: maxLength == null ? null : '',
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _switchRow(
      String label, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: const TextStyle(fontSize: 14)),
      subtitle: Text(subtitle,
          style: const TextStyle(fontSize: 11)),
    );
  }
}
