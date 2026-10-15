import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unpause/services/supabase_management_service.dart';

class _JsonAdapter implements HttpClientAdapter {
  _JsonAdapter(this.handler);

  ResponseBody Function(RequestOptions options) handler;
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('SupabaseManagementService', () {
    test('lists projects and sends the bearer token', () async {
      final adapter = _JsonAdapter(
        (_) => ResponseBody.fromString(
          '[{"ref":"p1","status":"INACTIVE"}]',
          200,
          headers: {
            'content-type': ['application/json'],
          },
        ),
      );
      final dio = Dio(BaseOptions(baseUrl: 'https://api.supabase.com'))
        ..httpClientAdapter = adapter;
      final service = SupabaseManagementService('scoped-token', client: dio);

      final projects = await service.listProjects();

      expect(projects, hasLength(1));
      expect(projects.single.id, 'p1');
      expect(
        adapter.lastRequest?.headers['Authorization'],
        'Bearer scoped-token',
      );
      expect(dio.options.connectTimeout, const Duration(seconds: 15));
      expect(dio.options.receiveTimeout, const Duration(seconds: 30));
    });

    test(
      'surfaces permission guidance and Retry-After for 403 and 429',
      () async {
        final adapter = _JsonAdapter(
          (_) => ResponseBody.fromString(
            '{"message":"forbidden"}',
            403,
            headers: {
              'content-type': ['application/json'],
            },
          ),
        );
        final dio = Dio(BaseOptions(baseUrl: 'https://api.supabase.com'))
          ..httpClientAdapter = adapter;
        final service = SupabaseManagementService('token', client: dio);

        await expectLater(
          service.listProjects(),
          throwsA(
            isA<SupabaseManagementException>()
                .having((error) => error.statusCode, 'statusCode', 403)
                .having(
                  (error) => error.message,
                  'message',
                  contains('Projects (account-wide) Read'),
                ),
          ),
        );

        adapter.handler = (_) => ResponseBody.fromString(
          '{"message":"slow down"}',
          429,
          headers: {
            'content-type': ['application/json'],
            'retry-after': ['7'],
          },
        );
        await expectLater(
          service.listProjects(),
          throwsA(
            isA<SupabaseManagementException>()
                .having((error) => error.statusCode, 'statusCode', 429)
                .having(
                  (error) => error.retryAfter,
                  'retryAfter',
                  const Duration(seconds: 7),
                ),
          ),
        );

        adapter.handler = (_) => ResponseBody.fromString(
          '{"message":"slow down"}',
          429,
          headers: {
            'content-type': ['application/json'],
            'retry-after': [
              HttpDate.format(DateTime.now().add(const Duration(seconds: 20))),
            ],
          },
        );
        await expectLater(
          service.listProjects(),
          throwsA(
            isA<SupabaseManagementException>().having(
              (error) => error.retryAfter,
              'retryAfter',
              isA<Duration>().having(
                (delay) => delay.inSeconds,
                'seconds',
                greaterThan(0),
              ),
            ),
          ),
        );
      },
    );

    test(
      'rejects malformed project rows instead of silently dropping them',
      () async {
        final adapter = _JsonAdapter(
          (_) => ResponseBody.fromString(
            '[{"ref":"p1"},null]',
            200,
            headers: {
              'content-type': ['application/json'],
            },
          ),
        );
        final dio = Dio(BaseOptions(baseUrl: 'https://api.supabase.com'))
          ..httpClientAdapter = adapter;
        final service = SupabaseManagementService('token', client: dio);

        await expectLater(
          service.listProjects(),
          throwsA(
            isA<SupabaseManagementException>().having(
              (error) => error.message,
              'message',
              contains('invalid project data'),
            ),
          ),
        );
      },
    );
  });
}
