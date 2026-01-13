import 'dart:convert';
import 'dart:typed_data';

class MimeDecodedBody {
  final String body;
  final String? icsPayload;
  final String? charset;
  final String? contentTransferEncoding;

  const MimeDecodedBody({
    required this.body,
    this.icsPayload,
    this.charset,
    this.contentTransferEncoding,
  });
}

class MimePart {
  final Map<String, String> headers;
  final String body;

  const MimePart({
    required this.headers,
    required this.body,
  });
}

/// Minimal MIME decoder for email bodies.
/// Handles multipart boundaries, content-transfer-encoding, and common charsets.
class MimeDecoder {
  static MimeDecodedBody decodeBody({
    required Map<String, String> headers,
    required Uint8List bodyBytes,
  }) {
    final contentType = headers['content-type'];
    final transferEncoding = headers['content-transfer-encoding'];
    final boundary = _parseBoundary(contentType);
    final defaultCharset = _parseCharset(contentType);
    final rawBody = latin1.decode(bodyBytes, allowInvalid: true);

    if (boundary != null) {
      String? plainText;
      String? htmlText;
      String? calendar;
      for (final part in _splitMultipart(rawBody, boundary)) {
        final partContentType =
            part.headers['content-type'] ?? contentType ?? 'text/plain';
        final partEncoding =
            part.headers['content-transfer-encoding'] ?? transferEncoding;
        final charset =
            _parseCharset(partContentType) ?? defaultCharset;
        final decoded = _decodePart(
          latin1.encode(part.body),
          charset: charset,
          contentTransferEncoding: partEncoding,
        );
        final lowerType = partContentType.toLowerCase();
        if (lowerType.startsWith('text/plain') && plainText == null) {
          plainText = decoded;
        } else if (lowerType.startsWith('text/html') && htmlText == null) {
          htmlText = decoded;
        } else if (lowerType.startsWith('text/calendar') &&
            calendar == null) {
          calendar = decoded;
        }
      }
      final selected = plainText ?? htmlText ?? rawBody.trim();
      return MimeDecodedBody(
        body: selected.trim(),
        icsPayload: calendar?.trim(),
        charset: defaultCharset,
        contentTransferEncoding: transferEncoding,
      );
    }

    final decoded = _decodePart(
      bodyBytes,
      charset: defaultCharset,
      contentTransferEncoding: transferEncoding,
    );
    final icsPayload = _extractIcs(decoded);
    return MimeDecodedBody(
      body: decoded.trim(),
      icsPayload: icsPayload,
      charset: defaultCharset,
      contentTransferEncoding: transferEncoding,
    );
  }

  static List<MimePart> _splitMultipart(String rawBody, String boundary) {
    final token = '--$boundary';
    final parts = <MimePart>[];
    for (final chunk in rawBody.split(token)) {
      final trimmed = chunk.trim();
      if (trimmed.isEmpty || trimmed == '--') {
        continue;
      }
      final lines = trimmed.split(RegExp(r'\r?\n'));
      final headerLines = <String>[];
      var index = 0;
      for (; index < lines.length; index++) {
        if (lines[index].trim().isEmpty) {
          index++;
          break;
        }
        headerLines.add(lines[index]);
      }
      final headers = parseHeaders(headerLines);
      final body = lines.skip(index).join('\n');
      parts.add(MimePart(headers: headers, body: body));
    }
    return parts;
  }

  static Map<String, String> parseHeaders(List<String> lines) {
    final headers = <String, String>{};
    String? currentKey;
    for (final line in lines) {
      if (line.startsWith(' ') || line.startsWith('\t')) {
        if (currentKey != null) {
          headers[currentKey] =
              '${headers[currentKey]} ${line.trim()}';
        }
        continue;
      }
      final index = line.indexOf(':');
      if (index <= 0) {
        continue;
      }
      currentKey = line.substring(0, index).trim().toLowerCase();
      headers[currentKey] = line.substring(index + 1).trim();
    }
    return headers;
  }

  static Map<String, String> parseHeaderBlock(String headerText) {
    final lines = headerText.split(RegExp(r'\r?\n'));
    return parseHeaders(lines);
  }

  static String _decodePart(
    Uint8List bytes, {
    String? charset,
    String? contentTransferEncoding,
  }) {
    final encoding = contentTransferEncoding?.toLowerCase().trim() ?? '';
    List<int> payload = bytes;

    if (encoding == 'base64') {
      final cleaned = latin1.decode(bytes, allowInvalid: true)
          .replaceAll(RegExp(r'\s+'), '');
      try {
        payload = base64.decode(cleaned);
      } catch (_) {
        // Fall back to original bytes.
        payload = bytes;
      }
    } else if (encoding == 'quoted-printable') {
      payload = _decodeQuotedPrintableBytes(
        latin1.decode(bytes, allowInvalid: true),
      );
    }

    return _decodeBytesWithCharset(payload, charset);
  }

  static List<int> _decodeQuotedPrintableBytes(String input) {
    var text = input.replaceAll('=\r\n', '').replaceAll('=\n', '');
    final bytes = <int>[];
    var i = 0;
    while (i < text.length) {
      if (text[i] == '=' && i + 2 < text.length) {
        final hex = text.substring(i + 1, i + 3);
        final byte = int.tryParse(hex, radix: 16);
        if (byte != null) {
          bytes.add(byte);
          i += 3;
          continue;
        }
      }
      bytes.add(text.codeUnitAt(i));
      i++;
    }
    return bytes;
  }

  static String _decodeBytesWithCharset(List<int> bytes, String? charset) {
    final lower = charset?.toLowerCase() ?? '';
    if (lower.contains('utf-8') || lower.contains('utf8')) {
      return utf8.decode(bytes, allowMalformed: true);
    }
    if (lower.contains('iso-8859-1') || lower.contains('latin1')) {
      return latin1.decode(bytes);
    }
    if (lower.contains('windows-1252') || lower.contains('cp1252')) {
      return _decodeWindows1252(bytes);
    }
    try {
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return latin1.decode(bytes, allowInvalid: true);
    }
  }

  static String _decodeWindows1252(List<int> bytes) {
    final buffer = StringBuffer();
    for (final byte in bytes) {
      if (_cp1252Map.containsKey(byte)) {
        buffer.write(_cp1252Map[byte]);
      } else {
        buffer.writeCharCode(byte);
      }
    }
    return buffer.toString();
  }

  static String? _parseBoundary(String? contentType) {
    if (contentType == null) {
      return null;
    }
    final boundaryIndex = contentType.toLowerCase().indexOf('boundary=');
    if (boundaryIndex == -1) {
      return null;
    }
    final value = contentType.substring(boundaryIndex + 9).trim();
    final raw = value.split(';').first.trim();
    if (raw.startsWith('"') && raw.endsWith('"')) {
      return raw.substring(1, raw.length - 1);
    }
    return raw;
  }

  static String? _parseCharset(String? contentType) {
    if (contentType == null) {
      return null;
    }
    final match = RegExp(r'charset="?([^\";]+)"?', caseSensitive: false)
        .firstMatch(contentType);
    return match?.group(1)?.trim();
  }

  static String? _extractIcs(String text) {
    final start = text.indexOf('BEGIN:VCALENDAR');
    if (start == -1) {
      return null;
    }
    final end = text.indexOf('END:VCALENDAR');
    if (end == -1) {
      return null;
    }
    return text.substring(start, end + 'END:VCALENDAR'.length).trim();
  }
}

const Map<int, String> _cp1252Map = {
  0x80: '€',
  0x82: '‚',
  0x83: 'ƒ',
  0x84: '„',
  0x85: '…',
  0x86: '†',
  0x87: '‡',
  0x88: 'ˆ',
  0x89: '‰',
  0x8A: 'Š',
  0x8B: '‹',
  0x8C: 'Œ',
  0x8E: 'Ž',
  0x91: '‘',
  0x92: '’',
  0x93: '“',
  0x94: '”',
  0x95: '•',
  0x96: '–',
  0x97: '—',
  0x98: '˜',
  0x99: '™',
  0x9A: 'š',
  0x9B: '›',
  0x9C: 'œ',
  0x9E: 'ž',
  0x9F: 'Ÿ',
};
