import 'package:dio/dio.dart';
import 'package:serenity/core/constants/app_constants.dart';
import 'package:serenity/core/errors/app_exceptions.dart';
import 'package:serenity/services/secure_storage_service.dart';

class ApiClient {
  late final Dio _dio;
  final SecureStorageService _storage;

  ApiClient(this._storage) {
    _dio = Dio(BaseOptions(
      baseUrl:        AppConstants.baseUrl,
      connectTimeout: AppConstants.connectTimeout,
      // FIX: was 30s — too short for the full LLM pipeline which can take ~20s.
      // Now 60s so the blocking /journal endpoint never times out mid-analysis.
      receiveTimeout: AppConstants.receiveTimeout,
      headers: {'Content-Type': 'application/json'},
    ));
    _dio.interceptors.add(_AuthInterceptor(_storage));
  }

  Future<Response<T>> get<T>(String path, {Map<String, dynamic>? query}) =>
      _wrap(() => _dio.get(path, queryParameters: query));

  Future<Response<T>> post<T>(String path, {dynamic data}) =>
      _wrap(() => _dio.post(path, data: data));

  Future<Response<T>> put<T>(String path, {dynamic data}) =>
      _wrap(() => _dio.put(path, data: data));

  Future<Response<T>> patch<T>(String path, {dynamic data}) =>
      _wrap(() => _dio.patch(path, data: data));

  // FIX: added DELETE method — needed for GDPR account deletion endpoint
  Future<Response<T>> delete<T>(String path, {dynamic data}) =>
      _wrap(() => _dio.delete(path, data: data));

  Future<Response<T>> _wrap<T>(Future<Response<T>> Function() fn) async {
    try {
      return await fn();
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  AppException _map(DioException e) {
    switch (e.type) {
      case DioExceptionType.cancel:
        return const UnauthorizedException();
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
        return const NetworkException();
      case DioExceptionType.receiveTimeout:
        // Distinguish timeout from connection error so UI can show a better message
        return const ServerException();
      case DioExceptionType.badResponse:
        final s = e.response?.statusCode;
        final d = e.response?.data?['detail']?.toString() ?? 'An error occurred.';
        if (s == 401) return const UnauthorizedException();
        if (s == 429) return const ValidationException('Too many requests. Please wait a moment.');
        if (s != null && s >= 500) return const ServerException();
        return ValidationException(d);
      default:
        return const NetworkException();
    }
  }
}

class _AuthInterceptor extends Interceptor {
  final SecureStorageService _s;
  _AuthInterceptor(this._s);

  @override
  Future<void> onRequest(RequestOptions o, RequestInterceptorHandler h) async {
    // Skip auth header for public auth endpoints
    if (o.path.contains('/auth/')) return h.next(o);
    final token = await _s.getToken();
    if (token != null && token.isNotEmpty) {
      o.headers['Authorization'] = 'Bearer $token';
      return h.next(o);
    }
    return h.reject(DioException(
      requestOptions: o,
      error: 'No token.',
      type: DioExceptionType.cancel,
    ));
  }
}