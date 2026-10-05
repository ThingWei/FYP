import 'package:flutter/material.dart';

import '../../../shared/widgets/account_components.dart';

class KycVerificationStatusPage extends StatelessWidget {
  const KycVerificationStatusPage({super.key, required this.onReturn});

  final VoidCallback onReturn;

  @override
  Widget build(BuildContext context) => AccountCard(
        child: RentHubFeedbackState(
          kind: FeedbackKind.empty,
          title: 'UI Preview Complete',
          message:
              'No verification decision was made. Live submissions require AI-assisted checks and final administrator approval.',
          actionLabel: 'Return to Profile',
          onAction: onReturn,
        ),
      );
}
