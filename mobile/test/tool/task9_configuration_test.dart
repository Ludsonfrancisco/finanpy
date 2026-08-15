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
    expect(
      workflow,
      contains(
        'flutter test integration_test/auth_sync_home_test.dart -d windows',
      ),
    );
    expect(
      'https://financeiro.palmbook.online/api/v1'.allMatches(workflow),
      hasLength(3),
    );
    expect(workflow, isNot(contains('https://example.invalid/api/v1')));
    expect(
      'flutter test --exclude-tags=golden'.allMatches(workflow),
      hasLength(2),
    );
    expect(workflow, contains('flutter test --tags=golden'));
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
    expect(goldenTest, contains("_packageRoot('flutter')"));
    expect(goldenTest, isNot(contains("environment['FLUTTER_ROOT']")));
    expect(goldenTest, isNot(contains("environment['LOCALAPPDATA']")));
    expect(goldenTest, isNot(contains(r'C:\Windows\Fonts')));
  });

  test('goldens are isolated to their canonical Windows renderer', () {
    final homeGoldens = File(
      'test/features/home/home_goldens_test.dart',
    ).readAsStringSync();
    final shellGoldens = File(
      'test/app/adaptive_shell_test.dart',
    ).readAsStringSync();

    expect(homeGoldens, contains("tags: 'golden'"));
    expect("tags: 'golden'".allMatches(shellGoldens), hasLength(2));
  });

  test('Windows runner manifest is committed despite the Python ignore', () {
    final rootIgnore = File('../.gitignore').readAsStringSync();

    expect(rootIgnore, contains('!/mobile/windows/runner/runner.exe.manifest'));
    expect(File('windows/runner/runner.exe.manifest').existsSync(), isTrue);
  });

  test('Android release manifest grants Internet access', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(
      manifest,
      contains('<uses-permission android:name="android.permission.INTERNET"/>'),
    );
  });

  test('Windows benchmark measures ten complete process launches', () {
    final harness = File(
      'tool/run_windows_home_benchmark.ps1',
    ).readAsStringSync();
    final application = File('tool/benchmark_home.dart').readAsStringSync();

    expect(harness, contains('Start-Process'));
    expect(harness, contains(r'$iterationCount = 10'));
    expect(harness, contains('build windows --profile'));
    expect(harness, contains('median_ms'));
    expect(application, contains('lar_finance_task9_benchmark.ready.json'));
    expect(application, isNot(contains('for (var iteration = 0;')));
  });
}
