import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/state/session.dart';
import '../../core/theme/mcolors.dart';
import '../../core/widgets/widgets.dart';

/// /admin — admin hub: greeting + navigation cards (web §3.16 entry).
class AdminHomePage extends ConsumerWidget {
  const AdminHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider.select((s) => s.user));
    return Scaffold(
      appBar: AppBar(title: Text(t(context, 'Admin', '管理后台'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            PageHeader(
              title: 'Hello, ${user?.username ?? 'admin'}!',
              description: t(context, 'Admin management console', '管理后台控制台'),
            ),
            const SizedBox(height: 8),
            _tile(
              context,
              delay: 0,
              icon: Icons.dashboard_outlined,
              color: MColors.chartBlue2,
              title: t(context, 'Dashboard', '概览'),
              subtitle: t(context, 'Site stats & host CPU / memory charts',
                  '站点统计与主机 CPU / 内存图表'),
              onTap: () => context.push('/admin/dashboard'),
            ),
            _tile(
              context,
              delay: 60,
              icon: Icons.group_outlined,
              color: MColors.chartViolet2,
              title: t(context, 'Users', '用户'),
              subtitle: t(context, 'Manage registered users', '管理注册用户'),
              onTap: () => context.push('/admin/users'),
            ),
            _tile(
              context,
              delay: 120,
              icon: Icons.receipt_long_outlined,
              color: MColors.chartOrange2,
              title: t(context, 'Admin Logs', '管理日志'),
              subtitle: t(context, 'Audit logs of the whole site', '全站审计日志'),
              onTap: () => context.push('/admin/logs'),
            ),
            _tile(
              context,
              delay: 180,
              icon: Icons.settings_outlined,
              color: MColors.chartGreen2,
              title: t(context, 'Settings', '设置'),
              subtitle: t(context,
                  'General / Email / Register & Login / OAuth2', '通用 / 邮件 / 注册登录 / OAuth2'),
              onTap: () => _openSettingsChooser(context),
            ),
          ],
        ),
      ),
    );
  }

  /// One Settings entry that opens a chooser with the four sections.
  void _openSettingsChooser(BuildContext pageContext) {
    showMSheet(
      context: pageContext,
      title: t(pageContext, 'Settings', '设置'),
      child: Builder(builder: (sheetContext) {
        Widget item(IconData icon, String label, String route) => ListTile(
              leading: Icon(icon, size: 22),
              title: Text(label, style: const TextStyle(fontSize: 14)),
              trailing: const Icon(Icons.chevron_right, size: 20),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              onTap: () {
                Navigator.of(sheetContext).pop();
                pageContext.push(route);
              },
            );
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            item(Icons.tune_outlined, t(pageContext, 'General', '通用'),
                '/admin/settings/general'),
            item(Icons.mail_outline, t(pageContext, 'Email', '邮件'),
                '/admin/settings/email'),
            item(Icons.how_to_reg_outlined,
                t(pageContext, 'Register & Login', '注册与登录'),
                '/admin/settings/register-login'),
            item(Icons.fingerprint, 'OAuth2', '/admin/settings/oauth'),
          ],
        );
      }),
    );
  }

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required int delay,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: FadeSlideIn(
        delay: delay,
        child: MCard(
          onTap: onTap,
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  size: 20, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
