import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../design_system/components/owner_selector.dart';
import '../design_system/components/sync_status.dart';
import '../design_system/lar_spacing.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/auth/presentation/device_owner_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/more_screen.dart';
import 'adaptive_shell.dart';
import 'app_config.dart';

GoRouter createAppRouter(AppConfig config, AuthController authController) {
  config.validate();
  return GoRouter(
    initialLocation: '/login',
    refreshListenable: authController,
    redirect: (context, state) {
      final path = state.uri.path;
      return switch (authController.state.phase) {
        AuthPhase.checking => null,
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
        builder: (context, state) =>
            const _RouteNotice(title: 'Preparando dados'),
      ),
      ShellRoute(
        builder: (context, state, child) {
          final index = state.uri.path == '/more' ? 1 : 0;
          return AdaptiveShell(
            selectedIndex: index,
            onSelect: (value) => context.go(value == 0 ? '/home' : '/more'),
            child: child,
          );
        },
        routes: <RouteBase>[
          GoRoute(
            path: '/home',
            builder: (context, state) => const _HomeShell(),
          ),
          GoRoute(
            path: '/more',
            builder: (context, state) => const MoreScreen(),
          ),
        ],
      ),
    ],
  );
}

final class _HomeShell extends StatefulWidget {
  const _HomeShell();
  @override
  State<_HomeShell> createState() => _HomeShellState();
}

final class _HomeShellState extends State<_HomeShell> {
  int owner = 0;
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: SingleChildScrollView(
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
                  const SyncStatusView(
                    data: SyncStatusData(
                      state: SyncVisualState.offline,
                      lastSuccessAt: null,
                    ),
                  ),
                  const SizedBox(height: LarSpacing.lg),
                  OwnerSelector(
                    selected: owner,
                    onSelected: (value) => setState(() => owner = value),
                  ),
                  const SizedBox(height: LarSpacing.xxl),
                  Text('Dados ainda não sincronizados', style: text.titleLarge),
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
    );
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
