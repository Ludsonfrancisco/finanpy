# Task 3 — Casa de Valores design system and adaptive shell

## Commit chain

- `b19adae` — initial design-system and adaptive-shell foundation.
- `c44b8b7` — clean golden baselines.
- `b7b3335` — system theme, accessibility, contrast, scrolling, and representative structural golden corrections.

## Delivered

- Explicit Material 3 Casa de Valores light/dark tokens; `ThemeMode.system` follows platform preference.
- Adaptive rail (desktop) and bottom navigation (mobile), only with implemented destinations.
- Private, data-safe Home shell with `SingleChildScrollView`; financial amount hiding and tabular figures; owner selection; sync-state semantics including freshness.
- Dark error/on-error pair corrected for AA contrast.
- Desktop Home/shell golden fixture now contains rail, navigation/status icons, and structural content shapes without test-font artifacts. Labels remain tested in real widgets.

## TDD, accessibility, and visual evidence

- RED recorded for missing Task 3 APIs; green widget coverage for tokens, amount privacy, owner labels, sync state, and 390×844/1366×768 shell breakpoints.
- Golden-artifact regression proved the first fixture contained three text widgets; it now asserts no text/Ahem artifacts, required icon geometry, clean debug flags, and no pending exception.
- Both regenerated dark and light PNGs were independently inspected: no red/yellow overlays or Ahem glyphs.
- Dual independent Impeccable v4 verdicts are ready.

## Fresh verification

- `flutter test --update-goldens test/app/adaptive_shell_test.dart` — 6 passed.
- `flutter test test/app/adaptive_shell_test.dart` — 6 passed.
- `dart format --set-exit-if-changed lib test` — clean.
- `flutter analyze` — no issues.
- `flutter test` — 17 passed.
- `flutter build windows --debug` — succeeded.

## Residual P2 / next task

Task 4 should broaden automated text-scale, keyboard-focus and owner-selector interaction coverage. Cupertino-specific platform adaptation remains a next-task concern; Task 3 intentionally provides the shared Material adaptive foundation. Strings should move to the localization layer when it is introduced.
