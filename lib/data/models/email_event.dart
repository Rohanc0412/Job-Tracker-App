class EmailEvent {
  final String id;
  final String applicationId;
  final String accountLabel;
  final String provider;
  final String folder;
  final String? cursorValue;
  final String messageId;
  final String subject;
  final String fromAddr;
  final DateTime date;
  final String? extractedStatus;
  final String? extractedFieldsJson;
  final String? evidenceSnippet;
  final String hash;
  final bool isSignificantUpdate;

  const EmailEvent({
    required this.id,
    required this.applicationId,
    required this.accountLabel,
    required this.provider,
    required this.folder,
    this.cursorValue,
    required this.messageId,
    required this.subject,
    required this.fromAddr,
    required this.date,
    this.extractedStatus,
    this.extractedFieldsJson,
    this.evidenceSnippet,
    required this.hash,
    required this.isSignificantUpdate,
  });
}
