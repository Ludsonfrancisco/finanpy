# Nubank OFX Flutter Import — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: use `test-driven-development`
> for every behavior change and `verification-before-completion` before each
> commit. Execute one task at a time. After commit and push, stop and wait for
> explicit owner authorization before the next task.

**Goal:** permitir que o app Flutter selecione um OFX Nubank de conta ou cartão,
mostre uma prévia detalhada e só grave os movimentos após confirmação explícita,
com criação automática e idempotente da conta padrão.

**Architecture:** Django permanece a autoridade: interpreta o arquivo em
memória, cria/reutiliza a conta, persiste somente a prévia normalizada, pagina os
itens e confirma tudo atomicamente. Flutter usa o seletor nativo, transporte
multipart autenticado e uma máquina de estados; nunca interpreta OFX nem grava
movimentos diretamente. Após confirmação, o pull existente atualiza Drift e a
Home.

**Tech Stack:** Python 3.12, Django 5.2.13, Django REST Framework 3.17.1,
SQLite, Ruff 0.15.11, Flutter 3.47.0, Dart 3.13.0, Dio 5.11.0,
Riverpod 3.4.2, GoRouter 17.3.0 e `file_picker 12.0.0` com pins exatos.

**Approved spec:**
`docs/superpowers/specs/2026-08-15-nubank-ofx-flutter-import-design.md`

## Global constraints

- Não ler arquivos OFX reais em testes automatizados. Não versionar nome,
  caminho, conteúdo, hash ou dado financeiro real.
- Fixtures são sintéticas e apenas reproduzem a estrutura técnica das duas
  variantes observadas.
- Não implementar limite, parcelas, faturas, Open Finance, CSV, PDF ou outros
  bancos.
- O servidor é autoridade. Flutter não faz parse, deduplicação nem criação local
  de transação.
- O arquivo bruto existe apenas em memória durante picker/upload/parse e não vai
  para Drift, secure storage ou logs.
- Dinheiro usa `Decimal` no backend e minor units inteiros no Flutter; `double`
  é proibido no domínio financeiro.
- Todos os acessos filtram o Lar de `request.auth`; conta e responsável não
  podem ser enviados livremente pelo cliente.
- Manter limite de 10 MiB, TTL de 23 h, purge em até 24 h, lock cooperativo do
  SQLite, confirmação atômica e deduplicação atuais.
- A conta padrão é `Nubank — Conta`/`checking` ou
  `Nubank — Cartão`/`credit`, moeda BRL, saldo inicial zero, responsável ativo
  `Eu`.
- Cada task: RED registrado, GREEN mínimo, testes focalizados, lint/checks,
  revisão, commit Conventional Commit, push e sincronismo remoto `0 0`.
- Não iniciar task seguinte, merge, deploy, instalação ou importação real sem
  autorização separada.

## Fixed API contract

As rotas existentes permanecem:

| Método | Rota | Uso Flutter |
| --- | --- | --- |
| POST | `/api/v1/imports/ofx/preview/` | multipart `file` e primeira página |
| GET | `/api/v1/imports/{batch_uuid}/?after={line}&limit=50` | próxima página/detalhe |
| POST | `/api/v1/imports/{batch_uuid}/bind-account/` | compatibilidade legada; app não chama |
| POST | `/api/v1/imports/{batch_uuid}/confirm/` | confirmação atômica |
| POST | `/api/v1/imports/{batch_uuid}/cancel/` | descarte da prévia |

Resumo ampliado, preservando os campos atuais:

```json
{
  "uuid": "00000000-0000-4000-8000-000000000000",
  "status": "preview_ready",
  "provider": "nubank",
  "product_type": "bank_account",
  "statement_start": "2026-08-01",
  "statement_end": "2026-08-12",
  "expires_at": "2026-08-16T12:00:00Z",
  "account_uuid": "00000000-0000-4000-8000-000000000001",
  "financial_owner_uuid": "00000000-0000-4000-8000-000000000002",
  "created_count": 0,
  "duplicate_count": 0,
  "warning_count": 0,
  "pending_count": 36,
  "record_count": 36,
  "income_total": "1000.00",
  "expense_total": "250.00",
  "is_repeated_file": false,
  "records": [
    {
      "uuid": "00000000-0000-4000-8000-000000000003",
      "posted_on": "2026-08-01",
      "description": "Descrição sintética",
      "amount": "25.00",
      "transaction_type": "expense",
      "outcome": "pending"
    }
  ],
  "next_cursor": "50"
}
```

`after` é a última `line_number` já recebida, codificada como inteiro decimal
positivo. `limit` padrão é 50 e máximo 100. A ordenação é `line_number, pk`. O
cursor nunca é identificador bancário. `next_cursor` é `null` na última página.

## Task 1: Compatibilizar o parser com as duas variantes reais

**Files:**

- Modify: `imports/ofx.py`
- Modify: `imports/tests/test_ofx.py`
- Create: `imports/tests/fixtures/nubank-account-utf8-none.ofx`
- Create: `imports/tests/fixtures/nubank-card-explicit-leaf-closing.ofx`

**Produces:** suporte estrito para UTF-8/NONE e SGML com fechamento explícito de
tags folha, sem copiar dados reais.

- [x] **Step 1: Criar fixtures anônimas mínimas**

Criar uma fixture de conta com cabeçalho:

```text
OFXHEADER:100
DATA:OFXSGML
VERSION:102
ENCODING:UTF-8
CHARSET:NONE
```

Criar uma fixture de cartão USASCII/1252 com tags folha explicitamente fechadas,
por exemplo `<CODE>0</CODE>`, mantendo somente nomes, IDs e valores sintéticos.

- [x] **Step 2: Escrever testes RED**

```python
def test_parses_utf8_none_account_statement(self):
    parsed = parse_nubank_ofx(load_fixture('nubank-account-utf8-none.ofx'))
    self.assertEqual(parsed.product_type, 'bank_account')
    self.assertEqual(parsed.transactions[0].description, 'Compra sintética ação')

def test_parses_sgml_card_with_explicit_leaf_closing_tags(self):
    parsed = parse_nubank_ofx(
        load_fixture('nubank-card-explicit-leaf-closing.ofx')
    )
    self.assertEqual(parsed.product_type, 'credit_card')

def test_rejects_unknown_encoding_and_mismatched_sgml_closing_tag(self):
    with self.assertRaises(OfxParseError):
        parse_nubank_ofx(unknown_encoding)
    with self.assertRaises(OfxParseError):
        parse_nubank_ofx(mismatched_closing_tag)
```

- [x] **Step 3: Executar o RED**

```powershell
$env:SECRET_KEY='task-only-secret-not-production'
$env:DEBUG='True'
python manage.py test imports.tests.test_ofx
```

Expected: UTF-8/NONE falha por encoding não suportado; cartão falha por markup.

- [x] **Step 4: Implementar decoder e tokenizer mínimos**

Extrair o cabeçalho anterior a `<OFX>` sem logá-lo. Aceitar somente:

```python
SUPPORTED_ENCODINGS = {
    (b'UTF-8', b'NONE'): 'utf-8',
    (b'USASCII', b'1252'): 'cp1252',
    (b'ASCII', b'1252'): 'cp1252',
    (None, b'1252'): 'cp1252',  # compatibilidade com fixtures legadas
}
```

Preservar `utf-8-sig`. No tokenizer SGML, aceitar fechamento explícito apenas
da última tag folha emitida; fechamento de container continua balanceado e
qualquer fechamento desconhecido ou fora de ordem gera `OfxParseError`.

- [x] **Step 5: Rodar regressões e privacidade**

```powershell
python manage.py test imports.tests.test_ofx api.tests.test_import_api
python -m ruff check --config pyproject.toml imports/ofx.py imports/tests/test_ofx.py
git diff --check
git status --short
```

Expected: testes verdes e nenhum dos dois arquivos reais no status/diff.

- [x] **Step 6: Revisar, commitar e enviar**

```powershell
git add imports/ofx.py imports/tests/test_ofx.py imports/tests/fixtures
git commit -m "fix(imports): parse real Nubank OFX variants"
git push origin codex/sprint-5-ofx-flutter
git rev-list --left-right --count HEAD...origin/codex/sprint-5-ofx-flutter
```

Expected: `0 0`. Parar e solicitar autorização para Task 2.

## Task 2: Criar e vincular automaticamente a conta padrão

**Files:**

- Modify: `imports/services.py`
- Modify: `imports/tests/test_services.py`
- Modify: `imports/tests/process_workers.py`

**Produces:** toda prévia compatível chega `preview_ready` com conta e owner `Eu`.

- [ ] **Step 1: Escrever testes RED do contrato nominal**

```python
def test_first_account_preview_creates_checking_account_owned_by_self(self):
    batch = create_preview(
        household=self.household,
        device_session=self.session,
        content=account_fixture,
    )
    self.assertEqual(batch.status, ImportBatch.PREVIEW_READY)
    self.assertEqual(batch.account.name, 'Nubank — Conta')
    self.assertEqual(batch.account.type, Account.CHECKING)
    self.assertEqual(batch.account.financial_owner.type, FinancialOwner.SELF)

def test_first_card_preview_creates_credit_account_and_cancel_keeps_it(self):
    batch = create_preview(..., content=card_fixture)
    account_id = batch.account_id
    cancel_preview(batch=batch)
    self.assertTrue(Account.objects.filter(pk=account_id).exists())
```

Também testar que segunda prévia da mesma fonte reutiliza `ImportAccountLink` e
não cria outra conta.

- [ ] **Step 2: Escrever RED de bordas e corrida**

- owner `Eu` ausente/inativo retorna `ImportStateError`, sem conta/lote parcial;
- conta existente é reutilizada somente quando há exatamente um candidato com
  mesmo Lar, owner `Eu`, nome, tipo e BRL;
- dois candidatos idênticos causam erro seguro, nunca escolha arbitrária;
- dois processos reais criando a mesma fonte terminam com um link e uma conta;
- conta criada gera `SyncChange` sob o `DeviceSession` da prévia;
- outro Lar recebe conta própria e nunca vê/reutiliza a primeira.

- [ ] **Step 3: Executar o RED**

```powershell
python manage.py test imports.tests.test_services
```

Expected: lote atual fica `needs_account_link` e nenhum default é criado.

- [ ] **Step 4: Implementar helper dentro do lock existente**

```python
DEFAULT_ACCOUNT_SPECS = {
    'bank_account': ('Nubank — Conta', Account.CHECKING),
    'credit_card': ('Nubank — Cartão', Account.CREDIT),
}

def _get_or_create_default_account(*, parsed, household, device_session):
    owner = FinancialOwner.objects.filter(
        household=household,
        type=FinancialOwner.SELF,
        is_active=True,
    ).first()
    if owner is None:
        raise ImportStateError('Default owner is unavailable.')
    # Executado sob FileLock + transaction.atomic da criação da prévia.
    # Reutiliza um único candidato exato; zero cria; múltiplos falham.
```

Criar `Account` com `user=device_session.user`, `currency='BRL'` e
`initial_balance=Decimal('0.00')`; executar `full_clean()` e salvar dentro de
`capture_sync_context`. Criar o `ImportAccountLink` antes do lote. Recuperar
`IntegrityError` consultando o vencedor; nunca expor `external_account_id`.

- [ ] **Step 5: Verificar domínio e concorrência**

```powershell
python manage.py test imports.tests.test_services sync.tests.test_capture
python -m ruff check --config pyproject.toml imports/services.py imports/tests
python manage.py check
python manage.py makemigrations --check --dry-run
git diff --check
```

- [ ] **Step 6: Revisar, commitar e enviar**

```powershell
git add imports/services.py imports/tests/test_services.py imports/tests/process_workers.py
git commit -m "feat(imports): create Nubank accounts automatically"
git push origin codex/sprint-5-ofx-flutter
```

Parar e solicitar autorização para Task 3.

## Task 3: Expor prévia detalhada e paginada

**Files:**

- Modify: `imports/models.py`
- Create: `imports/migrations/0004_import_record_uuid.py`
- Modify: `imports/services.py`
- Modify: `imports/tests/test_models.py`
- Modify: `imports/tests/test_migrations.py`
- Modify: `api/import_serializers.py`
- Modify: `api/import_views.py`
- Modify: `api/tests/test_import_api.py`
- Modify: `api/tests/test_openapi_contract.py`
- Modify: `docs/openapi-v1.yaml`

**Produces:** item público por UUID, totais financeiros e paginação estável.

- [ ] **Step 1: Escrever RED da migration**

Adicionar `uuid = models.UUIDField(...)` ao estado esperado do teste antes da
migration. O ensaio deve cobrir banco fresh e upgrade de `0003` com registros já
existentes, provando UUIDs distintos, `UNIQUE NOT NULL`, rollback para `0003` e
reaplicação.

- [ ] **Step 2: Implementar migration segura**

Usar três estágios:

1. adicionar UUID nullable e sem unique;
2. `RunPython` em lotes por PK preenchendo `uuid.uuid4()`;
3. alterar para `default=uuid.uuid4, unique=True, null=False`.

Não editar migrations históricas.

- [ ] **Step 3: Escrever testes RED de detalhe/paginação**

```python
def test_detail_returns_private_records_in_stable_pages(self):
    first = self.client.get(f'{url}?limit=2', **self.auth).json()
    self.assertEqual(len(first['records']), 2)
    self.assertEqual(first['next_cursor'], '2')
    self.assertEqual(
        set(first['records'][0]),
        {'uuid', 'posted_on', 'description', 'amount', 'transaction_type', 'outcome'},
    )

def test_detail_rejects_invalid_after_and_limit(self): ...
def test_detail_never_exposes_fitid_account_id_hash_or_file_name(self): ...
def test_foreign_household_cannot_page_records(self): ...
```

Testar limites 1, 50, 100 e rejeição de 0/101; página final retorna `null`.

- [ ] **Step 4: Implementar query e serialização sem N+1**

Criar `serialize_import_record(record)` e serviço de leitura que:

- filtra primeiro o batch pelo Lar;
- ordena `line_number, pk`;
- busca `limit + 1` registros com `line_number > after`;
- calcula em SQL `record_count`, `pending_count`, soma absoluta de income e
  expense;
- retorna `amount` sempre como magnitude decimal de duas casas e
  `transaction_type` separado;
- não retorna `external_id`, `fingerprint`, `line_number`, hash ou IDs internos.

O POST de preview devolve a primeira página no mesmo formato do GET.

- [ ] **Step 5: Atualizar OpenAPI e contrato executável**

Adicionar `ImportRecordPreview`, campos de totais, `records`, `next_cursor`,
parâmetros `after`/`limit` e exemplos apenas sintéticos. Manter os cinco métodos,
`OpaqueBearer` e respostas 400/401/404/503 existentes.

- [ ] **Step 6: Rodar gates backend**

```powershell
python manage.py test imports.tests api.tests.test_import_api api.tests.test_openapi_contract api.tests.test_observability
python -m ruff check --config pyproject.toml imports api
python manage.py check
python manage.py makemigrations --check --dry-run
python manage.py sqlmigrate imports 0004
git diff --check
```

- [ ] **Step 7: Revisar, commitar e enviar**

```powershell
git add imports api docs/openapi-v1.yaml
git commit -m "feat(api): paginate OFX preview records"
git push origin codex/sprint-5-ofx-flutter
```

Parar e solicitar autorização para Task 4.

## Task 4: Criar picker, modelos e repositório Flutter

**Files:**

- Modify: `mobile/pubspec.yaml`, `mobile/pubspec.lock`
- Modify: `mobile/lib/core/network/api_error.dart`
- Modify: `mobile/lib/core/network/dio_transport.dart`
- Modify: `mobile/lib/core/network/session_transport.dart`
- Create: `mobile/lib/features/imports/domain/import_preview.dart`
- Create: `mobile/lib/features/imports/data/ofx_file_picker.dart`
- Create: `mobile/lib/features/imports/data/import_repository.dart`
- Modify: `mobile/test/core/network/session_transport_test.dart`
- Create: `mobile/test/features/imports/import_repository_test.dart`
- Create: `mobile/test/features/imports/ofx_file_picker_test.dart`

**Produces:** fronteira Flutter testável para seleção, upload, paginação,
confirmação e cancelamento.

- [ ] **Step 1: Adicionar dependência com pin exato**

```powershell
cd mobile
flutter pub add file_picker:12.0.0
flutter pub get
flutter pub outdated
```

Não aceitar permissão ampla de storage em Android/iOS. O document picker nativo
é suficiente.

- [ ] **Step 2: Escrever RED do transporte**

Testar `SessionTransport.postObject` com `FormData`, refresh 401 único,
offline/timeout e parsing de envelope:

```dart
final class ServerFailure extends ApiError {
  const ServerFailure({required this.code, required this.statusCode});
  final String code;
  final int statusCode;
  @override
  String toString() => 'ServerFailure(code: $code, status: $statusCode)';
}
```

`toString()` e eventos nunca incluem body, descrição, valor, token ou arquivo.

- [ ] **Step 3: Escrever RED de parser JSON e dinheiro**

Cobrir UUID canônico, RFC3339 UTC, datas civis válidas, decimal de duas casas,
minor units inteiro, enums conhecidos, paginação e rejeição atômica de payload
parcial/malformado. Não usar `double.parse`.

- [ ] **Step 4: Escrever RED do file picker/repository**

Injetar interface:

```dart
abstract interface class OfxFilePicker {
  Future<SelectedOfx?> pick();
}

final class SelectedOfx {
  const SelectedOfx(this.bytes);
  final Uint8List bytes;
}
```

Testar cancelamento, extensão inválida, >10 MiB antes da rede, multipart com
filename constante `statement.ofx`, paginação ordenada, confirmação e
cancelamento. O nome real nunca sai do adapter.

- [ ] **Step 5: Implementar GREEN mínimo**

`FilePickerOfxPicker` usa:

```dart
FilePicker.platform.pickFiles(
  type: FileType.custom,
  allowedExtensions: const ['ofx'],
  allowMultiple: false,
  withData: true,
)
```

`DjangoImportRepository` usa `Dio FormData` e as rotas fixas. Mapeia os códigos
seguros do servidor para estados de domínio, sem usar a mensagem remota como
conteúdo de UI.

- [ ] **Step 6: Rodar gates Flutter focalizados**

```powershell
cd mobile
dart format --set-exit-if-changed lib test
flutter analyze
flutter test test/core/network/session_transport_test.dart test/features/imports
flutter build windows --debug
flutter build apk --debug
git diff --check
```

- [ ] **Step 7: Revisar, commitar e enviar**

```powershell
git add mobile
git commit -m "feat(mobile): add OFX import data pipeline"
git push origin codex/sprint-5-ofx-flutter
```

Parar e solicitar autorização para Task 5.

## Task 5: Implementar máquina de estados e integração de navegação

**Files:**

- Create: `mobile/lib/features/imports/application/import_controller.dart`
- Create: `mobile/test/features/imports/import_controller_test.dart`
- Modify: `mobile/lib/app/router.dart`
- Modify: `mobile/lib/features/auth/presentation/more_screen.dart`
- Modify: `mobile/lib/main.dart`
- Create: `mobile/test/features/imports/import_navigation_test.dart`
- Modify: testes existentes que constroem `MyApp`/`createAppRouter`

**Produces:** fluxo alcançável por Mais, sem corrida ou dupla confirmação.

- [ ] **Step 1: Escrever RED da máquina de estados**

Estados fixos:

```dart
enum ImportPhase {
  idle,
  picking,
  uploading,
  preview,
  confirming,
  completed,
  failure,
}
```

Testar:

- picker cancelado volta a idle sem erro;
- upload bem-sucedido carrega todas as páginas em ordem;
- offline, inválido, grande, expirado e ocupado viram erros seguros distintos;
- retry ignora conclusão obsoleta de operação anterior;
- dois taps em confirmar produzem uma chamada;
- cancelar limpa bytes/preview em memória;
- confirmação chama `LedgerSyncCoordinator.synchronize()` antes de completed;
- falha no pull mantém recibo completed e sinaliza dados pendentes de sync;
- `dispose()` invalida futures tardios.

- [ ] **Step 2: Implementar controller serializado**

Usar epoch monotônica e Future em voo. Nunca manter bytes depois que
`createPreview()` termina. Expor estado imutável e métodos `selectFile`,
`retry`, `loadMore`, `confirm`, `cancel` e `reset`.

- [ ] **Step 3: Escrever RED de rota/guard**

Testar que usuário autenticado abre `/more/import-ofx`, usuário deslogado é
redirecionado ao login e o botão **Importar OFX** recebe foco/ativação por
teclado. Back durante upload não inicia segunda operação nem perde logout.

- [ ] **Step 4: Integrar dependências**

Criar uma instância de `DjangoImportRepository` em `main.dart`; injetar no
router. Adicionar rota filha `/more/import-ofx`. `MoreScreen` recebe callback de
navegação, sem criar transporte próprio.

- [ ] **Step 5: Rodar gates focalizados**

```powershell
cd mobile
dart format --set-exit-if-changed lib test
flutter analyze
flutter test test/features/imports test/features/auth test/core/sync
git diff --check
```

- [ ] **Step 6: Revisar, commitar e enviar**

```powershell
git add mobile
git commit -m "feat(mobile): orchestrate OFX import flow"
git push origin codex/sprint-5-ofx-flutter
```

Parar e solicitar autorização para Task 6.

## Task 6: Construir a tela adaptativa Casa de Valores

**Files:**

- Create: `mobile/lib/features/imports/presentation/import_screen.dart`
- Create: `mobile/lib/features/imports/presentation/widgets/import_source_card.dart`
- Create: `mobile/lib/features/imports/presentation/widgets/import_summary.dart`
- Create: `mobile/lib/features/imports/presentation/widgets/import_record_list.dart`
- Create: `mobile/lib/features/imports/presentation/widgets/import_actions.dart`
- Create: `mobile/test/features/imports/import_screen_test.dart`
- Create: `mobile/test/accessibility/import_accessibility_test.dart`
- Create: `mobile/test/features/imports/import_goldens_test.dart`
- Create: `mobile/test/goldens/import_mobile_light.png`
- Create: `mobile/test/goldens/import_mobile_dark.png`
- Create: `mobile/test/goldens/import_windows_light.png`
- Create: `mobile/test/goldens/import_windows_dark.png`
- Modify: `mobile/lib/app/router.dart`

**Produces:** tela final, responsiva, acessível e sem aparência genérica.

- [ ] **Step 1: Escrever RED de estados visuais**

Cobrir idle, uploading, preview, empty, repeated, expired, busy, offline,
confirming, completed e atomic failure. Preview deve mostrar período, origem,
contagens, totais, item por item e ações Confirmar/Cancelar.

- [ ] **Step 2: Implementar mobile e desktop**

- mobile: fluxo vertical, SafeArea, resumo antes da lista, ações persistentes sem
  cobrir conteúdo;
- Windows >=900 px: conteúdo principal + painel lateral de resumo/ações;
- valores usam `FinancialAmount`/minor units;
- `Nubank — Conta` e `Nubank — Cartão` são rótulos do produto detectado, não
  prova criptográfica de origem;
- claro/escuro seguem `LarTheme`; nenhum roxo, gradiente decorativo ou card
  redundante;
- sem alertas, categorias ou lançamentos falsos.

- [ ] **Step 3: Escrever RED de acessibilidade**

Testar 320 px com escala 200%, alvos Android >=48 dp, iOS >=44 pt, SafeArea,
semântica de entrada/saída/duplicado/aviso, ordem de foco, Tab/Enter/Escape no
Windows, foco devolvido ao erro e `disableAnimations`.

- [ ] **Step 4: Gerar e inspecionar goldens em lote**

```powershell
cd mobile
flutter test --update-goldens test/features/imports/import_goldens_test.dart
flutter test test/features/imports/import_goldens_test.dart
```

Inspecionar as quatro imagens juntas. Regenerar uma única vez após a onda de
correções visuais. Não aprovar golden de placeholder ou com fonte Ahem.

- [ ] **Step 5: Rodar gates UI**

```powershell
dart format --set-exit-if-changed lib test
flutter analyze
flutter test test/features/imports test/accessibility/import_accessibility_test.dart
flutter build windows --debug
flutter build apk --debug
git diff --check
```

- [ ] **Step 6: Revisar, commitar e enviar**

```powershell
git add mobile
git commit -m "feat(mobile): build adaptive OFX import preview"
git push origin codex/sprint-5-ofx-flutter
```

Parar e solicitar autorização para Task 7.

## Task 7: Fechar integração, documentação e release candidate

**Files:**

- Create: `mobile/integration_test/ofx_import_preview_test.dart`
- Create: `docs/sprints/sprint-5-ofx-flutter-import.md`
- Modify: `.github/workflows/ci.yml`
- Modify: `README.md`
- Modify: `PRD.md`
- Modify: `docs/README.md`
- Modify: `docs/ROADMAP.md`
- Modify: `docs/imports-and-sync.md`
- Modify: `docs/mobile-ux.md`
- Modify: `docs/security-and-operations.md`

**Produces:** evidência reprodutível e candidato instalável; não faz deploy nem
importa arquivo real.

- [ ] **Step 1: Criar teste de integração sintético**

No servidor fake local: login já autenticado → Mais → selecionar bytes
sintéticos → multipart → prévia paginada → confirmar → pull → Home. Cobrir
também cancelamento e 401 com um único refresh. Assertar zero chamada a
`/sync/push/`.

- [ ] **Step 2: Fazer auditoria de privacidade**

Buscar paths Downloads, extensões dos dois arquivos reais, identificadores,
strings de fixture privada, tokens e segredos em diff/histórico da branch. O
teste deve verificar que multipart usa nome constante e logs de importação
contêm somente rota, status, request ID e códigos.

- [ ] **Step 3: Atualizar CI**

Garantir `flutter pub get`, format, analyze, unit/widget/golden tests, build
Windows, APK e iOS `--no-codesign` nos runners atuais. Não alegar iOS verde até
o job macOS real passar.

- [ ] **Step 4: Atualizar documentação honestamente**

Registrar:

- dois perfis Nubank estruturais suportados;
- importação ainda manual;
- contas padrão e owner `Eu`;
- preview detalhado, 10 MiB, 23/24 h, descarte bruto e dedup;
- limites/parcelas/faturas na Sprint 6;
- nenhum OFX real foi versionado;
- validação real ainda pendente de merge/deploy/install e autorização.

- [ ] **Step 5: Executar matriz final backend**

```powershell
$env:SECRET_KEY='final-gate-secret-not-production'
$env:DEBUG='True'
python -Wd manage.py test
coverage run manage.py test
coverage report --fail-under=90
python -m ruff check --config pyproject.toml .
python manage.py check
python manage.py makemigrations --check --dry-run
git diff --check
```

- [ ] **Step 6: Executar matriz final Flutter**

```powershell
cd mobile
flutter clean
flutter pub get
dart run build_runner build
dart format --set-exit-if-changed lib test integration_test
flutter analyze
flutter test
flutter test integration_test/ofx_import_preview_test.dart -d windows
flutter build windows --release
flutter build apk --release
dart run msix:create --install-certificate false
```

- [ ] **Step 7: Revisão final, commit e push**

```powershell
git add .github README.md PRD.md docs mobile
git commit -m "test: close Flutter OFX import task"
git push origin codex/sprint-5-ofx-flutter
git status --short
git rev-list --left-right --count HEAD...origin/codex/sprint-5-ofx-flutter
```

Expected: worktree limpa, `0 0`, nenhuma revisão Critical/Important. Parar.

## Manual validation gate — after implementation

Esta etapa não pode ocorrer automaticamente e não pertence ao commit da Task 7.
Exige, em sequência, autorizações separadas para:

1. mesclar a branch em `main`;
2. fazer deploy e validar migrations/processos no EasyPanel;
3. instalar o novo app Windows;
4. selecionar o OFX real de conta;
5. parar na prévia e conferir exatamente 36 itens, período e totais;
6. somente com nova autorização, confirmar os 36 movimentos;
7. repetir o gate de prévia e confirmação para os 28 itens do cartão.

Se a prévia divergir, cancelar. Não corrigir dados diretamente no banco e não
prosseguir ao cartão.

## Spec coverage

| Requisito | Tasks |
| --- | --- |
| UTF-8/NONE de conta e SGML real de cartão | 1 |
| criação/reuso automático das contas e owner Eu | 2 |
| detalhe privado, totais e paginação | 3 |
| picker nativo e multipart seguro | 4 |
| estados, concorrência, confirmação e pull | 5 |
| UX Casa de Valores e acessibilidade multiplataforma | 6 |
| privacidade, CI, documentação e release candidate | 7 |
| parada obrigatória antes de gravar dados reais | Manual validation gate |

## Plan self-review

- Sem placeholders, credenciais, caminhos dos arquivos reais ou dados pessoais.
- Cada requisito aprovado tem implementação e teste correspondente.
- Nenhuma task implementa fatura, limite, parcelas, outros bancos ou Open
  Finance.
- O vínculo automático substitui o passo manual apenas para os dois produtos
  Nubank; a rota de bind continua por compatibilidade.
- UUID de preview exige migration nova, sem alteração de migration histórica.
- Paginação tem ordenação, limites e cursor definidos.
- Erros, expiração, concorrência, cancelamento e retry têm comportamento
  verificável e fail-closed.
- Cada task termina com commit/push e bloqueia avanço até autorização.
