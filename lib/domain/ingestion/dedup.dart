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
  if (incomingCompany.isEmpty || incomingRole.isEmpty) {
    return null;
  }

  Application? best;
  var bestScore = 0.0;
  for (final app in existing) {
    final companyScore = _similarity(incomingCompany, app.company);
    final roleScore = _similarity(incomingRole, app.role);
    final score = (companyScore * 0.6) + (roleScore * 0.4);
    if (score > bestScore) {
      bestScore = score;
      best = app;
    }
  }
  if (bestScore >= 0.65) {
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
  final intersection = tokensA.intersection(tokensB).length.toDouble();
  final union = tokensA.union(tokensB).length.toDouble();
  if (union == 0) {
    return 0.0;
  }
  return intersection / union;
}

Set<String> _tokenize(String text) {
  return text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\\s]'), ' ')
      .split(RegExp(r'\\s+'))
      .where((token) => token.isNotEmpty)
      .toSet();
}
