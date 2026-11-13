import '../../shared/widgets/renthub_dialog.dart';
import '../../core/booking/dispute_eligibility.dart';
import '../../core/network/api_client.dart';
import 'live_dispute_progress.dart';
import 'live_rental_progress.dart';
import '../../core/network/user_facing_error.dart';
import '../../core/validation/input_validation.dart';
import '../../core/validation/input_rules.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/domain_models.dart';
import '../../shared/widgets/renthub_components.dart';
import '../renter/booking/booking_flow.dart' show formatMoney;
import 'live_renthub_controller.dart';
import 'live_photo_widgets.dart';

class LiveDisputePage extends StatefulWidget {
  const LiveDisputePage({
    super.key,
    required this.rental,
    required this.owner,
    this.initialCategory,
  });

  final Rental rental;
  final bool owner;
  final String? initialCategory;

  @override
  State<LiveDisputePage> createState() => _LiveDisputePageState();
}

class _LiveDisputePageState extends State<LiveDisputePage> {
  final formKey = GlobalKey<FormState>();
  final responseFormKey = GlobalKey<FormState>();
  final summary = TextEditingController();
  final description = TextEditingController();
  final response = TextEditingController();
  late String category;
  final List<String> evidenceRefs = [];
  bool refreshing = true, checked = false, closedByServer = false;
  String? refreshError;
  int refreshGeneration = 0;

  Future<void> pickEvidence() async {
    try {
      final reference = await pickAndPreviewUpload(
        context,
        purpose: 'dispute_evidence',
        allowPdf: true,
      );
      if (reference != null && mounted) {
        setState(() => evidenceRefs.add(reference));
      }
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(exception))));
      }
    }
  }

  Future<void> removeEvidence(int index) async {
    final reference = evidenceRefs[index];
    try {
      await context.read<LiveRentHubController>().deleteUpload(reference);
      if (mounted) setState(() => evidenceRefs.remove(reference));
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(exception))));
      }
    }
  }

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
    category = categories.contains(widget.initialCategory)
        ? widget.initialCategory!
        : categories.first;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Historical case access must not depend on a new-case eligibility check.
      if (context
              .read<LiveRentHubController>()
              .disputeForRental(widget.rental.id) !=
          null) {
        setState(() {
          refreshing = false;
          checked = true;
        });
      } else {
        refreshEligibility();
      }
    });
  }

  Future<void> refreshEligibility() async {
    final generation = ++refreshGeneration;
    final id = widget.rental.id;
    setState(() {
      refreshing = true;
      refreshError = null;
    });
    try {
      await context
          .read<LiveRentHubController>()
          .refreshDisputeEligibility(widget.rental);
      if (mounted &&
          generation == refreshGeneration &&
          id == widget.rental.id) {
        setState(() => checked = true);
      }
    } catch (exception) {
      if (mounted &&
          generation == refreshGeneration &&
          id == widget.rental.id) {
        setState(() {
          checked = false;
          refreshError = friendlyError(exception);
        });
      }
    } finally {
      if (mounted &&
          generation == refreshGeneration &&
          id == widget.rental.id) {
        setState(() => refreshing = false);
      }
    }
  }

  @override
  void dispose() {
    summary.dispose();
    description.dispose();
    response.dispose();
    super.dispose();
  }

  String label(String value) => disputeLabel(value);

  Future<void> create() async {
    final controller = context.read<LiveRentHubController>();
    if (!checked ||
        refreshing ||
        closedByServer ||
        controller.disputeCreationBlockReason(widget.rental) != null) {
      return;
    }
    if (!(formKey.currentState?.validate() ?? false)) return;
    try {
      await context.read<LiveRentHubController>().createDispute(
            rental: widget.rental,
            category: category,
            summary: summary.text,
            description: description.text,
            evidence: evidenceRefs,
          );
      evidenceRefs.clear();
      if (mounted) showMockSuccess(context, 'Dispute submitted for review');
    } catch (exception) {
      if (mounted) {
        if (exception is ApiException &&
            exception.code == 'DISPUTE_WINDOW_CLOSED') {
          setState(() => closedByServer = true);
        }
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(exception))));
      }
    }
  }

  Future<void> respond(Dispute dispute) async {
    if (!(responseFormKey.currentState?.validate() ?? false)) return;
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
            evidence: evidenceRefs,
          );
      response.clear();
      evidenceRefs.clear();
      if (mounted) showMockSuccess(context, 'Response added to the case');
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(exception))));
      }
    }
  }

  Future<void> submitClaim(Dispute dispute) async {
    final amount = TextEditingController();
    final details = TextEditingController();
    final accepted = await InputValidation.showFormDialog<bool>(
      context: context,
      builder: (context) => rentHubDialog(
        title: const Text('Submit damage-waiver claim'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: (const InputDecoration(
                  labelText: 'Amount requested (RM)',
                )).copyWith(counterText: '', errorMaxLines: 3),
                validator: InputRules.amountRequestedRm.validate,
                inputFormatters: InputValidation.formatters(
                    InputRules.amountRequestedRm, amount),
                autovalidateMode: AutovalidateMode.onUserInteraction,
                maxLength: InputRules.amountRequestedRm.maxLength,
                maxLengthEnforcement: InputValidation.lengthEnforcement,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: details,
                minLines: 3,
                maxLines: 5,
                decoration: (const InputDecoration(
                  labelText: 'Damage and repair details',
                )).copyWith(counterText: '', errorMaxLines: 3),
                validator: InputRules.damageAndRepairDetails.validate,
                inputFormatters: InputValidation.formatters(
                    InputRules.damageAndRepairDetails, details),
                autovalidateMode: AutovalidateMode.onUserInteraction,
                maxLength: InputRules.damageAndRepairDetails.maxLength,
                maxLengthEnforcement: InputValidation.lengthEnforcement,
              ),
              const SizedBox(height: 12),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'After continuing, select a repair quotation or evidence file for administrator review.',
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
            onPressed: () => InputValidation.popIfValid(context, true),
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
        final controller = context.read<LiveRentHubController>();
        final evidence = await pickAndPreviewUpload(
          context,
          purpose: 'claim_evidence',
          allowPdf: true,
        );
        if (evidence == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Select an evidence file to submit the claim.'),
              ),
            );
          }
          return;
        }
        await controller.submitClaim(
          dispute: dispute,
          description: details.text,
          amount: parsed,
          evidence: [evidence],
        );
        if (mounted) showMockSuccess(context, 'Insurance claim submitted');
      } catch (exception) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(friendlyError(exception))));
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
    final blocked = closedByServer
        ? disputeWindowClosedMessage
        : controller.disputeCreationBlockReason(widget.rental);
    return Scaffold(
      appBar: AppBar(
        title: Text(dispute == null ? 'Report a rental issue' : 'Your case'),
      ),
      body: SafeArea(
        child: dispute == null
            ? _createForm(controller.loading, blocked)
            : _details(dispute, controller.claimForRental(widget.rental.id),
                controller.loading),
      ),
    );
  }

  Widget _createForm(bool loading, String? blocked) => Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (refreshing) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              const Text('Checking this rental…'),
              const SizedBox(height: 16),
            ],
            if (blocked != null) ...[
              Card(
                  child: Padding(
                      padding: const EdgeInsets.all(16), child: Text(blocked))),
              const SizedBox(height: 16),
            ] else if (refreshError != null) ...[
              Text(refreshError!),
              TextButton(
                  onPressed: refreshing ? null : refreshEligibility,
                  child: const Text('Try again')),
              const SizedBox(height: 16),
            ],
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
            const SizedBox(height: 16),
            const DisputeProgressPanel(),
            if (widget.rental.listingType == 'physical') _conditionRecords(),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: category,
              decoration: const InputDecoration(labelText: 'Issue category'),
              items: categories
                  .map((item) => DropdownMenuItem(
                      value: item,
                      child: Text(label(item),
                          maxLines: 1, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (value) => setState(() => category = value!),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: summary,
              decoration: (const InputDecoration(labelText: 'Short summary'))
                  .copyWith(counterText: '', errorMaxLines: 3),
              validator: InputValidation.compose(
                  InputRules.shortSummary.validate,
                  (value) => (value?.trim().length ?? 0) < 5
                      ? 'Enter at least 5 characters'
                      : null),
              inputFormatters:
                  InputValidation.formatters(InputRules.shortSummary, summary),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              maxLength: InputRules.shortSummary.maxLength,
              maxLengthEnforcement: InputValidation.lengthEnforcement,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: description,
              minLines: 5,
              maxLines: 8,
              decoration: (const InputDecoration(
                labelText: 'What happened?',
                alignLabelWithHint: true,
              )).copyWith(counterText: '', errorMaxLines: 3),
              validator: InputValidation.compose(
                  InputRules.whatHappened.validate,
                  (value) => (value?.trim().length ?? 0) < 20
                      ? 'Enter at least 20 characters'
                      : null),
              inputFormatters: InputValidation.formatters(
                  InputRules.whatHappened, description),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              maxLength: InputRules.whatHappened.maxLength,
              maxLengthEnforcement: InputValidation.lengthEnforcement,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.attach_file),
              title: Text('${evidenceRefs.length} evidence files uploaded'),
              subtitle:
                  const Text('JPEG, PNG, WebP, or PDF; maximum 10 files.'),
              trailing: IconButton(
                tooltip: 'Upload evidence',
                onPressed: loading ||
                        refreshing ||
                        !checked ||
                        blocked != null ||
                        evidenceRefs.length >= 10
                    ? null
                    : pickEvidence,
                icon: const Icon(Icons.upload_file_outlined),
              ),
            ),
            for (var index = 0; index < evidenceRefs.length; index++)
              PhotoAttachmentTile(
                  reference: evidenceRefs[index],
                  label: 'Evidence ${index + 1}',
                  onRemove: () => removeEvidence(index)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: loading || refreshing || !checked || blocked != null
                  ? null
                  : create,
              icon: const Icon(Icons.gavel_outlined),
              label: const Text('Send for review'),
            ),
          ],
        ),
      );

  Widget _conditionRecords() => ExpansionTile(
          title: const Text('Handover & return photos'),
          subtitle: const Text('Compare the saved condition records.'),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          childrenPadding: const EdgeInsets.all(12),
          children: [
            RentalConditionSection(
                title: 'Before handover', record: widget.rental.handover),
            const SizedBox(height: 16),
            RentalConditionSection(
                title: 'At return', record: widget.rental.returnSubmission),
          ]);

  Widget _details(Dispute dispute, InsuranceClaim? claim, bool loading) => Form(
      key: responseFormKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DisputeProgressPanel(dispute: dispute),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(dispute.reason,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  StatusBadge(disputeLabel(dispute.status)),
                  const SizedBox(height: 8),
                  Text(label(dispute.category)),
                  const SizedBox(height: 4),
                  SelectableText('Case reference: ${dispute.id}',
                      style: const TextStyle(color: AppColors.secondaryText)),
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
                    DisputeDecisionPanel(dispute: dispute),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (dispute.evidence.isNotEmpty) ...[
            Text('Photos and documents sent with the report',
                style: Theme.of(context).textTheme.titleMedium),
            for (var i = 0; i < dispute.evidence.length; i++)
              PhotoAttachmentTile(
                  reference: dispute.evidence[i],
                  label: 'Report attachment ${i + 1}'),
            const SizedBox(height: 16),
          ],
          if (widget.rental.listingType == 'physical') _conditionRecords(),
          Text('Updates from both parties',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (dispute.responses.isEmpty)
            const Text(
              'No participant responses yet.',
              style: TextStyle(color: AppColors.secondaryText),
            ),
          for (final item in dispute.responses)
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label(item.role),
                              style: Theme.of(context).textTheme.titleSmall),
                          Text(rentalEventTime(item.submittedAt),
                              style: const TextStyle(
                                  color: AppColors.secondaryText)),
                          const SizedBox(height: 8),
                          Text(item.text),
                          for (var i = 0; i < item.evidence.length; i++)
                            PhotoAttachmentTile(
                                reference: item.evidence[i],
                                label: 'Response attachment ${i + 1}'),
                        ]))),
          if (!dispute.closed) ...[
            const SizedBox(height: 16),
            TextFormField(
              controller: response,
              minLines: 3,
              maxLines: 5,
              decoration: (const InputDecoration(
                labelText: 'Add information or a response',
              )).copyWith(counterText: '', errorMaxLines: 3),
              validator: InputRules.addInformationOrAResponse.validate,
              inputFormatters: InputValidation.formatters(
                  InputRules.addInformationOrAResponse, response),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              maxLength: InputRules.addInformationOrAResponse.maxLength,
              maxLengthEnforcement: InputValidation.lengthEnforcement,
              keyboardType: TextInputType.multiline,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: evidenceRefs.length >= 10 ? null : pickEvidence,
              icon: const Icon(Icons.attach_file),
              label: Text('Attach evidence (${evidenceRefs.length})'),
            ),
            for (var index = 0; index < evidenceRefs.length; index++)
              PhotoAttachmentTile(
                  reference: evidenceRefs[index],
                  label: 'Response evidence ${index + 1}',
                  onRemove: () => removeEvidence(index)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: loading ? null : () => respond(dispute),
              icon: const Icon(Icons.send_outlined),
              label: const Text('Send update'),
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
                onPressed: loading ? null : () => submitClaim(dispute),
                icon: const Icon(Icons.health_and_safety_outlined),
                label: const Text('Request damage-waiver review'),
              )
            else if (claim != null)
              Card(
                child: ListTile(
                  title: Text(formatMoney(claim.amountRequested)),
                  subtitle: Text(
                    claim.decisionReason.isEmpty
                        ? claim.description
                        : '${claim.decisionReason}${claim.payoutStatus == 'pending_funding' ? '\nDemo payout is waiting for funding. No payment has been made.' : ''}',
                  ),
                  trailing: StatusBadge(claim.status),
                ),
              ),
          ],
        ],
      ));
}
