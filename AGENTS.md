# Repository Guidelines

## Project Structure & Module Organization
- Source in `lib/` (Flutter/Dart). Prefer feature folders: `lib/screens/`, `lib/widgets/`, `lib/services/`.
- Tests in `test/`, mirroring `lib/` paths; files end with `_test.dart`.
- Assets in `assets/` and declared in `pubspec.yaml` under `flutter.assets`.
- Platform configs live in `android/`, `ios/`, `macos/`, `linux/`, `windows/`, `web/`.
- Config: `pubspec.yaml` (deps, assets), `analysis_options.yaml` (lints).

## Build, Test, and Development Commands
- Install deps: `flutter pub get`.
- Analyze code: `flutter analyze` (uses repo lints).
- Format code: `dart format .` (formats the entire repo).
- Run app: `flutter run -d chrome` (or a device ID).
- Run tests: `flutter test`; coverage: `flutter test --coverage` → `coverage/lcov.info`.
- Builds: `flutter build apk`, `flutter build ios`, `flutter build web`.

## Coding Style & Naming Conventions
- Indentation: 2 spaces; no tabs.
- Naming: lowerCamelCase (vars/functions), UpperCamelCase (classes), snake_case filenames (e.g., `student_card.dart`).
- Imports: group `dart:`, `package:`, then relative; prefer relative within a feature.
- Respect `analysis_options.yaml`; disable lints only with clear justification.

## Testing Guidelines
- Use `flutter_test` with `test` and `testWidgets`.
- Mirror `lib/` structure in `test/`; name files `*_test.dart`.
- Cover core logic and widget behavior; use golden tests for stable UI when useful.

## Commit & Pull Request Guidelines
- Commits: short, present-tense summaries (often French). Conventional Commits allowed (e.g., `feat(auth): ...`).
- PRs: include description, rationale, screenshots for UI, steps to test, and link issues (e.g., `Closes #123`). Keep focused and small.

## Security & Configuration Tips
- Pass secrets via `--dart-define=KEY=VALUE`; never commit secrets.
- Declare permissions in `AndroidManifest.xml`/`Info.plist` as needed.
- Do not commit generated/local data (e.g., `*.db`); include only required assets.

## Agent Notes
- Follow this file’s guidance; mirror structure and style.
- Prefer minimal, targeted changes; update docs/tests when behavior changes.

