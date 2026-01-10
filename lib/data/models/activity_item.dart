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

  const ActivityItem({
    required this.title,
    required this.detail,
    required this.timestamp,
    required this.kind,
  });
}
