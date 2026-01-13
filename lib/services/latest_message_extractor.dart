import 'email_text_extractor.dart';

class LatestMessageMeta {
  final String envelopeFrom;
  final String envelopeTo;
  final String subject;
  final String date;

  const LatestMessageMeta({
    required this.envelopeFrom,
    required this.envelopeTo,
    required this.subject,
    required this.date,
  });
}

class ForwardedMessageMeta {
  final String? originalFromEmail;
  final List<String> originalToEmails;
  final List<String> originalCcEmails;
  final String? originalDateLine;
  final String? originalSubjectLine;
  final String? fromLine;
  final String? toLine;
  final String? ccLine;

  const ForwardedMessageMeta({
    required this.originalFromEmail,
    required this.originalToEmails,
    required this.originalCcEmails,
    required this.originalDateLine,
    required this.originalSubjectLine,
    required this.fromLine,
    required this.toLine,
    required this.ccLine,
  });
}

class LatestMessageContext {
  final String latestText;
  final ForwardedMessageMeta? forwarded;
  final LatestMessageMeta meta;

  const LatestMessageContext({
    required this.latestText,
    required this.forwarded,
    required this.meta,
  });
}

LatestMessageContext extract_latest_message_context({
  required String? bodyText,
  required String? bodyHtml,
  required String? snippet,
  required String envelopeFrom,
  required String envelopeTo,
  required String subject,
  required String date,
  int maxInputChars = 20000,
}) {
  final meta = LatestMessageMeta(
    envelopeFrom: envelopeFrom,
    envelopeTo: envelopeTo,
    subject: subject,
    date: date,
  );

  var raw = _selectBody(bodyText, bodyHtml, snippet);
  if (raw.trim().isEmpty) {
    return LatestMessageContext(latestText: '', forwarded: null, meta: meta);
  }

  raw = _normalizeBody(raw);
  final forwarded = _parseForwarded(raw);
  final latestSource = forwarded?.bodyText ?? raw;
  final latestText = _cleanLatest(latestSource, maxInputChars);

  return LatestMessageContext(
    latestText: latestText,
    forwarded: forwarded?.meta,
    meta: meta,
  );
}

String _selectBody(String? bodyText, String? bodyHtml, String? snippet) {
  if (bodyText != null && bodyText.trim().isNotEmpty) {
    return bodyText;
  }
  if (bodyHtml != null && bodyHtml.trim().isNotEmpty) {
    return bodyHtml;
  }
  return snippet ?? '';
}

String _normalizeBody(String input) {
  final value = input.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  if (_looksLikeHtml(value)) {
    return EmailTextExtractor.extractTextPreservingReplies(value);
  }
  return EmailTextExtractor.normalizeSeparators(value);
}

bool _looksLikeHtml(String value) {
  final lower = value.toLowerCase();
  return lower.contains('<html') ||
      lower.contains('<body') ||
      lower.contains('<div') ||
      lower.contains('<p>') ||
      lower.contains('<table');
}

String _cleanLatest(String input, int maxInputChars) {
  var cleaned = EmailTextExtractor.normalizeSeparators(input);
  cleaned = _stripMimeBoundaryLines(cleaned);
  cleaned = EmailTextExtractor.stripReplyChains(cleaned);
  cleaned = EmailTextExtractor.stripLegalDisclaimers(cleaned);
  cleaned = _dropQuotedLines(cleaned);
  cleaned = cleaned.replaceAll(RegExp(r'[ \t]+'), ' ');
  cleaned = cleaned.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  cleaned = EmailTextExtractor.topSection(
    cleaned,
    maxLines: 120,
    maxChars: maxInputChars,
  );
  if (cleaned.length > maxInputChars) {
    cleaned = cleaned.substring(0, maxInputChars);
  }
  return cleaned.trim();
}

String _stripMimeBoundaryLines(String text) {
  final lines = text.split('\n');
  final kept = <String>[];
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      kept.add(line);
      continue;
    }
    if (_isMimeBoundaryLine(trimmed) || _isMimeHeaderLine(trimmed)) {
      continue;
    }
    kept.add(line);
  }
  return kept.join('\n');
}

bool _isMimeBoundaryLine(String trimmed) {
  if (trimmed.startsWith('boundary=') || trimmed.startsWith('boundary:')) {
    return true;
  }
  if (trimmed.startsWith('--')) {
    if (trimmed.contains('=_Part_') || trimmed.contains('=_NextPart')) {
      return true;
    }
    return RegExp(r"^--[_A-Za-z0-9'()+,./:=?-]{6,}--?$")
        .hasMatch(trimmed);
  }
  return false;
}

bool _isMimeHeaderLine(String trimmed) {
  return RegExp(
    r'^(content-type|content-transfer-encoding|mime-version):',
    caseSensitive: false,
  ).hasMatch(trimmed);
}

String _dropQuotedLines(String text) {
  final lines = text.split('\n');
  final kept = <String>[];
  for (final line in lines) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('>')) {
      continue;
    }
    if (RegExp(r'^_{5,}$').hasMatch(trimmed)) {
      break;
    }
    kept.add(line);
  }
  return kept.join('\n');
}

class _ForwardedParse {
  final ForwardedMessageMeta meta;
  final String bodyText;

  const _ForwardedParse({
    required this.meta,
    required this.bodyText,
  });
}

_ForwardedParse? _parseForwarded(String raw) {
  final lines = raw.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final lower = lines[i].toLowerCase();
    if (!_isForwardedMarker(lower)) {
      continue;
    }
    final headerStart = _findHeaderStart(lines, i + 1);
    if (headerStart == null) {
      continue;
    }
    final headerEnd = _findHeaderEnd(lines, headerStart);
    final headerLines = lines.sublist(headerStart, headerEnd);

    String? fromLine;
    String? toLine;
    String? ccLine;
    String? dateLine;
    String? subjectLine;
    for (final line in headerLines) {
      final trimmed = line.trim();
      if (_startsWithHeader(trimmed, 'from')) {
        fromLine ??= trimmed;
      } else if (_startsWithHeader(trimmed, 'to')) {
        toLine ??= trimmed;
      } else if (_startsWithHeader(trimmed, 'cc')) {
        ccLine ??= trimmed;
      } else if (_startsWithHeader(trimmed, 'date') ||
          _startsWithHeader(trimmed, 'sent')) {
        dateLine ??= trimmed;
      } else if (_startsWithHeader(trimmed, 'subject')) {
        subjectLine ??= trimmed;
      }
    }

    final originalFromEmail = _extractFirstEmail(fromLine);
    final originalToEmails = _extractEmailsFromLine(toLine);
    final originalCcEmails = _extractEmailsFromLine(ccLine);

    var bodyIndex = headerEnd;
    while (bodyIndex < lines.length && lines[bodyIndex].trim().isEmpty) {
      bodyIndex++;
    }
    final bodyText = lines.sublist(bodyIndex).join('\n');

    return _ForwardedParse(
      meta: ForwardedMessageMeta(
        originalFromEmail: originalFromEmail,
        originalToEmails: originalToEmails,
        originalCcEmails: originalCcEmails,
        originalDateLine: dateLine,
        originalSubjectLine: subjectLine,
        fromLine: fromLine,
        toLine: toLine,
        ccLine: ccLine,
      ),
      bodyText: bodyText,
    );
  }
  return null;
}

bool _isForwardedMarker(String lowerLine) {
  return lowerLine.contains('forwarded message') ||
      lowerLine.contains('begin forwarded message') ||
      lowerLine.contains('---------- forwarded message');
}

int? _findHeaderStart(List<String> lines, int start) {
  for (var i = start; i < lines.length && i < start + 12; i++) {
    final trimmed = lines[i].trimLeft();
    if (_startsWithHeader(trimmed, 'from') ||
        _startsWithHeader(trimmed, 'to') ||
        _startsWithHeader(trimmed, 'subject') ||
        _startsWithHeader(trimmed, 'date') ||
        _startsWithHeader(trimmed, 'sent') ||
        _startsWithHeader(trimmed, 'cc')) {
      return i;
    }
  }
  return null;
}

int _findHeaderEnd(List<String> lines, int start) {
  for (var i = start; i < lines.length; i++) {
    if (lines[i].trim().isEmpty) {
      return i;
    }
  }
  return lines.length;
}

bool _startsWithHeader(String line, String key) {
  return line.toLowerCase().startsWith('$key:');
}

final RegExp _emailRegex =
    RegExp(r'[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}', caseSensitive: false);

String? _extractFirstEmail(String? line) {
  if (line == null) {
    return null;
  }
  final match = _emailRegex.firstMatch(line);
  return match?.group(0);
}

List<String> _extractEmailsFromLine(String? line) {
  if (line == null) {
    return const [];
  }
  final matches = _emailRegex.allMatches(line);
  return matches.map((match) => match.group(0)!).toList();
}
