/// Data models mirroring the Go backend JSON structs (see docs/backend-api-spec.md).
/// All parsing is tolerant: unknown/missing fields fall back to defaults.
library;

String? _s(dynamic v) => v?.toString();
int _i(dynamic v) => v == null ? 0 : (v is num ? v.toInt() : int.tryParse(v.toString()) ?? 0);
double _d(dynamic v) =>
    v == null ? 0 : (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0);
bool _b(dynamic v) {
  if (v == null) return false;
  if (v is bool) return v;
  return v.toString() == 'true' || v.toString() == '1';
}
int? _ni(dynamic v) => v == null ? null : (v is num ? v.toInt() : int.tryParse(v.toString()));
DateTime? _t(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());
Map<String, dynamic> _m(dynamic v) => v is Map<String, dynamic> ? v : {};
List<dynamic> _l(dynamic v) => v is List ? v : [];

class User {
  User({
    required this.id,
    required this.username,
    required this.email,
    this.totpEnabled,
    this.isAdmin = false,
    this.verified,
    required this.createdAt,
    this.loginAt,
    this.pwdAt,
  });

  final int id;
  final String username;
  final String email;
  final bool? totpEnabled;
  final bool isAdmin;
  final bool? verified;
  final DateTime createdAt;
  final DateTime? loginAt;
  final DateTime? pwdAt;

  factory User.fromJson(dynamic v) {
    final m = _m(v);
    return User(
      id: _i(m['id']),
      username: _s(m['username']) ?? '',
      email: _s(m['email']) ?? '',
      totpEnabled: m['totp_enabled'] == null ? null : _b(m['totp_enabled']),
      isAdmin: _b(m['is_admin']),
      verified: m['verified'] == null ? null : _b(m['verified']),
      createdAt: _t(m['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      loginAt: _t(m['login_at']),
      pwdAt: _t(m['pwd_at']),
    );
  }
}

class Team {
  Team({
    required this.id,
    required this.ownerId,
    required this.name,
    this.description = '',
    this.color = '',
    this.image = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  final int id;
  final int ownerId;
  final String name;
  final String description;
  final String color;
  final String image;
  final DateTime createdAt;

  factory Team.fromJson(dynamic v) {
    final m = _m(v);
    return Team(
      id: _i(m['id']),
      ownerId: _i(m['owner_id']),
      name: _s(m['name']) ?? '',
      description: _s(m['description']) ?? '',
      color: _s(m['color']) ?? '',
      image: _s(m['image']) ?? '',
      createdAt: _t(m['created_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'owner_id': ownerId,
        'name': name,
        'description': description,
        'color': color,
        'image': image,
        'created_at': createdAt.toIso8601String(),
      };
}

class TeamMember {
  TeamMember({required this.user, required this.role});

  final User user;
  final int role; // 0 admin / 1 read+terminal / 2 read only

  factory TeamMember.fromJson(dynamic v) =>
      TeamMember(user: User.fromJson(v), role: _i(_m(v)['role']));
}

class UserSession {
  UserSession({
    required this.id,
    required this.uid,
    required this.tid,
    required this.userAgent,
    this.clientIp = '',
    required this.time,
  });

  final String id;
  final int uid;
  final int tid;
  final String userAgent;
  final String clientIp;
  final DateTime time;

  factory UserSession.fromJson(dynamic v) {
    final m = _m(v);
    return UserSession(
      id: _s(m['id']) ?? '',
      uid: _i(m['uid']),
      tid: _i(m['tid']),
      userAgent: _s(m['user_agent']) ?? '',
      clientIp: _s(m['client_ip']) ?? '',
      time: _t(m['time']) ?? DateTime.fromMillisecondsSinceEpoch(_i(m['time']) * 1000),
    );
  }
}

class AuthIdentity {
  AuthIdentity({
    required this.id,
    required this.name,
    required this.icon,
    this.linkedName = '',
    this.linkedEmail = '',
  });

  final int id;
  final String name;
  final String icon;
  final String linkedName;
  final String linkedEmail;

  bool get linked => linkedEmail.isNotEmpty;

  factory AuthIdentity.fromJson(dynamic v) {
    final m = _m(v);
    final linked = _m(m['linked']);
    return AuthIdentity(
      id: _i(m['id']),
      name: _s(m['name']) ?? '',
      icon: _s(m['icon']) ?? '',
      linkedName: _s(linked['name']) ?? '',
      linkedEmail: _s(linked['email']) ?? '',
    );
  }
}

class AuthKeys {
  AuthKeys({this.captcha = '', required this.oauth});

  final String captcha; // Turnstile site key, empty = disabled
  final List<AuthProvider> oauth;

  factory AuthKeys.fromJson(dynamic v) {
    final m = _m(v);
    return AuthKeys(
      captcha: _s(m['captcha']) ?? '',
      oauth: _l(m['oauth']).map(AuthProvider.fromJson).toList(),
    );
  }
}

class AuthProvider {
  AuthProvider({required this.id, required this.name, required this.icon});

  final int id;
  final String name;
  final String icon;

  factory AuthProvider.fromJson(dynamic v) {
    final m = _m(v);
    return AuthProvider(
      id: _i(m['id']),
      name: _s(m['name']) ?? '',
      icon: _s(m['icon']) ?? '',
    );
  }
}

class Category {
  Category({required this.id, required this.name, required this.sort});

  final int id;
  final String name;
  final int sort;

  factory Category.fromJson(dynamic v) {
    final m = _m(v);
    return Category(id: _i(m['id']), name: _s(m['name']) ?? '', sort: _i(m['sort']));
  }
}

class SshKey {
  SshKey({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory SshKey.fromJson(dynamic v) {
    final m = _m(v);
    return SshKey(
      id: _i(m['id']),
      name: _s(m['name']) ?? '',
      createdAt: _t(m['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: _t(m['updated_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class ServerFull {
  ServerFull({
    required this.id,
    required this.category,
    required this.type,
    required this.name,
    required this.allowMonitor,
    required this.allowTerminal,
    this.publicVisible = false,
    required this.weight,
    this.note,
    this.provider,
    this.cycle,
    this.startTime,
    this.endTime,
    this.amount,
    this.autoRenew = false,
    this.bandwidth,
    this.traffic,
    this.trafficType,
    this.notePublic,
    this.address = '',
    this.port = 0,
    this.username = '',
    this.password = '',
    this.keyId = 0,
    this.hostKey = '',
    this.agentStatus = 0,
    this.agentVersion,
    this.agentLastSeenAt,
    this.agentUuid,
  });

  final int id;
  final int category;
  final int type; // 0 ssh / 1 active agent / 2 passive agent
  final String name;
  final bool allowMonitor;
  final bool allowTerminal;
  final bool publicVisible;
  final int weight;
  final String? note;
  final String? provider;
  final int? cycle; // 0 once / 1 month / 2 quarter / 3 half / 4 year / -1 none
  final DateTime? startTime;
  final DateTime? endTime;
  final String? amount; // "0"=free, "-1"=payg
  final bool autoRenew;
  final String? bandwidth;
  final String? traffic;
  final int? trafficType; // -1 none / 0 in / 1 out / 2 both
  final String? notePublic;
  final String address;
  final int port;
  final String username;
  final String password;
  final int keyId;
  final String hostKey;
  final int agentStatus;
  final String? agentVersion;
  final DateTime? agentLastSeenAt;
  final String? agentUuid;

  factory ServerFull.fromJson(dynamic v) {
    final m = _m(v);
    return ServerFull(
      id: _i(m['id']),
      category: _i(m['category']),
      type: _i(m['type']),
      name: _s(m['name']) ?? '',
      allowMonitor: _b(m['allow_monitor']),
      allowTerminal: _b(m['allow_terminal']),
      publicVisible: m['public_visible'] == null ? false : _b(m['public_visible']),
      weight: _i(m['weight']),
      note: _s(m['note']),
      provider: _s(m['provider']),
      cycle: _ni(m['cycle']),
      startTime: _t(m['start_time']),
      endTime: _t(m['end_time']),
      amount: _s(m['amount']),
      autoRenew: _b(m['auto_renew']),
      bandwidth: _s(m['bandwidth']),
      traffic: _s(m['traffic']),
      trafficType: _ni(m['traffic_type']),
      notePublic: _s(m['note_public']),
      address: _s(m['address']) ?? '',
      port: _i(m['port']),
      username: _s(m['username']) ?? '',
      password: _s(m['password']) ?? '',
      keyId: _i(m['key_id']),
      hostKey: _s(m['host_key']) ?? '',
      agentStatus: _i(m['agent_status']),
      agentVersion: _s(m['agent_version']),
      agentLastSeenAt: _t(m['agent_last_seen_at']),
      agentUuid: _s(m['agent_uuid']),
    );
  }

  /// JSON body shape expected by PUT /server/:id (JSON Bind).
  Map<String, dynamic> toEditJson() => {
        'id': id,
        'category': category,
        'type': type,
        'name': name,
        'allow_monitor': allowMonitor,
        'allow_terminal': allowTerminal,
        'public_visible': publicVisible,
        'weight': weight,
        'note': note ?? '',
        'provider': provider ?? '',
        'cycle': cycle ?? -1,
        'start_time': startTime?.toIso8601String() ?? '',
        'end_time': endTime?.toIso8601String() ?? '',
        'amount': amount ?? '',
        'auto_renew': autoRenew,
        'bandwidth': bandwidth ?? '',
        'traffic': traffic ?? '',
        'traffic_type': trafficType ?? -1,
        'note_public': notePublic ?? '',
        'address': address,
        'port': port,
        'username': username,
        'password': password,
        'key_id': keyId,
        if (hostKey.isNotEmpty) 'host_key': hostKey,
      };
}

class MonitorList {
  MonitorList({
    required this.id,
    required this.name,
    required this.type,
    required this.weight,
    required this.category,
    required this.allowTerminal,
    this.os,
    this.county,
    this.area,
    this.openTime,
    this.note,
    this.provider,
    this.cycle,
    this.startTime,
    this.endTime,
    this.amount,
    this.bandwidth,
    this.traffic,
    this.trafficType,
    this.notePublic,
    this.coreC,
    this.coreT,
  });

  final int id;
  final String name;
  final int type;
  final int weight;
  final int category;
  final bool allowTerminal;
  final String? os;
  final String? county; // country code
  final String? area;
  final DateTime? openTime;
  final String? note;
  final String? provider;
  final int? cycle;
  final DateTime? startTime;
  final DateTime? endTime;
  final String? amount;
  final String? bandwidth;
  final String? traffic;
  final int? trafficType;
  final String? notePublic;
  final int? coreC;
  final int? coreT;

  factory MonitorList.fromJson(dynamic v) {
    final m = _m(v);
    return MonitorList(
      id: _i(m['id']),
      name: _s(m['name']) ?? '',
      type: _i(m['type']),
      weight: _i(m['weight']),
      category: _i(m['category']),
      allowTerminal: _b(m['allow_terminal']),
      os: _s(m['os']),
      county: _s(m['county']),
      area: _s(m['area']),
      openTime: _t(m['open_time']),
      note: _s(m['note']),
      provider: _s(m['provider']),
      cycle: _ni(m['cycle']),
      startTime: _t(m['start_time']),
      endTime: _t(m['end_time']),
      amount: _s(m['amount']),
      bandwidth: _s(m['bandwidth']),
      traffic: _s(m['traffic']),
      trafficType: _ni(m['traffic_type']),
      notePublic: _s(m['note_public']),
      coreC: _ni(m['core_c']),
      coreT: _ni(m['core_t']),
    );
  }
}

class MonitorDetail {
  MonitorDetail({required this.list, this.detail});

  /// The MonitorList part.
  final MonitorList list;

  /// Extra advanced fields (hostname/cpu_name/kernel/ip/arch), null if absent.
  final Map<String, dynamic>? detail;

  String? get hostname => _s(detail?['hostname']);
  String? get cpuName => _s(detail?['cpu_name']);
  int? get coreC => _ni(detail?['core_c']);
  int? get coreT => _ni(detail?['core_t']);
  String? get kernel => _s(detail?['kernel']);
  String? get ip => _s(detail?['ip']);
  String? get arch => _s(detail?['arch']);

  factory MonitorDetail.fromJson(dynamic v) {
    final m = _m(v);
    return MonitorDetail(list: MonitorList.fromJson(m), detail: m);
  }
}

class TerminalServer {
  TerminalServer({
    required this.id,
    required this.name,
    required this.type,
    required this.category,
    this.os,
    this.username,
    this.address,
    this.port,
  });

  final int id;
  final String name;
  final int type;
  final int category;
  final String? os;
  final String? username;
  final String? address;
  final int? port;

  factory TerminalServer.fromJson(dynamic v) {
    final m = _m(v);
    return TerminalServer(
      id: _i(m['id']),
      name: _s(m['name']) ?? '',
      type: _i(m['type']),
      category: _i(m['category']),
      os: _s(m['os']),
      username: _s(m['username']),
      address: _s(m['address']),
      port: _ni(m['port']),
    );
  }
}

class DiskInfo {
  DiskInfo({required this.mp, required this.totalGb, required this.usedGb});

  final String mp;
  final double totalGb;
  final double usedGb;

  factory DiskInfo.fromJson(dynamic v) {
    final m = _m(v);
    return DiskInfo(
      mp: _s(m['mp']) ?? '/',
      totalGb: _d(m['total_gb']),
      usedGb: _d(m['used_gb']),
    );
  }

  double get usedPercent => totalGb <= 0 ? 0 : usedGb / totalGb * 100;
}

class ServerStatus {
  ServerStatus({
    required this.cpu,
    required this.memTotalMb,
    required this.memUsedMb,
    required this.swapTotalMb,
    required this.swapUsedMb,
    required this.disks,
    required this.diskReadKibS,
    required this.diskWriteKibS,
    required this.diskReadIops,
    required this.diskWriteIops,
    required this.rxKibS,
    required this.txKibS,
    required this.rxTotalMb,
    required this.txTotalMb,
    required this.tcpTotal,
    required this.udpTotal,
    required this.time,
  });

  final double cpu;
  final double memTotalMb;
  final double memUsedMb;
  final double swapTotalMb;
  final double swapUsedMb;
  final List<DiskInfo>? disks;
  final double diskReadKibS;
  final double diskWriteKibS;
  final double diskReadIops;
  final double diskWriteIops;
  final double rxKibS;
  final double txKibS;
  final double rxTotalMb;
  final double txTotalMb;
  final int tcpTotal;
  final int udpTotal;
  final DateTime? time;

  double get memPercent => memTotalMb <= 0 ? 0 : memUsedMb / memTotalMb * 100;
  double get swapPercent => swapTotalMb <= 0 ? 0 : swapUsedMb / swapTotalMb * 100;

  factory ServerStatus.fromJson(dynamic v) {
    final m = _m(v);
    return ServerStatus(
      cpu: _d(m['cpu']),
      memTotalMb: _d(m['mem_total_mb']),
      memUsedMb: _d(m['mem_used_mb']),
      swapTotalMb: _d(m['swap_total_mb']),
      swapUsedMb: _d(m['swap_used_mb']),
      disks: m['disks'] == null
          ? null
          : _l(m['disks']).map(DiskInfo.fromJson).toList(),
      diskReadKibS: _d(m['disk_read_kib_s']),
      diskWriteKibS: _d(m['disk_write_kib_s']),
      diskReadIops: _d(m['disk_read_iops']),
      diskWriteIops: _d(m['disk_write_iops']),
      rxKibS: _d(m['rx_kib_s']),
      txKibS: _d(m['tx_kib_s']),
      rxTotalMb: _d(m['rx_total_mb']),
      txTotalMb: _d(m['tx_total_mb']),
      tcpTotal: _i(m['tcp_total']),
      udpTotal: _i(m['udp_total']),
      time: _t(m['time']),
    );
  }
}

/// Snapshot pushed over the monitor SSE stream.
class MonitorSnapshot {
  MonitorSnapshot({required this.servers, required this.status, required this.nowSec});

  final List<MonitorList> servers;
  final Map<int, ServerStatus> status;
  final int nowSec;

  factory MonitorSnapshot.fromJson(dynamic v) {
    final m = _m(v);
    final status = <int, ServerStatus>{};
    final sm = _m(m['status']);
    sm.forEach((k, v) {
      final id = int.tryParse(k);
      if (id != null) status[id] = ServerStatus.fromJson(v);
    });
    return MonitorSnapshot(
      servers: _l(m['servers']).map(MonitorList.fromJson).toList(),
      status: status,
      nowSec: _i(m['now']),
    );
  }
}

class MonitorInfoResult {
  MonitorInfoResult({required this.info, required this.now, required this.stale});

  final MonitorDetail info;
  final DateTime? now;
  final bool stale;

  factory MonitorInfoResult.fromJson(dynamic v) {
    final m = _m(v);
    return MonitorInfoResult(
      info: MonitorDetail.fromJson(m['info']),
      now: _t(m['now']),
      stale: _b(m['stale']),
    );
  }
}

class ServerAlert {
  ServerAlert({
    required this.id,
    required this.item,
    required this.threshold,
    required this.forDuration,
  });

  final int id;
  final String item;
  final int threshold;
  final int forDuration;

  factory ServerAlert.fromJson(dynamic v) {
    final m = _m(v);
    return ServerAlert(
      id: _i(m['id']),
      item: _s(m['item']) ?? '',
      threshold: _i(m['threshold']),
      forDuration: _i(m['for_duration']),
    );
  }
}

class AlertFieldConfig {
  AlertFieldConfig({required this.enabled, this.min, this.max, this.defaultValue, this.unit = ''});

  final bool enabled;
  final int? min;
  final int? max;
  final int? defaultValue;
  final String unit;

  factory AlertFieldConfig.fromJson(dynamic v) {
    final m = _m(v);
    return AlertFieldConfig(
      enabled: _b(m['enabled']),
      min: _ni(m['min']),
      max: _ni(m['max']),
      defaultValue: _ni(m['default']),
      unit: _s(m['unit']) ?? '',
    );
  }
}

class AlertItemConfig {
  AlertItemConfig({
    required this.item,
    required this.label,
    required this.description,
    required this.threshold,
    required this.forDuration,
    required this.notifyOnce,
  });

  final String item;
  final String label;
  final String description;
  final AlertFieldConfig threshold;
  final AlertFieldConfig forDuration;
  final bool notifyOnce;

  factory AlertItemConfig.fromJson(dynamic v) {
    final m = _m(v);
    return AlertItemConfig(
      item: _s(m['item']) ?? '',
      label: _s(m['label']) ?? '',
      description: _s(m['description']) ?? '',
      threshold: AlertFieldConfig.fromJson(m['threshold']),
      forDuration: AlertFieldConfig.fromJson(m['for_duration']),
      notifyOnce: _b(m['notify_once']),
    );
  }
}

class AlertsData {
  AlertsData({
    required this.alerts,
    required this.teamAlerts,
    required this.itemConfigs,
  });

  /// server_id -> item -> alert
  final Map<int, Map<String, ServerAlert>> alerts;
  final Map<String, ServerAlert> teamAlerts;
  final List<AlertItemConfig> itemConfigs;

  factory AlertsData.fromJson(dynamic v) {
    final m = _m(v);
    final alerts = <int, Map<String, ServerAlert>>{};
    final am = _m(m['alerts']);
    am.forEach((sid, items) {
      final id = int.tryParse(sid);
      if (id == null) return;
      final inner = <String, ServerAlert>{};
      _m(items).forEach((item, a) => inner[item] = ServerAlert.fromJson(a));
      alerts[id] = inner;
    });
    final team = <String, ServerAlert>{};
    _m(m['team_alerts']).forEach((item, a) => team[item] = ServerAlert.fromJson(a));
    return AlertsData(
      alerts: alerts,
      teamAlerts: team,
      itemConfigs: _l(m['item_configs']).map(AlertItemConfig.fromJson).toList(),
    );
  }
}

class AuditLog {
  AuditLog({
    required this.userId,
    required this.username,
    required this.email,
    required this.category,
    required this.message,
    required this.ip,
    required this.ipCountry,
    required this.ipCountryCode,
    required this.userAgent,
    required this.level,
    required this.time,
  });

  final int userId;
  final String username;
  final String email;
  final String category;
  final String message;
  final String ip;
  final String ipCountry;
  final String ipCountryCode;
  final String userAgent;
  final String level; // low / medium / high
  final DateTime? time;

  factory AuditLog.fromJson(dynamic v) {
    final m = _m(v);
    return AuditLog(
      userId: _i(m['user_id']),
      username: _s(m['username']) ?? '',
      email: _s(m['email']) ?? '',
      category: _s(m['category']) ?? '',
      message: _s(m['message']) ?? '',
      ip: _s(m['ip']) ?? '',
      ipCountry: _s(m['ip_country']) ?? '',
      ipCountryCode: _s(m['ip_country_code']) ?? '',
      userAgent: _s(m['user_agent']) ?? '',
      level: _s(m['level']) ?? 'low',
      time: _t(m['time']),
    );
  }
}

class LogsPage {
  LogsPage({required this.logs, required this.nextCursor, required this.hasMore});

  final List<AuditLog> logs;
  final String nextCursor;
  final bool hasMore;

  factory LogsPage.fromJson(dynamic v) {
    final m = _m(v);
    return LogsPage(
      logs: _l(m['logs']).map(AuditLog.fromJson).toList(),
      nextCursor: _s(m['next_cursor']) ?? '',
      hasMore: _b(m['has_more']),
    );
  }
}

class NotificationTarget {
  NotificationTarget({required this.module, required this.target});

  final String module; // email | shoutrrr
  final String target;

  Map<String, dynamic> toJson() => {'module': module, 'target': target};

  factory NotificationTarget.fromJson(dynamic v) {
    final m = _m(v);
    return NotificationTarget(module: _s(m['module']) ?? 'email', target: _s(m['target']) ?? '');
  }
}

class PublicPageConfig {
  PublicPageConfig({
    required this.enabled,
    this.name,
    this.domain,
    this.title,
    this.description,
    this.customCss,
    this.urlByName,
    this.urlByDomain,
  });

  final bool enabled;
  final String? name;
  final String? domain;
  final String? title;
  final String? description;
  final String? customCss;
  final String? urlByName;
  final String? urlByDomain;

  factory PublicPageConfig.fromJson(dynamic v) {
    final m = _m(v);
    return PublicPageConfig(
      enabled: _b(m['enabled']),
      name: _s(m['name']),
      domain: _s(m['domain']),
      title: _s(m['title']),
      description: _s(m['description']),
      customCss: _s(m['custom_css']),
      urlByName: _s(m['url_by_name']),
      urlByDomain: _s(m['url_by_domain']),
    );
  }

  Map<String, dynamic> toUpdateJson() => {
        'enabled': enabled,
        'name': name ?? '',
        'domain': domain ?? '',
        'title': title ?? '',
        'description': description ?? '',
        'custom_css': customCss ?? '',
      };
}

/// Install parameters returned when adding / reinstalling an agent server.
class AgentInstallParams {
  AgentInstallParams({this.id, this.host, this.port, this.agentUid, this.publicKey, this.hub, this.enrollToken});

  final int? id;
  final String? host;
  final int? port;
  final String? agentUid;
  final String? publicKey;
  final String? hub;
  final String? enrollToken;

  factory AgentInstallParams.fromJson(dynamic v) {
    final m = _m(v);
    return AgentInstallParams(
      id: _ni(m['id']),
      host: _s(m['host']),
      port: _ni(m['port']),
      agentUid: _s(m['agent_uid']),
      publicKey: _s(m['public_key']),
      hub: _s(m['hub']),
      enrollToken: _s(m['enroll_token']),
    );
  }
}

class TwoFaStatus {
  TwoFaStatus({required this.verified, this.totp, required this.login2fa, required this.cooling});

  final bool verified;
  final bool? totp;
  final bool login2fa;
  final int cooling;

  factory TwoFaStatus.fromJson(dynamic v) {
    final m = _m(v);
    return TwoFaStatus(
      verified: _b(m['verified']),
      totp: m['totp'] == null ? null : _b(m['totp']),
      login2fa: _b(m['login_2fa']),
      cooling: _i(m['cooling']),
    );
  }
}

class SystemUsagePoint {
  SystemUsagePoint({required this.cpuUsage, required this.memory, required this.time});

  final double cpuUsage;
  final double memory;
  final DateTime? time;

  factory SystemUsagePoint.fromJson(dynamic v) {
    final m = _m(v);
    return SystemUsagePoint(
      cpuUsage: _d(m['cpu_usage']),
      memory: _d(m['memory']),
      time: _t(m['time']),
    );
  }
}

class AdminDashboardStats {
  AdminDashboardStats({
    required this.users,
    required this.teams,
    required this.servers,
    required this.records,
    required this.system,
  });

  final int users;
  final int teams;
  final int servers;
  final int records;
  final List<SystemUsagePoint> system;

  factory AdminDashboardStats.fromJson(dynamic v) {
    final m = _m(v);
    return AdminDashboardStats(
      users: _i(m['users']),
      teams: _i(m['teams']),
      servers: _i(m['servers']),
      records: _i(m['records']),
      system: _l(m['system']).map(SystemUsagePoint.fromJson).toList(),
    );
  }
}

class AdminSettings {
  AdminSettings({
    required this.map,
  });

  final Map<String, dynamic> map;

  factory AdminSettings.fromJson(dynamic v) => AdminSettings(map: _m(v));

  bool get debug => _b(map['debug']);
  String get title => _s(map['title']) ?? '';
  String get favicon => _s(map['favicon']) ?? '';
  String get domain => _s(map['domain']) ?? '';
  String get emailProvider => _s(map['email_provider']) ?? 'smtp';
  String get smtpHost => _s(map['smtp_host']) ?? '';
  int get smtpPort => _i(map['smtp_port']);
  String get smtpUsername => _s(map['smtp_username']) ?? '';
  String get smtpPassword => _s(map['smtp_password']) ?? '';
  bool get smtpTls => _b(map['smtp_tls']);
  bool get trustProxy => _b(map['trust_proxy']);
  bool get sessionBindIp => _b(map['session_bind_ip']);
  bool get emailVerifyLogin => _b(map['email_verify_login']);
  bool get registrationEnabled => _b(map['registration_enabled']);
  bool get registrationVerifyEmail => _b(map['registration_verify_email']);
  String get captchaSiteKey => _s(map['captcha_site_key']) ?? '';
  String get captchaSecretKey => _s(map['captcha_secret_key']) ?? '';
}

class OAuthProvider {
  OAuthProvider({
    required this.id,
    required this.name,
    required this.icon,
    required this.protocol,
    required this.issuerUrl,
    required this.authUrl,
    required this.tokenUrl,
    required this.userinfoUrl,
    required this.scopes,
    required this.subjectField,
    required this.clientId,
    required this.clientSecret,
    required this.skip2fa,
    required this.isEnabled,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String name;
  final String icon;
  final String protocol; // oauth2 | oidc
  final String issuerUrl;
  final String authUrl;
  final String tokenUrl;
  final String userinfoUrl;
  final String scopes;
  final String subjectField;
  final String clientId;
  final String clientSecret;
  final bool skip2fa;
  final bool isEnabled;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory OAuthProvider.fromJson(dynamic v) {
    final m = _m(v);
    return OAuthProvider(
      id: _i(m['id']),
      name: _s(m['name']) ?? '',
      icon: _s(m['icon']) ?? '',
      protocol: _s(m['protocol']) ?? 'oauth2',
      issuerUrl: _s(m['issuer_url']) ?? '',
      authUrl: _s(m['auth_url']) ?? '',
      tokenUrl: _s(m['token_url']) ?? '',
      userinfoUrl: _s(m['userinfo_url']) ?? '',
      scopes: _s(m['scopes']) ?? '',
      subjectField: _s(m['subject_field']) ?? '',
      clientId: _s(m['client_id']) ?? '',
      clientSecret: _s(m['client_secret']) ?? '',
      skip2fa: _b(m['skip_2fa']),
      isEnabled: _b(m['is_enabled']),
      createdAt: _t(m['created_at']),
      updatedAt: _t(m['updated_at']),
    );
  }

  Map<String, dynamic> toFormJson() => {
        'name': name,
        'icon': icon,
        'protocol': protocol,
        'issuer_url': issuerUrl,
        'auth_url': authUrl,
        'token_url': tokenUrl,
        'userinfo_url': userinfoUrl,
        'scopes': scopes,
        'subject_field': subjectField,
        'client_id': clientId,
        'client_secret': clientSecret,
        'skip_2fa': skip2fa ? 'true' : 'false',
        'is_enabled': isEnabled ? 'true' : 'false',
      };
}

class UsersPage {
  UsersPage({required this.users, required this.total});

  final List<User> users;
  final int total;

  factory UsersPage.fromJson(dynamic v) {
    final m = _m(v);
    return UsersPage(
      users: _l(m['users']).map(User.fromJson).toList(),
      total: _i(m['total']),
    );
  }
}

class OAuthProvidersPage {
  OAuthProvidersPage({required this.items, required this.total});

  final List<OAuthProvider> items;
  final int total;

  factory OAuthProvidersPage.fromJson(dynamic v) {
    final m = _m(v);
    return OAuthProvidersPage(
      items: _l(m['items']).map(OAuthProvider.fromJson).toList(),
      total: _i(m['total']),
    );
  }
}

/// Export file: {"format":"mosona-team-export-v1","kdf":..,"salt":..,"nonce":..,"ciphertext":..}
class EncryptedExportFile {
  EncryptedExportFile({required this.map});

  final Map<String, dynamic> map;

  String get format => _s(map['format']) ?? '';
}
