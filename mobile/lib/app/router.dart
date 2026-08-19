import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../design_system/components/sync_status.dart';
import '../design_system/lar_spacing.dart';
import '../core/sync/sync_coordinator.dart';
import '../core/sync/sync_state.dart';
import '../features/accounts/application/accounts_controller.dart';
import '../features/accounts/data/accounts_repository.dart';
import '../features/accounts/presentation/accounts_screen.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/auth/presentation/device_owner_screen.dart';
import '../features/auth/presentation/initial_sync_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/more_screen.dart';
import '../features/bills/application/bills_controller.dart';
import '../features/bills/data/bills_repository.dart';
import '../features/bills/presentation/bills_screen.dart';
import '../features/cards/application/cards_controller.dart';
import '../features/cards/data/cards_repository.dart';
import '../features/cards/presentation/cards_screen.dart';
import '../features/categories/application/categories_controller.dart';
import '../features/categories/data/categories_repository.dart';
import '../features/categories/presentation/categories_screen.dart';
import '../features/home/application/home_controller.dart';
import '../features/home/data/home_repository.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/imports/application/import_controller.dart';
import '../features/imports/data/import_repository.dart';
import '../features/imports/data/ofx_file_picker.dart';
import '../features/imports/presentation/import_screen.dart';
import '../features/reports/application/reports_controller.dart';
import '../features/reports/data/reports_repository.dart';
import '../features/reports/presentation/reports_screen.dart';
import '../features/transactions/application/transactions_controller.dart';
import '../features/transactions/data/transactions_repository.dart';
import '../features/transactions/presentation/transactions_screen.dart';
import 'adaptive_shell.dart';
import 'app_config.dart';
import 'privacy_shield.dart';
import 'value_visibility_controller.dart';

GoRouter createAppRouter(
  AppConfig config,
  AuthController authController, {
  LedgerSyncCoordinator? syncCoordinator,
  HomeRepository? homeRepository,
  AccountsRepository? accountsRepository,
  TransactionsRepository? transactionsRepository,
  CategoriesRepository? categoriesRepository,
  ReportsRepository? reportsRepository,
  BillsRepository? billsRepository,
  CardsRepository? cardsRepository,
  ValueVisibilityController? valueVisibilityController,
  ImportRepository? importRepository,
  OfxFilePicker? ofxFilePicker,
}) {
  config.validate();
  final picker = ofxFilePicker ?? FilePickerOfxPicker();
  return GoRouter(
    initialLocation: '/login',
    refreshListenable: authController,
    redirect: (context, state) {
      final path = state.uri.path;
      return switch (authController.state.phase) {
        AuthPhase.checking => path == '/login' ? null : '/login',
        AuthPhase.signedOut => path == '/login' ? null : '/login',
        AuthPhase.choosingOwner =>
          path == '/device-owner' ? null : '/device-owner',
        AuthPhase.initialSync =>
          path == '/initial-sync' ? null : '/initial-sync',
        AuthPhase.authenticated =>
          path == '/login' || path == '/device-owner' || path == '/initial-sync'
              ? '/home'
              : null,
      };
    },
    routes: <RouteBase>[
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/device-owner',
        builder: (context, state) => const DeviceOwnerScreen(),
      ),
      GoRoute(
        path: '/initial-sync',
        builder: (context, state) => syncCoordinator == null
            ? const _RouteNotice(title: 'Preparando dados')
            : InitialSyncScreen(
                coordinator: syncCoordinator,
                onReady: authController.completeInitialSync,
              ),
      ),
      ShellRoute(
        builder: (context, state, child) {
          final path = state.uri.path;
          final int index;
          if (path.startsWith('/transactions')) {
            index = 1;
          } else if (path.startsWith('/accounts')) {
            index = 2;
          } else if (path.startsWith('/more')) {
            index = 3;
          } else {
            index = 0;
          }
          return PrivacyShield(
            onInactive: valueVisibilityController
                ?.protectBeforeFirstReadForInactiveReturn,
            onResumed: valueVisibilityController == null
                ? null
                : () => valueVisibilityController.restore(
                    returningFromInactive: true,
                  ),
            child: AdaptiveShell(
              selectedIndex: index,
              onSelect: (value) => context.go(switch (value) {
                1 => '/transactions',
                2 => '/accounts',
                3 => '/more',
                _ => '/home',
              }),
              child: child,
            ),
          );
        },
        routes: <RouteBase>[
          GoRoute(
            path: '/home',
            builder: (context, state) => _HomeShell(
              syncCoordinator: syncCoordinator,
              homeRepository: homeRepository,
              valueVisibilityController: valueVisibilityController,
            ),
          ),
          GoRoute(
            path: '/transactions',
            builder: (context, state) => _TransactionsShell(
              syncCoordinator: syncCoordinator,
              transactionsRepository: transactionsRepository,
              valueVisibilityController: valueVisibilityController,
              onOpenImport: () => context.go('/more/import-ofx'),
            ),
          ),
          GoRoute(
            path: '/accounts',
            builder: (context, state) => _AccountsShell(
              syncCoordinator: syncCoordinator,
              accountsRepository: accountsRepository,
              valueVisibilityController: valueVisibilityController,
              onOpenImport: () => context.go('/more/import-ofx'),
            ),
          ),
          GoRoute(
            path: '/categories',
            builder: (context, state) => _CategoriesShell(
              syncCoordinator: syncCoordinator,
              categoriesRepository: categoriesRepository,
            ),
          ),
          GoRoute(
            path: '/reports',
            builder: (context, state) => _ReportsShell(
              syncCoordinator: syncCoordinator,
              reportsRepository: reportsRepository,
            ),
          ),
          GoRoute(
            path: '/bills',
            builder: (context, state) => _BillsShell(
              billsRepository: billsRepository,
              accountsRepository: accountsRepository,
            ),
          ),
          GoRoute(
            path: '/cards',
            builder: (context, state) => _CardsShell(
              cardsRepository: cardsRepository,
              accountsRepository: accountsRepository,
              categoriesRepository: categoriesRepository,
            ),
          ),
          GoRoute(
            path: '/more',
            builder: (context, state) => MoreScreen(
              onOpenBills: () => context.go('/bills'),
              onOpenCards: () => context.go('/cards'),
              onOpenImport: importRepository == null
                  ? null
                  : () => context.go('/more/import-ofx'),
              onOpenCategories: () => context.go('/categories'),
              onOpenReports: () => context.go('/reports'),
            ),
            routes: <RouteBase>[
              GoRoute(
                path: 'import-ofx',
                builder: (context, state) => importRepository == null
                    ? const _RouteNotice(title: 'Importação OFX')
                    : _ImportShell(
                        repository: importRepository,
                        picker: picker,
                        syncCoordinator: syncCoordinator,
                      ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

final class _HomeShell extends StatefulWidget {
  const _HomeShell({
    required this.syncCoordinator,
    required this.homeRepository,
    required this.valueVisibilityController,
  });

  final LedgerSyncCoordinator? syncCoordinator;
  final HomeRepository? homeRepository;
  final ValueVisibilityController? valueVisibilityController;

  @override
  State<_HomeShell> createState() => _HomeShellState();
}

final class _HomeShellState extends State<_HomeShell> {
  HomeController? _controller;

  @override
  void initState() {
    super.initState();
    _createController();
  }

  @override
  void didUpdateWidget(_HomeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.syncCoordinator == widget.syncCoordinator &&
        oldWidget.homeRepository == widget.homeRepository) {
      return;
    }
    _controller?.dispose();
    _createController();
  }

  void _createController() {
    final repository = widget.homeRepository;
    final coordinator = widget.syncCoordinator;
    _controller = repository == null || coordinator == null
        ? null
        : HomeController(repository: repository, syncState: coordinator.state);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller != null) {
      return HomeScreen(
        controller: controller,
        visibilityController: widget.valueVisibilityController,
      );
    }
    final text = Theme.of(context).textTheme;
    final coordinator = widget.syncCoordinator;
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          if (coordinator != null) await coordinator.synchronize();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Padding(
                padding: const EdgeInsets.all(LarSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('CASA DE VALORES', style: text.labelLarge),
                    const SizedBox(height: LarSpacing.xs),
                    Text('Início', style: text.headlineMedium),
                    const SizedBox(height: LarSpacing.lg),
                    if (coordinator == null)
                      const SyncStatusView(
                        data: SyncStatusData(
                          state: SyncVisualState.offline,
                          lastSuccessAt: null,
                        ),
                      )
                    else
                      AnimatedBuilder(
                        animation: coordinator.state,
                        builder: (context, _) => SyncStatusView(
                          data: SyncStatusData(
                            state: _visualState(coordinator.state.phase),
                            lastSuccessAt: coordinator.state.timestamp,
                          ),
                        ),
                      ),
                    const SizedBox(height: LarSpacing.lg),
                    Text(
                      'Dados ainda não sincronizados',
                      style: text.titleLarge,
                    ),
                    const SizedBox(height: LarSpacing.sm),
                    Text(
                      'Quando a primeira sincronização estiver disponível, a visão financeira aparecerá aqui.',
                      style: text.bodyLarge,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

SyncVisualState _visualState(SyncPhase phase) => switch (phase) {
  SyncPhase.idle => SyncVisualState.offline,
  SyncPhase.syncing => SyncVisualState.syncing,
  SyncPhase.current => SyncVisualState.current,
  SyncPhase.offline => SyncVisualState.offline,
  SyncPhase.failed => SyncVisualState.failed,
};

final class _AccountsShell extends StatefulWidget {
  const _AccountsShell({
    required this.syncCoordinator,
    required this.accountsRepository,
    required this.valueVisibilityController,
    required this.onOpenImport,
  });

  final LedgerSyncCoordinator? syncCoordinator;
  final AccountsRepository? accountsRepository;
  final ValueVisibilityController? valueVisibilityController;
  final VoidCallback onOpenImport;

  @override
  State<_AccountsShell> createState() => _AccountsShellState();
}

final class _AccountsShellState extends State<_AccountsShell> {
  AccountsController? _controller;

  @override
  void initState() {
    super.initState();
    _createController();
  }

  @override
  void didUpdateWidget(_AccountsShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.syncCoordinator == widget.syncCoordinator &&
        oldWidget.accountsRepository == widget.accountsRepository) {
      return;
    }
    _controller?.dispose();
    _createController();
  }

  void _createController() {
    final repository = widget.accountsRepository;
    final coordinator = widget.syncCoordinator;
    _controller = repository == null || coordinator == null
        ? null
        : AccountsController(
            repository: repository,
            syncState: coordinator.state,
          );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller != null) {
      return AccountsScreen(
        controller: controller,
        visibilityController: widget.valueVisibilityController,
        onOpenImport: widget.onOpenImport,
      );
    }
    return const _RouteNotice(title: 'Contas');
  }
}

final class _TransactionsShell extends StatefulWidget {
  const _TransactionsShell({
    required this.syncCoordinator,
    required this.transactionsRepository,
    required this.valueVisibilityController,
    required this.onOpenImport,
  });

  final LedgerSyncCoordinator? syncCoordinator;
  final TransactionsRepository? transactionsRepository;
  final ValueVisibilityController? valueVisibilityController;
  final VoidCallback onOpenImport;

  @override
  State<_TransactionsShell> createState() => _TransactionsShellState();
}

final class _TransactionsShellState extends State<_TransactionsShell> {
  TransactionsController? _controller;

  @override
  void initState() {
    super.initState();
    _createController();
  }

  @override
  void didUpdateWidget(_TransactionsShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.syncCoordinator == widget.syncCoordinator &&
        oldWidget.transactionsRepository == widget.transactionsRepository) {
      return;
    }
    _controller?.dispose();
    _createController();
  }

  void _createController() {
    final repository = widget.transactionsRepository;
    final coordinator = widget.syncCoordinator;
    _controller = repository == null || coordinator == null
        ? null
        : TransactionsController(
            repository: repository,
            syncState: coordinator.state,
          );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller != null) {
      return TransactionsScreen(
        controller: controller,
        visibilityController: widget.valueVisibilityController,
        onOpenImport: widget.onOpenImport,
      );
    }
    return const _RouteNotice(title: 'Movimentações');
  }
}

final class _ImportShell extends StatefulWidget {
  const _ImportShell({
    required this.repository,
    required this.picker,
    required this.syncCoordinator,
  });

  final ImportRepository repository;
  final OfxFilePicker picker;
  final LedgerSyncCoordinator? syncCoordinator;

  @override
  State<_ImportShell> createState() => _ImportShellState();
}

final class _ImportShellState extends State<_ImportShell> {
  late ImportController _controller;

  @override
  void initState() {
    super.initState();
    _controller = _createController();
  }

  @override
  void didUpdateWidget(_ImportShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository == widget.repository &&
        oldWidget.syncCoordinator == widget.syncCoordinator) {
      return;
    }
    _controller.dispose();
    _controller = _createController();
  }

  ImportController _createController() {
    final coordinator = widget.syncCoordinator;
    return ImportController(
      picker: widget.picker,
      repository: widget.repository,
      synchronize: coordinator == null
          ? () async {}
          : () async => coordinator.synchronize(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) => ImportScreen(
      state: _controller.state,
      onSelect: () => unawaited(_controller.selectFile()),
      onConfirm: () => unawaited(_controller.confirm()),
      onCancel: () => unawaited(_controller.cancel()),
      onRetry: () => unawaited(_controller.retry()),
      onLoadMore: () => unawaited(_controller.loadMore()),
    ),
  );
}

final class _CategoriesShell extends StatefulWidget {
  const _CategoriesShell({
    required this.syncCoordinator,
    required this.categoriesRepository,
  });

  final LedgerSyncCoordinator? syncCoordinator;
  final CategoriesRepository? categoriesRepository;

  @override
  State<_CategoriesShell> createState() => _CategoriesShellState();
}

final class _CategoriesShellState extends State<_CategoriesShell> {
  CategoriesController? _controller;

  @override
  void initState() {
    super.initState();
    _createController();
  }

  @override
  void didUpdateWidget(_CategoriesShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.syncCoordinator == widget.syncCoordinator &&
        oldWidget.categoriesRepository == widget.categoriesRepository) {
      return;
    }
    _controller?.dispose();
    _createController();
  }

  void _createController() {
    final repository = widget.categoriesRepository;
    final coordinator = widget.syncCoordinator;
    _controller = repository == null || coordinator == null
        ? null
        : CategoriesController(
            repository: repository,
            syncState: coordinator.state,
          );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller != null) {
      return CategoriesScreen(controller: controller);
    }
    return const _RouteNotice(title: 'Categorias');
  }
}

final class _ReportsShell extends StatefulWidget {
  const _ReportsShell({
    required this.syncCoordinator,
    required this.reportsRepository,
  });

  final LedgerSyncCoordinator? syncCoordinator;
  final ReportsRepository? reportsRepository;

  @override
  State<_ReportsShell> createState() => _ReportsShellState();
}

final class _ReportsShellState extends State<_ReportsShell> {
  ReportsController? _controller;

  @override
  void initState() {
    super.initState();
    _createController();
  }

  @override
  void didUpdateWidget(_ReportsShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.syncCoordinator == widget.syncCoordinator &&
        oldWidget.reportsRepository == widget.reportsRepository) {
      return;
    }
    _controller?.dispose();
    _createController();
  }

  void _createController() {
    final repository = widget.reportsRepository;
    final coordinator = widget.syncCoordinator;
    _controller = repository == null || coordinator == null
        ? null
        : ReportsController(
            repository: repository,
            syncState: coordinator.state,
          );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller != null) {
      return ReportsScreen(controller: controller);
    }
    return const _RouteNotice(title: 'Relatórios & Gráficos');
  }
}

final class _BillsShell extends StatefulWidget {
  const _BillsShell({
    required this.billsRepository,
    required this.accountsRepository,
  });

  final BillsRepository? billsRepository;
  final AccountsRepository? accountsRepository;

  @override
  State<_BillsShell> createState() => _BillsShellState();
}

final class _BillsShellState extends State<_BillsShell> {
  BillsController? _controller;

  @override
  void initState() {
    super.initState();
    _createController();
  }

  @override
  void didUpdateWidget(_BillsShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.billsRepository == widget.billsRepository) {
      return;
    }
    _controller?.dispose();
    _createController();
  }

  void _createController() {
    final repository = widget.billsRepository;
    _controller = repository == null
        ? null
        : BillsController(
            repository: repository,
          );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller != null) {
      return BillsScreen(
        controller: controller,
        accountsRepository: widget.accountsRepository,
      );
    }
    return const _RouteNotice(title: 'Contas Fixas & Vencimentos');
  }
}

final class _CardsShell extends StatefulWidget {
  const _CardsShell({
    required this.cardsRepository,
    required this.accountsRepository,
    required this.categoriesRepository,
  });

  final CardsRepository? cardsRepository;
  final AccountsRepository? accountsRepository;
  final CategoriesRepository? categoriesRepository;

  @override
  State<_CardsShell> createState() => _CardsShellState();
}

final class _CardsShellState extends State<_CardsShell> {
  CardsController? _controller;

  @override
  void initState() {
    super.initState();
    _createController();
  }

  @override
  void didUpdateWidget(_CardsShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cardsRepository == widget.cardsRepository) {
      return;
    }
    _controller?.dispose();
    _createController();
  }

  void _createController() {
    final repository = widget.cardsRepository;
    _controller = repository == null
        ? null
        : CardsController(
            repository: repository,
          );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller != null) {
      return CardsScreen(
        controller: controller,
        accountsRepository: widget.accountsRepository,
        categoriesRepository: widget.categoriesRepository,
      );
    }
    return const _RouteNotice(title: 'Cartões de Crédito & Faturas');
  }
}

final class _RouteNotice extends StatelessWidget {
  const _RouteNotice({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(LarSpacing.xl),
      child: Text(title, style: Theme.of(context).textTheme.headlineMedium),
    ),
  );
}
