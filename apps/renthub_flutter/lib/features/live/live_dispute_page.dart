import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/domain_models.dart';
import '../../shared/widgets/renthub_components.dart';
import '../renter/booking/booking_flow.dart' show formatMoney;
import 'live_renthub_controller.dart';

class LiveDisputePage extends StatefulWidget {
  const LiveDisputePage({
    super.key,
    required this.rental,
    required this.owner,
  });

  final Rental rental;
  final bool owner;

  @override
  State<LiveDisputePage> createState() => _LiveDisputePageState();
}

class _LiveDisputePageState extends State<LiveDisputePage> {
  final formKey = GlobalKey<FormState>();
  final summary = TextEditingController();
  final description = TextEditingController();
  final response = TextEditingController();
  late String category;
  bool attachEvidence = false;

  List<String> get categories => widget.rental.listingType == 'physical'
      ? const [
          'damaged_item',
          'return_condition',
          'missing_item',
          'deposit_deduction',
          'late_return',
          'communication',
          'other',
        ]
      : const [
          'service_quality',
          'non_delivery',
          'scope_mismatch',
          'cancellation',
          'communication',
          'other',
        ];

  @override
  void initState() {
    super.initState();
    category = categories.first;
  }

  @override
  void dispose() {
    summary.dispose();
    description.dispose();
    response.dispose();
    super.dispose();
  }

  String label(String value) => value
      .split('_')
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');

  Future<void> create() async {
    if (!formKey.currentState!.validate()) return;
    try {
      await context.read<LiveRentHubController>().createDispute(
            rental: widget.rental,
            category: category,
            summary: summary.text,
            description: description.text,
            evidence: attachEvidence
                ? ['local://disputes/flutter-evidence.jpg']
                : const [],
          );
      if (mounted) showMockSuccess(context, 'Dispute submitted for review');
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(exception.toString())));
      }
    }
  }

  Future<void> respond(Dispute dispute) async {
    if (response.text.trim().length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter at least 5 characters.')),
      );
      return;
    }
    try {
      await context.read<LiveRentHubController>().respondToDispute(
            dispute,
            response.text,
            evidence: attachEvidence
                ? ['local://disputes/response-evidence.jpg']
                : const [],
          );
      response.clear();
      if (mounted) showMockSuccess(context, 'Response added to the case');
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(exception.toString())));
      }
    }
  }

  Future<void> submitClaim(Dispute dispute) async {
    final amount = TextEditingController();
    final details = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Submit damage-waiver claim'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Amount requested (RM)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: details,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Damage and repair details',
                ),
              ),
              const SizedBox(height: 12),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'A repair quotation placeholder will be attached. This does not submit a claim to a real insurer.',
                  style: TextStyle(color: AppColors.secondaryText),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Submit Claim'),
          ),
        ],
      ),
    );
    final parsed = double.tryParse(amount.text);
    if (accepted == true &&
        parsed != null &&
        parsed > 0 &&
        details.text.trim().length >= 20 &&
        mounted) {
      try {
        await context.read<LiveRentHubController>().submitClaim(
          dispute: dispute,
          description: details.text,
          amount: parsed,
          evidence: const ['local://claims/repair-quotation.pdf'],
        );
        if (mounted) showMockSuccess(context, 'Insurance claim submitted');
      } catch (exception) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(exception.toString())));
        }
      }
    } else if (accepted == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid amount and at least 20 characters.'),
        ),
      );
    }
    amount.dispose();
    details.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LiveRentHubController>();
    final dispute = controller.disputeForRental(widget.rental.id);
    return Scaffold(
      appBar: AppBar(
        title: Text(dispute == null ? 'Raise a Dispute' : 'Dispute Tracking'),
      ),
      body: SafeArea(
        child: dispute == null
            ? _createForm(controller.loading)
            : _details(dispute, controller.claimForRental(widget.rental.id)),
      ),
    );
  }

  Widget _createForm(bool loading) => Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              widget.rental.listingType == 'physical'
                  ? 'Physical-item rental issue'
                  : 'Service booking issue',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              'Rental ${widget.rental.id}',
              style: const TextStyle(color: AppColors.secondaryText),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              initialValue: category,
              decoration: const InputDecoration(labelText: 'Issue category'),
              items: categories
                  .map((item) =>
                      DropdownMenuItem(value: item, child: Text(label(item))))
                  .toList(),
              onChanged: (value) => setState(() => category = value!),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: summary,
              decoration: const InputDecoration(labelText: 'Short summary'),
              validator: (value) => (value?.trim().length ?? 0) < 5
                  ? 'Enter at least 5 characters'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: description,
              minLines: 5,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'What happened?',
                alignLabelWithHint: true,
              ),
              validator: (value) => (value?.trim().length ?? 0) < 20
                  ? 'Enter at least 20 characters'
                  : null,
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: attachEvidence,
              onChanged: (value) =>
                  setState(() => attachEvidence = value ?? false),
              title: const Text('Attach evidence placeholder'),
              subtitle:
                  const Text('Photo/document upload is simulated locally.'),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: loading ? null : create,
              icon: const Icon(Icons.gavel_outlined),
              label: const Text('Submit Dispute'),
            ),
          ],
        ),
      );

  Widget _details(Dispute dispute, InsuranceClaim? claim) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          dispute.reason,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      StatusBadge(dispute.status.replaceAll('_', ' ')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('${label(dispute.category)} • ${dispute.id}'),
                  const SizedBox(height: 8),
                  Text(dispute.description),
                  if (dispute.adminNote.isNotEmpty) ...[
                    const Divider(height: 24),
                    Text(
                      'Administrator note: ${dispute.adminNote}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                  if (dispute.outcome != null) ...[
                    const Divider(height: 24),
                    Text('Decision: ${label(dispute.outcome!)}'),
                    Text(
                      'Simulated allocation — Renter ${formatMoney(dispute.renterAmount)}, Owner ${formatMoney(dispute.ownerAmount)}',
                    ),
                    if (dispute.mockBlockchainReference != null)
                      Text(
                        dispute.mockBlockchainReference!,
                        style: const TextStyle(color: AppColors.secondaryText),
                      ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Case responses',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (dispute.responses.isEmpty)
            const Text(
              'No participant responses yet.',
              style: TextStyle(color: AppColors.secondaryText),
            ),
          for (final item in dispute.responses)
            Card(
              child: ListTile(
                leading: const Icon(Icons.chat_bubble_outline),
                title: Text(label(item.role)),
                subtitle: Text(item.text),
                trailing:
                    item.evidence.isEmpty ? null : const Icon(Icons.attachment),
              ),
            ),
          if (!dispute.closed) ...[
            const SizedBox(height: 16),
            TextField(
              controller: response,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Add information or a response',
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => respond(dispute),
              icon: const Icon(Icons.send_outlined),
              label: const Text('Add Response'),
            ),
          ],
          if (widget.rental.listingType == 'physical' &&
              (widget.owner || claim != null)) ...[
            const SizedBox(height: 20),
            Text('Damage-waiver claim',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (widget.owner && claim == null && !dispute.closed)
              FilledButton.tonalIcon(
                onPressed: () => submitClaim(dispute),
                icon: const Icon(Icons.health_and_safety_outlined),
                label: const Text('Submit Insurance Claim'),
              )
            else if (claim != null)
              Card(
                child: ListTile(
                  title: Text(formatMoney(claim.amountRequested)),
                  subtitle: Text(
                    claim.decisionReason.isEmpty
                        ? claim.description
                        : claim.decisionReason,
                  ),
                  trailing: StatusBadge(claim.status),
                ),
              ),
          ],
        ],
      );
}
