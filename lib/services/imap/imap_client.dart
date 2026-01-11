import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'imap_request_builder.dart';

class ImapSelectResult {
  final int uidValidity;

  const ImapSelectResult({
    required this.uidValidity,
  });
}

class ImapFetchedMessage {
  final int uid;
  final String headerText;
  final Uint8List bodyBytes;
  final int bodyByteLen;

  const ImapFetchedMessage({
    required this.uid,
    required this.headerText,
    required this.bodyBytes,
    required this.bodyByteLen,
  });
}

abstract class ImapTransport {
  Stream<List<int>> get stream;
  void write(String data);
  Future<void> close();
}

class SocketImapTransport implements ImapTransport {
  SocketImapTransport(this._socket);

  final Socket _socket;

  @override
  Stream<List<int>> get stream => _socket;

  @override
  void write(String data) {
    _socket.write(data);
  }

  @override
  Future<void> close() async {
    await _socket.close();
  }
}

class ImapClient {
  ImapClient({
    ImapTransport? transport,
    ImapRequestBuilder? requestBuilder,
    int maxLiteralBytes = 1024 * 1024,
  })  : _transport = transport,
        _requestBuilder = requestBuilder ?? ImapRequestBuilder(),
        _maxLiteralBytes = maxLiteralBytes;

  ImapTransport? _transport;
  final ImapRequestBuilder _requestBuilder;
  final int _maxLiteralBytes;
  ImapLineReader? _reader;
  int _tagCounter = 0;

  Future<void> connect(String host, int port) async {
    if (_transport == null) {
      print('[ImapClient] Establishing SSL connection to $host:$port...');
      final socket = await SecureSocket.connect(host, port);
      print('[ImapClient] SSL connection established');
      _transport = SocketImapTransport(socket);
    }
    _reader = ImapLineReader(_transport!.stream);
    print('[ImapClient] Reading server greeting...');
    final greeting = await _reader!.readLine();
    print('[ImapClient] Server greeting: $greeting');
  }

  Future<void> login(String username, String password) async {
    print('[ImapClient] Preparing LOGIN command...');
    final command = _requestBuilder.login(username, password);
    print('[ImapClient] Sending LOGIN command (password hidden)');
    await _sendAndExpectOk(command);
    print('[ImapClient] LOGIN successful');
  }

  Future<ImapSelectResult> select(String folder) async {
    final tag = _nextTag();
    _sendTagged(tag, _requestBuilder.select(folder));
    var uidValidity = 0;
    while (true) {
      final line = await _reader!.readLine();
      if (line.startsWith(tag)) {
        _ensureOk(line);
        break;
      }
      final match = RegExp(r'\[UIDVALIDITY (\d+)\]').firstMatch(line);
      if (match != null) {
        uidValidity = int.parse(match.group(1)!);
      }
    }
    return ImapSelectResult(uidValidity: uidValidity);
  }

  Future<List<int>> uidSearchSince(DateTime date) async {
    final tag = _nextTag();
    _sendTagged(tag, _requestBuilder.uidSearchSince(date));
    return _readSearchResults(tag);
  }

  Future<List<int>> uidSearchAll() async {
    final tag = _nextTag();
    _sendTagged(tag, _requestBuilder.uidSearchAll());
    return _readSearchResults(tag);
  }

  Future<List<int>> uidSearchFrom(int uid) async {
    final tag = _nextTag();
    _sendTagged(tag, _requestBuilder.uidSearchFrom(uid));
    return _readSearchResults(tag);
  }

  Future<List<int>> uidSearchJobApplications(DateTime? since) async {
    final tag = _nextTag();
    _sendTagged(tag, _requestBuilder.uidSearchJobApplications(since));
    return _readSearchResults(tag);
  }

  Future<List<int>> uidSearchJobApplicationsFrom(int uid) async {
    final tag = _nextTag();
    _sendTagged(tag, _requestBuilder.uidSearchJobApplicationsFrom(uid));
    return _readSearchResults(tag);
  }

  Future<String> fetchHeader(int uid, {int maxHeaderBytes = 64 * 1024}) async {
    final tag = _nextTag();
    _sendTagged(tag, _requestBuilder.uidFetchHeaders(uid, maxHeaderBytes));
    String headerText = '';

    while (true) {
      final line = await _reader!.readLine();
      if (line.startsWith(tag)) {
        _ensureOk(line);
        break;
      }
      final headerMatch =
          RegExp(r'BODY(?:\.PEEK)?\[HEADER[^\]]*\] \{(\d+)\}',
                  caseSensitive: false)
              .firstMatch(line);
      if (headerMatch != null) {
        final length = int.parse(headerMatch.group(1)!);
        final literal = await _reader!.readLiteral(
          length,
          maxBytes: maxHeaderBytes,
        );
        headerText = String.fromCharCodes(literal.bytes);
      }
    }

    return headerText;
  }

  Future<ImapFetchedMessage> fetchMessage(int uid) async {
    final tag = _nextTag();
    _sendTagged(tag, _requestBuilder.uidFetchHeadersAndBody(uid, _maxLiteralBytes));
    String headerText = '';
    Uint8List bodyBytes = Uint8List(0);
    var bodyByteLen = 0;

    while (true) {
      final line = await _reader!.readLine();
      if (line.startsWith(tag)) {
        _ensureOk(line);
        break;
      }
      final headerMatch =
          RegExp(r'BODY(?:\.PEEK)?\[HEADER[^\]]*\] \{(\d+)\}',
                  caseSensitive: false)
              .firstMatch(line);
      if (headerMatch != null) {
        final length = int.parse(headerMatch.group(1)!);
        final literal = await _reader!.readLiteral(
          length,
          maxBytes: _maxLiteralBytes,
        );
        headerText = String.fromCharCodes(literal.bytes);
        continue;
      }

      final bodyMatch =
          RegExp(r'BODY(?:\.PEEK)?\[TEXT[^\]]*\] \{(\d+)\}',
                  caseSensitive: false)
              .firstMatch(line);
      if (bodyMatch != null) {
        final length = int.parse(bodyMatch.group(1)!);
        final literal = await _reader!.readLiteral(
          length,
          maxBytes: _maxLiteralBytes,
        );
        bodyBytes = literal.bytes;
        bodyByteLen = literal.fullLength;
      }
    }

    return ImapFetchedMessage(
      uid: uid,
      headerText: headerText,
      bodyBytes: bodyBytes,
      bodyByteLen: bodyByteLen == 0 ? bodyBytes.length : bodyByteLen,
    );
  }

  Future<void> logout() async {
    final command = _requestBuilder.logout();
    await _sendAndExpectOk(command);
    await _reader?.close();
    await _transport?.close();
  }

  Future<void> _sendAndExpectOk(String command) async {
    final tag = _nextTag();
    final preview = command.length > 20 ? '${command.substring(0, 20)}...' : command;
    print('[ImapClient] Tag: $tag, Command: $preview');
    _sendTagged(tag, command);
    print('[ImapClient] Command sent, waiting for response...');
    while (true) {
      print('[ImapClient] Reading response line...');
      final line = await _reader!.readLine();
      print('[ImapClient] Response: $line');
      if (line.startsWith(tag)) {
        _ensureOk(line);
        print('[ImapClient] Command completed with tag $tag');
        break;
      }
    }
  }

  Future<List<int>> _readSearchResults(String tag) async {
    final uids = <int>[];
    while (true) {
      final line = await _reader!.readLine();
      if (line.startsWith(tag)) {
        _ensureOk(line);
        break;
      }
      if (line.startsWith('* SEARCH')) {
        final parts = line.split(' ');
        for (final part in parts.skip(2)) {
          final parsed = int.tryParse(part);
          if (parsed != null) {
            uids.add(parsed);
          }
        }
      }
    }
    return uids;
  }

  void _sendTagged(String tag, String command) {
    _transport?.write('$tag $command\r\n');
  }

  String _nextTag() {
    _tagCounter++;
    return 'A${_tagCounter.toString().padLeft(4, '0')}';
  }

  void _ensureOk(String line) {
    if (!line.contains('OK')) {
      throw StateError('IMAP command failed: $line');
    }
  }
}

class ImapLiteral {
  final Uint8List bytes;
  final int fullLength;

  const ImapLiteral({
    required this.bytes,
    required this.fullLength,
  });
}

class ImapLineReader {
  ImapLineReader(Stream<List<int>> stream)
      : _iterator = StreamIterator<List<int>>(stream);

  final StreamIterator<List<int>> _iterator;
  final List<int> _buffer = [];

  Future<String> readLine() async {
    while (true) {
      final index = _buffer.indexOf(10);
      if (index != -1) {
        final bytes = _buffer.sublist(0, index + 1);
        _buffer.removeRange(0, index + 1);
        final line = String.fromCharCodes(bytes);
        return line.trimRight();
      }
      await _fillBuffer();
    }
  }

  Future<ImapLiteral> readLiteral(int length, {required int maxBytes}) async {
    final keep = min(length, maxBytes);
    final bytes = BytesBuilder(copy: false);
    var remaining = length;
    var kept = 0;
    while (remaining > 0) {
      if (_buffer.isEmpty) {
        await _fillBuffer();
      }
      final take = min(remaining, _buffer.length);
      if (kept < keep) {
        final toKeep = min(take, keep - kept);
        bytes.add(_buffer.sublist(0, toKeep));
        kept += toKeep;
      }
      _buffer.removeRange(0, take);
      remaining -= take;
    }
    return ImapLiteral(bytes: bytes.takeBytes(), fullLength: length);
  }

  Future<void> _fillBuffer() async {
    if (!await _iterator.moveNext()) {
      throw StateError('IMAP connection closed.');
    }
    _buffer.addAll(_iterator.current);
  }

  Future<void> close() async {
    await _iterator.cancel();
    _buffer.clear();
  }
}
