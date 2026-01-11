import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:job_tracker/services/imap/imap_client.dart';

class ImapScriptStep {
  final String command;
  final List<Object> responses;

  const ImapScriptStep({
    required this.command,
    required this.responses,
  });
}

class MockImapTransport implements ImapTransport {
  MockImapTransport(this._script) {
    _enqueue('* OK IMAP ready\r\n');
  }

  final List<ImapScriptStep> _script;
  final StreamController<List<int>> _controller =
      StreamController<List<int>>();

  @override
  Stream<List<int>> get stream => _controller.stream;

  @override
  void write(String data) {
    final trimmed = data.trim();
    final space = trimmed.indexOf(' ');
    final tag = space == -1 ? 'A0000' : trimmed.substring(0, space);
    final command = space == -1 ? '' : trimmed.substring(space + 1);
    if (_script.isEmpty) {
      fail('Unexpected IMAP command: $command');
    }
    final step = _script.removeAt(0);
    expect(command, startsWith(step.command));
    for (final response in step.responses) {
      if (response is String) {
        _enqueue(response.replaceAll('{tag}', tag));
      } else if (response is List<int>) {
        _controller.add(response);
      } else {
        throw StateError('Unsupported response type: $response');
      }
    }
  }

  @override
  Future<void> close() async {
    await _controller.close();
  }

  void _enqueue(String value) {
    _controller.add(utf8.encode(value));
  }
}
