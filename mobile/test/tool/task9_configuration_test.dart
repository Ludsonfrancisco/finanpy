import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pubspec pins the private pilot MSIX configuration exactly', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(pubspec, contains('  msix: 3.18.0'));
    expect(pubspec, contains('msix_config:\n'));
    expect(pubspec, contains('  display_name: Lar Finance'));
    expect(pubspec, contains('  identity_name: online.palmbook.larfinance'));
    expect(pubspec, contains('  publisher_display_name: Lar Finance'));
    expect(pubspec, contains('  publisher: CN=Lar Finance Private'));
    expect(pubspec, contains('  msix_version: 0.1.0.0'));
    expect(pubspec, contains('  capabilities: internetClient'));
    expect(pubspec, contains('  install_certificate: false'));
  });

  test('CI defines secret-free Flutter checks and three platform builds', () {
    final workflow = File('../.github/workflows/ci.yml').readAsStringSync();

    expect(workflow, contains('flutter_checks:'));
    expect(workflow, contains('flutter_windows:'));
    expect(workflow, contains('flutter_android:'));
    expect(workflow, contains('flutter_ios:'));
    expect(workflow, contains('runs-on: windows-latest'));
    expect(workflow, contains('runs-on: macos-latest'));
    expect(workflow, contains('flutter build windows --release'));
    expect(
      workflow,
      contains('dart run msix:create --install-certificate false'),
    );
    expect(workflow, contains('flutter build apk --release'));
    expect(workflow, contains('flutter build ios --release --no-codesign'));
    expect('tool/flutter-version.json'.allMatches(workflow), hasLength(4));
    expect(workflow, isNot(contains('/sync/push/')));
    expect(workflow, isNot(contains('LAR_FINANCE_EMAIL')));
    expect(workflow, isNot(contains('LAR_FINANCE_PASSWORD')));
  });

  test('golden font fixtures resolve from portable tool metadata', () {
    final goldenTest = File(
      'test/features/home/home_goldens_test.dart',
    ).readAsStringSync();

    expect(goldenTest, contains('.dart_tool/package_config.json'));
    expect(goldenTest, isNot(contains("environment['LOCALAPPDATA']")));
    expect(goldenTest, isNot(contains(r'C:\Windows\Fonts')));
  });
}
