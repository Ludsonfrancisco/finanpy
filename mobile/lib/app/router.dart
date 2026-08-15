import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../design_system/components/sync_status.dart';
import '../design_system/lar_spacing.dart';
import '../core/sync/sync_coordinator.dart';
import '../core/sync/sync_state.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/auth/presentation/device_owner_screen.dart';
import '../features/auth/presentation/initial_sync_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/more_screen.dart';
import '../features/home/application/home_controller.dart';
import '../features/home/data/home_repository.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/imports/application/import_controller.dart';
import '../features/imports/data/import_repository.dart';
import '../features/imports/data/ofx_file_picker.dart';
import '../features/imports/presentation/import_screen.dart';
import 'adaptive_shell.dart';
import 'app_config.dart';
import 'privacy_shield.dart';
import 'value_visibility_controller.dart';

GoRouter createAppRouter(
  AppConfig config,
  AuthController authController, {
  LedgerSyncCoordinator? syncCoordinator,
  HomeRepository? homeRepository,
  ValueVisibilityController? valueVisibilityController,
  ImportRepository? importRepository,
  OfxFilePicker? ofxFilePicker,
}) {
  config.validate();
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
          final index = state.uri.path.startsWith('/more') ? 1 : 0;
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
              onSelect: (value) => context.go(value == 0 ? '/home' : '/more'),
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
            path: '/more',
            builder: (context, state) => MoreScreen(
              onOpenImport: importRepository == null
                  ? null
                  : () => context.go('/more/import-ofx'),
            ),
            routes: <RouteBase>[
              GoRoute(
                path: 'import-ofx',
                builder: (context, state) => importRepository == null
                    ? const _RouteNotice(title: 'Importação OFX')
                    : _ImportShell(
                        repository: importRepository,
                        picker: ofxFilePicker ?? FilePickerOfxPicker(),
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

/// Hosts the import controller for the route. Task 6 replaces the body with
/// the Casa de Valores screen; the ownership of the controller stays here.
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
        oldWidget.picker == widget.picker &&
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
