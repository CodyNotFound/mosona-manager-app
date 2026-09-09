import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../state/controllers.dart';

/// Fixed User-Agent: the backend binds sessions to the exact User-Agent that
/// was used at login, so it must stay stable for HTTP *and* WebSocket calls.
const kUserAgent = 'MosonaManagerApp/1.0.0 (Flutter; +https://manager.mosona.cc)';

/// Unified API envelope: `{"code": "...", "msg": "...", "data": ...}`.
class Envelope {
  Envelope({required this.code, required this.msg, this.data, this.extras = const {}});

  final String code;
  final String msg;
  final dynamic data;

  /// Extra top-level fields (e.g. team export's skipped_servers).
  final Map<String, dynamic> extras;

  bool get isOk => code == 'ok';

  T? as<T>() => data is T ? data as T : null;
}

/// Exception carrying the backend `code` so callers can branch on
/// `2fa_required`, `verify`, `login`, `ssh_host_key_confirmation_required`, ...
class ApiException implements Exception {
  ApiException(this.code, this.msg, {this.httpStatus, this.data});

  final String code;
  final String msg;
  final int? httpStatus;
  final dynamic data;

  bool get isNetwork => code == 'network';

  @override
  String toString() => 'ApiException($httpStatus $code): $msg';
}

/// Session cookie persistence keyed by host, backed by SharedPreferences.
class CookieStore {
  CookieStore(this._prefs);

  final SharedPreferences _prefs;

  String _key(String host) => 'mosona-app-cookie:${host.toLowerCase()}';

  String? get(String host) => _prefs.getString(_key(host));

  void put(String host, String value) => _prefs.setString(_key(host), value);

  void clear(String host) => _prefs.remove(_key(host));

  /// Builds a `Cookie:` header value for websocket / manual requests.
  String? headerFor(Uri uri) {
    final v = get(uri.host);
    return v == null ? null : 'session=$v';
  }
}

String formEncode(Map<String, dynamic> fields) {
  final parts = <String>[];
  fields.forEach((k, v) {
    if (v == null) return;
    final s = v is bool ? (v ? 'true' : 'false') : v.toString();
    parts.add('${Uri.encodeQueryComponent(k)}=${Uri.encodeQueryComponent(s)}');
  });
  return parts.join('&');
}

class ApiClient {
  ApiClient({required this.baseUrl, required this.cookies});

  final String baseUrl;
  final CookieStore cookies;
  late final Dio _dio = _build();

  Dio _build() {
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'user-agent': kUserAgent,
        'accept': 'application/json, text/plain, */*',
      },
      validateStatus: (_) => true, // we inspect status + envelope ourselves
    ));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final host = options.uri.host;
        final session = cookies.get(host);
        if (session != null) {
          options.headers['cookie'] = 'session=$session';
        }
        handler.next(options);
      },
      onResponse: (response, handler) {
        _captureSession(response);
        handler.next(response);
      },
    ));
    return dio;
  }

  void _captureSession(Response response) {
    String? raw;
    final sc = response.headers.map['set-cookie'];
    if (sc != null && sc.isNotEmpty) {
      for (final line in sc) {
        if (line.startsWith('session=')) {
          raw = line.split(';').first.trim();
          break;
        }
      }
    }
    if (raw != null) {
      final value = raw.substring('session='.length);
      if (value.isNotEmpty) {
        cookies.put(response.requestOptions.uri.host, value);
      } else {
        cookies.clear(response.requestOptions.uri.host);
      }
    }
  }

  Uri uri(String path, [Map<String, dynamic>? query]) {
    final q = formEncode(query ?? <String, dynamic>{});
    return Uri.parse('$baseUrl$path${q.isEmpty ? '' : '?$q'}');
  }

  /// WebSocket URL for a path under the current base URL.
  Uri wsUri(String path) {
    final http = uri(path);
    return http.replace(
      scheme: http.scheme == 'https' ? 'wss' : 'ws',
    );
  }

  Future<Envelope> request(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Map<String, dynamic>? form,
    Object? json,
  }) async {
    assert((form == null) != (json == null) || (form == null && json == null),
        'pass either form or json, not both');
    try {
      final res = await _dio.fetch(RequestOptions(
        method: method,
        baseUrl: baseUrl,
        path: path,
        queryParameters: query?.
            map((k, v) => MapEntry(k, v is bool ? v.toString() : v)),
        data: form != null ? formEncode(form) : json,
        headers: {
          'user-agent': kUserAgent,
          if (form != null) 'content-type': 'application/x-www-form-urlencoded',
          if (json != null) 'content-type': 'application/json',
        },
        responseType: ResponseType.json,
        validateStatus: (_) => true,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
      ));
      return _parse(res);
    } on DioException catch (e) {
      throw ApiException('network', e.message ?? 'Connection error');
    }
  }

  Envelope _parse(Response res) => parseResponse(res);

  /// Public response parser (also used for multipart requests).
  Envelope parseResponse(Response res) {
    dynamic body;
    final data = res.data;
    if (data is String) {
      try {
        body = jsonDecode(data);
      } catch (_) {
        body = null;
      }
    } else {
      body = data;
    }
    if (body is Map<String, dynamic> && body['code'] is String) {
      final extras = <String, dynamic>{};
      body.forEach((k, v) {
        if (k != 'code' && k != 'msg' && k != 'data' && k != 'version') extras[k] = v;
      });
      return Envelope(
        code: body['code'] as String,
        msg: (body['msg'] ?? '') as String,
        // /api/v1/version returns {"code","version"} without a data field.
        data: body['data'] ?? body['version'],
        extras: extras,
      );
    }
    throw ApiException(
      'network',
      'HTTP ${res.statusCode}: unexpected response',
      httpStatus: res.statusCode,
    );
  }

  /// Plain-text GET (used by /api/ping); a 5xx/404 body is an error, not pong.
  Future<String> getText(String path) async {
    try {
      final res = await _dio.get<String>(path,
          options: Options(responseType: ResponseType.plain));
      if (res.statusCode != 200) {
        throw ApiException('error', 'HTTP ${res.statusCode}',
            httpStatus: res.statusCode);
      }
      return res.data ?? '';
    } on DioException catch (e) {
      throw ApiException('network', e.message ?? 'Connection error');
    }
  }

  /// Raw streaming GET (used by the SSE client).
  Dio get dio => _dio;

  void dispose() => _dio.close();
}

/// Codes that should bubble up untouched so pages can react (navigate to
/// /2fa, show email-code dialog, force re-login, ...).
const kPassthroughCodes = {
  '2fa_required',
  'verify',
  'login',
  'init_required',
  'team_access_revoked',
  'team_required',
  'no_admin',
  'ssh_host_key_confirmation_required',
  'ssh_host_key_state_changed',
  'legacy_ssh_host_key_confirmation_required',
  'unreadable_server_credential',
  'unreadable_key_credential',
  'agent_uid_conflict',
  'cooling',
  'rate_limited',
};

final apiClientProvider = Provider<ApiClient>((ref) {
  final base = ref.watch(serverConfigProvider);
  final prefs = ref.watch(sharedPrefsProvider);
  final client = ApiClient(baseUrl: base, cookies: CookieStore(prefs));
  ref.onDispose(client.dispose);
  return client;
});
