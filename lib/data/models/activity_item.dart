enum ActivityKind {
  update,
  interview,
  offer,
  rejection,
}

class ActivityItem {
  final String title;
  final String detail;
  final DateTime timestamp;
  final ActivityKind kind;
  final String? applicationId;
  final String? timezone;
  final String? rawBodyText;
  final String? rawBodyPath;

  const ActivityItem({
    required this.title,
    required this.detail,
    required this.timestamp,
    required this.kind,
    this.applicationId,
    this.timezone,
    this.rawBodyText,
    this.rawBodyPath,
  });
}
