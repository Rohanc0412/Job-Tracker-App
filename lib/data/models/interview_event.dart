class InterviewEvent {
  final String id;
  final String applicationId;
  final String accountLabel;
  final String messageId;
  final DateTime startTime;
  final DateTime? endTime;
  final String? timezone;
  final String? location;
  final String? meetingUrl;
  final String source;
  final double confidence;
  final DateTime createdAt;

  const InterviewEvent({
    required this.id,
    required this.applicationId,
    required this.accountLabel,
    required this.messageId,
    required this.startTime,
    this.endTime,
    this.timezone,
    this.location,
    this.meetingUrl,
    required this.source,
    required this.confidence,
    required this.createdAt,
  });
}
