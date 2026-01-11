import 'package:flutter_test/flutter_test.dart';
import 'package:job_tracker/domain/ingestion/parser_rules.dart';

void main() {
  test('extracts and selects portal url', () {
    final text =
        'See https://jobs.bluefinch.io/positions/BE-4471?utm_source=mail '
        'and https://example.com/about';
    final urls = extractUrls(text);
    expect(urls.length, 2);

    final portal = selectPortalUrl(urls);
    expect(portal, 'https://jobs.bluefinch.io/positions/BE-4471');
  });

  test('sanitizes portal url tracking params', () {
    final url =
        'https://careers.crescent.ai/jobs/CAI-ML-8891?utm_source=mail&ref=offer';
    final sanitized = sanitizeUrl(url);
    expect(sanitized, 'https://careers.crescent.ai/jobs/CAI-ML-8891');
  });

  test('extracts job id from text and url', () {
    final text =
        'Job ID: NIM-DA-1023. Portal: https://careers.nimbus-analytics.com/jobs/NIM-DA-1023';
    final jobId = extractJobId(text);
    expect(jobId, 'NIM-DA-1023');

    final urlJobId = extractJobId(text,
        portalUrl: 'https://jobs.bluefinch.io/positions/BE-4471');
    expect(urlJobId, 'BE-4471');
  });

  test('extracts company from sender when subject is generic', () {
    final subject = 'Update on your DevOps Engineer application';
    final body = 'We appreciate your interest in Verdant Systems.';
    final fromAddr = 'Verdant Systems <recruiting@verdant.io>';
    final company = extractCompany(subject, body, fromAddr);
    expect(company, 'Verdant Systems');
  });
}
