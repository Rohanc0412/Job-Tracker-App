import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/open.dart';

String? configureSqliteForTests() {
  if (!Platform.isWindows) {
    return null;
  }

  final envPath = Platform.environment['JOB_TRACKER_SQLITE3_DLL'];
  final candidates = [
    if (envPath != null && envPath.isNotEmpty) envPath,
    p.join(
      Directory.current.path,
      'build',
      'windows',
      'x64',
      'plugins',
      'sqlite3_flutter_libs',
      'Debug',
      'sqlite3.dll',
    ),
    p.join(
      Directory.current.path,
      'build',
      'windows',
      'x64',
      'plugins',
      'sqlite3_flutter_libs',
      'Release',
      'sqlite3.dll',
    ),
    p.join(
      Directory.current.path,
      'build',
      'windows',
      'x64',
      'runner',
      'Debug',
      'sqlite3.dll',
    ),
    p.join(
      Directory.current.path,
      'build',
      'windows',
      'x64',
      'runner',
      'Release',
      'sqlite3.dll',
    ),
  ];

  for (final candidate in candidates) {
    if (!File(candidate).existsSync()) {
      continue;
    }
    try {
      final library = DynamicLibrary.open(candidate);
      open.overrideFor(OperatingSystem.windows, () => library);
      return null;
    } catch (_) {
      // Try the next candidate.
    }
  }

  return 'sqlite3.dll not found. Run `flutter build windows` or set JOB_TRACKER_SQLITE3_DLL.';
}
