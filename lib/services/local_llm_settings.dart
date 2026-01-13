class LocalLlmSettingsKeys {
  static const String baseUrl = 'ollama.base_url';
  static const String modelId = 'ollama.model_id';
  static const String requestTimeoutMs = 'ollama.request_timeout_ms';
  static const String maxInputChars = 'ollama.max_input_chars';
}

class LocalLlmDefaults {
  static const String baseUrl = 'http://127.0.0.1:11434';
  static const String modelId = 'qwen2.5:3b-instruct';
  static const int requestTimeoutMs = 30000;
  static const int maxInputChars = 20000;
  static const String openAiBaseUrl = 'https://api.openai.com/v1';
}

const String kOpenAiModelId = 'gpt-4o-mini';

const List<String> LocalLlmModels = [
  'qwen2.5:3b-instruct',
  'qwen2.5:7b-instruct',
  kOpenAiModelId,
];
