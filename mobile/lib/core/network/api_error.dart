sealed class ApiError implements Exception {
  const ApiError(this.message);

  final String message;

  @override
  String toString() => message;
}

final class AuthFailure extends ApiError {
  const AuthFailure()
    : super('Não foi possível entrar. Confira os dados e tente novamente.');
}

final class OfflineFailure extends ApiError {
  const OfflineFailure()
    : super('Sem conexão. Confira sua internet e tente novamente.');
}

final class SessionExpired extends ApiError {
  const SessionExpired() : super('Sua sessão expirou. Entre novamente.');
}

final class RequestFailure extends ApiError {
  const RequestFailure() : super('Não foi possível concluir a solicitação.');
}

/// A refused request whose stable server code may drive a domain decision.
///
/// Only the code and the status cross this boundary. The remote message is
/// never carried, so it can never reach the interface.
final class ServerFailure extends ApiError {
  const ServerFailure({required this.code, required this.statusCode})
    : super('Não foi possível concluir a solicitação.');

  final String code;
  final int statusCode;

  @override
  String toString() => 'ServerFailure(code: $code, status: $statusCode)';
}
