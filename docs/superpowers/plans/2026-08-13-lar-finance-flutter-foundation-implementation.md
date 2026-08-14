# Lar Finance Flutter Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** entregar a fundação Flutter instalável do Lar Finance para Windows, Android e iOS, com identidade Casa de Valores, login privado, sessão segura, cache SQLite, sincronização online e Home real somente leitura.

**Architecture:** um cliente Flutter organizado por feature consome a API Django v1, guarda tokens apenas no cofre nativo e mantém uma projeção local do Lar em SQLite/Drift. A Home observa o banco local; bootstrap e deltas são aplicados em transações atômicas. O shell e o design system são compartilhados, mas navegação, densidade, foco e comportamento nativo se adaptam a celular e Windows.

**Tech Stack:** Flutter stable verificado e fixado na Task 1; Dart correspondente; Flutter Riverpod 3.4.2; GoRouter 17.3.0; Dio 5.11.0; Drift 2.34.3; drift_flutter 0.3.1; flutter_secure_storage 10.3.1; intl 0.20.3; drift_dev 2.34.5; build_runner 2.15.3; Flutter test/integration_test; backend Python 3.12, Django 5.2.13 e DRF 3.17.1.

**Design aprovado:** [Sprint 4 — Fundação Flutter e Casa de Valores](../specs/2026-08-13-lar-finance-flutter-foundation-design.md).

## Global Constraints

- Plataformas obrigatórias no mesmo workspace: Windows, Android e iOS; build iOS real exige macOS/Xcode.
- Backend Django/EasyPanel é a fonte canônica; não duplicar regras financeiras no cliente além das projeções de leitura descritas neste plano.
- Sprint 4 é somente leitura financeira. Não enviar operações ao `/sync/push/`, não criar outbox e não editar ledger.
- Home abre pelo SQLite local; bootstrap e delta só publicam cursor depois de transação local concluída.
- Tokens de acesso e renovação ficam somente no armazenamento seguro nativo, nunca no SQLite, logs, analytics ou fixtures.
- Uma falha 401 pode disparar uma única renovação coordenada; cada requisição é repetida no máximo uma vez.
- Falha definitiva de refresh volta ao login sem apagar o cache financeiro.
- Valores usam centavos inteiros no cliente e strings decimais no contrato HTTP; nunca usar `double` para cálculo financeiro.
- Produto privado, um login familiar, responsáveis `Eu`, `Esposa` e `Conjunto`; sem signup ou landing page.
- Direção Casa de Valores: sem roxo, neon, glassmorphism, gradientes chamativos ou pilhas de cards.
- Temas claro e escuro; números com algarismos tabulares; contraste AA; redução de movimento; escala de texto; teclado e foco Windows.
- Nenhuma permissão de câmera, localização, contatos, push ou biometria nesta sprint.
- A URL pública da API não é segredo e entra por `--dart-define=LAR_FINANCE_API_BASE_URL=`; credenciais nunca entram em código/CI.
- Cada task usa TDD, revisão independente, gates focados, commit Conventional Commit e push. Não iniciar a task seguinte sem autorização explícita do usuário.
- Preservar `.codex-sprint2/` e qualquer alteração do usuário fora do escopo.

## Plano de modelos — Sprint 4

**Inventário confirmado:** `gpt-5.6-terra` e `gpt-5.6-sol`, com `low`, `medium`, `high`, `xhigh`, `max` e `ultra`.
**Complexidade geral:** alta.
**Estratégia de consumo:** usar Terra nas tarefas delimitadas de scaffold/UI e Sol nos contratos de autenticação, persistência financeira, sincronização e gate final.
**Modelo/intensidade predominante:** `gpt-5.6-sol` com `high`.
**Motivo:** a sprint combina três plataformas, segurança de sessão, migração local e consistência financeira; falhas podem contaminar todas as tasks seguintes.

| Task | Modelo | Intensidade | Consumo | Motivo |
|---|---|---:|---|---|
| 1. Toolchain e scaffold | `gpt-5.6-terra` | high | médio | instalação, compatibilidade e CI são delimitados, mas multiplataforma |
| 2. Login inicializável | `gpt-5.6-sol` | high | médio | muda contrato de autenticação e OpenAPI |
| 3. Casa de Valores e shell | `gpt-5.6-terra` | high | médio | trabalho visual guiado por especificação aprovada |
| 4. Domínio e SQLite | `gpt-5.6-sol` | high | alto | precisão monetária, schema e atomicidade |
| 5. Sessão segura | `gpt-5.6-sol` | xhigh | alto | refresh concorrente, revogação e armazenamento seguro |
| 6. Sincronização | `gpt-5.6-sol` | xhigh | alto | cursor, tombstones e commit atômico |
| 7. Home real | `gpt-5.6-sol` | high | alto | agregações financeiras e estados de UX |
| 8. Privacidade e adaptação | `gpt-5.6-terra` | high | médio | integração nativa e acessibilidade com escopo definido |
| 9. Builds e fechamento | `gpt-5.6-sol` | high | alto | validação cruzada, performance, instalador e auditoria final |

Tokens reais: não disponíveis.

---

## Estrutura de arquivos alvo

| Caminho | Responsabilidade |
|---|---|
| `mobile/pubspec.yaml` | SDK, dependências pinadas, assets e configuração MSIX |
| `mobile/lib/main.dart` | bootstrap mínimo do Flutter e ProviderScope |
| `mobile/lib/app/` | configuração, router, lifecycle e shell adaptativo |
| `mobile/lib/design_system/` | tokens, temas e componentes Casa de Valores |
| `mobile/lib/core/network/` | transporte Dio, envelopes e renovação coordenada |
| `mobile/lib/core/storage/` | Drift, tabelas, DAOs, migrations e preferências não secretas |
| `mobile/lib/core/sync/` | bootstrap, pull incremental, cursor e estado de freshness |
| `mobile/lib/features/auth/` | login, escolha do responsável do dispositivo e logout |
| `mobile/lib/features/home/` | consulta local, agregações e Home somente leitura |
| `mobile/test/` | unitários, widgets, goldens, migrations e helpers sintéticos |
| `mobile/integration_test/` | jornada login/sync/offline/reconexão/logout |
| `.github/workflows/ci.yml` | análise/testes Flutter e builds por plataforma |

## Contratos internos fixos

```dart
abstract interface class TokenStore {
  Future<StoredTokens?> read();
  Future<void> write(StoredTokens tokens);
  Future<void> clear();
}

abstract interface class ApiTransport {
  Future<Map<String, Object?>> getObject(String path, {Map<String, Object?> query = const {}});
  Future<Map<String, Object?>> postObject(String path, Map<String, Object?> body);
  Future<void> postEmpty(String path);
  Future<Map<String, Object?>> patchObject(String path, Map<String, Object?> body);
}

abstract interface class LocalLedger {
  Stream<HomeSnapshot> watchHome(OwnerScope scope, DateTime now);
  Future<void> replaceBootstrap(BootstrapPayload payload, DateTime syncedAt, String sessionDeviceUuid);
  Future<void> applyDelta(SyncPage page, DateTime syncedAt);
  Future<SyncMetadata?> readSyncMetadata();
}

abstract interface class SyncCoordinator {
  Future<SyncResult> synchronize();
}
```

`OwnerScope.household` inclui `self`, `spouse` e `shared`. `OwnerScope.self` e `OwnerScope.spouse` filtram o UUID do respectivo responsável. O rótulo financeiro inicial é **Saldo consolidado**, não patrimônio líquido, porque dívidas/investimentos completos ainda não existem.

The sync DTO boundary is fixed as JSON objects validated before persistence:

```dart
typedef JsonObject = Map<String, Object?>;

final class BootstrapPayload {
  const BootstrapPayload({
    required this.household,
    required this.owners,
    required this.accounts,
    required this.categories,
    required this.transactions,
    required this.cursor,
  });
  final JsonObject household;
  final List<JsonObject> owners;
  final List<JsonObject> accounts;
  final List<JsonObject> categories;
  final List<JsonObject> transactions;
  final String cursor;
}

final class SyncChangePayload {
  const SyncChangePayload({
    required this.entityType,
    required this.entityUuid,
    required this.entityVersion,
    required this.operation,
    required this.payload,
  });
  final String entityType;
  final String entityUuid;
  final int entityVersion;
  final String operation;
  final JsonObject payload;
}

final class SyncPage {
  const SyncPage({required this.changes, required this.cursor});
  final List<SyncChangePayload> changes;
  final String cursor;
}

final class SyncMetadata {
  const SyncMetadata({
    required this.cursor,
    required this.householdUuid,
    required this.sessionDeviceUuid,
    required this.lastSuccessAt,
  });
  final String cursor;
  final String householdUuid;
  final String sessionDeviceUuid;
  final DateTime lastSuccessAt;
}

enum SyncResult { current, updated, offlineWithCache, noCacheOffline, failed }
```

---

### Task 1: Verificar toolchain, criar workspace Flutter e fixar dependências

**Routing — Task 1**

**Modelo:** `gpt-5.6-terra`
**Intensidade:** high
**Motivo:** instalação e scaffold são previsíveis, mas precisam provar três targets e versões compatíveis.
**Consumo esperado:** médio
**Ferramentas:** shell, documentação oficial Flutter/pub.dev e GitHub Actions.

**Files:**
- Create: `mobile/`, `mobile/tool/flutter-version.json`, `mobile/lib/app/app_config.dart`, `mobile/test/app/app_config_test.dart`, `docs/adr/ADR-009-flutter-toolchain.md`
- Modify: `.gitignore`, `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: API base `/api/v1` e a especificação aprovada.
- Produces: workspace compilável, `AppConfig.apiBaseUrl`, lockfile e matriz inicial de CI.

- [ ] **Step 1: provar o estado inicial do ambiente**

Run:

```powershell
where.exe flutter
where.exe dart
where.exe java
where.exe adb
where.exe cmake
where.exe msbuild
```

Expected: registrar cada item encontrado/ausente no relatório da task; no snapshot de planejamento, Flutter e Dart estão ausentes. Não editar o projeto antes dessa evidência.

- [ ] **Step 2: instalar o Flutter stable pela documentação oficial e habilitar targets**

Run after installing the SDK in a user-owned tools directory:

```powershell
flutter channel stable
flutter upgrade
flutter config --enable-windows-desktop --enable-android --enable-ios
flutter doctor -v
flutter --version --machine | Set-Content -Encoding UTF8 $env:TEMP\lar-finance-flutter-version.json
```

Expected: Windows toolchain and Android toolchain pass; iOS is reported unavailable on Windows and recorded as an expected platform limitation. If Windows or Android remains red, stop the task and report the exact missing component.

- [ ] **Step 3: criar o workspace sem web/macOS/Linux**

Run:

```powershell
flutter create --org online.palmbook --project-name lar_finance --platforms android,ios,windows mobile
New-Item -ItemType Directory -Force mobile\tool | Out-Null
Copy-Item $env:TEMP\lar-finance-flutter-version.json mobile\tool\flutter-version.json
```

Expected: `mobile/android`, `mobile/ios`, `mobile/windows`, `mobile/lib/main.dart` and `mobile/test/widget_test.dart` exist; no `mobile/web`, `mobile/linux` or `mobile/macos` directory exists.

- [ ] **Step 4: fixar dependências verificadas no pubspec e lockfile**

Set these exact constraints in `mobile/pubspec.yaml`:

```yaml
environment:
  sdk: ">=3.10.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter
  dio: 5.11.0
  drift: 2.34.3
  drift_flutter: 0.3.1
  flutter_riverpod: 3.4.2
  flutter_secure_storage: 10.3.1
  go_router: 17.3.0
  intl: 0.20.3

dev_dependencies:
  flutter_test:
    sdk: flutter
  integration_test:
    sdk: flutter
  build_runner: 2.15.3
  drift_dev: 2.34.5
  flutter_lints: 6.0.0
```

Run:

```powershell
Set-Location mobile
flutter pub get
flutter pub outdated
```

Expected: dependency resolution succeeds and `mobile/pubspec.lock` is created. Do not silently replace a pinned version; if the installed stable SDK rejects one, record the solver output and request a plan adjustment.

- [ ] **Step 5: escrever primeiro o teste de configuração**

Create `mobile/test/app/app_config_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lar_finance/app/app_config.dart';

void main() {
  test('normalizes the API base URL without a trailing slash', () {
    const config = AppConfig(apiBaseUrl: 'https://example.test/api/v1/');
    expect(config.normalizedApiBaseUrl, 'https://example.test/api/v1');
  });

  test('rejects non HTTPS production URLs', () {
    expect(
      () => const AppConfig(apiBaseUrl: 'http://example.test/api/v1').validate(),
      throwsArgumentError,
    );
  });
}
```

- [ ] **Step 6: executar RED e implementar AppConfig**

Run:

```powershell
flutter test test/app/app_config_test.dart
```

Expected: FAIL because `app_config.dart` does not exist.

Create `mobile/lib/app/app_config.dart`:

```dart
final class AppConfig {
  const AppConfig({required this.apiBaseUrl});

  factory AppConfig.fromEnvironment() => const AppConfig(
        apiBaseUrl: String.fromEnvironment(
          'LAR_FINANCE_API_BASE_URL',
          defaultValue: 'https://financeiro.palmbook.online/api/v1',
        ),
      );

  final String apiBaseUrl;

  String get normalizedApiBaseUrl =>
      apiBaseUrl.endsWith('/') ? apiBaseUrl.substring(0, apiBaseUrl.length - 1) : apiBaseUrl;

  void validate() {
    final uri = Uri.parse(normalizedApiBaseUrl);
    final local = uri.host == 'localhost' || uri.host == '127.0.0.1';
    if (!uri.hasScheme || (uri.scheme != 'https' && !local)) {
      throw ArgumentError.value(apiBaseUrl, 'apiBaseUrl', 'HTTPS is required outside localhost');
    }
  }
}
```

Run again; Expected: PASS.

- [ ] **Step 7: adicionar job Flutter inicial à CI**

Append this `flutter` job to `.github/workflows/ci.yml`; it parses the committed JSON instead of duplicating the SDK version:

```yaml
  flutter:
    name: Flutter checks
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: mobile
    steps:
      - name: Check out repository
        uses: actions/checkout@v6
      - name: Read pinned Flutter version
        id: flutter-version
        shell: bash
        run: echo "version=$(python -c 'import json; print(json.load(open("tool/flutter-version.json"))["frameworkVersion"])')" >> "$GITHUB_OUTPUT"
      - name: Install Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: ${{ steps.flutter-version.outputs.version }}
          channel: stable
          cache: true
      - run: flutter pub get
      - run: dart format --output=none --set-exit-if-changed .
      - run: flutter analyze
      - run: flutter test
```

Verification commands:

```powershell
Set-Location mobile
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build windows --debug
flutter build apk --debug
```

Expected: all commands exit 0. iOS build is not claimed on Windows.

- [ ] **Step 8: documentar a decisão e fechar a task**

`docs/adr/ADR-009-flutter-toolchain.md` must record exact Flutter/Dart/Java/Gradle/Visual Studio versions, supported targets, package pins, the official source URL and the iOS-on-Windows limitation. Then run `git diff --check`, request independent review, commit and push:

```powershell
git add mobile .github/workflows/ci.yml .gitignore docs/adr/ADR-009-flutter-toolchain.md
git commit -m "build: scaffold Flutter client"
git push -u origin codex/sprint-4-flutter-foundation
```

Stop and request user authorization for Task 2.

---

### Task 2: Tornar o login inicializável sem conhecer UUID de responsável

**Routing — Task 2**

**Modelo:** `gpt-5.6-sol`
**Intensidade:** high
**Motivo:** alteração pequena, porém no contrato de autenticação e isolamento do Lar.
**Consumo esperado:** médio
**Ferramentas:** Django, DRF, OpenAPI, TDD e revisão de segurança.

**Files:**
- Modify: `api/serializers.py`, `api/tests/test_auth_api.py`, `api/tests/test_openapi_contract.py`, `docs/openapi-v1.yaml`, `docs/mobile-ux.md`

**Interfaces:**
- Consumes: `FinancialOwner.SELF`, `DeviceSession` e `/devices/current/` atuais.
- Produces: `POST /api/v1/auth/login/` aceita `default_owner_uuid` ausente; servidor escolhe o owner ativo `self`. UUID explícito mantém o comportamento atual.

- [ ] **Step 1: escrever os testes de contrato RED**

Add to `api/tests/test_auth_api.py`:

```python
def test_login_without_default_owner_uses_active_self_owner(self):
    payload = {
        'email': self.user.email,
        'password': self.password,
        'platform': DeviceSession.WINDOWS,
        'name': 'Notebook novo',
    }

    response = self.client.post('/api/v1/auth/login/', payload, content_type='application/json')

    self.assertEqual(response.status_code, 200)
    self.assertEqual(response.json()['device']['default_owner_uuid'], str(self.self_owner.uuid))

def test_login_without_default_owner_rejects_household_without_active_self(self):
    self.self_owner.is_active = False
    self.self_owner.save(update_fields=['is_active'])

    response = self.client.post(
        '/api/v1/auth/login/',
        {
            'email': self.user.email,
            'password': self.password,
            'platform': DeviceSession.ANDROID,
            'name': 'Telefone novo',
        },
        content_type='application/json',
    )

    self.assertEqual(response.status_code, 401)
    self.assertEqual(response.json()['error']['code'], 'invalid_credentials')
```

Run the two tests. Expected: first fails because `default_owner_uuid` is required.

- [ ] **Step 2: implementar fallback seguro no serializer**

Change the field and resolution in `LoginSerializer`:

```python
default_owner_uuid = serializers.UUIDField(required=False)

owner_uuid = attrs.get('default_owner_uuid')
owner_query = FinancialOwner.objects.filter(
    household=membership.household,
    is_active=True,
    type__in=(FinancialOwner.SELF, FinancialOwner.SPOUSE),
)
if owner_uuid is None:
    owner = owner_query.filter(type=FinancialOwner.SELF).first()
    if owner is None:
        raise InvalidCredentials()
else:
    owner = owner_query.filter(uuid=owner_uuid).first()
    if owner is None:
        raise serializers.ValidationError(
            {'default_owner_uuid': ['Escolha o responsável próprio ou cônjuge deste Lar.']}
        )
attrs['default_owner'] = owner
```

Keep explicit foreign/inactive/shared UUIDs invalid. Do not expose owner existence in the error.

- [ ] **Step 3: atualizar OpenAPI e testar compatibilidade**

In `LoginRequest`, keep `email`, `password`, `platform` and `name` required; remove only `default_owner_uuid` from `required` and describe the self fallback. Add a contract assertion:

```python
login = self.schema['components']['schemas']['LoginRequest']
self.assertNotIn('default_owner_uuid', login['required'])
self.assertIn('default_owner_uuid', login['properties'])
```

Run:

```powershell
python manage.py test api.tests.test_auth_api api.tests.test_openapi_contract
python -m ruff check api --config pyproject.toml
python manage.py check
python manage.py makemigrations --check
git diff --check
```

Expected: all commands exit 0 and no migration is generated.

- [ ] **Step 4: revisar, commitar e enviar**

Request a security/spec review that explicitly checks invalid login indistinguishability and old clients sending UUID. Commit and push:

```powershell
git add api/serializers.py api/tests/test_auth_api.py api/tests/test_openapi_contract.py docs/openapi-v1.yaml docs/mobile-ux.md
git commit -m "fix: bootstrap device login safely"
git push origin codex/sprint-4-flutter-foundation
```

Stop and request user authorization for Task 3.

---

### Task 3: Implementar design system Casa de Valores e shell adaptativo

**Routing — Task 3**

**Modelo:** `gpt-5.6-terra`
**Intensidade:** high
**Motivo:** direção visual, componentes e breakpoints já foram aprovados; exige fidelidade e acessibilidade, não nova arquitetura.
**Consumo esperado:** médio
**Ferramentas:** Flutter widget/golden tests e Impeccable v4 para crítica final.

**Files:**
- Create: `mobile/lib/design_system/lar_colors.dart`, `lar_spacing.dart`, `lar_typography.dart`, `lar_theme.dart`, `components/financial_amount.dart`, `components/owner_selector.dart`, `components/sync_status.dart`, `mobile/lib/app/adaptive_shell.dart`, `mobile/lib/app/lar_sidebar.dart`, `mobile/lib/app/lar_bottom_navigation.dart`, `mobile/lib/app/router.dart`
- Create tests: `mobile/test/design_system/lar_theme_test.dart`, `financial_amount_test.dart`, `mobile/test/app/adaptive_shell_test.dart`
- Create goldens: `mobile/test/goldens/casa_de_valores_dark.png`, `casa_de_valores_light.png`
- Modify: `mobile/lib/main.dart`, `mobile/pubspec.yaml`

**Interfaces:**
- Consumes: `AppConfig` from Task 1.
- Produces: `LarTheme.light`, `LarTheme.dark`, `FinancialAmount`, `OwnerSelector`, `SyncStatusView`, `AdaptiveShell` and router paths `/login`, `/device-owner`, `/initial-sync`, `/home`, `/more`.

- [ ] **Step 1: escrever testes RED dos tokens**

```dart
test('Casa de Valores tokens contain no purple family colors', () {
  for (final color in LarColors.all) {
    final hsv = HSVColor.fromColor(color);
    final purple = hsv.hue >= 260 && hsv.hue <= 330 && hsv.saturation > 0.15;
    expect(purple, isFalse, reason: color.toARGB32().toRadixString(16));
  }
  expect(LarColors.darkCanvas, const Color(0xFF091311));
  expect(LarColors.champagne, const Color(0xFFC7A35A));
});

testWidgets('financial amount uses tabular figures and hides only digits', (tester) async {
  await tester.pumpWidget(
    const MaterialApp(home: FinancialAmount(minorUnits: 2486040, hidden: false)),
  );
  expect(find.text('R\$ 24.860,40'), findsOneWidget);

  await tester.pumpWidget(
    const MaterialApp(home: FinancialAmount(minorUnits: 2486040, hidden: true)),
  );
  expect(find.text('R\$ ••••••'), findsOneWidget);
});
```

Run focused tests. Expected: FAIL because the classes do not exist.

- [ ] **Step 2: criar tokens e temas claro/escuro**

Implement immutable tokens, including:

```dart
abstract final class LarColors {
  static const darkCanvas = Color(0xFF091311);
  static const darkSurface = Color(0xFF101B18);
  static const lightCanvas = Color(0xFFF3EFE6);
  static const lightSurface = Color(0xFFFFFCF5);
  static const champagne = Color(0xFFC7A35A);
  static const mineral = Color(0xFF2F756A);
  static const amber = Color(0xFFB9782D);
  static const danger = Color(0xFFB8534F);
  static const darkText = Color(0xFFE8E3D8);
  static const lightText = Color(0xFF17201D);
  static const all = <Color>[
    darkCanvas,
    darkSurface,
    lightCanvas,
    lightSurface,
    champagne,
    mineral,
    amber,
    danger,
    darkText,
    lightText,
  ];
}
```

Use Material 3 with explicit `ColorScheme`; do not generate the palette from a seed because that may introduce purple hues. Apply `FontFeature.tabularFigures()` to financial text. Use system fonts to avoid an unverified font license.

- [ ] **Step 3: implementar os componentes fundamentais**

`FinancialAmount` formats integer cents with `NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$')`. `OwnerSelector` is a segmented control with exactly `Lar`, `Eu`, `Esposa`. `SyncStatusView` accepts:

```dart
enum SyncVisualState { current, syncing, offline, failed }

final class SyncStatusData {
  const SyncStatusData({required this.state, required this.lastSuccessAt});
  final SyncVisualState state;
  final DateTime? lastSuccessAt;
}
```

Every component must expose semantic labels that do not reveal a hidden amount.

- [ ] **Step 4: provar os breakpoints antes do shell**

Add widget tests at 390×844 and 1366×768. Expected mobile: `NavigationBar`; expected desktop: `NavigationRail` or sidebar; no bottom bar on desktop.

Implement:

```dart
abstract final class LarBreakpoints {
  static const desktop = 900.0;
}

final class AdaptiveShell extends StatelessWidget {
  const AdaptiveShell({required this.child, required this.selectedIndex, required this.onSelect, super.key});
  final Widget child;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width >= LarBreakpoints.desktop;
    return desktop
        ? Row(children: [LarSidebar(selectedIndex: selectedIndex, onSelect: onSelect), Expanded(child: child)])
        : Scaffold(body: child, bottomNavigationBar: LarBottomNavigation(selectedIndex: selectedIndex, onSelect: onSelect));
  }
}
```

Only implemented destinations appear; no disabled future tabs.

- [ ] **Step 5: gerar e revisar goldens**

Run:

```powershell
flutter test --update-goldens test/design_system test/app/adaptive_shell_test.dart
flutter test test/design_system test/app/adaptive_shell_test.dart
flutter analyze
```

Compare the dark Home shell against `docs/design-assets/casa-de-valores-home-reference.png`. Use Impeccable v4 to critique hierarchy, density, focus and anti-patterns. Generated logo/plant ornaments must not be copied.

- [ ] **Step 6: commit e push**

After independent design/accessibility review:

```powershell
git add mobile/lib/app mobile/lib/design_system mobile/test mobile/pubspec.yaml mobile/pubspec.lock
git commit -m "feat: add Casa de Valores design system"
git push origin codex/sprint-4-flutter-foundation
```

Stop and request user authorization for Task 4.

---

### Task 4: Implementar domínio financeiro e cache Drift

**Routing — Task 4**

**Modelo:** `gpt-5.6-sol`
**Intensidade:** high
**Motivo:** o schema local preserva precisão, relações e versões; erro silencioso compromete Home e sync.
**Consumo esperado:** alto
**Ferramentas:** Drift, build_runner, SQLite e testes de migration/atomicidade.

**Files:**
- Create: `mobile/lib/core/money/minor_units.dart`, `mobile/lib/core/storage/app_database.dart`, `tables.dart`, `local_ledger.dart`, `mobile/lib/core/sync/sync_models.dart`, `mobile/test/core/money/minor_units_test.dart`, `mobile/test/core/storage/app_database_test.dart`, `migration_test.dart`
- Generate and commit: `mobile/lib/core/storage/app_database.g.dart`, `mobile/drift_schemas/schema_v1.json`

**Interfaces:**
- Consumes: bootstrap/entity payloads defined in `docs/openapi-v1.yaml` and `sync/registry.py`.
- Produces: `AppDatabase`, `DriftLocalLedger`, `parseMinorUnits`, `BootstrapPayload`, `SyncPage`, `SyncMetadata` and `HomeSnapshot` stream.

- [ ] **Step 1: escrever testes RED de dinheiro**

```dart
test('parses exact BRL decimal strings to minor units', () {
  expect(parseMinorUnits('0.00'), 0);
  expect(parseMinorUnits('24860.40'), 2486040);
  expect(parseMinorUnits('-12.05'), -1205);
});

test('rejects exponent and more than two decimal places', () {
  expect(() => parseMinorUnits('1e3'), throwsFormatException);
  expect(() => parseMinorUnits('10.001'), throwsFormatException);
});
```

Implement with `RegExp(r'^-?\d+\.\d{2}$')`, split whole/fraction and return signed integer cents. Do not call `double.parse`.

- [ ] **Step 2: definir schema v1**

Create Drift tables with text UUID primary keys and foreign-key UUID fields:

```dart
class Households extends Table {
  TextColumn get uuid => text()();
  TextColumn get name => text()();
  DateTimeColumn get updatedAt => dateTime()();
  @override Set<Column<Object>> get primaryKey => {uuid};
}

class Owners extends Table {
  TextColumn get uuid => text()();
  TextColumn get type => text().check(type.isIn(const ['self', 'spouse', 'shared']))();
  TextColumn get name => text()();
  @override Set<Column<Object>> get primaryKey => {uuid};
}
```

Define owner scope explicitly:

```dart
enum OwnerScopeKind { household, selfOwner, spouse }

final class OwnerScope {
  const OwnerScope.household() : kind = OwnerScopeKind.household, ownerUuid = null;
  const OwnerScope.self(String uuid) : kind = OwnerScopeKind.selfOwner, ownerUuid = uuid;
  const OwnerScope.spouse(String uuid) : kind = OwnerScopeKind.spouse, ownerUuid = uuid;

  final OwnerScopeKind kind;
  final String? ownerUuid;
}
```

Add equivalent `Accounts`, `Categories`, `Transactions`, `SyncState` and `LocalSettings`. Store `initialBalanceMinor` and `amountMinor` as integers; store dates as ISO-backed Drift dates; store `version` as integer. `SyncState` has singleton key `ledger`, cursor, `householdUuid`, `sessionDeviceUuid` and nullable `lastSuccessAt`.

The database is protected by each platform's application sandbox. This task does not claim client-side encryption at rest; enabling SQLCipher requires a separate threat-model decision and migration proof.

- [ ] **Step 3: escrever RED de bootstrap atômico**

The test opens `NativeDatabase.memory()`, seeds one old account, invokes `replaceBootstrap`, forces an invalid transaction relation, and asserts the old account and old cursor remain after the exception. A valid payload must replace all ledger rows and advance the cursor in the same transaction.

Required assertion:

```dart
expect(await db.select(db.accounts).get(), hasLength(1));
expect((await ledger.readSyncMetadata())?.cursor, 'cursor-before');
```

- [ ] **Step 4: implementar LocalLedger**

`replaceBootstrap` must execute one Drift transaction, delete child tables before parents, insert household/owners/accounts/categories/transactions, and update `SyncState` last. `applyDelta` must:

- reject unknown `entity_type` with `FormatException`;
- reject an older/equal version for an existing UUID without changing the row;
- upsert `create`/`update` payloads;
- delete the UUID for `operation == 'delete'`;
- update cursor only after all changes succeed.

The public methods match `LocalLedger` in the fixed contracts section.

- [ ] **Step 5: exportar schema e testar migration**

Run:

```powershell
dart run build_runner build --delete-conflicting-outputs
dart run drift_dev schema dump lib/core/storage/app_database.dart drift_schemas/
flutter test test/core/money test/core/storage
flutter analyze
```

Expected: schema v1 exported, generated file stable, tests pass. The migration test must create v1, reopen it, and preserve settings plus ledger rows.

- [ ] **Step 6: revisão, commit e push**

Review must check foreign relations, cents, version monotonicity, unknown entities, rollback and cursor ordering. Then:

```powershell
git add mobile/lib/core mobile/test/core mobile/drift_schemas
git commit -m "feat: add local financial cache"
git push origin codex/sprint-4-flutter-foundation
```

Stop and request user authorization for Task 5.

---

### Task 5: Implementar login, escolha do responsável e sessão segura

**Routing — Task 5**

**Modelo:** `gpt-5.6-sol`
**Intensidade:** xhigh
**Motivo:** tokens rotativos e refresh concorrente exigem uma única autoridade e falha segura.
**Consumo esperado:** alto
**Ferramentas:** Dio, flutter_secure_storage, Riverpod, testes concorrentes e widget tests.

**Files:**
- Create: `mobile/lib/core/network/api_error.dart`, `dio_transport.dart`, `session_transport.dart`, `mobile/lib/features/auth/domain/session.dart`, `data/secure_token_store.dart`, `data/auth_repository.dart`, `application/auth_controller.dart`, `presentation/login_screen.dart`, `presentation/device_owner_screen.dart`, `presentation/more_screen.dart`
- Create tests: `mobile/test/core/network/session_transport_test.dart`, `mobile/test/features/auth/auth_repository_test.dart`, `login_screen_test.dart`, `device_owner_screen_test.dart`
- Modify: `mobile/lib/app/router.dart`, `mobile/lib/main.dart`

**Interfaces:**
- Consumes: optional owner login from Task 2, `AppConfig`, `TokenStore` and routes from Task 3.
- Produces: `AuthRepository.login`, `selectDeviceOwner`, `logout`, `SessionTransport`, `AuthController` and guarded routes.

- [ ] **Step 1: definir tokens e cofre sem logs**

```dart
final class StoredTokens {
  const StoredTokens({required this.accessToken, required this.accessExpiresAt, required this.refreshToken, required this.refreshExpiresAt, required this.deviceUuid});
  final String accessToken;
  final DateTime accessExpiresAt;
  final String refreshToken;
  final DateTime refreshExpiresAt;
  final String deviceUuid;
}

final class SecureTokenStore implements TokenStore {
  SecureTokenStore(this.storage);
  final FlutterSecureStorage storage;
  static const _access = 'session.access';
  static const _accessExpiry = 'session.access_expiry';
  static const _refresh = 'session.refresh';
  static const _refreshExpiry = 'session.refresh_expiry';
  static const _deviceUuid = 'session.device_uuid';
}
```

Tests use an in-memory `FakeTokenStore`; they assert no token appears in `toString`, thrown error or captured logger events.

- [ ] **Step 2: escrever RED do refresh concorrente**

Create a fake transport that returns 401 to two simultaneous requests, delays refresh, then succeeds. Assert:

```dart
final responses = await Future.wait([
  client.getObject('/bootstrap/'),
  client.getObject('/devices/current/'),
]);
expect(fake.refreshCalls, 1);
expect(fake.retriedRequests, 2);
expect(responses, hasLength(2));
```

Add cases: refresh 401 clears tokens and throws `SessionExpired`; a retried request returning 401 is not refreshed again; network timeout preserves tokens and raises `OfflineFailure`.

- [ ] **Step 3: implementar renovação coordenada**

`SessionTransport` owns `Completer<StoredTokens>? _refreshing`. The first 401 creates it and calls `/auth/refresh/`; concurrent 401s await the same future. Store the rotated pair before completing. Mark retries using an internal boolean parameter, not a public header. Never disable TLS validation.

Exact refresh API body:

```dart
{'refresh_token': current.refreshToken}
```

Authorization header:

```dart
{'Authorization': 'Bearer ${tokens.accessToken}'}
```

- [ ] **Step 4: escrever e implementar fluxo de login**

`AuthRepository.login` posts:

```dart
{
  'email': email,
  'password': password,
  'platform': platformName,
  'name': deviceName,
}
```

Its public signature is:

```dart
Future<LoginResult> login({required String email, required String password});

final class DeviceOwnerOption {
  const DeviceOwnerOption({required this.uuid, required this.type, required this.name});
  final String uuid;
  final String type;
  final String name;
}

final class LoginResult {
  const LoginResult({required this.session, required this.owners});
  final StoredTokens session;
  final List<DeviceOwnerOption> owners;
}
```

`platformName` is selected with `Platform.isWindows`, `Platform.isAndroid` or `Platform.isIOS`. `deviceName` is `Lar Finance no Windows`, `Lar Finance no Android` or `Lar Finance no iPhone`; the user may rename it later in `Mais`, without a device-information plugin.

It stores returned tokens plus `device.uuid`, fetches `/owners/`, and routes to `/device-owner`. `selectDeviceOwner(uuid)` patches `/devices/current/` with `default_owner_uuid`, stores the selected UUID in `LocalSettings`, then allows initial sync. Choices are restricted to owner types `self` and `spouse`; `shared` is not a device identity.

- [ ] **Step 5: testar e implementar telas**

Widget tests cover invalid email, password visibility, submitting state, generic 401 message, offline failure, text scale 200%, Enter key on Windows, owner choice and logout. Login copy:

- title: `Entre no Lar Finance`;
- fields: `E-mail` and `Senha`;
- generic auth error: `Não foi possível entrar. Confira os dados e tente novamente.`;
- no signup/landing/forgot-password link unless a backend flow exists.

`MoreScreen` shows device name, last sync from local DB and logout. Logout calls `/auth/logout/`, clears tokens even if the server is unreachable, preserves ledger cache and routes to login.

- [ ] **Step 6: executar gates e fechar**

```powershell
flutter test test/core/network test/features/auth
flutter analyze
dart format --output=none --set-exit-if-changed lib test
git diff --check
```

After security and spec reviews:

```powershell
git add mobile/lib/core/network mobile/lib/features/auth mobile/lib/app mobile/test
git commit -m "feat: add secure device authentication"
git push origin codex/sprint-4-flutter-foundation
```

Stop and request user authorization for Task 6.

---

### Task 6: Implementar bootstrap e sincronização incremental atômica

**Routing — Task 6**

**Modelo:** `gpt-5.6-sol`
**Intensidade:** xhigh
**Motivo:** cursor e dados precisam avançar juntos; falha parcial não pode produzir cache incoerente.
**Consumo esperado:** alto
**Ferramentas:** fake API, Drift real em arquivo temporário, testes de concorrência e rede.

**Files:**
- Create: `mobile/lib/core/sync/sync_api.dart`, `sync_coordinator.dart`, `sync_state.dart`, `mobile/lib/features/auth/presentation/initial_sync_screen.dart`, `mobile/test/core/sync/sync_coordinator_test.dart`, `mobile/test/fixtures/bootstrap.json`, `delta_create_update_delete.json`
- Modify: `mobile/lib/app/app_lifecycle.dart`, `mobile/lib/main.dart`

**Interfaces:**
- Consumes: `SessionTransport`, `LocalLedger`, `/bootstrap/` and `/sync/changes/`.
- Produces: `DjangoSyncApi`, `LedgerSyncCoordinator`, `SyncState`, background refresh on launch/resume and pull-to-refresh.

- [ ] **Step 1: escrever fixtures sintéticas exatas**

`bootstrap.json` contains one household, three owners, two accounts, two categories, three transactions, the server summary and a cursor. Values are synthetic and follow `docs/openapi-v1.yaml`. `delta_create_update_delete.json` includes one transaction create, one account update and one category tombstone.

No real OFX, email, account identifier or production UUID enters fixtures.

- [ ] **Step 2: escrever RED de primeira sincronização e rollback**

Tests must assert:

```dart
final result = await coordinator.synchronize();
expect(result, SyncResult.updated);
expect((await ledger.readSyncMetadata())?.cursor, bootstrap.cursor);
expect(await database.select(database.transactions).get(), hasLength(3));
```

When the payload has a broken account reference, assert `SyncResult.failed`, zero new rows and unchanged prior cursor. When there is no cache and network is offline, assert `SyncResult.noCacheOffline`.

- [ ] **Step 3: implementar SyncApi e coordinator**

`DjangoSyncApi.fetchBootstrap()` maps `/bootstrap/`. `fetchChanges(cursor)` calls `/sync/changes/?cursor=...&limit=100`. `LedgerSyncCoordinator.synchronize()`:

1. acquires a single in-process mutex by sharing one in-flight Future;
2. reads local metadata;
3. uses bootstrap if cursor is absent;
4. otherwise pulls pages until a page returns fewer than 100 changes;
5. applies each page atomically;
6. records last success only with the page transaction;
7. maps network failure to offline without changing data/cursor.

Do not call `/sync/push/` in this sprint.

`InitialSyncScreen` shows indeterminate progress, a safe error with retry, and an explicit offline-without-cache message. It routes to `/home` only after the first valid local snapshot exists; it never displays a fake percentage.

On app restart, cached Home may render before the network only when `SyncState.sessionDeviceUuid` equals the UUID stored with the active secure session. A new login has a new device UUID and must complete bootstrap before any cached financial value is shown. Logout clears secure session material but preserves the ledger database.

- [ ] **Step 4: provar repetição, tombstone e concorrência**

Tests cover repeated cursor, empty delta, entity version older/equal/newer, tombstone, malformed cursor response, two simultaneous `synchronize()` calls and 101 changes over two pages. The fake must assert only one bootstrap/pull chain runs concurrently.

- [ ] **Step 5: ligar lifecycle sem loop agressivo**

On authenticated launch: render cached Home first, then call sync. On `AppLifecycleState.resumed`, sync only if the last successful sync is older than five minutes. Pull-to-refresh always requests sync but reuses the in-flight future.

`SyncState` exposes `idle`, `syncing`, `current`, `offline`, `failed`, timestamp and a safe retry action. Do not schedule background services or request OS background permissions.

- [ ] **Step 6: gates, revisão, commit e push**

```powershell
flutter test test/core/storage test/core/sync
flutter analyze
dart format --output=none --set-exit-if-changed lib test
git diff --check
```

Independent review must verify cursor ordering, pagination, atomicity, cache-first render and absence of push. Then:

```powershell
git add mobile/lib/core/sync mobile/lib/app mobile/test/core/sync mobile/test/fixtures
git commit -m "feat: add atomic ledger synchronization"
git push origin codex/sprint-4-flutter-foundation
```

Stop and request user authorization for Task 7.

---

### Task 7: Entregar Home real somente leitura

**Routing — Task 7**

**Modelo:** `gpt-5.6-sol`
**Intensidade:** high
**Motivo:** a Home mistura agregações monetárias, escopo de responsáveis e estados visuais; números enganosos são risco alto.
**Consumo esperado:** alto
**Ferramentas:** Drift queries, Riverpod, widget/golden tests e Impeccable v4.

**Files:**
- Create: `mobile/lib/features/home/domain/home_snapshot.dart`, `data/home_repository.dart`, `application/home_controller.dart`, `presentation/home_screen.dart`, `widgets/balance_header.dart`, `commitments_summary.dart`, `attention_list.dart`, `recent_transactions.dart`
- Create tests: `mobile/test/features/home/home_repository_test.dart`, `home_screen_test.dart`, `home_goldens_test.dart`
- Modify: `mobile/lib/core/storage/local_ledger.dart`, `mobile/lib/app/router.dart`

**Interfaces:**
- Consumes: local accounts/transactions/owners, `SyncState` and Casa de Valores components.
- Produces: reactive `HomeSnapshot` for `household`, `self` and `spouse`; Home route `/home`.

- [ ] **Step 1: fixar as fórmulas em testes RED**

For a selected owner scope:

```text
saldo consolidado = soma(initial_balance das contas do escopo)
                    + soma(receitas do escopo)
                    - soma(despesas do escopo)
gasto do mês = soma(despesas com date no mês local atual)
compromissos próximos = soma(despesas futuras entre amanhã e os próximos 30 dias)
movimentações recentes = 5 transações por date desc, updated_at desc, uuid desc
```

`Lar` includes all owner UUIDs, including `shared`. `Eu` and `Esposa` include only the corresponding owner UUID. The test must prove shared data does not leak into individual scopes and that an account initial balance is counted once.

- [ ] **Step 2: implementar consulta Home no Drift**

Expose:

```dart
final class HomeSnapshot {
  const HomeSnapshot({
    required this.scope,
    required this.balanceMinor,
    required this.monthExpenseMinor,
    required this.upcomingCommitmentMinor,
    required this.recentTransactions,
    required this.lastSyncedAt,
  });
  final OwnerScope scope;
  final int balanceMinor;
  final int monthExpenseMinor;
  final int upcomingCommitmentMinor;
  final List<HomeTransaction> recentTransactions;
  final DateTime? lastSyncedAt;
}

final class HomeTransaction {
  const HomeTransaction({
    required this.uuid,
    required this.description,
    required this.categoryName,
    required this.ownerName,
    required this.date,
    required this.signedAmountMinor,
  });
  final String uuid;
  final String description;
  final String categoryName;
  final String ownerName;
  final DateTime date;
  final int signedAmountMinor;
}
```

Use integer SQL sums and a single reactive query boundary. No network call belongs in `HomeRepository`.

- [ ] **Step 3: escrever widget tests de todos os estados**

Cover loading without cache, offline without cache, cache stale/offline, empty ledger, populated household, self, spouse, sync failure with retained cache, hidden values and 200% text scale. Required visible labels:

- `Saldo consolidado`;
- `Compromissos próximos`;
- `Gasto em agosto` using current localized month;
- `Movimentações recentes`;
- `Última sincronização`.

Never show `R$ 0,00` for a field whose source was absent or failed to parse; use `Indisponível`.

- [ ] **Step 4: construir a Home na ordem aprovada**

Layout order: sync/privacy row, owner selector, dominant balance, commitments/month spend, attention, recent movements. On desktop, constrain reading width and use a right context panel only above the desktop breakpoint. On mobile, use one scroll view and safe areas.

The attention section contains only evidence-backed states: sync failure, offline/stale cache, or missing account data. When none applies, omit the section; do not invent review counts or warnings from unavailable endpoints.

Movement rows expose description, category, owner, date and signed amount. Income and expense are distinguished by sign, label and color—not color alone.

- [ ] **Step 5: golden e crítica visual**

Generate light/dark mobile and Windows goldens using fixed fonts/device pixel ratio in tests. Compare with the approved Casa de Valores reference. Run Impeccable v4 review for hierarchy, density, adaptation, fake affordances and “AI slop”; fix all material findings.

Run:

```powershell
flutter test test/features/home
flutter test test/features/home/home_goldens_test.dart
flutter analyze
```

- [ ] **Step 6: revisão financeira, commit e push**

Reviewer must independently recompute fixtures for Lar/Eu/Esposa and inspect no `double` usage in financial paths. Then:

```powershell
git add mobile/lib/features/home mobile/lib/core/storage mobile/lib/app mobile/test/features/home
git commit -m "feat: add read-only financial home"
git push origin codex/sprint-4-flutter-foundation
```

Stop and request user authorization for Task 8.

---

### Task 8: Fechar privacidade, acessibilidade e adaptação nativa

**Routing — Task 8**

**Modelo:** `gpt-5.6-terra`
**Intensidade:** high
**Motivo:** integrações são limitadas e verificáveis, mas precisam respeitar três plataformas e tecnologias assistivas.
**Consumo esperado:** médio
**Ferramentas:** Flutter semantics, código nativo Android/iOS, Windows keyboard tests e goldens.

**Files:**
- Create: `mobile/lib/app/privacy_shield.dart`, `mobile/lib/app/value_visibility_controller.dart`, `mobile/test/app/privacy_shield_test.dart`, `value_visibility_test.dart`, `mobile/test/accessibility/home_accessibility_test.dart`
- Modify: `mobile/android/app/src/main/kotlin/online/palmbook/lar_finance/MainActivity.kt`, `mobile/ios/Runner/AppDelegate.swift`, `mobile/lib/main.dart`, `mobile/lib/app/adaptive_shell.dart`, Home widgets

**Interfaces:**
- Consumes: `LocalSettings`, lifecycle and Home components.
- Produces: persistent hide-values setting, lifecycle privacy cover, platform privacy handling, keyboard/focus and semantic compliance.

- [ ] **Step 1: escrever RED da preferência global**

Test that toggling visibility writes `values.hidden = true` to `LocalSettings`, survives controller reconstruction, and changes all `FinancialAmount` widgets. The semantics label when hidden must be `Valor oculto`, never the original amount.

- [ ] **Step 2: implementar ValueVisibilityController**

Use Riverpod with a repository backed by `LocalSettings`. Default to hidden only before the first preference read if the app is returning from an inactive state; otherwise use the persisted user choice. A single accessible button toggles the global state.

- [ ] **Step 3: testar e implementar privacy shield**

`PrivacyShield` observes lifecycle. For `inactive`, `paused`, `hidden` and `detached`, render an opaque Casa de Valores surface over financial routes; for `resumed`, restore content using the persisted visibility setting.

Android must set `WindowManager.LayoutParams.FLAG_SECURE` in `MainActivity.onCreate` to block screenshots/recent-app previews. iOS must add/remove an opaque overlay in application lifecycle callbacks. Windows uses the Flutter shield and documents that OS thumbnail behavior is best-effort, not a security boundary.

Android implementation:

```kotlin
package online.palmbook.lar_finance

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
}
```

iOS implementation in `AppDelegate`:

```swift
private var privacyView: UIView?

override func applicationDidEnterBackground(_ application: UIApplication) {
  super.applicationDidEnterBackground(application)
  guard let window = window else { return }
  let cover = UIView(frame: window.bounds)
  cover.backgroundColor = UIColor(red: 9 / 255, green: 19 / 255, blue: 17 / 255, alpha: 1)
  cover.accessibilityLabel = "Lar Finance protegido"
  window.addSubview(cover)
  privacyView = cover
}

override func applicationWillEnterForeground(_ application: UIApplication) {
  privacyView?.removeFromSuperview()
  privacyView = nil
  super.applicationWillEnterForeground(application)
}
```

The overlay contains no financial content.

- [ ] **Step 4: acessibilidade e teclado**

Tests enforce:

- every icon-only action has tooltip and semantic label;
- 200% text scale has no overflow at 320 logical pixels;
- owner selector announces selected state;
- sync state uses text plus icon, not color only;
- Tab traversal reaches privacy, owner selector, retry and navigation in visual order;
- Enter/Space activate focused controls;
- animations become zero/short when `disableAnimations` is true.

Android tap targets are at least 48 dp. iOS respects safe areas. Windows shows visible focus and hover feedback.

- [ ] **Step 5: gates, revisão, commit e push**

```powershell
flutter test test/app test/accessibility test/features/home
flutter analyze
dart format --output=none --set-exit-if-changed lib test
flutter build windows --debug
flutter build apk --debug
git diff --check
```

After privacy/accessibility review:

```powershell
git add mobile
git commit -m "feat: protect and adapt financial views"
git push origin codex/sprint-4-flutter-foundation
```

Stop and request user authorization for Task 9.

---

### Task 9: Executar jornada integrada, builds, instalável Windows e fechamento

**Routing — Task 9**

**Modelo:** `gpt-5.6-sol`
**Intensidade:** high
**Motivo:** o gate final cruza contrato, segurança, dados, UX, performance e distribuição em três plataformas.
**Consumo esperado:** alto
**Ferramentas:** integration_test, GitHub Actions Windows/macOS/Ubuntu, MSIX, servidor de teste e revisão transversal.

**Files:**
- Create: `mobile/integration_test/auth_sync_home_test.dart`, `mobile/tool/benchmark_home.dart`, `docs/sprints/sprint-4-flutter-foundation.md`
- Modify: `mobile/pubspec.yaml`, `.github/workflows/ci.yml`, `README.md`, `docs/README.md`, `docs/ROADMAP.md`, `PRD.md`

**Interfaces:**
- Consumes: todas as tasks anteriores e API v1 implantada.
- Produces: jornada automatizada, artefatos Windows/Android/iOS aplicáveis, evidência de performance e handoff da Sprint 4.

- [ ] **Step 1: criar teste integrado com servidor sintético controlado**

The integration harness starts a local fake HTTP server implementing login, owners, current-device patch, bootstrap, changes, refresh and logout. The test executes:

```text
fresh install → login → choose Eu → bootstrap → Home
→ stop fake server → relaunch → cached offline Home
→ start server with delta → resume → updated Home
→ expire access token → one refresh → successful retry
→ logout → login screen with ledger cache retained
```

Assert no request reaches `/sync/push/` and no fixture contains production credentials/data.

- [ ] **Step 2: medir abertura cache-first**

`benchmark_home.dart` seeds 20 accounts, 50 categories and 10,000 synthetic transactions, closes/reopens the database and measures from app bootstrap to first populated Home frame. Run 10 warm-cache iterations in release/profile mode on the documented Windows reference machine. Acceptance: median under 2 seconds; report median, p95, hardware, Flutter version and build mode. Do not claim Android/iOS performance without measurement.

- [ ] **Step 3: produzir instalável Windows**

Add the verified current Windows package builder as `msix: 3.18.0` under `dev_dependencies`, run `flutter pub get`, and configure:

```yaml
msix_config:
  display_name: Lar Finance
  identity_name: online.palmbook.larfinance
  publisher_display_name: Lar Finance
  publisher: CN=Lar Finance Private
  msix_version: 0.1.0.0
  capabilities: internetClient
  install_certificate: false
```

Run `flutter build windows --release` and `dart run msix:create --install-certificate false`. The CI artifact must include the MSIX and SHA-256 file. Certificate/signing for general distribution remains a release-sprint concern; for this private pilot, document the exact sideload trust step without weakening Windows globally.

- [ ] **Step 4: ampliar a matriz de CI**

Add:

- Ubuntu job: format, analyze, all unit/widget/golden tests;
- Windows job: Windows release build, MSIX creation and artifact upload;
- Ubuntu Android job: release APK build and artifact upload;
- macOS job: `flutter build ios --release --no-codesign` and tests.

All jobs read the committed Flutter version file. No credential, signing key or production login is required.

- [ ] **Step 5: executar matriz final fresca**

Local Windows commands:

```powershell
Set-Location mobile
flutter clean
flutter pub get
dart run build_runner build --delete-conflicting-outputs
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter test integration_test
flutter build windows --release
flutter build apk --release
dart run msix:create --install-certificate false
```

Repository commands:

```powershell
Set-Location ..
python -Wd manage.py test
python -m ruff check . --config pyproject.toml
python manage.py check
python manage.py check --deploy --fail-level WARNING
python manage.py makemigrations --check
git diff --check
```

Expected: every applicable command exits 0. iOS evidence comes from the macOS CI job; if no macOS run exists, status remains explicitly unverified.

- [ ] **Step 6: revisão transversal e documentação**

Independent reviewers cover:

1. spec compliance and no scope creep into writes/OFX/cards;
2. token/privacy/logging security;
3. SQLite/cursor/financial math;
4. Casa de Valores fidelity and accessibility;
5. Windows/Android/iOS build evidence.

`docs/sprints/sprint-4-flutter-foundation.md` records exact SHAs, commands/results, coverage available, performance, artifact hashes, CI URLs, residual risks, rollback and model audit. Update roadmap/PRD checkboxes only for evidence actually proven.

- [ ] **Step 7: commit, push e aguardar autorização de merge**

```powershell
git add mobile .github/workflows/ci.yml README.md PRD.md docs
git commit -m "docs: close Flutter foundation sprint"
git push origin codex/sprint-4-flutter-foundation
git status --short
git rev-list --left-right --count HEAD...origin/codex/sprint-4-flutter-foundation
```

Expected: only preserved user-owned untracked paths remain and branch sync is `0 0`. Do not merge to `main`, deploy or start Sprint 5 without explicit authorization.

---

## Matriz de cobertura da especificação

| Requisito | Task |
|---|---:|
| Windows/Android/iOS no mesmo workspace | 1, 9 |
| Casa de Valores claro/escuro | 3, 7 |
| shell adaptativo e Windows não esticado | 3, 7, 8 |
| login privado e responsável do dispositivo | 2, 5 |
| tokens no cofre e refresh único | 5 |
| SQLite local e atomicidade | 4, 6 |
| bootstrap/delta/offline/freshness | 6 |
| Home real Lar/Eu/Esposa | 7 |
| ocultar valores e app switcher | 8 |
| acessibilidade/motion/teclado | 3, 8 |
| cache-first abaixo de 2 segundos | 7, 9 |
| instalável Windows | 9 |
| Android e iOS validados | 1, 9 |
| testes, CI, revisão e documentação | todas; gate final 9 |

## Fora do escopo confirmado

- importação OFX no Flutter;
- edição/criação financeira e outbox;
- biometria, push, câmera, localização e contatos;
- cartões/faturas/limites/parcelas completos;
- publicação em lojas;
- cliente macOS e redesign final exclusivo de desktop;
- Open Finance ou provedor pago.

## Fontes técnicas verificadas em 13/08/2026

- [Flutter SDK archive](https://docs.flutter.dev/install/archive): stable é o canal recomendado; a página documenta a janela 3.47 para agosto de 2026, mas a Task 1 registra o patch exato realmente instalado.
- [GoRouter 17.3.0](https://pub.dev/packages/go_router)
- [flutter_secure_storage 10.3.1](https://pub.dev/packages/flutter_secure_storage)
- [Dio 5.11.0](https://pub.dev/packages/dio)
- [Flutter Riverpod 3.4.2](https://pub.dev/packages/flutter_riverpod)
- [Drift 2.34.3](https://pub.dev/packages/drift/versions)
- [drift_flutter 0.3.1](https://pub.dev/packages/drift_flutter)
- [drift_dev 2.34.5](https://pub.dev/packages/drift_dev)
- [build_runner 2.15.3](https://pub.dev/packages/build_runner)
- [intl 0.20.3](https://pub.dev/packages/intl)
- [msix 3.18.0](https://pub.dev/packages/msix/versions)

## Execution handoff

Recomendação: executar com **Subagent-Driven Development**, um implementador novo por task e revisão de especificação + qualidade antes de cada commit. O usuário recebe o resultado objetivo e autoriza explicitamente a task seguinte. A alternativa é execução inline com checkpoints, sem paralelizar tasks dependentes.
