# Lar Finance Flutter Client Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the iOS, Android and Windows client with secure authentication, local-first reads, reliable synchronization and the daily financial journeys.

**Architecture:** A Flutter workspace consumes `/api/v1`, separates presentation/application/data layers by feature, stores a normalized local cache and transactional outbox in SQLite, and adapts navigation for mobile and Windows.

**Tech Stack:** Flutter/Dart versions pinned in Sprint 0, selected state/SQLite/network/secure-storage packages from ADR-003, native Keychain/Keystore/Credential Locker, Flutter test/integration_test.

## Global Constraints

- Do not start before API/auth/sync contract tests pass.
- Freeze ADR-008 before final visual components; use an engineering theme until then.
- No purple asset, token, chart series or generated illustration.
- First useful home render must be under 2 seconds from local data.
- Every repository mutation writes data and outbox atomically.

---

## Task 1: Scaffold the workspace and CI

**Files:** Create `mobile/pubspec.yaml`, `mobile/lib/`, `mobile/test/`, platform folders; modify `.github/workflows/ci.yml`.

- [ ] Pin Flutter/Dart and package versions in lockfile/ADR.
- [ ] Enable iOS, Android and Windows targets with the public name Lar Finance.
- [ ] Add format/analyze/test/build CI matrix.
- [ ] Add synthetic environment configuration without secrets in assets.

## Task 2: Implement local schema and repositories

**Files:** Create `mobile/lib/core/storage/`, `mobile/lib/features/*/data/`, migration tests.

- [ ] Write failing migration/round-trip tests for owner, account, category and transaction records.
- [ ] Implement SQLite schema, versioned migrations and repository interfaces.
- [ ] Preserve decimal strings, UTC timestamps, UUIDs, versions and tombstones.
- [ ] Test upgrade from every shipped local schema version.

## Task 3: Implement API client and secure session

**Files:** Create `mobile/lib/core/network/`, `mobile/lib/features/auth/`, platform configuration and tests.

- [ ] Write failing tests for login, refresh race, timeout, revoked device and logout.
- [ ] Implement safe API errors and certificate-valid HTTPS only.
- [ ] Store refresh material in platform secure storage, never SQLite/logs.
- [ ] Add biometric opt-in with password fallback and accessibility labels.

## Task 4: Implement outbox and delta sync

**Files:** Create `mobile/lib/core/sync/` and integration tests with a fake API.

- [ ] Write failing offline-create/reconnect/retry/conflict/tombstone tests.
- [ ] Implement atomic outbox, idempotent push and cursor pull.
- [ ] Add explicit conflict state for financial fields.
- [ ] Surface last-sync/stale/offline state to presentation.

## Task 5: Build adaptive shell and approved design tokens

**Files:** Create `mobile/lib/app/`, `mobile/lib/design_system/`, golden/accessibility tests.

- [ ] Complete the design gate and ADR-008 first.
- [ ] Implement light/dark tokens and no-purple automated token check.
- [ ] Implement bottom navigation for mobile and rail/sidebar for Windows.
- [ ] Add text scaling, reduced motion, focus traversal and keyboard shortcuts.

## Task 6: Build login and Home

**Files:** Create/modify `mobile/lib/features/auth/presentation/`, `home/`; add widget/golden tests.

- [ ] Test all login states including offline without prior session.
- [ ] Test Home with Lar/Eu/Esposa, unknown values and stale data.
- [ ] Implement source/freshness and hide-values behavior.
- [ ] Benchmark cold/warm render using a realistic local fixture.

## Task 7: Build transactions, detail and import flow

**Files:** Create `mobile/lib/features/transactions/`, `imports/`; add tests.

- [ ] Test pagination, filters, search, edits and conflicts.
- [ ] Build phone list and Windows adaptive view.
- [ ] Build file picker, mapping, preview, issue resolution and receipt states.
- [ ] Add share-sheet intake only where platform support is proven.

## Task 8: Build cards and statements

**Files:** Create `mobile/lib/features/cards/`; add widget/integration tests.

- [ ] Test unknown limit, open/closed/paid/overdue states and installments.
- [ ] Implement card and statement detail without treating payment as a second expense.
- [ ] Verify currency/text scaling and screen-reader output.

## Task 9: Platform verification

- [ ] Run analyze, unit, widget, golden and integration suites.
- [ ] Build debug/release candidates for all three platforms.
- [ ] Test Windows keyboard/mouse, Android back behavior and iOS safe areas.
- [ ] Test offline, token expiry, large text, reduced motion and app-switch privacy.
- [ ] Request design and code review before distribution.
