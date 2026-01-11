import 'package:flutter_test/flutter_test.dart';
import 'package:job_tracker/domain/ingestion/status_engine.dart';
import 'package:job_tracker/domain/status/status_types.dart';

void main() {
  test('classifies offer status', () {
    final result = classifyStatus(
      'Offer for Product Manager at Aurora Health',
      'We are excited to extend an offer for the role.',
    );
    expect(result.status, ApplicationStatus.offer);
    expect(result.confidence, greaterThanOrEqualTo(90));
  });

  test('classifies rejection status', () {
    final result = classifyStatus(
      'Update on your application',
      'We are not moving forward with your application.',
    );
    expect(result.status, ApplicationStatus.rejected);
    expect(result.confidence, greaterThanOrEqualTo(90));
  });

  test('classifies interview status', () {
    final result = classifyStatus(
      'Interview request - Customer Success Manager',
      'Can we schedule a call next week?',
    );
    expect(result.status, ApplicationStatus.interview);
  });

  test('respects monotonic transitions', () {
    final incoming = classifyStatus(
      'Application received - Backend Engineer',
      'Your application has been received.',
    );
    final decision = applyMonotonicTransition(
      currentStatus: ApplicationStatus.offer,
      currentConfidence: 92,
      incoming: incoming,
    );
    expect(decision.status, ApplicationStatus.offer);
  });
}
