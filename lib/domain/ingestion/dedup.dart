import '../../data/models/application.dart';
import 'parser_rules.dart';

class ExtractedApplicationData {
  final String? jobId;
  final String? portalUrl;
  final String? company;
  final String? role;

  const ExtractedApplicationData({
    this.jobId,
    this.portalUrl,
    this.company,
    this.role,
  });
}

Application? matchApplication(
  List<Application> existing,
  ExtractedApplicationData incoming,
) {
  if (incoming.jobId != null) {
    for (final app in existing) {
      if (app.jobId != null && app.jobId == incoming.jobId) {
        return app;
      }
    }
  }

  if (incoming.portalUrl != null) {
    final incomingUrl = sanitizeUrl(incoming.portalUrl!);
    for (final app in existing) {
      if (app.portalUrl != null &&
          sanitizeUrl(app.portalUrl!) == incomingUrl) {
        return app;
      }
    }
  }

  final incomingCompany = incoming.company ?? '';
  final incomingRole = incoming.role ?? '';
  // Require both company and role to be non-empty and meaningful (at least 3 chars)
  if (incomingCompany.length < 3 || incomingRole.length < 3) {
    return null;
  }

  Application? best;
  var bestScore = 0.0;
  for (final app in existing) {
    // Skip applications with short/generic company or role
    if (app.company.length < 3 || app.role.length < 3) {
      continue;
    }
    final companyScore = _similarity(incomingCompany, app.company);
    final roleScore = _similarity(incomingRole, app.role);
    final score = (companyScore * 0.6) + (roleScore * 0.4);
    if (score > bestScore) {
      bestScore = score;
      best = app;
    }
  }
  // Require high similarity (0.85) to prevent false matches on generic names
  if (bestScore >= 0.85) {
    return best;
  }
  return null;
}

double _similarity(String a, String b) {
  final tokensA = _tokenize(a);
  final tokensB = _tokenize(b);
  if (tokensA.isEmpty || tokensB.isEmpty) {
    return 0.0;
  }
  // Require at least 2 tokens in the union to avoid single-word false matches
  final union = tokensA.union(tokensB);
  if (union.length < 2) {
    // Single token match - only count as match if strings are nearly identical
    if (a.toLowerCase().trim() == b.toLowerCase().trim()) {
      return 1.0;
    }
    return 0.0;
  }
  final intersection = tokensA.intersection(tokensB).length.toDouble();
  return intersection / union.length.toDouble();
}

Set<String> _tokenize(String text) {
  return text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\\s]'), ' ')
      .split(RegExp(r'\\s+'))
      .where((token) => token.isNotEmpty)
      .toSet();
}
