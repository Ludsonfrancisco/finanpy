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
- An outer correlation middleware guarantees the same UUID response header even
  when `SecurityMiddleware` returns an HTTPS redirect before access logging.
- Device authentication fields are derived only from a real `DeviceSession` in
  `request.auth`; Django web sessions cannot populate them.
- Django framework loggers use a separate safe JSON formatter that preserves
  severity, logger, status, and correlation evidence without rendering request
  targets, messages, arguments, headers, or exception text.
- Unhandled DRF exceptions return a private HTTP 500 `ErrorEnvelope` with stable
  code `internal_error` and are represented by one safe API access event.
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

The hardening review was also performed test-first. The initial focused run
reproduced a missing request ID on HTTPS redirects, cookie-based false device
authentication, an HTML 500 response, unsafe default Django formatting, and
implicit rather than operation-level OpenAPI security. Each focused test was
observed failing before the corresponding minimal change.

## Verification evidence

- Focused observability, error, and OpenAPI tests: 21 PASS.
- Full Django suite in the hardened working tree: 267 tests PASS in 113.522 seconds.
- Coverage: 98% overall (`5225` statements, `88` missed). The changed runtime
  modules `api/exceptions.py`, `api/logging.py`, and `api/middleware.py`, plus all
  three focused test modules, each report 100% coverage.
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
