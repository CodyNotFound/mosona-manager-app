import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter, LengthLimitingTextInputFormatter;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../../core/widgets/widgets.dart';

/// Team avatar helpers shared by TeamPage and CreateTeamPage.
///
/// Modes mirror the web client: either pick a color (preset swatches +
/// custom hue slider) or pick an image (cropped square, resized to 256px).

/// Web default team color.
const String kDefaultTeamColor = '#61390b';

/// Preset swatches, first entry is the web default.
const List<String> kTeamColorPresets = [
  '#61390b',
  '#16a34a',
  '#0ea5e9',
  '#6366f1',
  '#8b5cf6',
  '#ec4899',
  '#ef4444',
  '#f97316',
  '#eab308',
  '#14b8a6',
  '#64748b',
  '#0a0a0a',
];

Color colorFromHex(String hex) {
  var h = hex.trim().replaceAll('#', '');
  if (h.length == 3) {
    h = h.split('').map((c) => '$c$c').join();
  }
  if (h.length == 6) h = 'FF$h';
  final v = int.tryParse(h, radix: 16);
  return v == null ? const Color(0xFF61390B) : Color(v);
}

String hexFromColor(Color c) {
  String part(double v) => (v * 255.0).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  return '#${part(c.r)}${part(c.g)}${part(c.b)}';
}

/// WCAG relative luminance (web utils/color.ts rgbToLuminance).
double _luminanceChannel(double v) =>
    v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();

double luminanceOf(Color c) =>
    0.2126 * _luminanceChannel(c.r) +
    0.7152 * _luminanceChannel(c.g) +
    0.0722 * _luminanceChannel(c.b);

double contrastRatio(double l1, double l2) {
  final hi = math.max(l1, l2);
  final lo = math.min(l1, l2);
  return (hi + 0.05) / (lo + 0.05);
}

/// Picks a text color with >= 4.5:1 contrast against [bg], mirroring the web
/// avatar logic (components/team/avatar.tsx:59-95): walk lightness in 0.05
/// steps starting away from the background's lightness, fall back to b/w.
Color contrastTextFor(Color bg) {
  final bgLum = luminanceOf(bg);
  const target = 4.5;
  final hsl = HSLColor.fromColor(bg);
  final preferredDir = hsl.lightness > 0.5 ? -1 : 1;

  Color? tryDirection(int dir) {
    for (var i = 0; i <= 20; i++) {
      final newL = (hsl.lightness + dir * i * 0.05).clamp(0.0, 1.0);
      final candidate = hsl.withLightness(newL).toColor();
      if (contrastRatio(bgLum, luminanceOf(candidate)) >= target) {
        return candidate;
      }
    }
    return null;
  }

  final found = tryDirection(preferredDir) ?? tryDirection(-preferredDir);
  if (found == null) return bgLum > 0.5 ? Colors.black : Colors.white;
  return found;
}

/// Color circle with the team name initial (used in team lists).
class TeamAvatar extends StatelessWidget {
  const TeamAvatar({
    super.key,
    required this.name,
    this.colorHex = kDefaultTeamColor,
    this.size = 36,
  });

  final String name;
  final String colorHex;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bg = colorFromHex(colorHex);
    final initial = name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: bg,
      child: Text(
        initial,
        style: TextStyle(
          color: contrastTextFor(bg),
          fontWeight: FontWeight.w700,
          fontSize: size * 0.42,
        ),
      ),
    );
  }
}

/// Avatar editing card: color picker row or image pick (256px square crop).
///
/// Reports the current selection through [onChanged]; [imageBytes] is
/// non-null only when the user picked an image (send it as the multipart
/// `avatar_image` field), otherwise persist [colorHex] as `avatar_color`.
class AvatarEditor extends StatefulWidget {
  const AvatarEditor({
    super.key,
    this.name = '',
    this.initialColor = kDefaultTeamColor,
    this.initialImageUrl,
    this.onChanged,
  });

  /// Team name used for the avatar initial (web parity).
  final String name;
  final String initialColor;

  /// Network URL of the currently stored image avatar (may be null).
  final String? initialImageUrl;
  final void Function(String colorHex, Uint8List? imageBytes)? onChanged;

  @override
  State<AvatarEditor> createState() => _AvatarEditorState();
}

class _AvatarEditorState extends State<AvatarEditor> {
  late Color _color = colorFromHex(widget.initialColor);
  late double _hue = HSLColor.fromColor(_color).hue;
  late bool _imageMode = widget.initialImageUrl != null;
  Uint8List? _bytes;
  bool _busy = false;
  bool _initialImageFailed = false;
  late final _hexCtrl = TextEditingController(text: widget.initialColor);

  bool get _usingImage =>
      _imageMode &&
      (_bytes != null ||
          (widget.initialImageUrl != null && !_initialImageFailed));

  void _setColor(Color c, {String? hexText}) {
    setState(() {
      _color = c;
      _bytes = null;
      _imageMode = false;
      _hue = HSLColor.fromColor(c).hue;
      _hexCtrl.text = hexText ?? hexFromColor(c);
    });
    widget.onChanged?.call(hexFromColor(c), null);
  }

  void _emitImage() =>
      widget.onChanged?.call(hexFromColor(_color), _bytes);

  Future<void> _pickImage() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final xfile = await ImagePicker()
          .pickImage(source: ImageSource.gallery, maxWidth: 512, maxHeight: 512);
      if (xfile == null) return;
      final raw = await xfile.readAsBytes();
      final decoded = img.decodeImage(raw);
      if (!mounted) return;
      if (decoded == null) {
        toastWarn(context, t(context, 'Unsupported image format', '不支持的图片格式'));
        return;
      }
      final cropped = img.copyResizeCropSquare(
        decoded,
        size: 256,
        interpolation: img.Interpolation.average,
      );
      final jpg = img.encodeJpg(cropped, quality: 90);
      setState(() {
        _bytes = jpg;
        _imageMode = true;
      });
      _emitImage();
    } catch (_) {
      if (mounted) {
        toastWarn(context, t(context, 'Failed to process image', '图片处理失败'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = widget.name.isEmpty
        ? 'A'
        : widget.name.substring(0, 1).toUpperCase();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (_bytes != null)
              CircleAvatar(radius: 36, backgroundImage: MemoryImage(_bytes!))
            else if (_usingImage)
              CircleAvatar(
                radius: 36,
                backgroundColor: _color,
                backgroundImage: NetworkImage(widget.initialImageUrl!),
                onBackgroundImageError: (_, _) =>
                    setState(() => _initialImageFailed = true),
              )
            else
              CircleAvatar(
                radius: 36,
                backgroundColor: _color,
                child: Text(
                  initial,
                  style: TextStyle(
                    color: contrastTextFor(_color),
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _pickImage,
                    icon: _busy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.photo_outlined, size: 18),
                    label: Text(t(context, 'Choose image', '选择图片')),
                  ),
                  if (_usingImage)
                    TextButton(
                      onPressed: () => _setColor(_color),
                      child: Text(
                        t(context, 'Use color instead', '改用颜色'),
                        style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final hex in kTeamColorPresets)
              _Swatch(
                color: colorFromHex(hex),
                selected: !_usingImage && hexFromColor(_color) == hex,
                onTap: () => _setColor(colorFromHex(hex)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            SizedBox(
              width: 64,
              child: Text(
                t(context, 'Custom', '自定义'),
                style: TextStyle(
                    fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    height: 14,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      gradient: LinearGradient(
                        colors: [
                          for (var i = 0; i <= 6; i++)
                            HSVColor.fromAHSV(1, i * 60.0, 1, 1).toColor(),
                        ],
                      ),
                    ),
                  ),
                  Slider(
                    value: _hue.clamp(0, 360),
                    max: 360,
                    activeColor: Colors.transparent,
                    inactiveColor: Colors.transparent,
                    thumbColor: Colors.white,
                    onChanged: (v) => _setColor(
                        HSLColor.fromAHSL(1, v, 0.65, 0.5).toColor()),
                  ),
                ],
              ),
            ),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: _color,
                shape: BoxShape.circle,
                border: Border.all(color: theme.dividerColor),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Free-form hex input, web parity (components/team/avatar.tsx:160-166).
        TextField(
          controller: _hexCtrl,
          decoration: InputDecoration(
            labelText: t(context, 'Hex color', 'Hex 颜色'),
            hintText: '#16a34a',
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[#0-9a-fA-F]')),
            LengthLimitingTextInputFormatter(7),
          ],
          onChanged: (v) {
            final c = colorFromHex(v);
            setState(() {
              _color = c;
              _bytes = null;
              _imageMode = false;
              _hue = HSLColor.fromColor(c).hue;
            });
            widget.onChanged?.call(hexFromColor(c), null);
          },
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.selected, this.onTap});

  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? theme.colorScheme.primary : theme.dividerColor,
            width: selected ? 3 : 1,
          ),
        ),
        child: selected
            ? const Icon(Icons.check, size: 16, color: Colors.white)
            : null,
      ),
    );
  }
}
