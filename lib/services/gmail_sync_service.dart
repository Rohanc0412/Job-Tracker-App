import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'package:intl/intl.dart';
import 'package:sqlite3/sqlite3.dart';

import '../data/db/db.dart';
import '../services/fixture_ingestion_pipeline.dart';
import 'imap/imap_client.dart';
import 'raw_body_storage.dart';

class GmailSyncConfig {
  final String email;
  final String appPassword;
  final String folder;
  final DateTime? startDate;
  final bool storeRawBody;
  final int maxRawBodyBytes;
  final int hardCapBytes;
  final String dbPath;
  final String rawBodiesDir;
  final bool skipSeed;

  const GmailSyncConfig({
    required this.email,
    required this.appPassword,
    required this.folder,
    required this.startDate,
    required this.storeRawBody,
    required this.maxRawBodyBytes,
    required this.hardCapBytes,
    required this.dbPath,
    required this.rawBodiesDir,
    this.skipSeed = false,
  });

  Map<String, Object?> toMap() => {
        'email': email,
        'appPassword': appPassword,
        'folder': folder,
        'startDate': startDate?.toIso8601String(),
        'storeRawBody': storeRawBody,
        'maxRawBodyBytes': maxRawBodyBytes,
        'hardCapBytes': hardCapBytes,
        'dbPath': dbPath,
        'rawBodiesDir': rawBodiesDir,
        'skipSeed': skipSeed,
      };

  factory GmailSyncConfig.fromMap(Map<String, Object?> map) {
    final startDate = map['startDate'] as String?;
    return GmailSyncConfig(
      email: map['email'] as String,
      appPassword: map['appPassword'] as String,
      folder: map['folder'] as String,
      startDate: startDate == null ? null : DateTime.parse(startDate),
      storeRawBody: map['storeRawBody'] as bool,
      maxRawBodyBytes: map['maxRawBodyBytes'] as int,
      hardCapBytes: map['hardCapBytes'] as int,
      dbPath: map['dbPath'] as String,
      rawBodiesDir: map['rawBodiesDir'] as String,
      skipSeed: (map['skipSeed'] as bool?) ?? false,
    );
  }
}

class GmailSyncProgress {
  final String stage;
  final int processed;
  final int total;
  final String message;

  const GmailSyncProgress({
    required this.stage,
    required this.processed,
    required this.total,
    required this.message,
  });

  factory GmailSyncProgress.fromMap(Map<String, Object?> map) {
    return GmailSyncProgress(
      stage: map['stage'] as String,
      processed: map['processed'] as int,
      total: map['total'] as int,
      message: map['message'] as String,
    );
  }

  Map<String, Object?> toMap() => {
        'stage': stage,
        'processed': processed,
        'total': total,
        'message': message,
      };
}

class GmailSyncResult {
  final int fetched;
  final int inserted;
  final int skipped;
  final int? lastUid;
  final int? uidValidity;

  const GmailSyncResult({
    required this.fetched,
    required this.inserted,
    required this.skipped,
    required this.lastUid,
    required this.uidValidity,
  });
}

class GmailSyncService {
  Stream<GmailSyncProgress> startSync(GmailSyncConfig config) {
    final controller = StreamController<GmailSyncProgress>();
    final receivePort = ReceivePort();
    Isolate.spawn(
      _syncEntryPoint,
      _IsolatePayload(config.toMap(), receivePort.sendPort),
    );
    receivePort.listen((message) {
      if (message is Map<String, Object?>) {
        controller.add(GmailSyncProgress.fromMap(message));
        if (message['stage'] == 'done') {
          controller.close();
          receivePort.close();
        }
      }
    }, onError: controller.addError);
    return controller.stream;
  }
}

class GmailSyncRunner {
  static Future<GmailSyncResult> run(
    GmailSyncConfig config, {
    ImapClient? client,
    AppDatabase? database,
    void Function(GmailSyncProgress progress)? onProgress,
  }) async {
    final db = database ?? AppDatabase(
      dbPath: config.dbPath,
      skipSeed: config.skipSeed,
    );
    await db.open();
    final rawDb = db.rawDb;
    final cursorStore = _SyncStateStore(rawDb);

    _ensureAccount(rawDb, config.email);

    final cursor = cursorStore.loadCursor(
      accountLabel: config.email,
      folder: config.folder,
    );

    final imap = client ?? ImapClient(maxLiteralBytes: config.hardCapBytes);
    await imap.connect('imap.gmail.com', 993);
    await imap.login(config.email, config.appPassword);
    final selectResult = await imap.select(config.folder);

    final uidValidity = selectResult.uidValidity;
    var lastUid = cursor.lastUid;
    if (cursor.uidValidity != null && cursor.uidValidity != uidValidity) {
      lastUid = null;
    }

    List<int> uids;
    if (lastUid == null || lastUid == 0) {
      final startDate = config.startDate;
      if (startDate == null) {
        await imap.logout();
        throw StateError('Start date is required for the first sync.');
      }
      // Use filtered search for job-related emails only
      uids = await imap.uidSearchJobApplications(startDate);
    } else {
      // Use filtered search for job-related emails only
      uids = await imap.uidSearchJobApplicationsFrom(lastUid + 1);
    }
    uids.sort();

    var processed = 0;
    var inserted = 0;
    var skipped = 0;

    final storage = RawBodyStorage(
      maxRawBodyBytes: config.maxRawBodyBytes,
      hardCapBytes: config.hardCapBytes,
      rawBodiesDir: config.rawBodiesDir,
    );

    final insertStmt = rawDb.prepare(
      'INSERT OR IGNORE INTO email_events (id, applicationId, accountLabel, '
      'provider, folder, cursorValue, messageId, subject, fromAddr, date, '
      'extractedStatus, extractedFieldsJson, evidenceSnippet, raw_body_text, '
      'raw_body_path, raw_body_sha256, raw_body_byte_len, hash, '
      'isSignificantUpdate) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
    );
    final insertAppStmt = rawDb.prepare(
      'INSERT OR IGNORE INTO applications (id, company, role, jobId, portalUrl, '
      'firstSeen, lastSeen, currentStatus, confidence, accountLabel, '
      'sourceLabel, contact, nextStep, nextStepAt) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
    );

    for (final uid in uids) {
      processed++;
      onProgress?.call(
        GmailSyncProgress(
          stage: 'fetch',
          processed: processed,
          total: uids.length,
          message: 'Fetching UID $uid',
        ),
      );

      final fetched = await imap.fetchMessage(uid);
      final header = _parseHeaders(fetched.headerText);
      final fromAddr = header['from'] ?? 'unknown';
      final subject = header['subject'] ?? 'No subject';
      final messageId =
          header['message-id'] ?? '<gmail-uid-$uid@local>';
      final date = _parseDate(header['date']);
      final bodyBytes = fetched.bodyBytes;
      final bodyText = utf8.decode(bodyBytes, allowMalformed: true);

      final storageResult = await storage.store(
        bodyBytes: bodyBytes,
        reportedByteLen: fetched.bodyByteLen,
        storeRawBody: config.storeRawBody,
      );

      final snippet = _makeSnippet(bodyText, 160);
      final hash = sha256
          .convert(utf8.encode('$messageId|$fromAddr|$subject|$uid'))
          .toString();
      final appId = _applicationId(config.email, uid);
      insertAppStmt.execute([
        appId,
        'Unknown Company',
        'Unknown Role',
        null,
        null,
        date.toIso8601String(),
        date.toIso8601String(),
        'applied',
        40.0,
        config.email,
        'Gmail',
        null,
        null,
        null,
      ]);
      insertStmt.execute([
        'gmail_$uid',
        appId,
        config.email,
        'gmail',
        config.folder,
        uid.toString(),
        messageId,
        subject,
        fromAddr,
        date.toIso8601String(),
        null,
        null,
        snippet,
        storageResult.rawBodyText,
        storageResult.rawBodyPath,
        storageResult.rawBodySha256,
        storageResult.rawBodyByteLen,
        hash,
        0,
      ]);

      if (rawDb.updatedRows > 0) {
        inserted++;
      } else {
        skipped++;
      }
    }
    insertStmt.dispose();
    insertAppStmt.dispose();

    if (uids.isNotEmpty) {
      lastUid = uids.last;
    }

    if (uids.isNotEmpty) {
      final pipeline = FixtureIngestionPipeline(
        db,
        provider: 'gmail',
        cleanupFixtureApps: false,
      );
      await pipeline.run();
      rawDb.execute(
        "DELETE FROM applications WHERE id LIKE 'gm_%' "
        'AND id NOT IN (SELECT DISTINCT applicationId FROM email_events);',
      );
    }

    await imap.logout();

    if (lastUid != null) {
      cursorStore.saveCursor(
        accountLabel: config.email,
        folder: config.folder,
        uidValidity: uidValidity,
        lastUid: lastUid,
        syncedAt: DateTime.now().toUtc(),
      );
    }

    return GmailSyncResult(
      fetched: processed,
      inserted: inserted,
      skipped: skipped,
      lastUid: lastUid,
      uidValidity: uidValidity,
    );
  }

  static Map<String, String> _parseHeaders(String headerText) {
    final headers = <String, String>{};
    String? currentKey;
    final lines = headerText.split(RegExp(r'\r?\n'));
    for (final line in lines) {
      if (line.startsWith(' ') || line.startsWith('\t')) {
        if (currentKey != null) {
          headers[currentKey] =
              '${headers[currentKey]} ${line.trim()}';
        }
        continue;
      }
      final index = line.indexOf(':');
      if (index <= 0) {
        continue;
      }
      currentKey = line.substring(0, index).trim().toLowerCase();
      headers[currentKey] = line.substring(index + 1).trim();
    }
    return headers;
  }

  static DateTime _parseDate(String? value) {
    if (value == null) {
      return DateTime.now().toUtc();
    }
    try {
      return DateFormat('EEE, dd MMM yyyy HH:mm:ss Z', 'en_US').parseUtc(value);
    } catch (_) {
      try {
        return DateTime.parse(value).toUtc();
      } catch (_) {
        return DateTime.now().toUtc();
      }
    }
  }

  static String _makeSnippet(String body, int maxLength) {
    final normalized = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxLength) {
      return normalized;
    }
    return '${normalized.substring(0, maxLength - 3).trimRight()}...';
  }

  static String _applicationId(String email, int uid) {
    final safe = email.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_');
    return 'gm_${safe}_$uid';
  }

  static void _ensureAccount(Database db, String email) {
    final existing = db.select(
      'SELECT id FROM accounts WHERE provider = ? AND label = ?;',
      ['gmail', email],
    );
    if (existing.isNotEmpty) {
      return;
    }
    final id = 'acct_gmail_${email.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_')}';
    db.execute(
      'INSERT INTO accounts (id, label, provider, createdAt) VALUES (?, ?, ?, ?);',
      [id, email, 'gmail', DateTime.now().toUtc().toIso8601String()],
    );
  }
}

class _SyncStateStore {
  _SyncStateStore(this._db);

  final Database _db;

  _GmailCursor loadCursor({
    required String accountLabel,
    required String folder,
  }) {
    final rows = _db.select(
      'SELECT cursorKey, cursorValue, lastSyncTime FROM sync_state '
      'WHERE provider = ? AND accountLabel = ? AND folder = ?;',
      ['gmail', accountLabel, folder],
    );
    int? uidValidity;
    int? lastUid;
    DateTime? lastSyncTime;
    for (final row in rows) {
      final key = row['cursorKey'] as String;
      final value = row['cursorValue'] as String;
      if (key == 'uidvalidity') {
        uidValidity = int.tryParse(value);
      } else if (key == 'last_uid') {
        lastUid = int.tryParse(value);
        lastSyncTime = DateTime.tryParse(row['lastSyncTime'] as String);
      }
    }
    return _GmailCursor(
      uidValidity: uidValidity,
      lastUid: lastUid,
      lastSyncTime: lastSyncTime,
    );
  }

  void saveCursor({
    required String accountLabel,
    required String folder,
    required int uidValidity,
    required int lastUid,
    required DateTime syncedAt,
  }) {
    final uidValidityId = _cursorId(accountLabel, folder, 'uidvalidity');
    final lastUidId = _cursorId(accountLabel, folder, 'last_uid');
    _db.execute(
      'INSERT OR REPLACE INTO sync_state '
      '(id, accountLabel, provider, folder, cursorKey, cursorValue, lastSyncTime) '
      'VALUES (?, ?, ?, ?, ?, ?, ?);',
      [
        uidValidityId,
        accountLabel,
        'gmail',
        folder,
        'uidvalidity',
        uidValidity.toString(),
        syncedAt.toIso8601String(),
      ],
    );
    _db.execute(
      'INSERT OR REPLACE INTO sync_state '
      '(id, accountLabel, provider, folder, cursorKey, cursorValue, lastSyncTime) '
      'VALUES (?, ?, ?, ?, ?, ?, ?);',
      [
        lastUidId,
        accountLabel,
        'gmail',
        folder,
        'last_uid',
        lastUid.toString(),
        syncedAt.toIso8601String(),
      ],
    );
  }

  String _cursorId(String accountLabel, String folder, String key) {
    final safeAccount =
        accountLabel.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_');
    final safeFolder = folder.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_');
    return 'sync_gmail_${safeAccount}_${safeFolder}_$key';
  }
}

class _GmailCursor {
  final int? uidValidity;
  final int? lastUid;
  final DateTime? lastSyncTime;

  const _GmailCursor({
    required this.uidValidity,
    required this.lastUid,
    required this.lastSyncTime,
  });
}

class _IsolatePayload {
  final Map<String, Object?> config;
  final SendPort sendPort;

  const _IsolatePayload(this.config, this.sendPort);
}

@pragma('vm:entry-point')
Future<void> _syncEntryPoint(_IsolatePayload payload) async {
  final config = GmailSyncConfig.fromMap(payload.config);
  final sendPort = payload.sendPort;

  void send(GmailSyncProgress progress) {
    sendPort.send(progress.toMap());
  }

  try {
    send(GmailSyncProgress(
      stage: 'start',
      processed: 0,
      total: 0,
      message: 'Connecting to Gmail',
    ));
    await GmailSyncRunner.run(
      config,
      onProgress: send,
    );
    send(GmailSyncProgress(
      stage: 'done',
      processed: 0,
      total: 0,
      message: 'Sync complete',
    ));
  } catch (error) {
    sendPort.send({
      'stage': 'done',
      'processed': 0,
      'total': 0,
      'message': 'Sync failed: $error',
    });
  }
}
