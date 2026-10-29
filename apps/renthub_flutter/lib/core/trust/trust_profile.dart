class TrustCohort {
  const TrustCohort(
      {this.status = 'insufficient_history',
      this.score,
      this.completedRentals = 0,
      this.distinctPartners = 0,
      this.reviewCount = 0,
      this.averageRating,
      this.timelyRentals = 0,
      this.measuredTimeliness = 0,
      this.confirmedIssues = 0});
  final String status;
  final int? score;
  final int completedRentals,
      distinctPartners,
      reviewCount,
      timelyRentals,
      measuredTimeliness,
      confirmedIssues;
  final double? averageRating;
  bool get established => status == 'established' && score != null;
  String get label => established
      ? '$score / 100'
      : status == 'unavailable'
          ? 'Score unavailable'
          : 'Not enough rental history';
  factory TrustCohort.fromJson(dynamic raw) {
    if (raw is! Map) return const TrustCohort();
    int count(String key) => raw[key] is num && (raw[key] as num).isFinite
        ? (raw[key] as num).toInt().clamp(0, 1000000)
        : 0;
    final score = raw['score'];
    return TrustCohort(
        status: raw['status'] is String
            ? raw['status'] as String
            : 'insufficient_history',
        score: score is num && score.isFinite && score >= 0 && score <= 100
            ? score.round()
            : null,
        completedRentals: count('completedRentals'),
        distinctPartners: count('distinctPartners'),
        reviewCount: count('reviewCount'),
        averageRating: raw['averageRating'] is num &&
                (raw['averageRating'] as num).isFinite
            ? (raw['averageRating'] as num).toDouble()
            : null,
        timelyRentals: count('timelyRentals'),
        measuredTimeliness: count('measuredTimeliness'),
        confirmedIssues: count('confirmedIssues'));
  }
}

class TrustRoleSummary {
  const TrustRoleSummary(
      {this.marketplace = const TrustCohort(),
      this.demo = const TrustCohort()});
  final TrustCohort marketplace, demo;
  factory TrustRoleSummary.fromJson(dynamic raw) => raw is Map
      ? TrustRoleSummary(
          marketplace: TrustCohort.fromJson(raw['marketplace']),
          demo: TrustCohort.fromJson(raw['demo']))
      : const TrustRoleSummary();
}

class TrustProfile {
  const TrustProfile(
      {this.supported = false,
      this.overall = const TrustRoleSummary(),
      this.owner = const TrustRoleSummary(),
      this.renter = const TrustRoleSummary()});
  final bool supported;
  final TrustRoleSummary overall, owner, renter;
  TrustRoleSummary forRole(String role) => role == 'owner'
      ? owner
      : role == 'renter'
          ? renter
          : overall;
  factory TrustProfile.fromJson(dynamic raw) =>
      raw is Map && raw['version'] == 'renthub-trust-v1'
          ? TrustProfile(
              supported: true,
              overall: TrustRoleSummary.fromJson(raw['overall']),
              owner: TrustRoleSummary.fromJson(raw['owner']),
              renter: TrustRoleSummary.fromJson(raw['renter']))
          : const TrustProfile();
}
