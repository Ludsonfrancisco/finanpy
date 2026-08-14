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
