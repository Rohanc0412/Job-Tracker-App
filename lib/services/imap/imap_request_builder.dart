import 'package:intl/intl.dart';

class ImapRequestBuilder {
  ImapRequestBuilder({
    DateFormat? dateFormat,
  }) : _dateFormat = dateFormat ?? DateFormat('dd-MMM-yyyy', 'en_US');

  final DateFormat _dateFormat;

  String login(String username, String password) {
    return 'LOGIN ${_quote(username)} ${_quote(password)}';
  }

  String select(String folder) {
    return 'SELECT ${_quote(folder)}';
  }

  String uidSearchSince(DateTime date) {
    final formatted = _dateFormat.format(date.toUtc());
    return 'UID SEARCH SINCE $formatted';
  }

  String uidSearchAll() {
    return 'UID SEARCH ALL';
  }

  String uidSearchFrom(int uid) {
    return 'UID SEARCH UID $uid:*';
  }

  String uidSearchJobApplications(DateTime? since) {
    // Server-side filtering for job-related emails using IMAP OR queries
    // This significantly reduces the number of emails fetched
    final dateFilter = since != null ? 'SINCE ${_dateFormat.format(since.toUtc())} ' : '';
    final keywordFilter = _jobKeywordFilter();
    return 'UID SEARCH $dateFilter$keywordFilter';
  }

  String uidSearchJobApplicationsFrom(int uid) {
    // Server-side filtering for job-related emails from a specific UID
    final keywordFilter = _jobKeywordFilter();
    return 'UID SEARCH UID $uid:* $keywordFilter';
  }

  /// Builds an IMAP OR query to filter for job-related emails.
  /// Uses TEXT search which matches both subject and body.
  String _jobKeywordFilter() {
    // Keywords that indicate job application emails
    const keywords = [
      'application',
      'interview',
      'candidate',
      'position',
      'opportunity',
      'hiring',
      'recruiter',
      'offer',
      'rejected',
      'assessment',
      'coding challenge',
      'phone screen',
    ];

    // Build nested OR structure: OR (OR (OR a b) c) d)
    // IMAP OR takes exactly 2 arguments, so we nest them
    var filter = 'TEXT "${keywords[0]}"';
    for (var i = 1; i < keywords.length; i++) {
      filter = 'OR $filter TEXT "${keywords[i]}"';
    }
    return '($filter)';
  }

  String uidFetchHeadersAndBody(int uid, int maxBodyBytes) {
    return 'UID FETCH $uid (UID BODY.PEEK[HEADER] BODY.PEEK[TEXT]<0.$maxBodyBytes>)';
  }

  String uidFetchHeaders(int uid, int maxHeaderBytes) {
    return 'UID FETCH $uid (UID BODY.PEEK[HEADER]<0.$maxHeaderBytes>)';
  }

  String logout() => 'LOGOUT';

  String _quote(String value) {
    final escaped = value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
    return '"$escaped"';
  }
}
