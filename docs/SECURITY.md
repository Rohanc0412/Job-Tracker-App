# Security

This is a local-only desktop application. No telemetry is collected and no data
is uploaded to remote services. Optional email syncing connects directly to
Gmail via IMAP to fetch messages in read-only mode.

## Local data stored
- SQLite database with applications, email event metadata, extracted statuses,
  interview events, and sync state (no tokens are stored in SQLite).
- UI preferences in `settings.json`.
- Raw email bodies stored locally (in SQLite for smaller messages or as
  compressed files for larger messages when enabled).
- Synthetic fixtures are optional and local-only.

Email evidence snippets are stored locally to support timelines and later
processing. No secrets or tokens are stored in the database.

## Storage locations
- Database:
  - Windows: `%APPDATA%\job_tracker\job_tracker.db`
  - macOS: `~/Library/Application Support/job_tracker/job_tracker.db`
- UI preferences:
  - Windows: `%APPDATA%\job_tracker\settings.json`
  - macOS: `~/Library/Application Support/job_tracker/settings.json`
- Raw bodies (when enabled):
  - Windows: `%APPDATA%\job_tracker\raw_bodies\`
  - macOS: `~/Library/Application Support/job_tracker/raw_bodies/`
- Secrets:
  - Stored in OS secure storage via `flutter_secure_storage`
    (Windows Credential Manager, macOS Keychain).

The app creates the application support directory with best-effort restrictive
permissions (e.g., 700 for directories and 600 for files on macOS/Linux).

## Wiping all local data
Option A (recommended):
1) Settings -> Security -> "Wipe Local Data".

Option B (manual):
1) Close the app.
2) Delete the database, settings file, and raw_bodies directory from the
   application support directory.
3) Remove secrets from OS secure storage (or uninstall the app).

## Email safety

### Gmail (IMAP)
The app syncs Gmail in read-only mode and never marks emails as read. It uses
IMAP BODY.PEEK and does not issue any flag-modifying commands.

### Data handling
- Email bodies are stripped of HTML tags for plain text snippets
- Raw bodies (when enabled): ≤512 KB stored inline, larger bodies compressed to local files (2 MB hard cap)
- Message IDs, subjects, senders, and dates stored for deduplication and timeline display
- No email content is sent to third-party services
