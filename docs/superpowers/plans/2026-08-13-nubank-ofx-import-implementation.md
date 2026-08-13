# Nubank OFX Import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** entregar uma API privada que recebe OFX Nubank, mostra prévia e só cria
lançamentos após confirmação atômica, sem armazenar o arquivo bruto.

**Architecture:** criar o app Django `imports` para conter modelos de lote,
linhas, referências bancárias e vínculo de conta. Um parser puro transforma bytes
OFX em objetos normalizados; serviços de domínio criam prévia, vínculo,
confirmação e cancelamento. Views DRF expõem o fluxo sob `/api/v1/imports/` e
reutilizam `DeviceSession`, isolamento por Lar, sinais de sync e o envelope de
erro já existentes.

**Tech Stack:** Python 3.12, Django 5.2.13, Django REST Framework 3.17.1,
SQLite, biblioteca padrão `xml.etree.ElementTree`, `hashlib`, `decimal`,
`datetime`, unittest/Django TestCase e Ruff 0.15.11.

## Global Constraints

- Primeiro formato: OFX Nubank de conta (`BANKACCTFROM`) e cartão (`CCACCTFROM`);
  CSV, PDF, outros bancos, fatura/limite/parcelas e Flutter não entram nesta
  entrega.
- Nunca versionar, logar, copiar para fixture ou persistir o OFX bruto. Fixtures
  precisam ser sintéticas e sem dados financeiros reais.
- Rejeitar arquivo acima de 10 MiB antes do parse; reter prévia normalizada no
  máximo por 24 horas; lote confirmado preserva apenas recibo, linhas
  normalizadas e assinaturas anti-duplicação.
- Todo arquivo exige prévia e confirmação explícita. Prévia, cancelamento, erro
  de parse e erro de confirmação não podem mudar `Transaction`.
- Associar automaticamente conta conhecida pelo identificador OFX. Conta
  desconhecida fica bloqueada até o usuário vinculá-la a uma conta do mesmo Lar;
  o responsável é sempre o da conta vinculada, nunca enviado livremente.
- Aplicar ou criar `Não categorizado` por Lar e por tipo (`income`/`expense`),
  sem inferir categoria a partir de descrição.
- Reimportação de arquivo confirmado usa SHA-256 por Lar; `FITID` é único por
  conta/provedor; similaridade por fingerprint somente cria aviso.
- Confirmar executa em uma única `transaction.atomic()` e utiliza
  `capture_sync_context(device_session=..., operation_id=None)` para que os
  lançamentos apareçam no delta da Sprint 2.
- Acesso somente por `DeviceSession` ativa; todas as consultas de conta, lote,
  linha e referência devem ser filtradas pelo Lar de `request.auth`.
- Logs de importação podem conter código, contagens, tipo de arquivo e request
  ID; nunca nome, caminho, hash completo, identificador de conta, descrição,
  valor ou conteúdo do OFX.
- Cada task concluída: testes focalizados, Ruff, `manage.py check`, migrations
  quando afetadas, revisão independente, commit Conventional Commit e push para
  `codex/sprint-3-ofx-import`. Não avançar à task seguinte sem autorização do
  usuário.

---

## Estrutura de arquivos

| Caminho | Responsabilidade |
| --- | --- |
| `imports/apps.py` | Registro do app e conexão dos sinais de sync somente para entidades sincronizáveis. |
| `imports/models.py` | `ImportAccountLink`, `ImportBatch`, `ImportRecord` e `SourceReference`; constraints e estados. |
| `imports/migrations/0001_initial.py` | Schema forward-only do domínio de importação. |
| `imports/ofx.py` | Parser puro, normalização e exceções sem Django/HTTP. |
| `imports/services.py` | Prévia, vínculo, confirmação, cancelamento, categoria padrão e deduplicação. |
| `imports/tests/fixtures/*.ofx` | OFX sintéticos de conta e cartão Nubank. |
| `imports/tests/test_models.py` | Constraints e expiração dos modelos. |
| `imports/tests/test_ofx.py` | Parser, encoding, campos obrigatórios e limites. |
| `imports/tests/test_services.py` | Fluxos de prévia, vínculo, deduplicação, atomicidade e sync. |
| `api/import_views.py` | Views DRF privadas de upload, leitura, vínculo, confirmação e cancelamento. |
| `api/import_serializers.py` | Corpos de resposta/entrada sem vazar dados indevidos. |
| `api/urls.py` | Rotas `/api/v1/imports/`. |
| `api/tests/test_import_api.py` | Autorização, multipart, envelope de erro e isolamento API. |
| `docs/openapi-v1.yaml` | Contrato das novas rotas e erros. |
| `docs/imports-and-sync.md` | Comportamento entregue, descarte do OFX e limitações reais. |
| `docs/sprints/sprint-3-ofx-import.md` | Handoff desta entrega, evidências, rollback e limites. |

## Contratos internos fixos

```python
# imports/ofx.py
@dataclass(frozen=True)
class ParsedOfxTransaction:
    external_id: str | None
    posted_on: date
    amount: Decimal
    description: str
    transaction_type: Literal['income', 'expense']

@dataclass(frozen=True)
class ParsedNubankOfx:
    product_type: Literal['bank_account', 'credit_card']
    external_account_id: str
    statement_start: date
    statement_end: date
    transactions: tuple[ParsedOfxTransaction, ...]

def parse_nubank_ofx(content: bytes) -> ParsedNubankOfx: ...

# imports/services.py
def create_preview(*, household, device_session, content: bytes) -> ImportBatch: ...
def bind_preview_account(*, batch: ImportBatch, account: Account) -> ImportBatch: ...
def confirm_preview(*, batch: ImportBatch, device_session) -> ImportBatch: ...
def cancel_preview(*, batch: ImportBatch) -> ImportBatch: ...
```

`create_preview()` nunca cria `Transaction`. `bind_preview_account()` só aceita
uma conta do mesmo Lar e sempre replica `account.financial_owner`. `confirm_preview()`
só aceita lote `preview_ready`, vinculado e não expirado; retorna o mesmo lote
`completed` em repetição, sem criar segunda transação.

### Task 1: Criar o domínio persistente de importação

**Files:**
- Create: `imports/__init__.py`, `imports/apps.py`, `imports/admin.py`,
  `imports/models.py`, `imports/migrations/__init__.py`,
  `imports/migrations/0001_initial.py`, `imports/tests/__init__.py`,
  `imports/tests/test_models.py`
- Modify: `core/settings.py`

**Consumes:** `Account`, `FinancialOwner`, `DeviceSession` e `Transaction` da
base atual.

**Produces:** modelos abaixo e migration aplicável em SQLite:

```python
class ImportAccountLink(models.Model):
    household: Household
    account: Account
    provider: str  # 'nubank'
    product_type: str  # 'bank_account' ou 'credit_card'
    external_account_id: str

class ImportBatch(models.Model):
    PREVIEW_READY = 'preview_ready'
    NEEDS_ACCOUNT_LINK = 'needs_account_link'
    COMPLETED = 'completed'
    FAILED = 'failed'
    CANCELLED = 'cancelled'
    household: Household
    device_session: DeviceSession
    account: Account | None
    financial_owner: FinancialOwner | None
    provider: str
    product_type: str
    file_sha256: str
    statement_start: date
    statement_end: date
    expires_at: datetime
    status: str
    created_count: int
    duplicate_count: int
    warning_count: int

class ImportRecord(models.Model):
    batch: ImportBatch
    line_number: int
    external_id: str | None
    posted_on: date
    amount: Decimal
    description: str
    transaction_type: str
    fingerprint: str
    outcome: str  # pending, duplicate, warning, created
    transaction: Transaction | None

class SourceReference(models.Model):
    account: Account
    provider: str
    external_id: str
    transaction: Transaction
```

- [ ] **Step 1: Escrever os testes de modelo antes do código**

```python
class ImportModelTest(TestCase):
    def test_link_is_unique_per_household_provider_product_and_external_id(self):
        ImportAccountLink.objects.create(...)
        with self.assertRaises(IntegrityError):
            ImportAccountLink.objects.create(...)

    def test_source_reference_rejects_same_fitid_for_same_account(self):
        SourceReference.objects.create(account=self.account, provider='nubank', external_id='fit-1', transaction=self.transaction)
        with self.assertRaises(IntegrityError):
            SourceReference.objects.create(account=self.account, provider='nubank', external_id='fit-1', transaction=self.transaction)
```

- [ ] **Step 2: Rodar os testes para registrar o RED**

Run: `..\finanpy-sprint2\.venv\Scripts\python.exe manage.py test imports.tests.test_models`

Expected: falha por `ModuleNotFoundError: No module named 'imports'`.

- [ ] **Step 3: Criar app, modelos e migration mínima**

```python
# imports/apps.py
class ImportsConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'imports'

# core/settings.py: acrescentar antes de api
'imports',

# imports/models.py: constraint essencial
models.UniqueConstraint(
    fields=['account', 'provider', 'external_id'],
    name='unique_import_source_reference',
)
```

Criar índices em `ImportBatch(household, status, expires_at)`,
`ImportRecord(batch, line_number)` e `SourceReference(account, provider,
external_id)`. Usar `PROTECT` para os vínculos financeiros, `CASCADE` apenas de
`ImportRecord` para seu próprio `ImportBatch`, e `SET_NULL` para o lançamento
eventualmente apagado por manutenção futura.

- [ ] **Step 4: Gerar, inspecionar e executar a migration**

Run:

```powershell
..\finanpy-sprint2\.venv\Scripts\python.exe manage.py makemigrations imports
..\finanpy-sprint2\.venv\Scripts\python.exe manage.py sqlmigrate imports 0001
..\finanpy-sprint2\.venv\Scripts\python.exe manage.py migrate
..\finanpy-sprint2\.venv\Scripts\python.exe manage.py test imports.tests.test_models
```

Expected: migration cria somente tabelas/índices/constraints do app `imports` e
os testes passam.

- [ ] **Step 5: Rodar gates da task**

Run:

```powershell
..\finanpy-sprint2\.venv\Scripts\python.exe -m ruff check --config pyproject.toml imports core/settings.py
..\finanpy-sprint2\.venv\Scripts\python.exe manage.py check
..\finanpy-sprint2\.venv\Scripts\python.exe manage.py makemigrations --check --dry-run
```

Expected: exit 0 em todos.

- [ ] **Step 6: Revisão, commit e push**

```powershell
git add imports core/settings.py
git commit -m "feat: add import batch domain"
git push origin codex/sprint-3-ofx-import
```

### Task 2: Implementar o parser OFX Nubank puro

**Files:**
- Create: `imports/ofx.py`, `imports/tests/test_ofx.py`,
  `imports/tests/fixtures/nubank-account.ofx`,
  `imports/tests/fixtures/nubank-card.ofx`,
  `imports/tests/fixtures/nubank-invalid.ofx`

**Consumes:** nenhum modelo ou HTTP; somente bytes sintéticos.

**Produces:** `parse_nubank_ofx(content: bytes) -> ParsedNubankOfx` e exceções
`OfxParseError`, `UnsupportedOfxError`, `OversizedOfxError`.

- [ ] **Step 1: Criar fixtures sintéticas e testes RED**

```python
def test_parses_nubank_bank_account_fitids_dates_amounts_and_signs(self):
    parsed = parse_nubank_ofx(load_fixture('nubank-account.ofx'))
    self.assertEqual(parsed.product_type, 'bank_account')
    self.assertEqual(parsed.transactions[0].external_id, 'synthetic-fitid-1')
    self.assertEqual(parsed.transactions[0].amount, Decimal('-12.34'))
    self.assertEqual(parsed.transactions[0].transaction_type, 'expense')

def test_parses_credit_card_structure_without_claiming_limit_or_installments(self):
    parsed = parse_nubank_ofx(load_fixture('nubank-card.ofx'))
    self.assertEqual(parsed.product_type, 'credit_card')

def test_rejects_non_ofx_missing_account_id_and_more_than_10_mib(self):
    with self.assertRaises(OfxParseError): parse_nubank_ofx(b'not-ofx')
    with self.assertRaises(UnsupportedOfxError): parse_nubank_ofx(missing_account_id)
    with self.assertRaises(OversizedOfxError): parse_nubank_ofx(b'x' * (10 * 1024 * 1024 + 1))
```

- [ ] **Step 2: Rodar o RED**

Run: `..\finanpy-sprint2\.venv\Scripts\python.exe manage.py test imports.tests.test_ofx`

Expected: falha porque `imports.ofx` ainda não existe.

- [ ] **Step 3: Implementar parse defensivo e determinístico**

```python
MAX_OFX_BYTES = 10 * 1024 * 1024

def parse_nubank_ofx(content: bytes) -> ParsedNubankOfx:
    if len(content) > MAX_OFX_BYTES:
        raise OversizedOfxError('Arquivo excede 10 MiB.')
    text = decode_ofx(content)  # tentar utf-8-sig e cp1252; nunca logar content
    root = parse_sgmlish_ofx(text)
    account = root.find('.//BANKACCTFROM') or root.find('.//CCACCTFROM')
    if account is None:
        raise UnsupportedOfxError('Estrutura OFX não suportada.')
    return build_parsed_nubank_statement(root, account)
```

Converter `TRNAMT` com `Decimal`, normalizar `-0` para `0.00`, derivar tipo pelo
sinal, exigir `DTPOSTED`, `TRNAMT`, `MEMO` e `ACCTID`, aceitar `FITID` ausente
como `None`, e recusar XML/OFX malformado sem traceback para o cliente.

- [ ] **Step 4: Rodar parser e regressões**

Run:

```powershell
..\finanpy-sprint2\.venv\Scripts\python.exe manage.py test imports.tests.test_ofx
..\finanpy-sprint2\.venv\Scripts\python.exe -m ruff check --config pyproject.toml imports
```

Expected: todos verdes; fixture real não aparece em `git status`.

- [ ] **Step 5: Revisão, commit e push**

```powershell
git add imports/ofx.py imports/tests
git commit -m "feat: parse Nubank OFX statements"
git push origin codex/sprint-3-ofx-import
```

### Task 3: Criar prévia, vínculo automático e deduplicação

**Files:**
- Create: `imports/services.py`, `imports/tests/test_services.py`
- Modify: `imports/models.py`, `imports/admin.py`

**Consumes:** `parse_nubank_ofx`, `ImportAccountLink`, `ImportBatch`,
`ImportRecord`, `SourceReference`, `Account`, `DeviceSession`.

**Produces:** `create_preview`, `bind_preview_account`, `cancel_preview` e
`get_batch_for_household`.

- [ ] **Step 1: Escrever testes RED para prévia e isolamento**

```python
def test_known_account_creates_preview_without_transactions(self):
    ImportAccountLink.objects.create(... external_account_id='synthetic-account')
    batch = create_preview(household=self.household, device_session=self.session, content=fixture_bytes)
    self.assertEqual(batch.status, ImportBatch.PREVIEW_READY)
    self.assertEqual(batch.account, self.account)
    self.assertEqual(batch.financial_owner, self.account.financial_owner)
    self.assertEqual(Transaction.objects.count(), 0)

def test_unknown_account_needs_link_and_foreign_account_is_rejected(self):
    batch = create_preview(... content=unknown_account_fixture)
    self.assertEqual(batch.status, ImportBatch.NEEDS_ACCOUNT_LINK)
    with self.assertRaises(ImportAccessError):
        bind_preview_account(batch=batch, account=self.foreign_account)

def test_duplicate_fitid_is_marked_duplicate_and_fingerprint_is_only_warning(self):
    SourceReference.objects.create(... external_id='synthetic-fitid-1')
    batch = create_preview(...)
    self.assertEqual(batch.duplicate_count, 1)
    self.assertEqual(batch.warning_count, 1)
```

- [ ] **Step 2: Rodar o RED**

Run: `..\finanpy-sprint2\.venv\Scripts\python.exe manage.py test imports.tests.test_services`

Expected: falha por `ImportError` para os serviços ausentes.

- [ ] **Step 3: Implementar serviços de prévia**

```python
def create_preview(*, household, device_session, content):
    parsed = parse_nubank_ofx(content)
    digest = hashlib.sha256(content).hexdigest()
    link = ImportAccountLink.objects.filter(
        household=household,
        provider='nubank',
        product_type=parsed.product_type,
        external_account_id=parsed.external_account_id,
    ).select_related('account__financial_owner').first()
    batch = ImportBatch.objects.create(
        household=household, device_session=device_session, provider='nubank',
        product_type=parsed.product_type, file_sha256=digest,
        account=link.account if link else None,
        financial_owner=link.account.financial_owner if link else None,
        status=ImportBatch.PREVIEW_READY if link else ImportBatch.NEEDS_ACCOUNT_LINK,
        expires_at=timezone.now() + timedelta(hours=24), ...
    )
    persist_normalized_records(batch, parsed)
    return recalculate_preview(batch)
```

Criar `ImportAccessError`, `ImportStateError` e `ExpiredPreviewError` sem usar
`ValidationError` de UI. `get_batch_for_household` filtra por `household` antes
de retornar o lote. `bind_preview_account` cria `ImportAccountLink` somente para
conta do Lar, valida que tipo `credit_card` só aponta para `Account.CREDIT`, e
recalcula duplicatas após o vínculo. Não usar descrição ou valor em logs.

- [ ] **Step 4: Rodar testes da task**

Run:

```powershell
..\finanpy-sprint2\.venv\Scripts\python.exe manage.py test imports.tests.test_models imports.tests.test_ofx imports.tests.test_services
..\finanpy-sprint2\.venv\Scripts\python.exe -m ruff check --config pyproject.toml imports
..\finanpy-sprint2\.venv\Scripts\python.exe manage.py check
```

Expected: exit 0.

- [ ] **Step 5: Revisão, commit e push**

```powershell
git add imports
git commit -m "feat: preview Nubank OFX imports"
git push origin codex/sprint-3-ofx-import
```

### Task 4: Confirmar atomicamente e produzir recibo sincronizável

**Files:**
- Modify: `imports/services.py`, `imports/models.py`, `imports/tests/test_services.py`

**Consumes:** batch `preview_ready` vinculado, registros normalizados e sinais
existentes de `Transaction`.

**Produces:** `confirm_preview` e categoria `Não categorizado` por Lar/tipo.

- [ ] **Step 1: Escrever testes RED de confirmação e rollback**

```python
def test_confirm_creates_transactions_source_references_and_sync_changes(self):
    batch = preview_for_known_account()
    confirmed = confirm_preview(batch=batch, device_session=self.session)
    self.assertEqual(confirmed.status, ImportBatch.COMPLETED)
    self.assertEqual(Transaction.objects.count(), 2)
    self.assertEqual(SourceReference.objects.count(), 2)
    self.assertEqual(SyncChange.objects.filter(household=self.household).count(), 2)
    self.assertEqual(Category.objects.filter(name='Não categorizado', type='expense').count(), 1)

def test_confirm_rolls_back_every_transaction_if_one_reference_conflicts(self):
    batch = preview_for_known_account()
    create_conflicting_reference_for_second_record()
    with self.assertRaises(ImportConflictError):
        confirm_preview(batch=batch, device_session=self.session)
    self.assertEqual(Transaction.objects.count(), 0)
    self.assertEqual(batch.refresh_from_db() or batch.status, ImportBatch.PREVIEW_READY)

def test_confirm_again_is_receipt_only_and_does_not_duplicate(self):
    confirm_preview(...)
    confirm_preview(...)
    self.assertEqual(Transaction.objects.count(), 2)
```

- [ ] **Step 2: Rodar o RED**

Run: `..\finanpy-sprint2\.venv\Scripts\python.exe manage.py test imports.tests.test_services`

Expected: falha por `confirm_preview` inexistente ou comportamento não atômico.

- [ ] **Step 3: Implementar confirmação sob transação**

```python
@transaction.atomic
def confirm_preview(*, batch, device_session):
    batch = ImportBatch.objects.select_for_update().select_related(
        'account__financial_owner', 'household'
    ).get(pk=batch.pk, household=device_session.household)
    assert_confirmable(batch, device_session)
    categories = {
        kind: get_or_create_uncategorized(
            household=batch.household, user=device_session.user, transaction_type=kind
        )
        for kind in {record.transaction_type for record in batch.records.all() if record.outcome == 'pending'}
    }
    with capture_sync_context(device_session=device_session, operation_id=None):
        for record in batch.records.filter(outcome='pending').order_by('line_number'):
            item = Transaction(..., category=categories[record.transaction_type])
            item.full_clean()
            item.save(force_insert=True)
            SourceReference.objects.create(...)
            record.transaction = item
            record.outcome = 'created'
            record.save(update_fields=['transaction', 'outcome'])
    batch.status = ImportBatch.COMPLETED
    batch.created_count = batch.records.filter(outcome='created').count()
    batch.save(update_fields=['status', 'created_count'])
    return batch
```

Usar `select_for_update` nos `SourceReference` por conta e referências recebidas
antes de criar transações, para impedir corrida. Registros `duplicate` não criam
transação. Registros `warning` permanecem elegíveis para criação depois da
confirmação explícita do lote. Em qualquer `IntegrityError` de referência,
traduzir para `ImportConflictError`, manter batch em prévia e deixar o bloco
atômico desfazer categoria e transações recém-criadas.

- [ ] **Step 4: Testar confirmação, sync e regressões**

Run:

```powershell
..\finanpy-sprint2\.venv\Scripts\python.exe manage.py test imports.tests.test_services sync.tests.test_capture api.tests.test_sync_pull
..\finanpy-sprint2\.venv\Scripts\python.exe -m ruff check --config pyproject.toml imports
```

Expected: pass; cada `Transaction` confirmada gera `SyncChange` no Lar correto.

- [ ] **Step 5: Revisão, commit e push**

```powershell
git add imports
git commit -m "feat: confirm OFX imports atomically"
git push origin codex/sprint-3-ofx-import
```

### Task 5: Expor o fluxo na API v1 e registrar contrato

**Files:**
- Create: `api/import_serializers.py`, `api/import_views.py`,
  `api/tests/test_import_api.py`
- Modify: `api/urls.py`, `docs/openapi-v1.yaml`

**Consumes:** serviços de importação e autenticação por `DeviceSession`.

**Produces:** rotas abaixo:

| Método | Rota | Corpo | Resultado |
| --- | --- | --- | --- |
| POST | `/api/v1/imports/ofx/preview/` | multipart `file` | lote e contagens da prévia |
| GET | `/api/v1/imports/<uuid:batch_uuid>/` | — | lote do Lar atual |
| POST | `/api/v1/imports/<uuid:batch_uuid>/bind-account/` | `{"account_uuid": "..."}` | lote atualizado |
| POST | `/api/v1/imports/<uuid:batch_uuid>/confirm/` | `{}` | recibo completed |
| POST | `/api/v1/imports/<uuid:batch_uuid>/cancel/` | `{}` | recibo cancelled |

- [ ] **Step 1: Escrever testes RED de API e privacidade**

```python
def test_preview_requires_device_token_and_returns_stable_counts(self):
    response = self.client.post('/api/v1/imports/ofx/preview/', {'file': uploaded_fixture}, format='multipart', **self.auth)
    self.assertEqual(response.status_code, 201)
    self.assertEqual(response.json()['status'], 'preview_ready')
    self.assertNotIn('description', response.json())
    self.assertNotIn('file_sha256', response.json())

def test_foreign_batch_and_foreign_account_return_not_found(self):
    self.assertEqual(self.client.get(f'/api/v1/imports/{self.foreign_batch.uuid}/', **self.auth).status_code, 404)
    response = self.client.post(f'/api/v1/imports/{self.batch.uuid}/bind-account/', {'account_uuid': str(self.foreign_account.uuid)}, format='json', **self.auth)
    self.assertEqual(response.status_code, 404)

def test_invalid_ofx_uses_error_envelope_and_log_has_no_content(self):
    response = self.client.post(... invalid_file ..., **self.auth)
    self.assertEqual(response.json()['error']['code'], 'invalid_ofx')
```

- [ ] **Step 2: Rodar o RED**

Run: `..\finanpy-sprint2\.venv\Scripts\python.exe manage.py test api.tests.test_import_api`

Expected: 404 para rota ainda inexistente.

- [ ] **Step 3: Implementar serializadores, views e URLs mínimas**

```python
class OfxPreviewView(APIView):
    parser_classes = [MultiPartParser]

    def post(self, request):
        serializer = OfxUploadSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        batch = create_preview(
            household=request.auth.household,
            device_session=request.auth,
            content=serializer.validated_data['file'].read(),
        )
        return Response(serialize_import_batch(batch), status=status.HTTP_201_CREATED)
```

Mapear `OfxParseError`, `UnsupportedOfxError`, `OversizedOfxError`,
`ExpiredPreviewError` e `ImportStateError` para subclasses DRF com códigos,
respectivamente, `invalid_ofx`, `unsupported_ofx`, `file_too_large`,
`expired_import_preview` e `invalid_import_state`. `serialize_import_batch()`
retorna UUID, status, provider, product type, período, `account_uuid` opcional,
`financial_owner_uuid` opcional e contagens; nunca retorna hash, identificador
de conta, linhas, valor ou descrição nesta primeira API.

- [ ] **Step 4: Atualizar OpenAPI com respostas reais**

Acrescentar as cinco rotas, `OpaqueBearer` como segurança, schema
`ImportBatchSummary`, schema `BindImportAccountRequest` e todos os códigos de
erro acima. Atualizar `api/tests/test_openapi_contract.py` para comparar paths,
métodos e `security` com callbacks das views reais, não com uma lista duplicada.

- [ ] **Step 5: Rodar gates da API**

Run:

```powershell
..\finanpy-sprint2\.venv\Scripts\python.exe manage.py test api.tests.test_import_api api.tests.test_openapi_contract api.tests.test_observability imports.tests
..\finanpy-sprint2\.venv\Scripts\python.exe -m ruff check --config pyproject.toml api imports
..\finanpy-sprint2\.venv\Scripts\python.exe manage.py check
```

Expected: rotas privadas, payloads estáveis e logs sem conteúdo financeiro.

- [ ] **Step 6: Revisão, commit e push**

```powershell
git add api imports docs/openapi-v1.yaml
git commit -m "feat: expose OFX import preview API"
git push origin codex/sprint-3-ofx-import
```

### Task 6: Verificar migration, documentar e fechar a primeira entrega

**Files:**
- Create: `docs/sprints/sprint-3-ofx-import.md`
- Modify: `docs/imports-and-sync.md`, `docs/ROADMAP.md`, `PRD.md`, `README.md`,
  `docs/README.md`
- Test: `imports/tests/test_migrations.py`, `api/tests/test_migrations.py`

**Consumes:** todo o fluxo anterior.

**Produces:** evidência reprodutível de migration, contrato, limites e próximo
passo; não marca a Sprint 3 inteira como concluída.

- [ ] **Step 1: Escrever testes RED de migration**

```python
class ImportMigrationTest(TransactionTestCase):
    def test_fresh_database_has_import_constraints_and_rollback_removes_only_import_schema(self):
        self.migrate_from = [('sync', '0001_initial')]
        self.migrate_to = [('imports', '0001_initial')]
        # criar Lar/conta antes, avançar, criar lote, voltar e provar que Account/Transaction persistem
```

- [ ] **Step 2: Executar o RED e implementar apenas a evidência necessária**

Run: `..\finanpy-sprint2\.venv\Scripts\python.exe manage.py test imports.tests.test_migrations`

Expected: falha inicial até o ensaio cobrir o novo app; depois passa sem alterar
migrations históricas.

- [ ] **Step 3: Atualizar documentação com o estado entregue**

Em `docs/imports-and-sync.md`, registrar OFX Nubank, limite 10 MiB, preview de
24 h, confirmação, descarte bruto, categoria `Não categorizado`, deduplicação
por hash/FITID e que limite/parcelas/fatura futura seguem fora de escopo. Em
`docs/ROADMAP.md`, marcar somente os itens efetivamente entregues da Sprint 3 e
manter CSV, outros bancos e conciliação abertos. O handoff deve listar SHA(s),
comandos, totais de teste/cobertura, rollback da migration, riscos e próximo
passo: profile CSV Nubank ou primeira fixture sintética Inter, sujeito à
autorização do usuário.

- [ ] **Step 4: Executar a matriz final**

Run:

```powershell
$env:SECRET_KEY = & ..\finanpy-sprint2\.venv\Scripts\python.exe -c "import secrets; print(secrets.token_urlsafe(64))"
$env:DEBUG = 'True'
$env:SECURE_SSL_REDIRECT = 'False'
..\finanpy-sprint2\.venv\Scripts\python.exe -Wd manage.py test
..\finanpy-sprint2\.venv\Scripts\python.exe -m coverage run manage.py test
..\finanpy-sprint2\.venv\Scripts\python.exe -m coverage report --fail-under=90
..\finanpy-sprint2\.venv\Scripts\python.exe -m ruff check --config pyproject.toml .
..\finanpy-sprint2\.venv\Scripts\python.exe manage.py check
..\finanpy-sprint2\.venv\Scripts\python.exe manage.py check --deploy --fail-level WARNING
..\finanpy-sprint2\.venv\Scripts\python.exe manage.py makemigrations --check --dry-run
git diff --check origin/main...HEAD
```

Expected: todos os comandos exit 0, cobertura maior ou igual a 90%, e nenhuma
mudança de OFX real no diff ou no histórico.

- [ ] **Step 5: Revisão final, commit e push**

```powershell
git add docs imports api PRD.md README.md
git commit -m "test: verify Nubank OFX import pilot"
git push origin codex/sprint-3-ofx-import
git rev-list --left-right --count HEAD...origin/codex/sprint-3-ofx-import
```

Expected: revisão sem achado Critical/Important e sincronismo `0 0`.

## Cobertura da especificação

| Requisito aprovado | Tasks |
| --- | --- |
| OFX Nubank conta e cartão, sem estimar limite/parcelas | 2 |
| Prévia obrigatória, conta conhecida/desconhecida e responsável automático | 1, 3, 5 |
| Categoria explícita `Não categorizado` | 4 |
| Descarte bruto, 10 MiB e 24 h | 2, 3, 5, 6 |
| Hash/FITID/similaridade e recibo | 1, 3, 4, 5 |
| Confirmação atômica e sync | 4, 5 |
| Isolamento, erros seguros e logs sem PII | 3, 5, 6 |
| Documentação, migration e rollback | 1, 6 |

## Auto-revisão do plano

- Cobertura: todos os requisitos da especificação possuem pelo menos uma task na
  tabela acima.
- Ambiguidade removida: categoria é `Não categorizado`, arquivo máximo é 10 MiB,
  prévia expira em 24 h, e a conta desconhecida exige vínculo com conta já
  existente do mesmo Lar.
- Consistência: os mesmos nomes `ImportBatch`, `ImportRecord`,
  `SourceReference`, `create_preview`, `bind_preview_account`,
  `confirm_preview` e `cancel_preview` são usados em todo o plano.
- Escopo: não há Flutter, CSV, Open Finance, cartão/fatura/limite/parcelas ou
  integração de outros bancos nesta primeira entrega.
