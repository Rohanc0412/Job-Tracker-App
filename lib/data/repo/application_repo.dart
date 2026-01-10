import '../models/activity_item.dart';
import '../models/application.dart';

abstract class ApplicationRepo {
  Future<List<Application>> listApplications();
  Future<List<ActivityItem>> listRecentUpdates({int limit = 12});
  Future<List<ActivityItem>> listUpcomingInterviews();
  Future<List<ActivityItem>> listTimeline(String applicationId);

  Future<void> upsert(Application application);
  Future<void> delete(String id);
}
