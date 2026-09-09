/// Formatting helpers shared across pages (web parity).
library;

/// 1024-based rate/size formatting, e.g. 1536 -> "1.5 MiB/s".
String netRate(double kibPerSec) {
  var v = kibPerSec;
  const units = ['KiB/s', 'MiB/s', 'GiB/s', 'TiB/s'];
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v >= 100 || i == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1)} ${units[i]}';
}

/// 1024-based total formatting, input in MiB.
String mbTotal(double mb) {
  var v = mb;
  const units = ['MiB', 'GiB', 'TiB'];
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v >= 100 || i == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1)} ${units[i]}';
}

/// GB formatting for disk sizes.
String gb(double gb) => gb >= 1024
    ? '${(gb / 1024).toStringAsFixed(1)} TiB'
    : '${gb >= 100 ? gb.toStringAsFixed(0) : gb.toStringAsFixed(1)} GiB';

/// Uptime like "12d 3h" / "3h 21m" / "5m".
String formatUptime(Duration d) {
  if (d.isNegative) return '--';
  final days = d.inDays;
  final hours = d.inHours % 24;
  final minutes = d.inMinutes % 60;
  if (days > 0) return '${days}d ${hours}h';
  if (hours > 0) return '${hours}h ${minutes}m';
  return '${minutes}m';
}

String formatUptimeDays(DateTime? openTime) {
  if (openTime == null) return '--';
  return formatUptime(DateTime.now().difference(openTime)).split(' ').first;
}

/// Cycle: 0 once / 1 monthly / 2 quarterly / 3 semi-annual / 4 yearly / -1 none.
String cycleLabel(int? cycle, {bool suffixMode = false}) {
  switch (cycle) {
    case 0:
      return suffixMode ? 'Once' : 'One-time';
    case 1:
      return suffixMode ? '/Mo' : 'Monthly';
    case 2:
      return suffixMode ? '/Qu' : 'Quarterly';
    case 3:
      return suffixMode ? '/Hy' : 'Semi-annually';
    case 4:
      return suffixMode ? '/Ye' : 'Yearly';
    default:
      return suffixMode ? '' : 'No cycle';
  }
}

/// Total days a cycle represents (used for the remaining-progress bar).
int cycleDays(int? cycle) => switch (cycle) {
      1 => 30,
      2 => 91,
      3 => 182,
      4 => 365,
      _ => 0,
    };

/// Amount display: "0" -> Free, "-1" -> PAYG, otherwise "9.9/Mo".
String amountLabel(String? amount, int? cycle) {
  final a = amount ?? '';
  if (a.isEmpty || a == '0') return 'Free';
  if (a == '-1') return 'PAYG';
  final suffix = cycleLabel(cycle, suffixMode: true);
  return suffix.isEmpty ? a : '$a$suffix';
}

/// Days until expiry (negative = expired). null when no end_time/cycle.
int? daysRemaining(DateTime? end) {
  if (end == null) return null;
  return end.difference(DateTime.now()).inDays;
}

/// Remaining-cycle percent for the progress bar.
double remainingPercent(DateTime? start, DateTime? end, int? cycle) {
  final total = cycleDays(cycle);
  if (total == 0 || start == null || end == null) return 0;
  final whole = end.difference(start).inMilliseconds;
  if (whole <= 0) return 0;
  final left = end.difference(DateTime.now()).inMilliseconds;
  return (left / whole * 100).clamp(0, 100);
}

/// Traffic type: -1 none / 0 inbound / 1 outbound / 2 both.
String trafficTypeLabel(int? t) => switch (t) {
      0 => 'In',
      1 => 'Out',
      2 => 'Both',
      _ => '',
    };

/// Server type: 0 SSH / 1 active agent / 2 passive agent.
String serverTypeLabel(int type) => switch (type) {
      1 => 'Agent (active)',
      2 => 'Agent (passive)',
      _ => 'SSH',
    };

/// Team role: 0 full / 1 read+terminal / 2 read only.
String roleLabel(int role) => switch (role) {
      0 => 'Full access',
      1 => 'Read & terminal',
      2 => 'Read only',
      _ => '',
    };

/// Compact number: >=1M -> "1.2M", >=1K -> "1.2K".
String compactNumber(int n) {
  if (n >= 1000000) {
    final v = n / 1000000;
    return '${v >= 10 ? v.toStringAsFixed(0) : v.toStringAsFixed(1)}M';
  }
  if (n >= 1000) {
    final v = n / 1000;
    return '${v >= 10 ? v.toStringAsFixed(0) : v.toStringAsFixed(1)}K';
  }
  return n.toString();
}

/// OS icon file name, mirroring web's getOsIconName (best-effort lowercase match).
String osIconName(String? os) {
  final s = (os ?? '').toLowerCase();
  if (s.isEmpty) return 'unknown';
  if (s.contains('alpine')) return 'alpine';
  if (s.contains('almalinux')) return 'almalinux';
  if (s.contains('amazon')) return 'amazon';
  if (s.contains('android')) return 'android';
  if (s.contains('arch')) return 'arch';
  if (s.contains('centos')) return 'centos';
  if (s.contains('debian')) return 'debian';
  if (s.contains('deepin')) return 'deepin';
  if (s.contains('devuan')) return 'devuan';
  if (s.contains('fedora')) return 'fedora';
  if (s.contains('freebsd')) return 'freebsd';
  if (s.contains('gentoo')) return 'gentoo';
  if (s.contains('kal') || s.contains('kali')) return 'kali';
  if (s.contains('linux')) return 'linux';
  if (s.contains('macos') || s.contains('darwin') || s.contains('mac os')) return 'macos';
  if (s.contains('manjaro')) return 'manjaro';
  if (s.contains('openbsd')) return 'openbsd';
  if (s.contains('opensuse') || s.contains('suse') || s.contains('leap')) return 'opensuse';
  if (s.contains('oracle')) return 'oracle';
  if (s.contains('pop')) return 'pop';
  if (s.contains('raspbian') || s.contains('raspberry')) return 'raspberry';
  if (s.contains('red hat') || s.contains('redhat') || s.contains('rhel')) return 'redhat';
  if (s.contains('rocky')) return 'rocky';
  if (s.contains('ubuntu')) return 'ubuntu';
  if (s.contains('windows')) return 'windows';
  if (s.contains('zorin')) return 'zorin';
  return 'unknown';
}

/// Extract a short browser/os summary from a raw user-agent string.
(String browser, String osName) uaSummary(String ua) {
  var browser = 'Unknown';
  if (ua.contains('Edg/')) {
    browser = 'Edge';
  } else if (ua.contains('OPR/') || ua.contains('Opera')) {
    browser = 'Opera';
  } else if (ua.contains('Chrome/') && !ua.contains('Chromium')) {
    browser = 'Chrome';
  } else if (ua.contains('Chromium')) {
    browser = 'Chromium';
  } else if (ua.contains('Firefox/')) {
    browser = 'Firefox';
  } else if (ua.contains('Safari/') && ua.contains('Version/')) {
    browser = 'Safari';
  } else if (ua.contains('MosonaManagerApp')) {
    browser = 'Mosona App';
  }
  var osName = 'Unknown';
  if (ua.contains('Windows')) {
    osName = 'Windows';
  } else if (ua.contains('iPhone') || ua.contains('iPad')) {
    osName = 'iOS';
  } else if (ua.contains('Mac OS') || ua.contains('Macintosh')) {
    osName = 'macOS';
  } else if (ua.contains('Android')) {
    osName = 'Android';
  } else if (ua.contains('Linux') || ua.contains('X11')) {
    osName = 'Linux';
  }
  return (browser, osName);
}

/// Chart window sizes (target points) per time frame, web parity.
int timeFrameWindowSize(String tf) => switch (tf) {
      '1h' => 60,
      '12h' => 120,
      '24h' => 240,
      '7d' => 336,
      '30d' => 360,
      '365d' => 365,
      _ => 60,
    };
