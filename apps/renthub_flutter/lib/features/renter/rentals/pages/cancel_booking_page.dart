import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/account_components.dart';
import '../../../../shared/widgets/renthub_components.dart';
import '../../shared/widgets/renter_flow_components.dart';

class CancellationPage extends StatefulWidget {
  const CancellationPage({super.key, required this.subject});
  final String subject;

  @override
  State<CancellationPage> createState() => _CancellationPageState();
}

class _CancellationPageState extends State<CancellationPage> {
  String reason = 'Change of plans';

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Cancel Booking')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              RenterFlowCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(widget.subject,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: reason,
                      decoration: const InputDecoration(
                          labelText: 'Cancellation reason'),
                      items: const [
                        'Change of plans',
                        'Dates no longer suitable',
                        'Found another option',
                        'Other',
                      ]
                          .map((value) => DropdownMenuItem(
                              value: value, child: Text(value)))
                          .toList(),
                      onChanged: (value) => reason = value ?? reason,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'A Pending request can be cancelled before Owner approval.',
                      style: TextStyle(color: AppColors.secondaryText),
                    ),
                    const SizedBox(height: 20),
                    RentHubActionButton(
                      label: 'Confirm Cancellation',
                      style: RentHubButtonStyle.destructive,
                      onPressed: () async {
                        final confirmed = await confirmAction(
                          context,
                          title: 'Cancel this request?',
                          message: 'Reason: $reason',
                          action: 'Cancel Request',
                          destructive: true,
                        );
                        if (confirmed && context.mounted) {
                          Navigator.pop(context);
                          showMockSuccess(context, 'Booking request cancelled');
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}
