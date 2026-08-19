import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/app_config.dart';
import 'app/app_lifecycle.dart';
import 'app/router.dart';
import 'app/value_visibility_controller.dart';
import 'core/network/dio_transport.dart';
import 'core/network/session_transport.dart';
import 'core/storage/app_database.dart';
import 'core/storage/local_ledger.dart';
import 'core/sync/sync_api.dart';
import 'core/sync/sync_coordinator.dart';
import 'design_system/lar_theme.dart';
import 'features/accounts/data/accounts_repository.dart';
import 'features/auth/application/auth_controller.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/data/secure_token_store.dart';
import 'features/auth/domain/session.dart';
import 'features/bills/data/bills_repository.dart';
import 'features/categories/data/categories_repository.dart';
import 'features/home/data/home_repository.dart';
import 'features/imports/data/import_repository.dart';
import 'features/imports/data/ofx_file_picker.dart';
import 'features/reports/data/reports_repository.dart';
import 'features/transactions/data/transactions_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR');
  final config = AppConfig.fromEnvironment();
  config.validate();
  final database = AppDatabase(driftDatabase(name: 'lar_finance'));
  final valueVisibilityController = ValueVisibilityController(
    DriftValueVisibilityRepository(database),
  );
  await valueVisibilityController.restore(returningFromInactive: false);
  final tokenStore = SecureTokenStore(const FlutterSecureStorage());
  final sessionAuthority = SessionAuthority.forStore(tokenStore);
  final transport = DioTransport(baseUrl: config.normalizedApiBaseUrl);
  final sessionTransport = SessionTransport(
    transport: transport,
    tokenStore: tokenStore,
    sessionAuthority: sessionAuthority,
  );
  final repository = AuthRepository(
    publicTransport: transport,
    sessionTransport: sessionTransport,
    tokenStore: tokenStore,
    sessionAuthority: sessionAuthority,
    database: database,
  );
  final controller = AuthController(
    repository,
    sessionAuthority: sessionAuthority,
  );
  await controller.initialize();
  final syncCoordinator = LedgerSyncCoordinator(
    api: DjangoSyncApi(sessionTransport),
    ledger: DriftLocalLedger(database),
    sessionAuthority: sessionAuthority,
    onSessionExpired: controller.expireSession,
  );
  final homeRepository = DriftHomeRepository(database);
  final accountsRepository = DriftAccountsRepository(database);
  final transactionsRepository = DriftTransactionsRepository(database);
  final categoriesRepository = DriftCategoriesRepository(database);
  final reportsRepository = DriftReportsRepository(database);
  final importRepository = DjangoImportRepository(sessionTransport);
  final billsRepository = HttpBillsRepository(sessionTransport);
  runApp(
    MyApp(
      appConfig: config,
      authController: controller,
      syncCoordinator: syncCoordinator,
      homeRepository: homeRepository,
      accountsRepository: accountsRepository,
      transactionsRepository: transactionsRepository,
      categoriesRepository: categoriesRepository,
      reportsRepository: reportsRepository,
      billsRepository: billsRepository,
      valueVisibilityController: valueVisibilityController,
      importRepository: importRepository,
    ),
  );
}

class MyApp extends StatelessWidget {
  MyApp({
    super.key,
    required this.authController,
    this.syncCoordinator,
    this.homeRepository,
    this.accountsRepository,
    this.transactionsRepository,
    this.categoriesRepository,
    this.reportsRepository,
    this.billsRepository,
    this.valueVisibilityController,
    this.importRepository,
    this.ofxFilePicker,
    AppConfig? appConfig,
  }) : appConfig = appConfig ?? AppConfig.fromEnvironment(),
       router = createAppRouter(
         appConfig ?? AppConfig.fromEnvironment(),
         authController,
         syncCoordinator: syncCoordinator,
         homeRepository: homeRepository,
         accountsRepository: accountsRepository,
         transactionsRepository: transactionsRepository,
         categoriesRepository: categoriesRepository,
         reportsRepository: reportsRepository,
         billsRepository: billsRepository,
         valueVisibilityController: valueVisibilityController,
         importRepository: importRepository,
         ofxFilePicker: ofxFilePicker,
       );

  final AppConfig appConfig;
  final AuthController authController;
  final LedgerSyncCoordinator? syncCoordinator;
  final HomeRepository? homeRepository;
  final AccountsRepository? accountsRepository;
  final TransactionsRepository? transactionsRepository;
  final CategoriesRepository? categoriesRepository;
  final ReportsRepository? reportsRepository;
  final BillsRepository? billsRepository;
  final ValueVisibilityController? valueVisibilityController;
  final ImportRepository? importRepository;
  final OfxFilePicker? ofxFilePicker;
  final GoRouter router;

  @override
  Widget build(BuildContext context) {
    final app = MaterialApp.router(
      title: 'Lar Finance',
      theme: LarTheme.light,
      darkTheme: LarTheme.dark,
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
    );
    final coordinator = syncCoordinator;
    return ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(
          (ref) => authController,
          disposeNotifier: false,
        ),
        if (valueVisibilityController != null)
          valueVisibilityControllerProvider.overrideWith(
            (ref) => valueVisibilityController!,
            disposeNotifier: false,
          ),
      ],
      child: coordinator == null
          ? app
          : AppSyncLifecycle(
              coordinator: coordinator,
              isAuthenticated: () =>
                  authController.state.phase == AuthPhase.authenticated,
              child: app,
            ),
    );
  }
}
