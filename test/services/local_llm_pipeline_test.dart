import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:job_tracker/services/latest_message_extractor.dart';
import 'package:job_tracker/services/local_llm_pipeline.dart';
import 'package:job_tracker/services/ollama_endpoints.dart';

void main() {
  test('localhost enforcement rejects non-local URLs', () {
    expect(
      () => OllamaEndpoints.validateBaseUrl('https://localhost:11434'),
      throwsA(isA<StateError>()),
    );
    expect(
      () => OllamaEndpoints.validateBaseUrl('http://10.0.0.5:11434'),
      throwsA(isA<StateError>()),
    );
    expect(
      () => OllamaEndpoints.validateBaseUrl('http://localhost:1234'),
      throwsA(isA<StateError>()),
    );
  });

  test('schema retry path returns corrected json', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      if (calls == 1) {
        final invalid = jsonEncode({'relevant': true});
        return http.Response(
          jsonEncode({
            'message': {'content': invalid}
          }),
          200,
        );
      }
      final valid = {
        'relevant': true,
        'category': 'interview_invite',
        'confidence': 0.81,
        'company': 'Acme',
        'role': 'Backend Engineer',
        'jobId': null,
        'portalUrl': null,
        'status': 'interview',
        'interview': {
          'start': '2026-02-02T10:00:00Z',
          'end': null,
          'timezone': 'UTC',
          'location': null,
          'meetingUrl': null,
        },
        'summary': 'Interview invite from Acme.',
        'actionRequired': true,
        'actionItems': ['Confirm time'],
        'originalFromEmail': null,
        'originalToEmails': [],
        'evidence': [
          {
            'field': 'interview.timezone',
            'source': 'bodyText',
            'quote': 'UTC',
          }
        ],
      };
      final content = jsonEncode(valid);
      return http.Response(
        jsonEncode({
          'message': {'content': content}
        }),
        200,
      );
    });

    final pipeline = LocalLlmPipeline(
      config: const LocalLlmConfig(
        baseUrl: 'http://127.0.0.1:11434',
        modelId: 'test-model',
        requestTimeoutMs: 1000,
        maxInputChars: 2000,
      ),
      httpClient: client,
    );

    final context = extract_latest_message_context(
      bodyText: 'Interview on Feb 2 at 10:00 AM UTC.',
      bodyHtml: null,
      snippet: 'Interview on Feb 2 at 10:00 AM UTC',
      envelopeFrom: 'recruiter@acme.test',
      envelopeTo: 'me@example.com',
      subject: 'Interview invite',
      date: '2026-02-01T12:00:00Z',
    );
    final result = await pipeline.analyze(LlmEmailInput(
      context: context,
      snippet: 'Interview on Feb 2 at 10:00 AM UTC',
    ));

    expect(calls, 2);
    expect(result.relevant, isTrue);
    expect(result.extraction?.summary, 'Interview invite from Acme.');
  });

  test('timezone rule requires evidence', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      if (calls == 1) {
        final invalid = {
          'relevant': true,
          'category': 'interview_invite',
          'confidence': 0.6,
          'company': 'Acme',
          'role': 'Backend Engineer',
          'jobId': null,
          'portalUrl': null,
          'status': 'interview',
          'interview': {
            'start': '2026-02-02T10:00:00Z',
            'end': null,
            'timezone': 'UTC',
            'location': null,
            'meetingUrl': null,
          },
          'summary': 'Interview invite from Acme.',
          'actionRequired': true,
          'actionItems': [],
          'originalFromEmail': null,
          'originalToEmails': [],
          'evidence': [],
        };
        return http.Response(
          jsonEncode({
            'message': {'content': jsonEncode(invalid)}
          }),
          200,
        );
      }
      final irrelevant = {
        'relevant': false,
        'category': 'non_job',
        'confidence': 0.0,
        'reason': 'invalid',
      };
      return http.Response(
        jsonEncode({
          'message': {'content': jsonEncode(irrelevant)}
        }),
        200,
      );
    });

    final pipeline = LocalLlmPipeline(
      config: const LocalLlmConfig(
        baseUrl: 'http://127.0.0.1:11434',
        modelId: 'test-model',
        requestTimeoutMs: 1000,
        maxInputChars: 2000,
      ),
      httpClient: client,
    );

    final context = extract_latest_message_context(
      bodyText: 'Interview on Feb 2 at 10:00 AM UTC.',
      bodyHtml: null,
      snippet: 'Interview on Feb 2 at 10:00 AM UTC',
      envelopeFrom: 'recruiter@acme.test',
      envelopeTo: 'me@example.com',
      subject: 'Interview invite',
      date: '2026-02-01T12:00:00Z',
    );
    final result = await pipeline.analyze(LlmEmailInput(
      context: context,
      snippet: 'Interview on Feb 2 at 10:00 AM UTC',
    ));

    expect(calls, 1);
    expect(result.relevant, isTrue);
  });

  test('keep_alive unload request sent at end of sync', () async {
    final payloads = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      payloads.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response('{}', 200);
    });

    final pipeline = LocalLlmPipeline(
      config: const LocalLlmConfig(
        baseUrl: 'http://127.0.0.1:11434',
        modelId: 'test-model',
        requestTimeoutMs: 1000,
        maxInputChars: 2000,
      ),
      httpClient: client,
    );

    await pipeline.preload();
    await pipeline.unload();

    expect(payloads.length, 2);
    expect(payloads[0]['keep_alive'], '20m');
    expect(payloads[1]['keep_alive'], '0');
    expect(payloads[0]['messages'], isEmpty);
  });
}
