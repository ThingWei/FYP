import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/network/user_facing_error.dart';
import '../../core/theme/app_theme.dart';
import '../../core/validation/input_rules.dart';
import '../../core/validation/input_validation.dart';
import '../../shared/models/domain_models.dart';
import '../../shared/widgets/dot_pagination.dart';
import '../../shared/widgets/renthub_components.dart';
import 'admin_record_models.dart';
import 'live_case_navigation.dart';
import 'live_dispute_progress.dart';
import 'live_agreement.dart';
import 'live_photo_widgets.dart';
import 'live_renthub_controller.dart';

Future<void> openAdminCase(BuildContext context,
    {String? disputeId, String? claimId}) async {
  final controller = context.read<LiveRentHubController>();
  final account = controller.accountGeneration;
  try {
    if (claimId != null) {
      final data = await controller.api.request(
          'GET', '/admin/records/claims/${Uri.encodeComponent(claimId)}');
      disputeId = data is Map && data['record'] is Map
          ? data['record']['disputeId'] as String?
          : null;
    }
    if (!context.mounted || account != controller.accountGeneration) return;
    if (disputeId == null || disputeId.isEmpty) {
      throw ApiException(404, 'The linked case is unavailable.');
    }
    await Navigator.of(context, rootNavigator: true).push<void>(
        MaterialPageRoute(
            builder: (_) => AdminCaseWorkspace(
                disputeId: disputeId!, focusClaim: claimId != null)));
  } catch (error) {
    if (context.mounted && account == controller.accountGeneration) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyError(error))));
    }
  }
}

class AdminCaseWorkspace extends StatefulWidget {
  const AdminCaseWorkspace(
      {super.key, required this.disputeId, this.focusClaim = false});
  final String disputeId;
  final bool focusClaim;
  @override
  State<AdminCaseWorkspace> createState() => _AdminCaseWorkspaceState();
}

class _AdminCaseWorkspaceState extends State<AdminCaseWorkspace> {
  Map<String, dynamic>? data;
  late final int account;
  late final String? viewer;
  int request = 0, revision = 0;
  bool loading = true, submitting = false, claimInitialized = false;
  Object? error, actionError;
  final caseForm = GlobalKey<FormState>(), claimForm = GlobalKey<FormState>();
  final notes = TextEditingController(),
      renterAmount = TextEditingController(),
      ownerAmount = TextEditingController();
  final claimReason = TextEditingController(),
      claimAmount = TextEditingController();
  String action = 'under_review',
      outcome = 'release_to_renter',
      responsibility = 'undetermined',
      claimAction = 'approved';

  @override
  void initState() {
    super.initState();
    final controller = context.read<LiveRentHubController>();
    account = controller.accountGeneration;
    viewer = controller.profile?.id;
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  bool allowed(LiveRentHubController c) =>
      c.accountGeneration == account &&
      c.profile?.id == viewer &&
      c.profile?.roles.contains(UserRole.admin) == true;
  Map get record => data?['record'] as Map? ?? const {};
  Map get claim => data?['claim'] as Map? ?? const {};
  Map get actions => data?['actions'] as Map? ?? const {};
  double get held => (data?['balance']?['held'] as num?)?.toDouble() ?? 0;

  Future<void> load() async {
    final c = context.read<LiveRentHubController>();
    if (!mounted || !allowed(c)) return;
    final generation = ++request;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await c.api.request(
          'GET', '/admin/cases/${Uri.encodeComponent(widget.disputeId)}');
      if (result is! Map || result['record'] is! Map) {
        throw const FormatException('Invalid case');
      }
      if (!mounted || !allowed(c) || generation != request) return;
      setState(() {
        data = Map<String, dynamic>.from(result);
        revision++;
      });
      if (!claimInitialized && claim.isNotEmpty) {
        claimAmount.text = (claim['amountRequested'] as num).toStringAsFixed(2);
        claimInitialized = true;
      }
    } catch (e) {
      if (mounted && allowed(c) && generation == request) {
        setState(() => error = e);
      }
    } finally {
      if (mounted && allowed(c) && generation == request) {
        setState(() => loading = false);
      }
    }
  }

  @override
  void dispose() {
    request++;
    for (final field in [
      notes,
      renterAmount,
      ownerAmount,
      claimReason,
      claimAmount
    ]) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> decide({bool forClaim = false}) async {
    final c = context.read<LiveRentHubController>();
    if (submitting ||
        !allowed(c) ||
        !(forClaim ? claimForm : caseForm).currentState!.validate()) {
      return;
    }
    final selectedAction = action,
        selectedOutcome = outcome,
        selectedClaimAction = claimAction;
    final selectedNotes = notes.text.trim(),
        selectedClaimReason = claimReason.text.trim();
    final renter = double.tryParse(renterAmount.text),
        owner = double.tryParse(ownerAmount.text);
    final approved = double.tryParse(claimAmount.text);
    final selectedResponsibility = responsibility;
    final oldHeld = held;
    final oldStatus = record['status'], oldClaimStatus = claim['status'];
    setState(() {
      submitting = true;
      actionError = null;
    });
    try {
      await load();
      if (!mounted || !allowed(c)) return;
      if (error != null) throw error!;
      if (forClaim
          ? claim['status'] != oldClaimStatus ||
              actions['canDecideClaim'] != true
          : record['status'] != oldStatus ||
              actions['canUpdate'] != true ||
              ['resolve', 'dismiss'].contains(selectedAction) &&
                  (actions['canResolve'] != true ||
                      (held * 100).round() != (oldHeld * 100).round())) {
        throw ApiException(409,
            'This case changed. Review the latest details before confirming.',
            code: 'CASE_CHANGED');
      }
      final title = forClaim
          ? selectedClaimAction == 'approved'
              ? 'Approve claim?'
              : 'Reject claim?'
          : 'Update case?';
      final summary = forClaim
          ? selectedClaimAction == 'approved'
              ? 'Approve ${adminMoney(approved)}. Payment remains pending funding.'
              : 'Record the claim rejection.'
          : selectedAction == 'resolve'
              ? '${adminLabel(selectedOutcome)} · ${adminMoney(held)} held'
              : adminLabel(
                  selectedAction == 'dismiss' ? 'dismissed' : selectedAction);
      final confirmed = await confirmAction(context,
          title: title,
          message:
              '$summary\n${forClaim ? selectedClaimReason : selectedNotes}',
          action: 'Confirm');
      if (!confirmed || !mounted || !allowed(c)) return;
      if (forClaim) {
        await c.decideClaim(
            claim: InsuranceClaim.fromJson(Map<String, dynamic>.from(claim)),
            status: selectedClaimAction,
            reason: selectedClaimReason,
            approvedAmount:
                selectedClaimAction == 'approved' ? approved : null);
      } else if (['resolve', 'dismiss'].contains(selectedAction)) {
        await c.resolveDispute(
            dispute: Dispute.fromJson(Map<String, dynamic>.from(record)),
            outcome:
                selectedAction == 'dismiss' ? 'dismissed' : selectedOutcome,
            notes: selectedNotes,
            responsibleParty: selectedResponsibility,
            renterAmount: selectedAction != 'resolve'
                ? null
                : selectedOutcome == 'split'
                    ? renter
                    : selectedOutcome == 'release_to_renter'
                        ? oldHeld
                        : 0,
            ownerAmount: selectedAction != 'resolve'
                ? null
                : selectedOutcome == 'split'
                    ? owner
                    : selectedOutcome == 'release_to_owner'
                        ? oldHeld
                        : 0);
      } else {
        await c.updateDisputeStatus(
            Dispute.fromJson(Map<String, dynamic>.from(record)),
            selectedAction,
            selectedNotes);
      }
      if (!mounted || !allowed(c)) return;
      await load();
      await c.loadAdminOverview();
      if (mounted && allowed(c)) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Decision recorded')));
      }
    } catch (e) {
      if (mounted && allowed(c)) {
        // Retrieve any recorded outcome after an uncertain response. Draft controllers survive.
        await load();
        if (mounted && allowed(c)) setState(() => actionError = e);
      }
    } finally {
      if (mounted && allowed(c)) setState(() => submitting = false);
    }
  }

  Widget panel(String title, Widget child) => Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            child,
          ])));

  Widget overview() {
    final booking = data?['booking'] as Map? ?? const {};
    final balance = data?['balance'] as Map?;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      panel(
          'Case',
          _CaseFacts(values: {
            'Reported by': adminLabel(record['raisedByName']),
            'Other participant': adminLabel(record['respondentName']),
            'Issue': adminLabel(record['category']),
            'Opened': adminDate(record['createdAt']),
            'Start date': adminDate(booking['startDate'],
                calendar: record['listingType'] == 'physical'),
            'End date': adminDate(booking['endDate'],
                calendar: record['listingType'] == 'physical'),
          })),
      panel('What happened', Text(adminLabel(record['description']))),
      panel(
          'Funds',
          _CaseFacts(values: {
            'Booking total': adminMoney(booking['pricing']?['total']),
            'Remaining held':
                balance == null ? 'Not available' : adminMoney(balance['held']),
            'Already allocated': balance == null
                ? 'Not available'
                : adminMoney(balance['distributed']),
          })),
      if (claim.isNotEmpty)
        panel(
            'Damage-waiver claim',
            _CaseFacts(values: {
              'Status': adminLabel(claim['status']),
              'Requested': adminMoney(claim['amountRequested']),
              if (claim['decision']?['payoutStatus'] == 'pending_funding')
                'Payment': 'Pending funding',
            })),
      if (record['resolution'] is Map)
        panel(
            'Recorded decision',
            _CaseFacts(values: {
              'Outcome': adminLabel(record['resolution']['outcome']),
              'Notes': adminLabel(record['resolution']['notes']),
              'Renter allocation':
                  adminMoney(record['resolution']['renterAmount']),
              'Owner allocation':
                  adminMoney(record['resolution']['ownerAmount']),
              'Recorded': adminDate(record['resolution']['resolvedAt']),
            })),
      if ('${record['adminNote'] ?? ''}'.isNotEmpty)
        panel('Latest update', Text('${record['adminNote']}')),
      panel(
          'Activity',
          _CasePagedSection(
              key: ValueKey('${widget.disputeId}-events'),
              endpoint: '/admin/cases/${widget.disputeId}/activity',
              revision: revision,
              builder: (row) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(adminAuditAction(row['action'])),
                  subtitle: Text([
                    adminLabel(row['actorName']),
                    adminDate(row['createdAt']),
                    if ('${row['note'] ?? ''}'.isNotEmpty) '${row['note']}'
                  ].join('\n'))))),
    ]);
  }

  Widget evidence() {
    final rental = data?['rental'] as Map? ?? const {};
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      panel('Reported evidence',
          _CaseEvidence(references: record['evidence'] as List? ?? const [])),
      if (record['listingType'] == 'physical') ...[
        for (final entry in const {
          'handover': 'Handover',
          'returnSubmission': 'Return'
        }.entries)
          panel(
              entry.value,
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _CaseFacts(values: {
                  'Condition': adminLabel(rental[entry.key]?['condition']),
                  'Notes': adminLabel(rental[entry.key]?['notes']),
                  'Recorded': adminDate(rental[entry.key]?['recordedAt']),
                  if (entry.key == 'handover')
                    'Renter receipt':
                        adminDate(rental[entry.key]?['acknowledgedAt'])
                }),
                const SizedBox(height: 12),
                _CaseEvidence(
                    references:
                        rental[entry.key]?['evidence'] as List? ?? const []),
              ])),
      ] else
        panel(
            'Service',
            _CaseFacts(values: {
              'Delivered': adminDate(rental['serviceDeliveredAt']),
              'Completed': adminDate(rental['serviceCompletedAt'])
            })),
      if (claim.isNotEmpty)
        panel(
            'Claim evidence',
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(adminLabel(claim['description'])),
              const SizedBox(height: 12),
              _CaseEvidence(references: claim['evidence'] as List? ?? const []),
            ])),
      panel(
          'Participant responses',
          _CasePagedSection(
              endpoint:
                  '/admin/cases/${widget.disputeId}/activity?kind=responses',
              revision: revision,
              builder: (row) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                            '${adminLabel(row['authorName'])} · ${adminDate(row['submittedAt'])}',
                            style: Theme.of(context).textTheme.labelLarge),
                        const SizedBox(height: 4),
                        Text('${row['text'] ?? ''}'),
                        if ((row['evidence'] as List? ?? const []).isNotEmpty)
                          ExpansionTile(
                              title: Text(
                                  'Photos (${(row['evidence'] as List).length})'),
                              children: [
                                _CaseEvidence(
                                    references: row['evidence'] as List)
                              ]),
                      ])))),
    ]);
  }

  Widget textField(TextEditingController controller, InputRule rule,
          {String? label,
          int lines = 1,
          String? Function(String?)? validator}) =>
      TextFormField(
          controller: controller,
          validator: validator ?? rule.validate,
          inputFormatters: InputValidation.formatters(rule, controller),
          maxLength: rule.maxLength,
          maxLines: lines,
          keyboardType: rule.kind == InputKind.money
              ? const TextInputType.numberWithOptions(decimal: true)
              : null,
          decoration: InputDecoration(
              labelText: label ?? rule.label,
              counterText: '',
              errorMaxLines: 3));

  Widget decisions() {
    final sections = <Widget>[
      if (actionError != null)
        panel('Update needs attention', Text(friendlyError(actionError!))),
      panel(
          'Case action',
          actions['canUpdate'] != true
              ? const Text('This case is closed.')
              : Form(
                  key: caseForm,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DropdownButtonFormField<String>(
                            initialValue: action,
                            isExpanded: true,
                            decoration:
                                const InputDecoration(labelText: 'Action'),
                            items: [
                              for (final entry in const {
                                'under_review': 'Start review',
                                'more_evidence_required': 'Request evidence',
                                'escalated': 'Escalate',
                                'resolve': 'Resolve',
                                'dismiss': 'Dismiss'
                              }.entries)
                                DropdownMenuItem(
                                    value: entry.key, child: Text(entry.value))
                            ],
                            onChanged: submitting
                                ? null
                                : (value) => setState(() => action = value!)),
                        const SizedBox(height: 16),
                        if (action == 'resolve') ...[
                          Text('Remaining held ${adminMoney(held)}',
                              style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                              initialValue: outcome,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                  labelText: 'Allocate held funds'),
                              items: [
                                for (final entry in const {
                                  'release_to_renter': 'Return to renter',
                                  'release_to_owner': 'Release to Owner',
                                  'split': 'Split funds'
                                }.entries)
                                  DropdownMenuItem(
                                      value: entry.key,
                                      child: Text(entry.value))
                              ],
                              onChanged: submitting
                                  ? null
                                  : (value) =>
                                      setState(() => outcome = value!)),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                              initialValue: responsibility,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                  labelText: 'Responsibility'),
                              items: [
                                for (final entry in const {
                                  'undetermined': 'Not determined',
                                  'none': 'Neither participant',
                                  'renter': 'Renter',
                                  'owner': 'Owner',
                                  'both': 'Both participants'
                                }.entries)
                                  DropdownMenuItem(
                                      value: entry.key,
                                      child: Text(entry.value))
                              ],
                              onChanged: submitting
                                  ? null
                                  : (value) =>
                                      setState(() => responsibility = value!)),
                          const SizedBox(height: 16),
                          if (outcome == 'split') ...[
                            textField(renterAmount, InputRules.renterAmountRm),
                            const SizedBox(height: 16),
                            textField(ownerAmount, InputRules.ownerAmountRm,
                                validator: (value) {
                              final error =
                                  InputRules.ownerAmountRm.validate(value);
                              if (error != null) return error;
                              final renter = double.tryParse(renterAmount.text),
                                  owner = double.tryParse(value ?? '');
                              if (renter == null ||
                                  owner == null ||
                                  renter <= 0 ||
                                  owner <= 0) {
                                return 'Enter a positive amount for both participants.';
                              }
                              return (renter * 100).round() +
                                          (owner * 100).round() ==
                                      (held * 100).round()
                                  ? null
                                  : 'The split must total ${adminMoney(held)}.';
                            }),
                            const SizedBox(height: 16),
                          ],
                          if (actions['canResolve'] != true)
                            Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Text(
                                    '${actions['resolutionBlockReason'] ?? 'Refresh the case before resolving.'}')),
                        ],
                        if (action == 'dismiss' &&
                            actions['canResolve'] != true)
                          Text(
                              '${actions['resolutionBlockReason'] ?? 'Refresh the case before recording a decision.'}'),
                        textField(
                            notes,
                            ['resolve', 'dismiss'].contains(action)
                                ? InputRules.decisionNotes
                                : InputRules.requiredNote,
                            label: 'Notes',
                            lines: 3),
                        const SizedBox(height: 16),
                        FilledButton(
                            onPressed: submitting ||
                                    loading ||
                                    ['resolve', 'dismiss'].contains(action) &&
                                        actions['canResolve'] != true
                                ? null
                                : () => decide(),
                            child:
                                Text(submitting ? 'Saving…' : 'Review action')),
                      ]))),
      if (claim.isNotEmpty)
        panel(
            'Damage-waiver decision',
            actions['canDecideClaim'] != true
                ? _CaseFacts(values: {
                    'Status': adminLabel(claim['status']),
                    'Amount': adminMoney(claim['decision']?['approvedAmount']),
                    'Reason': adminLabel(claim['decision']?['reason']),
                    if (claim['decision']?['payoutStatus'] == 'pending_funding')
                      'Payment': 'Pending funding'
                  })
                : Form(
                    key: claimForm,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                              'Requested ${adminMoney(claim['amountRequested'])}'),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                              initialValue: claimAction,
                              decoration:
                                  const InputDecoration(labelText: 'Decision'),
                              items: const [
                                DropdownMenuItem(
                                    value: 'approved', child: Text('Approve')),
                                DropdownMenuItem(
                                    value: 'rejected', child: Text('Reject'))
                              ],
                              onChanged: submitting
                                  ? null
                                  : (value) =>
                                      setState(() => claimAction = value!)),
                          const SizedBox(height: 16),
                          if (claimAction == 'approved') ...[
                            textField(claimAmount, InputRules.approvedAmountRm,
                                validator: (value) {
                              final error =
                                  InputRules.approvedAmountRm.validate(value);
                              if (error != null) return error;
                              final amount = double.tryParse(value ?? '');
                              return amount == null ||
                                      amount <= 0 ||
                                      amount > (claim['amountRequested'] as num)
                                  ? 'Enter an amount up to ${adminMoney(claim['amountRequested'])}.'
                                  : null;
                            }),
                            const SizedBox(height: 16),
                            const Text(
                                'Approved claims remain pending funding.'),
                            const SizedBox(height: 16)
                          ],
                          textField(claimReason, InputRules.decisionReason,
                              lines: 3),
                          const SizedBox(height: 16),
                          FilledButton(
                              onPressed: submitting || loading
                                  ? null
                                  : () => decide(forClaim: true),
                              child: const Text('Review claim decision')),
                        ]))),
    ];
    if (widget.focusClaim && claim.isNotEmpty) {
      final claimPanel = sections.removeLast();
      sections.insert(actionError == null ? 0 : 1, claimPanel);
    }
    final alert = actionError == null ? null : sections.removeAt(0);
    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth < 800) {
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [if (alert != null) alert, ...sections]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (alert != null) alert,
        Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            runSpacing: 12,
            children: [
              for (final section in sections)
                SizedBox(width: (box.maxWidth - 16) / 2, child: section),
            ]),
      ]);
    });
  }

  Widget scroll(Widget child) => SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: child)));
  @override
  Widget build(BuildContext context) {
    final c = context.watch<LiveRentHubController>();
    return DefaultTabController(
        length: 4,
        initialIndex: widget.focusClaim ? 3 : 0,
        child: Scaffold(
            appBar: AppBar(
                title: const Text('Case review'),
                actions: [
                  IconButton(
                      tooltip: 'Refresh case',
                      onPressed: loading || submitting ? null : load,
                      icon: const Icon(Icons.refresh))
                ],
                bottom: data == null || !allowed(c)
                    ? null
                    : const TabBar(
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        tabs: [
                            Tab(text: 'Overview'),
                            Tab(text: 'Evidence'),
                            Tab(text: 'Conversation'),
                            Tab(text: 'Decision')
                          ])),
            body: !allowed(c)
                ? const Center(
                    child: Text('This case is unavailable for this account.'))
                : data == null
                    ? Center(
                        child: loading
                            ? const CircularProgressIndicator()
                            : Column(mainAxisSize: MainAxisSize.min, children: [
                                Text(friendlyError(error!)),
                                TextButton(
                                    onPressed: load, child: const Text('Retry'))
                              ]))
                    : Column(children: [
                        if (loading) const LinearProgressIndicator(),
                        if (error != null)
                          MaterialBanner(
                              content: Text(friendlyError(error!)),
                              actions: [
                                TextButton(
                                    onPressed: load, child: const Text('Retry'))
                              ]),
                        Center(
                            child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 1040),
                                child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        16, 16, 16, 8),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Text(
                                              adminLabel(
                                                  record['listingTitle']),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleLarge),
                                          const SizedBox(height: 8),
                                          Wrap(
                                              spacing: 12,
                                              runSpacing: 8,
                                              crossAxisAlignment:
                                                  WrapCrossAlignment.center,
                                              children: [
                                                StatusBadge(adminLabel(
                                                    record['status'])),
                                                if (data?['booking'] != null)
                                                  TextButton.icon(
                                                      icon: const Icon(Icons
                                                          .description_outlined),
                                                      label: const Text(
                                                          'Agreement'),
                                                      onPressed: () => Navigator.push<
                                                              void>(
                                                          context,
                                                          MaterialPageRoute(
                                                              builder: (_) =>
                                                                  LiveAgreementPage(
                                                                      bookingId:
                                                                          '${record['bookingId']}'))))
                                              ]),
                                        ])))),
                        Expanded(
                            child: TabBarView(children: [
                          scroll(overview()),
                          scroll(evidence()),
                          scroll(Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                DisputeProgressPanel(
                                    dispute: Dispute.fromJson(
                                        Map<String, dynamic>.from(record))),
                                OutlinedButton.icon(
                                    onPressed: () async {
                                      await openCaseConversation(
                                          context, widget.disputeId,
                                          title:
                                              '${record['listingTitle'] ?? 'Case conversation'}');
                                      if (mounted) await load();
                                    },
                                    icon: const Icon(Icons.forum_outlined),
                                    label: const Text('Open in Messages')),
                                if (actions['canReview'] == true ||
                                    !['resolved', 'dismissed']
                                        .contains(record['status']))
                                  Builder(
                                      builder: (context) => Align(
                                          alignment: Alignment.centerRight,
                                          child: TextButton.icon(
                                              onPressed: () =>
                                                  DefaultTabController.of(
                                                          context)
                                                      .animateTo(3),
                                              icon: const Icon(
                                                  Icons.gavel_outlined),
                                              label: const Text(
                                                  'Review & resolve')))),
                                ExpansionTile(
                                    title:
                                        const Text('Earlier booking messages'),
                                    children: [
                                      _CasePagedSection(
                                          endpoint:
                                              '/admin/cases/${widget.disputeId}/conversation',
                                          revision: revision,
                                          builder: (row) => Card(
                                              child: Padding(
                                                  padding:
                                                      const EdgeInsets.all(12),
                                                  child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .stretch,
                                                      children: [
                                                        Text(
                                                            '${adminLabel(row['senderName'])} · ${adminDate(row['createdAt'])}',
                                                            style: Theme.of(
                                                                    context)
                                                                .textTheme
                                                                .labelLarge),
                                                        const SizedBox(
                                                            height: 4),
                                                        Text(
                                                            '${row['text'] ?? ''}'),
                                                        if (row['attachment']
                                                            is String)
                                                          _CaseEvidence(
                                                              references: [
                                                                row['attachment']
                                                              ]),
                                                        if (row['locationLabel']
                                                            is String)
                                                          Text(
                                                              '${row['locationLabel']}'),
                                                      ]))))
                                    ]),
                              ])),
                          scroll(decisions())
                        ])),
                      ])));
  }
}

class _CaseFacts extends StatelessWidget {
  const _CaseFacts({required this.values});
  final Map<String, String> values;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
      builder: (context, box) => Wrap(spacing: 16, runSpacing: 16, children: [
            for (final entry in values.entries)
              SizedBox(
                  width: box.maxWidth >= 520
                      ? (box.maxWidth - 16) / 2
                      : box.maxWidth,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.key,
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(color: AppColors.secondaryText)),
                        const SizedBox(height: 4),
                        SelectableText(entry.value)
                      ])),
          ]));
}

class _CaseEvidence extends StatelessWidget {
  const _CaseEvidence({required this.references});
  final List references;
  @override
  Widget build(BuildContext context) => references.isEmpty
      ? const Text('No photos attached.')
      : Wrap(spacing: 12, runSpacing: 12, children: [
          for (var index = 0; index < references.length; index++)
            LivePhotoThumbnail(
                reference: '${references[index]}',
                label: 'Evidence ${index + 1}',
                width: 112,
                height: 112),
        ]);
}

class _CasePagedSection extends StatefulWidget {
  const _CasePagedSection(
      {super.key,
      required this.endpoint,
      required this.revision,
      required this.builder});
  final String endpoint;
  final int revision;
  final Widget Function(Map<String, dynamic>) builder;
  @override
  State<_CasePagedSection> createState() => _CasePagedSectionState();
}

class _CasePagedSectionState extends State<_CasePagedSection> {
  List<Map<String, dynamic>> rows = [];
  int page = 1, limit = 20, total = 0, generation = 0;
  late final int account;
  bool loading = true;
  Object? error;
  @override
  void initState() {
    super.initState();
    account = context.read<LiveRentHubController>().accountGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  @override
  void didUpdateWidget(covariant _CasePagedSection old) {
    super.didUpdateWidget(old);
    if (old.endpoint != widget.endpoint) {
      page = 1;
      rows = [];
    }
    if (old.endpoint != widget.endpoint || old.revision != widget.revision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) load();
      });
    }
  }

  Future<void> load() async {
    if (!mounted) return;
    final c = context.read<LiveRentHubController>();
    if (c.accountGeneration != account ||
        c.profile?.roles.contains(UserRole.admin) != true) {
      return;
    }
    final request = ++generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await c.api.request('GET',
          '${widget.endpoint}${widget.endpoint.contains('?') ? '&' : '?'}page=$page&limit=$limit');
      if (!mounted || request != generation || c.accountGeneration != account) {
        return;
      }
      if (data is! ApiItems) throw const FormatException('Invalid page');
      final count = (data.meta['total'] as num).toInt();
      if (data.isEmpty && page > 1) {
        page = ((count - 1) ~/ limit + 1).clamp(1, page - 1);
        await load();
        return;
      }
      setState(() {
        rows =
            data.map((row) => Map<String, dynamic>.from(row as Map)).toList();
        total = count;
      });
    } catch (e) {
      if (mounted && request == generation && c.accountGeneration == account) {
        setState(() => error = e);
      }
    } finally {
      if (mounted && request == generation) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    generation++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (loading) const LinearProgressIndicator(),
        if (error != null)
          Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(friendlyError(error!)),
            TextButton(onPressed: load, child: const Text('Retry'))
          ]),
        if (!loading && rows.isEmpty && error == null)
          const Text('No records yet.'),
        for (final row in rows) widget.builder(row),
        if (total > 0) ...[
          const SizedBox(height: 12),
          Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 16,
              runSpacing: 8,
              children: [
                Text('$total records'),
                SizedBox(
                    width: 200,
                    child: DropdownButton<int>(
                        isExpanded: true,
                        value: limit,
                        items: [
                          for (final size in [10, 20, 50])
                            DropdownMenuItem(
                                value: size,
                                child: Text('$size per page',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis))
                        ],
                        onChanged: loading
                            ? null
                            : (value) {
                                setState(() {
                                  limit = value!;
                                  page = 1;
                                });
                                load();
                              })),
              ]),
          Center(
              child: DotPagination(
                  page: page,
                  pageCount: (total / limit).ceil(),
                  loading: loading,
                  onPage: (value) {
                    setState(() => page = value);
                    load();
                  })),
        ],
      ]);
}
