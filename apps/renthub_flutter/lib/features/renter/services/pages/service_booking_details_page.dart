import 'package:flutter/material.dart';

import '../../../../shared/widgets/account_components.dart';
import '../../booking/booking_flow.dart';
import '../../shared/widgets/renter_flow_components.dart';
import '../models/service_draft.dart';
import 'service_booking_summary_page.dart';

class ServiceBookingPage extends StatefulWidget {
  const ServiceBookingPage({
    super.key,
    required this.draft,
    required this.onOpenBookings,
    required this.onReturnHome,
  });

  final ServiceDraft draft;
  final VoidCallback onOpenBookings;
  final VoidCallback onReturnHome;

  @override
  State<ServiceBookingPage> createState() => _ServiceBookingPageState();
}

class _ServiceBookingPageState extends State<ServiceBookingPage> {
  final formKey = GlobalKey<FormState>();
  final requirements = TextEditingController();

  @override
  void dispose() {
    requirements.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.draft,
        builder: (context, _) => Scaffold(
          appBar: AppBar(title: const Text('Service Requirements')),
          bottomNavigationBar: SafeArea(
            minimum: const EdgeInsets.all(16),
            child: RentHubActionButton(
              label: 'Review Booking Summary',
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                widget.draft.requirements = requirements.text.trim();
                Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ServiceSummaryPage(
                      draft: widget.draft,
                      onOpenBookings: widget.onOpenBookings,
                      onReturnHome: widget.onReturnHome,
                    ),
                  ),
                );
              },
            ),
          ),
          body: SafeArea(
            child: Form(
              key: formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  ServiceSummaryHeader(draft: widget.draft),
                  const SizedBox(height: 12),
                  RenterFlowCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Date & Time',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final value = await showDatePicker(
                                  context: context,
                                  initialDate: widget.draft.date,
                                  firstDate: DateTime(2026, 8, 16),
                                  lastDate: DateTime(2027),
                                );
                                if (value != null) {
                                  widget.draft.updateDate(value);
                                }
                              },
                              icon: const Icon(Icons.calendar_today),
                              label: Text(formatShortDate(widget.draft.date)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final value = await showTimePicker(
                                  context: context,
                                  initialTime: widget.draft.time,
                                );
                                if (value != null) {
                                  widget.draft.updateTime(value);
                                }
                              },
                              icon: const Icon(Icons.schedule),
                              label: Text(widget.draft.time.format(context)),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: requirements,
                          minLines: 3,
                          maxLines: 5,
                          decoration: const InputDecoration(
                            labelText: 'Event requirements',
                            hintText:
                                'Venue, event type, deliverables and accessibility needs',
                          ),
                          validator: (value) => (value?.trim().length ?? 0) < 10
                              ? 'Add at least 10 characters'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          initialValue: widget.draft.guests,
                          decoration: const InputDecoration(
                              labelText: 'Estimated guests'),
                          items: const [10, 25, 50, 100, 150]
                              .map((value) => DropdownMenuItem(
                                    value: value,
                                    child: Text('$value guests'),
                                  ))
                              .toList(),
                          onChanged: (value) =>
                              widget.draft.guests = value ?? 50,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
