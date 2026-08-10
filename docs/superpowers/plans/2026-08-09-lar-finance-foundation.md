# Lar Finance Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Secure the current Django project, introduce the family ownership model, and expose a tested API foundation without breaking the existing web application.

**Architecture:** Keep the Django monolith, add household/owner boundaries and an API layer incrementally, migrate existing rows through reversible data migrations, and preserve the server-rendered UI as a fallback. PostgreSQL and Flutter are separate follow-up plans after this foundation is stable.

**Tech Stack:** Python 3.12, Django 5.2.13, the API/auth packages selected in ADR-001, SQLite for the migration rehearsal, Django TestCase, Ruff, Coverage, Docker Compose.

## Global Constraints

- Do not expose or repeat credentials found in QA scripts.
- Use TDD for every behavior change.
- Do not remove existing integer primary keys; add UUID as external identity.
- Every financial query must be scoped by household and owner rules.
- Do not implement PostgreSQL or Flutter in this plan.
- Keep `python manage.py test`, `check`, `makemigrations --check` and Ruff green after each task.
- Do not commit automatically; stop at review checkpoints.

---

## Task 1: Establish the verified baseline

**Files:**

- Modify: `.github/workflows/ci.yml` or create it if absent
- Modify: `.gitignore`
- Modify: `README.md`
- Test: existing Django test modules

- [ ] Run the existing suite and record test count/output in the task notes.
- [ ] Run `python manage.py check` and `python manage.py makemigrations --check`.
- [ ] Run `ruff check .` and `coverage run manage.py test` followed by `coverage report`.
- [ ] Add CI steps for dependency install, check, migration check, Ruff, tests and coverage report.
- [ ] Add a secret-scanning job/tool selected for the repository `[INVESTIGAR tool availability]`.
- [ ] Re-run the same commands locally.
- [ ] Self-review the diff for accidental secrets and unrelated changes.

## Task 2: Remove public registration

**Files:**

- Modify: `users/urls.py`
- Modify: `users/views.py`
- Modify: `core/urls.py`
- Modify: `templates/users/login.html`
- Modify: `templates/core/home.html` or the actual home template
- Test: `users/tests.py`
- Test: `core/tests.py`

- [ ] Write failing tests proving `/signup/` is unavailable and `/` redirects unauthenticated users to `/login/`.
- [ ] Run only `users.tests` and `core.tests`; verify red.
- [ ] Remove the signup route and public signup links.
- [ ] Change `HomeView` or root routing to login/dashboard redirect behavior.
- [ ] Keep administrative user creation through Django admin/command.
- [ ] Run focused tests and verify green.
- [ ] Run full suite and self-review copy/accessibility.

## Task 3: Replace credential-bearing QA scripts

**Files:**

- Delete after rotation approval: `create_accounts.py`
- Delete after rotation approval: `qa_create_accounts.py`
- Create: `accounts/tests/factories.py` or a project-consistent fixture helper `[INVESTIGAR test layout]`
- Modify: relevant QA documentation/scripts

- [ ] Confirm the exposed credential has been rotated outside Git before deleting references.
- [ ] Write a test/helper usage that creates accounts with generated users and no fixed PII.
- [ ] Replace QA dependencies on literal credentials with environment variables or fixtures.
- [ ] Search tracked files for the old secret without printing it to shared logs.
- [ ] Run the full test suite.
- [ ] Do not rewrite Git history without explicit authorization and a separate recovery plan.

## Task 4: Add Household and FinancialOwner

**Files:**

- Create: `households/__init__.py`
- Create: `households/apps.py`
- Create: `households/models.py`
- Create: `households/admin.py`
- Create: `households/tests.py`
- Modify: `core/settings.py`
- Create: `households/migrations/0001_initial.py`

- [ ] Write failing model tests for household, membership and two owners with unique constraints.
- [ ] Run `python manage.py test households`; verify red.
- [ ] Implement minimal models with UUID, timestamps and active status.
- [ ] Add admin registration without exposing unnecessary fields.
- [ ] Generate migration and inspect SQL/operations.
- [ ] Run household tests and full suite.

## Task 5: Attach existing entities to household/owner

**Files:**

- Modify: `accounts/models.py`
- Modify: `categories/models.py`
- Modify: `transactions/models.py`
- Create: migrations in each affected app
- Modify: `accounts/tests.py`
- Modify: `categories/tests.py`
- Modify: `transactions/tests.py`

- [ ] Write failing tests requiring owner and preventing cross-household relations.
- [ ] Add nullable household/owner fields first.
- [ ] Add a reversible data migration that creates one household and default owner per existing user, then backfills rows.
- [ ] Add verification assertions/counts inside migration tests.
- [ ] Make fields non-null and add constraints only after backfill.
- [ ] Update factories/forms/views to set owner explicitly.
- [ ] Run focused and full tests.
- [ ] Rehearse forward/backward migration on a copied database.

## Task 6: Add external UUID and optimistic version

**Files:**

- Modify: domain models or create a shared abstract model in a justified module
- Create: migrations
- Modify: model/view tests

- [ ] Write failing tests for unique UUID and version increments on supported mutations.
- [ ] Add non-editable UUID fields without replacing integer PKs.
- [ ] Add version field and a service-level update path; avoid magical save overrides unless ADR approves.
- [ ] Backfill UUIDs and add uniqueness after backfill.
- [ ] Run migration rehearsal and full tests.

## Task 7: Introduce Institution and transfer pairing

**Files:**

- Create or modify: `institutions/models.py` `[INVESTIGAR app boundary in ADR]`
- Modify: `accounts/models.py`
- Modify: `transactions/models.py`
- Create: migrations and tests

- [ ] Write failing tests for institution aliases and optional account institution.
- [ ] Write failing tests proving a paired internal transfer is excluded from income/expense totals.
- [ ] Implement Institution and Transfer with same-household constraints.
- [ ] Update dashboard aggregation through a domain/query service.
- [ ] Run focused tests and verify query count does not regress.

## Task 8: Approve ADR-001 and install API dependencies

**Files:**

- Create: `docs/adr/001-api-authentication.md`
- Modify: `requirements.txt`
- Modify: `core/settings.py`
- Modify: `core/urls.py`

- [ ] Compare supported API/auth choices against Django 5.2, rotation, revocation and OpenAPI needs.
- [ ] Record decision, rejected options, versions and security consequences.
- [ ] Pin exact dependencies in `requirements.txt`.
- [ ] Add minimal configuration and `/api/v1/` namespace.
- [ ] Run dependency/security checks, Django check and full tests.

## Task 9: Implement authentication and devices API

**Files:**

- Create: `api/v1/urls.py`
- Create: identity API serializers/views/services in the selected structure
- Modify: `households/models.py` or create device model in identity domain
- Create: API tests

- [ ] Write failing tests for login, refresh rotation, logout, expired token and revoked device.
- [ ] Implement endpoints with generic authentication errors.
- [ ] Store only necessary token identifiers server-side.
- [ ] Add rate limiting and safe audit events.
- [ ] Verify no email/token appears in application logs during tests.
- [ ] Run API tests and full suite.

## Task 10: Implement scoped core resources API

**Files:**

- Create: API serializers/views/services for owners, institutions, accounts, categories and transactions
- Create: API permission/filter tests
- Create: `docs/openapi/lar-finance-v1.yaml` or generated equivalent

- [ ] Write failing CRUD/filter tests for each resource.
- [ ] Add adversarial tests using IDs/UUIDs from another household.
- [ ] Implement owner/account/category validation in domain services, not only serializers.
- [ ] Add cursor pagination and deterministic ordering.
- [ ] Add OpenAPI examples with synthetic data only.
- [ ] Run contract tests and full suite.

## Task 11: Implement idempotency and sync delta

**Files:**

- Create: sync models/services/API endpoints in a domain-consistent app
- Create: migrations
- Create: sync tests
- Update: OpenAPI

- [ ] Write failing tests for repeated operation ID, stale version and delta cursor.
- [ ] Write failing test for tombstone delivery after deletion.
- [ ] Implement atomic operation receipt/idempotency storage.
- [ ] Implement version conflict response without silent overwrite.
- [ ] Implement delta cursor and tombstones with retention `[INVESTIGAR duration in ADR-004]`.
- [ ] Test retry after simulated timeout.
- [ ] Run full suite and measure query count on a multi-page delta.

## Task 12: Final verification and handoff

**Files:**

- Modify: `PRD.md`, `docs/architecture.md`, `docs/ROADMAP.md`, `README.md` only if behavior differs from the plan

- [ ] Run `ruff check .`.
- [ ] Run `python manage.py check --deploy` with safe production-like environment values.
- [ ] Run `python manage.py makemigrations --check`.
- [ ] Run the complete test suite and coverage report.
- [ ] Build the Docker image and test database persistence across container restart.
- [ ] Rehearse migrations on a copy and rollback.
- [ ] Inspect git diff for secrets, PII, generated DB/media and unrelated changes.
- [ ] Request code review before merge.
- [ ] Update Sprint 0–2 checkboxes only for evidence-backed completions.
