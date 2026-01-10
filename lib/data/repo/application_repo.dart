import '../models/application.dart';

abstract class ApplicationRepo {
  Future<List<Application>> listAll();
  Future<void> upsert(Application application);
  Future<void> delete(String id);
}
