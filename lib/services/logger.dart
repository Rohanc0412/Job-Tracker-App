import 'package:logging/logging.dart';

class AppLogger {
  static Logger get log => Logger('JobTracker');

  static void setup({Level level = Level.INFO}) {
    Logger.root.level = level;
    Logger.root.onRecord.listen((record) {
      final message = redact(record.message);
      // Simple console output for now.
      // ignore: avoid_print
      print('[${record.level.name}] ${record.time}: $message');
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
