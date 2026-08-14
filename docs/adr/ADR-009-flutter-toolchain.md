# ADR-009: Flutter client toolchain

- Status: Accepted
- Date: 2026-08-14

## Context

Lar Finance needs a reproducible Flutter foundation for Android, iOS, and Windows while preserving the existing Django backend. The client consumes the API under `/api/v1` and must use the approved dependency versions without floating direct constraints.

## Decision

Use the Flutter stable toolchain below:

- Flutter 3.47.0, framework revision `4cf24164269a5ebf0c16a028a00727d0e77bbb05`
- Dart 3.13.0
- DevTools 2.60.0
- Android Studio Quail 3 2026.1.3, build `AI-261.26222.65.2613.15948027`
- OpenJDK 25.0.2, build `25.0.2+-15348964-b329.117`, from the Android Studio JBR
- Android SDK Platform 36 revision 2 and Android SDK Build Tools 36.0.0
- Android SDK Platform Tools 37.0.1 and Command-line Tools 22.0
- Android NDK 28.2.13676358 and Android CMake 3.22.1, installed on demand by the first APK build
- Gradle 9.3.1 through the generated Gradle wrapper
- Visual Studio Build Tools 2022 17.14.37, product version 17.14.37516.0
- MSBuild 17.14.51.32402
- CMake 3.31.6-msvc6
- Windows SDK 10.0.26100.0

The Flutter SDK archive comes from the official Flutter release service:

- Manifest: `https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json`
- Archive: `https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.47.0-stable.zip`
- SHA-256: `9f96d393cdfad05bea0b4b42c603ffda027af11adadc8e4cf3ac87e49110c1ca`

Android Studio and Visual Studio Build Tools are installed from the Windows Package Manager `winget` source with package IDs `Google.AndroidStudio` and `Microsoft.VisualStudio.2022.BuildTools`. The Visual Studio installation includes `Microsoft.VisualStudio.Workload.VCTools`, its recommended components, `Microsoft.VisualStudio.Component.Windows11SDK.26100`, and the optional `Microsoft.VisualStudio.Component.VC.ATL` required by flutter_secure_storage_windows. Android Command-line Tools 22.0 come from the official Google archive `https://dl.google.com/android/repository/commandlinetools-win-15859902_latest.zip`, verified with SHA-256 `90ae805d20434428bffcb699c290860f19bb5f66a67e6b330067e3de801fb04a`.

Create only the `android`, `ios`, and `windows` platform directories. Web, Linux, and macOS are outside this foundation.

Pin these direct packages exactly:

- Runtime: dio 5.11.0, drift 2.34.3, drift_flutter 0.3.1, flutter_riverpod 3.4.2, flutter_secure_storage 10.3.1, go_router 17.3.0, and intl 0.20.3
- Development: build_runner 2.15.3, drift_dev 2.34.5, and flutter_lints 6.0.0
- SDK packages: flutter, flutter_localizations, flutter_test, and integration_test

The Dart SDK constraint is `>=3.10.0 <4.0.0`. Commit `pubspec.lock` and `tool/flutter-version.json`; CI reads `frameworkVersion` from that JSON instead of duplicating the Flutter version.

`AppConfig` defaults to `https://financeiro.palmbook.online/api/v1`, removes one trailing slash for requests, and requires HTTPS outside `localhost` and `127.0.0.1`.

## Supported targets and limitation

- Android: scaffolded, analyzed, tested, and built as a debug APK on Windows.
- Windows: scaffolded, analyzed, tested, and built as a debug application on Windows.
- iOS: scaffolded and tracked, but an iOS build requires macOS with Xcode and cannot be executed or claimed on Windows.

## Consequences

The repository gains a larger lockfile and platform-specific generated files, while build outputs, Dart tool state, and coverage remain ignored. Direct dependency upgrades and Flutter upgrades require an explicit decision that updates the pins, lockfile, and tool version JSON together.
