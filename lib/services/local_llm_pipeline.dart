import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'logger.dart';
import 'latest_message_extractor.dart';
import 'ollama_endpoints.dart';

class LocalLlmConfig {
  final String baseUrl;
  final String modelId;
  final int requestTimeoutMs;
  final int maxInputChars;

  const LocalLlmConfig({
    required this.baseUrl,
    required this.modelId,
    required this.requestTimeoutMs,
    required this.maxInputChars,
  });
}

class OpenAiLlmConfig {
  final String baseUrl;
  final String modelId;
  final String apiKey;
  final int requestTimeoutMs;
  final int maxInputChars;

  const OpenAiLlmConfig({
    required this.baseUrl,
    required this.modelId,
    required this.apiKey,
    required this.requestTimeoutMs,
    required this.maxInputChars,
  });
}

class LlmEmailInput {
  final LatestMessageContext context;
  final String snippet;

  const LlmEmailInput({
    required this.context,
    required this.snippet,
  });
}

abstract class LlmEmailAnalyzer {
  Future<LlmEmailResult> analyze(LlmEmailInput input);
}

abstract class LlmModelLifecycle {
  Future<void> preload();
  Future<void> unload();
}

class LocalLlmPipeline implements LlmEmailAnalyzer, LlmModelLifecycle {
  LocalLlmPipeline({
    required LocalLlmConfig config,
    http.Client? httpClient,
  })  : _config = config,
        _client = LocalOllamaClient(config, httpClient: httpClient);

  static const String _keepAlive = '20m';
  static const double _temperature = 0.0;
  static const int _maxTokens = 500;

  final LocalLlmConfig _config;
  final LocalOllamaClient _client;

  @override
  Future<void> preload() async {
    await _client.keepAlive(_keepAlive);
  }

  @override
  Future<void> unload() async {
    await _client.keepAlive('0');
  }

  @override
  Future<LlmEmailResult> analyze(LlmEmailInput input) async {
    final inputText = _formatLlmInput(input);
    final messages = [
      {'role': 'system', 'content': _systemPrompt},
      {'role': 'user', 'content': inputText},
    ];
    AppLogger.log.info('[LocalLlm] Prompt system:\n$_systemPrompt');
    AppLogger.log.info('[LocalLlm] Prompt user:\n$inputText');

    final initial = await _client.chat(
      messages: messages,
      keepAlive: _keepAlive,
      temperature: _temperature,
      maxTokens: _maxTokens,
    );
    AppLogger.log.info('[LocalLlm] Raw response (initial): $initial');
    final initialResult = _validateAndParse(initial, input: input);
    if (initialResult.isValid) {
      final result = initialResult.result!;
      if (!result.relevant && _shouldForceRelevant(input)) {
        return _fallbackRelevant(input, reason: 'heuristic_job_related');
      }
      return result;
    }

    final retryMessage =
        'Validation error: ${initialResult.error}. Return corrected JSON only.';
    final retryMessages = [
      {'role': 'system', 'content': _systemPrompt},
      {'role': 'user', 'content': inputText},
      {'role': 'user', 'content': retryMessage},
    ];
    AppLogger.log.info('[LocalLlm] Retry instruction:\n$retryMessage');

    final retried = await _client.chat(
      messages: retryMessages,
      keepAlive: _keepAlive,
      temperature: _temperature,
      maxTokens: _maxTokens,
    );
    AppLogger.log.info('[LocalLlm] Raw response (retry): $retried');
    final retryResult = _validateAndParse(retried, input: input);
    if (retryResult.isValid) {
      final result = retryResult.result!;
      if (!result.relevant && _shouldForceRelevant(input)) {
        return _fallbackRelevant(input, reason: 'heuristic_job_related');
      }
      return result;
    }

    if (_shouldForceRelevant(input)) {
      return _fallbackRelevant(input, reason: 'heuristic_job_related');
    }
    return LlmEmailResult.irrelevant(
      category: 'non_job',
      confidence: 0.0,
      reason: 'invalid_json',
    );
  }
}

class OpenAiLlmPipeline implements LlmEmailAnalyzer {
  OpenAiLlmPipeline({
    required OpenAiLlmConfig config,
    http.Client? httpClient,
  })  : _config = config,
        _client = OpenAiClient(config, httpClient: httpClient);

  static const double _temperature = 0.0;
  static const int _maxTokens = 500;

  final OpenAiLlmConfig _config;
  final OpenAiClient _client;

  @override
  Future<LlmEmailResult> analyze(LlmEmailInput input) async {
    if (_config.apiKey.trim().isEmpty) {
      throw StateError('OpenAI API key is missing.');
    }
    final inputText = _formatLlmInput(input);
    final messages = [
      {'role': 'system', 'content': _systemPrompt},
      {'role': 'user', 'content': inputText},
    ];
    AppLogger.log.info('[OpenAI] Prompt system:\n$_systemPrompt');
    AppLogger.log.info('[OpenAI] Prompt user:\n$inputText');

    final initial = await _client.chat(
      messages: messages,
      temperature: _temperature,
      maxTokens: _maxTokens,
    );
    AppLogger.log.info('[OpenAI] Raw response (initial): $initial');
    final initialResult = _validateAndParse(initial, input: input);
    if (initialResult.isValid) {
      final result = initialResult.result!;
      if (!result.relevant && _shouldForceRelevant(input)) {
        return _fallbackRelevant(input, reason: 'heuristic_job_related');
      }
      return result;
    }

    final retryMessage =
        'Validation error: ${initialResult.error}. Return corrected JSON only.';
    final retryMessages = [
      {'role': 'system', 'content': _systemPrompt},
      {'role': 'user', 'content': inputText},
      {'role': 'user', 'content': retryMessage},
    ];
    AppLogger.log.info('[OpenAI] Retry instruction:\n$retryMessage');

    final retried = await _client.chat(
      messages: retryMessages,
      temperature: _temperature,
      maxTokens: _maxTokens,
    );
    AppLogger.log.info('[OpenAI] Raw response (retry): $retried');
    final retryResult = _validateAndParse(retried, input: input);
    if (retryResult.isValid) {
      final result = retryResult.result!;
      if (!result.relevant && _shouldForceRelevant(input)) {
        return _fallbackRelevant(input, reason: 'heuristic_job_related');
      }
      return result;
    }

    if (_shouldForceRelevant(input)) {
      return _fallbackRelevant(input, reason: 'heuristic_job_related');
    }
    return LlmEmailResult.irrelevant(
      category: 'non_job',
      confidence: 0.0,
      reason: 'invalid_json',
    );
  }
}

class OpenAiClient {
  OpenAiClient(
    OpenAiLlmConfig config, {
    http.Client? httpClient,
  })  : _config = config,
        _http = httpClient ?? http.Client();

  final OpenAiLlmConfig _config;
  final http.Client _http;
  static final _log = Logger('OpenAiClient');

  Future<String> chat({
    required List<Map<String, String>> messages,
    required double temperature,
    required int maxTokens,
  }) async {
    final endpoint = _chatEndpoint(_config.baseUrl);
    final payload = {
      'model': _config.modelId,
      'messages': messages,
      'temperature': temperature,
      'max_tokens': maxTokens,
      'response_format': {'type': 'json_object'},
    };
    final response = await _send(endpoint, payload);
    final decoded = jsonDecode(response);
    final choices = decoded['choices'];
    if (choices is List && choices.isNotEmpty) {
      final message = choices.first['message'];
      final content = message is Map ? message['content'] : null;
      if (content is String && content.trim().isNotEmpty) {
        return content;
      }
    }
    throw const FormatException('Missing OpenAI content');
  }

  Future<String> _send(Uri endpoint, Map<String, Object?> payload) async {
    final timeout = Duration(milliseconds: _config.requestTimeoutMs);
    final body = jsonEncode(payload);
    try {
      final response = await _http
          .post(
            endpoint,
            headers: {
              HttpHeaders.contentTypeHeader: 'application/json',
              HttpHeaders.authorizationHeader: 'Bearer ${_config.apiKey}',
            },
            body: body,
          )
          .timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'OpenAI request failed (${response.statusCode}): ${response.body}',
        );
      }
      return response.body;
    } catch (error) {
      _log.warning('[OpenAI] Request failed: $error');
      rethrow;
    }
  }
}

Uri _chatEndpoint(String baseUrl) {
  final trimmed = baseUrl.trim().isEmpty
      ? 'https://api.openai.com/v1'
      : baseUrl.trim();
  final normalized =
      trimmed.endsWith('/') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
  return Uri.parse('$normalized/chat/completions');
}

String _formatLlmInput(LlmEmailInput input) {
  final context = input.context;
  final meta = context.meta;
  final sections = <String>[
    'Envelope-From: ${meta.envelopeFrom}',
    'Envelope-To: ${meta.envelopeTo}',
    'Subject: ${meta.subject}',
    'Date: ${meta.date}',
  ];

  final forwarded = context.forwarded;
  if (forwarded != null) {
    sections.add('Forwarded headers:');
    if (forwarded.fromLine != null) {
      sections.add(forwarded.fromLine!);
    }
    if (forwarded.toLine != null) {
      sections.add(forwarded.toLine!);
    }
    if (forwarded.ccLine != null) {
      sections.add(forwarded.ccLine!);
    }
    if (forwarded.originalDateLine != null) {
      sections.add(forwarded.originalDateLine!);
    }
    if (forwarded.originalSubjectLine != null) {
      sections.add(forwarded.originalSubjectLine!);
    }
  }

  if (context.latestText.isNotEmpty) {
    sections.add('Latest message:\n${context.latestText}');
  }

  final snippet = input.snippet.trim();
  if (snippet.isNotEmpty) {
    sections.add('Snippet: $snippet');
  }
  return sections.join('\n');
}

class LocalOllamaClient {
  LocalOllamaClient(
    LocalLlmConfig config, {
    http.Client? httpClient,
  })  : _config = config,
        _http = httpClient ?? http.Client() {
    OllamaEndpoints.validateBaseUrl(_config.baseUrl);
  }

  final LocalLlmConfig _config;
  final http.Client _http;
  static final _log = Logger('LocalOllamaClient');

  Future<void> keepAlive(String keepAlive) async {
    final endpoint = OllamaEndpoints.chat(_config.baseUrl);
    final payload = {
      'model': _config.modelId,
      'messages': const [],
      'stream': false,
      'keep_alive': keepAlive,
    };
    await _send(endpoint, payload);
  }

  Future<String> chat({
    required List<Map<String, String>> messages,
    required String keepAlive,
    required double temperature,
    required int maxTokens,
  }) async {
    final endpoint = OllamaEndpoints.chat(_config.baseUrl);
    final payload = {
      'model': _config.modelId,
      'messages': messages,
      'stream': false,
      'keep_alive': keepAlive,
      'format': kLlmJsonSchema,
      'options': {
        'temperature': temperature,
        'num_predict': maxTokens,
      },
    };
    final response = await _send(endpoint, payload);
    final decoded = jsonDecode(response);
    final content = decoded['message']?['content'];
    if (content is String && content.trim().isNotEmpty) {
      return content;
    }
    throw const FormatException('Missing LLM content');
  }

  Future<String> _send(Uri endpoint, Map<String, Object?> payload) async {
    final timeout = Duration(milliseconds: _config.requestTimeoutMs);
    final body = jsonEncode(payload);
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await _http
            .post(
              endpoint,
              headers: {HttpHeaders.contentTypeHeader: 'application/json'},
              body: body,
            )
            .timeout(timeout);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw HttpException(
            'Ollama request failed (${response.statusCode}): ${response.body}',
          );
        }
        return response.body;
      } catch (error) {
        _log.warning('[Ollama] Request failed: $error');
        if (attempt == 0) {
          await Future.delayed(const Duration(milliseconds: 300));
          continue;
        }
        rethrow;
      }
    }
    throw StateError('Ollama request failed');
  }
}

class LlmEmailResult {
  final bool relevant;
  final String category;
  final double confidence;
  final String? reason;
  final LlmExtractedFields? extraction;

  const LlmEmailResult._({
    required this.relevant,
    required this.category,
    required this.confidence,
    this.reason,
    this.extraction,
  });

  factory LlmEmailResult.irrelevant({
    required String category,
    required double confidence,
    required String reason,
  }) {
    return LlmEmailResult._(
      relevant: false,
      category: category,
      confidence: confidence,
      reason: reason,
    );
  }

  factory LlmEmailResult.relevant({
    required String category,
    required double confidence,
    required LlmExtractedFields extraction,
  }) {
    return LlmEmailResult._(
      relevant: true,
      category: category,
      confidence: confidence,
      extraction: extraction,
    );
  }
}

class LlmExtractedFields {
  final String? company;
  final String? role;
  final String? jobId;
  final String? portalUrl;
  final String? status;
  final LlmInterview interview;
  final String summary;
  final bool actionRequired;
  final List<String> actionItems;
  final String? originalFromEmail;
  final List<String> originalToEmails;
  final List<LlmEvidence> evidence;

  const LlmExtractedFields({
    required this.company,
    required this.role,
    required this.jobId,
    required this.portalUrl,
    required this.status,
    required this.interview,
    required this.summary,
    required this.actionRequired,
    required this.actionItems,
    required this.originalFromEmail,
    required this.originalToEmails,
    required this.evidence,
  });
}

class LlmInterview {
  final String? start;
  final String? end;
  final String? timezone;
  final String? location;
  final String? meetingUrl;

  const LlmInterview({
    required this.start,
    required this.end,
    required this.timezone,
    required this.location,
    required this.meetingUrl,
  });
}

class LlmEvidence {
  final String field;
  final String source;
  final String quote;

  const LlmEvidence({
    required this.field,
    required this.source,
    required this.quote,
  });
}

class _ValidationResult {
  final bool isValid;
  final String? error;
  final LlmEmailResult? result;

  const _ValidationResult({
    required this.isValid,
    this.error,
    this.result,
  });
}

_ValidationResult _validateAndParse(
  String content, {
  required LlmEmailInput input,
}) {
  try {
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic>) {
      return const _ValidationResult(isValid: false, error: 'Root is not object');
    }
    final relevant = decoded['relevant'];
    if (relevant is! bool) {
      return const _ValidationResult(
        isValid: false,
        error: 'Missing or invalid relevant flag',
      );
    }
    if (!relevant) {
      return _validateIrrelevant(decoded);
    }
    final normalized = _normalizeRelevantJson(decoded, input);
    return _validateRelevant(normalized);
  } catch (error) {
    return _ValidationResult(isValid: false, error: 'JSON parse error: $error');
  }
}

_ValidationResult _validateIrrelevant(Map<String, dynamic> json) {
  const allowedKeys = {'relevant', 'category', 'confidence', 'reason'};
  if (!_hasOnlyKeys(json, allowedKeys)) {
    return const _ValidationResult(
      isValid: false,
      error: 'Unexpected keys for IrrelevantEmail',
    );
  }
  final category = json['category'];
  if (category is! String ||
      (category != 'non_job' && category != 'promotion')) {
    return const _ValidationResult(
      isValid: false,
      error: 'Invalid category',
    );
  }
  final confidence = _parseConfidence(json['confidence']);
  if (confidence == null) {
    return const _ValidationResult(
      isValid: false,
      error: 'Invalid confidence',
    );
  }
  final reason = json['reason'];
  if (reason is! String || reason.length > 120) {
    return const _ValidationResult(
      isValid: false,
      error: 'Invalid reason',
    );
  }
  final result = LlmEmailResult.irrelevant(
    category: category,
    confidence: confidence,
    reason: reason,
  );
  return _ValidationResult(isValid: true, result: result);
}

_ValidationResult _validateRelevant(Map<String, dynamic> json) {
  const allowedKeys = {
    'relevant',
    'category',
    'confidence',
    'company',
    'role',
    'jobId',
    'portalUrl',
    'status',
    'interview',
    'summary',
    'actionRequired',
    'actionItems',
    'originalFromEmail',
    'originalToEmails',
    'evidence',
  };
  if (!_hasOnlyKeys(json, allowedKeys)) {
    return const _ValidationResult(
      isValid: false,
      error: 'Unexpected keys for RelevantEmail',
    );
  }
  const categories = {
    'application_confirmation',
    'status_change',
    'interview_invite',
    'interview_update',
    'assessment',
    'offer',
    'rejection',
    'request_more_info',
  };
  final category = json['category'];
  if (category is! String || !categories.contains(category)) {
    return const _ValidationResult(
      isValid: false,
      error: 'Invalid category',
    );
  }
  final confidence = _parseConfidence(json['confidence']);
  if (confidence == null) {
    return const _ValidationResult(
      isValid: false,
      error: 'Invalid confidence',
    );
  }
  final company = _parseOptionalString(json['company'], 120);
  if (company == null && json['company'] != null) {
    return const _ValidationResult(
      isValid: false,
      error: 'Invalid company',
    );
  }
  final role = _parseOptionalString(json['role'], 160);
  if (role == null && json['role'] != null) {
    return const _ValidationResult(
      isValid: false,
      error: 'Invalid role',
    );
  }
  final jobId = _parseOptionalString(json['jobId'], 80);
  if (jobId == null && json['jobId'] != null) {
    return const _ValidationResult(
      isValid: false,
      error: 'Invalid jobId',
    );
  }
  final portalUrl = _parseOptionalString(json['portalUrl'], 500);
  if (portalUrl == null && json['portalUrl'] != null) {
    return const _ValidationResult(
      isValid: false,
      error: 'Invalid portalUrl',
    );
  }
  const statuses = {
    'applied',
    'under_review',
    'interview',
    'offer',
    'rejected',
    'assessment',
    'other',
  };
  final status = json['status'];
  if (status != null && (status is! String || !statuses.contains(status))) {
    return const _ValidationResult(
      isValid: false,
      error: 'Invalid status',
    );
  }
  final interview = json['interview'];
  if (interview is! Map<String, dynamic>) {
    return const _ValidationResult(
      isValid: false,
      error: 'Invalid interview object',
    );
  }
  const interviewKeys = {
    'start',
    'end',
    'timezone',
    'location',
    'meetingUrl',
  };
  if (!_hasOnlyKeys(interview, interviewKeys)) {
    return const _ValidationResult(
      isValid: false,
      error: 'Unexpected interview keys',
    );
  }
  final interviewStart = _parseOptionalString(interview['start'], 40);
  if (interviewStart == null && interview['start'] != null) {
    return const _ValidationResult(
      isValid: false,
      error: 'Invalid interview.start',
    );
  }
  final interviewEnd = _parseOptionalString(interview['end'], 40);
  if (interviewEnd == null && interview['end'] != null) {
    return const _ValidationResult(
      isValid: false,
      error: 'Invalid interview.end',
    );
  }
  final interviewTz = _parseOptionalString(interview['timezone'], 64);
  if (interviewTz == null && interview['timezone'] != null) {
    return const _ValidationResult(
      isValid: false,
      error: 'Invalid interview.timezone',
    );
  }
  final interviewLocation = _parseOptionalString(interview['location'], 200);
  if (interviewLocation == null && interview['location'] != null) {
    return const _ValidationResult(
      isValid: false,
      error: 'Invalid interview.location',
    );
  }
  final interviewMeeting = _parseOptionalString(interview['meetingUrl'], 500);
  if (interviewMeeting == null && interview['meetingUrl'] != null) {
    return const _ValidationResult(
      isValid: false,
      error: 'Invalid interview.meetingUrl',
    );
  }

  final summary = json['summary'];
  if (summary is! String || summary.length > 180 || summary.contains('\n')) {
    return const _ValidationResult(
      isValid: false,
      error: 'Invalid summary',
    );
  }
  final actionRequired = json['actionRequired'];
  if (actionRequired is! bool) {
    return const _ValidationResult(
      isValid: false,
      error: 'Invalid actionRequired',
    );
  }
  final actionItemsRaw = json['actionItems'];
  if (actionItemsRaw is! List) {
    return const _ValidationResult(
      isValid: false,
      error: 'Invalid actionItems',
    );
  }
  if (actionItemsRaw.length > 5) {
    return const _ValidationResult(
      isValid: false,
      error: 'Too many actionItems',
    );
  }
  final actionItems = <String>[];
  for (final item in actionItemsRaw) {
    if (item is! String || item.length > 120) {
      return const _ValidationResult(
        isValid: false,
        error: 'Invalid action item',
      );
    }
    actionItems.add(item);
  }

  final originalFromEmail = _parseOptionalString(json['originalFromEmail'], 254);
  if (originalFromEmail == null && json['originalFromEmail'] != null) {
    return const _ValidationResult(
      isValid: false,
      error: 'Invalid originalFromEmail',
    );
  }
  final originalToEmailsRaw = json['originalToEmails'];
  if (originalToEmailsRaw is! List) {
    return const _ValidationResult(
      isValid: false,
      error: 'Invalid originalToEmails',
    );
  }
  if (originalToEmailsRaw.length > 8) {
    return const _ValidationResult(
      isValid: false,
      error: 'Too many originalToEmails',
    );
  }
  final originalToEmails = <String>[];
  for (final item in originalToEmailsRaw) {
    if (item is! String || item.length > 254) {
      return const _ValidationResult(
        isValid: false,
        error: 'Invalid originalToEmail',
      );
    }
    originalToEmails.add(item);
  }

  final evidenceRaw = json['evidence'];
  if (evidenceRaw is! List) {
    return const _ValidationResult(
      isValid: false,
      error: 'Invalid evidence list',
    );
  }
  if (evidenceRaw.length > 6) {
    return const _ValidationResult(
      isValid: false,
      error: 'Too many evidence items',
    );
  }
  const evidenceSources = {'bodyText', 'subject', 'from', 'snippet'};
  final evidence = <LlmEvidence>[];
  for (final item in evidenceRaw) {
    if (item is! Map<String, dynamic>) {
      return const _ValidationResult(
        isValid: false,
        error: 'Invalid evidence item',
      );
    }
    const evidenceKeys = {'field', 'source', 'quote'};
    if (!_hasOnlyKeys(item, evidenceKeys)) {
      return const _ValidationResult(
        isValid: false,
        error: 'Unexpected evidence keys',
      );
    }
    final field = item['field'];
    final source = item['source'];
    final quote = item['quote'];
    if (field is! String || field.length > 40) {
      return const _ValidationResult(
        isValid: false,
        error: 'Invalid evidence.field',
      );
    }
    if (source is! String || !evidenceSources.contains(source)) {
      return const _ValidationResult(
        isValid: false,
        error: 'Invalid evidence.source',
      );
    }
    if (quote is! String || quote.length > 140) {
      return const _ValidationResult(
        isValid: false,
        error: 'Invalid evidence.quote',
      );
    }
    evidence.add(LlmEvidence(field: field, source: source, quote: quote));
  }
  if (interviewTz != null) {
    final hasTimezoneEvidence =
        evidence.any((item) => item.field == 'interview.timezone');
    if (!hasTimezoneEvidence) {
      return const _ValidationResult(
        isValid: false,
        error: 'Missing evidence for interview.timezone',
      );
    }
  }
  if (originalFromEmail != null) {
    final hasOriginalFromEvidence =
        evidence.any((item) => item.field == 'originalFromEmail');
    if (!hasOriginalFromEvidence) {
      return const _ValidationResult(
        isValid: false,
        error: 'Missing evidence for originalFromEmail',
      );
    }
  }
  if (originalToEmails.isNotEmpty) {
    final hasOriginalToEvidence =
        evidence.any((item) => item.field == 'originalToEmails');
    if (!hasOriginalToEvidence) {
      return const _ValidationResult(
        isValid: false,
        error: 'Missing evidence for originalToEmails',
      );
    }
  }

  final extraction = LlmExtractedFields(
    company: company,
    role: role,
    jobId: jobId,
    portalUrl: portalUrl,
    status: status as String?,
    interview: LlmInterview(
      start: interviewStart,
      end: interviewEnd,
      timezone: interviewTz,
      location: interviewLocation,
      meetingUrl: interviewMeeting,
    ),
    summary: summary,
    actionRequired: actionRequired,
    actionItems: actionItems,
    originalFromEmail: originalFromEmail,
    originalToEmails: originalToEmails,
    evidence: evidence,
  );

  final result = LlmEmailResult.relevant(
    category: category,
    confidence: confidence,
    extraction: extraction,
  );
  return _ValidationResult(isValid: true, result: result);
}

Map<String, dynamic> _normalizeRelevantJson(
  Map<String, dynamic> json,
  LlmEmailInput input,
) {
  final normalized = Map<String, dynamic>.from(json);
  final evidence = _normalizeEvidence(normalized['evidence']);
  normalized['evidence'] = evidence;

  final forwarded = input.context.forwarded;
  if (forwarded == null) {
    normalized['originalFromEmail'] = null;
    normalized['originalToEmails'] = <String>[];
    _removeEvidence(evidence, const {'originalFromEmail', 'originalToEmails'});
  } else {
    final fromLine = forwarded.fromLine;
    final toLine = forwarded.toLine;
    final fromEmail = forwarded.originalFromEmail;
    final toEmails = forwarded.originalToEmails;
    if (fromEmail != null &&
        fromLine != null &&
        fromLine.length <= 140) {
      normalized['originalFromEmail'] = fromEmail;
      _ensureEvidence(
        evidence,
        field: 'originalFromEmail',
        source: 'bodyText',
        quote: fromLine,
      );
    } else {
      normalized['originalFromEmail'] = null;
      _removeEvidence(evidence, const {'originalFromEmail'});
    }
    if (toEmails.isNotEmpty && toLine != null && toLine.length <= 140) {
      normalized['originalToEmails'] = toEmails;
      _ensureEvidence(
        evidence,
        field: 'originalToEmails',
        source: 'bodyText',
        quote: toLine,
      );
    } else {
      normalized['originalToEmails'] = <String>[];
      _removeEvidence(evidence, const {'originalToEmails'});
    }
  }

  final interviewRaw = normalized['interview'];
  if (interviewRaw is Map<String, dynamic>) {
    final interview = Map<String, dynamic>.from(interviewRaw);
    final timezoneRaw = interview['timezone'];
    if (timezoneRaw is String && timezoneRaw.trim().isNotEmpty) {
      final timezone = timezoneRaw.trim();
      final hasEvidence =
          _hasTimezoneEvidence(evidence, timezone, input);
      if (!hasEvidence) {
        final match = _findExactMatchInInput(timezone, input);
        if (match != null && match.quote.length <= 140) {
          _ensureEvidence(
            evidence,
            field: 'interview.timezone',
            source: match.source,
            quote: match.quote,
          );
        } else {
          interview['timezone'] = null;
          _removeEvidence(evidence, const {'interview.timezone'});
        }
      }
    }
    normalized['interview'] = interview;
  }

  return normalized;
}

class _EvidenceMatch {
  final String source;
  final String quote;

  const _EvidenceMatch({
    required this.source,
    required this.quote,
  });
}

List<Map<String, dynamic>> _normalizeEvidence(Object? raw) {
  if (raw is! List) {
    return <Map<String, dynamic>>[];
  }
  const evidenceSources = {'bodyText', 'subject', 'from', 'snippet'};
  final normalized = <Map<String, dynamic>>[];
  for (final item in raw) {
    if (item is! Map<String, dynamic>) {
      continue;
    }
    final field = item['field'];
    final source = item['source'];
    final quote = item['quote'];
    if (field is! String || field.length > 40) {
      continue;
    }
    if (source is! String || !evidenceSources.contains(source)) {
      continue;
    }
    if (quote is! String || quote.length > 140) {
      continue;
    }
    normalized.add({
      'field': field,
      'source': source,
      'quote': quote,
    });
    if (normalized.length >= 6) {
      break;
    }
  }
  return normalized;
}

void _removeEvidence(List<Map<String, dynamic>> evidence, Set<String> fields) {
  evidence.removeWhere((item) => fields.contains(item['field']));
}

void _ensureEvidence(
  List<Map<String, dynamic>> evidence, {
  required String field,
  required String source,
  required String quote,
}) {
  if (quote.length > 140) {
    return;
  }
  final existing = evidence.any((item) => item['field'] == field);
  if (existing) {
    return;
  }
  if (evidence.length >= 6) {
    evidence.removeLast();
  }
  evidence.add({
    'field': field,
    'source': source,
    'quote': quote,
  });
}

bool _hasTimezoneEvidence(
  List<Map<String, dynamic>> evidence,
  String timezone,
  LlmEmailInput input,
) {
  for (final item in evidence) {
    if (item['field'] != 'interview.timezone') {
      continue;
    }
    final quote = item['quote'];
    if (quote is! String) {
      continue;
    }
    if (_quoteHasTimezone(quote, timezone)) {
      return true;
    }
  }
  return false;
}

bool _quoteHasTimezone(String quote, String timezone) {
  if (quote.contains(timezone)) {
    return true;
  }
  final tzRegex = RegExp(
    r'\b(ET|EST|EDT|PT|PST|PDT|UTC|GMT)\b|[+-]\d{2}:\d{2}|\b[A-Za-z]+/[A-Za-z_]+\b',
  );
  return tzRegex.hasMatch(quote);
}

_EvidenceMatch? _findExactMatchInInput(String needle, LlmEmailInput input) {
  final subject = input.context.meta.subject;
  final latestText = input.context.latestText;
  final snippet = input.snippet;
  final matchInLatest = _findCaseInsensitiveMatch(latestText, needle);
  if (matchInLatest != null) {
    return _EvidenceMatch(source: 'bodyText', quote: matchInLatest);
  }
  final matchInSnippet = _findCaseInsensitiveMatch(snippet, needle);
  if (matchInSnippet != null) {
    return _EvidenceMatch(source: 'snippet', quote: matchInSnippet);
  }
  final matchInSubject = _findCaseInsensitiveMatch(subject, needle);
  if (matchInSubject != null) {
    return _EvidenceMatch(source: 'subject', quote: matchInSubject);
  }
  return null;
}

String? _findCaseInsensitiveMatch(String haystack, String needle) {
  if (needle.isEmpty || haystack.isEmpty) {
    return null;
  }
  final lowerHaystack = haystack.toLowerCase();
  final lowerNeedle = needle.toLowerCase();
  final index = lowerHaystack.indexOf(lowerNeedle);
  if (index == -1) {
    return null;
  }
  return haystack.substring(index, index + needle.length);
}

bool _shouldForceRelevant(LlmEmailInput input) {
  final text = _combinedText(input);
  if (_isLikelyJobAd(text)) {
    return false;
  }
  return _containsAny(text, _jobLifecycleSignals) ||
      _containsAny(text, _jobContextSignals);
}

LlmEmailResult _fallbackRelevant(
  LlmEmailInput input, {
  required String reason,
}) {
  final text = _combinedText(input);
  final category = _deriveCategory(text);
  final status = _deriveStatus(category);
  final summary = _buildSummary(input);
  final actionRequired = _needsAction(text, category);
  final actionItems = actionRequired ? _buildActionItems(category) : <String>[];

  final forwarded = input.context.forwarded;
  String? originalFromEmail;
  var originalToEmails = <String>[];
  final evidence = <LlmEvidence>[];
  if (forwarded != null) {
    final fromLine = forwarded.fromLine;
    if (forwarded.originalFromEmail != null &&
        fromLine != null &&
        fromLine.length <= 140) {
      originalFromEmail = forwarded.originalFromEmail;
      evidence.add(LlmEvidence(
        field: 'originalFromEmail',
        source: 'bodyText',
        quote: fromLine,
      ));
    }
    final toLine = forwarded.toLine;
    if (forwarded.originalToEmails.isNotEmpty &&
        toLine != null &&
        toLine.length <= 140) {
      originalToEmails = forwarded.originalToEmails;
      evidence.add(LlmEvidence(
        field: 'originalToEmails',
        source: 'bodyText',
        quote: toLine,
      ));
    }
  }

  AppLogger.log.info(
    '[LocalLlm] Override irrelevant -> relevant via $reason '
    'category=$category subject="${input.context.meta.subject}"',
  );

  final extraction = LlmExtractedFields(
    company: null,
    role: null,
    jobId: null,
    portalUrl: null,
    status: status,
    interview: const LlmInterview(
      start: null,
      end: null,
      timezone: null,
      location: null,
      meetingUrl: null,
    ),
    summary: summary,
    actionRequired: actionRequired,
    actionItems: actionItems,
    originalFromEmail: originalFromEmail,
    originalToEmails: originalToEmails,
    evidence: evidence,
  );

  return LlmEmailResult.relevant(
    category: category,
    confidence: 0.55,
    extraction: extraction,
  );
}

String _combinedText(LlmEmailInput input) {
  final subject = input.context.meta.subject;
  final latestText = input.context.latestText;
  final snippet = input.snippet;
  return [subject, latestText, snippet].join('\n').toLowerCase();
}

bool _containsAny(String text, List<String> phrases) {
  for (final phrase in phrases) {
    if (text.contains(phrase)) {
      return true;
    }
  }
  return false;
}

bool _isLikelyJobAd(String text) {
  if (!_containsAny(text, _jobAdSignals)) {
    return false;
  }
  return !_containsAny(text, _jobLifecycleSignals);
}

String _deriveCategory(String text) {
  if (_containsAny(text, _rejectionSignals)) {
    return 'rejection';
  }
  if (_containsAny(text, _offerSignals)) {
    return 'offer';
  }
  if (_containsAny(text, _interviewSignals)) {
    return 'interview_invite';
  }
  if (_containsAny(text, _assessmentSignals)) {
    return 'assessment';
  }
  if (_containsAny(text, _applicationSignals)) {
    return 'application_confirmation';
  }
  if (_containsAny(text, _requestInfoSignals)) {
    return 'request_more_info';
  }
  if (_containsAny(text, _statusSignals)) {
    return 'status_change';
  }
  return 'status_change';
}

String? _deriveStatus(String category) {
  switch (category) {
    case 'application_confirmation':
      return 'applied';
    case 'interview_invite':
    case 'interview_update':
      return 'interview';
    case 'assessment':
      return 'assessment';
    case 'offer':
      return 'offer';
    case 'rejection':
      return 'rejected';
    case 'request_more_info':
      return 'other';
    case 'status_change':
      return 'under_review';
  }
  return null;
}

String _buildSummary(LlmEmailInput input) {
  var summary = input.context.meta.subject.trim();
  if (summary.isEmpty) {
    summary = input.context.latestText.trim();
  }
  summary = summary.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (summary.isEmpty) {
    summary = 'Job application update';
  }
  if (summary.length > 180) {
    summary = summary.substring(0, 180);
  }
  return summary;
}

bool _needsAction(String text, String category) {
  if (_containsAny(text, _actionSignals)) {
    return true;
  }
  return category == 'interview_invite' ||
      category == 'assessment' ||
      category == 'request_more_info';
}

List<String> _buildActionItems(String category) {
  switch (category) {
    case 'interview_invite':
      return const ['Schedule the interview'];
    case 'assessment':
      return const ['Complete the assessment'];
    case 'request_more_info':
      return const ['Provide the requested information'];
    default:
      return const ['Reply to the sender'];
  }
}

const List<String> _jobLifecycleSignals = [
  'application received',
  'application confirmation',
  'thank you for applying',
  'thanks for applying',
  'application submitted',
  'resume submitted',
  'application status',
  'status update',
  'under review',
  'not moving forward',
  'moving forward',
  'interview',
  'phone screen',
  'assessment',
  'coding challenge',
  'offer',
  'rejection',
  'schedule a call',
  'schedule an interview',
  'interview call',
];

const List<String> _jobContextSignals = [
  'internship',
  'recruiter',
  'hiring',
  'candidate',
  'resume',
  'cv',
  'position',
  'role',
  'job',
  'application',
];

const List<String> _jobAdSignals = [
  'job alert',
  'jobs for you',
  'jobs you may like',
  'recommended jobs',
  'new jobs',
  'open positions',
  'career fair',
  'newsletter',
  'weekly digest',
  'daily digest',
  'subscribe',
  'unsubscribe',
  'job board',
  'hiring now',
];

const List<String> _rejectionSignals = [
  'not moving forward',
  'unfortunately',
  'we will not be moving forward',
  'regret to inform',
  'not selected',
];

const List<String> _offerSignals = [
  'offer',
  'we are pleased to offer',
  'offer letter',
];

const List<String> _interviewSignals = [
  'interview',
  'schedule',
  'phone screen',
  'video call',
  'onsite',
];

const List<String> _assessmentSignals = [
  'assessment',
  'coding challenge',
  'take-home',
  'test',
];

const List<String> _applicationSignals = [
  'application received',
  'application confirmation',
  'thank you for applying',
  'thanks for applying',
  'application submitted',
  'resume submitted',
];

const List<String> _requestInfoSignals = [
  'please provide',
  'can you share',
  'could you share',
  'need more information',
  'request more information',
  'any update',
  'follow up',
];

const List<String> _statusSignals = [
  'status update',
  'under review',
  'in review',
];

const List<String> _actionSignals = [
  'please',
  'schedule',
  'choose',
  'select',
  'reply',
  'respond',
  'provide',
  'complete',
  'submit',
  'confirm',
];

bool _hasOnlyKeys(Map<String, dynamic> json, Set<String> allowed) {
  for (final key in json.keys) {
    if (!allowed.contains(key)) {
      return false;
    }
  }
  for (final key in allowed) {
    if (!json.containsKey(key)) {
      return false;
    }
  }
  return true;
}

double? _parseConfidence(Object? value) {
  if (value is num) {
    final confidence = value.toDouble();
    if (confidence >= 0 && confidence <= 1) {
      return confidence;
    }
  }
  return null;
}

String? _parseOptionalString(Object? value, int maxLength) {
  if (value == null) {
    return null;
  }
  if (value is! String) {
    return null;
  }
  if (value.length > maxLength) {
    return null;
  }
  return value;
}

const String _systemPrompt = '''
You are a strict JSON extraction engine for job application lifecycle emails.

Decide relevance using the email content (subject, body, snippet, forwarded content).
Mark as relevant if the email is related to the user's job application or next steps, including:
- application received/confirmation/submitted
- application status update or status change
- recruiter follow up or request for more information
- interview scheduling/invite/update
- assessment/test/coding challenge
- offer
- rejection

Forwarded emails still count as relevant if the forwarded content describes any of the above.
Automated messages about applications or interviews are still relevant.
When in doubt and the email is job-related (not an advertisement), mark it relevant.

Only mark NOT relevant when it is job advertising or unrelated marketing, such as:
- job listings with no sign the user applied
- newsletters, career fairs, generic recruiting blasts
- sales, promos, security alerts, or unrelated account notifications

If NOT relevant:
- Output ONLY the IrrelevantEmail JSON shape (no extra keys).
- Keep reason short.
- Use category "non_job" for job ads/newsletters not tied to an application.

If relevant:
- Output the RelevantEmail JSON shape.
- Extract conservatively; use null when unknown.
- confidence must be a number between 0 and 1 (inclusive).
- summary: single short sentence for Updates, no newlines, max 180 chars.
- evidence quotes must be exact spans from the email text. Do not paraphrase.
- Do not invent company, role, jobId, URLs, meeting links, or times.
- Company/role extraction (important):
  - Prefer explicit phrases from subject or body (e.g., "Your [Company] application", "position of [Role]", "role: [Role]", "Job title").
  - If subject is like "[Company] Application Status" or "Your [Company] Application", set company to the named company.
  - If subject/body shows "role [JobId] [Role]" or "requisition/req/R####", use that as jobId and capture the adjacent role title.
  - Do not use ATS/platform names (Workday, Greenhouse, Lever) as the company unless the email explicitly says the user applied to that company.
  - Keep the full role title as written (include level/team/track) but exclude trailing status words like "Open" if they are clearly status, not part of the title.
- For interview.start/end, use ISO 8601 only when the email explicitly provides date/time; otherwise null.
- Rejection emails are relevant. Use category "rejection" when the email says the application will not move forward.
- Application confirmations are relevant even if forwarded. If the content says an application was received, use category "application_confirmation".
- Forwarded handling: if forwarded header meta is provided, prefer originalFromEmail and originalToEmails from that meta. Do not guess. If not provided, set originalFromEmail to null and originalToEmails to [].
- If originalFromEmail is non-null, include an evidence item with field "originalFromEmail" quoting the exact "From:" line.
- If originalToEmails is non-empty, include an evidence item with field "originalToEmails" quoting the exact "To:" line.

Timezone rule (critical):
- interview.timezone must come from the email content only.
- Accept ET, EST, EDT, PT, PST, PDT, UTC, GMT, IANA zones (e.g., America/New_York), or numeric offsets (+05:30).
- Never default to the user timezone and never guess.
- If timezone is not explicit, set interview.timezone = null.
- If interview.timezone is not null, include an evidence item with field "interview.timezone" quoting the exact timezone text.

Return JSON only. Do not include markdown.
''';

const Map<String, dynamic> kLlmJsonSchema = {
  'type': 'object',
  'oneOf': [
    {
      'title': 'IrrelevantEmail',
      'type': 'object',
      'additionalProperties': false,
      'properties': {
        'relevant': {'const': false},
        'category': {'enum': ['non_job', 'promotion']},
        'confidence': {'type': 'number', 'minimum': 0, 'maximum': 1},
        'reason': {'type': 'string', 'maxLength': 120},
      },
      'required': ['relevant', 'category', 'confidence', 'reason'],
    },
    {
      'title': 'RelevantEmail',
      'type': 'object',
      'additionalProperties': false,
      'properties': {
        'relevant': {'const': true},
        'category': {
          'enum': [
            'application_confirmation',
            'status_change',
            'interview_invite',
            'interview_update',
            'assessment',
            'offer',
            'rejection',
            'request_more_info',
          ],
        },
        'confidence': {'type': 'number', 'minimum': 0, 'maximum': 1},
        'company': {'type': ['string', 'null'], 'maxLength': 120},
        'role': {'type': ['string', 'null'], 'maxLength': 160},
        'jobId': {'type': ['string', 'null'], 'maxLength': 80},
        'portalUrl': {'type': ['string', 'null'], 'maxLength': 500},
        'status': {
          'type': ['string', 'null'],
          'enum': [
            'applied',
            'under_review',
            'interview',
            'offer',
            'rejected',
            'assessment',
            'other',
            null,
          ],
        },
        'interview': {
          'type': 'object',
          'additionalProperties': false,
          'properties': {
            'start': {'type': ['string', 'null'], 'maxLength': 40},
            'end': {'type': ['string', 'null'], 'maxLength': 40},
            'timezone': {'type': ['string', 'null'], 'maxLength': 64},
            'location': {'type': ['string', 'null'], 'maxLength': 200},
            'meetingUrl': {'type': ['string', 'null'], 'maxLength': 500},
          },
          'required': ['start', 'end', 'timezone', 'location', 'meetingUrl'],
        },
        'summary': {'type': 'string', 'maxLength': 180},
        'actionRequired': {'type': 'boolean'},
        'actionItems': {
          'type': 'array',
          'maxItems': 5,
          'items': {'type': 'string', 'maxLength': 120},
        },
        'originalFromEmail': {'type': ['string', 'null'], 'maxLength': 254},
        'originalToEmails': {
          'type': 'array',
          'maxItems': 8,
          'items': {'type': 'string', 'maxLength': 254},
        },
        'evidence': {
          'type': 'array',
          'maxItems': 6,
          'items': {
            'type': 'object',
            'additionalProperties': false,
            'properties': {
              'field': {'type': 'string', 'maxLength': 40},
              'source': {'enum': ['bodyText', 'subject', 'from', 'snippet']},
              'quote': {'type': 'string', 'maxLength': 140},
            },
            'required': ['field', 'source', 'quote'],
          },
        },
      },
      'required': [
        'relevant',
        'category',
        'confidence',
        'company',
        'role',
        'jobId',
        'portalUrl',
        'status',
        'interview',
        'summary',
        'actionRequired',
        'actionItems',
        'originalFromEmail',
        'originalToEmails',
        'evidence',
      ],
    },
  ],
};
