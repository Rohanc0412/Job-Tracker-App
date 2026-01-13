import 'package:flutter_test/flutter_test.dart';
import 'package:job_tracker/services/email_text_extractor.dart';

void main() {
  group('EmailTextExtractor', () {
    test('extracts plain text from plain text email', () {
      const plainText = '''Hello Rohan,

Thanks for applying for the Data Analyst role at Nimbus Analytics. Your application has been received and is under review.
Job ID: NIM-DA-1023
Portal: https://careers.nimbus-analytics.com/jobs/NIM-DA-1023

Best,
Nimbus Analytics Recruiting''';

      final result = EmailTextExtractor.extractCleanText(plainText);

      expect(result, contains('Hello Rohan'));
      expect(result, contains('Data Analyst'));
      expect(result, contains('NIM-DA-1023'));
    });

    test('extracts text from simple HTML email', () {
      const htmlEmail = '''<html>
<body>
<p>Hello Rohan,</p>
<p>Thanks for applying for the <strong>Data Analyst</strong> role.</p>
<p>Job ID: NIM-DA-1023</p>
</body>
</html>''';

      final result = EmailTextExtractor.extractCleanText(htmlEmail);

      expect(result, contains('Hello Rohan'));
      expect(result, contains('Data Analyst'));
      expect(result, contains('Job ID: NIM-DA-1023'));
      expect(result, isNot(contains('<p>')));
      expect(result, isNot(contains('<strong>')));
    });

    test('removes script and style tags', () {
      const htmlEmail = '''<html>
<head>
<style>body { color: red; }</style>
</head>
<body>
<script>alert('test');</script>
<p>Hello Rohan</p>
</body>
</html>''';

      final result = EmailTextExtractor.extractCleanText(htmlEmail);

      expect(result, contains('Hello Rohan'));
      expect(result, isNot(contains('color: red')));
      expect(result, isNot(contains('alert')));
    });

    test('decodes HTML entities', () {
      const htmlEmail = '''<html>
<body>
<p>Hello &amp; welcome!</p>
<p>Price: &pound;50</p>
<p>&ldquo;Great job&rdquo;</p>
</body>
</html>''';

      final result = EmailTextExtractor.extractCleanText(htmlEmail);

      expect(result, contains('&'));
      expect(result, contains('Great job'));
    });

    test('preserves line breaks for block elements', () {
      const htmlEmail = '''<html>
<body>
<p>First paragraph</p>
<p>Second paragraph</p>
<div>Third section</div>
</body>
</html>''';

      final result = EmailTextExtractor.extractCleanText(htmlEmail);

      expect(result, contains('First paragraph'));
      expect(result, contains('Second paragraph'));
      expect(result, contains('Third section'));
      // Should have line breaks between paragraphs
      expect(result.split('\n').length, greaterThan(1));
    });

    test('getPreview truncates long text', () {
      final longText = 'a' * 300;
      final preview = EmailTextExtractor.getPreview(longText, maxLength: 200);

      expect(preview.length, lessThanOrEqualTo(203)); // 200 + '...'
      expect(preview, endsWith('...'));
    });

    test('getPreview returns full text if short enough', () {
      const shortText = 'Hello Rohan, welcome!';
      final preview = EmailTextExtractor.getPreview(shortText, maxLength: 200);

      expect(preview, equals(shortText));
      expect(preview, isNot(contains('...')));
    });

    test('normalizeSeparators normalizes common delimiters', () {
      const rawText = 'Role | Data Analyst\u00b7Remote\u2014Full-time';
      final normalized = EmailTextExtractor.normalizeSeparators(rawText);

      expect(normalized, contains('Role : Data Analyst-Remote-Full-time'));
    });

    test('reply chain stripping works', () {
      const rawText = '''Thanks for the update.

-----Original Message-----
From: Hiring Team <jobs@example.com>
Sent: Monday, Jan 1, 2024 9:00 AM
To: Rohan <rohan@example.com>
Subject: Interview request''';

      final cleaned = EmailTextExtractor.extractCleanText(rawText);

      expect(cleaned, contains('Thanks for the update.'));
      expect(cleaned, isNot(contains('Original Message')));
      expect(cleaned, isNot(contains('Interview request')));
    });

    test('disclaimer stripping works', () {
      const rawText = '''Hello Rohan,

We received your application.

This email and any attachments are confidential.''';

      final cleaned = EmailTextExtractor.extractCleanText(rawText);

      expect(cleaned, contains('We received your application.'));
      expect(cleaned, isNot(contains('This email and any attachments')));
    });

    test('topSection keeps only the first N non-empty lines', () {
      const rawText = '''Line 1

Line 2
Line 3

Line 4''';

      final top = EmailTextExtractor.topSection(rawText, maxLines: 2);

      expect(top, equals('Line 1\nLine 2'));
    });

    test('extractCleanText removes multipart boundaries and headers', () {
      const rawText = '''--boundary123
Content-Type: text/plain; charset="UTF-8"

Hello there
--boundary123
Content-Type: text/html; charset="UTF-8"

<p>Hello there</p>
--boundary123--''';

      final cleaned = EmailTextExtractor.extractCleanText(rawText);

      expect(cleaned, equals('Hello there'));
      expect(cleaned, isNot(contains('Content-Type:')));
      expect(cleaned, isNot(contains('--boundary123')));
    });

    test('decodeMimeHeader decodes encoded-word subjects', () {
      const encoded = '=?UTF-8?B?SGVsbG8gV29ybGQh?=';
      final decoded = EmailTextExtractor.decodeMimeHeader(encoded);

      expect(decoded, equals('Hello World!'));
    });

    test('decodeMimeHeader handles windows-1252 encoded words', () {
      const encoded = '=?windows-1252?Q?Hello_=93World=94?=';
      final decoded = EmailTextExtractor.decodeMimeHeader(encoded);

      expect(decoded, equals('Hello “World”'));
    });

    test('extractCleanText keeps forwarded content when header block is top', () {
      const rawText = '''________________________________
From: noreply@example.com
Sent: Wed, 10 Dec 2025 20:41
To: me@example.com
Subject: Application Confirmation

Your application has been received.
Thank you.''';

      final cleaned = EmailTextExtractor.extractCleanText(rawText);

      expect(cleaned, contains('Your application has been received.'));
      expect(cleaned, isNot(contains('From: noreply@example.com')));
    });

    test('extractCleanText keeps reply content and strips quoted thread', () {
      const rawText = '''Thanks — confirmed!

On Mon, Jan 1, 2024 at 9:00 AM Hiring Team <jobs@example.com> wrote:
> From: Hiring Team <jobs@example.com>
> Sent: Monday, Jan 1, 2024 9:00 AM
> To: Me <me@example.com>
> Subject: Interview request
>
> Original message body.''';

      final cleaned = EmailTextExtractor.extractCleanText(rawText);

      expect(cleaned, contains('Thanks'));
      expect(cleaned, contains('confirmed!'));
      expect(cleaned, isNot(contains('Original message body')));
    });

    test('extractCleanText avoids empty output for quote-only replies', () {
      const rawText = '''On Mon, Jan 1, 2024 at 9:00 AM Hiring Team wrote:
> Hello there
> This is the original message.''';

      final cleaned = EmailTextExtractor.extractCleanText(rawText);

      expect(cleaned, contains('Hello there'));
      expect(cleaned, isNot(equals('')));
    });
  });
}
