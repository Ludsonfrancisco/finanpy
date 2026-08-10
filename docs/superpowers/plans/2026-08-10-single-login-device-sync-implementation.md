# Lar Finance Single-Login Device Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a private `/api/v1/` that authenticates one shared Lar Finance login with independently revocable device sessions and synchronizes household financial data without silent loss or duplication.

**Architecture:** Preserve the Django web fallback and add Django REST Framework as a transport layer. Use short-lived opaque access tokens plus rotating refresh tokens stored only as HMAC digests, append-only household change events, idempotent push operations, optimistic versions, tombstones, bootstrap snapshots, and opaque delta cursors.

**Tech Stack:** Python 3.12, Django 5.2.13, Django REST Framework 3.17.1, SQLite server database, standard-library `secrets`/`hmac`/`hashlib`, Django signing, Django TestCase, Coverage 7.13.5, Ruff 0.15.11.

## Global Constraints

- Keep the Django web fallback and all 151 existing tests working.
- Use one shared household email/password in this phase; do not create a second login flow.
- Give every Windows, iOS, or Android installation its own revocable session.
- Require each device to select `self` or `spouse` as its default owner; `shared` remains selectable per record.
- Expose only UUIDs through `/api/v1/`; never expose database primary keys.
- Use 15-minute access tokens and sliding 30-day rotating refresh tokens.
- Apply rate limits of 5 login attempts/minute and 30 refresh attempts/minute per throttle identity.
- Store only HMAC-SHA256 token digests in the server database; never store raw tokens.
- Keep tokens out of response logs, exception text, analytics, and audit output.
- Scope every authenticated query and mutation to the active `HouseholdMembership` and its `Household`.
- Make every push operation idempotent by `(device_session, operation_id)` and reject reuse with different content.
- Never silently overwrite divergent amount, account, category, financial owner, or deletion changes.
- Keep unsynchronized client work recoverable; the server contract must distinguish temporary failure, validation failure, auth failure, and conflict.
- Do not implement Flutter screens, biometrics, bank-file parsing, cards, PostgreSQL migration, or EasyPanel deployment in this sprint.
- Keep SQLite at one application worker; do not add queues or Redis without measured evidence.
- Start every behavior change with a failing test, then run focused tests, full gates, commit, and push.
- Branch for execution: `codex/sprint-2-api-sync`; push after every completed task.

## File Structure

| Path | Responsibility |
|---|---|
| `api/` | HTTP transport, authentication, serializers, permissions, pagination, error envelope and `/api/v1/` routing |
| `api/models.py` | `DeviceSession` and `UsedRefreshToken` persistence |
| `api/tokens.py` | token generation, digesting, issuing, rotation, reuse detection and revocation |
| `api/authentication.py` | Bearer-token authentication and active household enforcement |
| `api/resources.py` | household-scoped read endpoints and bootstrap snapshot |
| `sync/` | sync event, idempotency, cursor and mutation domain |
| `sync/models.py` | `SyncChange` and `IdempotentOperation` |
| `sync/registry.py` | stable serialization and entity registry for accounts, categories and transactions |
| `sync/signals.py` | append change/tombstone events for web and API writes |
| `sync/services.py` | idempotent optimistic mutation engine |
| `sync/cursors.py` | signed household-bound cursor encode/decode |
| `docs/openapi-v1.yaml` | versioned client contract |

---

### Task 1: Establish the versioned API foundation

**Files:**
- Modify: `requirements.txt`
- Modify: `core/settings.py`
- Modify: `core/urls.py`
- Create: `api/__init__.py`
- Create: `api/apps.py`
- Create: `api/urls.py`
- Create: `api/views.py`
- Create: `api/exceptions.py`
- Create: `api/pagination.py`
- Create: `api/tests/__init__.py`
- Create: `api/tests/test_foundation.py`

**Interfaces:**
- Consumes: existing Django settings and root URL configuration.
- Produces: `/api/v1/health/`, `api_exception_handler(exc, context)`, `ApiCursorPagination`.

- [ ] **Step 1: Write the failing foundation tests**

```python
# api/tests/test_foundation.py
from django.test import TestCase


class ApiFoundationTest(TestCase):
    def test_health_exposes_only_stable_public_fields(self):
        response = self.client.get('/api/v1/health/')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {'status': 'ok', 'api_version': 'v1'})

    def test_method_not_allowed_uses_error_envelope(self):
        response = self.client.post('/api/v1/health/', data={}, content_type='application/json')
        self.assertEqual(response.status_code, 405)
        self.assertEqual(response.json()['error']['code'], 'method_not_allowed')
```

- [ ] **Step 2: Run the tests and verify the missing API fails**

Run: `python manage.py test api.tests.test_foundation -v 2`

Expected: FAIL because the `api` package and `/api/v1/health/` do not exist.

- [ ] **Step 3: Pin DRF and configure the API**

Add exactly `djangorestframework==3.17.1` to `requirements.txt`. Add `rest_framework` and `api` to `INSTALLED_APPS`, then configure:

```python
REST_FRAMEWORK = {
    'DEFAULT_AUTHENTICATION_CLASSES': [],
    'DEFAULT_PERMISSION_CLASSES': [
        'rest_framework.permissions.IsAuthenticated',
    ],
    'DEFAULT_PAGINATION_CLASS': 'api.pagination.ApiCursorPagination',
    'PAGE_SIZE': 50,
    'EXCEPTION_HANDLER': 'api.exceptions.api_exception_handler',
    'DEFAULT_RENDERER_CLASSES': ['rest_framework.renderers.JSONRenderer'],
    'DEFAULT_THROTTLE_RATES': {
        'login': '5/minute',
        'refresh': '30/minute',
    },
}
```

Install the pinned dependency with `python -m pip install djangorestframework==3.17.1` and verify `python -m pip show djangorestframework` reports version `3.17.1`.

Add `path('api/v1/', include('api.urls'))` before the development media route in `core/urls.py`.

- [ ] **Step 4: Implement the health route and stable error envelope**

```python
# api/views.py
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView


class HealthView(APIView):
    authentication_classes = []
    permission_classes = [AllowAny]

    def get(self, request):
        return Response({'status': 'ok', 'api_version': 'v1'})
```

```python
# api/exceptions.py
from rest_framework.views import exception_handler


def api_exception_handler(exc, context):
    response = exception_handler(exc, context)
    request = context.get('request')
    request_id = getattr(request, 'request_id', None)
    if response is None:
        return response
    detail = response.data
    code = getattr(exc, 'default_code', 'api_error')
    if isinstance(detail, dict) and 'detail' in detail:
        message = str(detail['detail'])
        fields = None
    else:
        message = 'Verifique os campos enviados.'
        fields = detail
    response.data = {
        'error': {'code': str(code), 'message': message, 'fields': fields},
        'request_id': request_id,
    }
    return response
```

Create `api/urls.py` with `path('health/', HealthView.as_view(), name='health')`. Implement `ApiCursorPagination` with `page_size=50`, `max_page_size=100`, and query parameter `limit`.

- [ ] **Step 5: Run focused and baseline gates**

Run:

```text
python manage.py test api.tests.test_foundation -v 2
python manage.py check
python manage.py makemigrations --check --dry-run
ruff check . --config pyproject.toml
```

Expected: foundation tests PASS, no system issues, no model changes, Ruff PASS.

- [ ] **Step 6: Commit and push Task 1**

```text
git add requirements.txt core/settings.py core/urls.py api
git commit -m "feat: establish private api v1"
git push origin codex/sprint-2-api-sync
```

---

### Task 2: Persist revocable device sessions and secure token rotation

**Files:**
- Create: `api/models.py`
- Create: `api/tokens.py`
- Create: `api/migrations/0001_initial.py`
- Create: `api/migrations/__init__.py`
- Create: `api/tests/test_tokens.py`
- Create: `api/admin.py`

**Interfaces:**
- Consumes: `Household`, `HouseholdMembership`, `FinancialOwner`, Django `SECRET_KEY`.
- Produces: `issue_session`, `rotate_refresh_token`, `revoke_session`, `digest_token`, `IssuedTokens`.

- [ ] **Step 1: Write failing token-service tests**

```python
# api/tests/test_tokens.py
from datetime import timedelta

from django.test import TestCase
from django.utils import timezone

from api.models import DeviceSession, UsedRefreshToken
from api.tokens import RefreshReuseError, digest_token, issue_session, rotate_refresh_token
from households.services import ensure_household_for_user, get_financial_owner
from users.models import User


class DeviceTokenServiceTest(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(email='lar@example.test', password='Strong-pass-123')
        self.household = ensure_household_for_user(self.user)
        self.owner = get_financial_owner(self.household, owner_type='self')

    def test_raw_tokens_are_returned_once_but_only_digests_are_stored(self):
        issued = issue_session(
            user=self.user,
            household=self.household,
            default_owner=self.owner,
            platform=DeviceSession.WINDOWS,
            name='Notebook',
        )
        session = issued.session
        self.assertNotEqual(session.access_token_digest, issued.access_token)
        self.assertEqual(session.access_token_digest, digest_token(issued.access_token))
        self.assertEqual(session.refresh_token_digest, digest_token(issued.refresh_token))
        self.assertNotIn(issued.access_token, repr(session.__dict__))

    def test_refresh_rotates_both_tokens_and_reuse_revokes_session(self):
        issued = issue_session(
            user=self.user,
            household=self.household,
            default_owner=self.owner,
            platform=DeviceSession.WINDOWS,
            name='Notebook',
        )
        rotated = rotate_refresh_token(issued.refresh_token)
        self.assertNotEqual(rotated.refresh_token, issued.refresh_token)
        self.assertTrue(UsedRefreshToken.objects.filter(
            token_digest=digest_token(issued.refresh_token),
        ).exists())
        with self.assertRaises(RefreshReuseError):
            rotate_refresh_token(issued.refresh_token)
        issued.session.refresh_from_db()
        self.assertIsNotNone(issued.session.revoked_at)
```

- [ ] **Step 2: Verify the token tests fail before implementation**

Run: `python manage.py test api.tests.test_tokens -v 2`

Expected: FAIL because `DeviceSession`, `UsedRefreshToken`, and token services do not exist.

- [ ] **Step 3: Implement the device-session models**

Create `DeviceSession` with these exact fields and constraints:

```python
class DeviceSession(models.Model):
    WINDOWS = 'windows'
    IOS = 'ios'
    ANDROID = 'android'
    PLATFORM_CHOICES = [(WINDOWS, 'Windows'), (IOS, 'iOS'), (ANDROID, 'Android')]

    uuid = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name='device_sessions')
    household = models.ForeignKey('households.Household', on_delete=models.PROTECT, related_name='device_sessions')
    default_owner = models.ForeignKey('households.FinancialOwner', on_delete=models.PROTECT, related_name='device_sessions')
    platform = models.CharField(max_length=16, choices=PLATFORM_CHOICES)
    name = models.CharField(max_length=80)
    access_token_digest = models.CharField(max_length=64, unique=True)
    access_expires_at = models.DateTimeField()
    refresh_token_digest = models.CharField(max_length=64, unique=True)
    refresh_expires_at = models.DateTimeField()
    revoked_at = models.DateTimeField(null=True, blank=True)
    last_seen_at = models.DateTimeField(default=timezone.now)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
```

`clean()` must reject a household outside the user's active membership, a default owner from another household, and the `shared` owner as device default. Create `UsedRefreshToken` with `session=ForeignKey(PROTECT)`, unique `token_digest`, `used_at`, and `expires_at`.

- [ ] **Step 4: Implement token issue, rotation, reuse detection, and revocation**

```python
# api/tokens.py public contract
ACCESS_LIFETIME = timedelta(minutes=15)
REFRESH_LIFETIME = timedelta(days=30)

@dataclass(frozen=True)
class IssuedTokens:
    session: DeviceSession
    access_token: str
    refresh_token: str

def digest_token(raw_token: str) -> str:
    return hmac.new(
        settings.SECRET_KEY.encode('utf-8'),
        raw_token.encode('utf-8'),
        hashlib.sha256,
    ).hexdigest()

def new_token() -> str:
    return secrets.token_urlsafe(48)
```

Implement `issue_session(*, user, household, default_owner, platform: str, name: str) -> IssuedTokens` inside `transaction.atomic()`. Implement `rotate_refresh_token(raw_token: str) -> IssuedTokens` with `select_for_update()`: reject expired/revoked sessions, create `UsedRefreshToken` for the old digest, rotate both tokens, and extend refresh expiry by 30 days. If a digest already exists in `UsedRefreshToken`, revoke its session and raise `RefreshReuseError`. Implement `revoke_session(session: DeviceSession) -> None` by setting `revoked_at=timezone.now()` once.

- [ ] **Step 5: Create and inspect the migration**

Run:

```text
python manage.py makemigrations api
python manage.py sqlmigrate api 0001
python manage.py test api.tests.test_tokens -v 2
python manage.py makemigrations --check --dry-run
```

Expected: migration contains both tables and unique token digests; token tests PASS; no pending migration.

- [ ] **Step 6: Commit and push Task 2**

```text
git add api/models.py api/tokens.py api/admin.py api/migrations api/tests/test_tokens.py
git commit -m "feat: add revocable device sessions"
git push origin codex/sprint-2-api-sync
```

---

### Task 3: Expose login, refresh, logout, device list, default owner, and revocation

**Files:**
- Create: `api/authentication.py`
- Create: `api/permissions.py`
- Create: `api/serializers.py`
- Create: `api/auth_views.py`
- Create: `api/tests/test_auth_api.py`
- Modify: `api/urls.py`
- Modify: `core/settings.py`

**Interfaces:**
- Consumes: Task 2 token services and `HouseholdMembership`.
- Produces: authenticated `request.user`, `request.auth` as `DeviceSession`, and auth/device endpoints.

- [ ] **Step 1: Write failing lifecycle and isolation tests**

Add tests for these exact behaviors:

```python
AUTH_CASES = (
    ('login_success', '/api/v1/auth/login/', 200, ('access_token', 'refresh_token', 'device')),
    ('shared_owner_default', '/api/v1/auth/login/', 400, ('default_owner_uuid',)),
    ('unknown_email', '/api/v1/auth/login/', 401, ('invalid_credentials',)),
    ('wrong_password', '/api/v1/auth/login/', 401, ('invalid_credentials',)),
    ('sixth_login_attempt', '/api/v1/auth/login/', 429, ('throttled',)),
    ('refresh_rotation', '/api/v1/auth/refresh/', 200, ('new_access', 'new_refresh')),
    ('logout_current', '/api/v1/auth/logout/', 204, ('current_revoked', 'other_active')),
    ('device_list', '/api/v1/devices/', 200, ('same_user_only', 'no_token_fields')),
    ('revoke_other', '/api/v1/devices/{device_uuid}/revoke/', 204, ('target_revoked', 'current_active')),
    ('patch_current_owner', '/api/v1/devices/current/', 200, ('self_or_spouse_only',)),
    ('inactive_membership', '/api/v1/devices/', 401, ('revoked_device',)),
)
```

Create one test method per case with shared fixture helpers. Post JSON using the concrete route from the case, assert the exact status and named outcomes, assert unknown email and wrong password return identical bodies, and never print returned tokens.

- [ ] **Step 2: Run tests to prove endpoints are absent**

Run: `python manage.py test api.tests.test_auth_api -v 2`

Expected: FAIL with missing routes/authentication.

- [ ] **Step 3: Implement Bearer authentication**

`DeviceTokenAuthentication.authenticate(request)` must:

1. accept exactly `Authorization: Bearer <token>`;
2. digest the raw value;
3. load a non-revoked, non-expired `DeviceSession` with user/household/default owner;
4. verify user, household, and membership are active;
5. update `last_seen_at` only when older than five minutes;
6. return `(session.user, session)`;
7. raise DRF `AuthenticationFailed` with stable codes `invalid_token`, `expired_token`, or `revoked_device`.

Set it as the first `DEFAULT_AUTHENTICATION_CLASSES` entry in `REST_FRAMEWORK`.

- [ ] **Step 4: Implement serializers and endpoints**

Expose exactly:

| Method | Path | Behavior |
|---|---|---|
| POST | `/api/v1/auth/login/` | email, password, platform, device name, default owner UUID |
| POST | `/api/v1/auth/refresh/` | rotate refresh token |
| POST | `/api/v1/auth/logout/` | revoke current device |
| GET | `/api/v1/devices/` | list current user's sessions without digests |
| PATCH | `/api/v1/devices/current/` | rename device or change self/spouse default |
| POST | `/api/v1/devices/<uuid>/revoke/` | revoke one owned session |

Login/refresh responses use:

```json
{
  "access_token": "returned-once",
  "access_expires_at": "ISO-8601",
  "refresh_token": "returned-once",
  "refresh_expires_at": "ISO-8601",
  "device": {
    "uuid": "UUID",
    "name": "Notebook",
    "platform": "windows",
    "default_owner_uuid": "UUID"
  }
}
```

Set `throttle_scope='login'` on login and `throttle_scope='refresh'` on refresh with `ScopedRateThrottle`. Return the same `invalid_credentials` message for unknown email and wrong password.

- [ ] **Step 5: Run auth, security, and regression tests**

Run:

```text
python manage.py test api.tests.test_auth_api api.tests.test_tokens households.tests.test_access -v 2
python manage.py check
ruff check api core/settings.py --config pyproject.toml
```

Expected: all focused tests PASS and no token digest appears in serialized devices.

- [ ] **Step 6: Commit and push Task 3**

```text
git add api core/settings.py
git commit -m "feat: expose device authentication api"
git push origin codex/sprint-2-api-sync
```

---

### Task 4: Add sync metadata, append-only changes, and idempotency persistence

**Files:**
- Modify: `core/settings.py`
- Modify: `accounts/models.py`
- Modify: `categories/models.py`
- Modify: `transactions/models.py`
- Create: `accounts/migrations/0005_account_sync_metadata.py`
- Create: `categories/migrations/0005_category_sync_metadata.py`
- Create: `transactions/migrations/0005_transaction_sync_metadata.py`
- Create: `sync/__init__.py`
- Create: `sync/apps.py`
- Create: `sync/models.py`
- Create: `sync/admin.py`
- Create: `sync/migrations/0001_initial.py`
- Create: `sync/migrations/__init__.py`
- Create: `sync/tests/__init__.py`
- Create: `sync/tests/test_models.py`
- Create: `sync/tests/test_migrations.py`

**Interfaces:**
- Consumes: current Household-scoped Account, Category, Transaction and Task 2 DeviceSession.
- Produces: external `uuid`, integer `sync_version`, `SyncChange`, `IdempotentOperation`.

- [ ] **Step 1: Write failing model and migration tests**

Tests must prove:

```python
MODEL_CASES = (
    ('account_uuid', 'Account', 'uuid', True, True),
    ('category_uuid', 'Category', 'uuid', True, True),
    ('transaction_uuid', 'Transaction', 'uuid', True, True),
    ('change_order', 'SyncChange', 'id', True, False),
    ('operation_same_device', 'IdempotentOperation', 'operation_id', False, True),
    ('operation_different_device', 'IdempotentOperation', 'operation_id', True, False),
)
```

For each entity UUID case, create two rows and assert non-null, unequal UUIDs and `field.editable is False`. For change order, create two changes and assert ascending IDs. For idempotency, assert a duplicate `(device, operation_id)` raises `IntegrityError` while the same operation UUID on a second device succeeds. Add `test_sync_change_cannot_be_updated_or_deleted_through_model_api`: changing `payload` and calling `save()` or calling `delete()` on a stored event must raise `ImmutableSyncChangeError`.

Migration tests must migrate a legacy fixture at the current `0004` state, create two rows per entity, migrate forward, and assert all UUIDs are populated/unique and every `sync_version == 1`. Reverse to `0004` and assert legacy fields/data remain.

- [ ] **Step 2: Verify tests fail before fields/apps exist**

Run: `python manage.py test sync.tests.test_models sync.tests.test_migrations -v 2`

Expected: FAIL because `sync` and metadata do not exist.

- [ ] **Step 3: Add sync metadata to financial entities**

Add to `Account`, `Category`, and `Transaction`:

```python
uuid = models.UUIDField(default=uuid.uuid4, unique=True, editable=False)
sync_version = models.PositiveBigIntegerField(default=1, editable=False)
```

Use three additive migrations. Do not add a callable default and `unique=True` in a single direct `AddField`, because legacy rows could receive an unsafe duplicated value on some migration paths. Each migration must perform this exact sequence:

1. `AddField` UUID as nullable and non-unique;
2. `RunPython` over rows in deterministic PK batches and assign a fresh `uuid.uuid4()` to each row;
3. `AlterField` UUID to non-null, `unique=True`, `default=uuid.uuid4`, `editable=False`;
4. add `sync_version` with database default 1 and preserve it as application default 1.

The reverse path drops only the two Sprint 2 fields. Do not rewrite migrations `0001` through `0004`.

- [ ] **Step 4: Implement append-only and idempotency models**

`SyncChange` exact contract:

```python
class SyncChange(models.Model):
    CREATE = 'create'
    UPDATE = 'update'
    DELETE = 'delete'
    OPERATION_CHOICES = [(CREATE, 'Create'), (UPDATE, 'Update'), (DELETE, 'Delete')]

    household = models.ForeignKey('households.Household', on_delete=models.PROTECT, related_name='sync_changes')
    device_session = models.ForeignKey('api.DeviceSession', null=True, blank=True, on_delete=models.PROTECT, related_name='sync_changes')
    operation_id = models.UUIDField(null=True, blank=True)
    entity_type = models.CharField(max_length=32)
    entity_uuid = models.UUIDField()
    entity_version = models.PositiveBigIntegerField()
    operation = models.CharField(max_length=8, choices=OPERATION_CHOICES)
    payload = models.JSONField()
    created_at = models.DateTimeField(auto_now_add=True)
```

Index `(household, id)` and `(household, entity_type, entity_uuid)`. `IdempotentOperation` stores `device_session`, `operation_id`, 64-character request hash, HTTP status, JSON response, and timestamps, with a unique constraint on `(device_session, operation_id)`. Make `SyncChange` append-only by allowing `save()` only while `_state.adding` is true and rejecting instance `delete()`. Register it in admin with every field read-only and without add/delete permissions.

- [ ] **Step 5: Generate, inspect, and test migrations**

Run:

```text
python manage.py makemigrations accounts categories transactions sync
python manage.py sqlmigrate sync 0001
python manage.py test sync.tests.test_models sync.tests.test_migrations -v 2
python manage.py makemigrations --check --dry-run
```

Expected: additive fields, physical uniqueness, sync indexes/constraint, forward/rollback PASS.

- [ ] **Step 6: Commit and push Task 4**

```text
git add core/settings.py accounts categories transactions sync
git commit -m "feat: add sync metadata and change ledger"
git push origin codex/sprint-2-api-sync
```

---

### Task 5: Capture web/API changes and expose a stable bootstrap snapshot

**Files:**
- Create: `sync/registry.py`
- Create: `sync/signals.py`
- Create: `sync/context.py`
- Create: `sync/cursors.py`
- Modify: `sync/apps.py`
- Create: `sync/tests/test_capture.py`
- Create: `api/resource_serializers.py`
- Create: `api/resources.py`
- Create: `api/tests/test_resources.py`
- Modify: `api/urls.py`

**Interfaces:**
- Consumes: Task 4 metadata/change models and Task 3 authentication.
- Produces: `serialize_entity(instance)`, `capture_sync_context(*, device_session=None, operation_id=None)`, `/api/v1/bootstrap/`, read-only resource routes.

- [ ] **Step 1: Write failing capture and read-isolation tests**

Cover:

```python
CAPTURE_EXPECTATIONS = (
    ('account_create', 'create', 1, ('uuid', 'version', 'household_uuid')),
    ('account_update', 'update', 2, ('uuid', 'version', 'name')),
    ('transaction_delete', 'delete', 2, ('uuid', 'deleted')),
    ('transaction_relations', 'create', 1, ('account_uuid', 'category_uuid', 'financial_owner_uuid')),
)

RESOURCE_EXPECTATIONS = (
    ('bootstrap', '/api/v1/bootstrap/', ('household', 'owners', 'accounts', 'categories', 'transactions', 'summary', 'cursor')),
    ('accounts', '/api/v1/accounts/', ('current_household_only', 'no_database_id')),
    ('categories', '/api/v1/categories/', ('current_household_only', 'no_database_id')),
    ('transactions', '/api/v1/transactions/', ('current_household_only', 'no_database_id')),
    ('owners', '/api/v1/owners/', ('uuid', 'type', 'name')),
)
```

Implement one assertion-focused test per tuple. Each capture test must assert exactly one new `SyncChange`; each resource test must create a foreign Lar row and assert its UUID/name never appears in the JSON.

- [ ] **Step 2: Run tests and confirm no capture/bootstrap exists**

Run: `python manage.py test sync.tests.test_capture api.tests.test_resources -v 2`

Expected: FAIL for missing registry/signals/routes.

- [ ] **Step 3: Implement stable entity serializers and capture context**

`sync.registry` must register exactly `account`, `category`, and `transaction`. Each payload includes `uuid`, `version`, `created_at`, `updated_at`, and domain fields. Relationships use `household.uuid`, `financial_owner.uuid`, `account.uuid`, and `category.uuid`; Decimal/date/datetime values are strings.

Use a `contextvars.ContextVar` carrying optional `device_session` and `operation_id`:

```python
@contextmanager
def capture_sync_context(*, device_session=None, operation_id=None):
    token = current_sync_context.set({
        'device_session': device_session,
        'operation_id': operation_id,
    })
    try:
        yield
    finally:
        current_sync_context.reset(token)
```

- [ ] **Step 4: Capture create/update/delete without recursion**

Connect signals only to `Account`, `Category`, and `Transaction` in `SyncConfig.ready()`.

- `pre_save`: on update, load the stored version. If `instance.sync_version == stored.sync_version + 1`, preserve it because the locked mutation service already advanced it; otherwise set it to `stored.sync_version + 1` for the web fallback.
- `post_save`: append `SyncChange` with create/update payload.
- `pre_delete`: append a delete tombstone with the entity's last version plus one and payload `{'uuid': str(instance.uuid), 'deleted': True}`.
- Never connect signals to `SyncChange` or `IdempotentOperation`.

Register `sync.apps.SyncConfig` in settings.

- [ ] **Step 5: Implement scoped read resources and bootstrap**

Expose authenticated GET routes:

```text
/api/v1/household/
/api/v1/owners/
/api/v1/accounts/
/api/v1/categories/
/api/v1/transactions/
/api/v1/summary/
/api/v1/bootstrap/
```

Bootstrap returns `{household, owners, accounts, categories, transactions, summary, cursor}` in one transaction. `cursor` represents the largest `SyncChange.id` visible to the Lar at snapshot completion. Create `sync/cursors.py` now with this final contract:

```python
from django.core import signing

CURSOR_SALT = 'lar-finance.sync.cursor.v1'


class InvalidCursor(ValueError):
    pass


def encode_cursor(change_id: int, household_uuid) -> str:
    return signing.dumps(
        {'change_id': int(change_id), 'household_uuid': str(household_uuid)},
        salt=CURSOR_SALT,
        compress=True,
    )


def decode_cursor(cursor: str, household_uuid) -> int:
    try:
        payload = signing.loads(cursor, salt=CURSOR_SALT)
        change_id = int(payload['change_id'])
    except (signing.BadSignature, KeyError, TypeError, ValueError) as exc:
        raise InvalidCursor from exc
    if change_id < 0 or payload.get('household_uuid') != str(household_uuid):
        raise InvalidCursor
    return change_id
```

Task 7 adds exhaustive tests and the delta endpoint without renaming these interfaces.

- [ ] **Step 6: Run focused and existing web tests**

Run:

```text
python manage.py test sync.tests.test_capture api.tests.test_resources accounts.tests categories.tests transactions.tests core.tests -v 2
ruff check sync api --config pyproject.toml
```

Expected: capture/resource tests PASS; existing web CRUD/dashboard tests remain PASS.

- [ ] **Step 7: Commit and push Task 5**

```text
git add sync api
git commit -m "feat: capture household sync changes"
git push origin codex/sprint-2-api-sync
```

---

### Task 6: Apply idempotent optimistic push operations

**Files:**
- Create: `sync/exceptions.py`
- Create: `sync/services.py`
- Create: `sync/hashes.py`
- Create: `sync/tests/test_push_service.py`
- Create: `api/sync_views.py`
- Create: `api/tests/test_sync_push.py`
- Modify: `api/urls.py`

**Interfaces:**
- Consumes: entity registry, DeviceSession, IdempotentOperation, capture context.
- Produces: `apply_operation(device_session, operation) -> OperationResult`, `POST /api/v1/sync/push/`.

- [ ] **Step 1: Write failing idempotency, validation, and conflict tests**

Test exact cases:

```python
PUSH_CASES = (
    ('retry_create', 'account', 'create', None, 200, 'duplicate', 1),
    ('changed_body_same_operation', 'account', 'create', None, 200, 'idempotency_conflict', 0),
    ('current_update', 'transaction', 'update', 1, 200, 'applied', 2),
    ('stale_amount', 'transaction', 'update', 1, 200, 'conflict', 2),
    ('stale_owner', 'transaction', 'update', 1, 200, 'conflict', 2),
    ('stale_delete', 'transaction', 'delete', 1, 200, 'conflict', 2),
    ('foreign_relation', 'transaction', 'create', None, 200, 'invalid', 0),
    ('mixed_batch', 'account', 'create', None, 200, 'per_operation_results', 1),
    ('oversized_batch', 'account', 'create', None, 400, 'max_100_operations', 0),
    ('account_in_use', 'account', 'delete', 1, 200, 'resource_in_use', 1),
    ('category_in_use', 'category', 'delete', 1, 200, 'resource_in_use', 1),
)
```

Build exact JSON operations from each tuple, submit them to `/api/v1/sync/push/`, and assert HTTP status, result status/code, resulting version, row count, and unchanged persisted sensitive fields for every conflict case.

- [ ] **Step 2: Verify push tests fail**

Run: `python manage.py test sync.tests.test_push_service api.tests.test_sync_push -v 2`

Expected: FAIL because push service/route do not exist.

- [ ] **Step 3: Implement canonical request hashing and stored outcomes**

```python
def request_hash(operation: dict) -> str:
    canonical = json.dumps(operation, sort_keys=True, separators=(',', ':'), ensure_ascii=False)
    return hashlib.sha256(canonical.encode('utf-8')).hexdigest()
```

Within `transaction.atomic()`, look up `(device_session, operation_id)` first. Return its stored response when hashes match; raise `IdempotencyConflict` when they differ. Store validation/conflict/success outcomes so a timeout retry receives the identical result.

- [ ] **Step 4: Implement the mutation service**

Accepted operation schema:

```json
{
  "operation_id": "UUID",
  "entity": "account|category|transaction",
  "action": "create|update|delete",
  "entity_uuid": "UUID",
  "expected_version": 3,
  "data": {}
}
```

For create, `expected_version` must be null and version starts at 1. For update/delete, lock the row with `select_for_update()` scoped to the session household and compare `expected_version`. Resolve all related UUIDs inside the same household. Call `full_clean()` before save. Use `capture_sync_context(device_session=session, operation_id=operation_id)` so the resulting change is attributed without logging contents.

Return one of:

```json
{"status":"applied","entity":{}}
{"status":"duplicate","entity":{}}
{"status":"conflict","code":"version_conflict","submitted":{},"current":{}}
{"status":"invalid","code":"validation_error","fields":{}}
```

- [ ] **Step 5: Implement the batch endpoint**

`POST /api/v1/sync/push/` accepts `{"operations": [{"operation_id": "UUID", "entity": "account", "action": "create", "entity_uuid": "UUID", "expected_version": null, "data": {"name": "Carteira", "type": "cash", "initial_balance": "0.00", "currency": "BRL", "financial_owner_uuid": "UUID"}}]}` with 1–100 entries. Process each operation in its own atomic block, preserve request order, return HTTP 200 for a syntactically valid batch, and put each per-operation status in `results`. Authentication/invalid JSON/oversized batches use normal 4xx responses.

- [ ] **Step 6: Run focused, boundary, and capture tests**

Run:

```text
python manage.py test sync.tests.test_push_service api.tests.test_sync_push sync.tests.test_capture households.tests.test_boundaries -v 2
python manage.py check
ruff check sync api --config pyproject.toml
```

Expected: retry is single-effect, stale writes conflict, and cross-Lar tests PASS.

- [ ] **Step 7: Commit and push Task 6**

```text
git add sync api
git commit -m "feat: add idempotent optimistic sync push"
git push origin codex/sprint-2-api-sync
```

---

### Task 7: Deliver signed delta cursors and tombstone pull

**Files:**
- Modify: `sync/cursors.py`
- Create: `sync/tests/test_cursors.py`
- Modify: `api/sync_views.py`
- Create: `api/tests/test_sync_pull.py`
- Modify: `api/urls.py`
- Modify: `api/resources.py`

**Interfaces:**
- Consumes: append-only SyncChange and authenticated DeviceSession.
- Produces: `encode_cursor(change_id, household_uuid)`, `decode_cursor(cursor, household_uuid)`, `GET /api/v1/sync/changes/`.

- [ ] **Step 1: Write failing cursor and pull tests**

```python
CURSOR_CASES = (
    ('round_trip', 42, 'same_household', 42),
    ('tampered', 42, 'changed_signature', 'invalid_cursor'),
    ('foreign_household', 42, 'other_household', 'invalid_cursor'),
)

PULL_CASES = (
    ('ordered_after_cursor', 2, 3, ('ascending', 'next_cursor')),
    ('delete_tombstone', 1, 1, ('delete', 'deleted_true')),
    ('limit_100', 101, 100, ('next_cursor', 'remaining_one')),
    ('repeat_cursor', 3, 3, ('identical_body', 'identical_cursor')),
    ('empty', 0, 0, ('same_cursor', 'empty_results')),
)
```

Create one test for each tuple. Cursor tests call the public encode/decode functions directly. Pull tests create the stated number of changes, authenticate a device, and assert count, order, tombstone payload and cursor behavior exactly.

- [ ] **Step 2: Verify tests fail before cursor implementation**

Run: `python manage.py test sync.tests.test_cursors api.tests.test_sync_pull -v 2`

Expected: FAIL because cursor/pull are missing.

- [ ] **Step 3: Verify and harden signed household-bound cursors**

```python
CURSOR_SALT = 'lar-finance.sync.cursor.v1'

def encode_cursor(change_id: int, household_uuid) -> str:
    return signing.dumps(
        {'change_id': int(change_id), 'household_uuid': str(household_uuid)},
        salt=CURSOR_SALT,
        compress=True,
    )

def decode_cursor(cursor: str, household_uuid) -> int:
    try:
        payload = signing.loads(cursor, salt=CURSOR_SALT)
    except signing.BadSignature as exc:
        raise InvalidCursor from exc
    if payload.get('household_uuid') != str(household_uuid):
        raise InvalidCursor
    return int(payload['change_id'])
```

Use an encoded zero cursor when none is supplied; do not expose raw database IDs.

- [ ] **Step 4: Implement delta pull and finalize bootstrap cursor**

`GET /api/v1/sync/changes/?cursor=<opaque>&limit=100` filters `household=request.auth.household` and `id > decoded_change_id`, orders by `id`, caps limit at 100, returns serialized events and cursor of the last returned event. If empty, return the supplied cursor. Update bootstrap to use the max visible change ID encoded with the same function.

- [ ] **Step 5: Run pull, push, and resource contract tests**

Run:

```text
python manage.py test sync.tests.test_cursors api.tests.test_sync_pull api.tests.test_sync_push api.tests.test_resources -v 2
ruff check sync api --config pyproject.toml
```

Expected: signed cursor isolation, stable repeated page, and tombstones PASS.

- [ ] **Step 6: Commit and push Task 7**

```text
git add sync/cursors.py sync/tests/test_cursors.py api/sync_views.py api/resources.py api/urls.py api/tests/test_sync_pull.py
git commit -m "feat: add household delta sync pull"
git push origin codex/sprint-2-api-sync
```

---

### Task 8: Add request IDs, safe structured logging, and the OpenAPI contract

**Files:**
- Create: `api/middleware.py`
- Create: `api/logging.py`
- Create: `api/tests/test_observability.py`
- Modify: `core/settings.py`
- Create: `docs/openapi-v1.yaml`
- Create: `api/tests/test_openapi_contract.py`
- Modify: `docs/architecture.md`
- Modify: `docs/security-and-operations.md`
- Modify: `docs/ROADMAP.md`

**Interfaces:**
- Consumes: all Sprint 2 routes and stable error codes.
- Produces: `X-Request-ID`, JSON access logs, complete OpenAPI 3.1 contract.

- [ ] **Step 1: Write failing privacy and contract tests**

Tests must capture logs and prove:

```python
OBSERVABILITY_CASES = (
    ('generated_request_id', None, 'uuid_response_header'),
    ('valid_request_id', 'e8b27e90-7b70-4c1e-bef1-6c8791e5fa31', 'same_response_header'),
    ('invalid_request_id', 'not-a-uuid', 'replacement_uuid'),
    ('login_privacy', 'lar@example.test Strong-pass-123', 'neither_value_in_log'),
    ('sync_privacy', '999.99 private description', 'neither_value_in_log'),
)

OPENAPI_EXPECTATIONS = (
    ('version', '3.1.0'),
    ('security_scheme', 'opaqueBearer'),
    ('error_schema', 'ErrorEnvelope'),
    ('route_count', 16),
)
```

Create one test per observability tuple using `self.assertLogs('lar_finance.api')`. Parse every emitted line with `json.loads` and assert forbidden input fragments are absent. Contract tests load `docs/openapi-v1.yaml` directly with `json.load` and assert all routes returned by Django's API URL resolver are represented.

Write `docs/openapi-v1.yaml` using JSON object syntax, which is valid YAML 1.2, and load that same file with Python `json.load`; do not maintain a mirrored constant and do not add PyYAML only for tests.

- [ ] **Step 2: Verify tests fail before middleware/contract exist**

Run: `python manage.py test api.tests.test_observability api.tests.test_openapi_contract -v 2`

Expected: FAIL for missing request ID, logs, and contract.

- [ ] **Step 3: Implement request ID middleware and safe API access logs**

Accept `X-Request-ID` only when it parses as UUID; otherwise generate `uuid.uuid4()`. Set `request.request_id` and the response header. Log one JSON object after response with exactly: timestamp, level, service, request_id, method, normalized route name, status, duration_ms, authenticated flag, device UUID when authenticated, and error code. Never log query/body/headers/token/email/financial values.

Insert middleware after `SecurityMiddleware`. Configure logger `lar_finance.api` to stdout with a JSON formatter and `propagate=False`.

- [ ] **Step 4: Write the complete OpenAPI 3.1 contract**

The document must list every route from Tasks 1, 3, 5, 6, and 7; define schemas `ErrorEnvelope`, `Device`, `TokenPair`, `Household`, `FinancialOwner`, `Account`, `Category`, `Transaction`, `Bootstrap`, `PushOperation`, `PushResult`, `SyncChange`, and `DeltaPage`; declare `opaqueBearer` as HTTP bearer without claiming JWT; include 400/401/403/404/409/429/500 responses where applicable.

The top-level metadata is exact:

```json
{
  "openapi": "3.1.0",
  "info": {
    "title": "Lar Finance Private API",
    "version": "1.0.0"
  },
  "servers": [{"url": "/api/v1"}]
}
```

- [ ] **Step 5: Update evidence-backed documentation**

Mark only delivered Sprint 2 items complete in `docs/ROADMAP.md`. Update architecture and security docs with actual routes, token lifetimes, opaque-token storage, throttles, request-ID fields, remaining limits, and no claim of Flutter/EasyPanel deployment.

- [ ] **Step 6: Run privacy and contract gates**

Run:

```text
python manage.py test api.tests.test_observability api.tests.test_openapi_contract -v 2
python manage.py check --deploy --fail-level WARNING
ruff check . --config pyproject.toml
git diff --check
```

Expected: no sensitive values in captured logs, every route in the contract, all gates PASS.

- [ ] **Step 7: Commit and push Task 8**

```text
git add api core/settings.py docs/openapi-v1.yaml docs/architecture.md docs/security-and-operations.md docs/ROADMAP.md
git commit -m "docs: publish private api v1 contract"
git push origin codex/sprint-2-api-sync
```

---

### Task 9: Run migration rehearsals, full verification, and Sprint 2 handoff

**Files:**
- Create: `docs/sprints/sprint-2-api-sync.md`
- Modify: `PRD.md`
- Modify: `README.md`
- Modify: `docs/README.md`
- Modify: `.github/workflows/ci.yml`
- Create: `api/tests/test_migrations.py`

**Interfaces:**
- Consumes: completed Tasks 1–8.
- Produces: CI gate, migration evidence, final sprint report and rollback instructions.

- [ ] **Step 1: Extend CI with contract and warning checks**

Keep existing secret scan and Django gates. Ensure CI installs the newly pinned requirement and runs:

```text
python -Wd manage.py test
coverage report --fail-under=90
python manage.py makemigrations --check
python manage.py check --deploy --fail-level WARNING
ruff check . --config pyproject.toml
```

The `-Wd` test run must fail on new deprecation warnings from project code.

- [ ] **Step 2: Rehearse fresh, legacy-forward, and rollback migrations**

Use temporary SQLite files only. Verify:

1. fresh database migrates to head;
2. database at Sprint 1 migrations with sample Lar data migrates forward;
3. UUIDs are populated and unique, versions are 1, sessions/changes are empty;
4. rollback removes only Sprint 2 schema and preserves Sprint 1 financial rows;
5. migrate forward again and run `audit_household_integrity`.

Add any missing automated migration case to `sync/tests/test_migrations.py` or `api/tests/test_migrations.py` before proceeding.

- [ ] **Step 3: Run the complete verification matrix**

Run with ephemeral `SECRET_KEY`, production security env, and `SECURE_SSL_REDIRECT=False` only for tests:

```text
ruff check . --config pyproject.toml
python manage.py check
python manage.py check --deploy --fail-level WARNING
python manage.py makemigrations --check --dry-run
coverage erase
coverage run manage.py test
coverage report --fail-under=90
git diff --check
```

Expected: all tests PASS, coverage at least 90%, no pending migrations, no deploy warning, no formatting errors.

- [ ] **Step 4: Write the Sprint 2 handoff**

`docs/sprints/sprint-2-api-sync.md` must record commits, exact versions, routes, token lifetimes, throttle rates, migration rehearsal counts, test/coverage results, known limits, rollback steps, and these explicit production blocks:

- no automatic EasyPanel deploy;
- no production migration until external backup restore is proven;
- historical credential rotation remains owner action;
- Flutter/import UI does not exist yet;
- SQLite remains one replica/worker.

Update PRD/README/docs index only with verified delivered behavior. Set Sprint 2 checkbox complete only after the final review is clean.

- [ ] **Step 5: Commit and push Task 9**

```text
git add .github/workflows/ci.yml PRD.md README.md docs api/tests sync/tests
git commit -m "test: verify private api sync sprint"
git push origin codex/sprint-2-api-sync
```

- [ ] **Step 6: Request final independent review before merging**

Reviewer must inspect the complete branch range from its merge base, verify spec coverage, security boundaries, token reuse behavior, cross-household isolation, idempotency, conflicts, migration reversibility, logs, OpenAPI, CI, and docs. Fix every Critical/Important finding, rerun covering tests, re-review, then run the full matrix again.

Expected final verdict: Spec PASS, Quality PASS, Ready to merge YES.

## Plan Sources

- Product design: `docs/superpowers/specs/2026-08-10-single-login-device-sync-design.md`
- Current architecture: `docs/architecture.md`
- Current roadmap: `docs/ROADMAP.md`
- Django REST Framework 3.17.1 release and compatibility: https://www.django-rest-framework.org/community/release-notes/
- Verified package artifact: https://pypi.org/project/djangorestframework/3.17.1/

## Self-Review Record

- Spec coverage: authentication, per-device revocation/default owner, automatic sync contract, offline-safe outbox semantics, idempotency, optimistic conflict handling, tombstones, error states, performance bootstrap, privacy, OpenAPI and tests each map to Tasks 1–9.
- Scope: Flutter UI, bank import, cards, PostgreSQL and EasyPanel changes remain explicitly excluded.
- Type consistency: `DeviceSession`, `IssuedTokens`, `SyncChange`, `IdempotentOperation`, `capture_sync_context`, `apply_operation`, `encode_cursor` and `decode_cursor` retain the same names/signatures across tasks.
- Placeholder scan: all steps contain concrete paths, commands, interfaces, inputs and expected outcomes.
