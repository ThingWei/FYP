class AdminRecordPageState {
  List<Map<String, dynamic>> items = [];
  int page = 1, limit = 20, total = 0, generation = 0, revision = -1;
  String search = '', status = 'all', documentType = 'all';
  bool loading = false, loaded = false;
  Object? error;
}

const adminRecordTitles = <String, String>{
  'users': 'Users',
  'verification': 'Verification records',
  'listings': 'Listings',
  'bookings': 'Bookings',
  'rentals': 'Rentals and services',
  'transactions': 'Transactions',
  'disputes': 'Disputes',
  'claims': 'Damage-waiver claims',
  'reports': 'Safety reports',
  'message-reports': 'Message reports',
  'reviews': 'Reviews',
  'audit-logs': 'Activity history',
  'generated-reports': 'Downloaded reports',
  'report-schedules': 'Report schedules',
  'referrals': 'Referrals',
  'reward-history': 'Points history',
  'pricing-references': 'Rental-price references',
};

const adminStatusFilters = <String, List<String>>{
  'verification': ['pending', 'approved', 'rejected', 'resubmission_required'],
  'users': ['active', 'suspended', 'banned', 'deactivated'],
  'listings': ['draft', 'pending_review', 'active', 'inactive', 'rejected'],
  'bookings': [
    'pending',
    'approved',
    'active',
    'completed',
    'cancelled',
    'rejected',
    'expired',
    'disputed'
  ],
  'rentals': [
    'scheduled',
    'active',
    'overdue',
    'return_submitted',
    'completion_pending',
    'completed',
    'disputed',
    'cancelled'
  ],
  'transactions': ['pending', 'authorized', 'succeeded', 'failed', 'voided'],
  'disputes': [
    'open',
    'awaiting_response',
    'under_review',
    'more_evidence_required',
    'escalated',
    'resolved',
    'dismissed'
  ],
  'claims': ['pending', 'approved', 'rejected'],
  'reports': ['open', 'resolved', 'dismissed'],
  'message-reports': ['open', 'resolved', 'dismissed'],
  'reviews': ['published', 'hidden'],
};

String adminLabel(Object? value) {
  final key = '$value';
  const labels = {
    'undetermined': 'Not determined',
    'none': 'Neither participant',
    'both': 'Both participants',
    'pending_review': 'Awaiting review',
    'resubmission_required': 'New documents requested',
    'unverified': 'Not verified',
    'verified': 'Verified',
    'approved': 'Approved',
    'pending': 'Pending',
    'rejected': 'Rejected',
    'active': 'Active',
    'inactive': 'Inactive',
    'draft': 'Draft',
    'cancelled': 'Cancelled',
    'completed': 'Completed',
    'expired': 'Expired',
    'published': 'Visible',
    'hidden': 'Hidden',
    'flagged': 'Flagged',
    'open': 'Open',
    'resolved': 'Resolved',
    'dismissed': 'Dismissed',
    'under_review': 'Being reviewed',
    'awaiting_response': 'Awaiting a reply',
    'more_evidence_required': 'More evidence requested',
    'pending_funding': 'Awaiting funding',
    'escalated': 'Escalated',
    'overdue': 'Overdue',
    'return_submitted': 'Return awaiting review',
    'completion_pending': 'Completion awaiting review',
    'voided': 'Payment released',
    'card': 'Demo card',
    'fpx': 'Demo FPX',
    'wallet': 'Demo wallet',
    'system': 'RentHub',
    'owner_settlement': 'Owner payment',
    'platform_retention': 'Platform fee retained',
    'deposit_deduction': 'Deposit deduction',
    'dispute_release': 'Dispute settlement',
    'unpaid': 'Awaiting payment',
    'authorized': 'Payment authorized',
    'captured': 'Payment received',
    'succeeded': 'Successful',
    'failed': 'Unsuccessful',
    'refunded': 'Refunded',
    'authorization': 'Payment authorization',
    'capture': 'Payment received',
    'refund': 'Refund',
    'deposit_release': 'Deposit returned',
    'owner_payout': 'Owner payment',
    'suspended': 'Suspended',
    'banned': 'Banned',
    'deactivated': 'Deactivated',
    'renter': 'Renter',
    'owner': 'Owner',
    'admin': 'Administrator',
    'physical': 'Physical item',
    'service': 'Service',
    'mykad': 'MyKad',
    'passport': 'Passport',
    'driving_licence': 'Driving licence',
    'pickup': 'Pickup',
    'owner_delivery': 'Owner delivery',
    'online': 'Online',
    'owner_location': 'Owner location',
    'renter_location': 'Renter location',
    'flexible': 'Flexible venue',
    'body_only': 'Camera body only',
    'with_lens': 'Camera with lens',
    'item_only': 'Item only',
    'equipment_set': 'Equipment set',
    'platform_summary': 'Platform summary',
    'payments': 'Payments',
    'bookings': 'Bookings',
    'users': 'Users',
    'listings': 'Listings',
    'disputes': 'Disputes',
    'daily': 'Daily',
    'weekly': 'Weekly',
    'monthly': 'Monthly',
    'manual': 'On request',
    'scheduled': 'Scheduled',
    'bonus': 'Bonus points',
    'referral_reward': 'Referral reward',
    'referral_welcome': 'Welcome reward',
    'redemption': 'Points used',
    'rewarded': 'Reward given',
    'rental_completed': 'Completed item rental',
    'service_completed': 'Completed service',
    'not_applicable': 'Not applicable',
    'release_to_renter': 'Return held funds to renter',
    'release_to_owner': 'Pay held funds to Owner',
    'split': 'Divide held funds',
    'damaged_item': 'Item damage',
    'return_condition': 'Return condition',
    'missing_item': 'Missing item',
    'late_return': 'Late return',
    'service_quality': 'Service quality',
    'non_delivery': 'Service not delivered',
    'scope_mismatch': 'Service differed from agreement',
    'communication': 'Communication',
    'cancellation': 'Cancellation',
    'misleading': 'Misleading information',
    'prohibited': 'Prohibited content',
    'scam': 'Suspected scam',
    'harassment': 'Harassment',
    'inappropriate': 'Inappropriate content',
    'spam': 'Spam',
    'other': 'Other concern',
    'moderation_report': 'Safety report',
    'message_report': 'Message report',
    'platform_settings': 'Platform settings',
    'user': 'User',
    'listing': 'Listing',
    'review': 'Review',
    'booking': 'Booking',
    'rental': 'Rental',
  };
  if (value == null || key.isEmpty || key == 'null') return 'Not available';
  if (value is bool) return value ? 'Yes' : 'No';
  return labels[key] ?? key;
}

String adminDate(Object? value, {bool calendar = false}) {
  if (value == null || '$value'.isEmpty) return 'Not available';
  final text = value.toString();
  final date = value is DateTime ? value : DateTime.tryParse(text);
  if (date == null) return 'Not available';
  final original =
      RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2}))?)?')
          .firstMatch(text);
  if (original == null) return 'Not available';
  final checked = DateTime.utc(int.parse(original[1]!), int.parse(original[2]!),
      int.parse(original[3]!));
  if (checked.month != int.parse(original[2]!) ||
      checked.day != int.parse(original[3]!) ||
      int.parse(original[4] ?? '0') > 23 ||
      int.parse(original[5] ?? '0') > 59 ||
      int.parse(original[6] ?? '0') > 59) {
    return 'Not available';
  }
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  final onlyDate = calendar || RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text);
  DateTime shown;
  if (onlyDate) {
    final parts = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(text);
    if (parts == null) return 'Not available';
    shown = DateTime.utc(
        int.parse(parts[1]!), int.parse(parts[2]!), int.parse(parts[3]!));
    if (shown.month != int.parse(parts[2]!) ||
        shown.day != int.parse(parts[3]!)) {
      return 'Not available';
    }
  } else {
    final parsed = value is DateTime
        ? value.toUtc()
        : DateTime.tryParse(RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(text)
            ? text
            : '${text}Z');
    if (parsed == null) return 'Not available';
    shown = parsed.toUtc().add(const Duration(hours: 8));
  }
  final label = '${shown.day} ${months[shown.month - 1]} ${shown.year}';
  if (onlyDate) return label;
  return '$label, ${shown.hour % 12 == 0 ? 12 : shown.hour % 12}:${shown.minute.toString().padLeft(2, '0')} ${shown.hour < 12 ? 'am' : 'pm'}';
}

String adminMoney(Object? value) => value is num && value.isFinite
    ? 'RM ${value.toStringAsFixed(2)}'
    : 'Not available';
String adminAccount(Map row, String field) => row['accountNames'] is Map
    ? adminLabel(row['accountNames'][row[field]])
    : 'Not available';
String adminRecordName(String type, Map row) => switch (type) {
      'users' || 'verification' => adminLabel(row['displayName']),
      'listings' => adminLabel(row['title']),
      'bookings' || 'rentals' => adminLabel(row['listingTitle']),
      'transactions' => adminLabel(row['type']),
      'reports' => adminLabel(row['targetLabel']),
      'message-reports' => 'Reported message',
      'reviews' =>
        '${adminLabel(row['authorName'])} → ${adminLabel(row['subjectName'])}',
      'disputes' ||
      'claims' =>
        adminLabel(row['listingTitle'] ?? row['reason'] ?? row['description']),
      'generated-reports' => adminLabel(row['fileName']),
      'report-schedules' => adminLabel(row['name']),
      'referrals' => adminLabel(row['referralCode']),
      'reward-history' => adminLabel(row['description']),
      'pricing-references' =>
        '${row['brand'] ?? ''} ${row['productModel'] ?? ''}'.trim(),
      'audit-logs' => adminAuditAction(row['action']),
      _ => 'Record details',
    };
String adminAuditAction(Object? action) =>
    const {
      'listing.moderated': 'Listing reviewed',
      'user.verification_decided': 'Identity review completed',
      'user.status_changed': 'Account status updated',
      'review.moderated': 'Review visibility updated',
      'report.resolved': 'Safety report reviewed',
      'dispute.resolved': 'Dispute decision recorded',
      'claim.decided': 'Claim reviewed',
      'payment.refunded': 'Refund recorded',
      'pricing_source.synced': 'Rental prices updated',
      'pricing_source.sync_failed': 'Rental-price update unsuccessful',
      'pricing_source.enabled': 'Price updates switched on',
      'pricing_source.disabled': 'Price updates switched off',
      'pricing_source.sync_requested': 'Price update requested',
      'pricing_reference.deactivated': 'Price reference removed from use',
      'pricing_references.imported': 'Price references imported',
      'lifecycle.manual_run': 'Scheduled tasks run',
    }[action] ??
    'Account or platform activity';

String adminRecordStatus(String type, Map row) => switch (type) {
      'users' => adminLabel(row['accountStatus']),
      'verification' => adminVerificationStatus(row),
      'pricing-references' ||
      'report-schedules' =>
        row[type == 'report-schedules' ? 'enabled' : 'active'] == true
            ? 'Active'
            : 'Switched off',
      'reviews' =>
        row['flag'] is Map && '${row['flag']['reason'] ?? ''}'.isNotEmpty
            ? 'Flagged'
            : adminLabel(row['status']),
      _ => row['status'] == null ? 'Recorded' : adminLabel(row['status']),
    };

String adminVerificationStatus(Map row) {
  final summaries =
      (row['verificationSummary'] as List? ?? const []).whereType<Map>();
  for (final status in [
    'pending',
    'resubmission_required',
    'rejected',
    'approved'
  ]) {
    if (summaries.any((entry) => entry['status'] == status)) {
      return status == 'pending' ? 'Awaiting review' : adminLabel(status);
    }
  }
  if (row['drivingEligibility'] is Map &&
      row['drivingEligibility']['status'] == 'pending') {
    return 'Awaiting review';
  }
  return adminLabel(
      row['verification'] is Map ? row['verification']['status'] : null);
}
