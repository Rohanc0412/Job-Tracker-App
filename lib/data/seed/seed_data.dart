import '../models/application.dart';
import '../models/email_event.dart';
import '../models/interview_event.dart';
import '../../domain/status/status_types.dart';

class SeedAccount {
  final String id;
  final String label;
  final String provider;
  final DateTime createdAt;

  const SeedAccount({
    required this.id,
    required this.label,
    required this.provider,
    required this.createdAt,
  });
}

class SeedSyncState {
  final String id;
  final String accountLabel;
  final String provider;
  final String folder;
  final String cursorKey;
  final String cursorValue;
  final DateTime lastSyncTime;

  const SeedSyncState({
    required this.id,
    required this.accountLabel,
    required this.provider,
    required this.folder,
    required this.cursorKey,
    required this.cursorValue,
    required this.lastSyncTime,
  });
}

class SeedData {
  static final List<SeedAccount> accounts = [
    SeedAccount(
      id: 'acct_gmail',
      label: 'Gmail',
      provider: 'gmail',
      createdAt: DateTime(2026, 1, 1, 8, 30),
    ),
    SeedAccount(
      id: 'acct_northeastern',
      label: 'Northeastern',
      provider: 'outlook',
      createdAt: DateTime(2026, 1, 1, 9, 0),
    ),
  ];

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

  static final List<EmailEvent> emailEvents = [
    EmailEvent(
      id: 'email_001',
      applicationId: 'app_001',
      accountLabel: 'Gmail',
      provider: 'gmail',
      folder: 'INBOX',
      cursorValue: 'cur_1001',
      messageId: '<msg-001@deltadynamics>',
      subject: 'Assessment link for ML Engineer role',
      fromAddr: 'hiring@deltadynamics.com',
      date: DateTime(2026, 1, 9, 9, 15),
      extractedStatus: 'assessment',
      extractedFieldsJson: '{"assessment":"take-home"}',
      evidenceSnippet: 'Assessment link delivered for review.',
      rawBodyText: '''Hello,

Thank you for your interest in the ML Engineer role at Delta Dynamics. We were impressed with your background and would like to move forward with the next step.

Please complete the technical assessment at the link below. The assessment should take approximately 2-3 hours and covers machine learning fundamentals, data processing, and model evaluation.

Assessment Link: https://assessments.deltadynamics.com/ml-eng-2026

You'll have 7 days to complete the assessment. Once submitted, our team will review it within 3-5 business days.

If you have any questions, feel free to reach out.

Best regards,
Delta Dynamics Hiring Team''',
      hash: 'hash_email_001',
      isSignificantUpdate: true,
    ),
    EmailEvent(
      id: 'email_002',
      applicationId: 'app_002',
      accountLabel: 'Gmail',
      provider: 'gmail',
      folder: 'INBOX',
      cursorValue: 'cur_1002',
      messageId: '<msg-002@acmerobotics>',
      subject: 'Interview scheduled for Software Engineer',
      fromAddr: 'recruiting@acmerobotics.com',
      date: DateTime(2026, 1, 8, 13, 40),
      extractedStatus: 'interview',
      extractedFieldsJson: '{"stage":"phone screen"}',
      evidenceSnippet: 'Interview scheduled for Jan 15, 2:00 PM.',
      rawBodyText: '''Hi there,

Great news! We'd like to schedule a phone screen interview with you for the Software Engineer position at Acme Robotics.

Interview Details:
Date: Wednesday, January 15, 2026
Time: 2:00 PM - 2:45 PM EST
Format: Video call
Meeting Link: https://meet.acmerobotics.com/room/eng-123

You'll be speaking with Sarah Chen, our Engineering Manager. The interview will cover your background, technical experience, and fit for the team.

Please confirm your availability by replying to this email.

Looking forward to speaking with you!

Best,
Acme Robotics Recruiting Team''',
      hash: 'hash_email_002',
      isSignificantUpdate: true,
    ),
    EmailEvent(
      id: 'email_003',
      applicationId: 'app_003',
      accountLabel: 'Northeastern',
      provider: 'outlook',
      folder: 'INBOX',
      cursorValue: 'cur_2001',
      messageId: '<msg-003@futuramobility>',
      subject: 'Offer details for Product Manager',
      fromAddr: 'talent@futura-mobility.com',
      date: DateTime(2026, 1, 6, 16, 5),
      extractedStatus: 'offer',
      extractedFieldsJson: '{"offer":"extended"}',
      evidenceSnippet: 'Offer package shared and ready for review.',
      rawBodyText: '''Dear Candidate,

Congratulations! We're excited to extend an offer for the Product Manager position at Futura Mobility.

Offer Summary:
• Base Salary: \$135,000 annually
• Equity: Stock options worth 0.15% of company
• Benefits: Health, dental, vision, 401k matching
• Start Date: February 3, 2026
• Location: Boston, MA (Hybrid - 3 days/week in office)

The full offer letter is attached to this email with complete details of compensation, benefits, and terms.

We believe you'll be a great addition to our team and look forward to working with you. Please review the offer and let us know if you have any questions.

To accept, please sign and return the offer letter by January 10, 2026.

Welcome to Futura Mobility!

Best regards,
Lisa Park
Head of Talent
Futura Mobility''',
      hash: 'hash_email_003',
      isSignificantUpdate: true,
    ),
    EmailEvent(
      id: 'email_004',
      applicationId: 'app_005',
      accountLabel: 'Northeastern',
      provider: 'outlook',
      folder: 'INBOX',
      cursorValue: 'cur_2002',
      messageId: '<msg-004@cloudharbor>',
      subject: 'Application moved to review',
      fromAddr: 'careers@cloudharbor.io',
      date: DateTime(2026, 1, 5, 11, 20),
      extractedStatus: 'underReview',
      extractedFieldsJson: '{"status":"under_review"}',
      evidenceSnippet: 'Recruiter reviewed application.',
      rawBodyText: '''Hello,

Thank you for applying for the Backend Developer position at Cloud Harbor.

Your application has been reviewed and moved to the next stage. Our engineering team is currently evaluating your profile and technical background.

We'll be in touch within the next 7-10 business days regarding next steps. In the meantime, feel free to explore our engineering blog at https://blog.cloudharbor.io to learn more about our tech stack and culture.

Thank you for your patience.

Cloud Harbor Careers Team''',
      hash: 'hash_email_004',
      isSignificantUpdate: true,
    ),
    EmailEvent(
      id: 'email_005',
      applicationId: 'app_006',
      accountLabel: 'Gmail',
      provider: 'gmail',
      folder: 'INBOX',
      cursorValue: 'cur_1003',
      messageId: '<msg-005@granitesystems>',
      subject: 'Resume received for DevOps Engineer',
      fromAddr: 'hr@granitesystems.com',
      date: DateTime(2026, 1, 3, 8, 45),
      extractedStatus: 'received',
      extractedFieldsJson: '{"status":"received"}',
      evidenceSnippet: 'Application received and logged.',
      rawBodyText: '''Dear Applicant,

Thank you for your application for the DevOps Engineer position at Granite Systems. We have received your resume and it has been logged in our system.

Application Reference: GS-DEVOPS-2026-143

Our hiring team reviews all applications on a rolling basis. If your qualifications match our requirements, a recruiter will reach out to schedule an initial conversation.

We appreciate your interest in Granite Systems.

Best regards,
Granite Systems HR''',
      hash: 'hash_email_005',
      isSignificantUpdate: true,
    ),
    EmailEvent(
      id: 'email_006',
      applicationId: 'app_007',
      accountLabel: 'Gmail',
      provider: 'gmail',
      folder: 'INBOX',
      cursorValue: 'cur_1004',
      messageId: '<msg-006@evergreenhealth>',
      subject: 'Application status update',
      fromAddr: 'talent@evergreenhealth.com',
      date: DateTime(2025, 12, 26, 10, 10),
      extractedStatus: 'rejected',
      extractedFieldsJson: '{"status":"closed"}',
      evidenceSnippet: 'Position closed.',
      rawBodyText: '''Dear Candidate,

Thank you for your interest in the QA Engineer position at Evergreen Health.

After careful consideration, we have decided to move forward with other candidates whose qualifications more closely align with our current needs. This was a competitive process and we appreciate the time you invested in your application.

We encourage you to apply for future openings that match your skills and experience. You can view our current opportunities at https://evergreenhealth.com/careers

We wish you the best in your job search.

Sincerely,
Evergreen Health Talent Team''',
      hash: 'hash_email_006',
      isSignificantUpdate: true,
    ),
  ];

  static final List<InterviewEvent> interviewEvents = [
    InterviewEvent(
      id: 'int_001',
      applicationId: 'app_002',
      accountLabel: 'Gmail',
      messageId: '<msg-002@acmerobotics>',
      startTime: DateTime(2026, 1, 15, 14, 0),
      endTime: DateTime(2026, 1, 15, 14, 45),
      timezone: 'America/New_York',
      location: 'Video call',
      meetingUrl: 'https://meet.acmerobotics.com/room/eng-123',
      source: 'calendar',
      confidence: 0.92,
      createdAt: DateTime(2026, 1, 8, 13, 50),
    ),
    InterviewEvent(
      id: 'int_002',
      applicationId: 'app_008',
      accountLabel: 'Northeastern',
      messageId: '<msg-007@harborline>',
      startTime: DateTime(2026, 1, 20, 15, 30),
      endTime: DateTime(2026, 1, 20, 16, 15),
      timezone: 'America/New_York',
      location: 'Harborline HQ',
      meetingUrl: 'https://harborline.tech/interviews/frontend',
      source: 'calendar',
      confidence: 0.88,
      createdAt: DateTime(2026, 1, 7, 9, 15),
    ),
  ];

  static final List<SeedSyncState> syncStates = [
    SeedSyncState(
      id: 'sync_001',
      accountLabel: 'Gmail',
      provider: 'gmail',
      folder: 'INBOX',
      cursorKey: 'gmail_history_id',
      cursorValue: 'hist_1001',
      lastSyncTime: DateTime(2026, 1, 9, 9, 30),
    ),
    SeedSyncState(
      id: 'sync_002',
      accountLabel: 'Northeastern',
      provider: 'outlook',
      folder: 'INBOX',
      cursorKey: 'outlook_delta_link',
      cursorValue: 'delta_2001',
      lastSyncTime: DateTime(2026, 1, 6, 16, 20),
    ),
  ];
}
