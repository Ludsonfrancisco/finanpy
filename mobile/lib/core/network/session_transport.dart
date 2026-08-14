import 'dart:async';

import '../../features/auth/domain/session.dart';
import 'api_error.dart';
import 'dio_transport.dart';

typedef SessionEventSink = void Function(String event);

final class SessionTransport {
  SessionTransport({
    required ApiTransport transport,
    required TokenStore tokenStore,
    SessionEventSink? onEvent,
  }) : _transport = transport,
       _tokenStore = tokenStore,
       _onEvent = onEvent;

  final ApiTransport _transport;
  final TokenStore _tokenStore;
  final SessionEventSink? _onEvent;
  Completer<StoredTokens>? _refreshing;
  String? _refreshingForAccess;

  Future<Map<String, Object?>> getObject(String path) =>
      _requestObject(path, method: 'GET');

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

  Future<Map<String, Object?>> _requestObject(
    String path, {
    required String method,
    Object? data,
  }) async {
    final response = await _request(path, method: method, data: data);
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
  }) async {
    final tokens = retryTokens ?? await _tokenStore.read();
    if (tokens == null) {
      throw const SessionExpired();
    }
    final response = await _transport.request(
      path,
      method: method,
      data: data,
      bearerToken: tokens.accessToken,
    );
    if (response.statusCode == 401) {
      if (isRetry) {
        await _expireSession();
        throw const SessionExpired();
      }
      final refreshed = await _coordinateRefresh(tokens);
      return _request(
        path,
        method: method,
        data: data,
        isRetry: true,
        retryTokens: refreshed,
      );
    }
    if (!response.isSuccessful) {
      throw const RequestFailure();
    }
    return response;
  }

  Future<StoredTokens> _coordinateRefresh(StoredTokens failedTokens) async {
    final activeRefresh = _refreshing;
    if (activeRefresh != null &&
        _refreshingForAccess == failedTokens.accessToken) {
      return activeRefresh.future;
    }

    final current = await _tokenStore.read();
    if (current == null) {
      throw const SessionExpired();
    }
    if (current.accessToken != failedTokens.accessToken) {
      return current;
    }

    final afterReadRefresh = _refreshing;
    if (afterReadRefresh != null &&
        _refreshingForAccess == failedTokens.accessToken) {
      return afterReadRefresh.future;
    }

    final completer = Completer<StoredTokens>();
    _refreshing = completer;
    _refreshingForAccess = failedTokens.accessToken;
    _onEvent?.call('session.refresh.started');
    unawaited(_completeRefresh(completer, current));
    return completer.future;
  }

  Future<void> _completeRefresh(
    Completer<StoredTokens> completer,
    StoredTokens current,
  ) async {
    try {
      completer.complete(await _performRefresh(current));
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    } finally {
      if (identical(_refreshing, completer)) {
        _refreshing = null;
        _refreshingForAccess = null;
      }
    }
  }

  Future<StoredTokens> _performRefresh(StoredTokens current) async {
    try {
      final response = await _transport.request(
        '/auth/refresh/',
        method: 'POST',
        data: <String, Object?>{'refresh_token': current.refreshToken},
      );
      if (!response.isSuccessful) {
        await _expireSession();
        throw const SessionExpired();
      }
      final body = response.data;
      if (body is! Map) {
        await _expireSession();
        throw const SessionExpired();
      }
      final rotated = StoredTokens.fromJson(body.cast<String, Object?>());
      await _tokenStore.write(rotated);
      _onEvent?.call('session.refresh.completed');
      return rotated;
    } on OfflineFailure {
      _onEvent?.call('session.refresh.offline');
      rethrow;
    } on SessionExpired {
      rethrow;
    } catch (_) {
      await _expireSession();
      throw const SessionExpired();
    }
  }

  Future<void> _expireSession() async {
    await _tokenStore.clear();
    _onEvent?.call('session.expired');
  }
}
