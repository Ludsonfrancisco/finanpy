import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lar_finance/design_system/lar_theme.dart';
import 'package:lar_finance/features/accounts/data/accounts_repository.dart';
import 'package:lar_finance/features/accounts/domain/accounts_models.dart';
import 'package:lar_finance/features/accounts/presentation/widgets/account_form_sheet.dart';
import 'package:lar_finance/features/home/domain/home_snapshot.dart';
import 'package:lar_finance/features/transactions/domain/transactions_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockAccountsRepository mockRepo;

  setUp(() {
    mockRepo = _MockAccountsRepository();
  });

  Widget buildTestApp({VoidCallback? onSaved}) {
    return MaterialApp(
      theme: LarTheme.light,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('pt', 'BR')],
      home: Scaffold(
        body: AccountFormSheet(repository: mockRepo, onSaved: onSaved),
      ),
    );
  }

  testWidgets('AccountFormSheet renders fields and validates empty name', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(buildTestApp());
    await tester.pumpAndSettle();

    expect(find.text('Nova Conta Bancária'), findsOneWidget);
    expect(find.text('Criar Conta'), findsOneWidget);

    await tester.ensureVisible(find.text('Criar Conta'));
    await tester.tap(find.text('Criar Conta'));
    await tester.pumpAndSettle();

    expect(find.text('Informe o nome da conta'), findsOneWidget);
  });

  testWidgets('AccountFormSheet creates a new account on valid submit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    var saved = false;
    await tester.pumpWidget(buildTestApp(onSaved: () => saved = true));
    await tester.pumpAndSettle();

    // Fill name and balance
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Ex: Nubank, Itaú Corrente, Carteira'),
      'Itaú Personalité',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '0,00'),
      '1500,00',
    );

    await tester.ensureVisible(find.text('Criar Conta'));
    await tester.tap(find.text('Criar Conta'));
    await tester.pumpAndSettle();

    expect(mockRepo.createdAccounts, hasLength(1));
    expect(mockRepo.createdAccounts.first['name'], 'Itaú Personalité');
    expect(mockRepo.createdAccounts.first['initialBalanceMinor'], 150000);
    expect(saved, isTrue);
  });
}

final class _MockAccountsRepository implements AccountsRepository {
  final List<Map<String, Object?>> createdAccounts = [];

  @override
  Future<HomeOwnerScopes> readOwnerScopes() async {
    return const HomeOwnerScopes(
      selfScope: OwnerScope.self('owner-1'),
      spouseScope: OwnerScope.spouse('owner-2'),
    );
  }

  @override
  Stream<AccountsSnapshot> watchAccounts(OwnerScope scope) {
    return Stream.value(
      AccountsSnapshot(
        scope: scope,
        accounts: const [],
        totalBalanceMinor: 0,
        lastSyncedAt: null,
        hasAccountData: false,
      ),
    );
  }

  @override
  Future<List<TransactionOwnerOption>> readAvailableOwners() async {
    return const [
      TransactionOwnerOption(uuid: 'owner-1', name: 'Ludson', type: 'self'),
    ];
  }

  @override
  Future<String> createAccount({
    required String name,
    required AccountType type,
    required int initialBalanceMinor,
    required String financialOwnerUuid,
  }) async {
    createdAccounts.add({
      'name': name,
      'type': type,
      'initialBalanceMinor': initialBalanceMinor,
      'financialOwnerUuid': financialOwnerUuid,
    });
    return 'acc-created-uuid';
  }
}
