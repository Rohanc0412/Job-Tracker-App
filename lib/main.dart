import 'package:flutter/material.dart';

import 'app.dart';
import 'services/app_data_paths.dart';
import 'services/logger.dart';
import 'services/settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SettingsStore.instance.load();
  final logPath = await AppDataPaths.logFilePath();
  AppLogger.setup(redactMessages: false, logFilePath: logPath);
  AppLogger.log.info('[AppLogger] Log file: $logPath');
  runApp(const JobTrackerApp());
}
