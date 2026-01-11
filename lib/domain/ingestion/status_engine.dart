import '../status/status_types.dart';

class StatusClassification {
  final ApplicationStatus status;
  final int confidence;
  final bool strongEvidence;

  const StatusClassification({
    required this.status,
    required this.confidence,
    required this.strongEvidence,
  });
}

class StatusDecision {
  final ApplicationStatus status;
  final int confidence;
  final bool changed;

  const StatusDecision({
    required this.status,
    required this.confidence,
    required this.changed,
  });
}

StatusClassification classifyStatus(String subject, String body) {
  final text = '${subject.toLowerCase()} ${body.toLowerCase()}';

  final rejection = _scoreRejection(text);
  if (rejection != null) {
    return rejection;
  }
  final offer = _scoreOffer(text);
  if (offer != null) {
    return offer;
  }
  final interview = _scoreInterview(text);
  if (interview != null) {
    return interview;
  }
  final assessment = _scoreAssessment(text);
  if (assessment != null) {
    return assessment;
  }
  final received = _scoreReceived(text);
  if (received != null) {
    return received;
  }

  return const StatusClassification(
    status: ApplicationStatus.applied,
    confidence: 40,
    strongEvidence: false,
  );
}

StatusDecision applyMonotonicTransition({
  required ApplicationStatus currentStatus,
  required int currentConfidence,
  required StatusClassification incoming,
}) {
  final currentRank = _statusRank[currentStatus] ?? 0;
  final incomingRank = _statusRank[incoming.status] ?? 0;

  if (incomingRank > currentRank) {
    return StatusDecision(
      status: incoming.status,
      confidence: incoming.confidence,
      changed: true,
    );
  }

  if (incomingRank == currentRank) {
    final nextConfidence =
        incoming.confidence > currentConfidence
            ? incoming.confidence
            : currentConfidence;
    return StatusDecision(
      status: currentStatus,
      confidence: nextConfidence,
      changed: false,
    );
  }

  if (incoming.strongEvidence) {
    return StatusDecision(
      status: incoming.status,
      confidence: incoming.confidence,
      changed: true,
    );
  }

  return StatusDecision(
    status: currentStatus,
    confidence: currentConfidence,
    changed: false,
  );
}

StatusClassification? _scoreRejection(String text) {
  final strongSignals = [
    'not moving forward',
    'position has been filled',
    'we will not be moving forward',
    'we have decided to move forward',
  ];
  if (strongSignals.any(text.contains)) {
    return const StatusClassification(
      status: ApplicationStatus.rejected,
      confidence: 95,
      strongEvidence: true,
    );
  }
  if (text.contains('rejected') || text.contains('decline')) {
    return const StatusClassification(
      status: ApplicationStatus.rejected,
      confidence: 90,
      strongEvidence: true,
    );
  }
  return null;
}

StatusClassification? _scoreOffer(String text) {
  if (text.contains('offer')) {
    return const StatusClassification(
      status: ApplicationStatus.offer,
      confidence: 92,
      strongEvidence: true,
    );
  }
  if (text.contains('pleased to') && text.contains('join us')) {
    return const StatusClassification(
      status: ApplicationStatus.offer,
      confidence: 88,
      strongEvidence: true,
    );
  }
  return null;
}

StatusClassification? _scoreInterview(String text) {
  final signals = [
    'interview',
    'schedule',
    'availability',
    'phone screen',
    'video call',
    'calendar invite',
  ];
  if (signals.any(text.contains)) {
    return const StatusClassification(
      status: ApplicationStatus.interview,
      confidence: 84,
      strongEvidence: false,
    );
  }
  return null;
}

StatusClassification? _scoreAssessment(String text) {
  final signals = [
    'assessment',
    'take-home',
    'coding challenge',
  ];
  if (signals.any(text.contains)) {
    return const StatusClassification(
      status: ApplicationStatus.assessment,
      confidence: 78,
      strongEvidence: false,
    );
  }
  return null;
}

StatusClassification? _scoreReceived(String text) {
  final signals = [
    'application received',
    'application confirmation',
    'submitted',
    'received your application',
  ];
  if (signals.any(text.contains)) {
    return const StatusClassification(
      status: ApplicationStatus.received,
      confidence: 70,
      strongEvidence: false,
    );
  }
  return null;
}

const Map<ApplicationStatus, int> _statusRank = {
  ApplicationStatus.applied: 1,
  ApplicationStatus.received: 2,
  ApplicationStatus.underReview: 3,
  ApplicationStatus.assessment: 4,
  ApplicationStatus.interview: 5,
  ApplicationStatus.offer: 6,
  ApplicationStatus.rejected: 7,
};
