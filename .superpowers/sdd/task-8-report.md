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

## Final observability contract closure

- The OpenAPI gate now derives every path, implemented HTTP handler, and public
  versus opaque-bearer policy from Django resolver callbacks and DRF view class
  configuration. It no longer maintains a second route/auth contract in tests.
- `django.server` uses a null handler with propagation disabled, so a realistic
  server record cannot render a raw API request target in stdout or stderr.
- The outer request-ID middleware converts non-contract API 5xx responses from
  downstream middleware/rendering into the stable `internal_error` envelope,
  preserving the request ID and reporting the matching access error code.
- Internal failures emit one separate safe diagnostic JSON event per request.
  Its fingerprint is derived only from the qualified exception type and safe
  structural code location; messages, arguments, request data, financial values,
  and traceback text are never serialized.

TDD reproduced the four findings before implementation: parallel
`django.server` output, HTML downstream 500, absent diagnostics, and duplicated
OpenAPI expectations. The final focused observability/error/OpenAPI run is 24
tests PASS. The final full suite is 270 tests PASS in 122.667 seconds with 97%
coverage (`5423` statements, `166` missed); the focused changed modules and tests
are 98% combined. Production deploy checks, repository Ruff, and diff checks all
pass. Auto-review also made downstream fallback access events report
`internal_error` instead of a null error code.

## Device-authentication contract binding

The runtime OpenAPI gate now resolves each view's explicit authentication and
permission overrides through its class hierarchy, falling back to DRF's
`DEFAULT_AUTHENTICATION_CLASSES` and `DEFAULT_PERMISSION_CLASSES`. Public
operations must have no authentication classes and exactly `AllowAny`; every
private operation must use only `DeviceTokenAuthentication` before it can map to
the documented `opaqueBearer` scheme. A resolver-callback regression replaces a
private view's authentication with `SessionAuthentication` and proves the gate
rejects it.

TDD evidence: the new regression failed because the previous helper assumed any
non-public view was opaque bearer, then passed after effective authentication
validation was added. Final focused OpenAPI/observability/error suite: 25 PASS.
Final full suite: 271 PASS in 111.180 seconds. Repository Ruff and diff checks:
PASS.

## Private-permission contract binding

The runtime OpenAPI gate now maps a private operation to `opaqueBearer` only
when its effective permission configuration exactly matches a known
login-enforcing policy used by the API: `IsAuthenticated` or
`IsDeviceSession`. Empty permission lists, `AllowAny`, permissive custom
permissions, and unknown permission compositions are rejected. Public operations
remain exactly no authentication classes plus `AllowAny`; inherited DRF defaults
remain the fallback when a view has no override.

TDD evidence: regressions for empty permissions and `AllowAny` failed against the
previous partial check, then passed with exact private-permission validation. The
existing `SessionAuthentication` regression remains green. Final focused
OpenAPI/observability/error suite: 27 PASS. Final full suite: 273 PASS in 128.179
seconds. Repository Ruff and diff checks: PASS.
