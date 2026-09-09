import 'package:flutter/material.dart';

/// Color tokens mirroring the web client (Tailwind palette + chart.css).
///
/// The web app uses a neutral shadcn theme for chrome colors and a fixed set
/// of semantic / chart colors. These constants keep the mobile app visually
/// aligned with it.
class MColors {
  MColors._();

  // Brand
  static const Color brand = Color(0xFF0CF8B9); // about-page glow
  static const Color link = Color(0xFF16A34A); // green-600 links
  static const Color logoFallback = Color(0xFFBBF7D0); // green-200

  // Status
  static const Color online = Color(0xFF22C55E); // green-500
  static const Color warning = Color(0xFFF97316); // orange-500
  static const Color offline = Color(0xFFEF4444); // red-500
  static const Color terminalConnected = Color(0xFF4ADE80); // green-400
  static const Color terminalConnecting = Color(0xFFFCD34D); // amber-300
  static const Color terminalDisconnected = Color(0xFFF87171); // red-400

  // Log levels
  static const Color logLow = Color(0xFF16A34A);
  static const Color logMedium = Color(0xFFCA8A04);
  static const Color logHigh = Color(0xFFDC2626);

  // Chart pairs (light hex from web chart.css)
  static const Color chartGreen1 = Color(0xFF7BF1A8);
  static const Color chartGreen2 = Color(0xFF00C950);
  static const Color chartBlue1 = Color(0xFF8EC5FF);
  static const Color chartBlue2 = Color(0xFF2B7FFF);
  static const Color chartRed1 = Color(0xFFFF7B7B);
  static const Color chartRed2 = Color(0xFFFF0000);
  static const Color chartYellow1 = Color(0xFFFFDF20);
  static const Color chartYellow2 = Color(0xFFF0B100);
  static const Color chartOrange1 = Color(0xFFFFB86A);
  static const Color chartOrange2 = Color(0xFFFF6900);
  static const Color chartViolet1 = Color(0xFFC4B4FF);
  static const Color chartViolet2 = Color(0xFF8E51FF);

  // Badge tints (20% alpha over the named color)
  static const Color badgeEmerald = Color(0x3322C55E);
  static const Color badgeIndigo = Color(0x336366F1);
  static const Color badgeViolet = Color(0x338B5CF6);
  static const Color badgeYellow = Color(0x33EAB308);
  static const Color badgeGreen = Color(0x3322C55E);
  static const Color badgeOrange = Color(0x33F97316);
  static const Color badgeRed = Color(0x33EF4444);

  // Light theme surfaces (shadcn oklch approximations)
  static const Color lightBackground = Color(0xFFFFFFFF);
  static const Color lightForeground = Color(0xFF232323);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightSecondary = Color(0xFFF5F5F5);
  static const Color lightMutedForeground = Color(0xFF8A8A8A);
  static const Color lightBorder = Color(0xFFE8E8E8);
  static const Color lightDestructive = Color(0xFFD93036);

  // Dark theme surfaces
  static const Color darkBackground = Color(0xFF0A0A0A);
  static const Color darkForeground = Color(0xFFF5F5F5);
  static const Color darkCard = Color(0xFF161616);
  static const Color darkSecondary = Color(0xFF2A2A2A);
  static const Color darkMutedForeground = Color(0xFFA8A8A8);
  static const Color darkBorder = Color(0x1AFFFFFF);
  static const Color darkDestructive = Color(0xFFE5484D);

  /// Progress bar color threshold used everywhere (CPU/mem/disk/swap/cycle).
  static Color progressColor(double percent) {
    if (percent >= 80) return const Color(0x80F87171); // red-400/50
    if (percent >= 60) return const Color(0x99F97316); // orange-500/60
    return const Color(0x9922C55E); // green-500/60
  }

  /// Server status color: online / warning / offline.
  static Color statusColor(ServerLifeStatus s) {
    switch (s) {
      case ServerLifeStatus.online:
        return online;
      case ServerLifeStatus.warning:
        return warning;
      case ServerLifeStatus.offline:
        return offline;
    }
  }
}

enum ServerLifeStatus { online, warning, offline }
