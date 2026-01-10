import 'package:flutter_test/flutter_test.dart';
import 'package:job_tracker/data/db/db.dart';
import 'package:job_tracker/data/repo/sqlite_application_repo.dart';
import 'package:job_tracker/data/seed/seed_data.dart';
import 'package:sqlite3/sqlite3.dart';

import '../support/sqlite_test_utils.dart';

final String? _sqliteSkipReason = configureSqliteForTests();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('schema creation and seed logic', () async {
    final database = AppDatabase(database: sqlite3.openInMemory());
    await database.open();

    final raw = database.rawDb;
    const tables = [
      'accounts',
      'applications',
      'email_events',
      'interview_events',
      'sync_state',
    ];

    for (final table in tables) {
      final result = raw.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name = ?;",
        [table],
      );
      expect(result, isNotEmpty, reason: 'Missing table: $table');
    }

    final countResult =
        raw.select('SELECT COUNT(*) AS count FROM applications;');
    final count = (countResult.first['count'] as num).toInt();
    expect(count, SeedData.applications.length);

    await database.open();
    final countResultAgain =
        raw.select('SELECT COUNT(*) AS count FROM applications;');
    final countAgain = (countResultAgain.first['count'] as num).toInt();
    expect(countAgain, SeedData.applications.length);

    await database.close();
  }, skip: _sqliteSkipReason);

  test('repository queries return expected rows', () async {
    final database = AppDatabase(database: sqlite3.openInMemory());
    await database.open();
    final repo = SqliteApplicationRepo(
      database,
      clock: () => DateTime(2026, 1, 1),
    );

    final apps = await repo.listApplications();
    expect(apps.length, SeedData.applications.length);

    final updates = await repo.listRecentUpdates();
    expect(updates, isNotEmpty);

    final upcoming = await repo.listUpcomingInterviews();
    expect(upcoming, isNotEmpty);

    final timeline = await repo.listTimeline('app_002');
    expect(timeline, isNotEmpty);

    await database.close();
  }, skip: _sqliteSkipReason);

  test('email event idempotency constraint rejects duplicates', () async {
    final database = AppDatabase(database: sqlite3.openInMemory());
    await database.open();
    final raw = database.rawDb;

    final existing = SeedData.emailEvents.first;
    expect(
      () => raw.execute(
        'INSERT INTO email_events (id, applicationId, accountLabel, provider, folder, cursorValue, '
        'messageId, subject, fromAddr, date, extractedStatus, extractedFieldsJson, evidenceSnippet, '
        'hash, isSignificantUpdate) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
        [
          'dup_001',
          existing.applicationId,
          existing.accountLabel,
          existing.provider,
          existing.folder,
          existing.cursorValue,
          existing.messageId,
          existing.subject,
          existing.fromAddr,
          existing.date.toIso8601String(),
          existing.extractedStatus,
          existing.extractedFieldsJson,
          existing.evidenceSnippet,
          'hash_dup',
          existing.isSignificantUpdate ? 1 : 0,
        ],
      ),
      throwsA(isA<SqliteException>()),
    );

    await database.close();
  }, skip: _sqliteSkipReason);
}
