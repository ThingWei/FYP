import 'package:flutter/material.dart';

import '../../../shared/widgets/account_components.dart';

class KycVerificationStatusPage extends StatelessWidget {
  const KycVerificationStatusPage({super.key, required this.onReturn});

  final VoidCallback onReturn;

  @override
  Widget build(BuildContext context) => AccountCard(
        child: RentHubFeedbackState(
          kind: FeedbackKind.success,
          title: 'Verification Successful',
          message: 'Your identity is verified for this prototype.',
          actionLabel: 'Return to Profile',
          onAction: onReturn,
        ),
      );
}
