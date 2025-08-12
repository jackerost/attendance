

# Copilot Instructions for the Attendance Project

This project is a Flutter-based attendance management system using Firebase (Firestore, Auth) and NFC. Follow these guidelines for effective and consistent contributions:

## Architecture & Data Flow
- **Flutter App**: Main code in `lib/` (UI, models, services, widgets, utils, pages).
- **Firebase**: Firestore for all data (sessions, sections, users, attendance), Firebase Auth for authentication. No local DB or direct SQL.
- **Session & Section Management**: Sessions are tied to sections/courses. Each session has `lecturerEmail` (stores UID), `courseId`, `sectionId`, and time fields. Section CRUD and participant management are in `lib/pages/course_list_page.dart` and `lib/pages/session_manager_page.dart`. Only the section owner (by UID in `lecturerEmail`) can edit/delete custom sections or add participants.
- **Attendance**: Managed via `AttendanceService` (`lib/services/attendance_service.dart`). Handles entry/exit, duplicate checks, and special attendance. Attendance is always linked to session, student, course, and section IDs. Always check session status and enrollment before marking attendance.
- **NFC**: NFC logic is in `lib/services/nfc_service.dart`. Use `NFCService.scanAndFetchStudent` to scan a card and fetch student info by `tagId` from Firestore. Always call `FlutterNfcKit.finish()` after scanning.
- **Routing**: All navigation is via named routes in `main.dart` (`AppRoutes`). Pass session IDs and arguments explicitly. See `SelectionPage` and `HomePage` for navigation patterns.

## Developer Workflows
- **Build**: Use standard Flutter commands:
  - `flutter pub get` to install dependencies
  - `flutter run` to launch the app
  - `flutter build apk` or `flutter build ios` for production builds
- **Firebase Setup**: Requires valid `google-services.json` (Android) and iOS config in `ios/`.
- **Testing**: Tests are in `test/`. Run with `flutter test`.
- **Hot Reload/Restart**: Use Flutter's hot reload for UI changes.

## Project Conventions
- **Firestore Field Naming**: `lecturerEmail` always stores the lecturer's UID (not email). Do not change this for compatibility.
- **Session/Section CRUD**: All creation, editing, and deletion must check that the current user matches `lecturerEmail` and, for deletion, that the section is custom (`sectionType`).
- **Participant Management**: Only the section owner can add/remove participants to custom sections. See `_addParticipantsToSection` in `course_list_page.dart`.
- **Attendance Logic**: Use `AttendanceService.markAttendance` for all attendance actions. Use `AttendanceScanType` for entry/exit. Always check session status and enrollment.
- **NFC Scanning**: Use `NFCService.scanAndFetchStudent` and handle null for failed scans. Always finish NFC session with `FlutterNfcKit.finish()`.
- **UI Patterns**: Use `AlertDialog` for CRUD popups, `SnackBar` for feedback. See `session_manager_page.dart`, `selection_page.dart`, and `course_list_page.dart` for examples.
- **Date/Time Handling**: Store times as Firestore `Timestamp`. Display using `intl` package formatting.
- **Error Handling**: Show user-facing errors with `SnackBar`. Log Firebase errors to console (see `logger` usage in services).
- **Widget Structure**: Use helper methods for repeated UI (e.g., `_buildDetailRow`, `_buildSelectionButton`, `ScannedStudentList`).

## Key Files & Directories
- `lib/pages/session_manager_page.dart`: Session CRUD, section checks, UI patterns.
- `lib/pages/course_list_page.dart`: Section CRUD, participant management, and ownership checks.
- `lib/services/attendance_service.dart`: Attendance logic, session/entry/exit checks.
- `lib/services/nfc_service.dart`: NFC scan and student lookup.
- `lib/pages/selection_page.dart`: Mode selection UI and navigation.
- `lib/pages/home_page.dart`: Dashboard, session status, and navigation to attendance/manager.
- `lib/widgets/scanned_student_list.dart`: UI for displaying scanned students.
- `lib/main.dart`: App entry, routing, and provider setup.
- `lib/models/`, `lib/services/`, `lib/utils/`, `lib/widgets/`: Organize code by responsibility.
- `pubspec.yaml`: Declares dependencies (Flutter, Firebase, intl, logger, etc.).
- `android/`, `ios/`, `web/`, `linux/`, `macos/`, `windows/`: Platform-specific configs.

## Integration Points
- **Firebase**: All data and auth flows go through Firestore and Firebase Auth. No direct SQL or local DB.
- **NFC**: Integrated for attendance via `flutter_nfc_kit` and Firestore lookup.
- **Provider**: Used for authentication service injection (`FirebaseAuthService`).

## Examples & Patterns
- To add a session: use `_showAddSessionDialog` and `_createSession` in `session_manager_page.dart`.
- To add participants: use `_showAddParticipantsDialog` and `_addParticipantsToSection` in `course_list_page.dart`.
- To mark attendance: use `AttendanceService.markAttendance` with all required IDs and scan type.
- To scan NFC: use `NFCService.scanAndFetchStudent` and handle null for failed scans.
- To check section type: use `_checkSectionType` (Firestore lookup).
- To enforce permissions: always compare `lecturerEmail` (UID) to current user's UID.
- For navigation: use named routes in `main.dart` and pass arguments explicitly (see `SelectionPage`, `HomePage`).

---
If you are unsure about a workflow or pattern, check the referenced files for canonical approaches, or ask for clarification.
