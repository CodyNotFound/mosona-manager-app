import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import 'api_client.dart';

/// Typed API services for every backend endpoint group.
/// Encoding rules follow the backend exactly (see docs/backend-api-spec.md):
/// most writes are form-urlencoded; JSON/multipart where noted.
class ApiServices {
  ApiServices(this.c);

  final ApiClient c;

  Future<T> _ok<T>(FutureOr<Envelope> f, T Function(dynamic) parse) async {
    final e = await f;
    if (e.isOk) return parse(e.data);
    throw ApiException(e.code, e.msg, data: e.data);
  }

  // ---------------------------------------------------------------- auth

  Future<Envelope> login(String email, String password,
          {bool rememberMe = false, String? otp}) =>
      c.request(
        'POST',
        '/api/auth/login',
        form: {
          'email': email,
          'password': password,
          'remember_me': rememberMe,
          if (otp != null && otp.isNotEmpty) 'otp': otp,
        },
      );

  Future<void> register(String username, String email, String password, {String? token}) => _ok(
        c.request('POST', '/api/auth/register', form: {
          'username': username,
          'email': email,
          'password': password,
          'token': token ?? '',
        }),
        (_) {},
      );

  Future<void> logout() async {
    // Local cookie must go even if the server call fails (offline logout):
    // otherwise the next cold start silently resurrects the session.
    try {
      await c.request('POST', '/api/auth/logout', form: {});
    } finally {
      c.cookies.clearHost(Uri.parse(c.baseUrl).host);
    }
  }

  Future<AuthKeys> authKeys() => _ok(
        c.request('GET', '/api/auth/keys'),
        AuthKeys.fromJson,
      );

  /// Returns the OAuth authorize URL + state.
  Future<({String url, String state})> oauthLogin(int id) => _ok(
        c.request('GET', '/api/auth/oauth/$id'),
        (d) {
          final m = d is Map<String, dynamic> ? d : <String, dynamic>{};
          return (url: m['url'].toString(), state: m['state'].toString());
        },
      );

  Future<void> oauthCallback(int id, String code, String state) => _ok(
        c.request('POST', '/api/auth/oauth/$id', form: {'code': code, 'state': state}),
        (_) {},
      );

  Future<TwoFaStatus> twoFaStatus() => _ok(
        c.request('GET', '/api/auth/2fa/status'),
        TwoFaStatus.fromJson,
      );

  Future<void> twoFaSendCode(String mode) =>
      _ok(c.request('POST', '/api/auth/2fa/send_code', form: {'mode': mode}), (_) {});

  Future<void> twoFaVerifyCode(String code) =>
      _ok(c.request('POST', '/api/auth/2fa/verify_code', form: {'code': code}), (_) {});

  Future<void> twoFaVerifyTotp(String code) =>
      _ok(c.request('POST', '/api/auth/2fa/verify_totp', form: {'code': code}), (_) {});

  // ---------------------------------------------------------------- user

  Future<({User user, Team? team, List<Team> teams})> me() => _ok(
        c.request('GET', '/api/v1/user/me'),
        (d) {
          final m = d is Map<String, dynamic> ? d : <String, dynamic>{};
          return (
            user: User.fromJson(m['user']),
            team: m['team'] == null ? null : Team.fromJson(m['team']),
            teams: (m['teams'] as List? ?? []).map(Team.fromJson).toList(),
          );
        },
      );

  Future<User?> findUser(String email) async {
    final e = await c.request('POST', '/api/v1/user/find', form: {'email': email});
    if (!e.isOk) throw ApiException(e.code, e.msg, data: e.data);
    if (e.data == null) return null;
    return User.fromJson(e.data);
  }

  Future<void> changeUsername(String username) => _ok(
        c.request('PUT', '/api/v1/user/edit/username', form: {'username': username}),
        (_) {},
      );

  Future<void> setActiveTeam(int teamId) => _ok(
        c.request('POST', '/api/v1/user/config/active-team/$teamId', form: {}),
        (_) {},
      );

  Future<({String current, List<UserSession> list})> sessions() => _ok(
        c.request('GET', '/api/v1/user/sessions'),
        (d) {
          final m = d is Map<String, dynamic> ? d : <String, dynamic>{};
          return (
            current: m['current'].toString(),
            list: (m['list'] as List? ?? []).map(UserSession.fromJson).toList(),
          );
        },
      );

  Future<void> revokeSession(String sid) =>
      _ok(c.request('DELETE', '/api/v1/user/sessions/$sid'), (_) {});

  Future<void> revokeAllSessions() =>
      _ok(c.request('DELETE', '/api/v1/user/sessions'), (_) {});

  Future<List<AuthIdentity>> oauthIdentities() => _ok(
        c.request('GET', '/api/v1/user/oauth'),
        (d) => (d as List? ?? []).map(AuthIdentity.fromJson).toList(),
      );

  Future<void> revokeOAuthIdentity(int providerId) =>
      _ok(c.request('DELETE', '/api/v1/user/oauth/$providerId'), (_) {});

  Future<void> linkOAuthIdentity(int id, String code, String state) => _ok(
        c.request('POST', '/api/v1/user/oauth/$id', form: {'code': code, 'state': state}),
        (_) {},
      );

  Future<({String secret, String url})> totpEnable() => _ok(
        c.request('POST', '/api/v1/user/totp/enable', form: {}),
        (d) {
          final m = d is Map<String, dynamic> ? d : <String, dynamic>{};
          return (secret: m['secret'].toString(), url: m['url'].toString());
        },
      );

  Future<void> totpConfirm(String secret, String code) => _ok(
        c.request('POST', '/api/v1/user/totp/confirm', form: {'secret': secret, 'code': code}),
        (_) {},
      );

  Future<void> totpDisable(String vCode) => _ok(
        c.request('POST', '/api/v1/user/totp/disable', form: {'v_code': vCode}),
        (_) {},
      );

  // ---------------------------------------------------------------- team

  Future<({Team team, List<TeamMember> members})> teamInfo() => _ok(
        c.request('GET', '/api/v1/team'),
        (d) {
          final m = d is Map<String, dynamic> ? d : <String, dynamic>{};
          return (
            team: Team.fromJson(m['team']),
            members: (m['members'] as List? ?? []).map(TeamMember.fromJson).toList(),
          );
        },
      );

  Future<int> createTeam({
    required String name,
    required String description,
    required String avatarColor,
    required List<({int id, int role})> members,
    List<int>? avatarImage,
  }) async {
    final membersJson = jsonEncode([
      for (final m in members) {'id': m.id, 'role': m.role},
    ]);
    final e = await _multipart(
      'POST',
      '/api/v1/team',
      {
        'name': name,
        'description': description,
        'avatar_color': avatarColor,
        'members': membersJson,
      },
      avatarImage,
      'avatar_image',
    );
    return _ok(e, (d) => d is num ? d.toInt() : int.tryParse(d.toString()) ?? 0);
  }

  Future<void> editTeam({
    required int id,
    required String name,
    required String description,
    required String avatarColor,
    required List<({int id, int role})> members,
    List<int>? avatarImage,
  }) async {
    final membersJson = jsonEncode([
      for (final m in members) {'id': m.id, 'role': m.role},
    ]);
    await _multipart(
      'PUT',
      '/api/v1/team/$id',
      {
        'name': name,
        'description': description,
        'avatar_color': avatarColor,
        'members': membersJson,
      },
      avatarImage,
      'avatar_image',
    );
  }

  Future<Envelope> _multipart(
    String method,
    String path,
    Map<String, String> fields,
    List<int>? fileBytes,
    String fileField,
  ) async {
    final formMap = <String, dynamic>{...fields};
    if (fileBytes != null) {
      formMap[fileField] = MultipartFile.fromBytes(
        fileBytes,
        filename: '$fileField.avif',
      );
    }
    try {
      final res = await c.dio.fetch(RequestOptions(
        method: method,
        baseUrl: c.baseUrl,
        path: path,
        data: FormData.fromMap(formMap),
        headers: {'user-agent': kUserAgent},
        responseType: ResponseType.json,
        validateStatus: (_) => true,
      ));
      return c.parseResponse(res);
    } on DioException catch (e) {
      throw ApiException('network', e.message ?? 'Connection error');
    }
  }

  Future<void> leaveTeam(int teamId) =>
      _ok(c.request('DELETE', '/api/v1/team/leave/$teamId'), (_) {});

  Future<PublicPageConfig> getPublicPage() => _ok(
        c.request('GET', '/api/v1/team/public-page'),
        PublicPageConfig.fromJson,
      );

  Future<void> updatePublicPage(PublicPageConfig cfg) => _ok(
        c.request('PUT', '/api/v1/team/public-page', json: cfg.toUpdateJson()),
        (_) {},
      );

  Future<Envelope> exportTeam({
    required String totpCode,
    required String exportPassword,
    bool skipUnreadableServers = false,
  }) =>
      c.request('POST', '/api/v1/team/export', json: {
        'totp_code': totpCode,
        'export_password': exportPassword,
        'skip_unreadable_servers': skipUnreadableServers,
      });

  Future<Envelope> importTeam({
    required String totpCode,
    String? exportPassword,
    Map<String, dynamic>? encrypted,
    dynamic data,
    bool trustLegacySshHostKeys = false,
  }) =>
      c.request('POST', '/api/v1/team/import', json: {
        'totp_code': totpCode,
        'export_password': ?exportPassword,
        'encrypted': ?encrypted,
        'data': ?data,
        'trust_legacy_ssh_host_keys': trustLegacySshHostKeys,
      });

  Future<List<NotificationTarget>> notificationList() => _ok(
        c.request('GET', '/api/v1/team/notification'),
        (d) => (d as List? ?? []).map(NotificationTarget.fromJson).toList(),
      );

  Future<void> notificationUpdate(List<NotificationTarget> targets) => _ok(
        c.request(
          'PUT',
          '/api/v1/team/notification',
          json: [for (final t in targets) t.toJson()],
        ),
        (_) {},
      );

  Future<void> notificationValidate(NotificationTarget t) =>
      _ok(c.request('POST', '/api/v1/team/notification/validate', json: t.toJson()), (_) {});

  Future<void> notificationTest(String uri) =>
      _ok(c.request('POST', '/api/v1/team/notification/test', json: {'uri': uri}), (_) {});

  // ---------------------------------------------------------------- keys

  Future<List<SshKey>> keyList() => _ok(
        c.request('GET', '/api/v1/key'),
        (d) => (d as List? ?? []).map(SshKey.fromJson).toList(),
      );

  Future<void> keyAdd(String name, String content, String? password) => _ok(
        c.request('POST', '/api/v1/key', form: {
          'name': name,
          'content': content,
          'password': password ?? '',
        }),
        (_) {},
      );

  Future<void> keyEdit(int id, String name, String? password) => _ok(
        c.request('PUT', '/api/v1/key/$id', form: {'name': name, 'password': password ?? ''}),
        (_) {},
      );

  Future<void> keyDelete(int id) => _ok(c.request('DELETE', '/api/v1/key/$id'), (_) {});

  // ---------------------------------------------------------------- category

  Future<List<Category>> categoryList() => _ok(
        c.request('GET', '/api/v1/category'),
        (d) => (d as List? ?? []).map(Category.fromJson).toList(),
      );

  Future<void> categoryCreate(String name) =>
      _ok(c.request('POST', '/api/v1/category', form: {'name': name}), (_) {});

  Future<void> categoryUpdate(int id, String name) =>
      _ok(c.request('PUT', '/api/v1/category/$id', form: {'name': name}), (_) {});

  Future<void> categoryDelete(int id) =>
      _ok(c.request('DELETE', '/api/v1/category/$id'), (_) {});

  Future<void> categorySort(List<int> ids) =>
      _ok(c.request('PUT', '/api/v1/category/sort', json: ids), (_) {});

  // ---------------------------------------------------------------- server

  Future<ServerFull> serverInfo(int id) =>
      _ok(c.request('GET', '/api/v1/server/$id'), ServerFull.fromJson);

  Future<Envelope> serverAdd(Map<String, dynamic> form) =>
      c.request('POST', '/api/v1/server', form: form);

  Future<void> serverEdit(int id, Map<String, dynamic> json) =>
      _ok(c.request('PUT', '/api/v1/server/$id', json: json), (_) {});

  Future<void> serverDelete(int id) =>
      _ok(c.request('DELETE', '/api/v1/server/$id'), (_) {});

  Future<Envelope> serverReinstall(int id, {required int mode, String? address, int? port}) =>
      c.request('POST', '/api/v1/server/$id/reinstall', form: {
        'mode': mode,
        'address': ?address,
        'port': ?port,
      });

  Future<void> serverSetCategory(int serverId, int categoryId) => _ok(
        c.request('PUT', '/api/v1/server/$serverId/category', form: {'category_id': categoryId}),
        (_) {},
      );

  // ---------------------------------------------------------------- monitor

  Future<MonitorSnapshot> monitorList() => _ok(
        c.request('GET', '/api/v1/server/monitor'),
        MonitorSnapshot.fromJson,
      );

  Future<MonitorInfoResult> monitorInfo(int id) => _ok(
        c.request('GET', '/api/v1/server/monitor/$id'),
        MonitorInfoResult.fromJson,
      );

  Future<List<ServerStatus>> monitorChart(int id, String timeFrame) => _ok(
        c.request('GET', '/api/v1/server/monitor/$id/chart', query: {'time_frame': timeFrame}),
        (d) => (d as List? ?? []).map(ServerStatus.fromJson).toList(),
      );

  Future<ServerStatus> monitorRealtime(int id) => _ok(
        c.request('GET', '/api/v1/server/monitor/$id/realtime'),
        ServerStatus.fromJson,
      );

  // ---------------------------------------------------------------- terminal

  Future<List<TerminalServer>> terminalList() => _ok(
        c.request('GET', '/api/v1/server/terminal'),
        (d) => (d as List? ?? []).map(TerminalServer.fromJson).toList(),
      );

  // ---------------------------------------------------------------- alerts

  Future<AlertsData> alertsList() =>
      _ok(c.request('GET', '/api/v1/alert'), AlertsData.fromJson);

  /// Returns the number of affected servers (web parity toast).
  Future<int> alertSet(int serverId, String item, int threshold, int forDuration,
          {bool override = false}) =>
      _ok(
        c.request('PUT', '/api/v1/alert/$serverId', form: {
          'item': item,
          'threshold': threshold,
          'for_duration': forDuration,
          'override': override,
        }),
        (d) => d is num ? d.toInt() : int.tryParse(d.toString()) ?? 0,
      );

  Future<int> alertDelete(String item, int serverId, {bool override = false}) => _ok(
        c.request('DELETE', '/api/v1/alert/$item/$serverId',
            query: {'override': override}),
        (d) => d is num ? d.toInt() : int.tryParse(d.toString()) ?? 0,
      );

  // ---------------------------------------------------------------- logs

  Future<LogsPage> logsList({
    String? cursor,
    required int pageSize,
    String category = 'all',
    String level = 'all',
    String? email,
    String? message,
    DateTime? start,
    DateTime? end,
    bool admin = false,
  }) =>
      _ok(
        c.request(
          'GET',
          admin ? '/api/admin/logs' : '/api/v1/logs',
          query: {
            'page_size': pageSize,
            if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
            'category': category,
            'level': level,
            if (email != null && email.isNotEmpty) 'email': email,
            if (message != null && message.isNotEmpty) 'message': message,
            if (start != null) 'start': start.toUtc().toIso8601String(),
            if (end != null) 'end': end.toUtc().toIso8601String(),
          },
        ),
        LogsPage.fromJson,
      );

  // ---------------------------------------------------------------- misc

  Future<bool> initStatus() => _ok(c.request('GET', '/api/init'), (d) => d == true);

  Future<void> initSetup({
    required String username,
    required String email,
    required String password,
    required String websiteUrl,
    required bool registrationEnable,
  }) =>
      _ok(
        c.request('POST', '/api/init', form: {
          'username': username,
          'email': email,
          'password': password,
          'website_url': websiteUrl,
          'registration_enable': registrationEnable,
        }),
        (_) {},
      );

  Future<String> version() => _ok(
        c.request('GET', '/api/v1/version'),
        (d) => d.toString(),
      );

  Future<String> ping() => c.getText('/api/ping');

  // ---------------------------------------------------------------- admin

  Future<AdminDashboardStats> adminDashboard() => _ok(
        c.request('GET', '/api/admin/dashboard'),
        AdminDashboardStats.fromJson,
      );

  Future<UsersPage> adminUsersList({
    required int page,
    required int size,
    String? search,
    String verify = 'all',
  }) =>
      _ok(
        c.request('GET', '/api/admin/users/list', query: {
          'page': page,
          'size': size,
          if (search != null && search.isNotEmpty) 'search': search,
          'verify': verify,
        }),
        UsersPage.fromJson,
      );

  Future<void> adminUserAdd({
    required String username,
    required String email,
    required String password,
    bool verified = false,
    bool admin = false,
  }) =>
      _ok(
        c.request('POST', '/api/admin/users', form: {
          'username': username,
          'email': email,
          'password': password,
          'verified': verified,
          'is_admin': admin,
        }),
        (_) {},
      );

  Future<void> adminUserUpdate({
    required int id,
    required String username,
    required String email,
    String? password,
    bool? verified,
    bool? admin,
    String? currentPassword,
  }) =>
      _ok(
        c.request('PUT', '/api/admin/users/$id', form: {
          'username': username,
          'email': email,
          if (password != null && password.isNotEmpty) 'password': password,
          'verified': ?verified,
          'admin': ?admin,
          if (currentPassword != null && currentPassword.isNotEmpty)
            'current_password': currentPassword,
        }),
        (_) {},
      );

  Future<Envelope> adminUserDelete(int id, {required String confirm, String? currentPassword}) =>
      c.request('DELETE', '/api/admin/users/$id',
          query: {'confirm': confirm},
          form: {'current_password': currentPassword ?? ''});

  Future<AdminSettings> adminSettingsGet() => _ok(
        c.request('GET', '/api/admin/settings'),
        AdminSettings.fromJson,
      );

  Future<void> adminSettingsSet(List<({String key, String value})> entries) => _ok(
        c.request(
          'POST',
          '/api/admin/settings',
          json: [
            for (final e in entries) {'key': e.key, 'value': e.value},
          ],
        ),
        (_) {},
      );

  Future<void> adminFaviconUpload(List<int> bytes) async {
    final e = await _multipart(
        'POST', '/api/admin/settings/favicon', <String, String>{}, bytes, 'image');
    _ok(e, (_) {});
  }

  Future<void> adminTestEmail() =>
      _ok(c.request('POST', '/api/admin/settings/test/email', json: {}), (_) {});

  Future<OAuthProvidersPage> adminOAuthList({int page = 1, int size = 20}) => _ok(
        c.request('GET', '/api/admin/oauth', query: {'page': page, 'size': size}),
        OAuthProvidersPage.fromJson,
      );

  Future<void> adminOAuthAdd(Map<String, dynamic> form) =>
      _ok(c.request('POST', '/api/admin/oauth', form: form), (_) {});

  Future<void> adminOAuthUpdate(int id, Map<String, dynamic> form) =>
      _ok(c.request('PUT', '/api/admin/oauth/$id', form: form), (_) {});

  Future<void> adminOAuthDelete(int id) =>
      _ok(c.request('DELETE', '/api/admin/oauth/$id'), (_) {});

  Future<void> adminOAuthSort(List<int> ids) =>
      _ok(c.request('POST', '/api/admin/oauth/sort', json: ids), (_) {});

  // ---------------------------------------------------------------- public preview

  Future<dynamic> publicBootstrap({String? name}) => c
      .request('GET',
          name == null ? '/api/public/preview/bootstrap' : '/api/public/preview/$name/bootstrap')
      .then((e) {
    if (e.isOk) return e.data;
    throw ApiException(e.code, e.msg, data: e.data);
  });
}

final apiProvider = Provider<ApiServices>((ref) {
  return ApiServices(ref.watch(apiClientProvider));
});
