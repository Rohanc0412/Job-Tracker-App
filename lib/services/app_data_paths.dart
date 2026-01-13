import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AppDataPaths {
  static const String dbFileName = 'job_tracker.db';
  static const String settingsFileName = 'settings.json';
  static const String rawBodiesDirName = 'raw_bodies';
  static const String logFileName = 'job_tracker.log';

  static Future<Directory> ensureSupportDir() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    await _restrictDirectory(dir);
    return dir;
  }

  static Future<String> databasePath() async {
    final dir = await ensureSupportDir();
    final path = p.join(dir.path, dbFileName);
    await _ensureSecureFile(path);
    return path;
  }

  static Future<String> databaseFilePath() async {
    final dir = await getApplicationSupportDirectory();
    return p.join(dir.path, dbFileName);
  }

  static Future<File> settingsFile() async {
    final dir = await ensureSupportDir();
    final file = File(p.join(dir.path, settingsFileName));
    await _ensureSecureFile(file.path);
    return file;
  }

  static Future<String> logFilePath() async {
    final dir = await ensureSupportDir();
    final path = p.join(dir.path, logFileName);
    await _ensureSecureFile(path);
    return path;
  }

  static Future<Directory> rawBodiesDir({bool ensure = true}) async {
    final baseDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(baseDir.path, rawBodiesDirName));
    if (ensure) {
      await dir.create(recursive: true);
      await _restrictDirectory(dir);
    }
    return dir;
  }

  static Future<void> _restrictDirectory(Directory dir) async {
    if (Platform.isWindows) {
      return;
    }
    try {
      await Process.run('chmod', ['700', dir.path]);
    } catch (_) {
      // Best-effort hardening; ignore errors.
    }
  }

  static Future<void> _ensureSecureFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    if (Platform.isWindows) {
      return;
    }
    try {
      await Process.run('chmod', ['600', path]);
    } catch (_) {
      // Best-effort hardening; ignore errors.
    }
  }
}
