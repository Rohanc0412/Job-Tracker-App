import 'dart:convert';

class EmailReviewItem {
  final String id;
  final String accountLabel;
  final String provider;
  final String folder;
  final String? cursorValue;
  final String messageId;
  final String subject;
  final String fromAddr;
  final String toAddr;
  final DateTime date;
  final String? snippet;
  final String? cleanBodyText;
  final String? cleanBodyPreview;
  final String? rawBodyText;
  final String? rawBodyPath;
  final String? rawBodySha256;
  final int? rawBodyByteLen;
  final Map<String, dynamic> llmData;
  final String llmState;
  final String? llmError;
  final Map<String, dynamic> userOverrides;
  final String? suggestedApplicationId;
  final String? selectedApplicationId;
  final String reviewState;
  final DateTime createdAt;
  final DateTime updatedAt;

  const EmailReviewItem({
    required this.id,
    required this.accountLabel,
    required this.provider,
    required this.folder,
    required this.cursorValue,
    required this.messageId,
    required this.subject,
    required this.fromAddr,
    required this.toAddr,
    required this.date,
    required this.snippet,
    required this.cleanBodyText,
    required this.cleanBodyPreview,
    required this.rawBodyText,
    required this.rawBodyPath,
    required this.rawBodySha256,
    required this.rawBodyByteLen,
    required this.llmData,
    required this.llmState,
    required this.llmError,
    required this.userOverrides,
    required this.suggestedApplicationId,
    required this.selectedApplicationId,
    required this.reviewState,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get effectiveRelevant =>
      _resolveBool('relevant', llmData['relevant'] ?? true);

  String get effectiveSubject =>
      _resolveString('subject', subject) ?? subject;

  String? get effectiveCompany =>
      _resolveString('company', llmData['company']);

  String? get effectiveRole => _resolveString('role', llmData['role']);

  String? get effectiveJobId => _resolveString('jobId', llmData['jobId']);

  String? get effectivePortalUrl =>
      _resolveString('portalUrl', llmData['portalUrl']);

  String? get effectiveStatus =>
      _resolveString('status', llmData['status']);

  String get effectiveSummary {
    final summary = _resolveString('summary', llmData['summary']);
    if (summary != null && summary.trim().isNotEmpty) {
      return summary;
    }
    return effectiveSubject;
  }

  String get effectiveSource =>
      _resolveString('source', null) ?? 'Gmail';

  bool get effectiveActionRequired =>
      _resolveBool('actionRequired', llmData['actionRequired'] ?? false);

  List<String> get effectiveActionItems =>
      _resolveStringList('actionItems', llmData['actionItems']);

  Map<String, dynamic> get effectiveInterview =>
      _resolveMap('interview', llmData['interview']);

  String? get originalFromEmail =>
      _resolveString('originalFromEmail', llmData['originalFromEmail']);

  List<String> get originalToEmails =>
      _resolveStringList('originalToEmails', llmData['originalToEmails']);

  String? get llmCategory => _parseString(llmData['category']);

  double? get llmConfidence => _parseDouble(llmData['confidence']);

  List<Map<String, dynamic>> get llmEvidence =>
      _parseMapList(llmData['evidence']);

  String? get llmReason => _parseString(llmData['reason']);

  EmailReviewItem copyWith({
    String? id,
    String? accountLabel,
    String? provider,
    String? folder,
    String? cursorValue,
    String? messageId,
    String? subject,
    String? fromAddr,
    String? toAddr,
    DateTime? date,
    String? snippet,
    String? cleanBodyText,
    String? cleanBodyPreview,
    String? rawBodyText,
    String? rawBodyPath,
    String? rawBodySha256,
    int? rawBodyByteLen,
    Map<String, dynamic>? llmData,
    String? llmState,
    String? llmError,
    Map<String, dynamic>? userOverrides,
    String? suggestedApplicationId,
    String? selectedApplicationId,
    String? reviewState,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return EmailReviewItem(
      id: id ?? this.id,
      accountLabel: accountLabel ?? this.accountLabel,
      provider: provider ?? this.provider,
      folder: folder ?? this.folder,
      cursorValue: cursorValue ?? this.cursorValue,
      messageId: messageId ?? this.messageId,
      subject: subject ?? this.subject,
      fromAddr: fromAddr ?? this.fromAddr,
      toAddr: toAddr ?? this.toAddr,
      date: date ?? this.date,
      snippet: snippet ?? this.snippet,
      cleanBodyText: cleanBodyText ?? this.cleanBodyText,
      cleanBodyPreview: cleanBodyPreview ?? this.cleanBodyPreview,
      rawBodyText: rawBodyText ?? this.rawBodyText,
      rawBodyPath: rawBodyPath ?? this.rawBodyPath,
      rawBodySha256: rawBodySha256 ?? this.rawBodySha256,
      rawBodyByteLen: rawBodyByteLen ?? this.rawBodyByteLen,
      llmData: llmData ?? this.llmData,
      llmState: llmState ?? this.llmState,
      llmError: llmError ?? this.llmError,
      userOverrides: userOverrides ?? this.userOverrides,
      suggestedApplicationId:
          suggestedApplicationId ?? this.suggestedApplicationId,
      selectedApplicationId:
          selectedApplicationId ?? this.selectedApplicationId,
      reviewState: reviewState ?? this.reviewState,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static Map<String, dynamic> decodeJson(String? value) {
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

  String? _resolveString(String key, Object? fallback) {
    final override = userOverrides[key];
    if (override is String && override.trim().isNotEmpty) {
      return override;
    }
    return _parseString(fallback);
  }

  bool _resolveBool(String key, Object? fallback) {
    final override = userOverrides[key];
    if (override is bool) {
      return override;
    }
    return fallback is bool ? fallback : false;
  }

  List<String> _resolveStringList(String key, Object? fallback) {
    final override = userOverrides[key];
    final resolved = _parseStringList(override);
    if (resolved.isNotEmpty) {
      return resolved;
    }
    return _parseStringList(fallback);
  }

  Map<String, dynamic> _resolveMap(String key, Object? fallback) {
    final override = userOverrides[key];
    if (override is Map<String, dynamic>) {
      return Map<String, dynamic>.from(override);
    }
    if (fallback is Map<String, dynamic>) {
      return Map<String, dynamic>.from(fallback);
    }
    return <String, dynamic>{};
  }
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
