import 'dart:convert';
import 'dart:io';

import 'email_text_extractor.dart';
import 'logger.dart';

class BodyRetrievalService {
  /// Retrieves the full email body content from either inline text or compressed file
  /// and extracts clean text (removes HTML markup and unnecessary formatting)
  Future<String?> getFullBody({
    required String? rawBodyText,
    required String? rawBodyPath,
  }) async {
    String? rawBody;

    AppLogger.log.info('[BodyRetrieval] getFullBody called: hasText=${rawBodyText != null}, textLen=${rawBodyText?.length ?? 0}, hasPath=${rawBodyPath != null}, path=$rawBodyPath');

    // Prefer reading from file when available, since inline text may be truncated.
    if (rawBodyPath != null && rawBodyPath.isNotEmpty) {
      try {
        final file = File(rawBodyPath);
        if (await file.exists()) {
          final compressed = await file.readAsBytes();
          final decompressed = gzip.decode(compressed);
          final decoded = utf8.decode(decompressed, allowMalformed: true);
          if (decoded.trim().isNotEmpty) {
            rawBody = decoded;
            AppLogger.log.info('[BodyRetrieval] Loaded from file: ${decoded.length} bytes, preview: ${decoded.substring(0, 100).replaceAll('\n', ' ')}...');
          }
        }
      } catch (e) {
        AppLogger.log.warning(
            '[BodyRetrieval] Failed to decompress body from $rawBodyPath: $e');
      }
    }

    // Fallback to inline text (may be truncated)
    if (rawBody == null && rawBodyText != null && rawBodyText.isNotEmpty) {
      rawBody = rawBodyText;
      AppLogger.log.info('[BodyRetrieval] Using inline text: ${rawBody.length} bytes, preview: ${rawBody.substring(0, 100).replaceAll('\n', ' ')}...');
    }

    // Extract clean text from HTML or plain text
    if (rawBody != null) {
      try {
        final cleanText = EmailTextExtractor.extractCleanText(rawBody);
        AppLogger.log.info('[BodyRetrieval] Extracted clean text: ${cleanText.length} bytes, preview: ${cleanText.substring(0, 100).replaceAll('\n', ' ')}...');
        return cleanText;
      } catch (e) {
        AppLogger.log.warning('[BodyRetrieval] Failed to extract clean text: $e');
        // Return raw body as fallback if extraction fails
        return rawBody;
      }
    }

    AppLogger.log.warning('[BodyRetrieval] No body content available');
    return null;
  }

  /// Gets a preview of the body (first N characters)
  String getBodyPreview(String? fullBody, {int maxLength = 500}) {
    if (fullBody == null || fullBody.isEmpty) {
      return '';
    }

    final normalized = fullBody.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxLength) {
      return normalized;
    }

    return '${normalized.substring(0, maxLength - 3).trimRight()}...';
  }
}
