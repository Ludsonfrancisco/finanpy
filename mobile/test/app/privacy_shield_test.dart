import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lar_finance/app/privacy_shield.dart';

void main() {
  testWidgets('covers financial content while the app is inactive', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: PrivacyShield(child: Text('R\$ 24.860,40'))),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();

    expect(find.bySemanticsLabel('Lar Finance protegido'), findsOneWidget);
    expect(find.text('R\$ 24.860,40'), findsNothing);
  });

  testWidgets('restores financial content after resume', (tester) async {
    final restore = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: PrivacyShield(
          onResumed: () => restore.future,
          child: const Text('Conteúdo financeiro'),
        ),
      ),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(find.bySemanticsLabel('Lar Finance protegido'), findsOneWidget);
    restore.complete();
    await tester.pump();
    await tester.pump();

    expect(find.bySemanticsLabel('Lar Finance protegido'), findsNothing);
    expect(find.text('Conteúdo financeiro'), findsOneWidget);
  });

  testWidgets(
    'an obsolete resume completion cannot uncover a newer inactive state',
    (tester) async {
      final restore = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: PrivacyShield(
            onResumed: () => restore.future,
            child: const Text('Conteúdo financeiro'),
          ),
        ),
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      restore.complete();
      await tester.pump();

      expect(find.bySemanticsLabel('Lar Finance protegido'), findsOneWidget);
      expect(find.text('Conteúdo financeiro'), findsNothing);
    },
  );
}
