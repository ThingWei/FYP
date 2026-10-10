import '../../../../core/validation/input_validation.dart';
import '../../../../core/validation/input_rules.dart';
import 'package:flutter/material.dart';

import '../../../../shared/mock_data/mock_data.dart';
import '../../../../shared/widgets/account_components.dart';
import '../../../../shared/widgets/renthub_components.dart';
import 'service_details_page.dart';

class ServiceResultsPage extends StatefulWidget {
  const ServiceResultsPage({
    super.key,
    required this.onOpenBookings,
    required this.onReturnHome,
  });

  final VoidCallback onOpenBookings;
  final VoidCallback onReturnHome;

  @override
  State<ServiceResultsPage> createState() => _ServiceResultsPageState();
}

class _ServiceResultsPageState extends State<ServiceResultsPage> {
  String _query = '';
  String _serviceType = 'All';
  bool _verifiedOnly = true;

  @override
  Widget build(BuildContext context) {
    final services = MockData.listings.where((listing) {
      if (!listing.isService) return false;
      final search = '${listing.title} ${listing.location}'.toLowerCase();
      if (_query.isNotEmpty && !search.contains(_query.toLowerCase())) {
        return false;
      }
      if (_serviceType != 'All') {
        final token = _serviceType == 'Photography' ? 'photo' : 'tutor';
        if (!listing.title.toLowerCase().contains(token)) return false;
      }
      if (_verifiedOnly && !listing.verified) return false;
      return true;
    }).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Services')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            TextFormField(
              onChanged: (value) => setState(() => _query = value.trim()),
              decoration: (const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search professional services',
              )).copyWith(counterText: '', errorMaxLines: 3),
              validator: InputRules.searchProfessionalServices.validate,
              inputFormatters: InputValidation.formatters(
                  InputRules.searchProfessionalServices, null),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              maxLength: InputRules.searchProfessionalServices.maxLength,
              maxLengthEnforcement: InputValidation.lengthEnforcement,
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final type in const ['All', 'Photography', 'Tutoring'])
                ChoiceChip(
                  label: Text(type),
                  selected: _serviceType == type,
                  onSelected: (_) => setState(() => _serviceType = type),
                ),
              FilterChip(
                  label: const Text('Verified Owners'),
                  selected: _verifiedOnly,
                  onSelected: (value) => setState(() => _verifiedOnly = value)),
            ]),
            const SizedBox(height: 16),
            Text('${services.length} service packages',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            if (services.isEmpty)
              const RentHubFeedbackState(
                kind: FeedbackKind.empty,
                title: 'No services found',
                message: 'Try a broader search or remove a filter.',
              ),
            for (final service in services) ...[
              ListingCard(
                listing: service,
                onTap: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ServiceDetailsPage(
                      service: service,
                      onOpenBookings: widget.onOpenBookings,
                      onReturnHome: widget.onReturnHome,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}
