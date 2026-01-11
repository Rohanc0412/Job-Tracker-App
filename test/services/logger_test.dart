import 'package:flutter_test/flutter_test.dart';
import 'package:job_tracker/services/logger.dart';

void main() {
  test('redacts tokens and secrets', () {
    const message = 'Authorization: Bearer abc123\n'
        'access_token=xyz789\n'
        'password: hunter2';
    final redacted = AppLogger.redact(message);

    expect(redacted, contains('Authorization: Bearer [REDACTED]'));
    expect(redacted, contains('access_token=[REDACTED]'));
    expect(redacted, contains('password: [REDACTED]'));
    expect(redacted, isNot(contains('abc123')));
    expect(redacted, isNot(contains('xyz789')));
  });

  test('redacts email body lines', () {
    const message = 'subject: Interview\nbody: Hello there, here is the body';
    final redacted = AppLogger.redact(message);

    expect(redacted, contains('body: [REDACTED]'));
    expect(redacted, isNot(contains('Hello there')));
  });
}
