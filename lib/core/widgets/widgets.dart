import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../state/controllers.dart';

export '../state/controllers.dart' show t;
import '../theme/mcolors.dart';
import '../utils/format.dart';

/// Shared UI primitives aligned with the web client's look & feel.

class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.description, this.actions});

  final String title;
  final String? description;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                if (description?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 2),
                  Text(description!,
                      style: TextStyle(
                          fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ],
            ),
          ),
          ...?actions,
        ],
      ),
    );
  }
}

class MCard extends StatelessWidget {
  const MCard({super.key, required this.child, this.padding, this.onTap, this.onLongPress});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: padding ?? const EdgeInsets.all(14),
          child: child,
        ),
      ),
    );
  }
}

class MBadge extends StatelessWidget {
  const MBadge({
    super.key,
    required this.child,
    this.color,
    this.backgroundColor,
    this.small = false,
  });

  final Widget child;
  final Color? color;
  final Color? backgroundColor;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = color ?? theme.colorScheme.onSurface;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 6 : 8, vertical: small ? 2 : 4),
      decoration: BoxDecoration(
        color: backgroundColor ?? fg.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: DefaultTextStyle(
        style: TextStyle(
          fontSize: small ? 10 : 11,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
        child: child,
      ),
    );
  }
}

/// 2px progress bar with threshold color (web parity).
class MProgress extends StatelessWidget {
  const MProgress({super.key, required this.percent, this.height = 4, this.color});

  final double percent;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? MColors.progressColor(percent.clamp(0, 100));
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: percent.clamp(0, 100) / 100),
        duration: const Duration(milliseconds: 400),
        builder: (context, v, _) => LinearProgressIndicator(
          value: v,
          minHeight: height,
          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
          valueColor: AlwaysStoppedAnimation(c),
        ),
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final ServerLifeStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      ServerLifeStatus.online => (
          t(context, 'online', '在线', zhHk: '在線'),
          MColors.online
        ),
      ServerLifeStatus.warning => (
          t(context, 'warning', '警告', zhHk: '警告'),
          MColors.warning
        ),
      ServerLifeStatus.offline => (
          t(context, 'offline', '离线', zhHk: '離線'),
          MColors.offline
        ),
    };
    return MBadge(color: color, child: Text(label));
  }
}

/// Server OS icon served by the hub at /icons/{name}.svg.
class OsIcon extends ConsumerWidget {
  const OsIcon({super.key, this.os, this.size = 32});

  final String? os;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final base = ref.watch(serverConfigProvider);
    final theme = Theme.of(context);
    if (base.isEmpty) {
      return _fallback(theme, Icons.dns_outlined);
    }
    final url = '$base/icons/${osIconName(os)}.svg';
    return SvgPicture.network(
      url,
      width: size,
      height: size,
      placeholderBuilder: (_) => _fallback(theme, Icons.dns_outlined),
    );
  }

  Widget _fallback(ThemeData theme, IconData icon) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: theme.colorScheme.secondary,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: size * 0.6, color: theme.colorScheme.onSurfaceVariant),
      );
}

/// Country flag served at /flags/{cc}.svg.
class FlagIcon extends ConsumerWidget {
  const FlagIcon({super.key, this.countryCode, this.size = 14});

  final String? countryCode;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cc = (countryCode ?? '').toLowerCase();
    if (cc.isEmpty || cc == '--') return const SizedBox.shrink();
    final base = ref.watch(serverConfigProvider);
    if (base.isEmpty) return const SizedBox.shrink();
    return SvgPicture.network(
      '$base/flags/$cc.svg',
      width: size,
      height: size,
      placeholderBuilder: (_) => const SizedBox.shrink(),
    );
  }
}

/// Gravatar avatar (md5 of email, mm fallback).
class Gravatar extends StatelessWidget {
  const Gravatar({super.key, required this.email, this.size = 36});

  final String email;
  final double size;

  String get _hash =>
      crypto.md5.convert(utf8.encode(email.trim().toLowerCase())).toString();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Image.network(
        'https://www.gravatar.com/avatar/$_hash?d=mm&s=128',
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => CircleAvatar(
          radius: size / 2,
          child: Icon(Icons.person, size: size * 0.55),
        ),
      ),
    );
  }
}

/// Submit button with an inline spinner when loading.
class LoadingButton extends StatelessWidget {
  const LoadingButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.danger = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (loading) ...[
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
        ],
        Text(label),
      ],
    );
    if (danger) {
      return FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: theme.colorScheme.error,
          foregroundColor: Colors.white,
        ),
        onPressed: loading ? null : onPressed,
        child: child,
      );
    }
    return FilledButton(
      onPressed: loading ? null : onPressed,
      child: child,
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.text, this.icon = Icons.inbox_outlined});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(text,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.width, this.height = 14, this.radius = 6});

  final double? width;
  final double height;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FadeTransition(
      opacity: Tween(begin: 0.4, end: 1.0)
          .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// Overview stat tile (dashboard/admin cards).
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color,
    this.subtitle,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? MColors.online;
    return MCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: c),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 10),
          Text(value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(label,
              style:
                  TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
          if (subtitle != null)
            Text(subtitle!,
                style: TextStyle(
                    fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// Key/value row used on the monitor info card and profile.
class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.label, this.value, this.child});

  final String label;
  final String? value;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label,
                style: TextStyle(
                    fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
          ),
          Expanded(
            child: child ??
                Text(value ?? '--',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ toasts

void _toast(BuildContext context, String message, Color color) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: Theme.of(context).colorScheme.surface,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: color),
      ),
    ),
  );
}

void toastSuccess(BuildContext context, [String? msg]) =>
    _toast(context, msg ?? t(context, 'Success', '成功'), MColors.online);

void toastWarn(BuildContext context, String msg) =>
    _toast(context, msg, MColors.warning);

void toastError(BuildContext context, String msg) =>
    _toast(context, msg, MColors.offline);

/// Web `ToastError` parity: code-based error presentation for [ApiException].
void showApiError(BuildContext context, Object error) {
  if (error is ApiException) {
    if (error.isNetwork) {
      toastWarn(context, t(context, 'Connection Error', '连接错误'));
      return;
    }
    if (error.code == 'error' || error.code == 'err') {
      toastError(context, error.msg);
    } else {
      final title = error.code.substring(0, 1).toUpperCase() + error.code.substring(1);
      toastWarn(context, title.isNotEmpty ? '$title\n${error.msg}' : error.msg);
    }
    return;
  }
  toastError(context, error.toString());
}

// ------------------------------------------------------------------ sheets

Future<T?> showMSheet<T>({
  required BuildContext context,
  required Widget child,
  String? title,
  bool scrollable = true,
}) {
  final theme = Theme.of(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: theme.colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Text(title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          Flexible(
            child: scrollable
                ? SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), child: child)
                : Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), child: child),
          ),
        ],
      ),
    ),
  );
}

/// Confirmation dialog that requires typing [name] to proceed (web parity
/// for destructive server/team/user deletion).
class ConfirmNameDialog extends StatefulWidget {
  const ConfirmNameDialog({
    super.key,
    required this.title,
    required this.message,
    required this.name,
    this.confirmLabel,
    this.extraLabel,
    this.extraObscure = true,
  });

  final String title;
  final String message;
  final String name; // text the user must type to enable confirm
  final String? confirmLabel;

  /// Optional second required input (e.g. admin current password). The dialog
  /// owns this field: confirm stays disabled until it is non-empty and pops
  /// its text (empty string when [extraLabel] is null).
  final String? extraLabel;
  final bool extraObscure;

  @override
  State<ConfirmNameDialog> createState() => _ConfirmNameDialogState();
}

class _ConfirmNameDialogState extends State<ConfirmNameDialog> {
  final _controller = TextEditingController();
  final _extra = TextEditingController();

  bool get _nameOk => _controller.text.trim() == widget.name;
  bool get _extraOk =>
      widget.extraLabel == null || _extra.text.isNotEmpty;
  bool get _valid => _nameOk && _extraOk;

  @override
  void dispose() {
    _controller.dispose();
    _extra.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.message, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: widget.name,
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (widget.extraLabel != null) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _extra,
              obscureText: widget.extraObscure,
              decoration: InputDecoration(
                isDense: true,
                labelText: widget.extraLabel,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(t(context, 'Cancel', '取消')),
        ),
        ValueListenableBuilder(
          valueListenable: _controller,
          builder: (context, _, _) => FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: Colors.white,
            ),
            onPressed: _valid ? () => Navigator.of(context).pop(_extra.text) : null,
            child: Text(widget.confirmLabel ??
                t(context, 'Confirm', '确认')),
          ),
        ),
      ],
    );
  }
}

/// Simple OK/Cancel dialog.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  String? okLabel,
  bool danger = false,
}) async {
  final theme = Theme.of(context);
  final res = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message, style: const TextStyle(fontSize: 13)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(t(context, 'Cancel', '取消')),
        ),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: Colors.white,
                )
              : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(okLabel ?? t(context, 'Confirm', '确认')),
        ),
      ],
    ),
  );
  return res ?? false;
}

/// Monospace style used for server names (web parity).
TextStyle monoStyle(BuildContext context, {double size = 13}) => TextStyle(
      fontFamily: 'Menlo',
      fontFamilyFallback: ['Monaco', 'Courier New', 'monospace'],
      fontSize: size,
      fontWeight: FontWeight.w600,
    );

/// Slide-fade entrance used for cards.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({super.key, required this.child, this.delay = 0, this.offset = 10});

  final Widget child;
  final int delay;
  final double offset;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );
  late final Animation<double> _a = CurvedAnimation(parent: _c, curve: Curves.easeOut);

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.delay.clamp(0, 900)), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _a,
      builder: (context, child) => Opacity(
        opacity: _a.value,
        child: Transform.translate(
          offset: Offset(0, widget.offset * (1 - _a.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Random hex string (avatar colors, slug suffixes). Uses a CSPRNG so the
/// same helper is safe for generated passwords too.
String randomHex(int length) {
  final rnd = math.Random.secure();
  const chars = '0123456789abcdef';
  return List.generate(length, (_) => chars[rnd.nextInt(chars.length)]).join();
}

/// Human-friendly secure password (letters+digits, unambiguous characters)
/// used by the admin user form's generator.
String randomPassword(int length) {
  final rnd = math.Random.secure();
  const chars = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789';
  return List.generate(length, (_) => chars[rnd.nextInt(chars.length)]).join();
}

/// Opens an external URL (GitHub / docs / gravatar...).
Future<void> launchExternal(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
}
