import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../data/db/db.dart';
import '../domain/status/status_types.dart';

class FixtureApplication {
  final String id;
  final String company;
  final String role;
  final String accountLabel;

  const FixtureApplication({
    required this.id,
    required this.company,
    required this.role,
    required this.accountLabel,
  });
}

class FixtureMessage {
  final String fileName;
  final String applicationId;

  const FixtureMessage({
    required this.fileName,
    required this.applicationId,
  });
}

class ParsedEmail {
  final String from;
  final String to;
  final String subject;
  final String messageId;
  final DateTime date;
  final String body;
  final String? icsPayload;

  const ParsedEmail({
    required this.from,
    required this.to,
    required this.subject,
    required this.messageId,
    required this.date,
    required this.body,
    this.icsPayload,
  });
}

class FixtureLoader {
  FixtureLoader(
    this._database, {
    AssetBundle? bundle,
  }) : _bundle = bundle ?? rootBundle;

  static const String fixturePrefix = 'assets/eml_fixtures/';
  static const int evidenceMaxLength = 160;

  final AppDatabase _database;
  final AssetBundle _bundle;

  Future<List<String>> listFixturePaths() async {
    final manifest = await AssetManifest.loadFromAssetBundle(_bundle);
    final paths = manifest
        .listAssets()
        .where((path) =>
            path.startsWith(fixturePrefix) && path.endsWith('.eml'))
        .toList()
      ..sort();
    return paths;
  }

  Future<int> loadFixtures({bool clearExisting = false}) async {
    await _database.open();
    final db = _database.rawDb;
    if (clearExisting) {
      _clearFixtureData(db);
    }

    final paths = await listFixturePaths();
    final byName = {
      for (final message in _fixtureMessages) message.fileName: message
    };

    final emails = <_FixtureEmail>[];
    for (final path in paths) {
      final name = p.basename(path);
      final meta = byName[name];
      if (meta == null) {
        continue;
      }
      final raw = await _bundle.loadString(path);
      final parsed = _parseEmail(raw);
      emails.add(_FixtureEmail(
        fileName: name,
        applicationId: meta.applicationId,
        parsed: parsed,
      ));
    }

    _upsertApplications(db, emails);
    final inserted = _insertEmailEvents(db, emails);
    return inserted;
  }

  void _clearFixtureData(Database db) {
    db.execute('DELETE FROM email_events;');
    db.execute('DELETE FROM interview_events;');
    db.execute('DELETE FROM applications;');
    db.execute('DELETE FROM accounts;');
    db.execute('DELETE FROM sync_state;');
  }

  void _upsertApplications(Database db, List<_FixtureEmail> emails) {
    final stats = <String, _FixtureApplicationStats>{};
    for (final email in emails) {
      final meta = _fixtureApplications[email.applicationId];
      if (meta == null) {
        continue;
      }
      final stat = stats.putIfAbsent(
        email.applicationId,
        () => _FixtureApplicationStats(meta),
      );
      stat.register(email.parsed.date, email.extractedStatus);
    }

    final stmt = db.prepare(
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

    for (final entry in stats.entries) {
      final meta = entry.value.meta;
      final firstSeen =
          entry.value.firstSeen ?? DateTime.now().toUtc();
      final lastSeen =
          entry.value.lastSeen ?? entry.value.firstSeen ?? DateTime.now().toUtc();
      final status = _mapStatus(entry.value.latestStatus);
      stmt.execute([
        meta.id,
        meta.company,
        meta.role,
        null,
        null,
        firstSeen.toIso8601String(),
        lastSeen.toIso8601String(),
        status.name,
        64.0,
        meta.accountLabel,
        'Fixture',
        null,
        null,
        null,
      ]);
    }
    stmt.dispose();
  }

  int _insertEmailEvents(Database db, List<_FixtureEmail> emails) {
    final stmt = db.prepare(
      'INSERT OR REPLACE INTO email_events (id, applicationId, accountLabel, '
      'provider, folder, cursorValue, messageId, subject, fromAddr, date, '
      'extractedStatus, extractedFieldsJson, evidenceSnippet, raw_body_text, '
      'raw_body_path, raw_body_sha256, raw_body_byte_len, hash, '
      'isSignificantUpdate) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
    );
    var inserted = 0;
    for (final email in emails) {
      final meta = _fixtureApplications[email.applicationId];
      if (meta == null) {
        continue;
      }
      final fieldsJson = email.parsed.icsPayload == null
          ? null
          : jsonEncode({'ics': email.parsed.icsPayload});
      final body = email.parsed.body;
      final snippet = _truncate(body, evidenceMaxLength);
      final bodyBytes = utf8.encode(body);
      final bodySha = sha256.convert(bodyBytes).toString();
      final status = email.extractedStatus;
      stmt.execute([
        'fx_${email.fileName}',
        email.applicationId,
        meta.accountLabel,
        'fixture',
        'INBOX',
        null,
        email.parsed.messageId,
        email.parsed.subject,
        email.parsed.from,
        email.parsed.date.toIso8601String(),
        status,
        fieldsJson,
        snippet,
        body,
        null,
        bodySha,
        bodyBytes.length,
        'fixture-${email.parsed.messageId}',
        status == null ? 0 : 1,
      ]);
      inserted++;
    }
    stmt.dispose();
    return inserted;
  }

  ParsedEmail _parseEmail(String raw) {
    final lines = raw.split(RegExp(r'\r?\n'));
    final headerLines = <String>[];
    var index = 0;
    for (; index < lines.length; index++) {
      if (lines[index].trim().isEmpty) {
        index++;
        break;
      }
      headerLines.add(lines[index]);
    }

    final headers = _parseHeaders(headerLines);
    final rawBody = lines.sublist(index).join('\n');
    final contentType = headers['content-type'];
    final boundary = _parseBoundary(contentType);

    String body = rawBody.trim();
    String? icsPayload;
    if (boundary != null) {
      body = '';
      final parts = rawBody.split('--$boundary');
      for (final part in parts) {
        final trimmed = part.trim();
        if (trimmed.isEmpty || trimmed == '--') {
          continue;
        }
        final partLines = trimmed.split(RegExp(r'\r?\n'));
        final partHeaderLines = <String>[];
        var partIndex = 0;
        for (; partIndex < partLines.length; partIndex++) {
          if (partLines[partIndex].trim().isEmpty) {
            partIndex++;
            break;
          }
          partHeaderLines.add(partLines[partIndex]);
        }
        final partHeaders = _parseHeaders(partHeaderLines);
        final partBody = partLines.sublist(partIndex).join('\n').trim();
        final partType = partHeaders['content-type'] ?? '';
        if (partType.startsWith('text/plain') && body.isEmpty) {
          body = partBody;
        }
        if (partType.startsWith('text/calendar')) {
          icsPayload = partBody;
        }
      }
    }

    icsPayload ??= _extractIcs(rawBody);

    final dateValue = headers['date'];
    final date = _parseDate(dateValue);
    return ParsedEmail(
      from: headers['from'] ?? 'unknown',
      to: headers['to'] ?? 'unknown',
      subject: headers['subject'] ?? 'No subject',
      messageId: headers['message-id'] ?? 'fixture-${date.toIso8601String()}',
      date: date,
      body: body.isEmpty ? rawBody.trim() : body,
      icsPayload: icsPayload,
    );
  }

  DateTime _parseDate(String? value) {
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

  Map<String, String> _parseHeaders(List<String> lines) {
    final headers = <String, String>{};
    String? currentKey;
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

  String? _parseBoundary(String? contentType) {
    if (contentType == null) {
      return null;
    }
    final boundaryIndex = contentType.toLowerCase().indexOf('boundary=');
    if (boundaryIndex == -1) {
      return null;
    }
    final value = contentType.substring(boundaryIndex + 9).trim();
    final raw = value.split(';').first.trim();
    if (raw.startsWith('"') && raw.endsWith('"')) {
      return raw.substring(1, raw.length - 1);
    }
    return raw;
  }

  String? _extractIcs(String rawBody) {
    final start = rawBody.indexOf('BEGIN:VCALENDAR');
    if (start == -1) {
      return null;
    }
    final end = rawBody.indexOf('END:VCALENDAR');
    if (end == -1) {
      return null;
    }
    return rawBody.substring(start, end + 'END:VCALENDAR'.length).trim();
  }

  ApplicationStatus _mapStatus(String? status) {
    switch (status) {
      case 'received':
        return ApplicationStatus.received;
      case 'interview':
        return ApplicationStatus.interview;
      case 'offer':
        return ApplicationStatus.offer;
      case 'rejected':
        return ApplicationStatus.rejected;
      default:
        return ApplicationStatus.applied;
    }
  }

  String _truncate(String value, int maxLength) {
    final trimmed = value.trim();
    if (trimmed.length <= maxLength) {
      return trimmed;
    }
    return '${trimmed.substring(0, maxLength - 3).trimRight()}...';
  }

}

class _FixtureEmail {
  final String fileName;
  final String applicationId;
  final ParsedEmail parsed;

  const _FixtureEmail({
    required this.fileName,
    required this.applicationId,
    required this.parsed,
  });

  String? get extractedStatus {
    final subject = parsed.subject.toLowerCase();
    final body = parsed.body.toLowerCase();
    if (subject.contains('offer') || body.contains('offer')) {
      return 'offer';
    }
    if (subject.contains('rejected') ||
        subject.contains('not moving forward') ||
        body.contains('not moving forward') ||
        body.contains('position has been filled')) {
      return 'rejected';
    }
    if (subject.contains('interview') ||
        body.contains('interview') ||
        body.contains('schedule a call')) {
      return 'interview';
    }
    if (subject.contains('received') ||
        subject.contains('submitted') ||
        subject.contains('application confirmation') ||
        body.contains('application received')) {
      return 'received';
    }
    return null;
  }
}

class _FixtureApplicationStats {
  final FixtureApplication meta;
  DateTime? firstSeen;
  DateTime? lastSeen;
  String? latestStatus;

  _FixtureApplicationStats(this.meta);

  void register(DateTime date, String? status) {
    if (firstSeen == null || date.isBefore(firstSeen!)) {
      firstSeen = date;
    }
    if (lastSeen == null || date.isAfter(lastSeen!)) {
      lastSeen = date;
      latestStatus = status;
    }
  }
}

const Map<String, FixtureApplication> _fixtureApplications = {
  'fx_app_001': FixtureApplication(
    id: 'fx_app_001',
    company: 'Nimbus Analytics',
    role: 'Data Analyst',
    accountLabel: 'Gmail',
  ),
  'fx_app_002': FixtureApplication(
    id: 'fx_app_002',
    company: 'Blue Finch Software',
    role: 'Backend Engineer',
    accountLabel: 'Gmail',
  ),
  'fx_app_003': FixtureApplication(
    id: 'fx_app_003',
    company: 'Orbit Labs',
    role: 'Product Designer',
    accountLabel: 'Northeastern',
  ),
  'fx_app_004': FixtureApplication(
    id: 'fx_app_004',
    company: 'Pine Ridge Systems',
    role: 'QA Engineer',
    accountLabel: 'Northeastern',
  ),
  'fx_app_005': FixtureApplication(
    id: 'fx_app_005',
    company: 'Aurora Health',
    role: 'Product Manager',
    accountLabel: 'Gmail',
  ),
  'fx_app_006': FixtureApplication(
    id: 'fx_app_006',
    company: 'Crescent AI',
    role: 'ML Engineer',
    accountLabel: 'Northeastern',
  ),
  'fx_app_007': FixtureApplication(
    id: 'fx_app_007',
    company: 'Verdant Systems',
    role: 'DevOps Engineer',
    accountLabel: 'Gmail',
  ),
  'fx_app_008': FixtureApplication(
    id: 'fx_app_008',
    company: 'Summit Logistics',
    role: 'Customer Success Manager',
    accountLabel: 'Northeastern',
  ),
};

const List<FixtureMessage> _fixtureMessages = [
  FixtureMessage(
    fileName: 'fx_001_received_nimbus.eml',
    applicationId: 'fx_app_001',
  ),
  FixtureMessage(
    fileName: 'fx_002_interview_nimbus.eml',
    applicationId: 'fx_app_001',
  ),
  FixtureMessage(
    fileName: 'fx_003_received_bluefinch.eml',
    applicationId: 'fx_app_002',
  ),
  FixtureMessage(
    fileName: 'fx_004_interview_bluefinch_ics.eml',
    applicationId: 'fx_app_002',
  ),
  FixtureMessage(
    fileName: 'fx_005_received_orbit.eml',
    applicationId: 'fx_app_003',
  ),
  FixtureMessage(
    fileName: 'fx_006_rejected_orbit.eml',
    applicationId: 'fx_app_003',
  ),
  FixtureMessage(
    fileName: 'fx_007_received_pineridge.eml',
    applicationId: 'fx_app_004',
  ),
  FixtureMessage(
    fileName: 'fx_008_interview_pineridge.eml',
    applicationId: 'fx_app_004',
  ),
  FixtureMessage(
    fileName: 'fx_009_interview_aurora_ics.eml',
    applicationId: 'fx_app_005',
  ),
  FixtureMessage(
    fileName: 'fx_010_offer_aurora.eml',
    applicationId: 'fx_app_005',
  ),
  FixtureMessage(
    fileName: 'fx_011_received_crescent.eml',
    applicationId: 'fx_app_006',
  ),
  FixtureMessage(
    fileName: 'fx_012_offer_crescent.eml',
    applicationId: 'fx_app_006',
  ),
  FixtureMessage(
    fileName: 'fx_013_received_verdant.eml',
    applicationId: 'fx_app_007',
  ),
  FixtureMessage(
    fileName: 'fx_014_rejected_verdant.eml',
    applicationId: 'fx_app_007',
  ),
  FixtureMessage(
    fileName: 'fx_015_received_summit.eml',
    applicationId: 'fx_app_008',
  ),
  FixtureMessage(
    fileName: 'fx_016_interview_summit.eml',
    applicationId: 'fx_app_008',
  ),
];
