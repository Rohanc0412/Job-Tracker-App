enum ApplicationStatus {
  applied,
  assessment,
  interview,
  offer,
  underReview,
  received,
  rejected,
}

extension ApplicationStatusLabels on ApplicationStatus {
  String get label {
    switch (this) {
      case ApplicationStatus.applied:
        return 'Applied';
      case ApplicationStatus.assessment:
        return 'Assessment';
      case ApplicationStatus.interview:
        return 'Interview';
      case ApplicationStatus.offer:
        return 'Offer';
      case ApplicationStatus.underReview:
        return 'Under Review';
      case ApplicationStatus.received:
        return 'Received';
      case ApplicationStatus.rejected:
        return 'Rejected';
    }
  }
}
