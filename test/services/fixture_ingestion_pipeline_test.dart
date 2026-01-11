import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:job_tracker/data/db/db.dart';
import 'package:job_tracker/services/fixture_ingestion_pipeline.dart';
import 'package:sqlite3/sqlite3.dart';

import '../support/sqlite_test_utils.dart';

final String? _sqliteSkipReason = configureSqliteForTests();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('dedup merges fixture emails by job id', () async {
    final database = AppDatabase(database: sqlite3.openInMemory());
    await database.open();
    final db = database.rawDb;

    db.execute('DELETE FROM email_events;');
    db.execute('DELETE FROM interview_events;');
    db.execute('DELETE FROM applications;');
    db.execute('DELETE FROM accounts;');
    db.execute('DELETE FROM sync_state;');

    db.execute(
      'INSERT INTO applications (id, company, role, jobId, portalUrl, firstSeen, '
      'lastSeen, currentStatus, confidence, accountLabel, sourceLabel, contact, '
      'nextStep, nextStepAt) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        'fx_app_dup_1',
        'Blue Finch Software',
        'Backend Engineer',
        'BE-4471',
        'https://jobs.bluefinch.io/positions/BE-4471',
        DateTime(2026, 1, 1).toIso8601String(),
        DateTime(2026, 1, 1).toIso8601String(),
        'received',
        70.0,
        'Gmail',
        'Fixture',
        null,
        null,
        null,
      ],
    );
    db.execute(
      'INSERT INTO applications (id, company, role, jobId, portalUrl, firstSeen, '
      'lastSeen, currentStatus, confidence, accountLabel, sourceLabel, contact, '
      'nextStep, nextStepAt) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        'fx_app_dup_2',
        'Blue Finch Software',
        'Backend Engineer',
        null,
        null,
        DateTime(2026, 1, 2).toIso8601String(),
        DateTime(2026, 1, 2).toIso8601String(),
        'applied',
        40.0,
        'Gmail',
        'Fixture',
        null,
        null,
        null,
      ],
    );

    db.execute(
      'INSERT INTO email_events (id, applicationId, accountLabel, provider, '
      'folder, cursorValue, messageId, subject, fromAddr, date, extractedStatus, '
      'extractedFieldsJson, evidenceSnippet, hash, isSignificantUpdate) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        'fx_email_dup_1',
        'fx_app_dup_1',
        'Gmail',
        'fixture',
        'INBOX',
        null,
        '<dup-1@bluefinch>',
        'Application received - Backend Engineer',
        'Blue Finch Software <recruiting@bluefinch.io>',
        DateTime(2026, 1, 3).toIso8601String(),
        null,
        null,
        'Job ID: BE-4471. Portal: https://jobs.bluefinch.io/positions/BE-4471',
        'hash_dup_1',
        0,
      ],
    );
    db.execute(
      'INSERT INTO email_events (id, applicationId, accountLabel, provider, '
      'folder, cursorValue, messageId, subject, fromAddr, date, extractedStatus, '
      'extractedFieldsJson, evidenceSnippet, hash, isSignificantUpdate) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        'fx_email_dup_2',
        'fx_app_dup_2',
        'Gmail',
        'fixture',
        'INBOX',
        null,
        '<dup-2@bluefinch>',
        'Interview request - Backend Engineer',
        'Blue Finch Software <recruiting@bluefinch.io>',
        DateTime(2026, 1, 4).toIso8601String(),
        null,
        null,
        'Interview request for job ID: BE-4471.',
        'hash_dup_2',
        0,
      ],
    );

    final pipeline = FixtureIngestionPipeline(database);
    await pipeline.run();

    final ids = db
        .select("SELECT DISTINCT applicationId FROM email_events WHERE provider='fixture';");
    expect(ids.length, 1);
    expect(ids.first['applicationId'], 'fx_app_dup_1');

    final appCount = db.select(
      "SELECT COUNT(*) AS count FROM applications WHERE id LIKE 'fx_app_dup_%';",
    );
    expect((appCount.first['count'] as num).toInt(), 1);

    await database.close();
  }, skip: _sqliteSkipReason);

  test('pipeline inserts interview events from ics', () async {
    final database = AppDatabase(database: sqlite3.openInMemory());
    await database.open();
    final db = database.rawDb;

    db.execute('DELETE FROM email_events;');
    db.execute('DELETE FROM interview_events;');
    db.execute('DELETE FROM applications;');
    db.execute('DELETE FROM accounts;');
    db.execute('DELETE FROM sync_state;');

    db.execute(
      'INSERT INTO applications (id, company, role, jobId, portalUrl, firstSeen, '
      'lastSeen, currentStatus, confidence, accountLabel, sourceLabel, contact, '
      'nextStep, nextStepAt) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        'fx_app_iv_1',
        'Blue Finch Software',
        'Backend Engineer',
        'BE-4471',
        'https://jobs.bluefinch.io/positions/BE-4471',
        DateTime(2026, 1, 1).toIso8601String(),
        DateTime(2026, 1, 1).toIso8601String(),
        'received',
        70.0,
        'Gmail',
        'Fixture',
        null,
        null,
        null,
      ],
    );

    const ics = 'BEGIN:VCALENDAR\n'
        'BEGIN:VEVENT\n'
        'DTSTART:20260201T150000Z\n'
        'DTEND:20260201T153000Z\n'
        'SUMMARY:Interview - Backend Engineer\n'
        'END:VEVENT\n'
        'END:VCALENDAR';

    db.execute(
      'INSERT INTO email_events (id, applicationId, accountLabel, provider, '
      'folder, cursorValue, messageId, subject, fromAddr, date, extractedStatus, '
      'extractedFieldsJson, evidenceSnippet, hash, isSignificantUpdate) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        'fx_email_iv_1',
        'fx_app_iv_1',
        'Gmail',
        'fixture',
        'INBOX',
        null,
        '<iv-1@bluefinch>',
        'Interview scheduled: Blue Finch Software',
        'Blue Finch Software <recruiting@bluefinch.io>',
        DateTime(2026, 1, 5).toIso8601String(),
        null,
        jsonEncode({'ics': ics}),
        'Your interview has been scheduled. Please find the invite attached.',
        'hash_iv_1',
        0,
      ],
    );

    final pipeline = FixtureIngestionPipeline(database);
    await pipeline.run();

    final events =
        db.select('SELECT startTime, endTime, confidence, timezone '
            'FROM interview_events;');
    expect(events.length, 1);
    final expectedStart = DateTime.utc(2026, 2, 1, 15, 0).toLocal();
    expect(events.first['startTime'], expectedStart.toIso8601String());
    expect((events.first['confidence'] as num).toDouble(), closeTo(0.9, 0.01));
    expect(events.first['timezone'], 'UTC');

    final appRows = db.select(
      'SELECT nextStep, nextStepAt FROM applications WHERE id = ?;',
      ['fx_app_iv_1'],
    );
    expect(appRows.first['nextStep'], 'Interview scheduled');
    expect(appRows.first['nextStepAt'], expectedStart.toIso8601String());

    await database.close();
  }, skip: _sqliteSkipReason);

  test('text interviews create medium confidence events', () async {
    final database = AppDatabase(database: sqlite3.openInMemory());
    await database.open();
    final db = database.rawDb;

    db.execute('DELETE FROM email_events;');
    db.execute('DELETE FROM interview_events;');
    db.execute('DELETE FROM applications;');
    db.execute('DELETE FROM accounts;');
    db.execute('DELETE FROM sync_state;');

    db.execute(
      'INSERT INTO applications (id, company, role, jobId, portalUrl, firstSeen, '
      'lastSeen, currentStatus, confidence, accountLabel, sourceLabel, contact, '
      'nextStep, nextStepAt) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        'fx_app_text_1',
        'Nimbus Analytics',
        'Data Analyst',
        'NIM-DA-1023',
        'https://careers.nimbus-analytics.com/jobs/NIM-DA-1023',
        DateTime(2026, 1, 1).toIso8601String(),
        DateTime(2026, 1, 1).toIso8601String(),
        'received',
        70.0,
        'Gmail',
        'Fixture',
        null,
        null,
        null,
      ],
    );

    db.execute(
      'INSERT INTO email_events (id, applicationId, accountLabel, provider, '
      'folder, cursorValue, messageId, subject, fromAddr, date, extractedStatus, '
      'extractedFieldsJson, evidenceSnippet, hash, isSignificantUpdate) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        'fx_email_text_1',
        'fx_app_text_1',
        'Gmail',
        'fixture',
        'INBOX',
        null,
        '<text-1@nimbus>',
        'Interview availability for Data Analyst',
        'Nimbus Analytics <recruiting@nimbus-analytics.com>',
        DateTime(2026, 1, 7).toIso8601String(),
        null,
        null,
        'Are you available Tuesday, Jan 13 at 2:00 PM ET?',
        'hash_text_1',
        0,
      ],
    );

    final pipeline = FixtureIngestionPipeline(database);
    await pipeline.run();

    final events = db.select(
      'SELECT startTime, confidence, timezone FROM interview_events;',
    );
    expect(events.length, 1);
    expect((events.first['confidence'] as num).toDouble(), closeTo(0.6, 0.01));
    expect(events.first['timezone'], 'ET');
    expect(events.first['startTime'], isNotNull);

    await database.close();
  }, skip: _sqliteSkipReason);
}
