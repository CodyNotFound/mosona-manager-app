import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mosona_manager/core/models/models.dart';

void main() {
  group('ServerStatus.fromJson', () {
    test('parses a full snapshot entry', () {
      const raw = '''
      {
        "cpu": 12.5,
        "mem_total_mb": 3800.0,
        "mem_used_mb": 1900.5,
        "swap_total_mb": 512,
        "swap_used_mb": 0,
        "disks": [ {"mp": "/", "total_gb": 40.0, "used_gb": 12.2} ],
        "disk_read_kib_s": 100.25,
        "disk_write_kib_s": 0,
        "disk_read_iops": 3,
        "disk_write_iops": 0,
        "rx_kib_s": 8192.0,
        "tx_kib_s": 1024.0,
        "rx_total_mb": 1048576.0,
        "tx_total_mb": 512.0,
        "tcp_total": 42,
        "udp_total": 7,
        "time": "2026-09-08T12:00:00Z"
      }
      ''';
      final s = ServerStatus.fromJson(jsonDecode(raw));
      expect(s.cpu, 12.5);
      expect(s.memPercent, closeTo(50.013, 0.01));
      expect(s.disks!.length, 1);
      expect(s.disks!.first.mp, '/');
      expect(s.disks!.first.usedPercent, closeTo(30.5, 0.1));
      expect(s.tcpTotal, 42);
      expect(s.time, isNotNull);
    });

    test('null disks tolerated', () {
      final s = ServerStatus.fromJson({'cpu': 0, 'disks': null});
      expect(s.disks, isNull);
      expect(s.memPercent, 0);
    });
  });

  group('MonitorSnapshot.fromJson', () {
    test('status map keyed by string ids', () {
      const raw = '''
      {
        "servers": [
          {"id": 1, "name": "web-1", "type": 0, "weight": 0, "category": 2,
           "allow_terminal": true, "os": "Debian 12", "county": "US", "area": "Los Angeles"}
        ],
        "status": {"1": {"cpu": 3.0, "time": "2026-09-08T12:00:00Z"}},
        "now": 1788964800
      }
      ''';
      final snap = MonitorSnapshot.fromJson(jsonDecode(raw));
      expect(snap.servers.length, 1);
      expect(snap.servers.first.name, 'web-1');
      expect(snap.status.containsKey(1), isTrue);
      expect(snap.status[1]!.cpu, 3.0);
      expect(snap.nowSec, 1788964800);
    });
  });

  group('ServerFull.fromJson + toEditJson', () {
    test('round trip key fields', () {
      const raw = '''
      {
        "id": 7, "category": 1, "type": 0, "name": "nas",
        "allow_monitor": true, "allow_terminal": false, "public_visible": true,
        "weight": 3, "note": "", "provider": "Hetzner",
        "cycle": 4, "start_time": "2026-01-01T00:00:00Z", "end_time": "2026-12-31T00:00:00Z",
        "amount": "39.9", "auto_renew": true, "bandwidth": "1Gbps", "traffic": "1TB",
        "traffic_type": 2, "note_public": "hi",
        "address": "1.2.3.4", "port": 22, "username": "root", "password": "",
        "key_id": 2, "agent_status": 0
      }
      ''';
      final s = ServerFull.fromJson(jsonDecode(raw));
      expect(s.publicVisible, isTrue);
      expect(s.cycle, 4);
      expect(s.amount, '39.9');
      final j = s.toEditJson();
      expect(j['name'], 'nas');
      expect(j['provider'], 'Hetzner');
      expect(j['public_visible'], isTrue);
      expect(j['key_id'], 2);
    });
  });

  group('AlertsData.fromJson', () {
    test('nested maps and item configs', () {
      const raw = '''
      {
        "alerts": {"5": {"cpu_usage": {"id": 1, "item": "cpu_usage", "threshold": 90, "for_duration": 300}}},
        "team_alerts": {"status": {"id": 2, "item": "status", "threshold": 1, "for_duration": 60}},
        "item_configs": [
          {"item": "cpu_usage", "label": "CPU Usage", "description": "",
           "threshold": {"enabled": true, "min": 0, "max": 100, "default": 90, "unit": "%"},
           "for_duration": {"enabled": true, "min": 30, "max": 86400, "default": 300, "unit": "s"},
           "notify_once": false}
        ]
      }
      ''';
      final d = AlertsData.fromJson(jsonDecode(raw));
      expect(d.alerts[5]!['cpu_usage']!.threshold, 90);
      expect(d.teamAlerts['status']!.forDuration, 60);
      expect(d.itemConfigs.first.threshold.unit, '%');
      expect(d.itemConfigs.first.threshold.max, 100);
    });
  });

  group('LogsPage.fromJson (cursor pagination)', () {
    test('parses logs and cursor', () {
      const raw = '''
      {
        "logs": [
          {"user_id": 1, "username": "cody", "email": "cody@example.com",
           "category": "server", "message": "Server added", "ip": "1.1.1.1",
           "ip_country": "United States", "ip_country_code": "US",
           "user_agent": "MosonaManagerApp/1.0.0 (Flutter)", "level": "low",
           "time": "2026-09-08T10:00:00Z"}
        ],
        "next_cursor": "MTc4ODk2NDgwMA==",
        "has_more": true
      }
      ''';
      final p = LogsPage.fromJson(jsonDecode(raw));
      expect(p.logs.first.username, 'cody');
      expect(p.hasMore, isTrue);
      expect(p.nextCursor, 'MTc4ODk2NDgwMA==');
      expect(uaSummaryOf(p.logs.first.userAgent), 'Mosona App');
    });
  });

  group('User / Team / misc models', () {
    test('User nullable flags', () {
      final u = User.fromJson({
        'id': 3,
        'username': 'a',
        'email': 'a@b.c',
        'is_admin': true,
        'created_at': '2026-01-01T00:00:00Z',
      });
      expect(u.isAdmin, isTrue);
      expect(u.totpEnabled, isNull);
      expect(u.verified, isNull);
    });

    test('TwoFaStatus cooling', () {
      final s = TwoFaStatus.fromJson(
          {'verified': true, 'totp': true, 'login_2fa': false, 'cooling': 12});
      expect(s.totp, isTrue);
      expect(s.cooling, 12);
    });

    test('PublicPageConfig', () {
      final c = PublicPageConfig.fromJson({
        'enabled': true,
        'name': 'myteam-a1b2c3',
        'url_by_name': 'https://x.example/preview/myteam-a1b2c3',
      });
      expect(c.enabled, isTrue);
      expect(c.urlByName, contains('preview'));
      final j = c.toUpdateJson();
      expect(j['enabled'], isTrue);
      expect(j['domain'], '');
    });
  });
}

String uaSummaryOf(String ua) {
  // local import-free check to keep this file focused on models
  final isApp = ua.contains('MosonaManagerApp');
  return isApp ? 'Mosona App' : 'Other';
}
