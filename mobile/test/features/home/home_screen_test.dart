import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lar_finance/app/app_lifecycle.dart';
import 'package:lar_finance/core/sync/sync_models.dart' show SyncResult;
import 'package:lar_finance/core/sync/sync_state.dart';
import 'package:lar_finance/design_system/components/financial_amount.dart';
import 'package:lar_finance/design_system/lar_colors.dart';
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

  test('recria a projeção na próxima meia-noite local', () async {
    var now = DateTime(2026, 8, 14, 23, 59, 30);
    final repository = _RecordingHomeRepository();
    final timers = <_ManualTimer>[];
    final controller = HomeController(
      repository: repository,
      syncState: _syncState(),
      now: () => now,
      timerFactory: (duration, callback) {
        final timer = _ManualTimer(duration, callback);
        timers.add(timer);
        return timer;
      },
    );
    addTearDown(controller.dispose);

    await controller.start();
    await Future<void>.delayed(Duration.zero);
    expect(repository.requestedTimes, <DateTime>[now]);
    expect(timers.single.duration, const Duration(seconds: 30));

    now = DateTime(2026, 8, 15);
    timers.single.fire();
    await Future<void>.delayed(Duration.zero);

    expect(repository.requestedTimes, <DateTime>[
      DateTime(2026, 8, 14, 23, 59, 30),
      DateTime(2026, 8, 15),
    ]);
    expect(timers.last.duration, const Duration(days: 1));
  });

  testWidgets('resume após virada de mês refaz agregados e label', (
    tester,
  ) async {
    var now = DateTime(2026, 8, 31, 23, 59);
    final resumeSignal = ValueNotifier<int>(0);
    addTearDown(resumeSignal.dispose);
    final repository = _RecordingHomeRepository();
    final controller = HomeController(
      repository: repository,
      syncState: _syncState()..markCurrent(_syncedAt),
      now: () => now,
      timerFactory: (duration, callback) => _ManualTimer(duration, callback),
    );
    addTearDown(controller.dispose);

    await _pumpHome(tester, controller, resumeSignal: resumeSignal);
    expect(find.text('Gasto em agosto'), findsOneWidget);
    expect(find.text('R\$\u00a08,00'), findsOneWidget);

    now = DateTime(2026, 9, 1, 8);
    resumeSignal.value += 1;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(repository.requestedTimes.last, now);
    expect(find.text('Gasto em setembro'), findsOneWidget);
    expect(find.text('R\$\u00a09,00'), findsOneWidget);
    expect(find.text('R\$\u00a08,00'), findsNothing);
  });

  testWidgets('iOS usa pull-to-refresh Cupertino e executa retry', (
    tester,
  ) async {
    var retries = 0;
    final repository = _FakeHomeRepository(
      streams: {OwnerScopeKind.household: Stream.value(_snapshot())},
    );
    final controller = HomeController(
      repository: repository,
      syncState: SyncState(
        retry: () async {
          retries += 1;
          return SyncResult.current;
        },
      ),
      now: () => DateTime(2026, 8, 14, 12),
      timerFactory: (duration, callback) => _ManualTimer(duration, callback),
    );
    addTearDown(controller.dispose);

    await _pumpHome(tester, controller, platform: TargetPlatform.iOS);

    expect(
      Theme.of(tester.element(find.byType(HomeScreen))).platform,
      TargetPlatform.iOS,
    );
    final scroll = tester.widget<CustomScrollView>(
      find.byType(CustomScrollView),
    );
    expect(scroll.slivers.first, isA<CupertinoSliverRefreshControl>());
    expect(find.byType(RefreshIndicator), findsNothing);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 300));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(retries, 1);
  });

  testWidgets('tipo explícito distingue receita e despesa de valor zero', (
    tester,
  ) async {
    final repository = _FakeHomeRepository(
      streams: {
        OwnerScopeKind.household: Stream.value(
          _snapshot(
            transactions: <HomeTransaction>[
              HomeTransaction(
                uuid: '50000000-0000-4000-8000-000000000010',
                description: 'Ajuste positivo',
                categoryName: 'Receita',
                ownerName: 'Eu',
                date: DateTime(2026, 8, 14),
                type: HomeTransactionType.income,
                signedAmountMinor: 0,
              ),
              HomeTransaction(
                uuid: '50000000-0000-4000-8000-000000000011',
                description: 'Ajuste negativo',
                categoryName: 'Casa',
                ownerName: 'Eu',
                date: DateTime(2026, 8, 14),
                type: HomeTransactionType.expense,
                signedAmountMinor: 0,
              ),
            ],
          ),
        ),
      },
    );
    final controller = _controller(
      repository,
      syncState: _syncState()..markCurrent(_syncedAt),
    );
    addTearDown(controller.dispose);

    await _pumpHome(tester, controller);

    expect(
      find.bySemanticsLabel(RegExp(r'Ajuste positivo.*Receita.*R\$.*0,00')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'Ajuste negativo.*Despesa.*R\$.*0,00')),
      findsOneWidget,
    );
    final zeroAmountColors = tester
        .widgetList<FinancialAmount>(find.byType(FinancialAmount))
        .where((amount) => amount.minorUnits == 0)
        .map((amount) => amount.style?.color)
        .toList();
    expect(
      zeroAmountColors,
      containsAll(<Color>[
        LarColors.mineral,
        LarTheme.light.colorScheme.onSurface,
      ]),
    );
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
      timerFactory: (duration, callback) => _ManualTimer(duration, callback),
    );

Future<void> _pumpHome(
  WidgetTester tester,
  HomeController controller, {
  double textScale = 1,
  TargetPlatform platform = TargetPlatform.android,
  ValueNotifier<int>? resumeSignal,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 1200);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  Widget home = MediaQuery(
    data: MediaQueryData(
      size: const Size(390, 1200),
      textScaler: TextScaler.linear(textScale),
    ),
    child: HomeScreen(controller: controller),
  );
  if (resumeSignal != null) {
    home = AppResumeScope(notifier: resumeSignal, child: home);
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: LarTheme.light.copyWith(platform: platform),
      home: home,
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
          type: HomeTransactionType.expense,
          signedAmountMinor: -28640,
        ),
        HomeTransaction(
          uuid: '50000000-0000-4000-8000-000000000002',
          description: 'Salário',
          categoryName: 'Receita',
          ownerName: 'Eu',
          date: DateTime(2026, 8, 13),
          type: HomeTransactionType.income,
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

final class _RecordingHomeRepository implements HomeRepository {
  final List<DateTime> requestedTimes = <DateTime>[];

  @override
  Future<HomeOwnerScopes> readOwnerScopes() async => const HomeOwnerScopes(
    selfScope: OwnerScope.self(_selfUuid),
    spouseScope: OwnerScope.spouse(_spouseUuid),
  );

  @override
  Stream<HomeSnapshot> watchSnapshot(OwnerScope scope, DateTime now) {
    requestedTimes.add(now);
    return Stream<HomeSnapshot>.value(
      _snapshot(scope: scope, monthExpenseMinor: now.month * 100),
    );
  }
}

final class _ManualTimer implements Timer {
  _ManualTimer(this.duration, this._callback);

  final Duration duration;
  final VoidCallback _callback;
  bool _active = true;

  void fire() {
    if (!_active) return;
    _active = false;
    _callback();
  }

  @override
  bool get isActive => _active;

  @override
  int get tick => _active ? 0 : 1;

  @override
  void cancel() => _active = false;
}
