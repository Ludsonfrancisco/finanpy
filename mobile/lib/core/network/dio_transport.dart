import 'package:dio/dio.dart';

import 'api_error.dart';

final class ApiResponse {
  const ApiResponse({required this.statusCode, required this.data});

  final int statusCode;
  final Object? data;

  bool get isSuccessful => statusCode >= 200 && statusCode < 300;

  @override
  String toString() => 'ApiResponse(statusCode: $statusCode, data: <redacted>)';
}

abstract interface class ApiTransport {
  Future<ApiResponse> request(
    String path, {
    required String method,
    Object? data,
    String? bearerToken,
  });
}

final class DioTransport implements ApiTransport {
  DioTransport({required String baseUrl, Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 10),
              sendTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 15),
              headers: const <String, String>{'Accept': 'application/json'},
              validateStatus: (status) => status != null,
            ),
          );

  final Dio _dio;

  @override
  Future<ApiResponse> request(
    String path, {
    required String method,
    Object? data,
    String? bearerToken,
  }) async {
    try {
      final response = await _dio.request<Object?>(
        path,
        data: data,
        options: Options(
          method: method,
          headers: bearerToken == null
              ? null
              : <String, String>{'Authorization': 'Bearer $bearerToken'},
        ),
      );
      return ApiResponse(statusCode: response.statusCode!, data: response.data);
    } on DioException catch (error) {
      if (_isOffline(error.type)) {
        throw const OfflineFailure();
      }
      throw const RequestFailure();
    }
  }

  bool _isOffline(DioExceptionType type) =>
      type == DioExceptionType.connectionTimeout ||
      type == DioExceptionType.sendTimeout ||
      type == DioExceptionType.receiveTimeout ||
      type == DioExceptionType.connectionError;
}
