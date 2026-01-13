import 'package:flutter_test/flutter_test.dart';
import 'package:job_tracker/services/latest_message_extractor.dart';

void main() {
  test('reply trimming keeps latest message only', () {
    const body = 'Hi team,\n'
        'Here is my availability for next week.\n'
        '\n'
        'On Mon, Jan 8, 2026 at 9:00 AM Jane Doe wrote:\n'
        '> Thanks for applying.\n'
        '> Can you share availability?\n';
    final context = extract_latest_message_context(
      bodyText: body,
      bodyHtml: null,
      snippet: null,
      envelopeFrom: 'candidate@example.com',
      envelopeTo: 'recruiter@example.com',
      subject: 'Availability',
      date: '2026-01-09T10:00:00Z',
      maxInputChars: 5000,
    );
    expect(context.latestText.contains('availability for next week'), isTrue);
    expect(context.latestText.contains('Thanks for applying'), isFalse);
  });

  test('forwarded parser extracts original from and to', () {
    const body = '---------- Forwarded message ---------\n'
        'From: Alexis Rivera <alexis@acme.test>\n'
        'To: Sam Lee <sam@jobs.test>, team@jobs.test\n'
        'Cc: hiring@acme.test\n'
        'Date: Mon, Jan 8, 2026 at 10:00 AM\n'
        'Subject: Interview request\n'
        '\n'
        'Hello Sam,\n'
        'Can we schedule an interview?\n';
    final context = extract_latest_message_context(
      bodyText: body,
      bodyHtml: null,
      snippet: null,
      envelopeFrom: 'forwarder@example.com',
      envelopeTo: 'me@example.com',
      subject: 'Fwd: Interview request',
      date: '2026-01-09T10:00:00Z',
      maxInputChars: 5000,
    );
    final forwarded = context.forwarded;
    expect(forwarded, isNotNull);
    expect(forwarded?.originalFromEmail, 'alexis@acme.test');
    expect(
      forwarded?.originalToEmails,
      ['sam@jobs.test', 'team@jobs.test'],
    );
    expect(
      forwarded?.originalCcEmails,
      ['hiring@acme.test'],
    );
    expect(context.latestText.contains('schedule an interview'), isTrue);
  });
}
