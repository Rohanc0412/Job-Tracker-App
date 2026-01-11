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
    // For initial sync, fetch ALL emails since the start date
    // The ingestion pipeline will filter for job-related content
    final dateFilter = since != null ? 'SINCE ${_dateFormat.format(since.toUtc())}' : 'ALL';

    return 'UID SEARCH $dateFilter';
  }

  String uidSearchJobApplicationsFrom(int uid) {
    // For incremental sync, fetch ALL emails from the last UID
    // The ingestion pipeline will filter for job-related content
    return 'UID SEARCH UID $uid:*';
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
