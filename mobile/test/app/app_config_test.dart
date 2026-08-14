import 'package:flutter_test/flutter_test.dart';
import 'package:lar_finance/app/app_config.dart';

void main() {
  test('normalizes the API base URL without a trailing slash', () {
    const config = AppConfig(apiBaseUrl: 'https://example.test/api/v1/');
    expect(config.normalizedApiBaseUrl, 'https://example.test/api/v1');
  });

  test('rejects non HTTPS production URLs', () {
    expect(
      () =>
          const AppConfig(apiBaseUrl: 'http://example.test/api/v1').validate(),
      throwsArgumentError,
    );
  });

  test('rejects HTTPS URLs without a host', () {
    expect(
      () => const AppConfig(apiBaseUrl: 'https:///api/v1').validate(),
      throwsArgumentError,
    );
  });

  test('rejects unsupported schemes for local URLs', () {
    expect(
      () => const AppConfig(apiBaseUrl: 'ftp://localhost/api/v1').validate(),
      throwsArgumentError,
    );
  });
}
