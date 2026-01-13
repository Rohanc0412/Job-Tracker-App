import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'package:intl/intl.dart';
import 'package:sqlite3/sqlite3.dart';

import '../data/db/db.dart';
import '../data/models/application.dart';
import '../domain/ingestion/dedup.dart';
import '../domain/status/status_types.dart';
import 'email_text_extractor.dart';
import 'imap/imap_client.dart';
import 'latest_message_extractor.dart';
import 'local_llm_pipeline.dart';
import 'local_llm_settings.dart';
import 'logger.dart';
import 'mime_decoder.dart';
import 'ollama_endpoints.dart';
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
  final String llmBaseUrl;
  final String llmModelId;
  final int llmRequestTimeoutMs;
  final int llmMaxInputChars;
  final String? llmApiKey;
  final String? logFilePath;

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
    required this.llmBaseUrl,
    required this.llmModelId,
    required this.llmRequestTimeoutMs,
    required this.llmMaxInputChars,
    required this.llmApiKey,
    this.logFilePath,
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
        'llmBaseUrl': llmBaseUrl,
        'llmModelId': llmModelId,
        'llmRequestTimeoutMs': llmRequestTimeoutMs,
        'llmMaxInputChars': llmMaxInputChars,
        'llmApiKey': llmApiKey,
        'logFilePath': logFilePath,
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
      llmBaseUrl: map['llmBaseUrl'] as String,
      llmModelId: map['llmModelId'] as String,
      llmRequestTimeoutMs: map['llmRequestTimeoutMs'] as int,
      llmMaxInputChars: map['llmMaxInputChars'] as int,
      llmApiKey: map['llmApiKey'] as String?,
      logFilePath: map['logFilePath'] as String?,
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

class GmailSyncReviewEvent {
  final String event;
  final String reviewId;

  const GmailSyncReviewEvent({
    required this.event,
    required this.reviewId,
  });

  factory GmailSyncReviewEvent.fromMap(Map<String, Object?> map) {
    return GmailSyncReviewEvent(
      event: map['event'] as String,
      reviewId: map['reviewId'] as String,
    );
  }

  Map<String, Object?> toMap() => {
        'event': event,
        'reviewId': reviewId,
      };
}

class GmailSyncSession {
  final Stream<GmailSyncProgress> progress;
  final Stream<GmailSyncReviewEvent> reviewEvents;

  const GmailSyncSession({
    required this.progress,
    required this.reviewEvents,
  });
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
  GmailSyncSession startSync(GmailSyncConfig config) {
    final progressController = StreamController<GmailSyncProgress>();
    final reviewController = StreamController<GmailSyncReviewEvent>();
    final receivePort = ReceivePort();
    Isolate.spawn(
      _syncEntryPoint,
      _IsolatePayload(config.toMap(), receivePort.sendPort),
    );
    receivePort.listen((message) {
      if (message is Map<String, Object?>) {
        final type = message['type'] as String?;
        if (type == 'review') {
          reviewController.add(GmailSyncReviewEvent.fromMap(message));
          return;
        }
        progressController.add(GmailSyncProgress.fromMap(message));
        if (message['stage'] == 'done') {
          progressController.close();
          reviewController.close();
          receivePort.close();
        }
      }
    }, onError: (error) {
      progressController.addError(error);
      reviewController.addError(error);
    });
    return GmailSyncSession(
      progress: progressController.stream,
      reviewEvents: reviewController.stream,
    );
  }
}

class GmailSyncRunner {
  static Future<GmailSyncResult> run(
    GmailSyncConfig config, {
    ImapClient? client,
    AppDatabase? database,
    LlmEmailAnalyzer? llmAnalyzer,
    void Function(GmailSyncProgress progress)? onProgress,
    void Function(GmailSyncReviewEvent event)? onReview,
  }) async {
    final db = database ?? AppDatabase(
      dbPath: config.dbPath,
      skipSeed: config.skipSeed,
    );
    await db.open();
    final rawDb = db.rawDb;
    final cursorStore = _SyncStateStore(rawDb);

    _ensureAccount(rawDb, config.email);
    final isOpenAiModel = config.llmModelId == kOpenAiModelId;
    if (!isOpenAiModel) {
      OllamaEndpoints.validateBaseUrl(config.llmBaseUrl);
    }

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
      uids = await imap.uidSearchJobApplicationsFrom(
        lastUid + 1,
        since: config.startDate,
      );
    }
    uids.sort();

    var processed = 0;
    var inserted = 0;
    var skipped = 0;
    final initialStartDate =
        (lastUid == null || lastUid == 0) ? config.startDate : null;
    final initialStartDateUtc = initialStartDate?.toUtc();

    final analyzer = llmAnalyzer ??
        (isOpenAiModel
            ? OpenAiLlmPipeline(
                config: OpenAiLlmConfig(
                  baseUrl: config.llmBaseUrl,
                  modelId: config.llmModelId,
                  apiKey: config.llmApiKey ?? '',
                  requestTimeoutMs: config.llmRequestTimeoutMs,
                  maxInputChars: config.llmMaxInputChars,
                ),
              )
            : LocalLlmPipeline(
                config: LocalLlmConfig(
                  baseUrl: config.llmBaseUrl,
                  modelId: config.llmModelId,
                  requestTimeoutMs: config.llmRequestTimeoutMs,
                  maxInputChars: config.llmMaxInputChars,
                ),
              ));
    final LlmModelLifecycle? lifecycle =
        analyzer is LlmModelLifecycle ? analyzer as LlmModelLifecycle : null;
    if (lifecycle != null) {
      await lifecycle.preload();
    }
    final applications = _loadApplications(rawDb);

    final storage = RawBodyStorage(
      maxRawBodyBytes: config.maxRawBodyBytes,
      hardCapBytes: config.hardCapBytes,
      rawBodiesDir: config.rawBodiesDir,
    );

    final previewBytes =
        min(config.hardCapBytes, config.llmMaxInputChars * 2);

    final insertReviewStmt = rawDb.prepare(
      'INSERT OR IGNORE INTO email_review_queue '
      '(id, accountLabel, provider, folder, cursorValue, messageId, subject, '
      'fromAddr, toAddr, date, snippet, clean_body_text, clean_body_preview, '
      'raw_body_text, raw_body_path, raw_body_sha256, raw_body_byte_len, '
      'llm_json, llm_state, llm_error, user_overrides_json, '
      'suggested_application_id, selected_application_id, review_state, '
      'createdAt, updatedAt) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '
      '?, ?, ?, ?, ?);',
    );
    final updateReviewLlmStmt = rawDb.prepare(
      'UPDATE email_review_queue '
      'SET llm_json = ?, llm_state = ?, llm_error = ?, '
      'suggested_application_id = ?, updatedAt = ? '
      'WHERE id = ?;',
    );
    final updateReviewBodyStmt = rawDb.prepare(
      'UPDATE email_review_queue '
      'SET clean_body_text = ?, clean_body_preview = ?, raw_body_text = ?, '
      'raw_body_path = ?, raw_body_sha256 = ?, raw_body_byte_len = ?, '
      'updatedAt = ? '
      'WHERE id = ?;',
    );

    try {
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

        final fetched = await imap.fetchMessagePreview(
          uid,
          maxBodyBytes: previewBytes,
        );
        final headers = MimeDecoder.parseHeaderBlock(fetched.headerText);
        final fromAddr = headers['from'] ?? 'unknown';
        final toAddr = headers['to'] ?? 'unknown';
        final subject = EmailTextExtractor.decodeMimeHeader(
            headers['subject'] ?? 'No subject');
        final messageId =
            headers['message-id'] ?? '<gmail-uid-$uid@local>';
        final date = _parseDate(headers['date']);

        final sanitizedSubject =
            subject.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (initialStartDateUtc != null &&
            date.isBefore(initialStartDateUtc)) {
          AppLogger.log.info(
            '[GmailSync] Skipping UID $uid before start date '
            '${initialStartDateUtc.toIso8601String()} '
            'subject="$sanitizedSubject"',
          );
          lastUid = uid;
          cursorStore.saveCursor(
            accountLabel: config.email,
            folder: config.folder,
            uidValidity: uidValidity,
            lastUid: lastUid,
            syncedAt: DateTime.now().toUtc(),
          );
          skipped++;
          continue;
        }

        final decodedPreview = MimeDecoder.decodeBody(
          headers: headers,
          bodyBytes: fetched.bodyBytes,
        );
        final previewSnippet = EmailTextExtractor.getPreview(
          decodedPreview.body,
          maxLength: 200,
        );
        final cleanPreview = EmailTextExtractor.extractCleanText(
          decodedPreview.body,
        );
        final cleanPreviewShort = _cleanPreview(cleanPreview, maxLength: 500);
        final reviewId = _reviewId(config.email, uid);
        final now = DateTime.now().toUtc();
        insertReviewStmt.execute([
          reviewId,
          config.email,
          'gmail',
          config.folder,
          uid.toString(),
          messageId,
          subject,
          fromAddr,
          toAddr,
          date.toIso8601String(),
          previewSnippet,
          cleanPreview,
          cleanPreviewShort,
          null,
          null,
          null,
          null,
          null,
          'pending',
          null,
          null,
          _applicationId(config.email, uid),
          null,
          'pending',
          now.toIso8601String(),
          now.toIso8601String(),
        ]);
        if (rawDb.updatedRows == 0) {
          skipped++;
          continue;
        }
        inserted++;
        onReview?.call(GmailSyncReviewEvent(
          event: 'created',
          reviewId: reviewId,
        ));
        final latestContext = extract_latest_message_context(
          bodyText: decodedPreview.body,
          bodyHtml: null,
          snippet: previewSnippet,
          envelopeFrom: fromAddr,
          envelopeTo: toAddr,
          subject: subject,
          date: date.toIso8601String(),
          maxInputChars: config.llmMaxInputChars,
        );
        final llmInput = LlmEmailInput(
          context: latestContext,
          snippet: previewSnippet,
        );

        Map<String, Object?>? llmLogPayload;
        String llmState = 'pending';
        String? llmError;
        String? suggestedAppId;
        try {
          final llmResult = await analyzer.analyze(llmInput);
          final llmSummary = llmResult.extraction?.summary;
          final llmReason = llmResult.reason;
          final detail = llmResult.relevant
              ? 'summary="${llmSummary ?? ''}"'
              : 'reason="${llmReason ?? ''}"';
          AppLogger.log.info(
            '[GmailSync] LLM UID $uid messageId=$messageId '
            'subject="$sanitizedSubject" relevant=${llmResult.relevant} '
            'category=${llmResult.category} '
            'confidence=${llmResult.confidence.toStringAsFixed(2)} '
            '$detail',
          );
          llmLogPayload = <String, Object?>{
            'relevant': llmResult.relevant,
            'category': llmResult.category,
            'confidence': llmResult.confidence,
            'reason': llmResult.reason,
          };
          final llmExtraction = llmResult.extraction;
          if (llmExtraction != null) {
            llmLogPayload.addAll({
              'company': llmExtraction.company,
              'role': llmExtraction.role,
              'jobId': llmExtraction.jobId,
              'portalUrl': llmExtraction.portalUrl,
              'status': llmExtraction.status,
              'summary': llmExtraction.summary,
              'actionRequired': llmExtraction.actionRequired,
              'actionItems': llmExtraction.actionItems,
              'originalFromEmail': llmExtraction.originalFromEmail,
              'originalToEmails': llmExtraction.originalToEmails,
              'interview': {
                'start': llmExtraction.interview.start,
                'end': llmExtraction.interview.end,
                'timezone': llmExtraction.interview.timezone,
                'location': llmExtraction.interview.location,
                'meetingUrl': llmExtraction.interview.meetingUrl,
              },
              'evidence': [
                for (final item in llmExtraction.evidence)
                  {
                    'field': item.field,
                    'source': item.source,
                    'quote': item.quote,
                  }
              ],
            });
            final incoming = ExtractedApplicationData(
              jobId: _normalizeText(llmExtraction.jobId),
              portalUrl: _normalizeText(llmExtraction.portalUrl),
              company: _normalizeText(llmExtraction.company),
              role: _normalizeText(llmExtraction.role),
            );
            final match = matchApplication(applications, incoming);
            suggestedAppId =
                match?.id ?? _applicationId(config.email, uid);
          } else {
            suggestedAppId = _applicationId(config.email, uid);
          }
          llmState = 'ready';
          AppLogger.log.info(
            '[GmailSync] LLM response UID $uid messageId=$messageId '
            'subject="$sanitizedSubject" result=${jsonEncode(llmLogPayload)}',
          );
        } catch (error) {
          llmError = error.toString();
          llmState = 'failed';
          suggestedAppId = _applicationId(config.email, uid);
          AppLogger.log.warning(
            '[GmailSync] LLM failed UID $uid messageId=$messageId '
            'subject="$sanitizedSubject" error=$llmError',
          );
        }
        updateReviewLlmStmt.execute([
          llmLogPayload == null ? null : jsonEncode(llmLogPayload),
          llmState,
          llmError,
          suggestedAppId,
          DateTime.now().toUtc().toIso8601String(),
          reviewId,
        ]);
        onReview?.call(GmailSyncReviewEvent(
          event: 'updated',
          reviewId: reviewId,
        ));

        lastUid = uid;
        cursorStore.saveCursor(
          accountLabel: config.email,
          folder: config.folder,
          uidValidity: uidValidity,
          lastUid: lastUid,
          syncedAt: DateTime.now().toUtc(),
        );

        ImapFetchedMessage? fullFetched;
        MimeDecodedBody? fullDecoded;
        if (config.storeRawBody) {
          fullFetched = await imap.fetchMessageFull(uid);
          fullDecoded = MimeDecoder.decodeBody(
            headers: headers,
            bodyBytes: fullFetched.bodyBytes,
          );
        }

        final storageResult = await storage.store(
          bodyBytes: fullFetched?.bodyBytes ?? fetched.bodyBytes,
          reportedByteLen: fullFetched?.bodyByteLen ?? fetched.bodyByteLen,
          storeRawBody: config.storeRawBody,
          decodedText: (fullDecoded ?? decodedPreview).body,
        );
        final cleanBody = EmailTextExtractor.extractCleanText(
          (fullDecoded ?? decodedPreview).body,
        );
        final cleanBodyPreview = _cleanPreview(cleanBody, maxLength: 500);
        updateReviewBodyStmt.execute([
          cleanBody,
          cleanBodyPreview,
          storageResult.rawBodyText,
          storageResult.rawBodyPath,
          storageResult.rawBodySha256,
          storageResult.rawBodyByteLen,
          DateTime.now().toUtc().toIso8601String(),
          reviewId,
        ]);
        onReview?.call(GmailSyncReviewEvent(
          event: 'updated',
          reviewId: reviewId,
        ));
      }
    } finally {
      insertReviewStmt.dispose();
      updateReviewLlmStmt.dispose();
      updateReviewBodyStmt.dispose();
      if (lifecycle != null) {
        try {
          await lifecycle.unload();
        } catch (_) {
          // Ignore unload errors.
        }
      }
    }

    if (uids.isNotEmpty) {
      lastUid = uids.last;
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

  static List<Application> _loadApplications(Database db) {
    final rows = db.select(
      'SELECT id, company, role, jobId, portalUrl, firstSeen, lastSeen, '
      'currentStatus, confidence, accountLabel, sourceLabel, contact, '
      'nextStep, nextStepAt '
      'FROM applications;',
    );
    return rows.map(_mapApplication).toList();
  }

  static Application _mapApplication(Row row) {
    return Application(
      id: row['id'] as String,
      company: row['company'] as String,
      role: row['role'] as String,
      jobId: row['jobId'] as String?,
      appliedOn: DateTime.parse(row['firstSeen'] as String),
      lastUpdated: DateTime.parse(row['lastSeen'] as String),
      status: _parseStatus(row['currentStatus'] as String),
      confidence: (row['confidence'] as num).round(),
      account: row['accountLabel'] as String,
      source: row['sourceLabel'] as String,
      portalUrl: row['portalUrl'] as String?,
      contact: row['contact'] as String?,
      nextStep: row['nextStep'] as String?,
      nextStepAt: _parseOptionalDate(row['nextStepAt'] as String?),
    );
  }

  static ApplicationStatus _parseStatus(String value) {
    for (final status in ApplicationStatus.values) {
      if (status.name == value) {
        return status;
      }
    }
    return ApplicationStatus.applied;
  }

  static DateTime? _parseOptionalDate(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(value);
  }

  static String? _normalizeText(String? value) {
    if (value == null) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String _applicationId(String email, int uid) {
    final safe = email.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_');
    return 'gm_${safe}_$uid';
  }

  static String _reviewId(String email, int uid) {
    final safe = email.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_');
    return 'review_${safe}_$uid';
  }

  static String _cleanPreview(String value, {int maxLength = 500}) {
    final trimmed = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (trimmed.length <= maxLength) {
      return trimmed;
    }
    final slice = trimmed.substring(0, maxLength);
    final lastSpace = slice.lastIndexOf(' ');
    if (lastSpace > maxLength * 0.8) {
      return '${slice.substring(0, lastSpace)}...';
    }
    return '${slice.trimRight()}...';
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
  AppLogger.setup(
    redactMessages: false,
    logFilePath: config.logFilePath,
  );
  if (config.logFilePath != null && config.logFilePath!.isNotEmpty) {
    AppLogger.log.info('[AppLogger] Log file: ${config.logFilePath}');
  }

  void sendProgress(GmailSyncProgress progress) {
    sendPort.send({
      'type': 'progress',
      ...progress.toMap(),
    });
  }

  void sendReview(GmailSyncReviewEvent event) {
    sendPort.send({
      'type': 'review',
      ...event.toMap(),
    });
  }

  try {
    sendProgress(GmailSyncProgress(
      stage: 'start',
      processed: 0,
      total: 0,
      message: 'Connecting to Gmail',
    ));
    await GmailSyncRunner.run(
      config,
      onProgress: sendProgress,
      onReview: sendReview,
    );
    sendProgress(GmailSyncProgress(
      stage: 'done',
      processed: 0,
      total: 0,
      message: 'Sync complete',
    ));
  } catch (error) {
    sendPort.send({
      'type': 'progress',
      'stage': 'done',
      'processed': 0,
      'total': 0,
      'message': 'Sync failed: $error',
    });
  }
}
