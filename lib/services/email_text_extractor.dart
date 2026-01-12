import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';
import 'package:logging/logging.dart';

class EmailTextExtractor {
  static final _log = Logger('EmailTextExtractor');

  /// Extracts clean text from email body (supports both plain text and HTML)
  static String extractCleanText(String emailBody) {
    if (emailBody.trim().isEmpty) {
      return '';
    }

    // Decode quoted-printable encoding if present
    String decodedBody = emailBody;
    if (emailBody.contains('=3D') || emailBody.contains('=\n')) {
      decodedBody = _decodeQuotedPrintable(emailBody);
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
      return extracted;
    } else {
      // Plain text email - just clean up excessive whitespace
      return _cleanPlainText(decodedBody);
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
        .replaceAll('&mdash;', '—')
        .replaceAll('&ndash;', '–')
        .replaceAll('&bull;', '•')
        .replaceAll('&copy;', '©')
        .replaceAll('&reg;', '®')
        .replaceAll('&trade;', '™')
        .replaceAll('&#8202;', ' ')
        .replaceAll('&zwnj;', '')
        .replaceAll('&rarr;', '→');
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
}
