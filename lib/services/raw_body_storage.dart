import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;


class RawBodyStorageResult {
  final String? rawBodyText;
  final String? rawBodyPath;
  final String rawBodySha256;
  final int rawBodyByteLen;

  const RawBodyStorageResult({
    required this.rawBodyText,
    required this.rawBodyPath,
    required this.rawBodySha256,
    required this.rawBodyByteLen,
  });
}

class RawBodyStorage {
  RawBodyStorage({
    required this.maxRawBodyBytes,
    required this.hardCapBytes,
    required this.rawBodiesDir,
  });

  final int maxRawBodyBytes;
  final int hardCapBytes;
  final String rawBodiesDir;

  Future<RawBodyStorageResult> store({
    required Uint8List bodyBytes,
    required int reportedByteLen,
    required bool storeRawBody,
  }) async {
    final byteLen =
        reportedByteLen > 0 ? reportedByteLen : bodyBytes.length;
    final sha = sha256.convert(bodyBytes).toString();

    if (!storeRawBody) {
      return RawBodyStorageResult(
        rawBodyText: null,
        rawBodyPath: null,
        rawBodySha256: sha,
        rawBodyByteLen: byteLen,
      );
    }

    if (bodyBytes.length <= maxRawBodyBytes) {
      return RawBodyStorageResult(
        rawBodyText: utf8.decode(bodyBytes, allowMalformed: true),
        rawBodyPath: null,
        rawBodySha256: sha,
        rawBodyByteLen: byteLen,
      );
    }

    final truncatedBytes = bodyBytes.sublist(0, maxRawBodyBytes);
    final rawText = utf8.decode(truncatedBytes, allowMalformed: true);
    final fileName = '$sha.gz';
    final path = p.join(rawBodiesDir, fileName);
    final file = File(path);
    final compressed = gzip.encode(bodyBytes);
    await file.writeAsBytes(compressed, flush: true);
    return RawBodyStorageResult(
      rawBodyText: rawText,
      rawBodyPath: path,
      rawBodySha256: sha,
      rawBodyByteLen: byteLen,
    );
  }
}
