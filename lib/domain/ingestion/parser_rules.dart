import 'dart:core';

const List<String> _portalHints = [
  'jobs',
  'careers',
  'job',
  'positions',
  'role',
  'opening',
];

List<String> extractUrls(String text) {
  final matches = RegExp(r'(https?://[^\s<>()\[\]"]+)')
      .allMatches(text);
  return matches
      .map((match) => match.group(0)!)
      .map(_trimUrl)
      .where((url) => url.isNotEmpty)
      .toList();
}

String sanitizeUrl(String url) {
  var sanitized = _trimUrl(url);
  final uri = Uri.tryParse(sanitized);
  if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
    return sanitized;
  }
  final filteredParams = Map<String, String>.from(uri.queryParameters);
  filteredParams.removeWhere((key, _) {
    final lower = key.toLowerCase();
    return lower.startsWith('utm_') ||
        lower == 'ref' ||
        lower == 'source' ||
        lower == 'campaign' ||
        lower == 'medium';
  });
  final cleaned = Uri(
    scheme: uri.scheme,
    userInfo: uri.userInfo,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path,
    queryParameters: filteredParams.isEmpty ? null : filteredParams,
  );
  return cleaned.toString();
}

String? selectPortalUrl(List<String> urls) {
  if (urls.isEmpty) {
    return null;
  }
  final scored = <_ScoredUrl>[];
  for (final url in urls) {
    final sanitized = sanitizeUrl(url);
    final uri = Uri.tryParse(sanitized);
    if (uri == null) {
      continue;
    }
    var score = 0;
    final path = uri.path.toLowerCase();
    final host = uri.host.toLowerCase();
    for (final hint in _portalHints) {
      if (path.contains(hint)) {
        score += 3;
      }
      if (host.contains(hint)) {
        score += 1;
      }
    }
    if (uri.queryParameters.keys.any(_isJobIdKey)) {
      score += 2;
    }
    scored.add(_ScoredUrl(sanitized, score));
  }
  if (scored.isEmpty) {
    return null;
  }
  scored.sort((a, b) => b.score.compareTo(a.score));
  return scored.first.url;
}

String? extractJobId(String text, {String? portalUrl}) {
  if (portalUrl != null) {
    final uri = Uri.tryParse(portalUrl);
    if (uri != null) {
      for (final entry in uri.queryParameters.entries) {
        if (_isJobIdKey(entry.key)) {
          return entry.value;
        }
      }
      for (final segment in uri.pathSegments.reversed) {
        if (segment.isEmpty) {
          continue;
        }
        if (RegExp(r'\d{3,}').hasMatch(segment)) {
          return segment;
        }
      }
    }
  }
  final match = RegExp(
    r'\bjob\s*id[:\s#-]*([A-Za-z0-9_-]+)',
    caseSensitive: false,
  ).firstMatch(text);
  if (match != null) {
    return match.group(1);
  }
  return null;
}

String? extractCompany(String subject, String body, String fromAddr) {
  final subjectCompany =
      _shouldSkipSubjectCompany(subject) ? null : _extractCompanyFromText(subject);
  if (subjectCompany != null) {
    return subjectCompany;
  }
  final bodyCompany = _extractCompanyFromText(body);
  if (bodyCompany != null) {
    return bodyCompany;
  }
  final fromDisplay = _extractDisplayName(fromAddr);
  if (fromDisplay != null && !_looksLikePersonName(fromDisplay)) {
    return fromDisplay;
  }
  final domainCompany = _extractCompanyFromEmail(fromAddr);
  if (domainCompany != null) {
    return domainCompany;
  }
  return fromDisplay;
}

String? extractRole(String subject, String body) {
  final roleFromSubject = _extractRoleFromText(subject);
  if (roleFromSubject != null) {
    return roleFromSubject;
  }
  return _extractRoleFromText(body);
}

String _trimUrl(String url) {
  return url.trim().replaceAll(RegExp(r'[).,;!]+$'), '');
}

String? _extractCompanyFromText(String text) {
  final patterns = [
    RegExp(r'\bat\s+([A-Z][A-Za-z0-9&. -]+)$'),
    RegExp(r'^([A-Z][A-Za-z0-9&. -]+?)\s+(?:application|interview|offer|update)'),
    RegExp(r'\bfrom\s+([A-Z][A-Za-z0-9&. -]+)$'),
    RegExp(r'^([A-Z][A-Za-z0-9&. -]+)\s+application confirmation'),
  ];
  for (final pattern in patterns) {
    final match = pattern.firstMatch(text.trim());
    if (match != null) {
      return match.group(1)?.trim();
    }
  }
  return null;
}

bool _shouldSkipSubjectCompany(String subject) {
  final value = subject.trim().toLowerCase();
  const prefixes = [
    'update on your',
    'scheduling your',
    'interview request',
  ];
  return prefixes.any(value.startsWith);
}

String? _extractRoleFromText(String text) {
  final patterns = [
    RegExp(r'for\s+([A-Z][A-Za-z0-9 &/.\-]+?)\s+at',
        caseSensitive: false),
    RegExp(r'for\s+([A-Z][A-Za-z0-9 &/.\-]+)$', caseSensitive: false),
    RegExp(r'application received\s*-\s*([A-Za-z0-9 &/.\-]+)$',
        caseSensitive: false),
    RegExp(r'interview request\s*-\s*([A-Za-z0-9 &/.\-]+)$',
        caseSensitive: false),
    RegExp(r'update on your\s+([A-Za-z0-9 &/.\-]+)\s+application',
        caseSensitive: false),
    RegExp(r'offer for\s+([A-Za-z0-9 &/.\-]+)\s+at',
        caseSensitive: false),
  ];
  for (final pattern in patterns) {
    final match = pattern.firstMatch(text.trim());
    if (match != null) {
      return match.group(1)?.trim();
    }
  }
  return null;
}

bool _isJobIdKey(String key) {
  final lower = key.toLowerCase();
  return lower == 'jobid' ||
      lower == 'job_id' ||
      lower == 'jid' ||
      lower == 'req' ||
      lower == 'reqid' ||
      lower == 'requisitionid' ||
      lower == 'requisition_id' ||
      lower == 'position' ||
      lower == 'positionid' ||
      lower == 'gh_jid';
}

String? _extractDisplayName(String fromAddr) {
  final parts = fromAddr.split('<');
  if (parts.isNotEmpty) {
    final display = parts.first.trim();
    if (display.isNotEmpty && !display.contains('@')) {
      return display.replaceAll(RegExp(r'\"'), '');
    }
  }
  return null;
}

String? _extractCompanyFromEmail(String fromAddr) {
  final emailMatch = RegExp(r'<([^>]+)>').firstMatch(fromAddr) ??
      RegExp(r'([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+)')
          .firstMatch(fromAddr);
  final email = emailMatch?.group(1);
  if (email == null || !email.contains('@')) {
    return null;
  }
  final domain = email.split('@').last;
  final pieces = domain.split('.');
  if (pieces.length < 2) {
    return null;
  }
  final company = pieces.first.replaceAll('-', ' ');
  return _titleCase(company);
}

bool _looksLikePersonName(String name) {
  final words = name.trim().split(RegExp(r'\s+'));
  if (words.length != 2) {
    return false;
  }
  final lower = words.map((word) => word.toLowerCase()).toList();
  const companyTokens = {
    'ai',
    'analytics',
    'company',
    'corp',
    'corporation',
    'health',
    'inc',
    'labs',
    'llc',
    'logistics',
    'ltd',
    'software',
    'solutions',
    'systems',
    'tech',
    'technologies',
    'group',
    'services',
  };
  if (lower.any(companyTokens.contains)) {
    return false;
  }
  return words.every((word) => word.length <= 12);
}

String _titleCase(String value) {
  return value
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) =>
          part[0].toUpperCase() + part.substring(1).toLowerCase())
      .join(' ');
}

class _ScoredUrl {
  final String url;
  final int score;

  const _ScoredUrl(this.url, this.score);
}
