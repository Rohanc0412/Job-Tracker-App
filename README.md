# Job Tracker

Local-only Flutter desktop app for tracking job applications.

## Status
Gmail sync implemented via IMAP.

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
The app stores a local SQLite database in the OS application support directory:
- Windows: `%APPDATA%\job_tracker\job_tracker.db`
- macOS: `~/Library/Application Support/job_tracker/job_tracker.db`

UI preferences are stored alongside the database:
- Windows: `%APPDATA%\job_tracker\settings.json`
- macOS: `~/Library/Application Support/job_tracker/settings.json`

Raw email bodies (when enabled) are stored under:
- Windows: `%APPDATA%\job_tracker\raw_bodies\`
- macOS: `~/Library/Application Support/job_tracker/raw_bodies/`

Secrets (tokens/app passwords) are stored in OS secure storage via
`flutter_secure_storage` (Windows Credential Manager, macOS Keychain).

Email bodies are stored locally in SQLite (and optionally as compressed files for
larger messages when raw body storage is enabled).

## Reset local data
Option A (recommended):
1) Settings -> Security -> "Wipe Local Data".

Option B (manual):
1) Close the app.
2) Delete the `job_tracker.db` file from the app support directory.
3) Delete the `raw_bodies/` directory if present.

Note: If you notice duplicate email content across different applications after
a Gmail sync, this indicates emails were incorrectly matched during dedup. Reset
local data and re-sync to fix.

## Test fixtures
Synthetic `.eml` fixtures are included under `assets/eml_fixtures/` to validate
parsing and status detection without using real email data.

To load fixtures:
1) Open Settings -> Testing.
2) Enable Test Mode.
3) (Optional) Clear fixture data before loading.
4) Click "Load Fixtures" to insert fixture emails and refresh the dashboard.

## Status engine and dedup
- Status engine: keyword-based classification (received, assessment, interview,
  offer, rejected) with confidence scores; monotonic transitions prevent
  regressions unless strong evidence is detected.
- Dedup strategy: match by job ID first, then portal URL, then company/role
  similarity using Jaccard token overlap. Requires 85% similarity threshold and
  minimum 3-character company/role names to prevent false matches on generic
  senders (e.g., promotional emails).

## Interview extraction
- ICS invites are preferred and parsed for DTSTART, DTEND, LOCATION, URL, and TZID
  when available; these are stored with high confidence.
- Text fallback looks for common patterns like `Jan 13 at 2:00 PM ET` and stores
  medium confidence; timezone may be unknown outside common US abbreviations.
- Only the earliest matching interview time in an email is stored.

Verification steps:
1) Load fixtures (Settings -> Testing -> Load Fixtures).
2) Open Dashboard -> Activity -> Upcoming Interviews and confirm dates/times.
3) Click an interview to focus the application and check the details timeline.

## Gmail sync (IMAP, read-only)
1) Open Settings -> Gmail.
2) Enter your Gmail address and app password.
3) Pick a start date for the initial sync.
4) Choose a folder (currently INBOX).
5) Toggle "Store raw email body locally" if you want full bodies saved.
6) Click "Save".
7) On the Dashboard, click "Sync Gmail".

Notes:
- The first sync requires a start date; later syncs use the saved cursor.
- Sync is incremental (UIDVALIDITY + last UID).
- Fetch uses BODY.PEEK and never marks messages as read.
- Raw bodies are stored locally under the app support directory in `raw_bodies/`
  when enabled (large bodies are compressed).

## Tests
- `flutter test`

## Screenshots
- Dashboard (placeholder): `docs/screenshots/dashboard.png`

## App icon placeholder pipeline
A placeholder icon is configured in `assets/icons/app_icon.png`.
To generate desktop icons later:
- `flutter pub run flutter_launcher_icons`

## Security
See `docs/SECURITY.md` for the local-only security posture.
