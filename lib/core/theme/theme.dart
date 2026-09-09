import 'package:flutter/material.dart';

import 'mcolors.dart';

/// Builds light/dark [ThemeData] aligned with the web client's neutral
/// shadcn theme (white / near-black surfaces, 10px radius feel).
class MosunaTheme {
  MosunaTheme._();

  static ThemeData light() => _base(
        brightness: Brightness.light,
        background: MColors.lightBackground,
        foreground: MColors.lightForeground,
        card: MColors.lightCard,
        secondary: MColors.lightSecondary,
        mutedForeground: MColors.lightMutedForeground,
        border: MColors.lightBorder,
        destructive: MColors.lightDestructive,
      );

  static ThemeData dark() => _base(
        brightness: Brightness.dark,
        background: MColors.darkBackground,
        foreground: MColors.darkForeground,
        card: MColors.darkCard,
        secondary: MColors.darkSecondary,
        mutedForeground: MColors.darkMutedForeground,
        border: MColors.darkBorder,
        destructive: MColors.darkDestructive,
      );

  static ThemeData _base({
    required Brightness brightness,
    required Color background,
    required Color foreground,
    required Color card,
    required Color secondary,
    required Color mutedForeground,
    required Color border,
    required Color destructive,
  }) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: foreground,
      onPrimary: background,
      secondary: secondary,
      onSecondary: foreground,
      error: destructive,
      onError: brightness == Brightness.dark ? Colors.white : Colors.white,
      surface: card,
      onSurface: foreground,
      onSurfaceVariant: mutedForeground,
      outline: border,
      outlineVariant: border,
      inverseSurface: foreground,
      onInverseSurface: background,
    );

    final radius = BorderRadius.circular(10);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      splashFactory: InkSparkle.splashFactory,
      dividerColor: border,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: foreground,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: foreground,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: card,
        indicatorColor: secondary,
        elevation: 0,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? foreground : mutedForeground,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w400,
            color: states.contains(WidgetState.selected) ? foreground : mutedForeground,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: border),
        ),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: foreground,
          foregroundColor: background,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground,
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: foreground),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: secondary,
        hintStyle: TextStyle(color: mutedForeground),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: mutedForeground),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: destructive),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: secondary,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        labelStyle: TextStyle(color: foreground, fontSize: 13),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        showCheckmark: false,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: foreground,
        contentTextStyle: TextStyle(color: background),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: border),
        ),
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? MColors.online : secondary,
        ),
        thumbColor: const WidgetStatePropertyAll(Colors.white),
      ),
    );
  }
}
