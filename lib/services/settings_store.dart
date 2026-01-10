class SettingsStore {
  final Map<String, Object?> _values = {};

  T? get<T>(String key) => _values[key] as T?;

  void set<T>(String key, T value) {
    _values[key] = value;
  }
}
