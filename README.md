# Job Tracker

Local-only Flutter desktop app for tracking job applications.

## Status
Part 1 UI implemented.

## Prerequisites
- Flutter SDK 3.3+ (with desktop support enabled)
- Windows: Visual Studio with "Desktop development with C++"
- macOS: Xcode + Command Line Tools

## Run
1) Fetch dependencies:
   - `flutter pub get`

2) Windows:
   - `flutter run -d windows`

3) macOS:
   - `flutter run -d macos`

## Local data storage
The app will store local data in the OS application support directory:
- Windows: `%APPDATA%\job_tracker`
- macOS: `~/Library/Application Support/job_tracker`

## Screenshots
- Dashboard (placeholder): `docs/screenshots/dashboard.png`

## App icon placeholder pipeline
A placeholder icon is configured in `assets/icons/app_icon.png`.
To generate desktop icons later:
- `flutter pub run flutter_launcher_icons`

## Security
See `docs/SECURITY.md` for the local-only security posture.
