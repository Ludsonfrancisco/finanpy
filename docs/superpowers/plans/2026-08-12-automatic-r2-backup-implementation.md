# Lar Finance Automatic R2 Backup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Criar backup diário consistente do SQLite no Cloudflare R2, com confirmação remota, idempotência, retenção `14/8/12`, execução supervisionada e prova de restauração.

**Architecture:** O domínio separa configuração, catálogo/retenção, gateway S3, orquestração de execução única e agenda. `supervisord` mantém Gunicorn e agendador como processos independentes no mesmo container; o agendador chama exatamente o mesmo serviço usado pelo comando manual.

**Tech Stack:** Python 3.12, Django 5.2.13, SQLite backup API, boto3 1.43.53, filelock 3.32.0, Supervisor 4.3.0, Cloudflare R2 S3 API, Docker/EasyPanel.

## Global Constraints

- Branch: `codex/task-automatic-r2-backup`; base aprovada: commit `a198891`.
- Banco real: `/app/data/db.sqlite3`; nunca copiar diretamente um SQLite aberto.
- R2: bucket privado `lar-finance-backups`; prefixo operacional `production`.
- Agenda padrão: `03:00`, timezone `America/Sao_Paulo`; retry após falha: 60 minutos.
- Retenção: 14 datas diárias, 8 domingos, 12 primeiros dias do mês; preservar a união e sempre o objeto mais recente.
- Chave: `production/backups/YYYY/MM/lar-finance-YYYY-MM-DD.sqlite3`.
- Um objeto físico por data; domingo e primeiro dia do mês são rótulos do mesmo objeto.
- Não sobrescrever objeto remoto existente. Objeto conflitante causa falha.
- Retenção só começa depois de backup local íntegro, upload e `HeadObject` confirmados.
- Objetos desconhecidos ou fora do formato gerenciado nunca são excluídos.
- Nenhuma rota HTTP nova, nenhuma migration e nenhuma restauração automática em produção.
- Segredos entram apenas por variáveis do EasyPanel; nunca em Git, argumentos, logs ou relatórios.
- Logs não contêm conteúdo, descrição, valor, saldo, email, access key ou secret key.
- SQLite continua com uma réplica e um worker Gunicorn.
- Cada task: RED → GREEN → revisão → gates → commit → push → parar e pedir autorização.
- Antes de cada task, informar ao usuário modelo e intensidade recomendados.
- Não iniciar task seguinte, merge, deploy ou mudança externa sem autorização explícita.

## Plano de modelos

| Task | Modelo | Intensidade | Consumo | Motivo |
|---|---|---|---|---|
| 1 — Política e configuração | `gpt-5.6-sol` | `high` | Médio | Retenção decide exclusões financeiras; erro é difícil de detectar. |
| 2 — Gateway R2 | `gpt-5.6-sol` | `high` | Médio | Autenticação S3, paginação e validação remota. |
| 3 — Orquestração e comando | `gpt-5.6-sol` | `high` | Alto | Integridade SQLite, trava, cleanup e logs privados. |
| 4 — Agendador | `gpt-5.6-terra` | `high` | Médio | Máquina de estados temporal bem delimitada. |
| 5 — Supervisor e container | `gpt-5.6-sol` | `high` | Médio | Mudança de PID 1 e disponibilidade do serviço. |
| 6 — Gates e documentação | `gpt-5.6-sol` | `high` | Alto | Revisão transversal e recuperação. |
| 7 — Ativação real | `gpt-5.6-sol` | `xhigh` | Alto | Credenciais e produção financeira real. |

## Estrutura de arquivos

| Arquivo | Responsabilidade |
|---|---|
| `core/backup_config.py` | Ler e validar configuração R2/agenda sem expor segredos. |
| `core/backup_catalog.py` | Formar/interpretar chaves, metadados e calcular retenção pura. |
| `core/r2_storage.py` | Encapsular boto3: head, upload, paginação e exclusão. |
| `core/remote_backup.py` | Orquestrar trava, SQLite, hash, R2, retenção e cleanup. |
| `core/backup_logging.py` | Serializar eventos JSON sanitizados. |
| `core/backup_scheduler.py` | Calcular quando executar, repetir e dormir. |
| `core/management/commands/backup_to_r2.py` | Entrada manual de execução única. |
| `core/management/commands/run_backup_scheduler.py` | Processo de longa duração. |
| `deploy/supervisord.conf` | Supervisionar web e agendador. |
| `core/tests_backup_*.py` | Testes unitários/integração do domínio. |
| `households/tests/test_deployment.py` | Contrato do container: Supervisor + um worker. |

---

### Task 1: Política de catálogo, retenção e configuração

**Routing:** `gpt-5.6-sol` / `high`. Consumo esperado: médio.

**Files:**
- Create: `core/backup_config.py`
- Create: `core/backup_catalog.py`
- Create: `core/tests_backup_config.py`
- Create: `core/tests_backup_catalog.py`
- Modify: `requirements.txt`

**Interfaces:**
- Produces: `R2BackupConfig.from_env(environ) -> R2BackupConfig`
- Produces: `build_object_key(prefix: str, backup_date: date) -> str`
- Produces: `parse_managed_key(prefix: str, key: str) -> date | None`
- Produces: `retention_labels(backup_date: date) -> frozenset[str]`
- Produces: `select_retained_keys(objects: Sequence[CatalogObject], daily=14, weekly=8, monthly=12) -> set[str]`

- [ ] **Step 1: Fixar dependências exatas e escrever testes RED de configuração**

Adicionar a `requirements.txt` apenas depois do RED:

```text
boto3==1.43.53
filelock==3.32.0
supervisor==4.3.0
```

Em `core/tests_backup_config.py`, exigir endpoint HTTPS, credenciais, bucket, prefixo normalizado, `03:00`, `America/Sao_Paulo`, retry 3600 e `repr` sem segredo:

```python
from django.test import SimpleTestCase

from core.backup_config import BackupConfigurationError, R2BackupConfig


class R2BackupConfigTest(SimpleTestCase):
    def valid_env(self):
        return {
            'R2_BACKUP_ENDPOINT_URL': 'https://account.r2.cloudflarestorage.com',
            'R2_BACKUP_ACCESS_KEY_ID': 'access-id',
            'R2_BACKUP_SECRET_ACCESS_KEY': 'secret-value',
            'R2_BACKUP_BUCKET': 'lar-finance-backups',
        }

    def test_defaults_are_operational_and_secret_is_not_represented(self):
        config = R2BackupConfig.from_env(self.valid_env())

        self.assertEqual(config.prefix, 'production')
        self.assertEqual(config.schedule_time.isoformat(), '03:00:00')
        self.assertEqual(config.time_zone.key, 'America/Sao_Paulo')
        self.assertEqual(config.retry_seconds, 3600)
        self.assertNotIn('secret-value', repr(config))

    def test_rejects_non_https_endpoint_without_echoing_secret(self):
        environ = self.valid_env() | {
            'R2_BACKUP_ENDPOINT_URL': 'http://account.invalid',
        }

        with self.assertRaises(BackupConfigurationError) as raised:
            R2BackupConfig.from_env(environ)

        self.assertNotIn('secret-value', str(raised.exception))
```

- [ ] **Step 2: Executar RED da configuração**

```powershell
$env:SECRET_KEY = & $PYTHON -c "import secrets; print(secrets.token_urlsafe(64))"
& $PYTHON manage.py test core.tests_backup_config
```

Expected: `ModuleNotFoundError: No module named 'core.backup_config'`.

- [ ] **Step 3: Implementar configuração mínima**

Em `core/backup_config.py`, criar exceção e dataclass imutável. Campos secretos usam `repr=False`. `from_env` recebe explicitamente um mapping, valida as quatro variáveis obrigatórias, prefixo sem barras nas pontas, horário estrito `%H:%M`, timezone via `zoneinfo.ZoneInfo` e endpoint com `urlsplit(endpoint_url).scheme == 'https'`.

```python
@dataclass(frozen=True)
class R2BackupConfig:
    endpoint_url: str
    access_key_id: str = field(repr=False)
    secret_access_key: str = field(repr=False)
    bucket: str
    prefix: str
    schedule_time: time
    time_zone: ZoneInfo
    retry_seconds: int = 3600
    daily_retention: int = 14
    weekly_retention: int = 8
    monthly_retention: int = 12

    @classmethod
    def from_env(cls, environ: Mapping[str, str]) -> 'R2BackupConfig':
        required_names = (
            'R2_BACKUP_ENDPOINT_URL',
            'R2_BACKUP_ACCESS_KEY_ID',
            'R2_BACKUP_SECRET_ACCESS_KEY',
            'R2_BACKUP_BUCKET',
        )
        values = {name: environ.get(name, '').strip() for name in required_names}
        missing = [name for name, value in values.items() if not value]
        if missing:
            raise BackupConfigurationError(
                f'Missing backup configuration: {", ".join(missing)}'
            )

        endpoint_url = values['R2_BACKUP_ENDPOINT_URL']
        if urlsplit(endpoint_url).scheme != 'https':
            raise BackupConfigurationError('R2_BACKUP_ENDPOINT_URL must use HTTPS.')

        prefix = environ.get('R2_BACKUP_PREFIX', 'production').strip().strip('/')
        if not prefix:
            raise BackupConfigurationError('R2_BACKUP_PREFIX must not be empty.')

        schedule_text = environ.get('R2_BACKUP_TIME', '03:00').strip()
        try:
            schedule_time = datetime.strptime(schedule_text, '%H:%M').time()
        except ValueError as error:
            raise BackupConfigurationError('R2_BACKUP_TIME must use HH:MM.') from error

        zone_name = environ.get(
            'R2_BACKUP_TIME_ZONE', 'America/Sao_Paulo'
        ).strip()
        try:
            time_zone = ZoneInfo(zone_name)
        except ZoneInfoNotFoundError as error:
            raise BackupConfigurationError('R2_BACKUP_TIME_ZONE is invalid.') from error

        return cls(
            endpoint_url=endpoint_url,
            access_key_id=values['R2_BACKUP_ACCESS_KEY_ID'],
            secret_access_key=values['R2_BACKUP_SECRET_ACCESS_KEY'],
            bucket=values['R2_BACKUP_BUCKET'],
            prefix=prefix,
            schedule_time=schedule_time,
            time_zone=time_zone,
        )
```

Toda mensagem de erro cita apenas o nome da variável inválida.

- [ ] **Step 4: Executar GREEN da configuração**

Run: `& $PYTHON manage.py test core.tests_backup_config`

Expected: todos os testes do módulo passam.

- [ ] **Step 5: Escrever testes RED de catálogo e retenção**

Em `core/tests_backup_catalog.py`, cobrir formato exato, domingo, primeiro dia, união, limite e proteção do mais recente:

```python
from datetime import date
from django.test import SimpleTestCase

from core.backup_catalog import (
    CatalogObject,
    build_object_key,
    parse_managed_key,
    retention_labels,
    select_retained_keys,
)


class BackupCatalogTest(SimpleTestCase):
    def test_key_round_trip_and_unknown_key(self):
        key = build_object_key('production', date(2026, 8, 12))
        self.assertEqual(
            key,
            'production/backups/2026/08/lar-finance-2026-08-12.sqlite3',
        )
        self.assertEqual(parse_managed_key('production', key), date(2026, 8, 12))
        self.assertIsNone(parse_managed_key('production', 'production/manual.sqlite3'))

    def test_labels_share_one_physical_object(self):
        self.assertEqual(
            retention_labels(date(2026, 3, 1)),
            frozenset({'daily', 'weekly', 'monthly'}),
        )

    def test_retention_preserves_union_and_latest(self):
        objects = [
            CatalogObject(key=f'key-{day}', backup_date=date(2026, 1, day))
            for day in range(1, 32)
        ]
        retained = select_retained_keys(objects, daily=2, weekly=1, monthly=1)
        self.assertIn('key-31', retained)
        self.assertIn('key-25', retained)
        self.assertIn('key-1', retained)
```

- [ ] **Step 6: Executar RED do catálogo**

Run: `& $PYTHON manage.py test core.tests_backup_catalog`

Expected: `ModuleNotFoundError: No module named 'core.backup_catalog'`.

- [ ] **Step 7: Implementar catálogo e retenção puros**

Em `core/backup_catalog.py`, `CatalogObject` contém apenas `key` e `backup_date`. `parse_managed_key` usa regex ancorada e confirma que diretórios e data representam o mesmo dia. `retention_labels` sempre contém `daily`, adiciona `weekly` quando `weekday() == 6` e `monthly` quando `day == 1`. `select_retained_keys` ordena datas decrescentes, seleciona cada classe separadamente, une os conjuntos e adiciona sempre o objeto mais recente.

- [ ] **Step 8: Rodar GREEN e regressão de backup existente**

```powershell
& $PYTHON manage.py test core.tests_backup_config core.tests_backup_catalog core.tests_backup
& $PYTHON -m ruff check core/backup_config.py core/backup_catalog.py core/tests_backup_config.py core/tests_backup_catalog.py
```

Expected: testes e Ruff com exit code `0`.

- [ ] **Step 9: Commit e push da Task 1**

```powershell
git add requirements.txt core/backup_config.py core/backup_catalog.py core/tests_backup_config.py core/tests_backup_catalog.py
git commit -m "feat(backup): add retention policy"
git push
```

Parar e pedir autorização para Task 2.

---

### Task 2: Gateway S3 compatível com Cloudflare R2

**Routing:** `gpt-5.6-sol` / `high`. Consumo esperado: médio.

**Files:**
- Create: `core/r2_storage.py`
- Create: `core/tests_r2_storage.py`

**Interfaces:**
- Consumes: `R2BackupConfig`, `parse_managed_key`, `retention_labels`
- Produces: `RemoteObject(CatalogObject)` com `size`, `sha256` e `retention`
- Produces: `R2Storage.from_config(config) -> R2Storage`
- Produces: `R2Storage.head_managed(key) -> RemoteObject | None`
- Produces: `R2Storage.upload_and_verify(path, key, backup_date, sha256) -> RemoteObject`
- Produces: `R2Storage.list_managed() -> list[RemoteObject]`
- Produces: `R2Storage.delete(key) -> None`

- [ ] **Step 1: Instalar dependências pinadas no venv de trabalho**

Run: `& $PYTHON -m pip install -r requirements.txt`

Expected: boto3 `1.43.53`, filelock `3.32.0` e supervisor `4.3.0` instalados.

- [ ] **Step 2: Escrever testes RED com `botocore.stub.Stubber`**

Os testes usam credenciais fictícias e nunca acessam rede. O setup cria um cliente
boto3 com endpoint `https://account.invalid`, injeta-o em `R2Storage` e ativa
`botocore.stub.Stubber`. Implementar estes casos com parâmetros exatos:

- `head_object` com erro `NoSuchKey/404` retorna `None`;
- `head_object` com `ContentLength=4` e `Metadata={}` levanta
  `RemoteObjectInvalid`;
- `put_object` recebe bucket, key, `application/vnd.sqlite3`, stream e os quatro
  metadados; o `head_object` seguinte confirma tamanho/hash;
- `head_object` pós-upload com tamanho diferente levanta `RemoteVerificationError`;
- duas páginas de `list_objects_v2`, usando `NextContinuationToken`, retornam todos
  os objetos gerenciados, enquanto `production/manual.sqlite3` é ignorado sem head;
- `delete_object` recebe somente bucket e key exatos.

Exemplo completo do comportamento de ausência:

```python
def test_head_returns_none_only_for_not_found(self):
    key = 'production/backups/2026/08/lar-finance-2026-08-12.sqlite3'
    self.stubber.add_client_error(
        'head_object',
        service_error_code='NoSuchKey',
        http_status_code=404,
        expected_params={'Bucket': 'lar-finance-backups', 'Key': key},
    )

    with self.stubber:
        self.assertIsNone(self.storage.head_managed(key))
```

Para upload, criar arquivo temporário com bytes conhecidos, calcular SHA-256 e usar `botocore.stub.ANY` somente para o stream `Body`; bucket, key, content type e metadados devem ser exatos.

- [ ] **Step 3: Executar RED**

Run: `& $PYTHON manage.py test core.tests_r2_storage`

Expected: `ModuleNotFoundError: No module named 'core.r2_storage'`.

- [ ] **Step 4: Implementar gateway mínimo**

`R2Storage.from_config` cria cliente:

```python
boto3.client(
    service_name='s3',
    endpoint_url=config.endpoint_url,
    aws_access_key_id=config.access_key_id,
    aws_secret_access_key=config.secret_access_key,
    region_name='auto',
)
```

`RemoteObject` herda de `CatalogObject`, permitindo que a política de retenção
receba diretamente a listagem remota. `upload_and_verify` usa `put_object` com
`ContentType='application/vnd.sqlite3'` e metadados ASCII `sha256`, `size`,
`backup-date`, `retention`. Depois chama `head_managed` e compara key, data, size,
hash local e rótulos esperados para aquela data. `list_managed` usa paginator
`list_objects_v2`, filtra a chave antes do `HeadObject` e não retorna objetos
inválidos como gerenciados. Qualquer objeto no namespace gerenciado com metadados
inválidos levanta `RemoteObjectInvalid`; objetos fora do padrão são ignorados.

- [ ] **Step 5: Executar GREEN, regressões e Ruff**

```powershell
& $PYTHON manage.py test core.tests_r2_storage core.tests_backup_catalog
& $PYTHON -m ruff check core/r2_storage.py core/tests_r2_storage.py
```

Expected: exit code `0`.

- [ ] **Step 6: Commit e push da Task 2**

```powershell
git add core/r2_storage.py core/tests_r2_storage.py
git commit -m "feat(backup): add R2 storage gateway"
git push
```

Parar e pedir autorização para Task 3.

---

### Task 3: Orquestração segura e comando de execução única

**Routing:** `gpt-5.6-sol` / `high`. Consumo esperado: alto.

**Files:**
- Create: `core/remote_backup.py`
- Create: `core/backup_logging.py`
- Create: `core/management/commands/backup_to_r2.py`
- Create: `core/tests_remote_backup.py`
- Create: `core/tests_backup_to_r2_command.py`
- Modify: `core/settings.py`

**Interfaces:**
- Consumes: `backup_sqlite`, `R2BackupConfig`, `R2Storage`, catálogo/retenção
- Produces: `BackupOutcome(status, key, size, sha256, deleted_keys)`
- Produces: `execute_remote_backup(config, storage, database_path, now) -> BackupOutcome`
- Produces: management command `backup_to_r2`

- [ ] **Step 1: Escrever RED para repetição e conflito antes da cópia local**

Com fake storage em memória, provar que objeto válido retorna `already_exists` sem chamar `backup_sqlite`, e objeto inválido levanta erro sem upload ou exclusão.

```python
@patch('core.remote_backup.backup_sqlite')
def test_existing_valid_day_is_idempotent_before_local_copy(self, backup_mock):
    storage = Mock()
    storage.head_managed.return_value = RemoteObject(
        key='production/backups/2026/08/lar-finance-2026-08-12.sqlite3',
        backup_date=date(2026, 8, 12),
        size=180224,
        sha256='a' * 64,
        retention=frozenset({'daily'}),
    )

    outcome = execute_remote_backup(
        self.config, storage, self.db, self.now
    )
    self.assertEqual(outcome.status, 'already_exists')
    backup_mock.assert_not_called()
    storage.upload_and_verify.assert_not_called()
    storage.list_managed.assert_not_called()
```

- [ ] **Step 2: Executar RED**

Run: `& $PYTHON manage.py test core.tests_remote_backup`

Expected: módulo `core.remote_backup` ausente.

- [ ] **Step 3: Implementar preflight idempotente e `BackupOutcome`**

Criar `BackupOutcome` frozen dataclass. A primeira operação dentro da trava é `storage.head_managed(key)`. Existente válido encerra sem temp, upload ou retenção. Exceções públicas do módulo são técnicas e sanitizadas: `BackupAlreadyRunning`, `BackupVerificationError`, `BackupRetentionError`.

- [ ] **Step 4: Escrever RED para SQLite, hash, upload, retenção e cleanup**

Cobrir:

- arquivo temporário criado ao lado do banco no subdiretório `backups`;
- `backup_sqlite` e SHA-256 do arquivo real;
- upload confirmado antes de `list_managed`;
- exclusão somente da diferença entre catálogo e `select_retained_keys`;
- ordem determinística de exclusão, mais antiga primeiro;
- primeira falha de delete interrompe restantes;
- temp removido em sucesso, erro SQLite, upload, head, list e delete;
- `FileLock(timeout=0)` impede concorrência;
- último backup nunca entra na lista de delete.

- [ ] **Step 5: Executar RED focado**

Run: `& $PYTHON manage.py test core.tests_remote_backup`

Expected: falhas específicas nos comportamentos ainda ausentes.

- [ ] **Step 6: Implementar fluxo completo**

O esqueleto obrigatório de `execute_remote_backup` é:

```python
def execute_remote_backup(config, storage, database_path, now):
    source = Path(database_path).resolve()
    backup_date = now.astimezone(config.time_zone).date()
    key = build_object_key(config.prefix, backup_date)
    lock = FileLock(str(source.parent / '.lar-finance-r2-backup.lock'), timeout=0)

    with lock:
        existing = storage.head_managed(key)
        if existing is not None:
            return BackupOutcome.already_exists(existing)

        temporary_path = create_unused_temporary_path(source.parent / 'backups')
        try:
            backup_sqlite(source, temporary_path)
            size, sha256 = file_identity(temporary_path)
            remote = storage.upload_and_verify(
                temporary_path, key, backup_date, sha256
            )
            objects = storage.list_managed()
            retained = select_retained_keys(
                objects,
                config.daily_retention,
                config.weekly_retention,
                config.monthly_retention,
            )
            deleted = delete_expired_oldest_first(storage, objects, retained)
            return BackupOutcome.created(remote, deleted)
        finally:
            temporary_path.unlink(missing_ok=True)
```

`create_unused_temporary_path` fecha e remove o arquivo reservado antes de chamar `backup_sqlite`, que recusa overwrite.

- [ ] **Step 7: Escrever RED para logs e management command**

Testar `call_command('backup_to_r2')` com serviço patchado:

- sucesso produz JSON com timestamp UTC, `service=lar-finance-backup`,
  `event=backup_finished`, status, etapa, duração, key, size, hash de 12 caracteres e
  quantidade excluída;
- erro retorna `CommandError` sanitizado;
- capture de stdout/stderr/log nunca contém access id, secret, conteúdo SQLite ou descrição financeira usada como sentinela.

- [ ] **Step 8: Implementar serialização e comando**

`core/backup_logging.py` expõe:

```python
def serialize_backup_event(*, timestamp, event, status, stage,
                           key=None, size=None,
                           sha256=None, duration_ms=None, deleted_count=0,
                           error_code=None) -> str:
    payload = {
        'timestamp': timestamp.astimezone(UTC).isoformat(),
        'service': 'lar-finance-backup',
        'event': event,
        'status': status,
        'stage': stage,
        'key': key,
        'size': size,
        'sha256': sha256[:12] if sha256 else None,
        'duration_ms': duration_ms,
        'deleted_count': deleted_count,
        'error_code': error_code,
    }
    return json.dumps(payload, ensure_ascii=False, separators=(',', ':'))
```

O hash é abreviado para 12 caracteres somente no log. `backup_to_r2` lê config via `R2BackupConfig.from_env(os.environ)`, banco via `settings.DATABASES['default']`, cria `R2Storage`, mede `time.monotonic()` e converte apenas exceções conhecidas em `CommandError` com código estável. Adicionar logger `lar_finance.backup` em `core/settings.py`, usando o handler JSON de stdout já existente e sem propagação.

- [ ] **Step 9: GREEN, regressões, check e Ruff**

```powershell
& $PYTHON manage.py test core.tests_remote_backup core.tests_backup_to_r2_command core.tests_backup
& $PYTHON manage.py check
& $PYTHON -m ruff check core
```

Expected: exit code `0`, sem secrets no output.

- [ ] **Step 10: Commit e push da Task 3**

```powershell
git add core/remote_backup.py core/backup_logging.py core/management/commands/backup_to_r2.py core/tests_remote_backup.py core/tests_backup_to_r2_command.py core/settings.py
git commit -m "feat(backup): upload verified SQLite copies"
git push
```

Parar e pedir autorização para Task 4.

---

### Task 4: Agendador diário recuperável

**Routing:** `gpt-5.6-terra` / `high`. Consumo esperado: médio.

**Files:**
- Create: `core/backup_scheduler.py`
- Create: `core/management/commands/run_backup_scheduler.py`
- Create: `core/tests_backup_scheduler.py`

**Interfaces:**
- Consumes: `R2BackupConfig.schedule_time`, `time_zone`, `retry_seconds`
- Produces: `LastAttempt(at: datetime, succeeded: bool)`
- Produces: `SchedulerDecision(run_now: bool, sleep_seconds: float)`
- Produces: `decide_next_action(now, schedule_time, time_zone, retry_seconds, last_attempt) -> SchedulerDecision`
- Produces: management command `run_backup_scheduler`

- [ ] **Step 1: Escrever RED da máquina de estados temporal**

Cobrir São Paulo com datetimes aware e esta matriz exata:

| Agora local | Última tentativa | Resultado esperado |
|---|---|---|
| `2026-08-12 02:00-03:00` | nenhuma | `run_now=False`, sleep `3600` |
| `2026-08-12 03:00-03:00` | nenhuma | `run_now=True`, sleep `0` |
| `2026-08-12 20:00-03:00` | nenhuma | `run_now=True`, sleep `0` |
| `2026-08-12 20:00-03:00` | sucesso em 12/08 | sleep até `13/08 03:00` |
| `2026-08-12 20:30-03:00` | falha às 20:00 | sleep `1800` |
| `2026-08-12 21:00-03:00` | falha às 20:00 | `run_now=True` |
| restart `2026-08-12 21:00-03:00` | memória vazia | `run_now=True` |

Adicionar um caso sintético com `ZoneInfo('America/New_York')` atravessando a
mudança de DST; o resultado deve ser datetime aware e apontar para `03:00` local,
sem somar cegamente 24 horas.

- [ ] **Step 2: Executar RED**

Run: `& $PYTHON manage.py test core.tests_backup_scheduler`

Expected: módulo ausente.

- [ ] **Step 3: Implementar decisões puras**

`LastAttempt` contém o datetime aware `at` e `succeeded`. Antes da janela, dormir
até hoje às `03:00`; depois da janela sem tentativa, rodar agora; após sucesso na
data local corrente, dormir até amanhã; após falha, dormir somente até
`last_attempt.at + retry_seconds` e rodar assim que esse instante chegar. Todos os
cálculos são aware e convertidos pela timezone configurada. Uma tentativa de data
anterior não impede o backup da data corrente.

- [ ] **Step 4: Escrever RED do comando sem loop infinito**

Patchar `time.sleep`, relógio e `call_command`. O sleeper lança uma exceção sentinela após receber o primeiro delay. Verificar:

- chama `backup_to_r2` após `03:00`;
- `CommandError` gera retry, não encerra processo;
- sucesso agenda dia seguinte;
- sinal `KeyboardInterrupt` encerra limpo;
- logs contêm somente códigos técnicos.

- [ ] **Step 5: Implementar comando de longa duração**

O loop chama `decide_next_action`; quando `run_now`, usa `call_command('backup_to_r2')`, atualiza `LastAttempt`, registra resultado e recalcula. O loop não captura `KeyboardInterrupt` como falha e não contém lógica de R2/SQLite.

- [ ] **Step 6: GREEN, checks e Ruff**

```powershell
& $PYTHON manage.py test core.tests_backup_scheduler core.tests_backup_to_r2_command
& $PYTHON manage.py check
& $PYTHON -m ruff check core/backup_scheduler.py core/management/commands/run_backup_scheduler.py core/tests_backup_scheduler.py
```

Expected: exit code `0`.

- [ ] **Step 7: Commit e push da Task 4**

```powershell
git add core/backup_scheduler.py core/management/commands/run_backup_scheduler.py core/tests_backup_scheduler.py
git commit -m "feat(backup): schedule daily R2 copies"
git push
```

Parar e pedir autorização para Task 5.

---

### Task 5: Supervisor, Docker e isolamento do web

**Routing:** `gpt-5.6-sol` / `high`. Consumo esperado: médio.

**Files:**
- Create: `deploy/supervisord.conf`
- Modify: `Dockerfile`
- Modify: `docker-compose.yml`
- Modify: `households/tests/test_deployment.py`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: commands `gunicorn core.wsgi:application` e `python manage.py run_backup_scheduler`
- Produces: container com PID 1 `supervisord`, um worker web e um scheduler independente

- [ ] **Step 1: Escrever RED do contrato de deploy**

Ampliar `SQLiteDeploymentConfigurationTest` para ler `deploy/supervisord.conf` com `configparser.RawConfigParser(interpolation=None)` e provar:

- `program:web` chama Gunicorn com `--workers 1`;
- `program:backup-scheduler` chama o comando Django;
- ambos usam `autorestart=true`, stdout/stderr do container e grupos de sinal;
- `Dockerfile` inicia `supervisord -c /app/deploy/supervisord.conf`;
- Compose não substitui esse comando por migrate automático ou Gunicorn direto.

- [ ] **Step 2: Executar RED**

Run: `& $PYTHON manage.py test households.tests.test_deployment`

Expected: `deploy/supervisord.conf` ausente e manifests incompatíveis.

- [ ] **Step 3: Criar configuração Supervisor**

Conteúdo funcional:

```ini
[supervisord]
nodaemon=true
logfile=/dev/null
pidfile=/tmp/supervisord.pid

[program:web]
command=gunicorn core.wsgi:application --bind 0.0.0.0:8000 --workers 1
directory=/app
autostart=true
autorestart=true
startsecs=5
stopsignal=TERM
stopasgroup=true
killasgroup=true
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0
stderr_logfile=/dev/fd/2
stderr_logfile_maxbytes=0

[program:backup-scheduler]
command=python manage.py run_backup_scheduler
directory=/app
autostart=true
autorestart=true
startsecs=5
stopsignal=TERM
stopasgroup=true
killasgroup=true
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0
stderr_logfile=/dev/fd/2
stderr_logfile_maxbytes=0
```

Dockerfile termina com `CMD ["supervisord", "-c", "/app/deploy/supervisord.conf"]`. Compose remove o comando que executa migrations automaticamente e herda o CMD da imagem. Migrations continuam operação explícita do runbook.

- [ ] **Step 4: Adicionar build de imagem à CI**

Depois dos checks Django, adicionar:

```yaml
      - name: Build production image
        run: docker build --tag lar-finance-ci:${{ github.sha }} .
```

Isso confirma instalação dos pins e presença do config no build.

- [ ] **Step 5: GREEN local e smoke de container**

```powershell
& $PYTHON manage.py test households.tests.test_deployment core.tests_backup_scheduler
docker build --tag lar-finance-backup-local .
docker run --rm lar-finance-backup-local supervisord --version
```

Expected: testes verdes, build exit `0`, versão `4.3.0`. Se Docker local não estiver disponível, registrar a limitação e exigir o job CI verde antes de concluir a task.

- [ ] **Step 6: Commit e push da Task 5**

```powershell
git add deploy/supervisord.conf Dockerfile docker-compose.yml households/tests/test_deployment.py .github/workflows/ci.yml
git commit -m "build: supervise web and backup scheduler"
git push
```

Parar e pedir autorização para Task 6.

---

### Task 6: Gates transversais, runbook e handoff

**Routing:** `gpt-5.6-sol` / `high`. Consumo esperado: alto.

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`
- Modify: `PRD.md`
- Modify: `docs/README.md`
- Modify: `docs/ROADMAP.md`
- Modify: `docs/deploy-easypanel.md`
- Modify: `docs/security-and-operations.md`
- Create: `docs/sprints/automatic-r2-backup.md`
- Create: `.superpowers/sdd/automatic-r2-backup-report.md` (ignorado pelo Git)

**Interfaces:**
- Consumes: toda a implementação Tasks 1–5
- Produces: runbook reproduzível, rollback, matriz de evidência e branch pronta para revisão/merge

- [ ] **Step 1: Executar testes focados com warnings como erro**

```powershell
$env:SECRET_KEY = & $PYTHON -c "import secrets; print(secrets.token_urlsafe(64))"
$env:SECURE_SSL_REDIRECT = 'False'
& $PYTHON -Wd manage.py test core.tests_backup core.tests_backup_config core.tests_backup_catalog core.tests_r2_storage core.tests_remote_backup core.tests_backup_to_r2_command core.tests_backup_scheduler households.tests.test_deployment
```

Expected: zero falhas e nenhuma `DeprecationWarning`.

- [ ] **Step 2: Executar suíte e cobertura completas**

```powershell
& $PYTHON -Wd manage.py test
& $PYTHON -m coverage erase
& $PYTHON -m coverage run manage.py test
& $PYTHON -m coverage report --fail-under=90
```

Expected: todos os testes passam e cobertura total ≥90%.

- [ ] **Step 3: Executar gates estáticos e de segurança**

```powershell
& $PYTHON -m ruff check . --config pyproject.toml
& $PYTHON manage.py check
& $PYTHON manage.py check --deploy --fail-level WARNING
& $PYTHON manage.py makemigrations --check --dry-run
git diff --check origin/main...HEAD
```

Expected: todos exit `0`, nenhuma migration nova.

- [ ] **Step 4: Documentar configuração e operação exatas**

O runbook deve incluir:

- sete variáveis R2 sem valores secretos;
- permissões mínimas do token;
- comando manual `python manage.py backup_to_r2`;
- formato da chave e metadados;
- interpretação de `created`, `already_exists`, `lock_busy`, `remote_invalid`, `upload_failed`, `retention_failed`;
- retenção `14/8/12` e proteção de desconhecidos/último;
- validação por download em cópia descartável;
- rollback para imagem anterior sem apagar objetos R2;
- proibição explícita de apontar restore para `/app/data/db.sqlite3` durante ensaio;
- estado honesto: automação codificada, ainda não ativada em produção.

- [ ] **Step 5: Atualizar roadmap e relatório de task**

Marcar código/testes como concluídos, mas manter ativação e prova real abertas. O relatório registra comandos, contagens, cobertura, SHA do branch, limitações e routing usado. Tokens reais: `não disponíveis`.

- [ ] **Step 6: Revisão final do diff e nova matriz fresca**

Repetir Steps 1–3 depois de qualquer correção. Conferir que `rg -n "R2_BACKUP_SECRET_ACCESS_KEY=|R2_BACKUP_ACCESS_KEY_ID=" .` não encontra valores atribuídos em arquivos versionados.

- [ ] **Step 7: Commit e push da Task 6**

```powershell
git add README.md CLAUDE.md PRD.md docs
git commit -m "docs: add automatic backup runbook"
git push
git status --short --branch
git rev-list --left-right --count HEAD...origin/codex/task-automatic-r2-backup
```

Expected: worktree limpa e sincronismo `0 0`.

Parar. Apresentar resultados e pedir autorização separada para revisão/merge. Não executar Task 7 antes de a implementação estar revisada e integrada em `main`.

---

### Task 7: Ativação no EasyPanel e restauração real

**Routing:** `gpt-5.6-sol` / `xhigh`. Consumo esperado: alto.

**Prerequisites:** implementação revisada, CI verde, merge em `main`, `origin/main` sincronizada e autorização explícita para produção.

**Files:**
- Create: `docs/audits/automatic-r2-backup-production.md`
- Modify: `README.md`
- Modify: `PRD.md`
- Modify: `docs/ROADMAP.md`
- Modify: `docs/deploy-easypanel.md`

**External state:** Cloudflare R2 e EasyPanel `financeiro/finanpy`.

- [ ] **Step 1: Preflight somente leitura**

Confirmar versão EasyPanel, branch/imagem a implantar, uma réplica, mount `/app/data`, `SQLITE_PATH=/app/data/db.sqlite3`, integridade atual, espaço livre, bucket privado e existência do backup restaurável anterior. Não registrar PII ou credenciais.

- [ ] **Step 2: Criar token dedicado de menor privilégio**

No Cloudflare, criar token S3 restrito ao bucket `lar-finance-backups` com Object Read & Write. Inserir access key e secret diretamente nas variáveis secretas do EasyPanel; não copiar para terminal local, arquivo, relatório ou chat.

- [ ] **Step 3: Configurar variáveis não secretas**

```text
R2_BACKUP_ENDPOINT_URL=https://<account-id>.r2.cloudflarestorage.com
R2_BACKUP_BUCKET=lar-finance-backups
R2_BACKUP_PREFIX=production
R2_BACKUP_TIME=03:00
R2_BACKUP_TIME_ZONE=America/Sao_Paulo
```

`<account-id>` é preenchido diretamente no EasyPanel e não é registrado no relatório.

- [ ] **Step 4: Deploy controlado**

Implantar `main` após confirmar backup externo anterior. Executar migrations explicitamente conforme runbook, iniciar imagem e confirmar simultaneamente Gunicorn e scheduler. Interromper e fazer rollback se health, logs, mount, worker count ou config falharem.

- [ ] **Step 5: Provar execução automática e idempotência**

Como o deploy ocorrerá depois das `03:00`, o scheduler deve tentar imediatamente o dia corrente. Confirmar no log `created` ou `already_exists`. Reiniciar apenas o serviço uma vez; a nova inicialização deve retornar `already_exists`, sem criar segunda chave e sem interromper o web.

- [ ] **Step 6: Provar objeto e restauração off-host**

Confirmar no R2 uma única chave do dia, classe Standard, tamanho e metadado SHA-256. Baixar com credencial temporária somente leitura para diretório descartável fora do repositório. Comparar bytes/hash, executar `PRAGMA integrity_check`, `manage.py check --deploy`, migrations em cópia e `audit_household_integrity`. Nunca apontar a cópia para o banco real.

- [ ] **Step 7: Limpeza segura**

Revogar credencial temporária de download, excluir cópia local/servidor descartável e preservar objeto R2. O token operacional permanece apenas no EasyPanel. Confirmar aplicação online e banco real inalterado.

- [ ] **Step 8: Registrar evidência sanitizada**

O relatório contém horário, versão/imagem, key lógica, tamanho, SHA-256, integridade, quantidade de migrations/checks, restart/idempotência, estado da agenda e rollback disponível. Não contém account id, chaves, email, valores, descrições ou conteúdo do banco.

- [ ] **Step 9: Gates finais, commit e push**

```powershell
& $PYTHON manage.py test
& $PYTHON -m ruff check . --config pyproject.toml
git diff --check
git add README.md PRD.md docs/ROADMAP.md docs/deploy-easypanel.md docs/audits/automatic-r2-backup-production.md
git commit -m "docs: verify automatic R2 backups"
git push
```

Parar e apresentar estado final. Alertas externos permanecem como próxima task possível, sem início automático.
