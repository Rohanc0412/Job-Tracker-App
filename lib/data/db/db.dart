import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../seed/seed_data.dart';

class AppDatabase {
  AppDatabase({
    Database? database,
    String? dbPath,
    Future<String> Function()? pathResolver,
  })  : _database = database,
        _dbPath = dbPath,
        _pathResolver = pathResolver ?? _resolveDefaultPath;

  static final AppDatabase instance = AppDatabase();

  Database? _database;
  final String? _dbPath;
  final Future<String> Function() _pathResolver;
  bool _initialized = false;

  Database get rawDb {
    final db = _database;
    if (db == null) {
      throw StateError('Database has not been opened yet.');
    }
    return db;
  }

  Future<void> open() async {
    if (_initialized) {
      return;
    }
    if (_database == null) {
      final path = _dbPath ?? await _pathResolver();
      _database = sqlite3.open(path);
    }
    final db = _database!;
    db.execute('PRAGMA foreign_keys = ON;');
    _createSchema(db);
    _seedIfEmpty(db);
    _initialized = true;
  }

  Future<void> close() async {
    _database?.dispose();
    _database = null;
    _initialized = false;
  }

  static Future<String> _resolveDefaultPath() async {
    final Directory supportDir = await getApplicationSupportDirectory();
    await supportDir.create(recursive: true);
    return p.join(supportDir.path, 'job_tracker.db');
  }

  void _createSchema(Database db) {
    for (final statement in _schemaStatements) {
      db.execute(statement);
    }
  }

  void _seedIfEmpty(Database db) {
    final result = db.select('SELECT COUNT(*) AS count FROM applications;');
    final count = (result.first['count'] as num).toInt();
    if (count == 0) {
      _seedDatabase(db);
    }
  }

  void _seedDatabase(Database db) {
    db.execute('BEGIN;');
    try {
      final accountStmt = db.prepare(
        'INSERT INTO accounts (id, label, provider, createdAt) VALUES (?, ?, ?, ?);',
      );
      for (final account in SeedData.accounts) {
        accountStmt.execute([
          account.id,
          account.label,
          account.provider,
          account.createdAt.toIso8601String(),
        ]);
      }
      accountStmt.dispose();

      final appStmt = db.prepare(
        'INSERT INTO applications (id, company, role, jobId, portalUrl, firstSeen, lastSeen, '
        'currentStatus, confidence, accountLabel, sourceLabel, contact, nextStep, nextStepAt) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
      );
      for (final app in SeedData.applications) {
        appStmt.execute([
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
      appStmt.dispose();

      final emailStmt = db.prepare(
        'INSERT INTO email_events (id, applicationId, accountLabel, provider, folder, cursorValue, '
        'messageId, subject, fromAddr, date, extractedStatus, extractedFieldsJson, evidenceSnippet, '
        'hash, isSignificantUpdate) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
      );
      for (final event in SeedData.emailEvents) {
        emailStmt.execute([
          event.id,
          event.applicationId,
          event.accountLabel,
          event.provider,
          event.folder,
          event.cursorValue,
          event.messageId,
          event.subject,
          event.fromAddr,
          event.date.toIso8601String(),
          event.extractedStatus,
          event.extractedFieldsJson,
          event.evidenceSnippet,
          event.hash,
          event.isSignificantUpdate ? 1 : 0,
        ]);
      }
      emailStmt.dispose();

      final interviewStmt = db.prepare(
        'INSERT INTO interview_events (id, applicationId, accountLabel, messageId, startTime, '
        'endTime, timezone, location, meetingUrl, source, confidence, createdAt) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
      );
      for (final event in SeedData.interviewEvents) {
        interviewStmt.execute([
          event.id,
          event.applicationId,
          event.accountLabel,
          event.messageId,
          event.startTime.toIso8601String(),
          event.endTime?.toIso8601String(),
          event.timezone,
          event.location,
          event.meetingUrl,
          event.source,
          event.confidence,
          event.createdAt.toIso8601String(),
        ]);
      }
      interviewStmt.dispose();

      final syncStmt = db.prepare(
        'INSERT INTO sync_state (id, accountLabel, provider, folder, cursorKey, cursorValue, '
        'lastSyncTime) VALUES (?, ?, ?, ?, ?, ?, ?);',
      );
      for (final state in SeedData.syncStates) {
        syncStmt.execute([
          state.id,
          state.accountLabel,
          state.provider,
          state.folder,
          state.cursorKey,
          state.cursorValue,
          state.lastSyncTime.toIso8601String(),
        ]);
      }
      syncStmt.dispose();

      db.execute('COMMIT;');
    } catch (_) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }
}

const List<String> _schemaStatements = [
  '''
  CREATE TABLE IF NOT EXISTS accounts (
    id TEXT PRIMARY KEY,
    label TEXT NOT NULL,
    provider TEXT NOT NULL,
    createdAt TEXT NOT NULL
  );
  ''',
  '''
  CREATE TABLE IF NOT EXISTS applications (
    id TEXT PRIMARY KEY,
    company TEXT NOT NULL,
    role TEXT NOT NULL,
    jobId TEXT,
    portalUrl TEXT,
    firstSeen TEXT NOT NULL,
    lastSeen TEXT NOT NULL,
    currentStatus TEXT NOT NULL,
    confidence REAL NOT NULL,
    accountLabel TEXT NOT NULL,
    sourceLabel TEXT NOT NULL,
    contact TEXT,
    nextStep TEXT,
    nextStepAt TEXT
  );
  ''',
  '''
  CREATE TABLE IF NOT EXISTS email_events (
    id TEXT PRIMARY KEY,
    applicationId TEXT NOT NULL,
    accountLabel TEXT NOT NULL,
    provider TEXT NOT NULL,
    folder TEXT NOT NULL,
    cursorValue TEXT,
    messageId TEXT NOT NULL,
    subject TEXT NOT NULL,
    fromAddr TEXT NOT NULL,
    date TEXT NOT NULL,
    extractedStatus TEXT,
    extractedFieldsJson TEXT,
    evidenceSnippet TEXT,
    hash TEXT NOT NULL,
    isSignificantUpdate INTEGER NOT NULL,
    FOREIGN KEY(applicationId) REFERENCES applications(id) ON DELETE CASCADE,
    UNIQUE(accountLabel, provider, messageId)
  );
  ''',
  '''
  CREATE TABLE IF NOT EXISTS interview_events (
    id TEXT PRIMARY KEY,
    applicationId TEXT NOT NULL,
    accountLabel TEXT NOT NULL,
    messageId TEXT NOT NULL,
    startTime TEXT NOT NULL,
    endTime TEXT,
    timezone TEXT,
    location TEXT,
    meetingUrl TEXT,
    source TEXT NOT NULL,
    confidence REAL NOT NULL,
    createdAt TEXT NOT NULL,
    FOREIGN KEY(applicationId) REFERENCES applications(id) ON DELETE CASCADE
  );
  ''',
  '''
  CREATE TABLE IF NOT EXISTS sync_state (
    id TEXT PRIMARY KEY,
    accountLabel TEXT NOT NULL,
    provider TEXT NOT NULL,
    folder TEXT NOT NULL,
    cursorKey TEXT NOT NULL,
    cursorValue TEXT NOT NULL,
    lastSyncTime TEXT NOT NULL
  );
  ''',
  'CREATE INDEX IF NOT EXISTS idx_applications_status ON applications(currentStatus);',
  'CREATE INDEX IF NOT EXISTS idx_applications_lastSeen ON applications(lastSeen);',
  'CREATE INDEX IF NOT EXISTS idx_interview_events_startTime ON interview_events(startTime);',
];
