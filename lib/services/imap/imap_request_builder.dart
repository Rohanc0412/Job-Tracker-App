import 'package:intl/intl.dart';

class ImapRequestBuilder {
  ImapRequestBuilder({
    DateFormat? dateFormat,
    DateFormat? gmailRawDateFormat,
  })  : _dateFormat = dateFormat ?? DateFormat('dd-MMM-yyyy', 'en_US'),
        _gmailRawDateFormat =
            gmailRawDateFormat ?? DateFormat('yyyy/MM/dd', 'en_US');

  final DateFormat _dateFormat;
  final DateFormat _gmailRawDateFormat;

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

  String uidSearchJobApplications(
    DateTime? since, {
    bool gmailRaw = false,
  }) {
    if (gmailRaw) {
      final query = _gmailRawQuery(since);
      return 'UID SEARCH X-GM-RAW ${_quote(query)}';
    }

    // Generic IMAP: subject filter + body keyword filter.
    final dateFilter = since != null
        ? 'SINCE ${_dateFormat.format(since.toUtc())} '
        : '';
    final subjectFilter = _jobSubjectFilter();
    final bodyFilter = _jobBodyFilter();
    return 'UID SEARCH ${dateFilter}OR $subjectFilter $bodyFilter';
  }

  String uidSearchJobApplicationsFrom(
    int uid, {
    DateTime? since,
    bool gmailRaw = false,
  }) {
    if (gmailRaw) {
      // Restrict by UID range and apply Gmail raw query to reduce noise.
      final query = _gmailRawQuery(since);
      return 'UID SEARCH UID $uid:* X-GM-RAW ${_quote(query)}';
    }

    // Generic IMAP: subject filter + body keyword filter.
    final subjectFilter = _jobSubjectFilter();
    final bodyFilter = _jobBodyFilter();
    final sinceFilter = since == null
        ? ''
        : 'SINCE ${_dateFormat.format(since.toUtc())} ';
    return 'UID SEARCH UID $uid:* ${sinceFilter}OR $subjectFilter $bodyFilter';
  }

  String _jobSubjectFilter() {
    // Keep this tight to avoid newsletters/marketing. (Notably: no "offer",
    // "opportunity", or "position" which are extremely noisy.)
    const keywords = [
      'application received',
      'application confirmation',
      'application',
      'interview',
      'recruiter',
      'hiring',
      'assessment',
      'coding challenge',
      'phone screen',
    ];

    var filter = 'SUBJECT ${_quote(keywords[0])}';
    for (var i = 1; i < keywords.length; i++) {
      filter = 'OR $filter SUBJECT ${_quote(keywords[i])}';
    }
    return '($filter)';
  }

  String _jobBodyFilter() {
    // Include a few body-only cues without widening too far.
    const keywords = [
      'application',
      'status update',
      'interview',
      'phone screen',
      'assessment',
      'coding challenge',
      'take home',
      'take-home',
      'recruiter',
      'hiring',
      'offer letter',
      'rejection',
      'background check',
      'reference check',
      'next steps',
    ];

    var filter = 'TEXT ${_quote(keywords[0])}';
    for (var i = 1; i < keywords.length; i++) {
      filter = 'OR $filter TEXT ${_quote(keywords[i])}';
    }
    return '($filter)';
  }

  String _gmailRawQuery(DateTime? since) {
    final sinceFilter = since == null
        ? ''
        : ' after:${_gmailRawDateFormat.format(since)}';
    final keywordQuery = _gmailKeywordQuery();
    final negativeQuery = _gmailNegativeQuery();
    return 'in:inbox$sinceFilter -category:promotions$keywordQuery$negativeQuery';
  }

  String _gmailKeywordQuery() {
    const keywords = [
      'application',
      'application status',
      'status update',
      'interview',
      'phone screen',
      'assessment',
      'coding challenge',
      'take home',
      'take-home',
      'recruiter',
      'hiring',
      'offer letter',
      'rejection',
      'background check',
      'reference check',
      'next steps',
    ];
    final clauses = keywords.map((term) => '"$term"').join(' OR ');
    return ' ($clauses)';
  }

  String _gmailNegativeQuery() {
    const negative = [
      'newsletter',
      'promo',
      'promotion',
      'sale',
      'discount',
      'webinar',
    ];
    final clauses = negative.map((term) => '"$term"').join(' OR ');
    return ' -($clauses)';
  }

  String uidFetchHeadersAndBody(int uid, int maxBodyBytes) {
    return 'UID FETCH $uid (UID BODY.PEEK[HEADER] BODY.PEEK[TEXT]<0.$maxBodyBytes>)';
  }

  String uidFetchHeadersAndBodyFull(int uid) {
    return 'UID FETCH $uid (UID BODY.PEEK[HEADER] BODY.PEEK[TEXT])';
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
