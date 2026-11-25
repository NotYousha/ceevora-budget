import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env.dart';
import '../security/session.dart';
import 'in_browser_backend.dart';

/// Standardised API error: `{"error": {"code": ..., "message": ...}}`.
class ApiException implements Exception {
  final int status;
  final String code;
  final String message;
  ApiException(this.status, this.code, this.message);
  @override
  String toString() => message;
}

class ApiClient {
  final Dio dio;
  ApiClient(this.dio);

  static ApiException _map(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['error'] is Map) {
      final err = data['error'] as Map;
      return ApiException(
        e.response!.statusCode ?? 0,
        '${err['code']}',
        '${err['message']}',
      );
    }
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      return ApiException(
        0,
        'OFFLINE',
        'Cannot reach the budget server (${Env.apiBaseUrl}).',
      );
    }
    return ApiException(
      e.response?.statusCode ?? 0,
      'HTTP_ERROR',
      e.message ?? 'Request failed',
    );
  }

  Future<T> _call<T>(Future<Response<dynamic>> Function() f) async {
    try {
      return (await f()).data as T;
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<T> get<T>(String path, [Map<String, dynamic>? query]) => _call(
    () => dio.get(
      path,
      queryParameters: query?..removeWhere((_, v) => v == null),
    ),
  );

  Future<T> post<T>(String path, Object? body, {String? idempotencyKey}) =>
      _call(
        () => dio.post(
          path,
          data: body,
          options: Options(headers: {'Idempotency-Key': ?idempotencyKey}),
        ),
      );

  Future<T> put<T>(String path, Object? body) =>
      _call(() => dio.put(path, data: body));
}

final apiProvider = Provider<ApiClient>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: Env.apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60),
      contentType: 'application/json',
    ),
  );
  final inBrowser = browserAdapter();
  if (inBrowser != null) dio.httpClientAdapter = inBrowser;
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (o, h) {
        final s = ref.read(sessionProvider);
        if (s != null) o.headers['Authorization'] = 'Bearer ${s.token}';
        h.next(o);
      },
      onError: (e, h) {
        // Expired/invalid token: drop the session; the router redirects to sign-in.
        if (e.response?.statusCode == 401 &&
            ref.read(sessionProvider) != null) {
          ref.read(sessionProvider.notifier).signOut(becauseExpired: true);
        }
        h.next(e);
      },
    ),
  );
  return ApiClient(dio);
});
