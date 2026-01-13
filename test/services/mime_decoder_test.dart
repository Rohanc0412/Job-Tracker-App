import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:job_tracker/services/mime_decoder.dart';

void main() {
  group('MimeDecoder', () {
    test('decodes quoted-printable with charset', () {
      final headers = {
        'content-type': 'text/plain; charset="windows-1252"',
        'content-transfer-encoding': 'quoted-printable',
      };
      final body = Uint8List.fromList(
        'Interview scheduled =96 please confirm'.codeUnits,
      );
      final decoded =
          MimeDecoder.decodeBody(headers: headers, bodyBytes: body);

      expect(decoded.body, 'Interview scheduled – please confirm');
    });

    test('prefers text/plain part over html', () {
      final headers = {
        'content-type': 'multipart/alternative; boundary="abc123"',
      };
      const rawBody = '''
--abc123
Content-Type: text/plain; charset="utf-8"

Plain part here
--abc123
Content-Type: text/html; charset="utf-8"

<h1>HTML part</h1>
--abc123--
''';
      final decoded = MimeDecoder.decodeBody(
        headers: headers,
        bodyBytes: latin1.encode(rawBody),
      );

      expect(decoded.body, 'Plain part here');
    });
  });
}
