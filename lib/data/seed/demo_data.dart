import '../models/application.dart';
import '../../domain/status/status_types.dart';

enum ActivityKind {
  update,
  interview,
  offer,
  rejection,
}

class ActivityItem {
  final String title;
  final String detail;
  final DateTime timestamp;
  final ActivityKind kind;

  const ActivityItem({
    required this.title,
    required this.detail,
    required this.timestamp,
    required this.kind,
  });
}

class DemoData {
  static final List<Application> applications = [
    Application(
      id: 'app_001',
      company: 'Delta Dynamics',
      role: 'ML Engineer',
      appliedOn: DateTime(2026, 1, 2),
      lastUpdated: DateTime(2026, 1, 9),
      status: ApplicationStatus.assessment,
      confidence: 68,
      account: 'Gmail',
      source: 'Company Site',
      portalUrl: 'https://jobs.deltadynamics.com/role/123',
      contact: 'hiring@deltadynamics.com',
      nextStep: 'Assessment review',
      nextStepAt: DateTime(2026, 1, 12, 10, 0),
    ),
    Application(
      id: 'app_002',
      company: 'Acme Robotics',
      role: 'Software Engineer',
      appliedOn: DateTime(2026, 1, 3),
      lastUpdated: DateTime(2026, 1, 8),
      status: ApplicationStatus.interview,
      confidence: 72,
      account: 'Gmail',
      source: 'LinkedIn',
      portalUrl: 'https://jobs.acmerobotics.com/position/1234',
      contact: 'recruiting@acmerobotics.com',
      nextStep: 'Interview scheduled',
      nextStepAt: DateTime(2026, 1, 15, 14, 0),
    ),
    Application(
      id: 'app_003',
      company: 'Futura Mobility',
      role: 'Product Manager',
      appliedOn: DateTime(2026, 1, 1),
      lastUpdated: DateTime(2026, 1, 6),
      status: ApplicationStatus.offer,
      confidence: 84,
      account: 'Northeastern',
      source: 'Referral',
      portalUrl: 'https://futura-mobility.com/careers/pm',
      contact: 'talent@futura-mobility.com',
      nextStep: 'Offer review',
      nextStepAt: DateTime(2026, 1, 10, 9, 0),
    ),
    Application(
      id: 'app_004',
      company: 'Kestrel AI',
      role: 'Research Engineer',
      appliedOn: DateTime(2025, 12, 28),
      lastUpdated: DateTime(2026, 1, 6),
      status: ApplicationStatus.applied,
      confidence: 58,
      account: 'Northeastern',
      source: 'Company Site',
      portalUrl: 'https://kestrel.ai/jobs/research',
      contact: 'hello@kestrel.ai',
      nextStep: 'Awaiting response',
    ),
    Application(
      id: 'app_005',
      company: 'Cloud Harbor',
      role: 'Backend Developer',
      appliedOn: DateTime(2026, 1, 4),
      lastUpdated: DateTime(2026, 1, 5),
      status: ApplicationStatus.underReview,
      confidence: 63,
      account: 'Northeastern',
      source: 'Referral',
      portalUrl: 'https://cloudharbor.io/careers/backend',
      contact: 'careers@cloudharbor.io',
      nextStep: 'Under review',
    ),
    Application(
      id: 'app_006',
      company: 'Granite Systems',
      role: 'DevOps Engineer',
      appliedOn: DateTime(2025, 12, 20),
      lastUpdated: DateTime(2026, 1, 3),
      status: ApplicationStatus.received,
      confidence: 49,
      account: 'Gmail',
      source: 'LinkedIn',
      portalUrl: 'https://granitesystems.com/jobs/devops',
      contact: 'hr@granitesystems.com',
      nextStep: 'Resume received',
    ),
    Application(
      id: 'app_007',
      company: 'Evergreen Health',
      role: 'QA Engineer',
      appliedOn: DateTime(2025, 12, 20),
      lastUpdated: DateTime(2025, 12, 26),
      status: ApplicationStatus.rejected,
      confidence: 31,
      account: 'Gmail',
      source: 'Company Site',
      portalUrl: 'https://evergreenhealth.com/jobs/qa',
      contact: 'talent@evergreenhealth.com',
      nextStep: 'Closed',
    ),
    Application(
      id: 'app_008',
      company: 'Harborline Tech',
      role: 'Frontend Engineer',
      appliedOn: DateTime(2025, 12, 18),
      lastUpdated: DateTime(2025, 12, 21),
      status: ApplicationStatus.interview,
      confidence: 66,
      account: 'Northeastern',
      source: 'Company Site',
      portalUrl: 'https://harborline.tech/jobs/frontend',
      contact: 'hello@harborline.tech',
      nextStep: 'Interview scheduled',
      nextStepAt: DateTime(2026, 1, 20, 15, 30),
    ),
  ];

  static final List<ActivityItem> updates = [
    ActivityItem(
      title: 'Delta Dynamics sent assessment',
      detail: 'Assessment link delivered',
      timestamp: DateTime(2026, 1, 9),
      kind: ActivityKind.update,
    ),
    ActivityItem(
      title: 'Cloud Harbor moved to review',
      detail: 'Recruiter reviewed application',
      timestamp: DateTime(2026, 1, 5),
      kind: ActivityKind.update,
    ),
    ActivityItem(
      title: 'Futura Mobility extended offer',
      detail: 'Offer package shared',
      timestamp: DateTime(2026, 1, 6),
      kind: ActivityKind.offer,
    ),
    ActivityItem(
      title: 'Granite Systems received resume',
      detail: 'Application received',
      timestamp: DateTime(2026, 1, 3),
      kind: ActivityKind.update,
    ),
    ActivityItem(
      title: 'Evergreen Health rejected',
      detail: 'Position closed',
      timestamp: DateTime(2025, 12, 26),
      kind: ActivityKind.rejection,
    ),
  ];

  static final List<ActivityItem> upcomingInterviews = [
    ActivityItem(
      title: 'Acme Robotics',
      detail: 'Interview • Jan 15, 2:00 PM',
      timestamp: DateTime(2026, 1, 15, 14, 0),
      kind: ActivityKind.interview,
    ),
    ActivityItem(
      title: 'Harborline Tech',
      detail: 'Interview • Jan 20, 3:30 PM',
      timestamp: DateTime(2026, 1, 20, 15, 30),
      kind: ActivityKind.interview,
    ),
  ];
}
