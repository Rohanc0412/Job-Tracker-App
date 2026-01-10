class EmailEvent {
  final String id;
  final String applicationId;
  final DateTime timestamp;
  final String subject;

  const EmailEvent({
    required this.id,
    required this.applicationId,
    required this.timestamp,
    required this.subject,
  });
}
