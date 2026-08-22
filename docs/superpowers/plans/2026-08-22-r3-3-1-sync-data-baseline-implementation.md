# R3.3.1 Sync, Data Parity, and Baseline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove that Web and Flutter compare the same current household data, fix the stale sync timestamp shown on Windows, identify the exact installed client build, and establish privacy-safe visual baselines before the shared shell redesign.

**Architecture:** Preserve the existing Django API, Flutter sync coordinator, Drift ledger, and automatic sync triggers. Make the Flutter `Mais` screen observe the existing live `SyncState` instead of the authentication snapshot, add an immutable build identifier through compile-time configuration, document the already-available financial fields, and validate Web/Windows with the same scope. No new sync protocol, database table, analytics service, or endpoint is introduced.

**Tech Stack:** Python 3.11.9, Django 5.2.13, Flutter 3.47.0, Dart 3.13.0, Riverpod 3.4.2, GoRouter 17.3.0, Drift 2.34.3, GitHub Actions, Windows PowerShell.

## Global Constraints

- Work only on Sprint R3.3.1; do not start the shell or visual redesign from R3.3.2.
- Use the same login, household, owner scope, period, and sync timestamp when comparing clients.
- Keep `design/tokens.json` untouched; this sprint validates data and references, not visual tokens.
- Do not change the Django sync contract, cursor semantics, local schema, or financial calculations.
- Do not add a monitoring vendor, logging SDK, package dependency, queue, or second sync mechanism.
- Never display or record access tokens, refresh tokens, session identity, full device UUID, account identifiers, or private financial payloads.
- The GitHub repository is public; real financial screenshots stay only in ignored `screenshots/` and are never staged.
- Synthetic Flutter goldens may remain versioned because they contain no personal data.
- Every task follows RED/GREEN when code changes, ends with focused verification, commit, and push.
- Stop after each task for review; stop again after Sprint R3.3.1 and request authorization before R3.3.2.

---

## File Structure

| File | Responsibility in this sprint |
|---|---|
| `mobile/lib/features/auth/presentation/more_screen.dart` | render the live synchronization timestamp and safe build/server identity |
| `mobile/lib/app/router.dart` | inject the existing `SyncState` and immutable `AppConfig` values into `MoreScreen` |
| `mobile/lib/app/app_config.dart` | expose compile-time client SHA and normalized server host |
| `mobile/test/features/auth/device_owner_screen_test.dart` | regress the stale timestamp and verify safe diagnostic copy |
| `mobile/test/app/app_config_test.dart` | verify build-label normalization and host extraction |
| `mobile/test/tool/task9_configuration_test.dart` | require the client SHA in all three release builds |
| `.github/workflows/ci.yml` | embed the exact Git commit in Windows, Android, and iOS artifacts |
| `docs/audits/2026-08-22-r3-3-1-sync-data-baseline.md` | record code-backed field availability and sanitized runtime evidence |
| `docs/superpowers/specs/2026-08-22-web-structure-flutter-casa-de-valores-design.md` | resolve the two R3.3.1 investigation markers |
| `docs/ROADMAP.md` | record the R3.3 umbrella and the completed gate without changing later tasks |

---

### Task 1: Make the Windows sync timestamp live

**Files:**
- Modify: `mobile/lib/features/auth/presentation/more_screen.dart`
- Modify: `mobile/lib/app/router.dart`
- Modify: `mobile/test/features/auth/device_owner_screen_test.dart`

**Interfaces:**
- Consumes: existing `SyncState.phase`, `SyncState.timestamp`, `AuthController.state.lastSyncAt`, and `LedgerSyncCoordinator.state`.
- Produces: `MoreScreen({SyncState? syncState, ...})`; the live timestamp wins when available, and the authentication snapshot remains the fallback for isolated tests or unavailable sync wiring.

- [ ] **Step 1: Write the failing reactive timestamp test**

Add these imports to `mobile/test/features/auth/device_owner_screen_test.dart`:

```dart
import 'package:lar_finance/core/sync/sync_models.dart';
import 'package:lar_finance/core/sync/sync_state.dart';
```

Add this test beside the existing `More shows local device status` test:

```dart
testWidgets('More follows the live sync timestamp after authentication', (
  tester,
) async {
  final controller = AuthController(_FakeAuthGateway());
  await controller.login(email: 'ana@example.com', password: 'secret');
  final syncState = SyncState(retry: () async => SyncResult.current)
    ..markCurrent(DateTime(2030, 8, 15, 11, 45));

  await tester.pumpWidget(
    _screenApp(controller, MoreScreen(syncState: syncState)),
  );

  expect(find.text('15/08/2030, 11:45'), findsOneWidget);
  expect(find.text('14/08/2030, 10:30'), findsNothing);

  syncState.markCurrent(DateTime(2030, 8, 15, 12, 5));
  await tester.pump();

  expect(find.text('15/08/2030, 12:05'), findsOneWidget);
  expect(find.text('15/08/2030, 11:45'), findsNothing);
});
```

- [ ] **Step 2: Run the focused test and verify RED**

```powershell
Set-Location mobile
flutter test test/features/auth/device_owner_screen_test.dart --plain-name "More follows the live sync timestamp after authentication"
```

Expected: FAIL because `MoreScreen` does not accept `syncState` and still reads only `AuthState.lastSyncAt`.

- [ ] **Step 3: Add the optional live state to `MoreScreen`**

Add the import and constructor field:

```dart
import '../../../core/sync/sync_state.dart';

const MoreScreen({
  this.syncState,
  this.onOpenBills,
  this.onOpenCards,
  this.onOpenImport,
  this.onOpenCategories,
  this.onOpenReports,
  super.key,
});

final SyncState? syncState;
```

Replace the current `build` method with this complete implementation:

```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  final controller = ref.watch(authControllerProvider);
  final liveState = syncState;
  Widget content() {
    final state = controller.state;
    final lastSyncAt = liveState?.timestamp ?? state.lastSyncAt;
    final lastSync = lastSyncAt == null
        ? 'Ainda não sincronizado'
        : DateFormat('dd/MM/yyyy, HH:mm').format(lastSyncAt.toLocal());
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(LarSpacing.xl),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text('Mais', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: LarSpacing.lg),
                Text(
                  'Dispositivo',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: LarSpacing.sm),
                Text(state.deviceName),
                const SizedBox(height: LarSpacing.lg),
                Text(
                  'Última sincronização',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: LarSpacing.xs),
                Text(lastSync),
                if (onOpenBills != null ||
                    onOpenCards != null ||
                    onOpenReports != null ||
                    onOpenCategories != null ||
                    onOpenImport != null) ...<Widget>[
                  const SizedBox(height: LarSpacing.xl),
                  Text(
                    'Cadastros & Ferramentas',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (onOpenCards != null) ...[
                    const SizedBox(height: LarSpacing.sm),
                    OutlinedButton.icon(
                      onPressed: onOpenCards,
                      icon: const Icon(Icons.credit_card_outlined),
                      label: const Text('Cartões de Crédito & Faturas'),
                    ),
                  ],
                  if (onOpenBills != null) ...[
                    const SizedBox(height: LarSpacing.sm),
                    OutlinedButton.icon(
                      onPressed: onOpenBills,
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: const Text('Contas Fixas & Vencimentos'),
                    ),
                  ],
                  if (onOpenReports != null) ...[
                    const SizedBox(height: LarSpacing.sm),
                    OutlinedButton.icon(
                      onPressed: onOpenReports,
                      icon: const Icon(Icons.pie_chart_outline),
                      label: const Text('Relatórios & Gráficos'),
                    ),
                  ],
                  if (onOpenCategories != null) ...[
                    const SizedBox(height: LarSpacing.sm),
                    OutlinedButton.icon(
                      onPressed: onOpenCategories,
                      icon: const Icon(Icons.category_outlined),
                      label: const Text('Categorias'),
                    ),
                  ],
                  if (onOpenImport != null) ...[
                    const SizedBox(height: LarSpacing.sm),
                    OutlinedButton.icon(
                      onPressed: onOpenImport,
                      icon: const Icon(Icons.file_upload_outlined),
                      label: const Text('Importar OFX'),
                    ),
                  ],
                ],
                const SizedBox(height: LarSpacing.xl),
                OutlinedButton.icon(
                  onPressed: state.isSubmitting ? null : controller.logout,
                  icon: state.isSubmitting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.logout),
                  label: const Text('Sair'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  if (liveState == null) return content();
  return AnimatedBuilder(
    animation: liveState,
    builder: (context, _) => content(),
  );
}
```

- [ ] **Step 4: Inject the existing coordinator state from the router**

In the `/more` route in `mobile/lib/app/router.dart`, add the state without
creating a second coordinator:

```dart
builder: (context, state) => MoreScreen(
  syncState: syncCoordinator?.state,
  onOpenBills: () => context.go('/bills'),
  onOpenCards: () => context.go('/cards'),
  onOpenImport: importRepository == null
      ? null
      : () => context.go('/more/import-ofx'),
  onOpenCategories: () => context.go('/categories'),
  onOpenReports: () => context.go('/reports'),
),
```

- [ ] **Step 5: Run GREEN and the neighboring lifecycle tests**

```powershell
Set-Location mobile
dart format --output=none --set-exit-if-changed lib/features/auth/presentation/more_screen.dart lib/app/router.dart test/features/auth/device_owner_screen_test.dart
flutter analyze
flutter test test/features/auth/device_owner_screen_test.dart test/core/sync/sync_lifecycle_test.dart
```

Expected: formatter and analyzer exit `0`; all auth and lifecycle tests pass,
including the new test that changes the timestamp after the first frame.

- [ ] **Step 6: Commit and push Task 1**

```powershell
Set-Location ..
git add mobile/lib/features/auth/presentation/more_screen.dart mobile/lib/app/router.dart mobile/test/features/auth/device_owner_screen_test.dart
git diff --cached --check
git commit -m "fix(mobile): show live sync timestamp"
git push origin codex/r3-3-1-sync-data-baseline
```

Stop and report that the stale label defect is fixed. Do not start Task 2 without authorization.

---

### Task 2: Identify the exact installed client artifact

**Files:**
- Modify: `mobile/lib/app/app_config.dart`
- Modify: `mobile/lib/features/auth/presentation/more_screen.dart`
- Modify: `mobile/lib/app/router.dart`
- Modify: `mobile/test/app/app_config_test.dart`
- Modify: `mobile/test/features/auth/device_owner_screen_test.dart`
- Modify: `mobile/test/tool/task9_configuration_test.dart`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: `LAR_FINANCE_API_BASE_URL` and GitHub's immutable `${{ github.sha }}`.
- Produces: `AppConfig.buildSha`, `AppConfig.buildLabel`, `AppConfig.serverHost`, and safe `MoreScreen(buildLabel:, serverHost:)` copy. No token, account, or session identifier is exposed.

- [ ] **Step 1: Write failing configuration and UI tests**

Add to `mobile/test/app/app_config_test.dart`:

```dart
test('exposes a short immutable client build and server host', () {
  const config = AppConfig(
    apiBaseUrl: 'https://financeiro.palmbook.online/api/v1/',
    buildSha: '1234567890abcdef1234567890abcdef12345678',
  );

  expect(config.buildLabel, '1234567');
  expect(config.serverHost, 'financeiro.palmbook.online');
});

test('keeps development label when no release SHA was injected', () {
  const config = AppConfig(apiBaseUrl: 'https://example.test/api/v1');
  expect(config.buildLabel, 'development');
});

test('rejects a malformed release SHA', () {
  expect(
    () => const AppConfig(
      apiBaseUrl: 'https://example.test/api/v1',
      buildSha: 'not-a-release-sha',
    ).validate(),
    throwsArgumentError,
  );
});
```

Extend the existing `More shows local device status and logs out offline` test:

```dart
await tester.pumpWidget(
  _screenApp(
    controller,
    const MoreScreen(
      buildLabel: '1234567',
      serverHost: 'financeiro.palmbook.online',
    ),
  ),
);

expect(find.text('Versão 1234567'), findsOneWidget);
expect(find.text('financeiro.palmbook.online'), findsOneWidget);
```

Add to `mobile/test/tool/task9_configuration_test.dart` after reading the workflow:

```dart
expect(
  r'LAR_FINANCE_BUILD_SHA=${{ github.sha }}'.allMatches(workflow),
  hasLength(3),
);
```

- [ ] **Step 2: Run the three focused tests and verify RED**

```powershell
Set-Location mobile
flutter test test/app/app_config_test.dart test/features/auth/device_owner_screen_test.dart test/tool/task9_configuration_test.dart
```

Expected: FAIL because build identity, host extraction, UI labels, and CI defines do not exist.

- [ ] **Step 3: Extend `AppConfig` without adding a package**

Implement in `mobile/lib/app/app_config.dart`:

```dart
final class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    this.buildSha = 'development',
  });

  factory AppConfig.fromEnvironment() => const AppConfig(
    apiBaseUrl: String.fromEnvironment(
      'LAR_FINANCE_API_BASE_URL',
      defaultValue: 'https://financeiro.palmbook.online/api/v1',
    ),
    buildSha: String.fromEnvironment(
      'LAR_FINANCE_BUILD_SHA',
      defaultValue: 'development',
    ),
  );

  final String apiBaseUrl;
  final String buildSha;

  String get normalizedApiBaseUrl => apiBaseUrl.endsWith('/')
      ? apiBaseUrl.substring(0, apiBaseUrl.length - 1)
      : apiBaseUrl;

  String get buildLabel => buildSha.length <= 7
      ? buildSha
      : buildSha.substring(0, 7);

  String get serverHost => Uri.parse(normalizedApiBaseUrl).host;
}
```

Keep the current URL checks in `validate()` and append this build check before
the method returns:

```dart
if (buildSha != 'development' &&
    !RegExp(r'^[0-9a-f]{40}$').hasMatch(buildSha)) {
  throw ArgumentError.value(
    buildSha,
    'buildSha',
    'A release build SHA must contain 40 lowercase hexadecimal characters',
  );
}
```

- [ ] **Step 4: Show only the safe build and host values in `Mais`**

Add to the `MoreScreen` constructor and fields:

```dart
this.buildLabel = 'development',
this.serverHost = 'não configurado',

final String buildLabel;
final String serverHost;
```

Under the existing device name, add:

```dart
const SizedBox(height: LarSpacing.sm),
Text('Versão $buildLabel'),
const SizedBox(height: LarSpacing.xs),
Text(serverHost),
```

In the `/more` route, inject only normalized public configuration:

```dart
MoreScreen(
  syncState: syncCoordinator?.state,
  buildLabel: config.buildLabel,
  serverHost: config.serverHost,
  onOpenBills: () => context.go('/bills'),
  onOpenCards: () => context.go('/cards'),
  onOpenImport: importRepository == null
      ? null
      : () => context.go('/more/import-ofx'),
  onOpenCategories: () => context.go('/categories'),
  onOpenReports: () => context.go('/reports'),
)
```

- [ ] **Step 5: Embed the exact SHA in all release artifacts**

Change only the three Flutter release commands in `.github/workflows/ci.yml`:

```yaml
flutter build windows --release --dart-define=LAR_FINANCE_API_BASE_URL=https://financeiro.palmbook.online/api/v1 --dart-define=LAR_FINANCE_BUILD_SHA=${{ github.sha }}
flutter build apk --release --dart-define=LAR_FINANCE_API_BASE_URL=https://financeiro.palmbook.online/api/v1 --dart-define=LAR_FINANCE_BUILD_SHA=${{ github.sha }}
flutter build ios --release --no-codesign --dart-define=LAR_FINANCE_API_BASE_URL=https://financeiro.palmbook.online/api/v1 --dart-define=LAR_FINANCE_BUILD_SHA=${{ github.sha }}
```

Do not alter signing, MSIX, artifact names, API URL, or deployment jobs.

- [ ] **Step 6: Run GREEN and configuration gates**

```powershell
Set-Location mobile
dart format --output=none --set-exit-if-changed lib/app/app_config.dart lib/app/router.dart lib/features/auth/presentation/more_screen.dart test/app/app_config_test.dart test/features/auth/device_owner_screen_test.dart test/tool/task9_configuration_test.dart
flutter analyze
flutter test test/app/app_config_test.dart test/features/auth/device_owner_screen_test.dart test/tool/task9_configuration_test.dart
Set-Location ..
git diff --check
```

Expected: all commands exit `0`; the configuration test finds exactly three build-SHA definitions.

- [ ] **Step 7: Commit and push Task 2**

```powershell
git add .github/workflows/ci.yml mobile/lib/app/app_config.dart mobile/lib/app/router.dart mobile/lib/features/auth/presentation/more_screen.dart mobile/test/app/app_config_test.dart mobile/test/features/auth/device_owner_screen_test.dart mobile/test/tool/task9_configuration_test.dart
git diff --cached --check
git commit -m "feat(mobile): expose safe build identity"
git push origin codex/r3-3-1-sync-data-baseline
```

Stop and report the build identity behavior. Do not start Task 3 without authorization.

---

### Task 3: Resolve the Dashboard data-availability investigation

**Files:**
- Create: `docs/audits/2026-08-22-r3-3-1-sync-data-baseline.md`
- Modify: `docs/superpowers/specs/2026-08-22-web-structure-flutter-casa-de-valores-design.md`
- Modify: `docs/ROADMAP.md`

**Interfaces:**
- Consumes: `DashboardView`, `HomeSnapshot`, `ReportsSummary`, `BillsMetricsModel`, `DriftHomeRepository`, `DriftReportsRepository`, and the current Drift category schema.
- Produces: a code-backed matrix stating what is already available, what is online-only, and what is actually missing. Later dashboard tasks use this matrix and must not invent values.

- [ ] **Step 1: Create the audit with the exact field matrix**

Create `docs/audits/2026-08-22-r3-3-1-sync-data-baseline.md` with:

```markdown
# R3.3.1 — Sincronização, dados e baseline visual

**Data:** 22/08/2026

**Privacidade:** o repositório é público. Nenhuma captura real, valor, conta,
token, sessão ou identificador privado é versionado.

## Causa confirmada no código para a data antiga da tela Mais

`MoreScreen` lia apenas `AuthState.lastSyncAt`, carregado durante autenticação ou
restauração de sessão. Sincronizações normais atualizavam `SyncState` e Drift,
mas não esse snapshot de autenticação. A Home já observava o estado vivo; a tela
Mais não. A Task 1 conecta a tela Mais ao mesmo `LedgerSyncCoordinator.state`.

Isso explica a data visualmente congelada, mas a validação no Windows ainda deve
provar uma sincronização real após instalar o artefato exato.

## Matriz de disponibilidade

| Indicador Web | Fonte Web | Flutter atual | Estado para R3.3 |
|---|---|---|---|
| saldo total | `DashboardView.total_balance` | `HomeSnapshot.balanceMinor` via Drift | disponível offline |
| saldo livre real | `bills_metrics.free_cash_balance` | `BillsMetricsModel.freeCashBalanceMinor` | disponível online; ainda não composto na Home |
| compromissos pendentes | `pending_bills_total` | `BillsMetricsModel.pendingExpensesTotalMinor` | disponível online; `HomeSnapshot.upcomingCommitmentMinor` não é semanticamente idêntico |
| vencidos | `overdue_bills_count` | `BillsMetricsModel.overdueCount` | disponível online |
| receitas, despesas, líquido e poupança | agregados mensais | `ReportsSummary` | disponível offline pelo ledger |
| fluxo de seis meses | `monthly_flows` | `ReportsSummary.monthlyFlows` | disponível offline pelo ledger |
| distribuição e maiores gastos | `expenses_by_category` | `categoryDistributions`, já ordenado por valor | disponível offline pelo ledger |
| transações recentes | 10 linhas | `HomeSnapshot.recentTransactions` | disponível offline; Flutter limita a 5 |
| lista de próximos vencimentos | `bills_metrics.upcoming_bills` | `BillsDataSnapshot.instances` | disponível online na área Contas Fixas |
| teto total, restante, uso e gasto diário permitido | orçamento de categorias no Django | schema Drift de categoria não possui `budget` | ausente no ledger Flutter; não exibir até contrato próprio |

## Decisão

R3.3.2 e R3.3.3 reutilizam os dados disponíveis. Saldo livre e contas fixas
continuam online até uma decisão de cache posterior. Orçamento diário não será
simulado com saldo ou gasto mensal. A quantidade de recentes pode mudar apenas
com teste de desempenho e sem alterar o significado.

## Evidência de execução

- [ ] timestamp da tela Mais mudou após sincronização real;
- [ ] cliente exibiu SHA curto correspondente ao artefato instalado;
- [ ] host exibido foi `financeiro.palmbook.online`;
- [ ] health público respondeu `status=ok`, `api_version=v1` e SHA de 40 caracteres;
- [ ] Web e Windows foram comparados no escopo `Lar` e no mesmo período;
- [ ] screenshots reais ficaram somente em `screenshots/`, ignorado pelo Git;
- [ ] seis goldens Flutter sintéticos passaram sem atualização.
```

- [ ] **Step 2: Resolve the field investigation in the approved spec**

Replace the paragraph ending in the first `[INVESTIGAR]` with:

```markdown
A disponibilidade foi mapeada em
`docs/audits/2026-08-22-r3-3-1-sync-data-baseline.md`: saldo e movimentações
existem no `HomeSnapshot`; receitas, despesas, líquido, poupança, fluxo e
categorias existem no `ReportsSummary`; saldo livre e vencimentos existem no
`BillsMetricsModel`, porém online; orçamento diário não existe no ledger Flutter
porque categoria local ainda não possui `budget`. Nenhum campo ausente será
substituído por outro indicador.
```

Leave the runtime sync `[INVESTIGAR]` marker in place until Task 4 proves the real Windows path.

- [ ] **Step 3: Reconcile the roadmap naming without marking later work complete**

Under `## R3 — Paridade visual incremental`, add this note before the current task list:

```markdown
> A especificação R3.3 reorganiza os itens abaixo como um programa incremental
> de convergência completa. R3.3.1 é somente o gate de sincronização, dados e
> baseline; nenhuma tela posterior é considerada concluída por essa mudança.
```

Do not check R3.3 Contas, R3.4 Categorias, or any later visual item.

- [ ] **Step 4: Verify every matrix row against the code**

```powershell
rg -n "total_balance|free_cash_balance|pending_bills_total|overdue_bills_count|monthly_flows|expenses_by_category|daily_burn_rate" core/views.py
rg -n "balanceMinor|monthExpenseMinor|upcomingCommitmentMinor|LIMIT 5" mobile/lib/features/home mobile/lib/core/storage
rg -n "totalIncomeMinor|totalExpenseMinor|netBalanceMinor|savingsRate|categoryDistributions|monthlyFlows" mobile/lib/features/reports
rg -n "freeCashBalanceMinor|pendingExpensesTotalMinor|overdueCount" mobile/lib/features/bills
rg -n "class Categories|budget" mobile/lib/core/storage/tables.dart
git diff --check
```

Expected: every `disponível` matrix row has a matching symbol; `budget` is absent from the local `Categories` table; the diff check exits `0`.

- [ ] **Step 5: Run repository calculation tests**

```powershell
Set-Location mobile
flutter test test/features/home/home_repository_test.dart test/features/reports/reports_repository_test.dart test/features/bills/bills_exact_money_test.dart
Set-Location ..
```

Expected: all three suites pass with exact minor-unit calculations.

- [ ] **Step 6: Commit and push Task 3**

```powershell
git add docs/audits/2026-08-22-r3-3-1-sync-data-baseline.md docs/superpowers/specs/2026-08-22-web-structure-flutter-casa-de-valores-design.md docs/ROADMAP.md
git diff --cached --check
git commit -m "docs: map cross-platform dashboard data"
git push origin codex/r3-3-1-sync-data-baseline
```

Stop and report the data matrix. Do not start Task 4 without authorization.

---

### Task 4: Validate the real Windows path and close R3.3.1

**Files:**
- Verify only: `mobile/test/goldens/home_mobile_light.png`
- Verify only: `mobile/test/goldens/home_mobile_dark.png`
- Verify only: `mobile/test/goldens/home_ios_light.png`
- Verify only: `mobile/test/goldens/home_ios_dark.png`
- Verify only: `mobile/test/goldens/home_windows_light.png`
- Verify only: `mobile/test/goldens/home_windows_dark.png`
- Modify: `docs/audits/2026-08-22-r3-3-1-sync-data-baseline.md`
- Modify: `docs/superpowers/specs/2026-08-22-web-structure-flutter-casa-de-valores-design.md`
- Modify: `docs/ROADMAP.md`
- Modify: `docs/superpowers/plans/2026-08-22-r3-3-1-sync-data-baseline-implementation.md`

**Interfaces:**
- Consumes: live timestamp from Task 1, build identity from Task 2, field matrix from Task 3, public `/api/v1/health/`, the CI Windows artifact, and existing synthetic goldens.
- Produces: observed proof that Windows refreshes against the intended server and a privacy-safe baseline for later visual work. No production data is committed.

- [ ] **Step 1: Verify production health without authentication**

```powershell
$health = Invoke-RestMethod -Uri 'https://financeiro.palmbook.online/api/v1/health/' -Method Get -TimeoutSec 15
if ($health.status -ne 'ok') { throw 'Health status is not ok' }
if ($health.api_version -ne 'v1') { throw 'Unexpected API version' }
if ($health.version -notmatch '^[0-9a-f]{40}$') { throw 'Health version is not a Git SHA' }
$health | ConvertTo-Json -Compress
```

Expected: exit `0` with only `status`, `api_version`, and `version`. Do not call authenticated endpoints from the terminal or print credentials.

- [ ] **Step 2: Wait for the exact CI run and download its Windows artifact**

```powershell
$sha = git rev-parse HEAD
$run = gh run list --branch codex/r3-3-1-sync-data-baseline --workflow CI --limit 10 --json databaseId,headSha,status,conclusion,url | ConvertFrom-Json | Where-Object { $_.headSha -eq $sha } | Select-Object -First 1
if ($null -eq $run) { throw 'No CI run matches HEAD' }
gh run watch $run.databaseId --exit-status
if (Test-Path -LiteralPath screenshots/r3-3-1-artifact) { throw 'Use a fresh screenshots/r3-3-1-artifact directory' }
New-Item -ItemType Directory -Path screenshots/r3-3-1-artifact | Out-Null
gh run download $run.databaseId --name "lar-finance-windows-msix-$sha" --dir screenshots/r3-3-1-artifact
Get-ChildItem screenshots/r3-3-1-artifact -Recurse
```

Expected: CI succeeds on the exact SHA and the downloaded artifact contains one MSIX plus its SHA-256 file. `screenshots/` is already ignored by Git.

- [ ] **Step 3: Install or run the exact Windows build and prove live sync**

This step requires the owner's interactive Windows session. Install the exact
artifact using the already-approved private certificate procedure, then:

1. open `Mais` and confirm `Versão` equals the first seven characters of `$sha`;
2. confirm the host is `financeiro.palmbook.online`;
3. note the displayed last-success time without copying financial values;
4. return to Home and invoke pull-to-refresh;
5. return to `Mais` and confirm the timestamp advances without restarting;
6. repeat once with the app minimized for over five minutes and resumed;
7. if the timestamp does not advance, stop the sprint and retain `[INVESTIGAR]` with the visible state (`Offline` or `Sincronização indisponível`); do not guess a transport fix.

Expected: `Mais` follows the same live timestamp already used by Home, and the
timestamp changes after a successful manual refresh.

- [ ] **Step 4: Compare the same household state in Web and Windows**

Open the authenticated Web Dashboard and Windows Home using:

```text
login: the same single household login
owner scope: Lar / household
period: current month
server host: financeiro.palmbook.online
sync: Windows timestamp after the refresh from Step 3
```

Compare only semantically identical values:

```text
Web total_balance == Flutter balanceMinor
Web monthly_expenses == Flutter monthExpenseMinor
Web recent transactions contain the same latest entries; Web may show 10 and Flutter 5
Web free_cash_balance is not compared to Flutter balanceMinor
Web pending_bills_total is not compared to Flutter upcomingCommitmentMinor
```

Save any real screenshots only under `screenshots/r3-3-1-real/`. Before every
commit, run `git status --short` and confirm no screenshot is staged.

- [ ] **Step 5: Revalidate the six synthetic visual baselines**

```powershell
Set-Location mobile
$before = Get-FileHash test/goldens/home_*.png -Algorithm SHA256 | Sort-Object Path
flutter test test/features/home/home_goldens_test.dart
$after = Get-FileHash test/goldens/home_*.png -Algorithm SHA256 | Sort-Object Path
if (Compare-Object $before $after -Property Path,Hash) { throw 'Golden files changed during verification' }
Set-Location ..
```

Expected: six golden tests pass and no PNG hash changes. Inspect all six images;
do not update them in this sprint.

- [ ] **Step 6: Record sanitized evidence and resolve the runtime investigation**

In the audit, check only evidence actually observed. Record:

- full client commit SHA;
- GitHub Actions run URL;
- server health SHA;
- whether the timestamp advanced after refresh and resume;
- whether semantically identical totals matched;
- names and dimensions of local screenshots, never their financial contents.

If Step 3 and Step 4 pass, replace the remaining sync `[INVESTIGAR]` paragraph in the spec with:

```markdown
A data antiga observada era causada pela tela `Mais`, que lia o snapshot de
autenticação em vez do `SyncState` vivo. A R3.3.1 conectou a tela ao coordenador
existente e a validação no Windows confirmou atualização após refresh e resume.
A evidência sanitizada está em
`docs/audits/2026-08-22-r3-3-1-sync-data-baseline.md`.
```

If either step fails, keep `[INVESTIGAR]`, record the exact safe state, and do not mark the sprint complete.

- [ ] **Step 7: Run the full local gates**

Backend:

```powershell
$env:SECRET_KEY='r3-3-1-final-verification-secret'
$env:DEBUG='False'
python scripts/generate_design_tokens.py --check
ruff check . --config pyproject.toml
python manage.py check
python manage.py makemigrations --check
python manage.py test
```

Flutter:

```powershell
Set-Location mobile
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test --exclude-tags=golden
flutter test --tags=golden test/features/home/home_goldens_test.dart
Set-Location ..
```

Expected: every command exits `0`; no migration, formatting, analysis, test, or golden failure.

- [ ] **Step 8: Close only R3.3.1 in documentation**

In this plan, mark executed checkboxes and add `**Status:** concluído` below the title. In the spec, mark Sprint R3.3.1 checkboxes complete only if Steps 3–7 passed. In `docs/ROADMAP.md`, record R3.3.1 as complete with commit SHAs and CI URL; leave R3.3.2 and every later task unchecked.

- [ ] **Step 9: Commit and push sprint closure**

```powershell
git status --short
git add docs/audits/2026-08-22-r3-3-1-sync-data-baseline.md docs/superpowers/specs/2026-08-22-web-structure-flutter-casa-de-valores-design.md docs/ROADMAP.md docs/superpowers/plans/2026-08-22-r3-3-1-sync-data-baseline-implementation.md
git diff --cached --check
git diff --cached --name-only | Select-String -Pattern '\.(png|jpg|jpeg|webp)$' -Quiet | ForEach-Object { if ($_){ throw 'Real screenshots must not be committed' } }
git commit -m "docs: close sync data baseline"
git push origin codex/r3-3-1-sync-data-baseline
```

- [ ] **Step 10: Verify remote synchronization and stop**

```powershell
git fetch origin
$local = git rev-parse HEAD
$remote = git rev-parse origin/codex/r3-3-1-sync-data-baseline
if ($local -ne $remote) { throw 'Local and remote branch differ' }
if (git status --short) { throw 'Worktree is not clean' }
```

Expected: local and remote SHAs match and the worktree is clean. Report what was
proved and request authorization before any merge or Sprint R3.3.2 work.
