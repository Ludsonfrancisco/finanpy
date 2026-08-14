final class AppConfig {
  const AppConfig({required this.apiBaseUrl});

  factory AppConfig.fromEnvironment() => const AppConfig(
    apiBaseUrl: String.fromEnvironment(
      'LAR_FINANCE_API_BASE_URL',
      defaultValue: 'https://financeiro.palmbook.online/api/v1',
    ),
  );

  final String apiBaseUrl;

  String get normalizedApiBaseUrl => apiBaseUrl.endsWith('/')
      ? apiBaseUrl.substring(0, apiBaseUrl.length - 1)
      : apiBaseUrl;

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
  }
}
