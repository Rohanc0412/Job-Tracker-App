import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class SecureStorage {
  Future<void> write({required String key, required String value});
  Future<String?> read({required String key});
  Future<void> delete({required String key});
  Future<void> deleteAll();
}

class FlutterSecureStorageAdapter implements SecureStorage {
  final FlutterSecureStorage _storage;

  const FlutterSecureStorageAdapter([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<void> write({required String key, required String value}) {
    return _storage.write(key: key, value: value);
  }

  @override
  Future<String?> read({required String key}) {
    return _storage.read(key: key);
  }

  @override
  Future<void> delete({required String key}) {
    return _storage.delete(key: key);
  }

  @override
  Future<void> deleteAll() {
    return _storage.deleteAll();
  }
}

class GmailCredentials {
  final String email;
  final String appPassword;

  const GmailCredentials({
    required this.email,
    required this.appPassword,
  });
}

class MicrosoftTokens {
  final String accessToken;
  final String refreshToken;

  const MicrosoftTokens({
    required this.accessToken,
    required this.refreshToken,
  });
}

class SecretsStore {
  static const String _prefix = 'job_tracker.';
  static const String _gmailEmailKey = '${_prefix}gmail.email';
  static const String _gmailAppPasswordKey = '${_prefix}gmail.app_password';
  static const String _msAccessTokenKey = '${_prefix}ms.access_token';
  static const String _msRefreshTokenKey = '${_prefix}ms.refresh_token';
  static const String _openAiApiKey = '${_prefix}openai.api_key';

  SecretsStore({SecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorageAdapter();

  final SecureStorage _storage;

  Future<void> saveGmailCredentials({
    required String email,
    required String appPassword,
  }) async {
    await _storage.write(key: _gmailEmailKey, value: email);
    await _storage.write(key: _gmailAppPasswordKey, value: appPassword);
  }

  Future<GmailCredentials?> readGmailCredentials() async {
    final email = await _storage.read(key: _gmailEmailKey);
    final appPassword = await _storage.read(key: _gmailAppPasswordKey);
    if (email == null || appPassword == null) {
      return null;
    }
    return GmailCredentials(email: email, appPassword: appPassword);
  }

  Future<void> clearGmailCredentials() async {
    await _storage.delete(key: _gmailEmailKey);
    await _storage.delete(key: _gmailAppPasswordKey);
  }

  Future<void> saveMicrosoftTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _msAccessTokenKey, value: accessToken);
    await _storage.write(key: _msRefreshTokenKey, value: refreshToken);
  }

  Future<MicrosoftTokens?> readMicrosoftTokens() async {
    final accessToken = await _storage.read(key: _msAccessTokenKey);
    final refreshToken = await _storage.read(key: _msRefreshTokenKey);
    if (accessToken == null || refreshToken == null) {
      return null;
    }
    return MicrosoftTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
  }

  Future<void> clearMicrosoftTokens() async {
    await _storage.delete(key: _msAccessTokenKey);
    await _storage.delete(key: _msRefreshTokenKey);
  }

  Future<void> saveOpenAiApiKey(String apiKey) async {
    await _storage.write(key: _openAiApiKey, value: apiKey);
  }

  Future<String?> readOpenAiApiKey() async {
    return _storage.read(key: _openAiApiKey);
  }

  Future<void> clearOpenAiApiKey() async {
    await _storage.delete(key: _openAiApiKey);
  }

  Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
