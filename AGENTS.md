# Repository Guidelines

## Project Structure & Module Organization
- Source: `lib/` (Flutter/Dart app code). Prefer feature folders (e.g., `lib/screens/`, `lib/widgets/`, `lib/services/`).
- Tests: `test/` with `*_test.dart` files mirroring `lib/` paths.
- Assets: `assets/` referenced in `pubspec.yaml` under `flutter.assets`.
- Platform: `android/`, `ios/`, `macos/`, `linux/`, `windows/`, `web/` for platform-specific config.
- Config: `pubspec.yaml` (deps, assets), `analysis_options.yaml` (lints).

## Build, Test, and Development Commands
- Install deps: `flutter pub get`
- Analyze: `flutter analyze` — static checks using repo lints.
- Format: `dart format .` — applies standard Dart formatting.
- Run app: `flutter run -d chrome` or target device ID.
- Tests: `flutter test` — runs unit/widget tests in `test/`.
- Coverage: `flutter test --coverage` → `coverage/lcov.info`.
- Builds: `flutter build apk` (Android), `flutter build ios` (iOS), `flutter build web`.

## Coding Style & Naming Conventions
- Indentation: 2 spaces; no tabs.
- Dart style: lowerCamelCase for vars/functions, UpperCamelCase for classes, snake_case for filenames (e.g., `student_card.dart`).
- Imports: prefer relative within feature; group `dart:`, `package:`, local.
- Linting: respect rules in `analysis_options.yaml`; fix or justify with comments sparingly.

## Testing Guidelines
- Framework: `flutter_test` with `testWidgets` and `test`.
- Structure: mirror `lib/` and name tests `*_test.dart` (e.g., `lib/services/auth_service.dart` → `test/services/auth_service_test.dart`).
- Expectations: cover core logic and widget behavior; use golden tests for stable UI when applicable.
- Run locally and ensure `flutter analyze` passes before pushing.

## Commit & Pull Request Guidelines
- Commits (current history): short, present-tense summaries (often French). Keep concise and scoped (e.g., "amélioration des modèles").
- Recommended style: optionally adopt Conventional Commits (`feat:`, `fix:`, `chore:`) with optional scope (e.g., `feat(auth): add 2FA`).
- PRs: include description, rationale, screenshots for UI, steps to test, and reference issues (e.g., `Closes #123`). Keep PRs small and focused.

## Security & Configuration Tips
- Secrets: pass at runtime via `--dart-define=KEY=VALUE`; do not commit secrets.
- Android/iOS permissions: declare in `AndroidManifest.xml`/`Info.plist` as needed.
- Assets/db: do not commit generated or local data (e.g., `*.db`) unless intended.

