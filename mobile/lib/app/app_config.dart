final class AppConfig {
  const AppConfig({required this.apiBaseUrl, this.buildSha = 'development'});

  factory AppConfig.fromEnvironment() => const AppConfig(
    apiBaseUrl: String.fromEnvironment(
      'LAR_FINANCE_API_BASE_URL',
      defaultValue: 'https://financeiro.palmbook.online/api/v1',
    ),
    buildSha: String.fromEnvironment(
      'LAR_FINANCE_BUILD_SHA',
      defaultValue: 'development',
    ),
  );

  final String apiBaseUrl;
  final String buildSha;

  String get normalizedApiBaseUrl => apiBaseUrl.endsWith('/')
      ? apiBaseUrl.substring(0, apiBaseUrl.length - 1)
      : apiBaseUrl;

  String get buildLabel => buildSha == 'development' || buildSha.length <= 7
      ? buildSha
      : buildSha.substring(0, 7);

  String get serverHost => Uri.parse(normalizedApiBaseUrl).host;

  void validate() {
    final uri = Uri.parse(normalizedApiBaseUrl);
    final local = uri.host == 'localhost' || uri.host == '127.0.0.1';
    final allowedScheme =
        uri.scheme == 'https' || (uri.scheme == 'http' && local);
    if (!uri.hasAuthority || uri.host.isEmpty || !allowedScheme) {
      throw ArgumentError.value(
        apiBaseUrl,
        'apiBaseUrl',
        'HTTPS is required outside localhost',
      );
    }
    if (buildSha != 'development' &&
        !RegExp(r'^[0-9a-f]{40}$').hasMatch(buildSha)) {
      throw ArgumentError.value(
        buildSha,
        'buildSha',
        'A release build SHA must contain 40 lowercase hexadecimal characters',
      );
    }
  }
}
