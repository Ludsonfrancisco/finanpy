# R1.4 Fail-Fast Deploy and Observable Version Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publicar e executar no EasyPanel uma imagem GHCR imutável que identifica seu SHA e só inicia Web e schedulers depois de preflight, backup R2 quando necessário, migrations, auditoria e collectstatic bem-sucedidos.

**Architecture:** A identidade da release fica em uma função pura compartilhada pelo health e pelo startup gate. Um serviço Django testável classifica o SQLite, executa um backup R2 exclusivo somente diante de migrations pendentes e então roda as etapas fail-fast; um command fino é chamado por um script POSIX antes do Supervisor. A CI continua com os seis gates atuais e publica no GHCR somente tags `v*` aprovadas.

**Tech Stack:** Python 3.12, Django 5.2.13, SQLite, boto3/R2 S3 API, Supervisor 4.3.0, Docker, GitHub Actions, Django TestCase/unittest.mock, Flutter 3.47.0 para regressão da release.

## Global Constraints

- Produção significa `DEBUG=False`; nesse modo `APP_VERSION` deve ser exatamente um SHA Git hexadecimal minúsculo de 40 caracteres.
- `DEBUG=True` permite somente `development` ou um SHA válido.
- Em produção, o SQLite resolvido deve ficar dentro de `/app/data`; a configuração suportada permanece `SQLITE_PATH=/app/data/db.sqlite3`.
- Banco novo e banco existente sem migrations pendentes não criam backup pré-deploy.
- Banco existente com migrations pendentes só migra depois de backup R2 exclusivo, consistente e verificado.
- Qualquer falha de preflight, integridade, backup, migration, auditoria ou collectstatic impede o Supervisor de iniciar.
- Não restaurar automaticamente, não editar `django_migrations` manualmente e não executar downgrade sem ensaio próprio.
- Manter uma réplica, um Gunicorn worker, SQLite, backup scheduler e import-preview-purge scheduler.
- Não adicionar PostgreSQL, fila, Kubernetes, autoscaling, alertas externos ou framework interno.
- Logs de deploy contêm somente versão, etapa, código estável, duração e resultado; nunca valores financeiros, dados pessoais, paths sensíveis ou credenciais.
- Publicar GHCR somente em tag `v*`, com tags imutáveis `vX.Y.Z` e `sha-<SHA completo>`; nunca reatribuir uma tag publicada.
- Cada task termina com verificação, commit, push, aviso objetivo e pausa; não iniciar a task seguinte sem autorização explícita do proprietário.
- Não iniciar nenhuma task R2 durante este plano.
- Modelo recomendado para as Tasks 1–6: GPT-5.6 Sol, intensidade high. Task 7 é operacional e usa o mesmo modelo/intensidade para reduzir erro humano.

---

## File Structure

### Novos arquivos

- `core/release.py`: leitura e validação da identidade pública da release.
- `core/deploy.py`: classificação do SQLite e orquestração fail-fast.
- `core/management/commands/prepare_deploy.py`: adaptação do serviço para management command.
- `core/tests_release.py`: contrato da versão em desenvolvimento e produção.
- `core/tests_deploy_backup.py`: chave exclusiva e gateway R2 de deploy.
- `core/tests_deploy.py`: preflight, ordem, falhas e privacidade do startup gate.
- `deploy/start.sh`: entrypoint POSIX fail-fast antes do Supervisor.
- `docs/audits/2026-08-21-fail-fast-deploy-rehearsal.md`: evidência local/container e, depois, evidência sanitizada do EasyPanel.

### Arquivos modificados

- `core/backup_catalog.py`: construir e validar a chave R2 exclusiva de deploy.
- `core/r2_storage.py`: upload condicional e verificação de objeto pré-deploy sem incluí-lo na retenção diária.
- `core/remote_backup.py`: criar cópia SQLite consistente usando lock/staging existentes.
- `core/settings.py`: logger sanitizado `lar_finance.deploy`.
- `core/wsgi.py`: remover migration e captura ampla do startup Web.
- `api/views.py`: incluir `version` no health.
- `api/tests/test_foundation.py`: contrato exato do health.
- `api/tests/test_openapi_contract.py`: contrato OpenAPI do campo `version`.
- `docs/openapi-v1.yaml`: schema público do health.
- `Dockerfile`: ARG/ENV/label de versão e entrypoint versionado.
- `households/tests/test_deployment.py`: contratos do Dockerfile, script, Supervisor, Compose e CI.
- `.github/workflows/ci.yml`: build com SHA, smoke de container e publicação GHCR condicionada aos seis jobs.
- `README.md`, `PRD.md`, `docs/ROADMAP.md`, `docs/architecture.md`, `docs/security-and-operations.md`, `docs/deploy-easypanel.md`: estado executável, release e rollback.

---

### Task 1: Identidade da release e health observável

**Files:**
- Create: `core/release.py`
- Create: `core/tests_release.py`
- Modify: `api/views.py`
- Modify: `api/tests/test_foundation.py`
- Modify: `api/tests/test_openapi_contract.py`
- Modify: `docs/openapi-v1.yaml`

**Interfaces:**
- Produces: `ReleaseVersionError(ValueError)`.
- Produces: `read_app_version(environ: Mapping[str, str] | None = None) -> str`.
- Produces: `validate_app_version(version: str, *, debug: bool) -> str`.
- Produces: `public_app_version(environ: Mapping[str, str] | None = None) -> str`.
- Health response: `{"status":"ok","api_version":"v1","version":"<version>"}`.

- [ ] **Step 1: Write failing release and health tests**

```python
# core/tests_release.py
from django.test import SimpleTestCase

from core.release import ReleaseVersionError, validate_app_version


class ReleaseVersionTest(SimpleTestCase):
    def test_production_accepts_only_full_lowercase_sha(self):
        sha = 'a' * 40
        self.assertEqual(validate_app_version(sha, debug=False), sha)
        for invalid in ('', 'development', 'unknown', 'A' * 40, 'a' * 39):
            with self.subTest(invalid=invalid):
                with self.assertRaises(ReleaseVersionError):
                    validate_app_version(invalid, debug=False)

    def test_development_allows_development_or_full_sha(self):
        self.assertEqual(
            validate_app_version('development', debug=True),
            'development',
        )
        self.assertEqual(validate_app_version('b' * 40, debug=True), 'b' * 40)
```

```python
# api/tests/test_foundation.py
@patch.dict(os.environ, {'APP_VERSION': 'c' * 40}, clear=False)
def test_health_exposes_only_stable_public_fields(self):
    response = self.client.get('/api/v1/health/')
    self.assertEqual(response.status_code, 200)
    self.assertEqual(
        response.json(),
        {'status': 'ok', 'api_version': 'v1', 'version': 'c' * 40},
    )
```

- [ ] **Step 2: Run the focused tests and confirm RED**

Run:

```powershell
python manage.py test core.tests_release api.tests.test_foundation api.tests.test_openapi_contract
```

Expected: FAIL because `core.release` does not exist and the OpenAPI health schema does not require `version`.

- [ ] **Step 3: Implement the release identity functions**

```python
# core/release.py
import os
import re
from typing import Mapping

SHA_PATTERN = re.compile(r'^[0-9a-f]{40}$')


class ReleaseVersionError(ValueError):
    pass


def read_app_version(environ: Mapping[str, str] | None = None) -> str:
    source = os.environ if environ is None else environ
    return source.get('APP_VERSION', 'development').strip()


def validate_app_version(version: str, *, debug: bool) -> str:
    if SHA_PATTERN.fullmatch(version):
        return version
    if debug and version == 'development':
        return version
    raise ReleaseVersionError('Application release version is invalid.')


def public_app_version(environ: Mapping[str, str] | None = None) -> str:
    return read_app_version(environ)
```

- [ ] **Step 4: Add version to the runtime and OpenAPI contracts**

```python
# api/views.py
from core.release import public_app_version


class HealthView(APIView):
    authentication_classes = []
    permission_classes = [AllowAny]

    def get(self, request):
        return Response(
            {
                'status': 'ok',
                'api_version': 'v1',
                'version': public_app_version(),
            }
        )
```

In `docs/openapi-v1.yaml`, make the health response require exactly `status`, `api_version`, and `version`; define `version` as a string matching `^(development|[0-9a-f]{40})$`. Add this assertion:

```python
def test_health_documents_observable_release_version(self):
    schema = self.contract['paths']['/health/']['get']['responses']['200'][
        'content'
    ]['application/json']['schema']
    self.assertEqual(schema['required'], ['status', 'api_version', 'version'])
    self.assertEqual(
        schema['properties']['version'],
        {
            'type': 'string',
            'pattern': r'^(development|[0-9a-f]{40})$',
        },
    )
```

- [ ] **Step 5: Run focused verification**

Run:

```powershell
python manage.py test core.tests_release api.tests.test_foundation api.tests.test_openapi_contract
python -m ruff check core/release.py core/tests_release.py api/views.py api/tests/test_foundation.py api/tests/test_openapi_contract.py --config pyproject.toml
python manage.py check
git diff --check
```

Expected: all commands exit 0.

- [ ] **Step 6: Commit, push, report, and stop**

```powershell
git add core/release.py core/tests_release.py api/views.py api/tests/test_foundation.py api/tests/test_openapi_contract.py docs/openapi-v1.yaml
git commit -m "feat: expose immutable release version"
git push origin HEAD
```

Report the commit SHA, focused test count and next task (`Task 2: backup pré-migration exclusivo`). Wait for explicit authorization.

---

### Task 2: Backup R2 exclusivo por tentativa de migration

**Files:**
- Create: `core/tests_deploy_backup.py`
- Modify: `core/backup_catalog.py`
- Modify: `core/r2_storage.py`
- Modify: `core/remote_backup.py`

**Interfaces:**
- Consumes: `R2BackupConfig`, `R2Storage`, `backup_sqlite`, `temporary_backup_path`, `_backup_lock`, `file_identity`.
- Produces: `build_deploy_object_key(prefix: str, version: str, now: datetime) -> str`.
- Produces: `parse_deploy_object_key(prefix: str, key: str) -> tuple[str, datetime, date] | None`.
- Produces: `DeployRemoteObject(key: str, backup_date: date, size: int, sha256: str)`.
- Produces: `R2Storage.upload_deploy_and_verify(path, key, backup_date, sha256) -> DeployRemoteObject`.
- Produces: `execute_deploy_backup(config, storage, database_path, now, version) -> BackupOutcome`.

- [ ] **Step 1: Write failing key and backup tests**

```python
# core/tests_deploy_backup.py
import sqlite3
from datetime import UTC, datetime, time
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import Mock
from zoneinfo import ZoneInfo

from django.test import SimpleTestCase

from core.backup_catalog import build_deploy_object_key
from core.backup_config import R2BackupConfig
from core.r2_storage import DeployRemoteObject
from core.remote_backup import execute_deploy_backup


def fixed_utc_now():
    return datetime(2026, 8, 21, 18, 30, 45, 123456, tzinfo=UTC)


def backup_config(*, prefix):
    return R2BackupConfig(
        endpoint_url='https://example.invalid',
        access_key_id='test-access',
        secret_access_key='test-secret',
        bucket='test-bucket',
        prefix=prefix,
        schedule_time=time(3, 0),
        time_zone=ZoneInfo('America/Sao_Paulo'),
    )


def create_valid_sqlite(path):
    with sqlite3.connect(path) as database:
        database.execute('CREATE TABLE sample (id INTEGER PRIMARY KEY)')


def deploy_remote_object():
    return DeployRemoteObject(
        key=build_deploy_object_key('production', 'b' * 40, fixed_utc_now()),
        backup_date=fixed_utc_now().date(),
        size=1,
        sha256='c' * 64,
    )


class DeployBackupTest(SimpleTestCase):
    def test_key_is_unique_per_sha_and_utc_microsecond(self):
        now = datetime(2026, 8, 21, 18, 30, 45, 123456, tzinfo=UTC)
        key = build_deploy_object_key('production', 'a' * 40, now)
        self.assertEqual(
            key,
            'production/deploy/' + 'a' * 40
            + '/20260821T183045123456Z/2026/08/21.sqlite3',
        )

    def test_verified_deploy_backup_does_not_run_daily_retention(self):
        with TemporaryDirectory() as directory:
            source = Path(directory, 'db.sqlite3')
            create_valid_sqlite(source)
            storage = Mock()
            storage.upload_deploy_and_verify.return_value = deploy_remote_object()

            outcome = execute_deploy_backup(
                config=backup_config(prefix='production'),
                storage=storage,
                database_path=source,
                now=fixed_utc_now(),
                version='b' * 40,
            )

            self.assertEqual(outcome.status, 'created')
            self.assertEqual(outcome.deleted_keys, ())
            storage.list_managed.assert_not_called()
            storage.delete.assert_not_called()
```

Use boto3 `Stubber` to add these exact methods in `DeployStorageTest`:

| Test method | Stubbed response | Exact assertion |
|---|---|---|
| `test_upload_uses_conditional_create_and_exact_metadata` | successful `put_object`, then matching `head_object` | request has `IfNoneMatch='*'`; metadata keys are exactly `sha256`, `size`, `backup-date`, `kind`; result equals `DeployRemoteObject` |
| `test_upload_rejects_preexisting_key` | `put_object` returns HTTP 412/`PreconditionFailed` | raises `RemoteObjectConflict`; no HEAD request |
| `test_upload_rejects_invalid_remote_metadata` | successful PUT, HEAD has a different SHA | raises `RemoteVerificationError` |
| `test_upload_does_not_hide_forbidden` | PUT returns HTTP 403 | original `ClientError` escapes |
| `test_upload_does_not_hide_server_error` | PUT returns HTTP 500 | original `ClientError` escapes |
| `test_daily_catalog_never_lists_deploy_prefix` | paginator returns one daily key and one deploy key | `list_managed()` returns only the daily object |

The successful request expectation is:

```python
expected_put = {
    'Bucket': 'test-bucket',
    'Key': build_deploy_object_key('production', 'a' * 40, fixed_utc_now()),
    'Body': ANY,
    'ContentType': 'application/vnd.sqlite3',
    'Metadata': {
        'sha256': expected_sha,
        'size': str(path.stat().st_size),
        'backup-date': '2026-08-21',
        'kind': 'deploy',
    },
    'IfNoneMatch': '*',
}
```

- [ ] **Step 2: Run tests and confirm RED**

Run:

```powershell
python manage.py test core.tests_deploy_backup
```

Expected: FAIL because the deploy key, object type and upload method do not exist.

- [ ] **Step 3: Add exact deploy key construction and parsing**

```python
# core/backup_catalog.py
def build_deploy_object_key(prefix: str, version: str, now: datetime) -> str:
    instant = now.astimezone(UTC)
    stamp = instant.strftime('%Y%m%dT%H%M%S%fZ')
    return (
        f'{prefix}/deploy/{version}/{stamp}/'
        f'{instant:%Y/%m/%d}.sqlite3'
    )
```

```python
def parse_deploy_object_key(
    prefix: str,
    key: str,
) -> tuple[str, datetime, date] | None:
    pattern = re.compile(
        rf'^{re.escape(prefix)}/deploy/'
        r'(?P<version>[0-9a-f]{40})/'
        r'(?P<stamp>\d{8}T\d{12}Z)/'
        r'(?P<year>\d{4})/(?P<month>\d{2})/(?P<day>\d{2})\.sqlite3$'
    )
    match = pattern.fullmatch(key)
    if match is None:
        return None
    try:
        instant = datetime.strptime(
            match['stamp'],
            '%Y%m%dT%H%M%S%fZ',
        ).replace(tzinfo=UTC)
        backup_date = date(
            int(match['year']),
            int(match['month']),
            int(match['day']),
        )
    except ValueError:
        return None
    if instant.date() != backup_date:
        return None
    return match['version'], instant, backup_date
```

- [ ] **Step 4: Add the dedicated verified R2 upload**

```python
# core/r2_storage.py
@dataclass(frozen=True)
class DeployRemoteObject:
    key: str
    backup_date: date
    size: int
    sha256: str


def upload_deploy_and_verify(self, path, key, backup_date, sha256):
    parsed = parse_deploy_object_key(self.prefix, key)
    if (
        parsed is None
        or parsed[2] != backup_date
        or SHA256_PATTERN.fullmatch(sha256) is None
    ):
        raise RemoteVerificationError('Deploy backup key is invalid.')
    backup_path = Path(path)
    size = backup_path.stat().st_size
    metadata = {
        'sha256': sha256,
        'size': str(size),
        'backup-date': backup_date.isoformat(),
        'kind': 'deploy',
    }
    try:
        with backup_path.open('rb') as body:
            self.client.put_object(
                Bucket=self.bucket,
                Key=key,
                Body=body,
                ContentType=SQLITE_CONTENT_TYPE,
                Metadata=metadata,
                IfNoneMatch='*',
            )
    except ClientError as error:
        status = error.response.get('ResponseMetadata', {}).get('HTTPStatusCode')
        code = error.response.get('Error', {}).get('Code')
        if status == 412 or code == 'PreconditionFailed':
            raise RemoteObjectConflict(
                'A deploy backup already exists for this key.'
            ) from None
        raise
    response = self.client.head_object(Bucket=self.bucket, Key=key)
    remote_metadata = response.get('Metadata', {})
    if (
        response.get('ContentLength') != size
        or remote_metadata != metadata
    ):
        raise RemoteVerificationError('Deploy backup verification failed.')
    return DeployRemoteObject(
        key=key,
        backup_date=backup_date,
        size=size,
        sha256=sha256,
    )
```

Keep this method outside `list_managed()` and daily retention. Translate 412 to `RemoteObjectConflict`; do not translate 403 or 5xx to not-found.

- [ ] **Step 5: Reuse the safe SQLite staging and lock**

```python
# core/remote_backup.py
def execute_deploy_backup(config, storage, database_path, now, version):
    source = Path(database_path).resolve()
    key = build_deploy_object_key(config.prefix, version, now)
    backup_date = now.astimezone(UTC).date()
    lock = FileLock(str(source.parent / '.lar-finance-r2-backup.lock'), timeout=0)

    with _backup_lock(lock):
        backup_directory = source.parent / 'backups'
        staging_directory = backup_directory / STAGING_DIRECTORY_NAME
        cleanup_stale_temporary_backups(backup_directory)
        cleanup_stale_temporary_backups(staging_directory)
        with temporary_backup_path(staging_directory) as temporary_path:
            try:
                backup_sqlite(source, temporary_path)
                _, sha256 = file_identity(temporary_path)
            except LOCAL_BACKUP_ERRORS:
                raise BackupVerificationError(
                    'Local SQLite backup could not be verified.',
                    error_code='copy_failed',
                    stage='copy',
                ) from None
            try:
                remote = storage.upload_deploy_and_verify(
                    temporary_path,
                    key,
                    backup_date,
                    sha256,
                )
            except REMOTE_OPERATION_ERRORS:
                raise BackupVerificationError(
                    'Deploy backup upload could not be verified.'
                ) from None
            return BackupOutcome.created(remote, ())
```

Preserve `KeyboardInterrupt` and `SystemExit`; do not catch them as operational failures.

- [ ] **Step 6: Run focused and regression verification**

Run:

```powershell
python manage.py test core.tests_deploy_backup core.tests_remote_backup core.tests_r2_storage core.tests_backup_catalog
python -m ruff check core/backup_catalog.py core/r2_storage.py core/remote_backup.py core/tests_deploy_backup.py --config pyproject.toml
python manage.py check
git diff --check
```

Expected: all focused and existing backup tests pass; no daily retention behavior changes.

- [ ] **Step 7: Commit, push, report, and stop**

```powershell
git add core/backup_catalog.py core/r2_storage.py core/remote_backup.py core/tests_deploy_backup.py
git commit -m "feat: add verified pre-deploy backup"
git push origin HEAD
```

Report SHA, tests and residual risk (R2 real is not touched). Wait for authorization.

---

### Task 3: Orquestrador e command fail-fast

**Files:**
- Create: `core/deploy.py`
- Create: `core/tests_deploy.py`
- Create: `core/management/commands/prepare_deploy.py`
- Modify: `core/settings.py`

**Interfaces:**
- Consumes: `validate_app_version`, `R2BackupConfig.from_env`, `R2Storage.from_config`, `execute_deploy_backup`.
- Produces: `DeployPreparationError(error_code: str, stage: str)`.
- Produces: `DatabaseState` enum values `NEW`, `READY`.
- Produces: `DeployOutcome(version: str, database_state: DatabaseState, migrations_applied: bool, backup_key: str | None)`.
- Produces: `sqlite_integrity_check(path: Path) -> None`.
- Produces: `classify_database(path: Path) -> DatabaseState`.
- Produces: `has_pending_migrations() -> bool`.
- Produces: `prepare_deploy(environ: Mapping[str, str] | None = None, now: datetime | None = None) -> DeployOutcome`.

- [ ] **Step 1: Write failing preflight and ordering tests**

```python
# core/tests_deploy.py
from datetime import UTC, datetime
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

from django.test import SimpleTestCase, override_settings

from core.deploy import DatabaseState, prepare_deploy


@override_settings(DEBUG=True)
@patch('core.deploy.validated_database_path', return_value=Path('test.sqlite3'))
@patch('core.deploy.classify_database', return_value=DatabaseState.READY)
@patch('core.deploy.has_pending_migrations', return_value=True)
@patch('core.deploy.R2BackupConfig.from_env', return_value=Mock())
@patch('core.deploy.R2Storage.from_config', return_value=Mock())
@patch('core.deploy.call_command')
@patch('core.deploy.execute_deploy_backup')
def test_existing_database_backs_up_before_migrate(
    self,
    backup,
    command,
    storage,
    config,
    pending,
    classify,
    database_path,
):
    events = []
    backup.side_effect = (
        lambda *args, **kwargs: events.append('backup')
        or SimpleNamespace(key='production/deploy/verified.sqlite3')
    )
    command.side_effect = lambda name, **kwargs: events.append(name)

    result = prepare_deploy(
        environ={'APP_VERSION': 'a' * 40},
        now=datetime(2026, 8, 21, 18, 30, tzinfo=UTC),
    )

    self.assertEqual(
        events,
        ['backup', 'migrate', 'audit_household_integrity', 'collectstatic'],
    )
    self.assertTrue(result.migrations_applied)
```

Use these exact additional test cases in the same module:

| Test method | Setup | Exact assertion |
|---|---|---|
| `test_new_database_migrates_without_backup` | `DatabaseState.NEW`, pending `True` | commands are migrate/audit/collectstatic; backup mock has zero calls |
| `test_ready_database_without_pending_migration_skips_backup_and_migrate` | `DatabaseState.READY`, pending `False` | commands are audit/collectstatic; backup has zero calls |
| `test_corrupt_sqlite_fails_before_migration_detection` | write `b'not sqlite'` to temp path | code `sqlite_integrity_failed`; detector/backup/command have zero calls |
| `test_production_rejects_path_outside_data_volume` | `DEBUG=False`, patch root to temporary `/app/data` equivalent | code `database_path_invalid`; no parent is created |
| `test_backup_failure_prevents_migrate` | backup raises `BackupVerificationError` | code `backup_failed`; command has zero calls |
| `test_migration_failure_prevents_later_stages` | migrate raises `CommandError` | only migrate called; code `migration_failed` |
| `test_audit_failure_prevents_collectstatic` | audit raises `CommandError` | migrate then audit; code `audit_failed` |
| `test_collectstatic_failure_is_terminal` | collectstatic raises `CommandError` | all prior stages called; code `collectstatic_failed` |
| `test_keyboard_interrupt_is_not_translated` | command raises `KeyboardInterrupt` | same `KeyboardInterrupt` escapes |
| `test_system_exit_is_not_translated` | command raises `SystemExit(2)` | same exit code `2` escapes |

- [ ] **Step 2: Run tests and confirm RED**

Run:

```powershell
python manage.py test core.tests_deploy
```

Expected: FAIL because `core.deploy` and `prepare_deploy` do not exist.

- [ ] **Step 3: Implement release/path and raw SQLite preflight**

```python
# core/deploy.py
class DeployPreparationError(RuntimeError):
    def __init__(self, *, error_code: str, stage: str):
        super().__init__(f'Deploy preparation failed [{error_code}].')
        self.error_code = error_code
        self.stage = stage


def sqlite_integrity_check(path: Path) -> None:
    try:
        with sqlite3.connect(f'file:{path}?mode=ro', uri=True) as database:
            rows = database.execute('PRAGMA integrity_check').fetchall()
    except sqlite3.Error:
        raise DeployPreparationError(
            error_code='sqlite_integrity_failed',
            stage='integrity',
        ) from None
    if rows != [('ok',)]:
        raise DeployPreparationError(
            error_code='sqlite_integrity_failed',
            stage='integrity',
        )
```

```python
class DatabaseState(StrEnum):
    NEW = 'new'
    READY = 'ready'


@dataclass(frozen=True)
class DeployOutcome:
    version: str
    database_state: DatabaseState
    migrations_applied: bool
    backup_key: str | None


PRODUCTION_DATA_ROOT = Path('/app/data')


def validated_database_path(value, *, debug: bool) -> Path:
    path = Path(value)
    if not debug:
        if not path.is_absolute():
            raise DeployPreparationError(
                error_code='database_path_invalid',
                stage='configuration',
            )
        root = PRODUCTION_DATA_ROOT.resolve(strict=False)
        resolved = path.resolve(strict=False)
        try:
            resolved.relative_to(root)
        except ValueError:
            raise DeployPreparationError(
                error_code='database_path_invalid',
                stage='configuration',
            ) from None
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
    except OSError:
        raise DeployPreparationError(
            error_code='database_path_invalid',
            stage='configuration',
        ) from None
    return path


def classify_database(path: Path) -> DatabaseState:
    try:
        path_stat = path.lstat()
    except FileNotFoundError:
        return DatabaseState.NEW
    if stat.S_ISLNK(path_stat.st_mode) or not stat.S_ISREG(path_stat.st_mode):
        raise DeployPreparationError(
            error_code='database_path_invalid',
            stage='configuration',
        )
    sqlite_integrity_check(path)
    try:
        with sqlite3.connect(f'file:{path}?mode=ro', uri=True) as database:
            tables = {
                row[0]
                for row in database.execute(
                    "SELECT name FROM sqlite_master "
                    "WHERE type='table' AND name NOT LIKE 'sqlite_%'"
                )
            }
    except sqlite3.Error:
        raise DeployPreparationError(
            error_code='sqlite_integrity_failed',
            stage='integrity',
        ) from None
    if not tables:
        return DatabaseState.NEW
    if 'django_migrations' not in tables:
        raise DeployPreparationError(
            error_code='database_unrecognized',
            stage='preflight',
        )
    return DatabaseState.READY
```

- [ ] **Step 4: Implement migration detection and ordered orchestration**

```python
def has_pending_migrations() -> bool:
    executor = MigrationExecutor(connection)
    targets = executor.loader.graph.leaf_nodes()
    return bool(executor.migration_plan(targets))


def prepare_deploy(environ=None, now=None) -> DeployOutcome:
    source = os.environ if environ is None else environ
    instant = datetime.now(UTC) if now is None else now.astimezone(UTC)
    try:
        version = validate_app_version(
            read_app_version(source),
            debug=settings.DEBUG,
        )
    except ReleaseVersionError:
        raise DeployPreparationError(
            error_code='version_invalid',
            stage='configuration',
        ) from None
    database_path = validated_database_path(
        settings.DATABASES['default']['NAME'],
        debug=settings.DEBUG,
    )
    state = classify_database(database_path)
    pending = has_pending_migrations()
    backup_key = None

    if state is DatabaseState.READY and pending:
        backup_key = run_deploy_backup(
            source,
            database_path,
            instant,
            version,
        )
    if pending:
        run_command('migrate', stage='migration', interactive=False)
    run_command('audit_household_integrity', stage='audit')
    run_command('collectstatic', stage='collectstatic', interactive=False)
    return DeployOutcome(version, state, pending, backup_key)
```

```python
def run_deploy_backup(source, database_path, instant, version) -> str:
    try:
        config = R2BackupConfig.from_env(source)
        storage = R2Storage.from_config(config)
        outcome = execute_deploy_backup(
            config,
            storage,
            database_path,
            instant,
            version,
        )
    except BackupConfigurationError:
        raise DeployPreparationError(
            error_code='configuration_invalid',
            stage='backup',
        ) from None
    except BackupAlreadyRunning:
        raise DeployPreparationError(
            error_code='lock_busy',
            stage='backup',
        ) from None
    except (BackupVerificationError, BackupRetentionError, R2StorageError, OSError):
        raise DeployPreparationError(
            error_code='backup_failed',
            stage='backup',
        ) from None
    return outcome.key
```

```python
def run_command(name: str, *, stage: str, **options) -> None:
    try:
        call_command(name, **options)
    except Exception:
        raise DeployPreparationError(
            error_code=f'{stage}_failed',
            stage=stage,
        ) from None
```

Because it catches `Exception`, `KeyboardInterrupt` and `SystemExit` remain untouched. Translate `ReleaseVersionError`, `BackupConfigurationError`, `BackupAlreadyRunning`, `BackupVerificationError`, `BackupRetentionError`, `R2StorageError`, `OSError` and `sqlite3.Error` at their exact stages before they reach the command; never include their original message in the serialized event.

- [ ] **Step 5: Implement safe events and the management command**

```python
# core/management/commands/prepare_deploy.py
ALLOWED_DEPLOY_EVENT_KEYS = {
    'timestamp',
    'event',
    'version',
    'stage',
    'status',
    'error_code',
    'duration_ms',
}


def serialize_deploy_event(**fields) -> str:
    event = {key: fields.get(key) for key in ALLOWED_DEPLOY_EVENT_KEYS}
    event['timestamp'] = datetime.now(UTC).isoformat()
    return json.dumps(event, separators=(',', ':'), sort_keys=True)


def duration_ms(started: float) -> int:
    return max(0, round((time.monotonic() - started) * 1000))


class Command(BaseCommand):
    help = 'Prepare the SQLite release and fail before Supervisor on error.'

    def handle(self, *args, **options):
        started = time.monotonic()
        try:
            outcome = prepare_deploy()
        except DeployPreparationError as error:
            logger.error(
                serialize_deploy_event(
                    event='deploy_prepare_failed',
                    version='invalid',
                    stage=error.stage,
                    error_code=error.error_code,
                    duration_ms=duration_ms(started),
                    status='error',
                )
            )
            raise CommandError(
                f'Deploy preparation failed [{error.error_code}].'
            ) from None
        logger.info(
            serialize_deploy_event(
                event='deploy_prepare_finished',
                version=outcome.version,
                stage='complete',
                error_code=None,
                duration_ms=duration_ms(started),
                status='ok',
            )
        )
```

Add this logger to `core/settings.py`:

```python
'lar_finance.deploy': {
    'handlers': ['api_stdout'],
    'level': 'INFO',
    'propagate': False,
},
```

Test the exact event keys and privacy boundary:

```python
payload = serialize_deploy_event(
    event='deploy_prepare_failed',
    version='invalid',
    stage='backup',
    status='error',
    error_code='backup_failed',
    duration_ms=12,
)
self.assertEqual(set(json.loads(payload)), ALLOWED_DEPLOY_EVENT_KEYS)
for forbidden in (
    'secret-access-value',
    'user@example.com',
    '/app/data/db.sqlite3',
    'R$ 1.234,56',
    'Mercado do bairro',
):
    self.assertNotIn(forbidden, payload)
```

- [ ] **Step 6: Add command-level failure assertions**

```python
@patch(
    'core.management.commands.prepare_deploy.prepare_deploy',
    side_effect=DeployPreparationError(
        error_code='configuration_invalid',
        stage='backup',
    ),
)
def test_command_returns_safe_nonzero_error(self, prepare):
    stderr = StringIO()
    with self.assertLogs('lar_finance.deploy', level='ERROR') as captured:
        with self.assertRaisesRegex(
            CommandError,
            r'^Deploy preparation failed \[configuration_invalid\]\.$',
        ):
            call_command('prepare_deploy', stderr=stderr)
    event = json.loads(captured.output[0].split(':', 2)[-1])
    self.assertEqual(event['error_code'], 'configuration_invalid')
    self.assertEqual(set(event), ALLOWED_DEPLOY_EVENT_KEYS)
```

- [ ] **Step 7: Run focused Django gates**

Run:

```powershell
python manage.py test core.tests_deploy core.tests_deploy_backup
python -m ruff check core/deploy.py core/tests_deploy.py core/management/commands/prepare_deploy.py core/settings.py --config pyproject.toml
python manage.py check
python manage.py makemigrations --check --dry-run
git diff --check
```

Expected: all commands exit 0 and no new migration is generated.

- [ ] **Step 8: Commit, push, report, and stop**

```powershell
git add core/deploy.py core/tests_deploy.py core/management/commands/prepare_deploy.py core/settings.py
git commit -m "feat: add fail-fast deploy preparation"
git push origin HEAD
```

Report SHA, task tests, command ordering and the next task. Wait for authorization.

---

### Task 4: Entry point fail-fast e WSGI limpo

**Files:**
- Create: `deploy/start.sh`
- Modify: `core/wsgi.py`
- Modify: `Dockerfile`
- Modify: `households/tests/test_deployment.py`

**Interfaces:**
- Consumes: management command `python manage.py prepare_deploy`.
- Produces: container command `/app/deploy/start.sh`.
- Preserves: Supervisor programs `web`, `backup-scheduler`, `import-preview-purge`, with one Gunicorn worker.

- [ ] **Step 1: Rewrite deployment tests first**

```python
def test_wsgI_never_runs_migrations(self):
    source = Path(BASE_DIR, 'core', 'wsgi.py').read_text(encoding='utf-8')
    self.assertNotIn('call_command', source)
    self.assertNotIn("'migrate'", source)
    self.assertNotIn('gunicorn', source.lower())


def test_start_script_is_fail_fast_before_supervisor(self):
    source = Path(BASE_DIR, 'deploy', 'start.sh').read_text(encoding='utf-8')
    self.assertEqual(
        [line for line in source.splitlines() if line and not line.startswith('#')],
        [
            'set -eu',
            'python manage.py prepare_deploy',
            'exec supervisord -c /app/deploy/supervisord.conf',
        ],
    )
```

Change the Dockerfile assertion to require `CMD ["/app/deploy/start.sh"]`, `ARG APP_VERSION=development`, `ENV APP_VERSION=${APP_VERSION}`, the OCI revision label and executable permission.

- [ ] **Step 2: Run tests and confirm RED**

Run:

```powershell
python manage.py test households.tests.test_deployment
```

Expected: FAIL because WSGI migrates and the Dockerfile starts Supervisor directly.

- [ ] **Step 3: Make WSGI application-only**

```python
# core/wsgi.py
import os

from django.core.wsgi import get_wsgi_application

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'core.settings')

application = get_wsgi_application()
```

- [ ] **Step 4: Add the POSIX startup gate and image identity**

```sh
#!/bin/sh
set -eu
python manage.py prepare_deploy
exec supervisord -c /app/deploy/supervisord.conf
```

```dockerfile
ARG APP_VERSION=development
ENV APP_VERSION=${APP_VERSION}
LABEL org.opencontainers.image.revision=${APP_VERSION}
RUN chmod 0755 /app/deploy/start.sh
CMD ["/app/deploy/start.sh"]
```

Place the Dockerfile lines in the runtime stage after `COPY . .`. Do not change `deploy/supervisord.conf` or `docker-compose.yml`.

- [ ] **Step 5: Verify runtime contracts**

Run:

```powershell
python manage.py test households.tests.test_deployment core.tests_deploy api.tests.test_foundation
python -m ruff check core/wsgi.py households/tests/test_deployment.py --config pyproject.toml
python manage.py check
git diff --check
```

When Docker is available, also run:

```powershell
docker build --build-arg APP_VERSION=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --tag lar-finance-r1-4 .
docker inspect lar-finance-r1-4 --format '{{json .Config.Cmd}} {{index .Config.Labels "org.opencontainers.image.revision"}}'
```

Expected: command is `[/app/deploy/start.sh]` and the label is 40 `a` characters.

- [ ] **Step 6: Commit, push, report, and stop**

```powershell
git add deploy/start.sh core/wsgi.py Dockerfile households/tests/test_deployment.py
git commit -m "fix: gate container startup before supervisor"
git push origin HEAD
```

Report SHA and proof that WSGI cannot swallow a migration failure. Wait for authorization.

---

### Task 5: CI completa, smoke de imagem e publicação GHCR

**Files:**
- Modify: `.github/workflows/ci.yml`
- Modify: `households/tests/test_deployment.py`

**Interfaces:**
- Consumes: six existing jobs `django`, `secrets`, `flutter_checks`, `flutter_windows`, `flutter_android`, `flutter_ios`.
- Produces: job `publish_image` with exact `needs` list and tag-only condition.
- Produces: images `ghcr.io/<owner-lowercase>/finanpy:<v-tag>` and `ghcr.io/<owner-lowercase>/finanpy:sha-<full-sha>`.

- [ ] **Step 1: Add failing structural CI tests**

```python
def test_publish_job_requires_all_six_quality_jobs_and_release_tag(self):
    publish = self._workflow_job('publish_image')
    self.assertEqual(
        set(publish['needs']),
        {
            'django',
            'secrets',
            'flutter_checks',
            'flutter_windows',
            'flutter_android',
            'flutter_ios',
        },
    )
    self.assertEqual(
        publish['if'],
        "startsWith(github.ref, 'refs/tags/v')",
    )
    self.assertEqual(publish['permissions']['packages'], 'write')
```

Add this source-level security assertion after parsing the job structure:

```python
source = Path(BASE_DIR, '.github', 'workflows', 'ci.yml').read_text(
    encoding='utf-8'
)
self.assertIn('--build-arg APP_VERSION="${GITHUB_SHA}"', source)
self.assertIn(':sha-${GITHUB_SHA}', source)
self.assertIn(':${GITHUB_REF_NAME}', source)
self.assertIn('password: ${{ secrets.GITHUB_TOKEN }}', source)
self.assertNotRegex(source, r'ghp_[A-Za-z0-9]{20,}')
self.assertNotRegex(source, r'github_pat_[A-Za-z0-9_]{20,}')
```

- [ ] **Step 2: Run deployment tests and confirm RED**

Run:

```powershell
python manage.py test households.tests.test_deployment
```

Expected: FAIL because `publish_image` is absent.

- [ ] **Step 3: Build the Django candidate with its SHA and smoke startup**

Change `Build production image` to:

```yaml
- name: Build production image
  run: >-
    docker build
    --build-arg APP_VERSION=${{ github.sha }}
    --tag lar-finance-ci:${{ github.sha }} .
```

```yaml
- name: Smoke immutable startup and process topology
  env:
    SECRET_KEY: ephemeral-ci-only-secret-value # gitleaks:allow
  run: |
    set -euo pipefail
    docker volume create lar-finance-ci-data
    cleanup() {
      docker rm -f lar-finance-ci-smoke >/dev/null 2>&1 || true
      docker volume rm lar-finance-ci-data >/dev/null 2>&1 || true
    }
    trap cleanup EXIT
    docker run --detach --name lar-finance-ci-smoke \
      --publish 127.0.0.1:18000:8000 \
      --volume lar-finance-ci-data:/app/data \
      --env DEBUG=False \
      --env SECRET_KEY \
      --env ALLOWED_HOSTS=127.0.0.1,localhost \
      --env SECURE_SSL_REDIRECT=False \
      --env SQLITE_PATH=/app/data/db.sqlite3 \
      --env R2_BACKUP_ENDPOINT_URL=https://example.invalid \
      --env R2_BACKUP_ACCESS_KEY_ID=ci-access \
      --env R2_BACKUP_SECRET_ACCESS_KEY=ci-secret \
      --env R2_BACKUP_BUCKET=ci-bucket \
      lar-finance-ci:${{ github.sha }}
    for attempt in $(seq 1 60); do
      if curl --fail --silent http://127.0.0.1:18000/api/v1/health/ \
        > health.json; then
        break
      fi
      sleep 1
    done
    python - <<'PY'
    import json
    import os
    from pathlib import Path

    health = json.loads(Path('health.json').read_text(encoding='utf-8'))
    assert health == {
        'status': 'ok',
        'api_version': 'v1',
        'version': os.environ['GITHUB_SHA'],
    }
    PY
    docker top lar-finance-ci-smoke -eo args > processes.txt
    grep -F 'gunicorn core.wsgi:application' processes.txt
    grep -F 'python manage.py run_backup_scheduler' processes.txt
    grep -F 'python manage.py run_import_preview_purge_scheduler' processes.txt
```

The invalid example endpoint keeps the scheduler isolated from a real bucket. Because the database is new, `prepare_deploy` must not contact R2; the scheduler may enter its documented retry path after Supervisor starts.

- [ ] **Step 4: Add tag-only GHCR publication after all gates**

```yaml
publish_image:
  name: Publish immutable GHCR image
  needs:
    - django
    - secrets
    - flutter_checks
    - flutter_windows
    - flutter_android
    - flutter_ios
  if: startsWith(github.ref, 'refs/tags/v')
  runs-on: ubuntu-latest
  permissions:
    contents: read
    packages: write
  steps:
    - uses: actions/checkout@v6
    - name: Resolve lowercase image name
      id: image
      shell: bash
      run: echo "name=ghcr.io/${GITHUB_REPOSITORY,,}" >> "$GITHUB_OUTPUT"
    - name: Authenticate to GHCR
      uses: docker/login-action@v3
      with:
        registry: ghcr.io
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}
    - name: Build immutable release image
      run: |
        docker build \
          --build-arg APP_VERSION="${GITHUB_SHA}" \
          --tag "${{ steps.image.outputs.name }}:${GITHUB_REF_NAME}" \
          --tag "${{ steps.image.outputs.name }}:sha-${GITHUB_SHA}" .
    - name: Push immutable release tags
      run: |
        docker push "${{ steps.image.outputs.name }}:${GITHUB_REF_NAME}"
        docker push "${{ steps.image.outputs.name }}:sha-${GITHUB_SHA}"
```

- [ ] **Step 5: Validate workflow syntax and contracts**

Run:

```powershell
python manage.py test households.tests.test_deployment
python -m ruff check households/tests/test_deployment.py --config pyproject.toml
python manage.py check
git diff --check
```

Also parse `.github/workflows/ci.yml` with the repository's existing YAML test helpers and run Gitleaks locally if available. Expected: all exit 0 and no secret assignment is committed.

- [ ] **Step 6: Commit, push, observe branch CI, and stop**

```powershell
git add .github/workflows/ci.yml households/tests/test_deployment.py
git commit -m "ci: publish immutable release images"
git push origin HEAD
```

Wait for the branch CI run to finish. Require all six existing jobs green; `publish_image` must be skipped on the branch. Report run URL, SHA and next task, then wait for authorization.

---

### Task 6: Matriz final, runbook e ensaio isolado

**Files:**
- Create: `docs/audits/2026-08-21-fail-fast-deploy-rehearsal.md`
- Modify: `README.md`
- Modify: `PRD.md`
- Modify: `docs/ROADMAP.md`
- Modify: `docs/architecture.md`
- Modify: `docs/security-and-operations.md`
- Modify: `docs/deploy-easypanel.md`

**Interfaces:**
- Consumes: `prepare_deploy`, `/api/v1/health/`, GHCR tag contract and manual rollback procedure.
- Produces: one operational source of truth that distinguishes local proof, GHCR proof and EasyPanel proof.

- [ ] **Step 1: Run the complete local quality matrix from a clean tree**

Run:

```powershell
$env:SECRET_KEY = python -c "import secrets; print(secrets.token_urlsafe(64))"
$env:DEBUG = 'False'
$env:APP_VERSION = 'a' * 40
$env:ALLOWED_HOSTS = 'localhost,127.0.0.1'
$env:SECURE_HSTS_SECONDS = '3600'
$env:SECURE_HSTS_INCLUDE_SUBDOMAINS = 'True'
$env:SECURE_HSTS_PRELOAD = 'True'
$env:SECURE_SSL_REDIRECT = 'True'
python -m ruff check . --config pyproject.toml
python manage.py check
python manage.py check --deploy --fail-level WARNING
python manage.py makemigrations --check --dry-run
$env:SECURE_SSL_REDIRECT = 'False'
python -Wd manage.py test
coverage erase
coverage run manage.py test
coverage report --fail-under=90
Set-Location mobile
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build windows --release --dart-define=LAR_FINANCE_API_BASE_URL=https://financeiro.palmbook.online/api/v1
flutter build apk --release --dart-define=LAR_FINANCE_API_BASE_URL=https://financeiro.palmbook.online/api/v1
Set-Location ..
git diff --check
```

Expected: all exit 0, no `DeprecationWarning`, coverage at least 90%, Windows release and APK release produced.

- [ ] **Step 2: Rehearse the safe-failure path only on a copied SQLite**

Create a temporary directory, copy a migration-old test SQLite into it, record its SHA-256 and `django_migrations`, and run the candidate image with that directory mounted at `/app/data` plus intentionally absent R2 credentials. Assert:

```text
container_exit != 0
health_unreachable = true
sqlite_sha256_after == sqlite_sha256_before
django_migrations_after == django_migrations_before
deploy_error_code == configuration_invalid
```

Never point this command at the EasyPanel production volume.

- [ ] **Step 3: Rehearse rollback using an isolated restored object**

Use the existing documented R2 download/verification path to restore a selected object into a disposable directory. Verify remote size/SHA, local SHA and `PRAGMA integrity_check`; start the prior image tag against only that disposable copy, verify health and audit, then destroy the disposable directory. Do not delete or overwrite any R2 object.

- [ ] **Step 4: Update documentation with observed evidence**

Document:

```markdown
- release source: GHCR `sha-<40-char-sha>`;
- startup order: preflight → optional backup → migrate → audit → collectstatic → Supervisor;
- one replica, one Gunicorn worker and two schedulers;
- health exact fields: status, api_version, version;
- rollback: stop processes, preserve failed DB, verify/restore copy, select prior SHA;
- local/container evidence completed with command outputs and hashes sanitized;
- GHCR tag and EasyPanel deployment remain open until Task 7.
```

Mark R1.4 as in progress, not complete. Remove the obsolete instruction that runs migration manually before Supervisor and replace it with the image entrypoint behavior.

- [ ] **Step 5: Review docs and secret/privacy boundaries**

Run:

```powershell
rg -n "TB[D]|TO[D]O|FIXM[E]|\[INVESTIGA[R]\]" docs/audits/2026-08-21-fail-fast-deploy-rehearsal.md docs/superpowers/specs/2026-08-21-fail-fast-deploy-version-design.md docs/superpowers/plans/2026-08-21-fail-fast-deploy-version-implementation.md
rg -n "R2_BACKUP_(ACCESS_KEY_ID|SECRET_ACCESS_KEY)=|SECRET_KEY=" README.md PRD.md docs .github Dockerfile deploy core
git diff --check
```

Expected: no placeholders in the R1.4 documents, no secret values, no contradictory claim that EasyPanel/GHCR production proof is complete.

- [ ] **Step 6: Commit, push, report, and stop**

```powershell
git add README.md PRD.md docs/ROADMAP.md docs/architecture.md docs/security-and-operations.md docs/deploy-easypanel.md docs/audits/2026-08-21-fail-fast-deploy-rehearsal.md
git commit -m "docs: add fail-fast release runbook"
git push origin HEAD
```

Report the final local matrix, rehearsal result, commit SHA and exact production actions awaiting Task 7. Wait for explicit authorization before creating a tag or changing EasyPanel.

---

### Task 7: Release tag, GHCR proof and EasyPanel acceptance

**Files:**
- Modify after evidence: `docs/audits/2026-08-21-fail-fast-deploy-rehearsal.md`
- Modify after evidence: `docs/ROADMAP.md`
- Modify after evidence: `PRD.md`

**Interfaces:**
- Consumes: green `main`, approved semantic tag, GHCR package credentials in EasyPanel secret store and prior immutable SHA tag.
- Produces: a production health response whose `version` equals the deployed image SHA.

- [ ] **Step 1: Stop for explicit release authorization and identify rollback image**

Before mutating GitHub tags or EasyPanel, report current `main` SHA, proposed unused tag (for example `v1.4.0`), prior known-good `sha-<SHA>` and the exact EasyPanel image field to change. Continue only after explicit authorization.

- [ ] **Step 2: Create and push one annotated release tag**

```powershell
git fetch --tags origin
git tag --list v1.4.0
git tag -a v1.4.0 -m "Lar Finance R1.4"
git push origin v1.4.0
```

The preflight command must show that `v1.4.0` is unused. If it already exists, stop; never move or overwrite it.

- [ ] **Step 3: Require the release CI and GHCR image to succeed**

Wait for all six gates and `publish_image`. Record the workflow URL, release SHA, tags `v1.4.0` and `sha-<SHA>`, and image digest. If any job fails or the digest cannot be read, stop without changing EasyPanel.

- [ ] **Step 4: Configure EasyPanel for the private immutable image**

In the EasyPanel secret store, configure the minimum GHCR pull credential. Change the app source to:

```text
ghcr.io/ludsonfrancisco/finanpy:sha-<approved-40-character-sha>
```

Keep one replica, the `/app/data` mount, `SQLITE_PATH=/app/data/db.sqlite3`, all seven existing R2 variables, `DEBUG=False`, and no command override. Do not expose the pull token in chat, screenshots, logs or documentation.

- [ ] **Step 5: Validate startup and public identity**

Require:

```text
prepare_deploy status=ok
integrity_status=ok
supervisor web=running
supervisor backup-scheduler=running
supervisor import-preview-purge=running
GET /api/v1/health/ = 200
health.version == approved Git SHA
authenticated login = success
one read-only financial screen = success
controlled restart preserves the same health SHA and data
```

Sanitize every copied log line. Do not paste tokens, cookies, account names, descriptions or values.

- [ ] **Step 6: Exercise only the safe rollback selection path**

Confirm the previous `sha-<SHA>` remains selectable and record the exact selection procedure. Do not corrupt or downgrade the real database. The destructive failure/restore path remains proven only against the disposable copy from Task 6.

- [ ] **Step 7: Close R1.4 documentation from observed evidence**

Update the audit, ROADMAP and PRD with the workflow URL, release SHA, GHCR digest, health equality, one-replica/worker proof, scheduler status, restart proof and accepted residual risks. Mark R1.4 complete only when every item is observed.

- [ ] **Step 8: Commit, push, report completion, and stop before R2**

```powershell
git add docs/audits/2026-08-21-fail-fast-deploy-rehearsal.md docs/ROADMAP.md PRD.md
git commit -m "docs: record immutable production release"
git push origin HEAD
```

Report the documentation commit and final production SHA. Explicitly state that R2 was not started and present the next product decision without executing it.

---

## Final Acceptance Matrix

| Requirement | Primary proof |
|---|---|
| WSGI never migrates | Task 4 source assertion and focused test |
| Invalid production version blocks startup | Task 1 unit test + Task 3 command test |
| Corrupt SQLite blocks all mutation | Task 3 raw SQLite test |
| Existing DB + pending migration requires R2 | Task 3 order/failure tests |
| New/no-pending DB skips deploy backup | Task 3 branch tests |
| Deploy backup is unique and immutable | Task 2 key, If-None-Match and HEAD tests |
| Migration/audit/static failure blocks Supervisor | Task 3 tests + Task 4 entrypoint contract |
| Health identifies exact image SHA | Task 1 contract + Task 5 container smoke + Task 7 public check |
| One worker and two schedulers remain | Task 4 static test + Task 5 container top + Task 7 runtime check |
| Only approved release tags publish GHCR | Task 5 workflow tests + Task 7 tag run |
| Rollback is safe and manual | Task 6 disposable rehearsal + Task 7 prior-image selection proof |
| Docs match reality | Task 6 open-state docs + Task 7 observed closure |
