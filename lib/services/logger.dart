import 'package:logging/logging.dart';

class AppLogger {
  static Logger get log => Logger('JobTracker');

  static void setup({Level level = Level.INFO}) {
    Logger.root.level = level;
    Logger.root.onRecord.listen((record) {
      // Simple console output for now.
      // ignore: avoid_print
      print('[${record.level.name}] ${record.time}: ${record.message}');
    });
  }
}
