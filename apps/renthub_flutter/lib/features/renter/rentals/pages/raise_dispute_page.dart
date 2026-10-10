import '../../../../core/validation/input_validation.dart';
import '../../../../core/validation/input_rules.dart';
import 'package:flutter/material.dart';

import '../../../../shared/widgets/account_components.dart';
import '../../../../shared/widgets/renthub_components.dart';
import '../../shared/widgets/renter_flow_components.dart';
import 'dispute_tracking_page.dart';

class DisputeSubmissionPage extends StatefulWidget {
  const DisputeSubmissionPage({
    super.key,
    required this.subject,
    this.service = false,
  });

  final String subject;
  final bool service;

  @override
  State<DisputeSubmissionPage> createState() => _DisputeSubmissionPageState();
}

class _DisputeSubmissionPageState extends State<DisputeSubmissionPage> {
  final details = TextEditingController();
  final formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Raise a Dispute')),
        body: SafeArea(
          child: Form(
            key: formKey,
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
                        initialValue: widget.service
                            ? 'Service not delivered as agreed'
                            : 'Item condition issue',
                        decoration:
                            const InputDecoration(labelText: 'Issue type'),
                        items: [
                          if (!widget.service) 'Item condition issue',
                          if (!widget.service) 'Deposit or return issue',
                          if (widget.service) 'Service not delivered as agreed',
                          'Communication issue',
                          'Other',
                        ]
                            .map((value) => DropdownMenuItem(
                                value: value, child: Text(value)))
                            .toList(),
                        onChanged: (_) {},
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: details,
                        minLines: 4,
                        maxLines: 6,
                        decoration: (const InputDecoration(
                          labelText: 'Describe what happened',
                        )).copyWith(counterText: '', errorMaxLines: 3),
                        validator: InputValidation.compose(
                            InputRules.describeWhatHappened.validate,
                            (value) => (value?.trim().length ?? 0) < 15
                                ? 'Add at least 15 characters'
                                : null),
                        inputFormatters: InputValidation.formatters(
                            InputRules.describeWhatHappened, details),
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        maxLength: InputRules.describeWhatHappened.maxLength,
                        maxLengthEnforcement: InputValidation.lengthEnforcement,
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => showMockSuccess(
                            context, 'Evidence placeholders added'),
                        icon: const Icon(Icons.attach_file),
                        label: const Text('Add Evidence'),
                      ),
                      const SizedBox(height: 20),
                      RentHubActionButton(
                        label: 'Submit Dispute',
                        style: RentHubButtonStyle.destructive,
                        onPressed: () {
                          if (!formKey.currentState!.validate()) return;
                          Navigator.pushReplacement<void, void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DisputeTrackingPage(
                                subject: widget.subject,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
