import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('scene lifecycle owns an idempotent opaque privacy overlay', () {
    final source = File('ios/Runner/SceneDelegate.swift').readAsStringSync();
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(source, contains('sceneWillResignActive'));
    expect(source, contains('sceneDidEnterBackground'));
    expect(source, contains('sceneDidBecomeActive'));
    expect(source, contains('privacyView == nil'));
    expect(source, contains('Lar Finance protegido'));
    expect(source, contains('red: 9 / 255'));
    expect(appDelegate, isNot(contains('applicationDidEnterBackground')));
  });
}
