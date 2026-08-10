# Lar Finance Operations and Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate canonical storage to PostgreSQL, make the home-server deployment recoverable/observable, and distribute signed Lar Finance clients to Windows, Android and iOS.

**Architecture:** EasyPanel runs immutable backend images and private PostgreSQL with controlled migrations, health checks, encrypted off-host backups and rollback. GitHub Actions produces tested platform artifacts; store/private distribution is selected per ADR-007.

**Tech Stack:** Docker, EasyPanel, PostgreSQL version selected in ADR-002, Django/Gunicorn, chosen self-hosted/free observability stack, GitHub Actions, Flutter release tooling and platform signing.

## Global Constraints

- Never migrate the only copy of production data.
- A backup is not valid until restored in isolation.
- Do not print secrets in CI or documentation.
- Do not publish to a store before privacy/permission metadata is approved.

---

## Task 1: Document and baseline EasyPanel

**Files:** Create `docs/runbooks/easypanel-inventory.md`, `docs/adr/002-postgresql.md`; modify deployment manifests.

- [ ] Inventory domain, TLS, image, env names, volumes, network, restart and health without values.
- [ ] Pin PostgreSQL image/version and define ownership/backup.
- [ ] Create production-like staging and rollback procedure.

## Task 2: Rehearse SQLite to PostgreSQL migration

**Files:** Create management command under `core/management/commands/` if needed; add migration verification tests/runbook.

- [ ] Copy/anonymize a representative database.
- [ ] Write count, constraint, balance and checksum verification queries.
- [ ] Run forward import, application tests and rollback rehearsal.
- [ ] Record duration and downtime estimate.

## Task 3: Execute controlled production migration

- [ ] Announce local maintenance window to the household.
- [ ] Stop writes and create two verified backups.
- [ ] Migrate, run checks, counts and smoke tests.
- [ ] Switch clients only after validation.
- [ ] Roll back on any unexplained discrepancy.

## Task 4: Observability and backup

**Files:** Modify Django logging/settings/deploy; create `docs/runbooks/backup-restore.md`, `incident-*.md`.

- [ ] Add health/readiness, JSON logs and request/job IDs.
- [ ] Add metrics/alerts for service, DB, disk, imports, sync, TLS and backup age.
- [ ] Implement encrypted off-host backup with retention.
- [ ] Schedule isolated restore tests and record evidence.
- [ ] Verify logs/alerts contain no financial values or PII.

## Task 5: Release CI and signing

**Files:** Modify `.github/workflows/`; platform config under `mobile/`; create `docs/release/`.

- [ ] Approve ADR-007 and obtain required accounts/certificates.
- [ ] Separate development/staging/production app IDs and API URLs.
- [ ] Build signed Windows, Android and iOS artifacts from tagged commits.
- [ ] Protect signing secrets and require reviewed release environment.
- [ ] Generate SBOM/checksums and retain artifacts.

## Task 6: Device distribution and update

- [ ] Install on the actual Windows, iPhone and Android devices.
- [ ] Test first login, biometrics, file import, offline, update and rollback.
- [ ] Validate store/privacy/permission text where applicable.
- [ ] Write a non-technical install/recovery guide.

## Task 7: Optional provider pilot gate

- [ ] Confirm two-CPF/seven-connection contract and full monthly price.
- [ ] Run one-institution pilot through the same import pipeline.
- [ ] Measure field coverage, delay, duplicates and outages for the agreed period.
- [ ] Keep manual import available and document provider removal.

## Task 8: Final verification

- [ ] Run backend, Flutter, migration, restore and release smoke suites.
- [ ] Verify alerts by controlled failure tests.
- [ ] Confirm rollback artifacts and runbooks are accessible offline.
- [ ] Request security/operations review before declaring production ready.
