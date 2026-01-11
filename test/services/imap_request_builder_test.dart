import 'package:flutter_test/flutter_test.dart';
import 'package:job_tracker/services/imap/imap_request_builder.dart';

void main() {
  test('fetch uses BODY.PEEK and no STORE commands', () {
    final builder = ImapRequestBuilder();
    final fetch = builder.uidFetchHeadersAndBody(10, 1024);
    expect(fetch, contains('BODY.PEEK'));
    expect(fetch, contains('BODY.PEEK[TEXT]<0.1024>'));
    expect(fetch.toUpperCase().contains('STORE'), isFalse);
  });

  test('commands avoid STORE', () {
    final builder = ImapRequestBuilder();
    final commands = [
      builder.login('user@example.com', 'app-pass'),
      builder.select('INBOX'),
      builder.uidSearchSince(DateTime.utc(2026, 1, 1)),
      builder.uidSearchFrom(100),
      builder.logout(),
    ];
    for (final cmd in commands) {
      expect(cmd.toUpperCase().contains('STORE'), isFalse);
    }
  });
}
