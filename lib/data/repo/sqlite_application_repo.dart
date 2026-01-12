import 'package:sqlite3/sqlite3.dart';

import '../../domain/status/status_types.dart';
import '../db/db.dart';
import '../models/activity_item.dart';
import '../models/application.dart';
import 'application_repo.dart';

class SqliteApplicationRepo implements ApplicationRepo {
  final AppDatabase _database;
  final DateTime Function() _clock;

  SqliteApplicationRepo(
    this._database, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  Future<Database> _db() async {
    await _database.open();
    return _database.rawDb;
  }

  @override
  Future<List<Application>> listApplications() async {
    final db = await _db();
    final rows = db.select(
      'SELECT id, company, role, jobId, portalUrl, firstSeen, lastSeen, '
      'currentStatus, confidence, accountLabel, sourceLabel, contact, nextStep, nextStepAt '
      'FROM applications ORDER BY lastSeen DESC;',
    );
    return rows.map(_mapApplication).toList();
  }

  @override
  Future<List<ActivityItem>> listRecentUpdates({int limit = 12}) async {
    final db = await _db();
    final rows = db.select(
      'SELECT e.subject, e.evidenceSnippet, e.date, e.extractedStatus, '
      'a.company, e.applicationId, e.raw_body_text, e.raw_body_path '
      'FROM email_events e '
      'LEFT JOIN applications a ON a.id = e.applicationId '
      'WHERE e.isSignificantUpdate = 1 '
      'ORDER BY e.date DESC LIMIT ?;',
      [limit],
    );
    return rows.map(_mapEmailActivity).toList();
  }

  @override
  Future<List<ActivityItem>> listUpcomingInterviews({int days = 14}) async {
    final db = await _db();
    final now = _clock();
    final nowIso = now.toIso8601String();
    final endIso = now.add(Duration(days: days)).toIso8601String();
    final rows = db.select(
      'SELECT i.startTime, a.company, a.role, i.applicationId, i.timezone '
      'FROM interview_events i '
      'LEFT JOIN applications a ON a.id = i.applicationId '
      'WHERE i.startTime >= ? AND i.startTime <= ? '
      'ORDER BY i.startTime ASC;',
      [nowIso, endIso],
    );
    return rows.map(_mapInterviewActivity).toList();
  }

  @override
  Future<List<ActivityItem>> listTimeline(String applicationId) async {
    final db = await _db();
    print('[Repo] listTimeline for applicationId: $applicationId');
    final emailRows = db.select(
      'SELECT id, subject, evidenceSnippet, date, extractedStatus, raw_body_text, raw_body_path '
      'FROM email_events WHERE applicationId = ?;',
      [applicationId],
    );
    print('[Repo] Found ${emailRows.length} emails for this application');
    for (final row in emailRows) {
      final emailId = row['id'] as String;
      final subject = row['subject'] as String;
      final bodyLen = (row['raw_body_text'] as String?)?.length ?? 0;
      print('[Repo]   - Email $emailId: "$subject" (body: $bodyLen bytes)');
    }

    final interviewRows = db.select(
      'SELECT startTime, location, meetingUrl, timezone '
      'FROM interview_events WHERE applicationId = ?;',
      [applicationId],
    );

    final timeline = <ActivityItem>[
      ...emailRows.map(_mapEmailTimeline),
      ...interviewRows.map(_mapInterviewTimeline),
    ];
    timeline.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return timeline;
  }

  @override
  Future<void> upsert(Application application) async {
    final db = await _db();
    db.execute(
      'INSERT INTO applications (id, company, role, jobId, portalUrl, firstSeen, lastSeen, '
      'currentStatus, confidence, accountLabel, sourceLabel, contact, nextStep, nextStepAt) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT(id) DO UPDATE SET '
      'company = excluded.company, '
      'role = excluded.role, '
      'jobId = excluded.jobId, '
      'portalUrl = excluded.portalUrl, '
      'firstSeen = excluded.firstSeen, '
      'lastSeen = excluded.lastSeen, '
      'currentStatus = excluded.currentStatus, '
      'confidence = excluded.confidence, '
      'accountLabel = excluded.accountLabel, '
      'sourceLabel = excluded.sourceLabel, '
      'contact = excluded.contact, '
      'nextStep = excluded.nextStep, '
      'nextStepAt = excluded.nextStepAt;',
      [
        application.id,
        application.company,
        application.role,
        application.jobId,
        application.portalUrl,
        application.appliedOn.toIso8601String(),
        application.lastUpdated.toIso8601String(),
        application.status.name,
        application.confidence.toDouble(),
        application.account,
        application.source,
        application.contact,
        application.nextStep,
        application.nextStepAt?.toIso8601String(),
      ],
    );
  }

  @override
  Future<void> delete(String id) async {
    final db = await _db();
    db.execute('DELETE FROM applications WHERE id = ?;', [id]);
  }

  Application _mapApplication(Row row) {
    return Application(
      id: row['id'] as String,
      company: row['company'] as String,
      role: row['role'] as String,
      jobId: row['jobId'] as String?,
      appliedOn: DateTime.parse(row['firstSeen'] as String),
      lastUpdated: DateTime.parse(row['lastSeen'] as String),
      status: _statusFromDb(row['currentStatus'] as String),
      confidence: (row['confidence'] as num).round(),
      account: row['accountLabel'] as String,
      source: row['sourceLabel'] as String,
      portalUrl: row['portalUrl'] as String?,
      contact: row['contact'] as String?,
      nextStep: row['nextStep'] as String?,
      nextStepAt: _parseDate(row['nextStepAt'] as String?),
    );
  }

  ActivityItem _mapEmailActivity(Row row) {
    final status = row['extractedStatus'] as String?;
    final company = row['company'] as String?;
    final title = _activityTitle(company, status, row['subject'] as String);
    final detail =
        (row['evidenceSnippet'] as String?) ?? (row['subject'] as String);
    return ActivityItem(
      title: title,
      detail: detail,
      timestamp: DateTime.parse(row['date'] as String),
      kind: _kindFromStatus(status),
      applicationId: row['applicationId'] as String?,
      rawBodyText: row['raw_body_text'] as String?,
      rawBodyPath: row['raw_body_path'] as String?,
    );
  }

  ActivityItem _mapInterviewActivity(Row row) {
    final company = row['company'] as String?;
    final role = row['role'] as String?;
    return ActivityItem(
      title: company ?? 'Interview',
      detail: role ?? 'Interview scheduled',
      timestamp: DateTime.parse(row['startTime'] as String),
      kind: ActivityKind.interview,
      applicationId: row['applicationId'] as String?,
      timezone: row['timezone'] as String?,
    );
  }

  ActivityItem _mapEmailTimeline(Row row) {
    final status = row['extractedStatus'] as String?;
    final subject = row['subject'] as String;
    return ActivityItem(
      title: subject,
      detail: (row['evidenceSnippet'] as String?) ?? subject,
      timestamp: DateTime.parse(row['date'] as String),
      kind: _kindFromStatus(status),
      rawBodyText: row['raw_body_text'] as String?,
      rawBodyPath: row['raw_body_path'] as String?,
    );
  }

  ActivityItem _mapInterviewTimeline(Row row) {
    final start = DateTime.parse(row['startTime'] as String);
    final detail =
        (row['location'] as String?) ?? (row['meetingUrl'] as String?);
    return ActivityItem(
      title: 'Interview scheduled',
      detail: detail ?? 'Interview scheduled',
      timestamp: start,
      kind: ActivityKind.interview,
      timezone: row['timezone'] as String?,
    );
  }

  ActivityKind _kindFromStatus(String? status) {
    switch (status) {
      case 'interview':
        return ActivityKind.interview;
      case 'offer':
        return ActivityKind.offer;
      case 'rejected':
        return ActivityKind.rejection;
      default:
        return ActivityKind.update;
    }
  }

  ApplicationStatus _statusFromDb(String value) {
    for (final status in ApplicationStatus.values) {
      if (status.name == value) {
        return status;
      }
    }
    return ApplicationStatus.applied;
  }

  DateTime? _parseDate(String? value) {
    if (value == null) {
      return null;
    }
    return DateTime.parse(value);
  }

  String _activityTitle(String? company, String? status, String fallback) {
    if (company == null) {
      return fallback;
    }
    return '$company - ${_statusLabel(status)}';
  }

  String _statusLabel(String? status) {
    switch (status) {
      case 'assessment':
        return 'Assessment';
      case 'interview':
        return 'Interview';
      case 'offer':
        return 'Offer';
      case 'underReview':
        return 'Under Review';
      case 'received':
        return 'Received';
      case 'rejected':
        return 'Rejected';
      case 'applied':
        return 'Applied';
      default:
        return 'Update';
    }
  }
}
