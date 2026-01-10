class InterviewEvent {
  final String id;
  final String applicationId;
  final DateTime scheduledAt;
  final String stage;

  const InterviewEvent({
    required this.id,
    required this.applicationId,
    required this.scheduledAt,
    required this.stage,
  });
}
