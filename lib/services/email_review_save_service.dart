import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';

import '../data/db/db.dart';
import '../data/models/application.dart';
import '../data/models/email_review_item.dart';
import '../domain/ingestion/status_engine.dart';
import '../domain/status/status_types.dart';

class EmailReviewSaveService {
  EmailReviewSaveService(this._database);

  final AppDatabase _database;

  Future<String> saveReview({
    required EmailReviewItem item,
    required Map<String, dynamic> overrides,
    required String? selectedApplicationId,
    required bool forceNewApplication,
  }) async {
    await _database.open();
    final db = _database.rawDb;

    _ensureAccount(db, item.accountLabel);

    final llm = item.llmData;
    final subject =
        _resolveString(overrides, llm, 'subject') ?? item.subject;
    final company =
        _resolveString(overrides, llm, 'company') ?? 'Unknown Company';
    final role = _resolveString(overrides, llm, 'role') ?? 'Unknown Role';
    final jobId = _resolveString(overrides, llm, 'jobId');
    final portalUrl = _resolveString(overrides, llm, 'portalUrl');
    final statusValue = _resolveString(overrides, llm, 'status');
    final summary =
        _resolveString(overrides, llm, 'summary') ?? subject;
    final source =
        _resolveString(overrides, llm, 'source') ?? 'Gmail';
    final actionRequired =
        _resolveBool(overrides, llm, 'actionRequired') ?? false;
    final actionItems = _resolveStringList(overrides, llm, 'actionItems');

    final interview = _resolveMap(overrides, llm, 'interview');
    final interviewStart = _parseDate(interview['start']);
    final interviewEnd = _parseDate(interview['end']);
    final interviewTz = _parseString(interview['timezone']);
    final interviewLocation = _parseString(interview['location']);
    final interviewMeeting = _parseString(interview['meetingUrl']);

    final originalFromEmail =
        _resolveString(overrides, llm, 'originalFromEmail');
    final originalToEmails =
        _resolveStringList(overrides, llm, 'originalToEmails');
    final evidence = _resolveMapList(overrides, llm, 'evidence');

    final appId = forceNewApplication
        ? _fallbackApplicationId(item)
        : (selectedApplicationId ??
            item.suggestedApplicationId ??
            _fallbackApplicationId(item));

    final currentApp = _loadApplicationById(db, appId) ??
        _createApplication(appId, item.accountLabel, item.date);

    final incomingStatus = _mapLlmStatus(statusValue);
    final llmConfidence = _parseDouble(llm['confidence']) ?? 0.0;
    final hasUserStatus = overrides['status'] is String &&
        (overrides['status'] as String).trim().isNotEmpty;
    final decision = incomingStatus == null
        ? StatusDecision(
            status: currentApp.status,
            confidence: currentApp.confidence,
            changed: false,
          )
        : applyMonotonicTransition(
            currentStatus: currentApp.status,
            currentConfidence: currentApp.confidence,
            incoming: StatusClassification(
              status: incomingStatus,
              confidence: hasUserStatus
                  ? 95
                  : (llmConfidence * 100).round(),
              strongEvidence: hasUserStatus || llmConfidence >= 0.85,
            ),
          );

    DateTime? nextStepAt;
    String? nextStep;
    if (interviewStart != null) {
      nextStepAt = _mergeNextStepAt(currentApp.nextStepAt, interviewStart);
      nextStep = 'Interview scheduled';
    }

    final updated = currentApp.copyWith(
      company: company,
      role: role,
      jobId: jobId ?? currentApp.jobId,
      portalUrl: portalUrl ?? currentApp.portalUrl,
      appliedOn: _minDate(currentApp.appliedOn, item.date),
      lastUpdated: _maxDate(currentApp.lastUpdated, item.date),
      status: decision.status,
      confidence: decision.confidence,
      account: currentApp.account.isEmpty
          ? item.accountLabel
          : currentApp.account,
      source: currentApp.source.isEmpty ? source : currentApp.source,
      nextStep: nextStep,
      nextStepAt: nextStepAt,
    );

    final updateAppStmt = db.prepare(
      'INSERT INTO applications (id, company, role, jobId, portalUrl, firstSeen, '
      'lastSeen, currentStatus, confidence, accountLabel, sourceLabel, contact, '
      'nextStep, nextStepAt) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT(id) DO UPDATE SET '
      'company = excluded.company, role = excluded.role, jobId = excluded.jobId, '
      'portalUrl = excluded.portalUrl, firstSeen = excluded.firstSeen, '
      'lastSeen = excluded.lastSeen, currentStatus = excluded.currentStatus, '
      'confidence = excluded.confidence, accountLabel = excluded.accountLabel, '
      'sourceLabel = excluded.sourceLabel, contact = excluded.contact, '
      'nextStep = excluded.nextStep, nextStepAt = excluded.nextStepAt;',
    );

    final insertEmailStmt = db.prepare(
      'INSERT OR IGNORE INTO email_events (id, applicationId, accountLabel, '
      'provider, folder, cursorValue, messageId, subject, fromAddr, date, '
      'extractedStatus, extractedFieldsJson, raw_body_text, raw_body_path, '
      'raw_body_sha256, raw_body_byte_len, llm_category, llm_confidence, '
      'llm_summary, llm_status, llm_company, llm_role, llm_job_id, '
      'llm_portal_url, llm_interview_start, llm_interview_end, '
      'llm_interview_tz, llm_interview_location, llm_meeting_url, '
      'llm_original_from_email, llm_original_to_emails_json, '
      'llm_evidence_json, llm_action_items_json, hash, isSignificantUpdate) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '
      '?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
    );

    final upsertInterviewStmt = db.prepare(
      'INSERT OR REPLACE INTO interview_events '
      '(id, applicationId, accountLabel, messageId, startTime, endTime, '
      'timezone, location, meetingUrl, source, confidence, createdAt) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
    );

    try {
      _upsertApplication(updateAppStmt, updated);

      final cursorValue = item.cursorValue ?? '';
      final emailId = cursorValue.isEmpty
          ? 'gmail_${item.messageId.hashCode}'
          : 'gmail_$cursorValue';
      final hash = sha256
          .convert(
              utf8.encode('${item.messageId}|${item.fromAddr}|$subject|$cursorValue'))
          .toString();
      final extractedStatus = _mapStatusLabel(statusValue);
      final evidenceJson = jsonEncode(evidence);
      final actionItemsJson = jsonEncode(actionItems);
      final originalToEmailsJson = jsonEncode(originalToEmails);

      insertEmailStmt.execute([
        emailId,
        appId,
        item.accountLabel,
        item.provider,
        item.folder,
        cursorValue,
        item.messageId,
        subject,
        item.fromAddr,
        item.date.toIso8601String(),
        extractedStatus,
        null,
        item.rawBodyText,
        item.rawBodyPath,
        item.rawBodySha256,
        item.rawBodyByteLen,
        _parseString(llm['category']),
        llmConfidence,
        summary,
        statusValue,
        company,
        role,
        jobId,
        portalUrl,
        interviewStart?.toIso8601String(),
        interviewEnd?.toIso8601String(),
        interviewTz,
        interviewLocation,
        interviewMeeting,
        originalFromEmail,
        originalToEmailsJson,
        evidenceJson,
        actionItemsJson,
        hash,
        1,
      ]);

      if (interviewStart != null) {
        _upsertInterviewEvent(
          upsertInterviewStmt,
          emailId: emailId,
          applicationId: appId,
          accountLabel: item.accountLabel,
          messageId: item.messageId,
          start: interviewStart,
          end: interviewEnd,
          timezone: interviewTz,
          location: interviewLocation,
          meetingUrl: interviewMeeting,
          confidence: llmConfidence,
          createdAt: item.date,
        );
      }
    } finally {
      updateAppStmt.dispose();
      insertEmailStmt.dispose();
      upsertInterviewStmt.dispose();
    }

    return appId;
  }
}

String _fallbackApplicationId(EmailReviewItem item) {
  final safe = item.accountLabel.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_');
  final cursorValue = item.cursorValue ?? 'unknown';
  return 'gm_${safe}_$cursorValue';
}

void _upsertApplication(PreparedStatement stmt, Application app) {
  stmt.execute([
    app.id,
    app.company,
    app.role,
    app.jobId,
    app.portalUrl,
    app.appliedOn.toIso8601String(),
    app.lastUpdated.toIso8601String(),
    app.status.name,
    app.confidence.toDouble(),
    app.account,
    app.source,
    app.contact,
    app.nextStep,
    app.nextStepAt?.toIso8601String(),
  ]);
}

void _upsertInterviewEvent(
  PreparedStatement stmt, {
  required String emailId,
  required String applicationId,
  required String accountLabel,
  required String messageId,
  required DateTime start,
  required DateTime? end,
  required String? timezone,
  required String? location,
  required String? meetingUrl,
  required double confidence,
  required DateTime createdAt,
}) {
  stmt.execute([
    'review_iv_$emailId',
    applicationId,
    accountLabel,
    messageId,
    start.toIso8601String(),
    end?.toIso8601String(),
    timezone,
    location,
    meetingUrl,
    'Review',
    confidence,
    createdAt.toIso8601String(),
  ]);
}

Application? _loadApplicationById(Database db, String id) {
  final rows = db.select(
    'SELECT id, company, role, jobId, portalUrl, firstSeen, lastSeen, '
    'currentStatus, confidence, accountLabel, sourceLabel, contact, '
    'nextStep, nextStepAt '
    'FROM applications WHERE id = ?;',
    [id],
  );
  if (rows.isEmpty) {
    return null;
  }
  final row = rows.first;
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

Application _createApplication(
  String id,
  String accountLabel,
  DateTime date,
) {
  return Application(
    id: id,
    company: 'Unknown Company',
    role: 'Unknown Role',
    appliedOn: date,
    lastUpdated: date,
    status: ApplicationStatus.applied,
    confidence: 40,
    account: accountLabel,
    source: 'Gmail',
  );
}

ApplicationStatus _parseStatus(String value) {
  for (final status in ApplicationStatus.values) {
    if (status.name == value) {
      return status;
    }
  }
  return ApplicationStatus.applied;
}

ApplicationStatus? _mapLlmStatus(String? value) {
  switch (value) {
    case 'applied':
      return ApplicationStatus.applied;
    case 'under_review':
      return ApplicationStatus.underReview;
    case 'assessment':
      return ApplicationStatus.assessment;
    case 'interview':
      return ApplicationStatus.interview;
    case 'offer':
      return ApplicationStatus.offer;
    case 'rejected':
      return ApplicationStatus.rejected;
  }
  return null;
}

String? _mapStatusLabel(String? value) {
  switch (value) {
    case 'applied':
      return 'applied';
    case 'under_review':
      return 'underReview';
    case 'assessment':
      return 'assessment';
    case 'interview':
      return 'interview';
    case 'offer':
      return 'offer';
    case 'rejected':
      return 'rejected';
  }
  return null;
}

DateTime? _parseDate(Object? value) {
  if (value is String && value.trim().isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}

DateTime? _parseOptionalDate(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  return DateTime.tryParse(value);
}

DateTime _minDate(DateTime a, DateTime b) {
  return a.isBefore(b) ? a : b;
}

DateTime _maxDate(DateTime a, DateTime b) {
  return a.isAfter(b) ? a : b;
}

DateTime _mergeNextStepAt(DateTime? existing, DateTime candidate) {
  if (existing == null) {
    return candidate;
  }
  return candidate.isBefore(existing) ? candidate : existing;
}

void _ensureAccount(Database db, String email) {
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

String? _resolveString(
  Map<String, dynamic> overrides,
  Map<String, dynamic> llm,
  String key,
) {
  final override = overrides[key];
  if (override is String && override.trim().isNotEmpty) {
    return override;
  }
  final llmValue = llm[key];
  if (llmValue is String && llmValue.trim().isNotEmpty) {
    return llmValue;
  }
  return null;
}

bool? _resolveBool(
  Map<String, dynamic> overrides,
  Map<String, dynamic> llm,
  String key,
) {
  final override = overrides[key];
  if (override is bool) {
    return override;
  }
  final llmValue = llm[key];
  if (llmValue is bool) {
    return llmValue;
  }
  return null;
}

List<String> _resolveStringList(
  Map<String, dynamic> overrides,
  Map<String, dynamic> llm,
  String key,
) {
  final override = overrides[key];
  final overrideList = _parseStringList(override);
  if (overrideList.isNotEmpty) {
    return overrideList;
  }
  return _parseStringList(llm[key]);
}

Map<String, dynamic> _resolveMap(
  Map<String, dynamic> overrides,
  Map<String, dynamic> llm,
  String key,
) {
  final override = overrides[key];
  if (override is Map<String, dynamic>) {
    return Map<String, dynamic>.from(override);
  }
  final llmValue = llm[key];
  if (llmValue is Map<String, dynamic>) {
    return Map<String, dynamic>.from(llmValue);
  }
  return <String, dynamic>{};
}

List<Map<String, dynamic>> _resolveMapList(
  Map<String, dynamic> overrides,
  Map<String, dynamic> llm,
  String key,
) {
  final override = overrides[key];
  final overrideList = _parseMapList(override);
  if (overrideList.isNotEmpty) {
    return overrideList;
  }
  return _parseMapList(llm[key]);
}

String? _parseString(Object? value) {
  if (value is String) {
    return value;
  }
  return null;
}

double? _parseDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return null;
}

List<String> _parseStringList(Object? value) {
  if (value is List) {
    return value.whereType<String>().toList();
  }
  return <String>[];
}

List<Map<String, dynamic>> _parseMapList(Object? value) {
  if (value is List) {
    final result = <Map<String, dynamic>>[];
    for (final item in value) {
      if (item is Map<String, dynamic>) {
        result.add(Map<String, dynamic>.from(item));
      }
    }
    return result;
  }
  return <Map<String, dynamic>>[];
}
