import 'package:job_tracker/data/models/activity_item.dart';
import 'package:job_tracker/data/models/application.dart';
import 'package:job_tracker/data/repo/application_repo.dart';
import 'package:job_tracker/data/seed/seed_data.dart';

class FakeApplicationRepo implements ApplicationRepo {
  final List<Application> _applications;
  final List<ActivityItem> _updates;
  final List<ActivityItem> _upcoming;
  final Map<String, List<ActivityItem>> _timelines;

  FakeApplicationRepo({
    List<Application>? applications,
    List<ActivityItem>? updates,
    List<ActivityItem>? upcoming,
    Map<String, List<ActivityItem>>? timelines,
  })  : _applications = List<Application>.from(
          applications ?? SeedData.applications,
        ),
        _updates = List<ActivityItem>.from(updates ?? const []),
        _upcoming = List<ActivityItem>.from(upcoming ?? const []),
        _timelines = Map<String, List<ActivityItem>>.from(timelines ?? const {});

  @override
  Future<List<Application>> listApplications() async {
    return List<Application>.from(_applications);
  }

  @override
  Future<List<ActivityItem>> listRecentUpdates({int limit = 12}) async {
    if (_updates.length <= limit) {
      return List<ActivityItem>.from(_updates);
    }
    return _updates.take(limit).toList();
  }

  @override
  Future<List<ActivityItem>> listUpcomingInterviews() async {
    return List<ActivityItem>.from(_upcoming);
  }

  @override
  Future<List<ActivityItem>> listTimeline(String applicationId) async {
    return List<ActivityItem>.from(_timelines[applicationId] ?? const []);
  }

  @override
  Future<void> upsert(Application application) async {
    final index =
        _applications.indexWhere((candidate) => candidate.id == application.id);
    if (index == -1) {
      _applications.add(application);
    } else {
      _applications[index] = application;
    }
  }

  @override
  Future<void> delete(String id) async {
    _applications.removeWhere((application) => application.id == id);
  }
}
