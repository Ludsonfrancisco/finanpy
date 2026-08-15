import 'dart:async';

import 'package:dio/dio.dart';

import '../../features/auth/domain/session.dart';
import 'api_error.dart';
import 'dio_transport.dart';

typedef SessionEventSink = void Function(String event);

final class SessionTransport {
  SessionTransport({
    required ApiTransport transport,
    required TokenStore tokenStore,
    SessionAuthority? sessionAuthority,
    SessionEventSink? onEvent,
    DateTime Function()? now,
  }) : _transport = transport,
       _sessionAuthority =
           sessionAuthority ?? SessionAuthority.forStore(tokenStore),
       _onEvent = onEvent,
       _now = now ?? DateTime.now;

  final ApiTransport _transport;
  final SessionAuthority _sessionAuthority;
  final SessionEventSink? _onEvent;
  final DateTime Function() _now;
  Completer<StoredTokens>? _refreshing;
  String? _refreshingForAccess;
  int? _refreshingGeneration;

  Future<Map<String, Object?>> getObject(
    String path, {
    bool surfaceServerErrors = false,
  }) => _requestObject(
    path,
    method: 'GET',
    surfaceServerErrors: surfaceServerErrors,
  );

  Future<Map<String, Object?>> postObject(String path, {Object? data}) =>
      _requestObject(
        path,
        method: 'POST',
        data: data,
        surfaceServerErrors: true,
      );

  Future<List<Object?>> getList(String path) async {
    final response = await _request(path, method: 'GET');
    final data = response.data;
    if (data is! List) {
      throw const RequestFailure();
    }
    return data.cast<Object?>();
  }

  Future<Map<String, Object?>> patchObject(
    String path,
    Map<String, Object?> data,
  ) => _requestObject(path, method: 'PATCH', data: data);

  Future<void> postEmpty(String path) async {
    await _request(path, method: 'POST');
  }

  Future<void> postEmptyWithSession(String path, StoredTokens? session) async {
    if (session == null) return;
    final response = await _transport.request(
      path,
      method: 'POST',
      bearerToken: session.accessToken,
    );
    if (!response.isSuccessful) throw const RequestFailure();
  }

  Future<StoredTokens?> restoreSession() async {
    final snapshot = await _sessionAuthority.snapshot();
    if (snapshot == null) return null;
    if (_isExpired(snapshot.tokens.refreshExpiresAt)) {
      await _expireSession(snapshot);
      return null;
    }
    if (_isExpired(snapshot.tokens.accessExpiresAt)) {
      return _coordinateRefresh(snapshot);
    }
    return snapshot.tokens;
  }

  Future<Map<String, Object?>> _requestObject(
    String path, {
    required String method,
    Object? data,
    bool surfaceServerErrors = false,
  }) async {
    final response = await _request(
      path,
      method: method,
      data: data,
      surfaceServerErrors: surfaceServerErrors,
    );
    final body = response.data;
    if (body is! Map) {
      throw const RequestFailure();
    }
    return body.cast<String, Object?>();
  }

  Future<ApiResponse> _request(
    String path, {
    required String method,
    Object? data,
    bool isRetry = false,
    StoredTokens? retryTokens,
    SessionSnapshot? expectedSession,
    bool surfaceServerErrors = false,
  }) async {
    final snapshot =
        expectedSession ??
        (retryTokens == null ? await _sessionAuthority.snapshot() : null);
    final tokens = retryTokens ?? snapshot?.tokens;
    if (tokens == null) {
      throw const SessionExpired();
    }
    if (!isRetry && _isExpired(tokens.accessExpiresAt)) {
      final refreshed = await _coordinateRefresh(snapshot!);
      return _request(
        path,
        method: method,
        data: data,
        isRetry: true,
        retryTokens: refreshed,
        expectedSession: snapshot,
        surfaceServerErrors: surfaceServerErrors,
      );
    }
    final response = await _transport.request(
      path,
      method: method,
      data: _sendable(data),
      bearerToken: tokens.accessToken,
    );
    if (response.statusCode == 401) {
      if (isRetry) {
        final cleared = await _expireSession(snapshot);
        if (!cleared) throw const RequestFailure();
        throw const SessionExpired();
      }
      final refreshed = await _coordinateRefresh(snapshot!);
      return _request(
        path,
        method: method,
        data: data,
        isRetry: true,
        retryTokens: refreshed,
        expectedSession: snapshot,
        surfaceServerErrors: surfaceServerErrors,
      );
    }
    if (!response.isSuccessful) {
      if (surfaceServerErrors) {
        throw ServerFailure(
          code: _serverErrorCode(response.data),
          statusCode: response.statusCode,
        );
      }
      throw const RequestFailure();
    }
    return response;
  }

  Future<StoredTokens> _coordinateRefresh(SessionSnapshot failedSession) async {
    final failedTokens = failedSession.tokens;
    final activeRefresh = _refreshing;
    if (activeRefresh != null && _isRefreshingFor(failedSession)) {
      return activeRefresh.future;
    }

    final current = await _sessionAuthority.snapshot();
    if (current == null) {
      throw const SessionExpired();
    }
    if (current.generation != failedSession.generation) {
      throw const RequestFailure();
    }
    if (current.tokens.accessToken != failedTokens.accessToken) {
      return current.tokens;
    }
    if (_isExpired(current.tokens.refreshExpiresAt)) {
      final cleared = await _expireSession(current);
      if (!cleared) throw const RequestFailure();
      throw const SessionExpired();
    }

    final afterReadRefresh = _refreshing;
    if (afterReadRefresh != null && _isRefreshingFor(failedSession)) {
      return afterReadRefresh.future;
    }

    final completer = Completer<StoredTokens>();
    _refreshing = completer;
    _refreshingForAccess = failedTokens.accessToken;
    _refreshingGeneration = current.generation;
    _onEvent?.call('session.refresh.started');
    unawaited(_completeRefresh(completer, current));
    return completer.future;
  }

  Future<void> _completeRefresh(
    Completer<StoredTokens> completer,
    SessionSnapshot current,
  ) async {
    try {
      completer.complete(await _performRefresh(current));
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    } finally {
      if (identical(_refreshing, completer) &&
          _refreshingGeneration == current.generation) {
        _refreshing = null;
        _refreshingForAccess = null;
        _refreshingGeneration = null;
      }
    }
  }

  Future<StoredTokens> _performRefresh(SessionSnapshot current) async {
    try {
      final response = await _transport.request(
        '/auth/refresh/',
        method: 'POST',
        data: <String, Object?>{'refresh_token': current.tokens.refreshToken},
      );
      if (response.statusCode == 401) {
        final cleared = await _expireSession(current);
        if (!cleared) throw const RequestFailure();
        throw const SessionExpired();
      }
      if (!response.isSuccessful) throw const RequestFailure();
      final body = response.data;
      if (body is! Map) {
        throw const RequestFailure();
      }
      final rotated = _parseSession(body);
      final identified = rotated.withSessionIdentity(current.sessionIdentity);
      final committed = await _sessionAuthority.commitRefresh(
        current,
        identified,
      );
      if (!committed) throw const RequestFailure();
      _onEvent?.call('session.refresh.completed');
      return identified;
    } on OfflineFailure {
      _onEvent?.call('session.refresh.offline');
      rethrow;
    } on SessionExpired {
      rethrow;
    } on ApiError {
      rethrow;
    } catch (_) {
      throw const RequestFailure();
    }
  }

  Future<bool> _expireSession([SessionSnapshot? expected]) async {
    final cleared = expected == null
        ? await _clearSession()
        : await _sessionAuthority.clearIfCurrent(expected);
    if (cleared) _onEvent?.call('session.expired');
    return cleared;
  }

  Future<bool> _clearSession() async {
    await _sessionAuthority.clear();
    return true;
  }

  StoredTokens _parseSession(Map body) {
    try {
      return StoredTokens.fromJson(body.cast<String, Object?>());
    } catch (_) {
      throw const RequestFailure();
    }
  }

  bool _isExpired(DateTime expiry) => !expiry.toUtc().isAfter(_now().toUtc());

  bool _isRefreshingFor(SessionSnapshot session) =>
      _refreshingForAccess == session.tokens.accessToken &&
      _refreshingGeneration == session.generation;

  /// A multipart body is a stream that a retry cannot consume twice.
  Object? _sendable(Object? data) => data is FormData ? data.clone() : data;

  String _serverErrorCode(Object? body) {
    if (body is! Map) return '';
    final error = body['error'];
    if (error is! Map) return '';
    final code = error['code'];
    return code is String ? code : '';
  }
}
