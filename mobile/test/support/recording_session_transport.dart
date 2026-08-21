import 'package:lar_finance/core/network/dio_transport.dart';
import 'package:lar_finance/core/network/session_transport.dart';
import 'package:lar_finance/features/auth/domain/session.dart';

final class RecordedApiRequest {
  const RecordedApiRequest({
    required this.path,
    required this.method,
    required this.data,
  });

  final String path;
  final String method;
  final Object? data;
}

final class RecordingApiTransport implements ApiTransport {
  RecordingApiTransport(this.respond);

  final Future<ApiResponse> Function(RecordedApiRequest request) respond;
  final List<RecordedApiRequest> requests = <RecordedApiRequest>[];

  @override
  Future<ApiResponse> request(
    String path, {
    required String method,
    Object? data,
    String? bearerToken,
  }) {
    final request = RecordedApiRequest(path: path, method: method, data: data);
    requests.add(request);
    return respond(request);
  }
}

final class MemoryTokenStore implements TokenStore {
  MemoryTokenStore([StoredTokens? initial]) : value = initial ?? testTokens();

  StoredTokens? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<StoredTokens?> read() async => value;

  @override
  Future<void> write(StoredTokens tokens) async => value = tokens;
}

StoredTokens testTokens() => StoredTokens(
  accessToken: 'access-test',
  accessExpiresAt: DateTime.utc(2030, 1, 1),
  refreshToken: 'refresh-test',
  refreshExpiresAt: DateTime.utc(2030, 2, 1),
  deviceUuid: '11111111-1111-4111-8111-111111111111',
);

SessionTransport recordingSessionTransport(RecordingApiTransport transport) =>
    SessionTransport(transport: transport, tokenStore: MemoryTokenStore());
