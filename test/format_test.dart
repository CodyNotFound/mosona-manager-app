import 'package:flutter_test/flutter_test.dart';
import 'package:mosona_manager/core/utils/format.dart';

void main() {
  group('netRate', () {
    test('formats KiB/s below 1024', () {
      expect(netRate(512), '512 KiB/s');
      expect(netRate(0), '0 KiB/s');
    });
    test('converts to MiB/s', () {
      expect(netRate(1536), '1.5 MiB/s');
      expect(netRate(1024 * 1024), '1.0 GiB/s');
    });
  });

  group('mbTotal', () {
    test('formats MiB and GiB', () {
      expect(mbTotal(512), '512 MiB');
      expect(mbTotal(2048), '2.0 GiB');
      expect(mbTotal(1024 * 1024 * 1.5), '1.5 TiB');
    });
  });

  group('gb', () {
    test('formats TiB above 1024', () {
      expect(gb(100), '100 GiB');
      expect(gb(2048), '2.0 TiB');
    });
  });

  group('formatUptime', () {
    test('days + hours', () {
      expect(formatUptime(const Duration(days: 2, hours: 5)), '2d 5h');
    });
    test('hours + minutes', () {
      expect(formatUptime(const Duration(hours: 3, minutes: 21)), '3h 21m');
    });
    test('minutes only', () {
      expect(formatUptime(const Duration(minutes: 5)), '5m');
    });
    test('negative renders placeholder', () {
      expect(formatUptime(const Duration(seconds: -1)), '--');
    });
  });

  group('cycleLabel', () {
    test('full names', () {
      expect(cycleLabel(1), 'Monthly');
      expect(cycleLabel(2), 'Quarterly');
      expect(cycleLabel(3), 'Semi-annually');
      expect(cycleLabel(4), 'Yearly');
      expect(cycleLabel(0), 'One-time');
      expect(cycleLabel(-1), 'No cycle');
    });
    test('suffix mode', () {
      expect(cycleLabel(1, suffixMode: true), '/Mo');
      expect(cycleLabel(4, suffixMode: true), '/Ye');
    });
  });

  group('amountLabel', () {
    test('special values', () {
      expect(amountLabel('0', 1), 'Free');
      expect(amountLabel('-1', 1), 'PAYG');
      expect(amountLabel(null, 1), 'Free');
    });
    test('with suffix', () {
      expect(amountLabel('9.9', 1), '9.9/Mo');
      expect(amountLabel('30', 4), '30/Ye');
    });
  });

  group('compactNumber', () {
    test('thousands and millions', () {
      expect(compactNumber(999), '999');
      expect(compactNumber(1200), '1.2K');
      expect(compactNumber(2500000), '2.5M');
    });
  });

  group('osIconName', () {
    test('common distros', () {
      expect(osIconName('Ubuntu 22.04 LTS'), 'ubuntu');
      expect(osIconName('Debian GNU/Linux 12'), 'debian');
      expect(osIconName('CentOS Linux 7'), 'centos');
      expect(osIconName('Alpine Linux v3'), 'alpine');
      expect(osIconName('Microsoft Windows Server 2022'), 'windows');
      expect(osIconName('Darwin 23.1.0'), 'macos');
      expect(osIconName(''), 'unknown');
    });
  });

  group('uaSummary', () {
    test('chrome on windows', () {
      final (b, o) = uaSummary(
          'Mozilla/5.0 (Windows NT 10.0) AppleWebKit/537.36 Chrome/120.0 Safari/537.36');
      expect(b, 'Chrome');
      expect(o, 'Windows');
    });
    test('firefox on linux', () {
      final (b, o) = uaSummary('Mozilla/5.0 (X11; Linux x86_64) Gecko/20100101 Firefox/121.0');
      expect(b, 'Firefox');
      expect(o, 'Linux');
    });
    test('app ua', () {
      final (b, o) = uaSummary('MosonaManagerApp/1.0.0 (Flutter)');
      expect(b, 'Mosona App');
    });
  });

  group('remainingPercent / daysRemaining', () {
    test('half way', () {
      final start = DateTime.now().subtract(const Duration(days: 15));
      final end = DateTime.now().add(const Duration(days: 15));
      final p = remainingPercent(start, end, 1);
      expect((p - 50).abs(), lessThan(2));
    });
    test('expired clamps to 0', () {
      final start = DateTime.now().subtract(const Duration(days: 40));
      final end = DateTime.now().subtract(const Duration(days: 10));
      expect(remainingPercent(start, end, 1), 0);
    });
    test('no cycle renders 0', () {
      expect(remainingPercent(null, DateTime.now(), -1), 0);
    });
    test('daysRemaining', () {
      expect(daysRemaining(DateTime.now().add(const Duration(days: 3))), inInclusiveRange(2, 3));
      expect(daysRemaining(null), isNull);
    });
  });

  group('timeFrameWindowSize', () {
    test('web parity', () {
      expect(timeFrameWindowSize('1h'), 60);
      expect(timeFrameWindowSize('12h'), 120);
      expect(timeFrameWindowSize('24h'), 240);
      expect(timeFrameWindowSize('7d'), 336);
      expect(timeFrameWindowSize('30d'), 360);
      expect(timeFrameWindowSize('365d'), 365);
    });
  });

  group('serverTypeLabel / roleLabel / trafficTypeLabel', () {
    test('labels', () {
      expect(serverTypeLabel(0), 'SSH');
      expect(serverTypeLabel(1), 'Agent (active)');
      expect(serverTypeLabel(2), 'Agent (passive)');
      expect(roleLabel(0), 'Full access');
      expect(roleLabel(1), 'Read & terminal');
      expect(roleLabel(2), 'Read only');
      expect(trafficTypeLabel(2), 'Both');
    });
  });
}
