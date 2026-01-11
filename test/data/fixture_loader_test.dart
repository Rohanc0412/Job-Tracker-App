import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:job_tracker/data/db/db.dart';
import 'package:job_tracker/services/fixture_loader.dart';
import 'package:sqlite3/sqlite3.dart';

import '../support/fixture_test_bundle.dart';
import '../support/sqlite_test_utils.dart';

final String? _sqliteSkipReason = configureSqliteForTests();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fixture assets count exists', () async {
    final database = AppDatabase(database: sqlite3.openInMemory());
    final loader = FixtureLoader(database, bundle: FixtureTestBundle());
    final paths = await loader.listFixturePaths();
    expect(paths.length, greaterThanOrEqualTo(16));
    await database.close();
  }, skip: _sqliteSkipReason);

  test('fixture loader inserts rows', () async {
    final database = AppDatabase(database: sqlite3.openInMemory());
    final loader = FixtureLoader(database, bundle: FixtureTestBundle());
    final inserted = await loader.loadFixtures(clearExisting: true);
    final result = database.rawDb
        .select("SELECT COUNT(*) AS count FROM email_events WHERE provider='fixture';");
    final count = (result.first['count'] as num).toInt();
    expect(count, inserted);
    await database.close();
  }, skip: _sqliteSkipReason);

  test('evidence snippets are truncated and raw bodies stored', () async {
    final database = AppDatabase(database: sqlite3.openInMemory());
    final bundle = FixtureTestBundle();
    final loader = FixtureLoader(database, bundle: bundle);
    await loader.loadFixtures(clearExisting: true);
    const fileName = 'fx_002_interview_nimbus.eml';
    final raw = await bundle.loadString('assets/eml_fixtures/$fileName');
    final body = _extractBody(raw);
    final rows = database.rawDb.select(
      'SELECT evidenceSnippet, raw_body_text, raw_body_sha256, raw_body_byte_len '
      'FROM email_events WHERE id = ?;',
      ['fx_$fileName'],
    );
    expect(rows, isNotEmpty);
    final snippet = rows.first['evidenceSnippet'] as String;
    expect(snippet.length <= FixtureLoader.evidenceMaxLength, isTrue);
    final rawBodyText = rows.first['raw_body_text'] as String;
    expect(rawBodyText, body);
    final byteLen = rows.first['raw_body_byte_len'] as int;
    expect(byteLen, utf8.encode(body).length);
    final sha = rows.first['raw_body_sha256'] as String;
    expect(sha, isNotEmpty);
    await database.close();
  }, skip: _sqliteSkipReason);
}

String _extractBody(String raw) {
  final lines = raw.split(RegExp(r'\r?\n'));
  var index = 0;
  for (; index < lines.length; index++) {
    if (lines[index].trim().isEmpty) {
      index++;
      break;
    }
  }
  final body = lines.sublist(index).join('\n').trim();
  return body;
}
