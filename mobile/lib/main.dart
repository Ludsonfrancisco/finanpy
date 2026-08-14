import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';

import 'app/app_config.dart';
import 'app/router.dart';
import 'core/network/dio_transport.dart';
import 'core/network/session_transport.dart';
import 'core/storage/app_database.dart';
import 'design_system/lar_theme.dart';
import 'features/auth/application/auth_controller.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/data/secure_token_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment();
  config.validate();
  final database = AppDatabase(driftDatabase(name: 'lar_finance'));
  final tokenStore = SecureTokenStore(const FlutterSecureStorage());
  final transport = DioTransport(baseUrl: config.normalizedApiBaseUrl);
  final repository = AuthRepository(
    publicTransport: transport,
    sessionTransport: SessionTransport(
      transport: transport,
      tokenStore: tokenStore,
    ),
    tokenStore: tokenStore,
    database: database,
  );
  final controller = AuthController(repository);
  await controller.initialize();
  runApp(MyApp(appConfig: config, authController: controller));
}

class MyApp extends StatelessWidget {
  MyApp({super.key, required this.authController, AppConfig? appConfig})
    : appConfig = appConfig ?? AppConfig.fromEnvironment(),
      router = createAppRouter(
        appConfig ?? AppConfig.fromEnvironment(),
        authController,
      );

  final AppConfig appConfig;
  final AuthController authController;
  final GoRouter router;

  @override
  Widget build(BuildContext context) => ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(
        (ref) => authController,
        disposeNotifier: false,
      ),
    ],
    child: MaterialApp.router(
      title: 'Lar Finance',
      theme: LarTheme.light,
      darkTheme: LarTheme.dark,
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
    ),
  );
}
