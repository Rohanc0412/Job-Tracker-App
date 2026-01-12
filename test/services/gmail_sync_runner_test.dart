import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:job_tracker/data/db/db.dart';
import 'package:job_tracker/services/gmail_sync_service.dart';
import 'package:job_tracker/services/imap/imap_client.dart';
import 'package:sqlite3/sqlite3.dart';

import '../support/mock_imap_transport.dart';
import '../support/sqlite_test_utils.dart';

final String? _sqliteSkipReason = configureSqliteForTests();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('stores large raw body to file and truncates db text', () async {
    final tempDir = await Directory.systemTemp.createTemp('gmail_sync');
    final db = AppDatabase(database: sqlite3.openInMemory());
    await db.open();

    final header = _headerText(uid: 101);
    final body = List.filled(200, 'A').join();
    final script = [
      ImapScriptStep(
        command: 'LOGIN',
        responses: ['{tag} OK LOGIN completed\r\n'],
      ),
      ImapScriptStep(
        command: 'SELECT',
        responses: [
          '* OK [UIDVALIDITY 42] UIDs valid\r\n',
          '{tag} OK SELECT completed\r\n',
        ],
      ),
      ImapScriptStep(
        command: 'UID SEARCH SINCE',
        responses: ['* SEARCH 101\r\n', '{tag} OK SEARCH completed\r\n'],
      ),
      ImapScriptStep(
        command: 'UID FETCH 101',
        responses: _fetchResponses(uid: 101, header: header, body: body),
      ),
      ImapScriptStep(
        command: 'LOGOUT',
        responses: ['* BYE LOGOUT\r\n', '{tag} OK LOGOUT completed\r\n'],
      ),
    ];

    final transport = MockImapTransport(script);
    final client = ImapClient(transport: transport, maxLiteralBytes: 1024);
    final config = GmailSyncConfig(
      email: 'user@example.com',
      appPassword: 'app-pass',
      folder: 'INBOX',
      startDate: DateTime.utc(2026, 1, 1),
      storeRawBody: true,
      maxRawBodyBytes: 32,
      hardCapBytes: 1024,
      dbPath: 'memory',
      rawBodiesDir: tempDir.path,
    );

    final result = await GmailSyncRunner.run(
      config,
      client: client,
      database: db,
    );

    expect(result.inserted, 1);
    final rows = db.rawDb.select(
      "SELECT evidenceSnippet, raw_body_text, raw_body_path, raw_body_sha256, raw_body_byte_len "
      "FROM email_events WHERE provider = 'gmail' AND accountLabel = ?;",
      ['user@example.com'],
    );
    expect(rows.length, 1);
    final row = rows.first;
    final snippet = row['evidenceSnippet'] as String;
    expect(snippet.length <= 160, isTrue);
    final rawText = row['raw_body_text'] as String;
    expect(utf8.encode(rawText).length <= 32, isTrue);
    final path = row['raw_body_path'] as String;
    expect(path, isNotEmpty);
    final sha = row['raw_body_sha256'] as String;
    expect(sha, sha256.convert(utf8.encode(body)).toString());
    final byteLen = row['raw_body_byte_len'] as int;
    expect(byteLen, utf8.encode(body).length);

    final file = File(path);
    expect(await file.exists(), isTrue);
    final compressed = await file.readAsBytes();
    final decompressed = utf8.decode(gzip.decode(compressed));
    expect(decompressed, body);

    await tempDir.delete(recursive: true);
    await db.close();
  }, skip: _sqliteSkipReason);

  test('raw body disabled stores only snippet and hashes', () async {
    final tempDir = await Directory.systemTemp.createTemp('gmail_sync');
    final db = AppDatabase(database: sqlite3.openInMemory());
    await db.open();

    final header = _headerText(uid: 201);
    final body = 'Hello world';
    final script = [
      ImapScriptStep(
        command: 'LOGIN',
        responses: ['{tag} OK LOGIN completed\r\n'],
      ),
      ImapScriptStep(
        command: 'SELECT',
        responses: [
          '* OK [UIDVALIDITY 42] UIDs valid\r\n',
          '{tag} OK SELECT completed\r\n',
        ],
      ),
      ImapScriptStep(
        command: 'UID SEARCH SINCE',
        responses: ['* SEARCH 201\r\n', '{tag} OK SEARCH completed\r\n'],
      ),
      ImapScriptStep(
        command: 'UID FETCH 201',
        responses: _fetchResponses(uid: 201, header: header, body: body),
      ),
      ImapScriptStep(
        command: 'LOGOUT',
        responses: ['* BYE LOGOUT\r\n', '{tag} OK LOGOUT completed\r\n'],
      ),
    ];

    final transport = MockImapTransport(script);
    final client = ImapClient(transport: transport, maxLiteralBytes: 1024);
    final config = GmailSyncConfig(
      email: 'user@example.com',
      appPassword: 'app-pass',
      folder: 'INBOX',
      startDate: DateTime.utc(2026, 1, 1),
      storeRawBody: false,
      maxRawBodyBytes: 64,
      hardCapBytes: 1024,
      dbPath: 'memory',
      rawBodiesDir: tempDir.path,
    );

    await GmailSyncRunner.run(
      config,
      client: client,
      database: db,
    );

    final rows = db.rawDb.select(
      "SELECT raw_body_text, raw_body_path, raw_body_sha256, raw_body_byte_len "
      "FROM email_events WHERE provider = 'gmail' AND accountLabel = ?;",
      ['user@example.com'],
    );
    expect(rows.length, 1);
    final row = rows.first;
    expect(row['raw_body_text'], isNull);
    expect(row['raw_body_path'], isNull);
    expect(row['raw_body_sha256'], isNotNull);
    expect(row['raw_body_byte_len'], isNotNull);

    await tempDir.delete(recursive: true);
    await db.close();
  }, skip: _sqliteSkipReason);

  test('cursor persists and only fetches new uids', () async {
    final tempDir = await Directory.systemTemp.createTemp('gmail_sync');
    final db = AppDatabase(database: sqlite3.openInMemory());
    await db.open();

    final header301 = _headerText(uid: 301);
    final header302 = _headerText(uid: 302);
    final header303 = _headerText(uid: 303);
    final body = 'Body';
    final scriptFirst = [
      ImapScriptStep(
        command: 'LOGIN',
        responses: ['{tag} OK LOGIN completed\r\n'],
      ),
      ImapScriptStep(
        command: 'SELECT',
        responses: [
          '* OK [UIDVALIDITY 55] UIDs valid\r\n',
          '{tag} OK SELECT completed\r\n',
        ],
      ),
      ImapScriptStep(
        command: 'UID SEARCH SINCE',
        responses: ['* SEARCH 301 302\r\n', '{tag} OK SEARCH completed\r\n'],
      ),
      ImapScriptStep(
        command: 'UID FETCH 301',
        responses: _fetchResponses(uid: 301, header: header301, body: body),
      ),
      ImapScriptStep(
        command: 'UID FETCH 302',
        responses: _fetchResponses(uid: 302, header: header302, body: body),
      ),
      ImapScriptStep(
        command: 'LOGOUT',
        responses: ['* BYE LOGOUT\r\n', '{tag} OK LOGOUT completed\r\n'],
      ),
    ];
    final clientFirst = ImapClient(
        transport: MockImapTransport(scriptFirst), maxLiteralBytes: 1024);
    final config = GmailSyncConfig(
      email: 'user@example.com',
      appPassword: 'app-pass',
      folder: 'INBOX',
      startDate: DateTime.utc(2026, 1, 1),
      storeRawBody: false,
      maxRawBodyBytes: 64,
      hardCapBytes: 1024,
      dbPath: 'memory',
      rawBodiesDir: tempDir.path,
    );

    await GmailSyncRunner.run(
      config,
      client: clientFirst,
      database: db,
    );

    final scriptSecond = [
      ImapScriptStep(
        command: 'LOGIN',
        responses: ['{tag} OK LOGIN completed\r\n'],
      ),
      ImapScriptStep(
        command: 'SELECT',
        responses: [
          '* OK [UIDVALIDITY 55] UIDs valid\r\n',
          '{tag} OK SELECT completed\r\n',
        ],
      ),
      ImapScriptStep(
        command: 'UID SEARCH UID 303:*',
        responses: ['* SEARCH 303\r\n', '{tag} OK SEARCH completed\r\n'],
      ),
      ImapScriptStep(
        command: 'UID FETCH 303',
        responses: _fetchResponses(uid: 303, header: header303, body: body),
      ),
      ImapScriptStep(
        command: 'LOGOUT',
        responses: ['* BYE LOGOUT\r\n', '{tag} OK LOGOUT completed\r\n'],
      ),
    ];
    final clientSecond = ImapClient(
        transport: MockImapTransport(scriptSecond), maxLiteralBytes: 1024);

    await GmailSyncRunner.run(
      config.copyWith(startDate: null),
      client: clientSecond,
      database: db,
    );

    final rows = db.rawDb.select(
      "SELECT COUNT(*) AS count FROM email_events "
      "WHERE provider = 'gmail' AND accountLabel = ?;",
      ['user@example.com'],
    );
    final count = (rows.first['count'] as num).toInt();
    expect(count, 3);

    await tempDir.delete(recursive: true);
    await db.close();
  }, skip: _sqliteSkipReason);
}

String _headerText({required int uid}) {
  return 'From: Test Sender <sender@example.com>\r\n'
      'Subject: Test message\r\n'
      'Date: Wed, 07 Jan 2026 14:30:00 -0500\r\n'
      'Message-ID: <msg-$uid@test>\r\n'
      '\r\n';
}

List<Object> _fetchResponses({
  required int uid,
  required String header,
  required String body,
}) {
  final headerBytes = utf8.encode(header);
  final bodyBytes = utf8.encode(body);
  return [
    '* 1 FETCH (UID $uid BODY[HEADER] {${headerBytes.length}}\r\n',
    headerBytes,
    '\r\n BODY[TEXT]<0> {${bodyBytes.length}}\r\n',
    bodyBytes,
    '\r\n)\r\n{tag} OK FETCH completed\r\n',
  ];
}

extension _GmailConfigCopy on GmailSyncConfig {
  GmailSyncConfig copyWith({
    DateTime? startDate,
  }) {
    return GmailSyncConfig(
      email: email,
      appPassword: appPassword,
      folder: folder,
      startDate: startDate,
      storeRawBody: storeRawBody,
      maxRawBodyBytes: maxRawBodyBytes,
      hardCapBytes: hardCapBytes,
      dbPath: dbPath,
      rawBodiesDir: rawBodiesDir,
    );
  }
}
