import 'package:flutter/material.dart';

import '../../../../shared/models/domain_models.dart';
import '../../../../shared/widgets/account_components.dart';
import '../../../../shared/widgets/renthub_components.dart';
import '../../booking/booking_flow.dart';
import '../../shared/widgets/renter_flow_components.dart';

class ExtensionRequestPage extends StatefulWidget {
  const ExtensionRequestPage({super.key, required this.listing});
  final Listing listing;

  @override
  State<ExtensionRequestPage> createState() => _ExtensionRequestPageState();
}

class _ExtensionRequestPageState extends State<ExtensionRequestPage> {
  int days = 1;

  @override
  Widget build(BuildContext context) => RenterSimpleFlowPage(
        title: 'Request Extension',
        icon: Icons.more_time,
        heading: widget.listing.title,
        status: 'Owner approval required',
        children: [
          DropdownButtonFormField<int>(
            initialValue: days,
            decoration: const InputDecoration(labelText: 'Extra rental days'),
            items: const [1, 2, 3, 5, 7]
                .map((value) => DropdownMenuItem(
                      value: value,
                      child: Text('$value day${value == 1 ? '' : 's'}'),
                    ))
                .toList(),
            onChanged: (value) => setState(() => days = value ?? 1),
          ),
          const SizedBox(height: 12),
          RenterFactRow('Additional subtotal',
              formatMoney(widget.listing.dailyPrice * days)),
          const SizedBox(height: 16),
          RentHubActionButton(
            label: 'Send Extension Request',
            onPressed: () {
              showMockSuccess(context, 'Extension request sent to Owner');
              Navigator.pop(context);
            },
          ),
        ],
      );
}
