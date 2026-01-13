class OllamaEndpoints {
  static const int _ollamaPort = 11434;

  static Uri chat(String baseUrl) {
    return _build(baseUrl, '/api/chat');
  }

  static Uri tags(String baseUrl) {
    return _build(baseUrl, '/api/tags');
  }

  static void validateBaseUrl(String baseUrl) {
    _build(baseUrl, '/');
  }

  static Uri _build(String baseUrl, String path) {
    final uri = Uri.parse(baseUrl);
    final scheme = uri.scheme.toLowerCase();
    if (scheme.isEmpty || scheme == 'https') {
      throw StateError(
        'Ollama baseUrl must use http://localhost:11434 or http://127.0.0.1:11434.',
      );
    }
    if (scheme != 'http') {
      throw StateError(
        'Ollama baseUrl must use http://localhost:11434 or http://127.0.0.1:11434.',
      );
    }
    final host = uri.host.toLowerCase();
    if (host != 'localhost' && host != '127.0.0.1') {
      throw StateError(
        'Ollama baseUrl must be localhost or 127.0.0.1 on port 11434.',
      );
    }
    if (uri.port != _ollamaPort) {
      throw StateError(
        'Ollama baseUrl must use port 11434.',
      );
    }
    return uri.replace(path: path, query: '');
  }
}
