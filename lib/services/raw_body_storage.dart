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
    String? decodedText,
  }) async {
    final byteLen =
        reportedByteLen > 0 ? reportedByteLen : bodyBytes.length;

    final text = decodedText ?? utf8.decode(bodyBytes, allowMalformed: true);
    final textBytes = utf8.encode(text);
    final sha = sha256.convert(textBytes).toString();

    if (!storeRawBody) {
      return RawBodyStorageResult(
        rawBodyText: null,
        rawBodyPath: null,
        rawBodySha256: sha,
        rawBodyByteLen: byteLen,
      );
    }

    if (textBytes.length <= maxRawBodyBytes) {
      return RawBodyStorageResult(
        rawBodyText: text,
        rawBodyPath: null,
        rawBodySha256: sha,
        rawBodyByteLen: byteLen,
      );
    }

    final truncatedBytes = textBytes.sublist(
      0,
      textBytes.length < maxRawBodyBytes
          ? textBytes.length
          : maxRawBodyBytes,
    );
    final rawText = utf8.decode(truncatedBytes, allowMalformed: true);
    final fileName = '$sha.gz';
    final path = p.join(rawBodiesDir, fileName);
    final file = File(path);
    final compressed = gzip.encode(textBytes);
    await file.writeAsBytes(compressed, flush: true);
    return RawBodyStorageResult(
      rawBodyText: rawText,
      rawBodyPath: path,
      rawBodySha256: sha,
      rawBodyByteLen: byteLen,
    );
  }
}
