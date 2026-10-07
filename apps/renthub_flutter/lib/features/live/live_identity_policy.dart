import '../../shared/models/domain_models.dart';

bool marketplaceIdentityApproved(User? user) => user?.mykadStatus == 'approved';

String marketplaceIdentityMessage(String status, String action) {
  final explanation = switch (status) {
    'pending' =>
      'Your MyKad is awaiting administrator review. Uploading it is not yet approval.',
    'rejected' =>
      'Your MyKad verification was rejected. Review the reason and submit new evidence.',
    'resubmission_required' =>
      'Your MyKad needs resubmission. Review the reason and submit new evidence.',
    'expired' =>
      'Your identity verification has expired. Complete a new review.',
    _ =>
      'Complete MyKad identity verification and wait for administrator approval.',
  };
  return '$explanation\n\nApproval is required before you can $action. You can still browse, message and save listing drafts.';
}
