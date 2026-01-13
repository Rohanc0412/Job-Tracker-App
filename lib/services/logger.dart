import 'dart:io';

import 'package:logging/logging.dart';

class AppLogger {
  static Logger get log => Logger('JobTracker');
  static bool _redactMessages = true;
  static String? _logFilePath;

  static void setup({
    Level level = Level.INFO,
    bool redactMessages = true,
    String? logFilePath,
  }) {
    _redactMessages = redactMessages;
    _logFilePath = logFilePath;
    Logger.root.level = level;
    Logger.root.onRecord.listen((record) {
      final message =
          _redactMessages ? redact(record.message) : record.message;
      final line = '[${record.level.name}] ${record.time}: $message';
      // Simple console output for now.
      // ignore: avoid_print
      print(line);
      final path = _logFilePath;
      if (path != null && path.isNotEmpty) {
        try {
          final file = File(path);
          file.writeAsStringSync('$line\n', mode: FileMode.append);
        } catch (_) {
          // Best effort logging; ignore file errors.
        }
      }
    });
  }

  static String redact(String message, {List<String> secrets = const []}) {
    var sanitized = message;
    for (final secret in secrets) {
      if (secret.trim().isEmpty) {
        continue;
      }
      sanitized = sanitized.replaceAll(secret, '[REDACTED]');
    }
    sanitized = _redactTokens(sanitized);
    sanitized = _redactSensitiveLines(sanitized);
    sanitized = _truncateLongMessages(sanitized, 500);
    return sanitized;
  }

  static String _redactTokens(String input) {
    final patterns = [
      RegExp(
        r'(authorization:\s*bearer\s+)([A-Za-z0-9._~+/=-]+)',
        caseSensitive: false,
      ),
      RegExp(
        r'((?:access|refresh|id|api|auth)?[_-]?token\s*[:=]\s*)([A-Za-z0-9._~+/=-]+)',
        caseSensitive: false,
      ),
      RegExp(
        '(password\\s*[:=]\\s*)([^\\s\"\\\'<>]+)',
        caseSensitive: false,
      ),
      RegExp(
        '(client_secret\\s*[:=]\\s*)([^\\s\"\\\'<>]+)',
        caseSensitive: false,
      ),
    ];
    var output = input;
    for (final pattern in patterns) {
      output = output.replaceAllMapped(
        pattern,
        (match) => '${match.group(1)}[REDACTED]',
      );
    }
    return output;
  }

  static String _redactSensitiveLines(String input) {
    final lines = input.split('\n');
    final redacted = <String>[];
    for (final line in lines) {
      if (line.length > 200) {
        redacted.add('[REDACTED]');
      } else if (_looksLikeBodyLine(line)) {
        redacted.add(_redactBodyLine(line));
      } else {
        redacted.add(line);
      }
    }
    return redacted.join('\n');
  }

  static bool _looksLikeBodyLine(String line) {
    final lower = line.toLowerCase();
    return lower.contains('body=') ||
        lower.contains('body:') ||
        lower.contains('email_body') ||
        lower.contains('message_body') ||
        lower.contains('raw_email') ||
        lower.contains('raw message');
  }

  static String _redactBodyLine(String line) {
    final match = RegExp(r'^([^:=]+[:=]\s*).*$').firstMatch(line);
    if (match == null) {
      return '[REDACTED]';
    }
    return '${match.group(1)}[REDACTED]';
  }

  static String _truncateLongMessages(String input, int maxLength) {
    if (input.length <= maxLength) {
      return input;
    }
    return '${input.substring(0, maxLength)}...[truncated]';
  }
}
