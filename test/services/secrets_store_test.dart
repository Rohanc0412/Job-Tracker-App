import 'package:flutter_test/flutter_test.dart';
import 'package:job_tracker/services/secrets_store.dart';

class _MemorySecureStorage implements SecureStorage {
  final Map<String, String> _values = {};

  @override
  Future<void> write({required String key, required String value}) async {
    _values[key] = value;
  }

  @override
  Future<String?> read({required String key}) async {
    return _values[key];
  }

  @override
  Future<void> delete({required String key}) async {
    _values.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    _values.clear();
  }
}

void main() {
  test('stores and reads gmail credentials', () async {
    final store = SecretsStore(storage: _MemorySecureStorage());

    await store.saveGmailCredentials(
      email: 'user@example.com',
      appPassword: 'app-pass-123',
    );

    final creds = await store.readGmailCredentials();
    expect(creds, isNotNull);
    expect(creds!.email, 'user@example.com');
    expect(creds.appPassword, 'app-pass-123');

    await store.clearGmailCredentials();
    expect(await store.readGmailCredentials(), isNull);
  });

  test('stores and reads microsoft tokens', () async {
    final store = SecretsStore(storage: _MemorySecureStorage());

    await store.saveMicrosoftTokens(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
    );

    final tokens = await store.readMicrosoftTokens();
    expect(tokens, isNotNull);
    expect(tokens!.accessToken, 'access-token');
    expect(tokens.refreshToken, 'refresh-token');

    await store.clearMicrosoftTokens();
    expect(await store.readMicrosoftTokens(), isNull);
  });
}
