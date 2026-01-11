import 'package:flutter/material.dart';

import 'app.dart';
import 'services/logger.dart';
import 'services/settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SettingsStore.instance.load();
  AppLogger.setup();
  runApp(const JobTrackerApp());
}
