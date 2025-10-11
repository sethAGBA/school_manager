# Gemini Code Assistant Context

## Project Overview

This is a Flutter application designed to automatically generate school timetables. The core of the project is a sophisticated algorithm that places classes, teachers, and subjects into a weekly schedule while respecting a variety of constraints.

The application is structured as follows:

- **Main UI (`lib/main.dart`):** A simple interface to trigger the generation process and visualize the resulting timetable. It includes a basic dashboard showing the number of classes, teachers, subjects, and rooms.
- **Timetable Generation Service (`lib/services/timetable_generator.dart`):** This is the heart of the application. It contains the logic for the timetable generation algorithm, which appears to be a heuristic-based approach that prioritizes and places courses based on a scoring system. It handles constraints such as teacher availability, room capacity, subject difficulty, and avoiding gaps in the schedule.
- **Data Models (`lib/models/models.dart` and `lib/services/timetable_generator.dart`):** The application's data structures, including `Classe`, `Professeur`, `Matiere`, `Salle`, and `EmploiDuTemps` (Timetable). Note that some models are currently defined in the generator service file and should be moved to the dedicated models file.
- **Dependencies:** The project uses `hive_flutter` for local data storage, `pdf` for exporting timetables to PDF, and `share_plus` for sharing functionality.

## Building and Running

This is a standard Flutter project. To run the application, use the following commands:

```bash
# Install dependencies
flutter pub get

# Run the app (select a device)
flutter run
```

To build the application for a specific platform, use the standard `flutter build` commands (e.g., `flutter build apk`, `flutter build ios`).

## Development Conventions

- **Code Style:** The project follows the standard Dart and Flutter linting rules defined in `analysis_options.yaml` (`package:flutter_lints`). All new code should adhere to these conventions.
- **Testing:** There is a basic widget test in `test/widget_test.dart`. More comprehensive unit and integration tests should be added, especially for the timetable generation logic.
- **State Management:** The current state management is done via `StatefulWidget` and `setState`. For more complex features, a more robust state management solution like Provider or Riverpod might be considered.
- **Model Organization:** The data models should be consolidated in the `lib/models/` directory for better organization. Currently, some models are defined within the `timetable_generator.dart` service.
- **Error Handling:** The generation process includes basic error handling with `try-catch` blocks and displays messages to the user via `SnackBar`. This should be maintained and improved as new features are added.
