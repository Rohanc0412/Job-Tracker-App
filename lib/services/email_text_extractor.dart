import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';
import 'package:logging/logging.dart';

class EmailTextExtractor {
  static final _log = Logger('EmailTextExtractor');

  static String decodeMimeHeader(String value) {
    final decoded = value.replaceAllMapped(
      RegExp(r'=\?([^?]+)\?([bBqQ])\?([^?]+)\?='),
      (match) {
        final charset = match.group(1) ?? '';
        final encoding = match.group(2) ?? '';
        final payload = match.group(3) ?? '';
        try {
          if (encoding.toUpperCase() == 'B') {
            final bytes = base64.decode(payload);
            return _decodeHeaderBytes(bytes, charset);
          }
          final qp = payload.replaceAll('_', ' ');
          final bytes = _decodeQuotedPrintableBytes(qp);
          return _decodeHeaderBytes(bytes, charset);
        } catch (_) {
          return payload;
        }
      },
    );
    return decoded.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String normalizeSeparators(String text) {
    var normalized = text;
    normalized = normalized.replaceAll('|', ':');
    normalized = normalized.replaceAll(
      RegExp(r'[\u2022\u00b7\u2219]'),
      '-',
    );
    normalized = normalized.replaceAll(
      RegExp(r'[\u2012\u2013\u2014\u2015]'),
      '-',
    );
    normalized = normalized.replaceAll(RegExp(r'[ \t]+'), ' ');
    return normalized;
  }

  static String stripReplyChains(String text) {
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final rawLine = lines[i];
      final line = rawLine.trim();
      final lower = line.toLowerCase();
      if (lower.contains('-----original message-----') ||
          lower.contains('begin forwarded message:')) {
        final prefix = lines.take(i).join('\n');
        if (prefix.trim().isEmpty) {
          return _dequoteLines(lines.skip(i + 1));
        }
        if (_isTrivialPreamble(lines, i)) {
          return _dequoteLines(lines.skip(i + 1));
        }
        return prefix;
      }
      if (RegExp(r'^_{5,}$').hasMatch(line)) {
        if (i == 0) {
          continue;
        }
        if (_isTrivialPreamble(lines, i)) {
          continue;
        }
        return lines.take(i).join('\n');
      }
      if (_looksLikeReplyHeader(line)) {
        final prefix = lines.take(i).join('\n');
        if (prefix.trim().isEmpty) {
          return _dequoteLines(lines.skip(i + 1));
        }
        return prefix;
      }
      if (_looksLikeQuotedHeaderBlock(lines, i)) {
        if (_isTrivialPreamble(lines, i)) {
          final stripped = _stripForwardedHeaderBlock(lines, i);
          if (stripped != null) {
            return stripped;
          }
        }
        final prefix = lines.take(i).join('\n');
        if (prefix.trim().isEmpty) {
          return _dequoteLines(lines.skip(i));
        }
        return prefix;
      }
    }
    return text;
  }

  static String stripLegalDisclaimers(String text) {
    final lower = text.toLowerCase();
    final markers = [
      'this email and any attachments',
      'confidentiality notice',
    ];
    var earliest = -1;
    for (final marker in markers) {
      final index = lower.indexOf(marker);
      if (index != -1 && (earliest == -1 || index < earliest)) {
        earliest = index;
      }
    }
    if (earliest == -1) {
      return text;
    }
    return text.substring(0, earliest);
  }

  static String topSection(
    String text, {
    int maxLines = 100,
    int maxChars = 9000,
  }) {
    final lines = text.split('\n');
    final kept = <String>[];
    for (final line in lines) {
      if (line.trim().isEmpty) {
        continue;
      }
      kept.add(line);
      if (kept.length >= maxLines) {
        break;
      }
    }
    var result = kept.join('\n');
    if (result.length > maxChars) {
      result = result.substring(0, maxChars);
    }
    return result;
  }

  /// Extracts clean text from email body (supports both plain text and HTML)
  static String extractCleanText(String emailBody) {
    if (emailBody.trim().isEmpty) {
      return '';
    }

    // Decode quoted-printable encoding if present
    final normalizedBody = normalizeSeparators(emailBody);
    final mimeBody = _extractMimePart(normalizedBody) ?? normalizedBody;
    String decodedBody = mimeBody;
    if (mimeBody.contains('=3D') || mimeBody.contains('=\n')) {
      decodedBody = _decodeQuotedPrintable(mimeBody);
      _log.info('Decoded quoted-printable: ${decodedBody.length} bytes');
    }

    // Check if it's HTML (contains common HTML tags)
    final isHtml = decodedBody.contains('<html') ||
        decodedBody.contains('<body') ||
        decodedBody.contains('<div') ||
        decodedBody.contains('<p>') ||
        decodedBody.contains('<table');

    if (isHtml) {
      final extracted = _extractTextFromHtml(decodedBody);
      final outputPreview = extracted.length > 200
          ? extracted.substring(0, 200).replaceAll('\n', ' ')
          : extracted.replaceAll('\n', ' ');
      _log.info('Extracted output preview: $outputPreview...');
      final withoutReplies = stripReplyChains(extracted);
      final withoutDisclaimers = stripLegalDisclaimers(withoutReplies);
      return _cleanPlainText(withoutDisclaimers);
    } else {
      // Plain text email - just clean up excessive whitespace
      final cleaned = _cleanPlainText(decodedBody);
      final withoutReplies = stripReplyChains(cleaned);
      final withoutDisclaimers = stripLegalDisclaimers(withoutReplies);
      return _cleanPlainText(withoutDisclaimers);
    }
  }

  /// Decode quoted-printable encoding (RFC 2045)
  static String _decodeQuotedPrintable(String input) {
    try {
      // Remove soft line breaks (=\n)
      var text = input.replaceAll('=\r\n', '').replaceAll('=\n', '');

      // Decode =XX sequences
      final bytes = <int>[];
      var i = 0;
      while (i < text.length) {
        if (text[i] == '=' && i + 2 < text.length) {
          final hex = text.substring(i + 1, i + 3);
          try {
            final byte = int.parse(hex, radix: 16);
            bytes.add(byte);
            i += 3;
            continue;
          } catch (_) {
            // Not a valid hex sequence, keep the '='
          }
        }
        bytes.add(text.codeUnitAt(i));
        i++;
      }

      return utf8.decode(bytes, allowMalformed: true);
    } catch (e) {
      _log.warning('Failed to decode quoted-printable: $e');
      return input;
    }
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

  static String _decodeHeaderBytes(List<int> bytes, String charset) {
    final lower = charset.toLowerCase();
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
      return _decodeWindows1252(bytes);
    }
  }

  /// Extracts text without stripping reply/forward chains.
  static String extractTextPreservingReplies(String emailBody) {
    if (emailBody.trim().isEmpty) {
      return '';
    }

    final normalizedBody = normalizeSeparators(emailBody);
    final mimeBody = _extractMimePart(normalizedBody) ?? normalizedBody;
    String decodedBody = mimeBody;
    if (mimeBody.contains('=3D') || mimeBody.contains('=\n')) {
      decodedBody = _decodeQuotedPrintable(mimeBody);
    }

    final isHtml = decodedBody.contains('<html') ||
        decodedBody.contains('<body') ||
        decodedBody.contains('<div') ||
        decodedBody.contains('<p>') ||
        decodedBody.contains('<table');

    if (isHtml) {
      final extracted = _extractTextFromHtml(decodedBody);
      return _cleanPlainText(extracted);
    }
    return _cleanPlainText(decodedBody);
  }

  static String _decodeWindows1252(List<int> bytes) {
    final buffer = StringBuffer();
    for (final byte in bytes) {
      final mapped = _cp1252Map[byte];
      if (mapped != null) {
        buffer.write(mapped);
      } else {
        buffer.writeCharCode(byte);
      }
    }
    return buffer.toString();
  }

  /// Extract text from HTML email
  static String _extractTextFromHtml(String html) {
    try {
      // Parse HTML
      final document = html_parser.parse(html);

      // Remove script and style tags completely
      document.querySelectorAll('script, style, noscript, select').forEach((element) {
        element.remove();
      });

      // Get the body element, or fall back to entire document
      final body = document.body ?? document.documentElement;
      if (body == null) {
        return _cleanPlainText(html);
      }

      // Extract text with basic formatting
      final text = _extractTextFromNode(body);

      // Clean up the extracted text
      return _cleanPlainText(text);
    } catch (e) {
      // If HTML parsing fails, try to strip tags manually
      return _stripHtmlTags(html);
    }
  }

  /// Recursively extract text from HTML nodes
  static String _extractTextFromNode(Node node) {
    final buffer = StringBuffer();

    for (final child in node.nodes) {
      if (child is Text) {
        buffer.write(child.text);
      } else if (child is Element) {
        // Add line breaks for block elements
        if (_isBlockElement(child.localName)) {
          buffer.write('\n');
        }

        // Recursively get text from children
        buffer.write(_extractTextFromNode(child));

        // Add line break after block elements
        if (_isBlockElement(child.localName)) {
          buffer.write('\n');
        }
      }
    }

    return buffer.toString();
  }

  /// Check if element is a block-level element
  static bool _isBlockElement(String? tagName) {
    if (tagName == null) return false;
    return const {
      'p',
      'div',
      'br',
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
      'li',
      'tr',
      'table',
      'article',
      'section',
      'header',
      'footer',
    }.contains(tagName.toLowerCase());
  }

  /// Strip HTML tags manually (fallback)
  static String _stripHtmlTags(String html) {
    // Remove HTML tags
    var text = html.replaceAll(RegExp(r'<[^>]*>'), ' ');

    // Decode common HTML entities
    text = _decodeHtmlEntities(text);

    return _cleanPlainText(text);
  }

  /// Decode common HTML entities
  static String _decodeHtmlEntities(String text) {
    return text
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&ldquo;', '"')
        .replaceAll('&rdquo;', '"')
        .replaceAll('&lsquo;', "'")
        .replaceAll('&rsquo;', "'")
        .replaceAll('&mdash;', '--')
        .replaceAll('&ndash;', '-')
        .replaceAll('&bull;', '*')
        .replaceAll('&copy;', '(c)')
        .replaceAll('&reg;', '(r)')
        .replaceAll('&trade;', '(tm)')
        .replaceAll('&#8202;', ' ')
        .replaceAll('&zwnj;', '')
        .replaceAll('&rarr;', '->');
  }

  /// Clean up plain text (remove excessive whitespace)
  static String _cleanPlainText(String text) {
    // Decode HTML entities
    text = _decodeHtmlEntities(text);

    // Replace multiple spaces with single space
    text = text.replaceAll(RegExp(r'[ \t]+'), ' ');

    // Replace multiple newlines with maximum of 2
    text = text.replaceAll(RegExp(r'\n\s*\n\s*\n+'), '\n\n');

    // Remove leading/trailing whitespace from each line
    final lines = text.split('\n').map((line) => line.trim()).toList();

    // Remove empty lines at start and end
    while (lines.isNotEmpty && lines.first.isEmpty) {
      lines.removeAt(0);
    }
    while (lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }

    return lines.join('\n').trim();
  }

  /// Get a preview of the cleaned text
  static String getPreview(String emailBody, {int maxLength = 200}) {
    final cleanText = extractCleanText(emailBody);

    if (cleanText.length <= maxLength) {
      return cleanText;
    }

    // Try to break at a word boundary
    var preview = cleanText.substring(0, maxLength);
    final lastSpace = preview.lastIndexOf(' ');

    if (lastSpace > maxLength * 0.8) {
      // If we can find a space in the last 20%, use it
      preview = preview.substring(0, lastSpace);
    }

    return '$preview...';
  }

  static bool _looksLikeReplyHeader(String line) {
    final candidate = _stripLeadingQuotePrefix(line);
    return RegExp(r'^on .+ wrote:$', caseSensitive: false)
        .hasMatch(candidate);
  }

  static bool _looksLikeQuotedHeaderBlock(List<String> lines, int startIndex) {
    final line = _stripLeadingQuotePrefix(lines[startIndex]);
    if (!RegExp(r'^(from|sent|to|subject):', caseSensitive: false)
        .hasMatch(line)) {
      return false;
    }
    var matches = 0;
    for (var i = startIndex; i < lines.length && i < startIndex + 6; i++) {
      final candidate = _stripLeadingQuotePrefix(lines[i]);
      if (RegExp(r'^(from|sent|to|subject):', caseSensitive: false)
          .hasMatch(candidate)) {
        matches++;
      }
    }
    return matches >= 2;
  }

  static String _stripLeadingQuotePrefix(String value) {
    var candidate = value.trimLeft();
    while (candidate.startsWith('>')) {
      candidate = candidate.substring(1).trimLeft();
    }
    return candidate;
  }

  static String _dequoteLines(Iterable<String> lines) {
    final out = <String>[];
    for (final line in lines) {
      out.add(_stripLeadingQuotePrefix(line));
    }
    return out.join('\n');
  }

  static bool _isTrivialPreamble(List<String> lines, int endIndex) {
    if (endIndex <= 0) {
      return true;
    }
    for (var i = 0; i < endIndex; i++) {
      final trimmed = lines[i].trim();
      if (trimmed.isEmpty) {
        continue;
      }
      if (RegExp(r'^_{5,}$').hasMatch(trimmed)) {
        continue;
      }
      if (RegExp(r'^-[_-]{3,}$').hasMatch(trimmed)) {
        continue;
      }
      return false;
    }
    return true;
  }

  static String? _stripForwardedHeaderBlock(List<String> lines, int startIndex) {
    var i = startIndex;
    var headerLines = 0;
    for (; i < lines.length; i++) {
      final trimmed = _stripLeadingQuotePrefix(lines[i]);
      if (trimmed.trim().isEmpty) {
        if (headerLines >= 2) {
          return lines.skip(i + 1).join('\n');
        }
        continue;
      }
      if (RegExp(r'^(from|sent|to|subject):', caseSensitive: false)
          .hasMatch(trimmed)) {
        headerLines++;
        continue;
      }
      // Stop at first non-header line.
      break;
    }
    if (i < lines.length && headerLines >= 2) {
      return lines.skip(i).join('\n');
    }
    return null;
  }

  static String? _extractMimePart(String body) {
    final lines = body.split('\n');
    String? boundary;
    for (final line in lines) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('--') || trimmed.length < 4) {
        continue;
      }
      final candidate = trimmed.substring(2).trim();
      if (candidate.isEmpty) {
        continue;
      }
      final token = candidate.endsWith('--')
          ? candidate.substring(0, candidate.length - 2).trim()
          : candidate;
      if (RegExp(r"^[A-Za-z0-9'()+_.,:=?-]{6,}$").hasMatch(token)) {
        boundary = token;
        break;
      }
    }
    if (boundary == null) {
      return null;
    }

    final parts = body.split('--$boundary');
    String? htmlFallback;
    for (final part in parts) {
      final trimmed = part.trim();
      if (trimmed.isEmpty || trimmed == '--') {
        continue;
      }
      final partLines = trimmed.split(RegExp(r'\r?\n'));
      var headerEnd = partLines.indexWhere((line) => line.trim().isEmpty);
      if (headerEnd == -1) {
        headerEnd = 0;
      }
      final headerBlock = partLines.take(headerEnd).join('\n').toLowerCase();
      final content = partLines.skip(headerEnd + 1).join('\n').trim();
      if (headerBlock.contains('content-type: text/plain')) {
        return content;
      }
      if (headerBlock.contains('content-type: text/html')) {
        htmlFallback ??= content;
      }
    }

    if (htmlFallback != null) {
      return htmlFallback;
    }

    final boundaryPrefix = '--$boundary';
    final filtered = lines.where((line) {
      final trimmed = line.trimLeft();
      if (trimmed.startsWith(boundaryPrefix)) {
        return false;
      }
      final lower = trimmed.toLowerCase();
      return !(lower.startsWith('content-type:') ||
          lower.startsWith('content-transfer-encoding:'));
    }).toList();
    return filtered.join('\n').trim();
  }

  static const Map<int, String> _cp1252Map = {
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
}
