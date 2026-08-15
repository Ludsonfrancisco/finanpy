import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lar_finance/app/adaptive_shell.dart';
import 'package:lar_finance/design_system/lar_theme.dart';
import 'package:lar_finance/features/imports/application/import_controller.dart';
import 'package:lar_finance/features/imports/domain/import_preview.dart';
import 'package:lar_finance/features/imports/presentation/import_screen.dart';

import '../../support/golden_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('pt_BR');
    await loadGoldenFonts();
  });

  for (final fixture in <_GoldenFixture>[
    const _GoldenFixture(
      name: 'mobile claro',
      size: Size(390, 844),
      brightness: Brightness.light,
      platform: TargetPlatform.android,
      file: '../../goldens/import_mobile_light.png',
    ),
    const _GoldenFixture(
      name: 'mobile escuro',
      size: Size(390, 844),
      brightness: Brightness.dark,
      platform: TargetPlatform.android,
      file: '../../goldens/import_mobile_dark.png',
    ),
    const _GoldenFixture(
      name: 'Windows claro',
      size: Size(1366, 768),
      brightness: Brightness.light,
      platform: TargetPlatform.windows,
      file: '../../goldens/import_windows_light.png',
    ),
    const _GoldenFixture(
      name: 'Windows escuro',
      size: Size(1366, 768),
      brightness: Brightness.dark,
      platform: TargetPlatform.windows,
      file: '../../goldens/import_windows_dark.png',
    ),
  ]) {
    testWidgets('Importação Casa de Valores ${fixture.name}', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = fixture.size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final base = fixture.brightness == Brightness.dark
          ? LarTheme.dark
          : LarTheme.light;
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: goldenTheme(
            base: base,
            platform: fixture.platform,
            brightness: fixture.brightness,
          ),
          home: AdaptiveShell(
            selectedIndex: 1,
            onSelect: (_) {},
            child: ImportScreen(
              state: ImportViewState(
                phase: ImportPhase.preview,
                preview: _preview,
              ),
              onSelect: () {},
              onConfirm: () {},
              onCancel: () {},
              onRetry: () {},
              onLoadMore: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(fixture.file),
      );
    }, tags: 'golden');
  }
}

final class _GoldenFixture {
  const _GoldenFixture({
    required this.name,
    required this.size,
    required this.brightness,
    required this.platform,
    required this.file,
  });

  final String name;
  final Size size;
  final Brightness brightness;
  final TargetPlatform platform;
  final String file;
}

final _preview = ImportPreview(
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
  recordCount: 4,
  pendingCount: 2,
  incomeTotalMinor: 780000,
  expenseTotalMinor: 53680,
  isRepeatedFile: false,
  records: <ImportRecordPreview>[
    ImportRecordPreview(
      uuid: '00000000-0000-4000-8000-000000000003',
      postedOn: DateTime.utc(2026, 8, 2),
      description: 'Supermercado sintético',
      amountMinor: 28640,
      type: ImportEntryType.expense,
      outcome: ImportRecordOutcome.pending,
    ),
    ImportRecordPreview(
      uuid: '00000000-0000-4000-8000-000000000004',
      postedOn: DateTime.utc(2026, 8, 5),
      description: 'Salário sintético',
      amountMinor: 780000,
      type: ImportEntryType.income,
      outcome: ImportRecordOutcome.pending,
    ),
    ImportRecordPreview(
      uuid: '00000000-0000-4000-8000-000000000005',
      postedOn: DateTime.utc(2026, 8, 8),
      description: 'Energia sintética',
      amountMinor: 21490,
      type: ImportEntryType.expense,
      outcome: ImportRecordOutcome.duplicate,
    ),
    ImportRecordPreview(
      uuid: '00000000-0000-4000-8000-000000000006',
      postedOn: DateTime.utc(2026, 8, 11),
      description: 'Assinatura sintética',
      amountMinor: 3550,
      type: ImportEntryType.expense,
      outcome: ImportRecordOutcome.warning,
    ),
  ],
  nextCursor: null,
);
