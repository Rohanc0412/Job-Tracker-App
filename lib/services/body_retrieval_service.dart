import 'dart:convert';
import 'dart:io';

import 'logger.dart';

class BodyRetrievalService {
  /// Retrieves the full email body content from either inline text or compressed file
  Future<String?> getFullBody({
    required String? rawBodyText,
    required String? rawBodyPath,
  }) async {
    // If we have inline text, return it directly
    if (rawBodyText != null && rawBodyText.isNotEmpty) {
      return rawBodyText;
    }

    // If we have a file path, decompress and read it
    if (rawBodyPath != null && rawBodyPath.isNotEmpty) {
      try {
        final file = File(rawBodyPath);
        if (!await file.exists()) {
          return null;
        }

        final compressed = await file.readAsBytes();
        final decompressed = gzip.decode(compressed);
        return utf8.decode(decompressed, allowMalformed: true);
      } catch (e) {
        AppLogger.log.warning('[BodyRetrieval] Failed to decompress body from $rawBodyPath: $e');
        return null;
      }
    }

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
