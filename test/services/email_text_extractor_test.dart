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
  });
}
