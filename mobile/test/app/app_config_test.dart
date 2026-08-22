import 'package:flutter_test/flutter_test.dart';
import 'package:lar_finance/app/app_config.dart';

void main() {
  test('normalizes the API base URL without a trailing slash', () {
    const config = AppConfig(apiBaseUrl: 'https://example.test/api/v1/');
    expect(config.normalizedApiBaseUrl, 'https://example.test/api/v1');
  });

  test('exposes a short immutable client build and server host', () {
    const config = AppConfig(
      apiBaseUrl: 'https://financeiro.palmbook.online/api/v1/',
      buildSha: '1234567890abcdef1234567890abcdef12345678',
    );

    expect(config.buildLabel, '1234567');
    expect(config.serverHost, 'financeiro.palmbook.online');
  });

  test('keeps development label when no release SHA was injected', () {
    const config = AppConfig(apiBaseUrl: 'https://example.test/api/v1');
    expect(config.buildLabel, 'development');
  });

  test('rejects a malformed release SHA', () {
    expect(
      () => const AppConfig(
        apiBaseUrl: 'https://example.test/api/v1',
        buildSha: 'not-a-release-sha',
      ).validate(),
      throwsArgumentError,
    );
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
