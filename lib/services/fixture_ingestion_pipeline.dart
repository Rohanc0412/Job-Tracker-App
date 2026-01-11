import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../data/db/db.dart';
import '../data/models/application.dart';
import '../domain/ingestion/dedup.dart';
import '../domain/ingestion/parser_rules.dart';
import '../domain/ingestion/status_engine.dart';
import '../domain/status/status_types.dart';

class FixtureIngestionPipeline {
  FixtureIngestionPipeline(
    this._database, {
    String provider = 'fixture',
    bool cleanupFixtureApps = true,
  })  : _provider = provider,
        _cleanupFixtureApps = cleanupFixtureApps;

  final AppDatabase _database;
  final String _provider;
  final bool _cleanupFixtureApps;

  Future<int> run() async {
    await _database.open();
    final db = _database.rawDb;

    final emailRows = db.select(
      'SELECT id, applicationId, accountLabel, subject, evidenceSnippet, '
      'raw_body_text, fromAddr, date, extractedFieldsJson, messageId '
      'FROM email_events WHERE provider = ? ORDER BY date ASC;',
      [_provider],
    );

    final applications = _loadApplications(db);
    final appById = {for (final app in applications) app.id: app};

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
    final updateEmailStmt = db.prepare(
      'UPDATE email_events '
      'SET applicationId = ?, extractedStatus = ?, extractedFieldsJson = ?, '
      'evidenceSnippet = ?, isSignificantUpdate = ? '
      'WHERE id = ?;',
    );
    final updateInterviewStmt = db.prepare(
      'INSERT OR REPLACE INTO interview_events '
      '(id, applicationId, accountLabel, messageId, startTime, endTime, '
      'timezone, location, meetingUrl, source, confidence, createdAt) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
    );

    var processed = 0;
    for (final row in emailRows) {
      final emailId = row['id'] as String;
      final appId = row['applicationId'] as String;
      final subject = (row['subject'] as String?) ?? '';
      final body = (row['raw_body_text'] as String?) ??
          (row['evidenceSnippet'] as String?) ??
          '';
      final fromAddr = (row['fromAddr'] as String?) ?? '';
      final accountLabel = (row['accountLabel'] as String?) ?? 'Fixture';
      final date = DateTime.parse(row['date'] as String);
      final messageId = (row['messageId'] as String?) ?? emailId;
      final extractedFields = _decodeFields(row['extractedFieldsJson'] as String?);
      final ics = extractedFields['ics'] as String?;

      final extractionText =
          ics == null ? '$subject\n$body' : '$subject\n$body\n$ics';
      final urls = extractUrls(extractionText);
      final portalUrl = selectPortalUrl(urls);
      final jobId = extractJobId(extractionText, portalUrl: portalUrl);
      final company = extractCompany(subject, body, fromAddr);
      final role = extractRole(subject, body);

      final classification = classifyStatus(subject, body);
      final shouldParseInterview =
          classification.status == ApplicationStatus.interview || ics != null;
      final interviewSchedule = shouldParseInterview
          ? _extractInterviewSchedule(
              subject: subject,
              body: body,
              icsPayload: ics,
              emailDate: date,
            )
          : null;
      final incoming = ExtractedApplicationData(
        jobId: jobId,
        portalUrl: portalUrl,
        company: company,
        role: role,
      );

      final match = matchApplication(applications, incoming);
      final selectedAppId = match?.id ?? appId;
      final currentApp =
          appById[selectedAppId] ?? _createApplication(selectedAppId, accountLabel, date);
      DateTime? nextStepAt;
      String? nextStep;
      if (interviewSchedule != null) {
        nextStepAt =
            _mergeNextStepAt(currentApp.nextStepAt, interviewSchedule.start);
        nextStep = 'Interview scheduled';
      }
      final decision = applyMonotonicTransition(
        currentStatus: currentApp.status,
        currentConfidence: currentApp.confidence,
        incoming: classification,
      );

      final updated = currentApp.copyWith(
        company: company ?? currentApp.company,
        role: role ?? currentApp.role,
        jobId: jobId ?? currentApp.jobId,
        portalUrl: portalUrl ?? currentApp.portalUrl,
        appliedOn: _minDate(currentApp.appliedOn, date),
        lastUpdated: _maxDate(currentApp.lastUpdated, date),
        status: decision.status,
        confidence: decision.confidence,
        account: currentApp.account.isEmpty ? accountLabel : currentApp.account,
        source: currentApp.source.isEmpty ? 'Fixture' : currentApp.source,
        nextStep: nextStep,
        nextStepAt: nextStepAt,
      );

      _upsertApplication(updateAppStmt, updated);
      appById[selectedAppId] = updated;
      final index = applications.indexWhere((app) => app.id == selectedAppId);
      if (index == -1) {
        applications.add(updated);
      } else {
        applications[index] = updated;
      }

      final statusChanged =
          decision.changed && decision.status != currentApp.status;
      final isSignificant =
          statusChanged || _isSignificantStatus(classification.status);

      extractedFields['company'] = company;
      extractedFields['role'] = role;
      extractedFields['portalUrl'] = portalUrl;
      extractedFields['jobId'] = jobId;
      extractedFields['status'] = classification.status.name;
      extractedFields['confidence'] = classification.confidence;
      if (interviewSchedule != null) {
        extractedFields['interviewStart'] =
            interviewSchedule.start.toIso8601String();
        if (interviewSchedule.end != null) {
          extractedFields['interviewEnd'] =
              interviewSchedule.end!.toIso8601String();
        }
        if (interviewSchedule.timezone != null) {
          extractedFields['interviewTimezone'] = interviewSchedule.timezone;
        }
      }

      final snippet = _truncate(body, 160);
      updateEmailStmt.execute([
        selectedAppId,
        classification.status.name,
        jsonEncode(extractedFields),
        snippet,
        isSignificant ? 1 : 0,
        emailId,
      ]);
      if (interviewSchedule != null) {
        _upsertInterviewEvent(
          updateInterviewStmt,
          interviewSchedule,
          emailId: emailId,
          applicationId: selectedAppId,
          accountLabel: accountLabel,
          messageId: messageId,
          createdAt: date,
        );
      }

      processed++;
    }

    updateAppStmt.dispose();
    updateEmailStmt.dispose();
    updateInterviewStmt.dispose();

    if (_cleanupFixtureApps) {
      db.execute(
        "DELETE FROM applications WHERE id LIKE 'fx_%' "
        'AND id NOT IN (SELECT DISTINCT applicationId FROM email_events);',
      );
    }

    return processed;
  }

  List<Application> _loadApplications(Database db) {
    final rows = db.select(
      'SELECT id, company, role, jobId, portalUrl, firstSeen, lastSeen, '
      'currentStatus, confidence, accountLabel, sourceLabel, contact, '
      'nextStep, nextStepAt '
      'FROM applications;',
    );
    return rows.map(_mapApplication).toList();
  }

  Application _mapApplication(Row row) {
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
      nextStepAt: _parseDate(row['nextStepAt'] as String?),
    );
  }

  Application _createApplication(String id, String accountLabel, DateTime date) {
    return Application(
      id: id,
      company: 'Unknown Company',
      role: 'Unknown Role',
      appliedOn: date,
      lastUpdated: date,
      status: ApplicationStatus.applied,
      confidence: 40,
      account: accountLabel,
      source: 'Fixture',
    );
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
    PreparedStatement stmt,
    _InterviewSchedule schedule, {
    required String emailId,
    required String applicationId,
    required String accountLabel,
    required String messageId,
    required DateTime createdAt,
  }) {
    stmt.execute([
      'fx_iv_$emailId',
      applicationId,
      accountLabel,
      messageId,
      schedule.start.toIso8601String(),
      schedule.end?.toIso8601String(),
      schedule.timezone,
      schedule.location,
      schedule.meetingUrl,
      'Fixture',
      schedule.confidence,
      createdAt.toIso8601String(),
    ]);
  }

  _InterviewSchedule? _extractInterviewSchedule({
    required String subject,
    required String body,
    required String? icsPayload,
    required DateTime emailDate,
  }) {
    if (icsPayload != null) {
      final schedule = _parseIcsSchedule(icsPayload);
      if (schedule != null) {
        return schedule;
      }
    }
    return _parseTextSchedule('$subject\n$body', emailDate);
  }

  _InterviewSchedule? _parseIcsSchedule(String icsPayload) {
    final startField = _findIcsDateField(icsPayload, 'DTSTART');
    if (startField == null) {
      return null;
    }
    final endField = _findIcsDateField(icsPayload, 'DTEND');
    final start = _parseIcsDateTime(startField.value,
        tzid: startField.timezone, isUtc: startField.isUtc);
    if (start == null) {
      return null;
    }
    final end = endField == null
        ? null
        : _parseIcsDateTime(endField.value,
            tzid: endField.timezone, isUtc: endField.isUtc);
    final summary = _findIcsTextField(icsPayload, 'SUMMARY');
    final location = _findIcsTextField(icsPayload, 'LOCATION');
    final meetingUrl = _findIcsTextField(icsPayload, 'URL');
    return _InterviewSchedule(
      start: start,
      end: end,
      timezone: startField.timezone ?? (startField.isUtc ? 'UTC' : null),
      location: location ?? summary,
      meetingUrl: meetingUrl,
      confidence: 0.9,
    );
  }

  _IcsDateField? _findIcsDateField(String icsPayload, String key) {
    final regex = RegExp(
      '^$key(?:;TZID=([^:]+))?:(\\d{8}T\\d{4,6}Z?)',
      caseSensitive: false,
      multiLine: true,
    );
    final match = regex.firstMatch(icsPayload);
    if (match == null) {
      return null;
    }
    final value = match.group(2);
    if (value == null) {
      return null;
    }
    return _IcsDateField(
      value: value,
      timezone: match.group(1),
      isUtc: value.endsWith('Z'),
    );
  }

  String? _findIcsTextField(String icsPayload, String key) {
    final regex = RegExp(
      '^$key:(.+)\$',
      caseSensitive: false,
      multiLine: true,
    );
    final match = regex.firstMatch(icsPayload);
    return match?.group(1)?.trim();
  }

  DateTime? _parseIcsDateTime(String value,
      {String? tzid, required bool isUtc}) {
    var raw = value;
    if (raw.endsWith('Z')) {
      raw = raw.substring(0, raw.length - 1);
    }
    if (raw.length < 13 || !raw.contains('T')) {
      return null;
    }
    final year = int.tryParse(raw.substring(0, 4));
    final month = int.tryParse(raw.substring(4, 6));
    final day = int.tryParse(raw.substring(6, 8));
    final hour = int.tryParse(raw.substring(9, 11));
    final minute = int.tryParse(raw.substring(11, 13));
    final second =
        raw.length >= 15 ? int.tryParse(raw.substring(13, 15)) : 0;
    if (year == null ||
        month == null ||
        day == null ||
        hour == null ||
        minute == null ||
        second == null) {
      return null;
    }
    final dateTime = isUtc
        ? DateTime.utc(year, month, day, hour, minute, second)
        : DateTime(year, month, day, hour, minute, second);
    if (isUtc) {
      return dateTime.toLocal();
    }
    if (tzid != null) {
      final offset = _tzOffsetHours(tzid);
      if (offset != null) {
        return DateTime.utc(year, month, day, hour - offset, minute, second)
            .toLocal();
      }
    }
    return dateTime;
  }

  _InterviewSchedule? _parseTextSchedule(String text, DateTime emailDate) {
    final matches = _interviewTextPattern.allMatches(text);
    if (matches.isEmpty) {
      return null;
    }
    final candidates = <DateTime>[];
    String? timezone;
    for (final match in matches) {
      final monthToken = match.group(1);
      final dayToken = match.group(2);
      final hourToken = match.group(3);
      final minuteToken = match.group(4);
      final meridiem = match.group(5);
      final tzToken = match.group(6);
      final month = _monthFromToken(monthToken);
      if (month == null ||
          dayToken == null ||
          hourToken == null ||
          minuteToken == null ||
          meridiem == null) {
        continue;
      }
      var hour = int.parse(hourToken);
      final minute = int.parse(minuteToken);
      final day = int.parse(dayToken);
      final meridiemUpper = meridiem.toUpperCase();
      if (meridiemUpper == 'PM' && hour < 12) {
        hour += 12;
      } else if (meridiemUpper == 'AM' && hour == 12) {
        hour = 0;
      }
      final candidate = _buildLocalDateTime(
        emailDate.year,
        month,
        day,
        hour,
        minute,
        tzToken,
      );
      if (candidate != null) {
        candidates.add(candidate);
        timezone ??= tzToken;
      }
    }
    if (candidates.isEmpty) {
      return null;
    }
    candidates.sort((a, b) => a.compareTo(b));
    return _InterviewSchedule(
      start: candidates.first,
      end: null,
      timezone: timezone?.toUpperCase(),
      location: null,
      meetingUrl: null,
      confidence: 0.6,
    );
  }

  DateTime? _buildLocalDateTime(
    int year,
    int month,
    int day,
    int hour,
    int minute,
    String? timezone,
  ) {
    if (timezone != null) {
      final offset = _tzOffsetHours(timezone);
      if (offset != null) {
        return DateTime.utc(year, month, day, hour - offset, minute)
            .toLocal();
      }
    }
    return DateTime(year, month, day, hour, minute);
  }

  int? _monthFromToken(String? token) {
    if (token == null) {
      return null;
    }
    switch (token.toLowerCase()) {
      case 'jan':
        return 1;
      case 'feb':
        return 2;
      case 'mar':
        return 3;
      case 'apr':
        return 4;
      case 'may':
        return 5;
      case 'jun':
        return 6;
      case 'jul':
        return 7;
      case 'aug':
        return 8;
      case 'sep':
      case 'sept':
        return 9;
      case 'oct':
        return 10;
      case 'nov':
        return 11;
      case 'dec':
        return 12;
    }
    return null;
  }

  int? _tzOffsetHours(String token) {
    switch (token.toUpperCase()) {
      case 'UTC':
      case 'GMT':
        return 0;
      case 'ET':
      case 'EST':
        return -5;
      case 'EDT':
        return -4;
      case 'CT':
      case 'CST':
        return -6;
      case 'CDT':
        return -5;
      case 'MT':
      case 'MST':
        return -7;
      case 'MDT':
        return -6;
      case 'PT':
      case 'PST':
        return -8;
      case 'PDT':
        return -7;
    }
    return null;
  }

  DateTime _mergeNextStepAt(DateTime? existing, DateTime candidate) {
    if (existing == null) {
      return candidate;
    }
    return candidate.isBefore(existing) ? candidate : existing;
  }

  ApplicationStatus _parseStatus(String value) {
    for (final status in ApplicationStatus.values) {
      if (status.name == value) {
        return status;
      }
    }
    return ApplicationStatus.applied;
  }

  DateTime _minDate(DateTime a, DateTime b) {
    return a.isBefore(b) ? a : b;
  }

  DateTime _maxDate(DateTime a, DateTime b) {
    return a.isAfter(b) ? a : b;
  }

  DateTime? _parseDate(String? value) {
    if (value == null) {
      return null;
    }
    return DateTime.tryParse(value);
  }

  Map<String, dynamic> _decodeFields(String? value) {
    if (value == null || value.trim().isEmpty) {
      return <String, dynamic>{};
    }
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      // Ignore malformed JSON.
    }
    return <String, dynamic>{};
  }

  bool _isSignificantStatus(ApplicationStatus status) {
    return status == ApplicationStatus.applied ||
        status == ApplicationStatus.interview ||
        status == ApplicationStatus.assessment ||
        status == ApplicationStatus.offer ||
        status == ApplicationStatus.rejected;
  }

  String _truncate(String value, int maxLength) {
    final trimmed = value.trim();
    if (trimmed.length <= maxLength) {
      return trimmed;
    }
    return '${trimmed.substring(0, maxLength - 3).trimRight()}...';
  }

}

class _InterviewSchedule {
  final DateTime start;
  final DateTime? end;
  final String? timezone;
  final String? location;
  final String? meetingUrl;
  final double confidence;

  const _InterviewSchedule({
    required this.start,
    this.end,
    this.timezone,
    this.location,
    this.meetingUrl,
    required this.confidence,
  });
}

class _IcsDateField {
  final String value;
  final String? timezone;
  final bool isUtc;

  const _IcsDateField({
    required this.value,
    required this.timezone,
    required this.isUtc,
  });
}

final RegExp _interviewTextPattern = RegExp(
  r'(?:'
  r'(?:Mon(?:day)?|Tue(?:sday)?|Wed(?:nesday)?|Thu(?:rsday)?|Fri(?:day)?|Sat(?:urday)?|Sun(?:day)?)'
  r',?\s+'
  r')?'
  r'(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)\s+'
  r'(\d{1,2})\s+at\s+'
  r'(\d{1,2}):(\d{2})\s*'
  r'(AM|PM)\s*'
  r'([A-Za-z]{2,4})?',
  caseSensitive: false,
);
