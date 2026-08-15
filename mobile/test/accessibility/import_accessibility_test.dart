import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lar_finance/design_system/lar_theme.dart';
import 'package:lar_finance/features/imports/application/import_controller.dart';
import 'package:lar_finance/features/imports/domain/import_preview.dart';
import 'package:lar_finance/features/imports/presentation/import_screen.dart';
import 'package:lar_finance/features/imports/presentation/widgets/import_actions.dart';

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  testWidgets('a 320 px screen at 200% text scale does not overflow', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await _pump(
      tester,
      ImportViewState(phase: ImportPhase.preview, preview: _preview()),
      textScale: 2,
    );

    expect(tester.takeException(), isNull);
  });

  for (final platform in <TargetPlatform>[
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    testWidgets('the decisions keep a reachable target on ${platform.name}', (
      tester,
    ) async {
      await _pump(
        tester,
        ImportViewState(phase: ImportPhase.preview, preview: _preview()),
        platform: platform,
      );

      for (final key in const <Key>[
        Key('import-confirm'),
        Key('import-cancel'),
      ]) {
        final size = tester.getSize(find.byKey(key));
        expect(size.height, greaterThanOrEqualTo(kImportTargetHeight));
      }
    });
  }

  testWidgets('the content stays inside the safe area', (tester) async {
    await _pump(tester, const ImportViewState());

    expect(find.byType(SafeArea), findsWidgets);
  });

  testWidgets('each line announces direction and outcome', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      ImportViewState(phase: ImportPhase.preview, preview: _preview()),
    );

    expect(find.bySemanticsLabel(RegExp('Saída')), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('Entrada')), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('Duplicado')), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('Aviso')), findsWidgets);
    handle.dispose();
  });

  testWidgets('the keyboard reaches confirm before cancel', (tester) async {
    await _pump(
      tester,
      ImportViewState(phase: ImportPhase.preview, preview: _preview()),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(_isFocused(tester, find.byKey(const Key('import-confirm'))), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(_isFocused(tester, find.byKey(const Key('import-cancel'))), isTrue);
  });

  testWidgets('enter confirms and escape cancels from the keyboard', (
    tester,
  ) async {
    var confirms = 0;
    var cancels = 0;
    await _pump(
      tester,
      ImportViewState(phase: ImportPhase.preview, preview: _preview()),
      onConfirm: () => confirms++,
      onCancel: () => cancels++,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(confirms, 1);
    expect(cancels, 1);
  });

  testWidgets('a failure takes the focus to its own recovery', (tester) async {
    await _pump(
      tester,
      const ImportViewState(
        phase: ImportPhase.failure,
        failure: ImportFailureKind.busy,
      ),
    );
    await tester.pump();

    expect(_isFocused(tester, find.byKey(const Key('import-retry'))), isTrue);
  });

  testWidgets('disabled animations replace the animated progress', (
    tester,
  ) async {
    await _pump(
      tester,
      const ImportViewState(phase: ImportPhase.uploading),
      disableAnimations: true,
    );

    expect(find.byKey(const Key('import-progress')), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Enviando arquivo'), findsOneWidget);
  });
}

Future<void> _pump(
  WidgetTester tester,
  ImportViewState state, {
  VoidCallback? onConfirm,
  VoidCallback? onCancel,
  double textScale = 1,
  bool disableAnimations = false,
  TargetPlatform platform = TargetPlatform.android,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: LarTheme.light.copyWith(platform: platform),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: disableAnimations,
          ),
          child: ImportScreen(
            state: state,
            onSelect: () {},
            onConfirm: onConfirm ?? () {},
            onCancel: onCancel ?? () {},
            onRetry: () {},
            onLoadMore: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

bool _isFocused(WidgetTester tester, Finder target) {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  final element = tester.element(target);
  var found = false;
  context.visitAncestorElements((ancestor) {
    if (ancestor == element) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

ImportPreview _preview() => ImportPreview(
  uuid: '00000000-0000-4000-8000-000000000000',
  status: ImportBatchStatus.previewReady,
  productType: ImportProductType.bankAccount,
  statementStart: DateTime.utc(2026, 8),
  statementEnd: DateTime.utc(2026, 8, 12),
  expiresAt: DateTime.utc(2026, 8, 16, 15),
  accountUuid: '00000000-0000-4000-8000-000000000001',
  financialOwnerUuid: '00000000-0000-4000-8000-000000000002',
  createdCount: 0,
  duplicateCount: 1,
  warningCount: 1,
  recordCount: 3,
  pendingCount: 1,
  incomeTotalMinor: 100000,
  expenseTotalMinor: 25050,
  isRepeatedFile: false,
  records: <ImportRecordPreview>[
    ImportRecordPreview(
      uuid: '00000000-0000-4000-8000-000000000003',
      postedOn: DateTime.utc(2026, 8, 2),
      description: 'Mercado sintético',
      amountMinor: 4250,
      type: ImportEntryType.expense,
      outcome: ImportRecordOutcome.pending,
    ),
    ImportRecordPreview(
      uuid: '00000000-0000-4000-8000-000000000004',
      postedOn: DateTime.utc(2026, 8, 3),
      description: 'Salário sintético',
      amountMinor: 100000,
      type: ImportEntryType.income,
      outcome: ImportRecordOutcome.duplicate,
    ),
    ImportRecordPreview(
      uuid: '00000000-0000-4000-8000-000000000005',
      postedOn: DateTime.utc(2026, 8, 4),
      description: 'Assinatura sintética',
      amountMinor: 2990,
      type: ImportEntryType.expense,
      outcome: ImportRecordOutcome.warning,
    ),
  ],
  nextCursor: null,
);
