# Task 8 report — request IDs, safe JSON logs, OpenAPI and docs

## Status

Implemented on `codex/sprint-2-api-sync` from base `850e13c`.

## Delivered

- `X-Request-ID` accepts only values parseable as UUID, preserves a valid value,
  and generates a UUID v4 when absent or invalid.
- API access logging emits one JSON object to stdout with the exact event fields
  defined in the brief. The logger is `lar_finance.api`, uses a JSON formatter,
  and does not propagate.
- The event excludes query strings, bodies, headers, credentials, emails,
  descriptions, and financial values. `device_uuid` receives a value only for an
  authenticated device session.
- Middleware is directly after Django `SecurityMiddleware`.
- `docs/openapi-v1.yaml` is JSON syntax valid as YAML 1.2 and is loaded directly
  with `json.load` in contract tests. It documents all 16 current API routes,
  the required schemas, opaque bearer authentication without a JWT claim,
  reusable error responses, and `X-Request-ID` response headers.
- Architecture, security/operations, and roadmap documentation now distinguish
  delivered backend behavior from pending Flutter and EasyPanel work.
- The legacy wrong-password test still verifies an identical anti-enumeration
  error while allowing the required per-request correlation IDs to differ.

## TDD evidence

The initial focused run failed with five missing-log assertions and a missing
OpenAPI file. After the middleware and contract were implemented, the focused
privacy/contract suite passed. Auto-review added a failing contract test for the
undocumented `X-Request-ID` response header; after the contract update it passed.

## Verification evidence

- Focused privacy and contract tests: PASS.
- Full Django suite in the final working tree: 258 tests PASS in 125.177 seconds.
- Coverage: 98% overall (`5077` statements, `90` missed); `api/logging.py` 100%,
  `api/middleware.py` 98%, and both new test modules 100% at measurement time.
- `manage.py check --deploy --fail-level WARNING` with production-like secure
  environment variables: PASS, zero issues.
- Ruff full repository: PASS.
- `git diff --check`: PASS (Git only reports the repository's LF/CRLF conversion
  warning on tracked Windows files).

## Remaining operational limits

- Login/refresh throttles use the configured Django cache and are not shared
  across multiple processes without a shared cache backend.
- Log collection, retention, metrics, and alerting remain external operational
  work.
- Resource-list filters/pagination, a Flutter client, and a validated EasyPanel
  deployment are not part of this task and remain pending.
- Optimistic and idempotency conflicts are per-operation results inside HTTP 200
  sync batches; the reusable HTTP 409 response remains reserved for a future
  non-batch conflict endpoint.
