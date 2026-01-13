import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../db/db.dart';
import '../models/email_review_item.dart';

class EmailReviewRepo {
  EmailReviewRepo(this._database);

  final AppDatabase _database;

  Future<Database> _db() async {
    await _database.open();
    return _database.rawDb;
  }

  Future<List<EmailReviewItem>> listPending() async {
    final db = await _db();
    final rows = db.select(
      'SELECT * FROM email_review_queue '
      'WHERE review_state = ? '
      'ORDER BY createdAt ASC;',
      ['pending'],
    );
    return rows.map(_mapRow).toList();
  }

  Future<EmailReviewItem?> findById(String id) async {
    final db = await _db();
    final rows = db.select(
      'SELECT * FROM email_review_queue WHERE id = ?;',
      [id],
    );
    if (rows.isEmpty) {
      return null;
    }
    return _mapRow(rows.first);
  }

  Future<void> updateUserOverrides(
    String id,
    Map<String, dynamic> overrides, {
    String? selectedApplicationId,
  }) async {
    final db = await _db();
    final encoded = _encodeJson(overrides);
    db.execute(
      'UPDATE email_review_queue '
      'SET user_overrides_json = ?, selected_application_id = ?, updatedAt = ? '
      'WHERE id = ?;',
      [
        encoded,
        selectedApplicationId,
        DateTime.now().toUtc().toIso8601String(),
        id,
      ],
    );
  }

  Future<void> markReviewState(String id, String state) async {
    final db = await _db();
    db.execute(
      'UPDATE email_review_queue '
      'SET review_state = ?, updatedAt = ? '
      'WHERE id = ?;',
      [state, DateTime.now().toUtc().toIso8601String(), id],
    );
  }

  EmailReviewItem _mapRow(Row row) {
    return EmailReviewItem(
      id: row['id'] as String,
      accountLabel: row['accountLabel'] as String,
      provider: row['provider'] as String,
      folder: row['folder'] as String,
      cursorValue: row['cursorValue'] as String?,
      messageId: row['messageId'] as String,
      subject: row['subject'] as String,
      fromAddr: row['fromAddr'] as String,
      toAddr: row['toAddr'] as String,
      date: DateTime.parse(row['date'] as String),
      snippet: row['snippet'] as String?,
      cleanBodyText: row['clean_body_text'] as String?,
      cleanBodyPreview: row['clean_body_preview'] as String?,
      rawBodyText: row['raw_body_text'] as String?,
      rawBodyPath: row['raw_body_path'] as String?,
      rawBodySha256: row['raw_body_sha256'] as String?,
      rawBodyByteLen: (row['raw_body_byte_len'] as num?)?.toInt(),
      llmData: EmailReviewItem.decodeJson(row['llm_json'] as String?),
      llmState: row['llm_state'] as String,
      llmError: row['llm_error'] as String?,
      userOverrides:
          EmailReviewItem.decodeJson(row['user_overrides_json'] as String?),
      suggestedApplicationId: row['suggested_application_id'] as String?,
      selectedApplicationId: row['selected_application_id'] as String?,
      reviewState: row['review_state'] as String,
      createdAt: DateTime.parse(row['createdAt'] as String),
      updatedAt: DateTime.parse(row['updatedAt'] as String),
    );
  }
}

String? _encodeJson(Map<String, dynamic> value) {
  if (value.isEmpty) {
    return null;
  }
  return jsonEncode(value);
}
