import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosona_manager/core/api/api_client.dart';

void main() {
  group('formEncode', () {
    test('encodes fields url-safe', () {
      final s = formEncode({
        'email': 'a b@example.com',
        'password': 'p@ss&word=1',
        'remember_me': true,
        'note': null,
      });
      // form-urlencoded rules: space becomes '+'
      expect(s,
          'email=a+b%40example.com&password=p%40ss%26word%3D1&remember_me=true');
    });

    test('empty map', () {
      expect(formEncode({}), '');
    });
  });

  group('ApiClient.parseResponse', () {
    ApiClient build() => ApiClient(baseUrl: 'https://x.example', cookies: _NoopStore());

    Response res(dynamic data, {int status = 200}) => Response(
          data: data,
          statusCode: status,
          requestOptions: RequestOptions(path: '/api/x'),
        );

    test('ok envelope with data', () {
      final e = build().parseResponse(res({
        'code': 'ok',
        'msg': 'Login success',
        'data': {'id': 1},
      }));
      expect(e.isOk, isTrue);
      expect((e.data as Map)['id'], 1);
    });

    test('error envelope carries code', () {
      final e = build().parseResponse(res({
        'code': '2fa_required',
        'msg': 'Two-factor authentication required',
      }, status: 200));
      expect(e.code, '2fa_required');
      expect(e.isOk, isFalse);
    });

    test('version envelope special case', () {
      final e = build().parseResponse(res({'code': 'ok', 'version': '0.1.16'}));
      expect(e.isOk, isTrue);
      expect(e.data, '0.1.16');
    });

    test('team export extras captured', () {
      final e = build().parseResponse(res({
        'code': 'ok',
        'msg': 'ok',
        'data': {'format': 'mosona-team-export-v1'},
        'skipped_servers': [
          {'server_id': 2, 'server_name': 'nas'}
        ],
      }));
      expect(e.extras.containsKey('skipped_servers'), isTrue);
      expect((e.extras['skipped_servers'] as List).first['server_name'], 'nas');
    });

    test('non-json body throws network ApiException', () {
      expect(
        () => build().parseResponse(res('<html>bad gateway</html>', status: 502)),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('wsUri', () {
    test('scheme upgrade', () {
      final c = ApiClient(baseUrl: 'https://manager.example.com', cookies: _NoopStore());
      final ws = c.wsUri('/api/v1/server/terminal/1/ws');
      expect(ws.scheme, 'wss');
      expect(ws.path, '/api/v1/server/terminal/1/ws');
      final c2 = ApiClient(baseUrl: 'http://127.0.0.1:3214', cookies: _NoopStore());
      expect(c2.wsUri('/x').scheme, 'ws');
      expect(c2.wsUri('/x').port, 3214);
    });
  });
}

class _NoopStore implements CookieStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
