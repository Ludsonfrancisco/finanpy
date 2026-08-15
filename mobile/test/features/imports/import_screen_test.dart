import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:lar_finance/design_system/components/financial_amount.dart';
import 'package:lar_finance/design_system/lar_theme.dart';
import 'package:lar_finance/features/imports/application/import_controller.dart';
import 'package:lar_finance/features/imports/domain/import_preview.dart';
import 'package:lar_finance/features/imports/presentation/import_screen.dart';

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  testWidgets('idle invites a selection without inventing data', (
    tester,
  ) async {
    await _pump(tester, const ImportViewState());

    expect(find.text('Importação OFX'), findsOneWidget);
    expect(find.text('Nenhum arquivo selecionado'), findsOneWidget);
    expect(find.byKey(const Key('import-select')), findsOneWidget);
    expect(find.byKey(const Key('import-confirm')), findsNothing);
    expect(find.textContaining('R\$'), findsNothing);
  });

  testWidgets('uploading shows progress and blocks a second selection', (
    tester,
  ) async {
    await _pump(tester, const ImportViewState(phase: ImportPhase.uploading));

    expect(find.text('Enviando arquivo'), findsOneWidget);
    expect(find.byKey(const Key('import-progress')), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('import-select')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('a preview shows origin, period, counts, totals and items', (
    tester,
  ) async {
    await _pump(
      tester,
      ImportViewState(phase: ImportPhase.preview, preview: _preview()),
    );

    expect(find.text('Nubank — Conta'), findsOneWidget);
    expect(find.textContaining('não é prova de origem'), findsOneWidget);
    expect(find.text('01 ago. 2026 a 12 ago. 2026'), findsOneWidget);
    expect(find.text('Lançamentos'), findsOneWidget);
    expect(find.text('3'), findsWidgets);
    expect(
      find.text(
        'Prévia disponível até '
        '${DateFormat('dd/MM/yyyy, HH:mm', 'pt_BR').format(DateTime.utc(2026, 8, 16, 15).toLocal())}',
      ),
      findsOneWidget,
    );
    expect(find.text(formatBrlMinor(100000)), findsOneWidget);
    expect(find.text(formatBrlMinor(25050)), findsOneWidget);
    expect(find.text('Mercado sintético'), findsOneWidget);
    expect(find.text('Salário sintético'), findsOneWidget);
    expect(find.byKey(const Key('import-confirm')), findsOneWidget);
    expect(find.byKey(const Key('import-cancel')), findsOneWidget);
  });

  testWidgets('a credit preview labels the detected product', (tester) async {
    await _pump(
      tester,
      ImportViewState(
        phase: ImportPhase.preview,
        preview: _preview(productType: ImportProductType.creditCard),
      ),
    );

    expect(find.text('Nubank — Cartão'), findsOneWidget);
  });

  testWidgets('an empty preview cannot be confirmed', (tester) async {
    await _pump(
      tester,
      ImportViewState(
        phase: ImportPhase.preview,
        preview: _preview(records: const <ImportRecordPreview>[], counts: 0),
      ),
    );

    expect(find.text('Nenhum lançamento no período'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('import-confirm')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('a repeated file is announced before any confirmation', (
    tester,
  ) async {
    await _pump(
      tester,
      ImportViewState(
        phase: ImportPhase.preview,
        preview: _preview(
          records: const <ImportRecordPreview>[],
          counts: 0,
          isRepeatedFile: true,
          duplicateCount: 12,
        ),
      ),
    );

    expect(find.text('Arquivo já importado antes'), findsOneWidget);
    expect(find.textContaining('12'), findsWidgets);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('import-confirm')))
          .onPressed,
      isNull,
    );
  });

  for (final failure in <({ImportFailureKind kind, String message})>[
    (
      kind: ImportFailureKind.expiredPreview,
      message: 'A prévia expirou. Selecione o arquivo novamente.',
    ),
    (
      kind: ImportFailureKind.busy,
      message: 'A importação está ocupada. Tente novamente.',
    ),
    (
      kind: ImportFailureKind.offline,
      message: 'Sem conexão. Confira sua internet e tente novamente.',
    ),
    (
      kind: ImportFailureKind.invalidFile,
      message: 'Não foi possível ler este arquivo OFX.',
    ),
    (
      kind: ImportFailureKind.unsupportedFile,
      message: 'Este arquivo não é um OFX compatível.',
    ),
    (
      kind: ImportFailureKind.fileTooLarge,
      message: 'O arquivo passa de 10 MiB.',
    ),
    (
      kind: ImportFailureKind.notFound,
      message: 'Esta prévia não está mais disponível.',
    ),
    (
      kind: ImportFailureKind.invalidState,
      message: 'Esta prévia não pode mais ser usada.',
    ),
    (
      kind: ImportFailureKind.unknown,
      message: 'Não foi possível concluir a importação.',
    ),
  ]) {
    testWidgets('${failure.kind.name} shows its own safe message', (
      tester,
    ) async {
      await _pump(
        tester,
        ImportViewState(phase: ImportPhase.failure, failure: failure.kind),
      );

      expect(find.text(failure.message), findsOneWidget);
      expect(find.byKey(const Key('import-retry')), findsOneWidget);
    });
  }

  testWidgets('a failure keeps the records already received', (tester) async {
    await _pump(
      tester,
      ImportViewState(
        phase: ImportPhase.failure,
        failure: ImportFailureKind.busy,
        preview: _preview(),
      ),
    );

    expect(find.text('Mercado sintético'), findsOneWidget);
    expect(find.byKey(const Key('import-retry')), findsOneWidget);
  });

  testWidgets('confirming keeps the actions visible and disabled', (
    tester,
  ) async {
    await _pump(
      tester,
      ImportViewState(phase: ImportPhase.confirming, preview: _preview()),
    );

    expect(find.text('Confirmando'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('import-confirm')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('import-cancel')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('a receipt reports what the ledger received', (tester) async {
    await _pump(
      tester,
      ImportViewState(
        phase: ImportPhase.completed,
        preview: _preview(
          status: ImportBatchStatus.completed,
          createdCount: 2,
          duplicateCount: 1,
        ),
      ),
    );

    expect(find.text('Importação concluída'), findsOneWidget);
    expect(find.text('Criados'), findsOneWidget);
    expect(find.byKey(const Key('import-confirm')), findsNothing);
    expect(find.byKey(const Key('import-select')), findsOneWidget);
  });

  testWidgets('a receipt with a failed pull flags the pending data', (
    tester,
  ) async {
    await _pump(
      tester,
      ImportViewState(
        phase: ImportPhase.completed,
        preview: _preview(status: ImportBatchStatus.completed),
        hasPendingSync: true,
      ),
    );

    expect(
      find.text('Dados gravados. A sincronização ainda está pendente.'),
      findsOneWidget,
    );
  });

  testWidgets('the actions call back exactly once per tap', (tester) async {
    var confirms = 0;
    var cancels = 0;
    await _pump(
      tester,
      ImportViewState(phase: ImportPhase.preview, preview: _preview()),
      onConfirm: () => confirms++,
      onCancel: () => cancels++,
    );

    await tester.tap(find.byKey(const Key('import-confirm')));
    await tester.tap(find.byKey(const Key('import-cancel')));
    await tester.pump();

    expect(confirms, 1);
    expect(cancels, 1);
  });

  testWidgets('a pending page offers to continue loading', (tester) async {
    var loads = 0;
    await _pump(
      tester,
      ImportViewState(
        phase: ImportPhase.preview,
        preview: _preview(nextCursor: '2'),
      ),
      onLoadMore: () => loads++,
    );

    await tester.ensureVisible(find.byKey(const Key('import-load-more')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('import-load-more')));
    await tester.pump();

    expect(loads, 1);
  });

  testWidgets('the desktop layout keeps the summary beside the list', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1366, 768);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await _pump(
      tester,
      ImportViewState(phase: ImportPhase.preview, preview: _preview()),
    );

    final summary = tester.getTopLeft(find.byKey(const Key('import-summary')));
    final list = tester.getTopLeft(find.byKey(const Key('import-record-list')));
    expect(summary.dx, greaterThan(list.dx));
  });
}

Future<void> _pump(
  WidgetTester tester,
  ImportViewState state, {
  VoidCallback? onSelect,
  VoidCallback? onConfirm,
  VoidCallback? onCancel,
  VoidCallback? onRetry,
  VoidCallback? onLoadMore,
  double textScale = 1,
  bool disableAnimations = false,
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: brightness == Brightness.dark ? LarTheme.dark : LarTheme.light,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: disableAnimations,
          ),
          child: ImportScreen(
            state: state,
            onSelect: onSelect ?? () {},
            onConfirm: onConfirm ?? () {},
            onCancel: onCancel ?? () {},
            onRetry: onRetry ?? () {},
            onLoadMore: onLoadMore ?? () {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

ImportPreview _preview({
  ImportProductType productType = ImportProductType.bankAccount,
  ImportBatchStatus status = ImportBatchStatus.previewReady,
  List<ImportRecordPreview>? records,
  int counts = 3,
  int createdCount = 0,
  int duplicateCount = 1,
  bool isRepeatedFile = false,
  String? nextCursor,
}) => ImportPreview(
  uuid: '00000000-0000-4000-8000-000000000000',
  status: status,
  productType: productType,
  statementStart: DateTime.utc(2026, 8),
  statementEnd: DateTime.utc(2026, 8, 12),
  expiresAt: DateTime.utc(2026, 8, 16, 15),
  accountUuid: '00000000-0000-4000-8000-000000000001',
  financialOwnerUuid: '00000000-0000-4000-8000-000000000002',
  createdCount: createdCount,
  duplicateCount: duplicateCount,
  warningCount: 0,
  recordCount: counts,
  pendingCount: counts,
  incomeTotalMinor: 100000,
  expenseTotalMinor: 25050,
  isRepeatedFile: isRepeatedFile,
  records: records ?? _records,
  nextCursor: nextCursor,
);

final _records = <ImportRecordPreview>[
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
];
