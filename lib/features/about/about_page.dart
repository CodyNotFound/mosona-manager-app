import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosona_manager/core/api/api_services.dart';
import 'package:mosona_manager/core/state/controllers.dart' show serverConfigProvider;
import 'package:mosona_manager/core/theme/mcolors.dart';
import 'package:mosona_manager/core/widgets/widgets.dart';

/// About page: brand hero, version (from GET /api/v1/version) and links.
class AboutPage extends ConsumerStatefulWidget {
  const AboutPage({super.key});

  @override
  ConsumerState<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends ConsumerState<AboutPage> {
  String? _version;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadVersion);
  }

  Future<void> _loadVersion() async {
    try {
      final v = await ref.read(apiProvider).version();
      if (!mounted) return;
      setState(() => _version = v);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = ref.watch(serverConfigProvider);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(title: Text(t(context, 'About', '关于'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          children: [
            const SizedBox(height: 8),
            Center(child: _glow(context, base)),
            const SizedBox(height: 22),
            Text(
              'Mosona Manager',
              textAlign: TextAlign.center,
              style:
                  monoStyle(context, size: 22).copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              t(context, 'Open-source server monitor & terminal management',
                  '开源服务器监控与终端管理'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: muted),
            ),
            const SizedBox(height: 14),
            Text(
              t(
                context,
                'Mosona Manager is an open-source, self-hosted server monitoring '
                    'and terminal management platform. Deploy a lightweight agent on '
                    'your machines, watch CPU, memory, disk and network in real time, '
                    'and open a secure shell right from your phone.',
                'Mosona Manager 是一个开源、可自托管的服务器监控与终端管理平台。'
                    '在机器上部署轻量 Agent，实时查看 CPU、内存、磁盘与网络，'
                    '并在手机上直接打开安全终端。',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.6, color: muted),
            ),
            const SizedBox(height: 24),
            FadeSlideIn(
              child: MCard(
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: muted),
                    const SizedBox(width: 8),
                    Text(t(context, 'Version', '版本'),
                        style: TextStyle(fontSize: 13, color: muted)),
                    const Spacer(),
                    _versionValue(theme),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            FadeSlideIn(
              delay: 60,
              child: MCard(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Column(
                  children: [
                    _linkTile(
                      context,
                      Icons.dock,
                      t(context, 'Docker deploy guide', 'Docker 部署指南'),
                      'https://manager.mosona.cc/docs/manual-deploy',
                    ),
                    Divider(height: 1, indent: 16, color: theme.dividerColor),
                    _linkTile(
                      context,
                      Icons.code,
                      'GitHub',
                      'https://github.com/mosona-labs/mosona-manager',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Brand hero: radial green glow with the about.webp artwork (or an "M").
  Widget _glow(BuildContext context, String base) {
    Widget fallback = Center(
      child: Text(
        'M',
        style: TextStyle(
          fontSize: 44,
          fontWeight: FontWeight.w900,
          color: MColors.link,
        ),
      ),
    );
    return Container(
      width: 140,
      height: 140,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [
          MColors.brand.withValues(alpha: 0.40),
          MColors.brand.withValues(alpha: 0.03),
        ]),
        boxShadow: [
          BoxShadow(
            color: MColors.brand.withValues(alpha: 0.30),
            blurRadius: 70,
            spreadRadius: 10,
          ),
        ],
      ),
      padding: const EdgeInsets.all(30),
      child: base.isEmpty
          ? fallback
          : ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.network(
                '$base/images/about.webp',
                width: 80,
                height: 80,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => fallback,
              ),
            ),
    );
  }

  Widget _versionValue(ThemeData theme) {
    if (_version == null && !_failed) {
      return const Skeleton(width: 80, height: 16);
    }
    if (_version == null) {
      return Text('--',
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant));
    }
    if (_version == '0.0.1') {
      // Backend convention: "0.0.1" means a self-compiled build.
      return Text(t(context, 'Self-built', '自行构建'),
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant));
    }
    return Text(_version!, style: monoStyle(context, size: 13));
  }

  Widget _linkTile(BuildContext context, IconData icon, String label, String url) {
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 20, color: MColors.link),
      title: Text(
        label,
        style: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.w600, color: MColors.link),
      ),
      trailing: Icon(Icons.open_in_new,
          size: 14, color: MColors.link.withValues(alpha: 0.7)),
      onTap: () => launchExternal(url),
    );
  }
}
