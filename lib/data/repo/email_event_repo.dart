import 'package:sqlite3/sqlite3.dart';

import '../../services/body_retrieval_service.dart';
import '../../services/email_text_extractor.dart';
import '../db/db.dart';
import '../models/email_event.dart';

class EmailEventRepo {
  EmailEventRepo(
    this._database, {
    BodyRetrievalService? bodyService,
  }) : _bodyService = bodyService ?? BodyRetrievalService();

  final AppDatabase _database;
  final BodyRetrievalService _bodyService;

  Future<Database> _db() async {
    await _database.open();
    return _database.rawDb;
  }

  Future<List<EmailEvent>> listForApplication(String applicationId) async {
    final db = await _db();
    final rows = db.select(
      'SELECT id, applicationId, accountLabel, provider, folder, cursorValue, '
      'messageId, subject, fromAddr, date, extractedStatus, extractedFieldsJson, '
      'llm_summary, raw_body_text, raw_body_path, raw_body_sha256, '
      'raw_body_byte_len, hash, isSignificantUpdate '
      'FROM email_events WHERE applicationId = ? '
      'ORDER BY date DESC;',
      [applicationId],
    );
    return rows.map(_mapEmailEvent).toList();
  }

  Future<String> unlinkToReview(EmailEvent event) async {
    final db = await _db();
    final now = DateTime.now().toUtc().toIso8601String();
    final cleanBody = await _bodyService.getFullBody(
      rawBodyText: event.rawBodyText,
      rawBodyPath: event.rawBodyPath,
    );
    final cleanPreview = _bodyService.getBodyPreview(cleanBody);
    final snippet = cleanPreview.isNotEmpty ? cleanPreview : event.subject;
    final reviewId = 'review_unlink_${event.id}';

    final existing = db.select(
      'SELECT id FROM email_review_queue '
      'WHERE accountLabel = ? AND provider = ? AND messageId = ?;',
      [event.accountLabel, event.provider, event.messageId],
    );

    db.execute('BEGIN;');
    try {
      if (existing.isNotEmpty) {
        final existingId = existing.first['id'] as String;
        db.execute(
          'UPDATE email_review_queue '
          'SET folder = ?, cursorValue = ?, subject = ?, fromAddr = ?, '
          'toAddr = ?, date = ?, snippet = ?, clean_body_text = ?, '
          'clean_body_preview = ?, raw_body_text = ?, raw_body_path = ?, '
          'raw_body_sha256 = ?, raw_body_byte_len = ?, llm_json = ?, '
          'llm_state = ?, llm_error = ?, user_overrides_json = ?, '
          'suggested_application_id = ?, selected_application_id = ?, '
          'review_state = ?, updatedAt = ? '
          'WHERE id = ?;',
          [
            event.folder,
            event.cursorValue,
            event.subject,
            event.fromAddr,
            event.accountLabel,
            event.date.toIso8601String(),
            snippet,
            cleanBody,
            cleanPreview.isEmpty ? null : cleanPreview,
            event.rawBodyText,
            event.rawBodyPath,
            event.rawBodySha256,
            event.rawBodyByteLen,
            null,
            'ready',
            null,
            null,
            event.applicationId,
            null,
            'pending',
            now,
            existingId,
          ],
        );
        _deleteEmailEvent(db, event);
        db.execute('COMMIT;');
        return existingId;
      }

      db.execute(
        'INSERT INTO email_review_queue '
        '(id, accountLabel, provider, folder, cursorValue, messageId, subject, '
        'fromAddr, toAddr, date, snippet, clean_body_text, clean_body_preview, '
        'raw_body_text, raw_body_path, raw_body_sha256, raw_body_byte_len, '
        'llm_json, llm_state, llm_error, user_overrides_json, '
        'suggested_application_id, selected_application_id, review_state, '
        'createdAt, updatedAt) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '
        '?, ?, ?, ?, ?);',
        [
          reviewId,
          event.accountLabel,
          event.provider,
          event.folder,
          event.cursorValue,
          event.messageId,
          event.subject,
          event.fromAddr,
          event.accountLabel,
          event.date.toIso8601String(),
          snippet,
          cleanBody,
          cleanPreview.isEmpty ? null : cleanPreview,
          event.rawBodyText,
          event.rawBodyPath,
          event.rawBodySha256,
          event.rawBodyByteLen,
          null,
          'ready',
          null,
          null,
          event.applicationId,
          null,
          'pending',
          now,
          now,
        ],
      );
      _deleteEmailEvent(db, event);
      db.execute('COMMIT;');
      return reviewId;
    } catch (_) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  void _deleteEmailEvent(Database db, EmailEvent event) {
    db.execute(
      'DELETE FROM interview_events WHERE messageId = ?;',
      [event.messageId],
    );
    db.execute(
      'DELETE FROM email_events WHERE id = ?;',
      [event.id],
    );
  }

  EmailEvent _mapEmailEvent(Row row) {
    return EmailEvent(
      id: row['id'] as String,
      applicationId: row['applicationId'] as String,
      accountLabel: row['accountLabel'] as String,
      provider: row['provider'] as String,
      folder: row['folder'] as String,
      cursorValue: row['cursorValue'] as String?,
      messageId: row['messageId'] as String,
      subject: EmailTextExtractor.decodeMimeHeader(
        row['subject'] as String,
      ),
      fromAddr: row['fromAddr'] as String,
      date: DateTime.parse(row['date'] as String),
      extractedStatus: row['extractedStatus'] as String?,
      extractedFieldsJson: row['extractedFieldsJson'] as String?,
      llmSummary: row['llm_summary'] as String?,
      rawBodyText: row['raw_body_text'] as String?,
      rawBodyPath: row['raw_body_path'] as String?,
      rawBodySha256: row['raw_body_sha256'] as String?,
      rawBodyByteLen: (row['raw_body_byte_len'] as num?)?.toInt(),
      hash: row['hash'] as String?,
      isSignificantUpdate:
          (row['isSignificantUpdate'] as num?)?.toInt() == 1,
    );
  }
}
