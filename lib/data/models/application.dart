import '../../domain/status/status_types.dart';

class Application {
  final String id;
  final String company;
  final String role;
  final DateTime appliedOn;
  final DateTime lastUpdated;
  final ApplicationStatus status;
  final int confidence;
  final String account;
  final String source;
  final String? jobId;
  final String? portalUrl;
  final String? contact;
  final String? nextStep;
  final DateTime? nextStepAt;

  const Application({
    required this.id,
    required this.company,
    required this.role,
    required this.appliedOn,
    required this.lastUpdated,
    required this.status,
    required this.confidence,
    required this.account,
    required this.source,
    this.jobId,
    this.portalUrl,
    this.contact,
    this.nextStep,
    this.nextStepAt,
  });

  Application copyWith({
    String? id,
    String? company,
    String? role,
    DateTime? appliedOn,
    DateTime? lastUpdated,
    ApplicationStatus? status,
    int? confidence,
    String? account,
    String? source,
    String? jobId,
    String? portalUrl,
    String? contact,
    String? nextStep,
    DateTime? nextStepAt,
  }) {
    return Application(
      id: id ?? this.id,
      company: company ?? this.company,
      role: role ?? this.role,
      appliedOn: appliedOn ?? this.appliedOn,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      status: status ?? this.status,
      confidence: confidence ?? this.confidence,
      account: account ?? this.account,
      source: source ?? this.source,
      jobId: jobId ?? this.jobId,
      portalUrl: portalUrl ?? this.portalUrl,
      contact: contact ?? this.contact,
      nextStep: nextStep ?? this.nextStep,
      nextStepAt: nextStepAt ?? this.nextStepAt,
    );
  }
}
