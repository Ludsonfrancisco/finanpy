# Lar Finance Imports and Cards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver idempotent OFX/CSV imports, reconciliation, and a correct credit-card/fatura domain on top of the foundation API.

**Architecture:** Add versioned source adapters that parse into immutable import batches, preview before an atomic ledger commit, and keep cards/statements separate from cash accounts. All inputs converge through one normalization and reconciliation pipeline.

**Tech Stack:** Python 3.12, Django 5.2.13, PostgreSQL/SQLite-compatible ORM, selected API stack from ADR-001, Django TestCase, anonymized financial fixtures.

## Global Constraints

- Start only after the foundation plan and household/owner backfill pass.
- Never use real credentials or unredacted files as fixtures.
- Missing fields remain unknown; do not substitute zero.
- Reimporting the same source must be idempotent.
- A card purchase must not reduce cash until statement payment.

---

## Task 1: Create import batch persistence

**Files:** Create `imports/models.py`, `imports/tests/test_models.py`, `imports/migrations/0001_initial.py`; modify `core/settings.py`.

- [ ] Write failing tests for batch state transitions, file hash uniqueness scope and immutable records.
- [ ] Implement `ImportBatch`, `ImportRecord`, `SourceReference` and `ReconciliationIssue`.
- [ ] Add safe admin views that omit raw payload by default.
- [ ] Run focused/full tests and inspect migrations.

## Task 2: Build the adapter contract and OFX parser

**Files:** Create `imports/adapters/base.py`, `imports/adapters/ofx.py`, `imports/tests/fixtures/ofx/`, `imports/tests/test_ofx.py`.

- [ ] Add anonymized fixtures for debit, credit, fee, transfer, accents and malformed dates.
- [ ] Write failing detection/parsing/normalization tests.
- [ ] Implement pure parsing without database writes.
- [ ] Add deterministic fingerprints and encoding/error diagnostics.
- [ ] Run mutation/reimport-focused tests.

## Task 3: Build versioned CSV profiles

**Files:** Create `imports/adapters/csv_base.py`, `imports/profiles/`, `imports/tests/fixtures/csv/`, `imports/tests/test_csv_profiles.py`.

- [ ] Obtain approved anonymized samples and record coverage in `docs/imports-and-sync.md`.
- [ ] Write failing tests for header detection, decimal sign, date and column mapping.
- [ ] Implement a profile registry with explicit versions.
- [ ] Implement the first institution/product profile only after fixture evidence.
- [ ] Verify unknown layouts fail safely with mapping guidance.

## Task 4: Preview, deduplicate and commit

**Files:** Create `imports/services/preview.py`, `fingerprint.py`, `commit.py`; create `imports/api/`; update OpenAPI.

- [ ] Write failing tests proving preview never changes the ledger.
- [ ] Write failing tests for same-file and cross-file duplicate candidates.
- [ ] Implement confidence-ranked matching; low confidence becomes an issue.
- [ ] Implement atomic commit and cancellation.
- [ ] Add API upload/status/preview/commit endpoints and safe limits.
- [ ] Simulate timeout/retry and prove no duplication.

## Task 5: Introduce the card domain

**Files:** Create `cards/models.py`, `cards/services.py`, `cards/tests/`, `cards/migrations/0001_initial.py`; modify settings/API.

- [ ] Write failing tests for card, statement cycle, reported/calculated totals and unknown limit.
- [ ] Implement `CreditCard`, `CardStatement`, `CardTransaction`, `StatementPayment`.
- [ ] Add owner/household constraints and signed decimal rules.
- [ ] Add API endpoints and OpenAPI schemas.
- [ ] Run query-count and full-suite checks.

## Task 6: Migrate legacy credit accounts

**Files:** Create data migrations under `cards/migrations/`; add migration tests.

- [ ] Write a migration test with unambiguous and ambiguous legacy `Account.CREDIT` rows.
- [ ] Generate a dry-run report instead of guessing institution/owner/card details.
- [ ] Migrate safe fields and preserve the legacy reference.
- [ ] Rehearse forward/backward migrations on a database copy.

## Task 7: Model installments and statement payment

**Files:** Modify `cards/models.py`, `cards/services.py`, tests and migrations; modify ledger reporting services.

- [ ] Write failing tests for installment totals/rounding, refunds, partial payment and overpayment credit.
- [ ] Implement purchase-root/installment links.
- [ ] Implement cash transaction to statement-payment reconciliation.
- [ ] Prove reports count expense once and cash movement separately.

## Task 8: Verify and hand off

- [ ] Run Ruff, checks, migrations, full tests and coverage.
- [ ] Import every approved fixture twice and compare entity counts.
- [ ] Inspect logs for leaked descriptions/values.
- [ ] Update coverage matrix and Sprint 3–4 evidence.
- [ ] Request code review before merge.
