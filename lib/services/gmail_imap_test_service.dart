import 'package:intl/intl.dart';

import 'imap/imap_client.dart';

class GmailImapTestMessage {
  final int uid;
  final String subject;
  final String from;
  final String date;

  const GmailImapTestMessage({
    required this.uid,
    required this.subject,
    required this.from,
    required this.date,
  });
}

class GmailImapTestResult {
  final int uidValidity;
  final List<GmailImapTestMessage> messages;

  const GmailImapTestResult({
    required this.uidValidity,
    required this.messages,
  });
}

class GmailImapTestService {
  Future<GmailImapTestResult> fetchRecentHeaders({
    required String email,
    required String appPassword,
    String folder = 'INBOX',
    int limit = 10,
  }) async {
    print('[GmailImapTest] Creating IMAP client...');
    final imap = ImapClient(maxLiteralBytes: 128 * 1024);

    print('[GmailImapTest] Connecting to imap.gmail.com:993...');
    await imap.connect('imap.gmail.com', 993);

    print('[GmailImapTest] Logging in as $email...');
    await imap.login(email, appPassword);

    print('[GmailImapTest] Selecting folder: $folder...');
    final selectResult = await imap.select(folder);

    print('[GmailImapTest] Searching for all UIDs...');
    final uids = await imap.uidSearchAll();
    uids.sort();
    final slice = uids.length > limit ? uids.sublist(uids.length - limit) : uids;
    print('[GmailImapTest] Found ${uids.length} total UIDs, fetching last $limit...');

    final messages = <GmailImapTestMessage>[];
    var count = 0;
    for (final uid in slice) {
      count++;
      print('[GmailImapTest] Fetching header $count/${slice.length} (UID $uid)...');
      final headerText = await imap.fetchHeader(uid);
      final headers = _parseHeaders(headerText);
      messages.add(GmailImapTestMessage(
        uid: uid,
        subject: headers['subject'] ?? 'No subject',
        from: headers['from'] ?? 'unknown',
        date: _formatDate(headers['date']),
      ));
    }

    print('[GmailImapTest] Logging out...');
    await imap.logout();

    print('[GmailImapTest] Complete! Fetched ${messages.length} messages');
    return GmailImapTestResult(
      uidValidity: selectResult.uidValidity,
      messages: messages,
    );
  }

  Map<String, String> _parseHeaders(String headerText) {
    final headers = <String, String>{};
    String? currentKey;
    final lines = headerText.split(RegExp(r'\r?\n'));
    for (final line in lines) {
      if (line.startsWith(' ') || line.startsWith('\t')) {
        if (currentKey != null) {
          headers[currentKey] = '${headers[currentKey]} ${line.trim()}';
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

  String _formatDate(String? value) {
    if (value == null) {
      return '';
    }
    try {
      return DateFormat('yyyy-MM-dd HH:mm')
          .format(DateFormat('EEE, dd MMM yyyy HH:mm:ss Z', 'en_US').parseUtc(value).toLocal());
    } catch (_) {
      return value;
    }
  }
}
