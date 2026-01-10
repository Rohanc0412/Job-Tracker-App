import '../models/application.dart';
import '../../domain/status/status_types.dart';

class SeedData {
  static List<Application> initialApplications() {
    return [
      Application(
        id: 'app_001',
        company: 'Example Co',
        role: 'Senior Engineer',
        appliedOn: DateTime.now().subtract(const Duration(days: 3)),
        lastUpdated: DateTime.now().subtract(const Duration(days: 1)),
        status: ApplicationStatus.applied,
        confidence: 62,
        account: 'Gmail',
        source: 'Company Site',
      ),
      Application(
        id: 'app_002',
        company: 'Acme Labs',
        role: 'Platform Engineer',
        appliedOn: DateTime.now().subtract(const Duration(days: 10)),
        lastUpdated: DateTime.now().subtract(const Duration(days: 2)),
        status: ApplicationStatus.interview,
        confidence: 74,
        account: 'Gmail',
        source: 'LinkedIn',
      ),
    ];
  }
}
