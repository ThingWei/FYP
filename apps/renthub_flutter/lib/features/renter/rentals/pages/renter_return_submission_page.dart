import 'package:flutter/material.dart';

import '../../../../shared/models/domain_models.dart';
import '../../../../shared/widgets/account_components.dart';
import '../../../../shared/widgets/renthub_components.dart';
import '../../shared/widgets/renter_flow_components.dart';
import 'rental_completed_page.dart';

class ReturnSubmissionPage extends StatefulWidget {
  const ReturnSubmissionPage({super.key, required this.listing});
  final Listing listing;

  @override
  State<ReturnSubmissionPage> createState() => _ReturnSubmissionPageState();
}

class _ReturnSubmissionPageState extends State<ReturnSubmissionPage> {
  bool conditionConfirmed = false;

  @override
  Widget build(BuildContext context) => RenterSimpleFlowPage(
        title: 'Return & Verification',
        icon: Icons.assignment_return_outlined,
        heading: widget.listing.title,
        status: 'Evidence required',
        children: [
          const RenterInfoSection(
            title: 'Return evidence',
            text:
                'Add clear front, back and accessory photos. Prototype placeholders are stored locally only.',
          ),
          OutlinedButton.icon(
            onPressed: () =>
                showMockSuccess(context, '3 evidence placeholders added'),
            icon: const Icon(Icons.add_a_photo_outlined),
            label: const Text('Add Return Photos'),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: conditionConfirmed,
            onChanged: (value) =>
                setState(() => conditionConfirmed = value ?? false),
            title: const Text('Item condition and accessories are documented'),
          ),
          RentHubActionButton(
            label: 'Submit Return for Owner Verification',
            onPressed: conditionConfirmed
                ? () => Navigator.pushReplacement<void, void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RentalCompletedPage(
                          listing: widget.listing,
                        ),
                      ),
                    )
                : null,
          ),
        ],
      );
}
