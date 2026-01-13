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

    final upcoming = await repo.listUpcomingInterviews(days: 30);
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
        'messageId, subject, fromAddr, date, extractedStatus, extractedFieldsJson, '
        'hash, isSignificantUpdate) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
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
          'hash_dup',
          existing.isSignificantUpdate ? 1 : 0,
        ],
      ),
      throwsA(isA<SqliteException>()),
    );

    await database.close();
  }, skip: _sqliteSkipReason);

  test('upcoming interviews respect window and ordering', () async {
    final database = AppDatabase(database: sqlite3.openInMemory());
    await database.open();
    final now = DateTime(2026, 1, 10, 9);
    final repo = SqliteApplicationRepo(
      database,
      clock: () => now,
    );
    final db = database.rawDb;

    db.execute('DELETE FROM interview_events;');

    final appId = SeedData.applications.first.id;
    db.execute(
      'INSERT INTO interview_events (id, applicationId, accountLabel, messageId, '
      'startTime, endTime, timezone, location, meetingUrl, source, confidence, '
      'createdAt) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        'iv_1',
        appId,
        'Gmail',
        'msg-1',
        now.add(const Duration(days: 1)).toIso8601String(),
        null,
        'UTC',
        null,
        null,
        'Fixture',
        0.9,
        now.toIso8601String(),
      ],
    );
    db.execute(
      'INSERT INTO interview_events (id, applicationId, accountLabel, messageId, '
      'startTime, endTime, timezone, location, meetingUrl, source, confidence, '
      'createdAt) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        'iv_2',
        appId,
        'Gmail',
        'msg-2',
        now.add(const Duration(days: 10)).toIso8601String(),
        null,
        'UTC',
        null,
        null,
        'Fixture',
        0.9,
        now.toIso8601String(),
      ],
    );
    db.execute(
      'INSERT INTO interview_events (id, applicationId, accountLabel, messageId, '
      'startTime, endTime, timezone, location, meetingUrl, source, confidence, '
      'createdAt) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        'iv_3',
        appId,
        'Gmail',
        'msg-3',
        now.add(const Duration(days: 25)).toIso8601String(),
        null,
        'UTC',
        null,
        null,
        'Fixture',
        0.9,
        now.toIso8601String(),
      ],
    );

    final upcoming = await repo.listUpcomingInterviews(days: 14);
    expect(upcoming.length, 2);
    expect(upcoming.first.timestamp.isBefore(upcoming.last.timestamp), isTrue);
    expect(upcoming.first.timestamp, now.add(const Duration(days: 1)));
    expect(upcoming.last.timestamp, now.add(const Duration(days: 10)));

    await database.close();
  }, skip: _sqliteSkipReason);
}
