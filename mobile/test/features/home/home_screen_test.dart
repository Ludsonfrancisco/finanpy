import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lar_finance/core/sync/sync_models.dart' show SyncResult;
import 'package:lar_finance/core/sync/sync_state.dart';
import 'package:lar_finance/design_system/lar_theme.dart';
import 'package:lar_finance/features/home/application/home_controller.dart';
import 'package:lar_finance/features/home/data/home_repository.dart';
import 'package:lar_finance/features/home/domain/home_snapshot.dart';
import 'package:lar_finance/features/home/presentation/home_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('pt_BR'));

  testWidgets('loading sem cache não presume nenhum valor financeiro', (
    tester,
  ) async {
    final repository = _FakeHomeRepository(
      streams: {OwnerScopeKind.household: const Stream<HomeSnapshot>.empty()},
    );
    final controller = _controller(repository);
    addTearDown(controller.dispose);

    await _pumpHome(tester, controller);

    expect(find.byKey(const Key('home-loading')), findsOneWidget);
    expect(find.text('Carregando dados locais'), findsOneWidget);
    expect(find.text('R\$\u00a00,00'), findsNothing);
  });

  testWidgets('offline sem cache explica indisponibilidade e permite tentar', (
    tester,
  ) async {
    final repository = _FakeHomeRepository(
      streams: {
        OwnerScopeKind.household: Stream.value(
          _snapshot(hasCache: false, hasAccountData: false),
        ),
      },
    );
    final syncState = _syncState()..markOffline(null);
    final controller = _controller(repository, syncState: syncState);
    addTearDown(controller.dispose);

    await _pumpHome(tester, controller);

    expect(find.text('Sem dados disponíveis offline'), findsOneWidget);
    expect(find.text('Indisponível'), findsWidgets);
    expect(find.text('Tentar novamente'), findsOneWidget);
    expect(find.text('R\$\u00a00,00'), findsNothing);
  });

  testWidgets('cache offline permanece legível e informa freshness', (
    tester,
  ) async {
    final cachedAt = DateTime(2026, 8, 14, 11);
    final repository = _FakeHomeRepository(
      streams: {
        OwnerScopeKind.household: Stream.value(
          _snapshot(lastSyncedAt: cachedAt),
        ),
      },
    );
    final syncState = _syncState()..markOffline(cachedAt);
    final controller = _controller(repository, syncState: syncState);
    addTearDown(controller.dispose);

    await _pumpHome(tester, controller);

    expect(find.textContaining('Offline'), findsWidgets);
    expect(find.text('Dados salvos no dispositivo'), findsOneWidget);
    expect(find.text('R\$\u00a024.860,40'), findsOneWidget);
    expect(find.textContaining('Última sincronização'), findsWidgets);
  });

  testWidgets('ledger vazio mantém rótulos e omite alertas inventados', (
    tester,
  ) async {
    final repository = _FakeHomeRepository(
      streams: {
        OwnerScopeKind.household: Stream.value(
          _snapshot(
            hasAccountData: false,
            transactions: const <HomeTransaction>[],
          ),
        ),
      },
    );
    final syncState = _syncState()..markCurrent(_syncedAt);
    final controller = _controller(repository, syncState: syncState);
    addTearDown(controller.dispose);

    await _pumpHome(tester, controller);

    expect(find.text('Saldo consolidado'), findsOneWidget);
    expect(find.text('Compromissos próximos'), findsOneWidget);
    expect(find.text('Gasto em agosto'), findsOneWidget);
    expect(find.text('Movimentações recentes'), findsOneWidget);
    expect(find.text('Nenhuma movimentação neste período'), findsOneWidget);
    expect(find.text('Dados de contas indisponíveis'), findsOneWidget);
    expect(find.textContaining('lançamentos para revisar'), findsNothing);
  });

  testWidgets('Lar Eu e Esposa atualizam todos os blocos sem vazamento', (
    tester,
  ) async {
    final repository = _FakeHomeRepository(
      streams: {
        OwnerScopeKind.household: Stream.value(_snapshot()),
        OwnerScopeKind.selfOwner: Stream.value(
          _snapshot(
            scope: const OwnerScope.self(_selfUuid),
            balanceMinor: 1400000,
            monthExpenseMinor: 10000,
            commitmentMinor: 20000,
            transactions: const <HomeTransaction>[],
          ),
        ),
        OwnerScopeKind.spouse: Stream.value(
          _snapshot(
            scope: const OwnerScope.spouse(_spouseUuid),
            balanceMinor: 2200000,
            monthExpenseMinor: 30000,
            commitmentMinor: 40000,
            transactions: const <HomeTransaction>[],
          ),
        ),
      },
    );
    final syncState = _syncState()..markCurrent(_syncedAt);
    final controller = _controller(repository, syncState: syncState);
    addTearDown(controller.dispose);

    await _pumpHome(tester, controller);
    expect(find.text('R\$\u00a024.860,40'), findsOneWidget);

    await controller.select(1);
    await tester.pump(const Duration(milliseconds: 20));
    expect(repository.requestedKinds.last, OwnerScopeKind.selfOwner);
    expect(find.text('R\$\u00a014.000,00'), findsOneWidget);
    expect(find.text('R\$\u00a024.860,40'), findsNothing);

    await controller.select(2);
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('R\$\u00a022.000,00'), findsOneWidget);
    expect(
      repository.requestedKinds,
      containsAllInOrder(OwnerScopeKind.values),
    );
  });

  testWidgets('falha de sync retém cache e mostra somente atenção comprovada', (
    tester,
  ) async {
    final repository = _FakeHomeRepository(
      streams: {OwnerScopeKind.household: Stream.value(_snapshot())},
    );
    final syncState = _syncState()..markFailed(_syncedAt);
    final controller = _controller(repository, syncState: syncState);
    addTearDown(controller.dispose);

    await _pumpHome(tester, controller);

    expect(find.text('Não foi possível sincronizar'), findsOneWidget);
    expect(find.text('R\$\u00a024.860,40'), findsOneWidget);
    expect(find.text('Atenção'), findsOneWidget);
  });

  testWidgets(
    'ocultar valores preserva contexto e remove dígitos financeiros',
    (tester) async {
      final repository = _FakeHomeRepository(
        streams: {OwnerScopeKind.household: Stream.value(_snapshot())},
      );
      final syncState = _syncState()..markCurrent(_syncedAt);
      final controller = _controller(repository, syncState: syncState);
      addTearDown(controller.dispose);

      await _pumpHome(tester, controller);
      expect(
        find.bySemanticsLabel(RegExp(r'Supermercado.*Despesa.*-R\$.*286,40')),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Ocultar valores'));
      await tester.pump();

      expect(find.text('Saldo consolidado'), findsOneWidget);
      expect(find.textContaining('••••••'), findsWidgets);
      expect(find.text('R\$\u00a024.860,40'), findsNothing);
      expect(find.byTooltip('Mostrar valores'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'Supermercado.*Valor financeiro oculto')),
        findsOneWidget,
      );
    },
  );

  testWidgets('200% de texto mantém ordem, sem overflow ou exceção', (
    tester,
  ) async {
    final repository = _FakeHomeRepository(
      streams: {OwnerScopeKind.household: Stream.value(_snapshot())},
    );
    final syncState = _syncState()..markCurrent(_syncedAt);
    final controller = _controller(repository, syncState: syncState);
    addTearDown(controller.dispose);

    await _pumpHome(tester, controller, textScale: 2);

    expect(tester.takeException(), isNull);
    final labels = <String>[
      'Saldo consolidado',
      'Compromissos próximos',
      'Gasto em agosto',
      'Movimentações recentes',
    ];
    final tops = labels
        .map((label) => tester.getTopLeft(find.text(label)).dy)
        .toList();
    expect(tops, orderedEquals(tops.toList()..sort()));
  });
}

const _selfUuid = '20000000-0000-4000-8000-000000000001';
const _spouseUuid = '20000000-0000-4000-8000-000000000002';
final _syncedAt = DateTime(2026, 8, 14, 11);

SyncState _syncState() => SyncState(retry: () async => SyncResult.current);

HomeController _controller(HomeRepository repository, {SyncState? syncState}) =>
    HomeController(
      repository: repository,
      syncState: syncState ?? _syncState(),
      now: () => DateTime(2026, 8, 14, 12),
    );

Future<void> _pumpHome(
  WidgetTester tester,
  HomeController controller, {
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 1200);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: LarTheme.light,
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(390, 1200),
          textScaler: TextScaler.linear(textScale),
        ),
        child: HomeScreen(controller: controller),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

HomeSnapshot _snapshot({
  OwnerScope scope = const OwnerScope.household(),
  int balanceMinor = 2486040,
  int monthExpenseMinor = 518472,
  int commitmentMinor = 342000,
  DateTime? lastSyncedAt,
  bool hasCache = true,
  bool hasAccountData = true,
  List<HomeTransaction>? transactions,
}) => HomeSnapshot(
  scope: scope,
  balanceMinor: balanceMinor,
  monthExpenseMinor: monthExpenseMinor,
  upcomingCommitmentMinor: commitmentMinor,
  recentTransactions:
      transactions ??
      <HomeTransaction>[
        HomeTransaction(
          uuid: '50000000-0000-4000-8000-000000000001',
          description: 'Supermercado',
          categoryName: 'Alimentação',
          ownerName: 'Conjunto',
          date: DateTime(2026, 8, 14),
          signedAmountMinor: -28640,
        ),
        HomeTransaction(
          uuid: '50000000-0000-4000-8000-000000000002',
          description: 'Salário',
          categoryName: 'Receita',
          ownerName: 'Eu',
          date: DateTime(2026, 8, 13),
          signedAmountMinor: 780000,
        ),
      ],
  lastSyncedAt: hasCache ? lastSyncedAt ?? _syncedAt : null,
  hasAccountData: hasAccountData,
);

final class _FakeHomeRepository implements HomeRepository {
  _FakeHomeRepository({required this.streams});

  final Map<OwnerScopeKind, Stream<HomeSnapshot>> streams;
  final List<OwnerScopeKind> requestedKinds = <OwnerScopeKind>[];

  @override
  Future<HomeOwnerScopes> readOwnerScopes() async => const HomeOwnerScopes(
    selfScope: OwnerScope.self(_selfUuid),
    spouseScope: OwnerScope.spouse(_spouseUuid),
  );

  @override
  Stream<HomeSnapshot> watchSnapshot(OwnerScope scope, DateTime now) {
    requestedKinds.add(scope.kind);
    return streams[scope.kind] ?? const Stream<HomeSnapshot>.empty();
  }
}
