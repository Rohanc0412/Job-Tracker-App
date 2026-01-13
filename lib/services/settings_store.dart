import 'dart:convert';
import 'dart:io';

import 'app_data_paths.dart';

class SettingsStore {
  SettingsStore._({Future<File> Function()? fileResolver})
      : _fileResolver = fileResolver ?? AppDataPaths.settingsFile;

  static final SettingsStore instance = SettingsStore._();

  factory SettingsStore.forTesting({Future<File> Function()? fileResolver}) {
    return SettingsStore._(fileResolver: fileResolver);
  }

  final Future<File> Function() _fileResolver;
  final Map<String, Object?> _values = {};
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) {
      return;
    }
    final file = await _fileResolver();
    print('[SettingsStore] Loading from: ${file.path}');
    if (await file.exists()) {
      try {
        final raw = await file.readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          _values
            ..clear()
            ..addAll(decoded);
          print('[SettingsStore] Loaded settings: ${_values.keys.toList()}');
          if (_values.containsKey('skipSeed')) {
            print('[SettingsStore] skipSeed = ${_values['skipSeed']}');
          }
        }
      } catch (e) {
        print('[SettingsStore] Error loading settings: $e');
        // Ignore malformed settings; defaults will apply.
      }
    } else {
      print('[SettingsStore] Settings file does not exist, starting fresh');
    }
    _loaded = true;
  }

  T? get<T>(String key) => _values[key] as T?;

  Future<void> set<T>(String key, T value) async {
    print('[SettingsStore] Setting $key = $value');
    _values[key] = value;
    await _persist();
  }

  Future<void> remove(String key) async {
    _values.remove(key);
    await _persist();
  }

  Future<void> clear() async {
    _values.clear();
    await _persist();
  }

  Future<void> _persist() async {
    final file = await _fileResolver();
    final json = jsonEncode(_values);
    await file.writeAsString(json, flush: true);
  }
}
