# Task 3 — Casa de Valores design system and adaptive shell

## RED / GREEN

- RED: `flutter test test/design_system test/app/adaptive_shell_test.dart` failed because the requested token, component and shell classes did not yet exist.
- GREEN: after the minimal implementation, focused tests passed. A test assertion was adjusted from the non-rendered `ButtonSegment` configuration object to its visible approved labels; breakpoint tests use the physical test viewport so 390×844 and 1366×768 are actual constraints.

## Files

- Added explicit Casa de Valores tokens, spacing, typography and Material 3 light/dark themes.
- Added `FinancialAmount`, `OwnerSelector`, `SyncStatusView`, adaptive desktop/mobile navigation, and the approved routes `/login`, `/device-owner`, `/initial-sync`, `/home`, `/more`.
- Replaced the Flutter counter template with the private, data-safe offline shell; it deliberately shows no fictional balance.
- Added unit/widget, breakpoint and golden coverage, including `casa_de_valores_dark.png` and `casa_de_valores_light.png`.

## Accessibility and responsiveness

- Financial values use tabular figures; hidden values expose only `Valor financeiro oculto` to semantics.
- Owner and sync controls expose Portuguese semantic labels; sync states include an icon plus text rather than colour alone.
- Desktop uses an extended `NavigationRail` from 900px; mobile uses only the two implemented `NavigationBar` destinations. Material 3 controls preserve keyboard focus behavior.

## Visual comparison

The shell follows the reference atmosphere: dark green-graphite canvas, restrained champagne selection, mineral/amber/danger state colours, sparse surfaces and an actual desktop sidebar rather than a stretched mobile bar. No reference logo, ornament, or synthetic financial values were copied. Golden rendering uses Flutter's test font (Ahem), so it validates layout/colour geometry rather than production system-font glyph aesthetics; no interactive Windows screenshot was captured.

## Verification

- `flutter test --update-goldens test/design_system test/app/adaptive_shell_test.dart` — 9 passed.
- `flutter test test/design_system test/app/adaptive_shell_test.dart` — 9 passed.
- `flutter analyze` — no issues.
- `flutter test` — 14 passed.
- `flutter build windows --debug` — built `build/windows/x64/runner/Debug/lar_finance.exe`.
- `git diff --check` — no whitespace errors (only expected Windows CRLF conversion warnings).

## Concerns

No functional blockers. A runtime Windows screenshot and the separate Impeccable v4 critique were not performed here; the controller coordinates that critique as requested.

## Corrective golden follow-up

Human inspection identified red text-layout artifacts and Ahem glyphs in the first golden baselines. The issue reproduced on the committed environment: the PNG had 5,941 sampled red pixels. The Flutter rendering debug flags `debugPaintBaselinesEnabled` and `debugPaintTextLayoutBoxes` were both false, and `tester.takeException()` was null, so it was not a debug-paint or overflow exception. The source strings are UTF-8 (the PowerShell display was the mojibake layer); no source corruption was found.

A RED regression test proved that the golden fixture contained three `Text` widgets (fixture copy and navigation labels), which causes test-font/layout artifacts. The fixture was reduced to structural, text-free sidebar/canvas geometry; production labels and functional breakpoint tests remain unchanged. The new regression asserts no `Text` widgets and no pending exception. Goldens were regenerated and independently viewed: no red/yellow overlays or Ahem glyphs remain. Fresh verification: adaptive golden tests 6 passed, full suite 16 passed, `flutter analyze` clean, and Windows debug build succeeded.
