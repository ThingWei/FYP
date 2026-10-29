import 'live_trust_page.dart';
import '../../core/network/user_facing_error.dart';
import '../../core/validation/input_validation.dart';
import '../../core/validation/input_rules.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../modules/user/controllers/auth_controller.dart';
import '../../modules/user/views/login_screen.dart';
import '../../shared/models/domain_models.dart';
import '../../shared/widgets/account_components.dart';
import '../../shared/widgets/renthub_components.dart';
import '../renter/booking/booking_flow.dart' show formatMoney;
import 'live_renthub_controller.dart';
import 'live_item_verification_panel.dart';
import 'live_pricing_references.dart';
import 'admin_record_models.dart';
import 'admin_record_widgets.dart';
import 'admin_system_status.dart';
import 'live_agreement.dart';

class LiveAdminApp extends StatelessWidget {
  const LiveAdminApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'RentHub Admin',
        theme: AppTheme.light,
        home: Consumer<AuthController>(
          builder: (context, auth, _) => auth.authenticated
              ? const LiveAdminShell()
              : const LoginScreen(administrator: true),
        ),
      );
}

class LiveAdminShell extends StatefulWidget {
  const LiveAdminShell({super.key});

  @override
  State<LiveAdminShell> createState() => _LiveAdminShellState();
}

class _LiveAdminShellState extends State<LiveAdminShell> {
  int selected = 0;

  static const destinations = [
    ('Dashboard', Icons.dashboard_outlined),
    ('Verification', Icons.verified_user_outlined),
    ('Users', Icons.people_outline),
    ('Listings', Icons.inventory_2_outlined),
    ('Bookings & Transactions', Icons.receipt_long_outlined),
    ('Disputes & Claims', Icons.gavel_outlined),
    ('Reports', Icons.report_outlined),
    ('Reviews', Icons.rate_review_outlined),
    ('Platform Settings', Icons.settings_outlined),
    ('Audit Logs', Icons.history),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      await context.read<LiveRentHubController>().loadAdminOverview();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LiveRentHubController>();
    return LayoutBuilder(
      builder: (context, constraints) {
        final persistent = constraints.maxWidth >= 1024;
        final navigation = _AdminNavigation(
          selected: selected,
          onSelected: (value) {
            setState(() => selected = value);
            if (!persistent) Navigator.pop(context);
          },
        );
        return Scaffold(
          drawer:
              persistent ? null : Drawer(child: SafeArea(child: navigation)),
          appBar: AppBar(
            automaticallyImplyLeading: !persistent,
            title: Text(destinations[selected].$1),
            actions: [
              IconButton(
                tooltip: 'Refresh overview',
                onPressed: controller.adminWorkspace.loading ? null : _load,
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: 'Log out',
                onPressed: () => context.read<AuthController>().logout(),
                icon: const Icon(Icons.logout),
              ),
              const SizedBox(width: 12),
            ],
          ),
          body: Row(
            children: [
              if (persistent)
                SizedBox(
                  width: constraints.maxWidth >= 1280 ? 260 : 224,
                  child: navigation,
                ),
              Expanded(
                child: selected == 0 &&
                        controller.adminWorkspace.loading &&
                        !controller.adminWorkspace.loaded
                    ? const Center(child: CircularProgressIndicator())
                    : selected == 0 &&
                            controller.adminWorkspace.error != null &&
                            !controller.adminWorkspace.loaded
                        ? RentHubFeedbackState(
                            kind: FeedbackKind.error,
                            title: UserFacingError.from(
                                    controller.adminWorkspace.error)
                                .title,
                            message:
                                friendlyError(controller.adminWorkspace.error!),
                            actionLabel: 'Try Again',
                            onAction: _load,
                          )
                        : _page(selected),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _page(int index) => switch (index) {
        0 => const _AdminDashboard(),
        1 => const _AdminRecordSection(type: 'verification'),
        2 => const _AdminRecordSection(type: 'users'),
        3 => const _AdminRecordSection(type: 'listings'),
        4 => const _AdminRecordTabs(
            types: ['bookings', 'rentals', 'transactions']),
        5 => const _AdminRecordTabs(types: ['disputes', 'claims']),
        6 => const _AdminRecordTabs(types: [
            'reports',
            'message-reports',
            'generated-reports',
            'report-schedules'
          ]),
        7 => const _AdminRecordSection(type: 'reviews'),
        8 => _AdminSettingsWorkspace(
            key: ValueKey(context.read<LiveRentHubController>().profile?.id)),
        9 => const _AdminRecordSection(type: 'audit-logs'),
        _ => _DeferredAdminModule(title: destinations[index].$1),
      };
}

class _AdminNavigation extends StatelessWidget {
  const _AdminNavigation({required this.selected, required this.onSelected});

  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.background,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: RentHubLogo()),
            ),
            for (var index = 0;
                index < _LiveAdminShellState.destinations.length;
                index++)
              ListTile(
                selected: selected == index,
                selectedTileColor: AppColors.primaryLight,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                leading: Icon(
                  _LiveAdminShellState.destinations[index].$2,
                ),
                title: Text(_LiveAdminShellState.destinations[index].$1),
                onTap: () => onSelected(index),
              ),
          ],
        ),
      );
}

class _AdminRecordTabs extends StatelessWidget {
  const _AdminRecordTabs({required this.types});
  final List<String> types;
  @override
  Widget build(BuildContext context) => DefaultTabController(
      length: types.length,
      child: Column(children: [
        TabBar(isScrollable: true, tabs: [
          for (final type in types) Tab(text: adminRecordTitles[type])
        ]),
        Expanded(
            child: TabBarView(children: [
          for (final type in types)
            _AdminRecordSection(key: ValueKey(type), type: type)
        ])),
      ]));
}

class _AdminRecordSection extends StatelessWidget {
  const _AdminRecordSection({super.key, required this.type});
  final String type;
  @override
  Widget build(BuildContext context) => AdminRecordsTable(
      key: ValueKey(type),
      type: type,
      header: type == 'listings'
          ? Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                  icon: const Icon(Icons.price_check),
                  label: const Text('Rental-price references'),
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                          builder: (_) => LivePricingReferencesPage(
                              api: PricingReferenceApi(context
                                  .read<LiveRentHubController>()
                                  .api))))))
          : ['generated-reports', 'report-schedules'].contains(type)
              ? const _AdminReportingPanel(controlsOnly: true)
              : null,
      detailBody: type == 'verification'
          ? (context, row) => _AdminVerification(focusedUser: row)
          : null,
      actions: (context, row, reload) {
        final c = context.watch<LiveRentHubController>();
        Widget action(String label, Future<void> Function() operation) =>
            OutlinedButton(
                onPressed: c.loading
                    ? null
                    : () async {
                        await operation();
                        if (context.mounted) {
                          await reload();
                          await c.loadAdminOverview();
                        }
                      },
                child: Text(label));
        switch (type) {
          case 'bookings':
          case 'rentals':
            final bookingId = type == 'bookings'
                ? row['publicId'] ?? row['id']
                : row['bookingId'];
            return [
              if (bookingId is String)
                action('View agreement', () async {
                  await Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              LiveAgreementPage(bookingId: bookingId)));
                })
            ];
          case 'users':
            return [
              action(
                  'View trust history',
                  () => openTrustDetails(context,
                      row['authId'] as String? ?? row['id'] as String)),
              if (row['accountStatus'] == 'active' &&
                  !(row['roles'] as List? ?? []).contains('admin'))
                action('Suspend',
                    () => const _AdminUsers()._restrict(context, row)),
              if (row['accountStatus'] != 'active')
                action('Reactivate',
                    () => const _AdminUsers()._reactivate(context, row))
            ];
          case 'listings':
            final listing = Listing.fromJson(row);
            return [
              if (!listing.isService)
                action(
                    'View photos',
                    () => showItemPhotoReview(context, listing,
                        showDiagnostics: false)),
              if (listing.status == 'pending_review') ...[
                action(
                    'Reject',
                    () => const _AdminListings()
                        ._moderate(context, listing, 'rejected')),
                action(
                    'Approve',
                    () => const _AdminListings()
                        ._moderate(context, listing, 'active'))
              ]
            ];
          case 'transactions':
            final payment = Transaction.fromJson(row);
            return [
              if (payment.type == 'capture' && payment.status == 'succeeded')
                action(
                    'Refund',
                    () => const _AdminBookingsTransactions()
                        ._refund(context, payment))
            ];
          case 'reviews':
            final review = Review.fromJson(row);
            return [
              action(
                  review.status == 'hidden' ? 'Restore Review' : 'Hide Review',
                  () => const _AdminReviews()._moderate(context, review,
                      review.status == 'hidden' ? 'published' : 'hidden'))
            ];
          case 'reports':
          case 'message-reports':
            return [
              if (row['status'] == 'open') ...[
                action(
                    'Dismiss',
                    () => const _AdminMessageReports()._resolve(
                        context, row, 'dismissed',
                        messageReport: type == 'message-reports')),
                action(
                    'Resolve',
                    () => const _AdminMessageReports()._resolve(
                        context, row, 'resolved',
                        messageReport: type == 'message-reports'))
              ]
            ];
          case 'disputes':
            final dispute = Dispute.fromJson(row);
            return [
              action(
                  'View case and agreement',
                  () =>
                      const _AdminDisputesClaims()._viewCase(context, dispute)),
              if (!['resolved', 'dismissed'].contains(dispute.status)) ...[
                action(
                    'Request more evidence',
                    () => const _AdminDisputesClaims()._updateStatus(
                        context, dispute, 'more_evidence_required')),
                action(
                    'Escalate',
                    () => const _AdminDisputesClaims()
                        ._updateStatus(context, dispute, 'escalated')),
                action(
                    'Resolve',
                    () =>
                        const _AdminDisputesClaims()._resolve(context, dispute))
              ]
            ];
          case 'claims':
            final claim = InsuranceClaim.fromJson(row);
            return [
              if (claim.status == 'pending') ...[
                action(
                    'Reject',
                    () => const _AdminDisputesClaims()
                        ._decideClaim(context, claim, 'rejected')),
                action(
                    'Approve',
                    () => const _AdminDisputesClaims()
                        ._decideClaim(context, claim, 'approved'))
              ]
            ];
          case 'generated-reports':
            return [
              action('Save report file',
                  () => const _AdminReportingPanel()._download(context, row))
            ];
          case 'report-schedules':
            return [
              action(row['enabled'] == true ? 'Turn off' : 'Turn on', () async {
                final accepted = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                            title: const Text('Change this report schedule?'),
                            content: Text(row['enabled'] == true
                                ? 'Automatic reports for this schedule will stop.'
                                : 'Reports will be generated automatically for this schedule.'),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancel')),
                              FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Confirm'))
                            ]));
                if (accepted == true) {
                  await c.setReportScheduleEnabled(row, row['enabled'] != true);
                }
              })
            ];
          default:
            return [];
        }
      });
}

class _AdminSettingsWorkspace extends StatefulWidget {
  const _AdminSettingsWorkspace({super.key});
  @override
  State<_AdminSettingsWorkspace> createState() =>
      _AdminSettingsWorkspaceState();
}

class _AdminSettingsWorkspaceState extends State<_AdminSettingsWorkspace> {
  Future<void>? pending;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context.read<LiveRentHubController>();
    pending ??= controller.platformSettings.isNotEmpty &&
            controller.loyaltyConfig.isNotEmpty
        ? Future.value()
        : controller.loadAdminSettings();
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
      length: 3,
      child: Column(children: [
        const TabBar(isScrollable: true, tabs: [
          Tab(text: 'Platform settings'),
          Tab(text: 'Referrals'),
          Tab(text: 'Points history')
        ]),
        Expanded(
            child: TabBarView(children: [
          FutureBuilder<void>(
              future: pending,
              builder: (context, result) => result.connectionState !=
                      ConnectionState.done
                  ? const Center(child: CircularProgressIndicator())
                  : result.hasError
                      ? Center(
                          child: TextButton(
                              onPressed: () => setState(() => pending = context
                                  .read<LiveRentHubController>()
                                  .loadAdminSettings()),
                              child: const Text(
                                  'Could not load settings. Try again')))
                      : const _AdminPlatformSettings(showRecords: false)),
          const _AdminRecordSection(type: 'referrals'),
          const _AdminRecordSection(type: 'reward-history')
        ]))
      ]));
}

class _AdminDashboard extends StatelessWidget {
  const _AdminDashboard();

  @override
  Widget build(BuildContext context) {
    final data = context.watch<LiveRentHubController>();
    final summary = data.adminSummary;
    return RefreshIndicator(
      onRefresh: data.loadAdmin,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Platform overview',
              style: Theme.of(context).textTheme.headlineSmall),
          const Text(
            'Review requests, manage records and check how RentHub is running.',
            style: TextStyle(color: AppColors.secondaryText),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _AdminMetric(
                  'Users', '${summary['users'] ?? '—'}', Icons.people_outline),
              _AdminMetric(
                'Pending listings',
                '${summary['pendingListings'] ?? '—'}',
                Icons.inventory_2_outlined,
              ),
              _AdminMetric(
                'Bookings',
                '${summary['bookings'] ?? '—'}',
                Icons.receipt_long_outlined,
              ),
              _AdminMetric(
                'Open safety reports',
                '${summary['openReports'] ?? '—'}',
                Icons.report_outlined,
              ),
              _AdminMetric(
                'Flagged reviews',
                '${summary['flaggedReviews'] ?? '—'}',
                Icons.rate_review_outlined,
              ),
            ],
          ),
          const SizedBox(height: 24),
          const _TechnologyHealthPanel(),
        ],
      ),
    );
  }
}

class _TechnologyHealthPanel extends StatelessWidget {
  const _TechnologyHealthPanel();
  @override
  Widget build(BuildContext context) => const AdminSystemStatus();
}

class _AdminMetric extends StatelessWidget {
  const _AdminMetric(this.label, this.value, this.icon);

  final String label, value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 140, maxWidth: 220),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: AppColors.primary),
                const SizedBox(height: 16),
                Text(value, style: Theme.of(context).textTheme.headlineSmall),
                Text(label),
              ],
            ),
          ),
        ),
      );
}

class _AdminVerification extends StatefulWidget {
  const _AdminVerification({this.focusedUser});
  final Map<String, dynamic>? focusedUser;

  @override
  State<_AdminVerification> createState() => _AdminVerificationState();
}

class _AdminVerificationState extends State<_AdminVerification> {
  String documentFilter = 'all';
  String sortOrder = 'newest';

  Map<String, dynamic> _pendingAttempt(Map<String, dynamic> user) {
    final verification =
        user['verification'] as Map<String, dynamic>? ?? const {};
    final history = (verification['history'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final summaries = user['verificationSummary'];
    final pendingTypes = summaries is List
        ? summaries
            .whereType<Map>()
            .where((item) => item['status'] == 'pending')
            .map((item) => item['documentType'])
            .toSet()
        : null;
    final candidates = history
        .where((item) =>
            item['status'] == 'pending' &&
            (pendingTypes == null ||
                pendingTypes.contains(item['documentType'])) &&
            (documentFilter == 'all' || item['documentType'] == documentFilter))
        .toList();
    // A simultaneously pending MyKad must remain reviewable before driving approval.
    if (documentFilter == 'all') {
      final mykad = candidates
          .where((item) => item['documentType'] == 'mykad')
          .lastOrNull;
      if (mykad != null) return mykad;
    }
    if (candidates.isNotEmpty) return candidates.last;
    final driving = user['drivingEligibility'];
    if (verification['status'] != 'pending' &&
        driving is Map &&
        driving['status'] == 'pending') {
      return {
        ...Map<String, dynamic>.from(driving),
        'documentType': 'driving_licence',
        'attemptId': driving['latestAttemptId']
      };
    }
    return verification['status'] == 'pending'
        ? {
            'documentType': verification['documentType'],
            'documentRefs': verification['documentRefs'],
            'aiEvidence': verification['ocrResult'],
            'status': 'pending',
          }
        : const <String, dynamic>{};
  }

  Future<void> _viewDocuments(
    BuildContext context,
    List<String> references,
  ) async {
    final controller = context.read<LiveRentHubController>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Protected verification documents'),
        content: SizedBox(
          width: 760,
          height: 520,
          child: FutureBuilder(
            future: Future.wait(
              references.map(controller.downloadProtectedUpload),
            ),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return RentHubFeedbackState(
                  kind: FeedbackKind.error,
                  title: 'Document preview unavailable',
                  message: friendlyError(snapshot.error),
                );
              }
              if (!snapshot.hasData) {
                return const RentHubFeedbackState(
                  kind: FeedbackKind.loading,
                  title: 'Loading protected documents',
                  message: 'Access is checked by the RentHub API.',
                );
              }
              return PageView(
                children: [
                  for (final bytes in snapshot.data!)
                    InteractiveViewer(
                      child: Image.memory(bytes, fit: BoxFit.contain),
                    ),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _review(
    BuildContext context,
    Map<String, dynamic> user,
    String status,
    String? attemptId,
  ) async {
    final reason = TextEditingController();
    final attempt = _pendingAttempt(user);
    final driving = attempt['documentType'] == 'driving_licence';
    final extracted =
        ((attempt['aiEvidence'] as Map?)?['extracted_fields'] as Map?) ??
            const {};
    final assistance =
        (attempt['aiEvidence'] as Map?)?['drivingAssistance'] as Map?;
    final classes = TextEditingController(
        text: assistance?['licenceClasses'] is List
            ? (assistance!['licenceClasses'] as List).join(', ')
            : '${extracted['licenceClass'] ?? ''}');
    final expiry =
        TextEditingController(text: '${assistance?['validUntil'] ?? ''}');
    bool identityMatchConfirmed = false;
    bool classReviewConfirmed = false;
    final accepted = await InputValidation.showFormDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            status == 'approved'
                ? (driving
                    ? 'Approve driving eligibility?'
                    : 'Approve identity?')
                : status == 'rejected'
                    ? (driving
                        ? 'Reject driving eligibility?'
                        : 'Reject identity?')
                    : 'Request resubmission?',
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
                child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user['displayName'] as String),
                const SizedBox(height: 12),
                if (driving) ...[
                  Text(
                      'MyKad identity: ${((user['verification'] as Map?)?['documents'] as List? ?? const []).whereType<Map>().where((item) => item['documentType'] == 'mykad').map((item) => item['status']).firstOrNull ?? 'unverified'}'),
                  Text(
                      'Holder match assistance: ${(attempt['aiEvidence'] as Map?)?['identityMatch'] ?? 'unavailable'}'),
                  Text(
                      'Read validity date (confirm from protected evidence): ${assistance?['validUntil'] ?? extracted['expiryDateText'] ?? 'not extracted'}'),
                  const Text(
                      'No JPJ API / official QR or government authentication. Review licence / MyJPJ evidence against approved MyKad.'),
                ],
                if (status == 'approved' && driving) ...[
                  TextFormField(
                    controller: classes,
                    decoration: (const InputDecoration(
                            labelText: 'Reviewed licence classes (e.g. D, B2)'))
                        .copyWith(counterText: '', errorMaxLines: 3),
                    validator: InputRules.reviewedLicenceClassesEGDB2.validate,
                    inputFormatters: InputValidation.formatters(
                        InputRules.reviewedLicenceClassesEGDB2, classes),
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    maxLength: InputRules.reviewedLicenceClassesEGDB2.maxLength,
                    maxLengthEnforcement: InputValidation.lengthEnforcement,
                  ),
                  TextFormField(
                    controller: expiry,
                    decoration: (const InputDecoration(
                            labelText: 'Valid until (YYYY-MM-DD)'))
                        .copyWith(counterText: '', errorMaxLines: 3),
                    validator: InputRules.validUntilYyyyMmDd.validate,
                    inputFormatters: InputValidation.formatters(
                        InputRules.validUntilYyyyMmDd, expiry),
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    maxLength: InputRules.validUntilYyyyMmDd.maxLength,
                    maxLengthEnforcement: InputValidation.lengthEnforcement,
                    keyboardType: TextInputType.number,
                  ),
                  CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: identityMatchConfirmed,
                      title: const Text(
                          'Holder matches the approved MyKad evidence'),
                      onChanged: (value) => setDialogState(
                          () => identityMatchConfirmed = value ?? false)),
                  CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: classReviewConfirmed,
                      title:
                          const Text('Licence classes and validity reviewed'),
                      onChanged: (value) => setDialogState(
                          () => classReviewConfirmed = value ?? false)),
                ],
                if (status != 'approved')
                  TextFormField(
                    controller: reason,
                    maxLines: 3,
                    decoration: (const InputDecoration(
                      labelText: 'Required reason',
                    )).copyWith(counterText: '', errorMaxLines: 3),
                    validator: InputRules.requiredReason.validate,
                    inputFormatters: InputValidation.formatters(
                        InputRules.requiredReason, reason),
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    maxLength: InputRules.requiredReason.maxLength,
                    maxLengthEnforcement: InputValidation.lengthEnforcement,
                  ),
              ],
            )),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => InputValidation.popIfValid(dialogContext, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true || !context.mounted) {
      reason.dispose();
      classes.dispose();
      expiry.dispose();
      return;
    }
    if (status != 'approved' && reason.text.trim().length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a review reason.')),
      );
      reason.dispose();
      classes.dispose();
      expiry.dispose();
      return;
    }
    try {
      await context.read<LiveRentHubController>().reviewIdentityVerification(
            user['_id'].toString(),
            status,
            reason: reason.text,
            attemptId: attemptId,
            driving: driving,
            licenceClasses: classes.text
                .toUpperCase()
                .split(RegExp(r'[,/\s]+'))
                .where((value) => value.isNotEmpty)
                .toSet()
                .toList(),
            expiresAt: expiry.text.trim(),
            identityMatchConfirmed: identityMatchConfirmed,
            classReviewConfirmed: classReviewConfirmed,
          );
    } catch (exception) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(exception))));
      }
    }
    reason.dispose();
    classes.dispose();
    expiry.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final users = widget.focusedUser == null
        ? context.watch<LiveRentHubController>().users
        : [widget.focusedUser!];
    final pending = users.where((user) {
      if (user['verificationSummary'] is List) {
        return (user['verificationSummary'] as List).whereType<Map>().any(
            (item) =>
                item['status'] == 'pending' &&
                (documentFilter == 'all' ||
                    item['documentType'] == documentFilter));
      }
      final verification = user['verification'] as Map<String, dynamic>?;
      final history = verification?['history'] as List? ?? const [];
      return verification?['status'] == 'pending' ||
          (user['drivingEligibility'] is Map &&
              user['drivingEligibility']['status'] == 'pending') ||
          history.any(
            (item) => item is Map && item['status'] == 'pending',
          );
    }).where((user) {
      if (documentFilter == 'all') return true;
      return _pendingAttempt(user)['documentType'] == documentFilter;
    }).toList();
    pending.sort((left, right) {
      final leftAttempt = _pendingAttempt(left);
      final rightAttempt = _pendingAttempt(right);
      final leftConfidence =
          ((leftAttempt['aiEvidence'] as Map?)?['confidence'] as num?)
                  ?.toDouble() ??
              0;
      final rightConfidence =
          ((rightAttempt['aiEvidence'] as Map?)?['confidence'] as num?)
                  ?.toDouble() ??
              0;
      if (sortOrder == 'confidence_low') {
        return leftConfidence.compareTo(rightConfidence);
      }
      if (sortOrder == 'confidence_high') {
        return rightConfidence.compareTo(leftConfidence);
      }
      final leftTime =
          DateTime.tryParse('${leftAttempt['submittedAt']}') ?? DateTime(1970);
      final rightTime =
          DateTime.tryParse('${rightAttempt['submittedAt']}') ?? DateTime(1970);
      return rightTime.compareTo(leftTime);
    });
    if (pending.isEmpty) {
      if (widget.focusedUser != null) return const SizedBox.shrink();
      return const RentHubFeedbackState(
        kind: FeedbackKind.empty,
        title: 'Verification queue is clear',
        message: 'New identity submissions will appear here.',
      );
    }
    if (widget.focusedUser != null) {
      final user = pending.first;
      final attempt = _pendingAttempt(user);
      final attemptId = attempt['attemptId'] as String?;
      final documentType = attempt['documentType'];
      final refs =
          (attempt['documentRefs'] as List? ?? const []).cast<String>();
      final current = context.watch<LiveRentHubController>();
      return AdminDetailSection(
          title: 'Review required',
          icon: Icons.fact_check_outlined,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                'Review the ${adminLabel(documentType)} photos before deciding. Automated checks do not prove that a document is genuine.'),
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                  onPressed:
                      refs.isEmpty ? null : () => _viewDocuments(context, refs),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('View Documents')),
              OutlinedButton(
                  onPressed: current.loading
                      ? null
                      : () => _review(
                          context, user, 'resubmission_required', attemptId),
                  child: const Text('Request Resubmission')),
              OutlinedButton(
                  onPressed: current.loading
                      ? null
                      : () => _review(context, user, 'rejected', attemptId),
                  child: const Text('Reject')),
              if (['mykad', 'driving_licence'].contains(documentType))
                FilledButton(
                    onPressed: current.loading
                        ? null
                        : () => _review(context, user, 'approved', attemptId),
                    child: const Text('Approve')),
            ]),
          ]));
    }
    return Column(
      children: [
        if (widget.focusedUser == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: documentFilter,
                    decoration:
                        const InputDecoration(labelText: 'Document type'),
                    items: const [
                      DropdownMenuItem(
                          value: 'all', child: Text('All documents')),
                      DropdownMenuItem(value: 'mykad', child: Text('MyKad')),
                      DropdownMenuItem(
                        value: 'driving_licence',
                        child: Text('Driving Eligibility'),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => documentFilter = value ?? 'all'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: sortOrder,
                    decoration: const InputDecoration(labelText: 'Sort queue'),
                    items: const [
                      DropdownMenuItem(
                          value: 'newest', child: Text('Newest first')),
                      DropdownMenuItem(
                        value: 'confidence_low',
                        child: Text('Lowest confidence'),
                      ),
                      DropdownMenuItem(
                        value: 'confidence_high',
                        child: Text('Highest confidence'),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => sortOrder = value ?? 'newest'),
                  ),
                ),
                const SizedBox(width: 16),
                Text('${pending.length} pending'),
              ],
            ),
          ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(24),
            itemCount: pending.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final user = pending[index];
              final verification =
                  user['verification'] as Map<String, dynamic>? ?? const {};
              final history = (verification['history'] as List? ?? const [])
                  .whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item))
                  .toList();
              final attempt = _pendingAttempt(user);
              final references = ((attempt['documentRefs'] ??
                          verification['documentRefs']) as List?)
                      ?.cast<String>() ??
                  const [];
              final ocr = Map<String, dynamic>.from(
                (attempt['aiEvidence'] ?? verification['ocrResult']) as Map? ??
                    const {},
              );
              final attemptId = attempt['attemptId'] as String?;
              final attemptDocumentType =
                  attempt['documentType'] ?? verification['documentType'];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const CircleAvatar(
                            child: Icon(Icons.person_search_outlined),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user['displayName'] as String,
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                                Text(
                                  '${adminLabel(attemptDocumentType ?? 'Document')} · ${references.length} protected photo(s)',
                                ),
                              ],
                            ),
                          ),
                          const StatusBadge('pending'),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(attemptDocumentType == 'driving_licence'
                          ? (ocr['identityMatch'] == 'matched'
                              ? 'The licence holder matches the verified identity. Review the licence before deciding.'
                              : 'Check the licence holder against the approved MyKad before deciding.')
                          : (ocr['outcome'] == 'accepted'
                              ? 'Automated checks are complete. Administrator review is still required.'
                              : 'Review both document images carefully before deciding.')),
                      const SizedBox(height: 8),
                      const Text(
                          'Automated checks do not prove that a document is genuine.'),
                      if (history.length > 1 && widget.focusedUser == null)
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title:
                              Text('Verification history (${history.length})'),
                          children: [
                            for (final previous in history.reversed)
                              ListTile(
                                dense: true,
                                title: Text(
                                  '${previous['documentType'] ?? 'document'} â€¢ ${previous['status'] ?? 'unknown'}',
                                ),
                                subtitle: Text(
                                  '${adminDate(previous['submittedAt'])}'
                                  '${('${previous['reviewReason'] ?? ''}').isEmpty ? '' : '\n${previous['reviewReason']}'}',
                                ),
                              ),
                          ],
                        ),
                      const SizedBox(height: 4),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: references.isEmpty
                                ? null
                                : () => _viewDocuments(context, references),
                            child: const Text('View Documents'),
                          ),
                          if (attemptDocumentType == 'driving_licence')
                            OutlinedButton(
                              onPressed: () {
                                final mykad = history
                                    .where((item) =>
                                        item['documentType'] == 'mykad' &&
                                        item['status'] == 'approved')
                                    .lastOrNull;
                                final refs = (mykad?['documentRefs'] as List? ??
                                        const [])
                                    .cast<String>();
                                if (refs.isNotEmpty) {
                                  _viewDocuments(context, refs);
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'No protected approved MyKad attempt is available. Request MyKad resubmission or locate the legacy protected evidence.')));
                                }
                              },
                              child: const Text('Compare approved MyKad'),
                            ),
                          OutlinedButton(
                            onPressed: () => _review(context, user,
                                'resubmission_required', attemptId),
                            child: const Text('Request Resubmission'),
                          ),
                          OutlinedButton(
                            onPressed: () =>
                                _review(context, user, 'rejected', attemptId),
                            child: const Text('Reject'),
                          ),
                          FilledButton(
                            onPressed: () =>
                                _review(context, user, 'approved', attemptId),
                            child: const Text('Approve'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AdminUsers extends StatelessWidget {
  const _AdminUsers();

  Future<void> _reactivate(
    BuildContext context,
    Map<String, dynamic> user,
  ) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Reactivate ${user['displayName']}?'),
        content: const Text(
          'The user can sign in again with a new session. Listings hidden '
          'during the restriction remain inactive for a manual review.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => InputValidation.popIfValid(context, true),
            child: const Text('Reactivate'),
          ),
        ],
      ),
    );
    if (accepted != true || !context.mounted) return;
    try {
      await context.read<LiveRentHubController>().changeAccountStatus(
            user['_id'] as String,
            'active',
            '',
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account reactivated.')),
        );
      }
    } catch (exception) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(exception))));
      }
    }
  }

  Future<void> _restrict(
    BuildContext context,
    Map<String, dynamic> user,
  ) async {
    final reason = TextEditingController();
    final accepted = await InputValidation.showFormDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Suspend ${user['displayName']}?'),
        content: TextFormField(
          controller: reason,
          decoration: (const InputDecoration(labelText: 'Required reason'))
              .copyWith(counterText: '', errorMaxLines: 3),
          validator: InputRules.requiredReason.validate,
          inputFormatters:
              InputValidation.formatters(InputRules.requiredReason, reason),
          autovalidateMode: AutovalidateMode.onUserInteraction,
          maxLength: InputRules.requiredReason.maxLength,
          maxLengthEnforcement: InputValidation.lengthEnforcement,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => InputValidation.popIfValid(context, true),
            child: const Text('Suspend'),
          ),
        ],
      ),
    );
    if (accepted == true && reason.text.trim().length >= 3 && context.mounted) {
      try {
        await context.read<LiveRentHubController>().changeAccountStatus(
              user['_id'] as String,
              'suspended',
              reason.text.trim(),
            );
      } catch (exception) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(friendlyError(exception))));
        }
      }
    }
    reason.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<LiveRentHubController>();
    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: data.users.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final user = data.users[index];
        final status = user['accountStatus'] as String? ?? 'active';
        final statusReason = user['accountStatusReason'] as String? ?? '';
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              child: Text((user['displayName'] as String).substring(0, 1)),
            ),
            title: Text(user['displayName'] as String),
            subtitle: Text(
              '${(user['roles'] as List).join(', ')} · ${user['email']}'
              '${statusReason.isEmpty ? '' : '\nReason: $statusReason'}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StatusBadge(status),
                const SizedBox(width: 8),
                if (status == 'active' &&
                    !(user['roles'] as List).contains('admin'))
                  OutlinedButton(
                    onPressed: () => _restrict(context, user),
                    child: const Text('Suspend'),
                  ),
                if (status != 'active')
                  FilledButton(
                    onPressed: () => _reactivate(context, user),
                    child: const Text('Reactivate'),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AdminListings extends StatelessWidget {
  const _AdminListings();

  Future<void> _moderate(
    BuildContext context,
    Listing listing,
    String status,
  ) async {
    final reason = TextEditingController();
    final accepted = await InputValidation.showFormDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${status == 'active' ? 'Approve' : 'Reject'} listing?'),
        content: status == 'rejected'
            ? TextFormField(
                controller: reason,
                decoration:
                    (const InputDecoration(labelText: 'Rejection reason'))
                        .copyWith(counterText: '', errorMaxLines: 3),
                validator: InputRules.rejectionReason.validate,
                inputFormatters: InputValidation.formatters(
                    InputRules.rejectionReason, reason),
                autovalidateMode: AutovalidateMode.onUserInteraction,
                maxLength: InputRules.rejectionReason.maxLength,
                maxLengthEnforcement: InputValidation.lengthEnforcement,
              )
            : Text(listing.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => InputValidation.popIfValid(context, true),
            child: Text(status == 'active' ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );
    if (accepted == true && context.mounted) {
      if (status == 'rejected' && reason.text.trim().length < 3) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('A rejection reason is required.')),
        );
      } else {
        try {
          await context.read<LiveRentHubController>().moderateListing(
                listing.id,
                status,
                reason: reason.text,
              );
        } catch (exception) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(friendlyError(exception))));
          }
        }
      }
    }
    reason.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<LiveRentHubController>();
    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: data.adminListings.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Card(
              child: ListTile(
            leading: const Icon(Icons.price_check_outlined),
            title: const Text('Rental-price references'),
            subtitle: const Text('Review and import advertised rental prices'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => LivePricingReferencesPage(
                        api: PricingReferenceApi(data.api)))),
          ));
        }
        final listing = data.adminListings[index - 1];
        return Card(
          child: ListTile(
            title: Text(listing.title),
            onTap: listing.isService
                ? null
                : () => showItemPhotoReview(context, listing,
                    showDiagnostics: true),
            subtitle: Text(
              '${listing.ownerName} · ${formatMoney(listing.dailyPrice)} · ${listing.listingTypeLabel}'
              '${!listing.isService ? '\n${listing.itemPhotoCheckLabel} · View photos' : ''}',
            ),
            isThreeLine: !listing.isService,
            trailing: listing.status == 'pending_review'
                ? Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: () =>
                            _moderate(context, listing, 'rejected'),
                        child: const Text('Reject'),
                      ),
                      FilledButton(
                        onPressed: () => _moderate(context, listing, 'active'),
                        child: const Text('Approve'),
                      ),
                    ],
                  )
                : StatusBadge(listing.status.replaceAll('_', ' ')),
          ),
        );
      },
    );
  }
}

extension on Listing {
  String get listingTypeLabel => isService ? 'Service' : 'Physical item';
}

class _AdminBookingsTransactions extends StatelessWidget {
  const _AdminBookingsTransactions();

  Future<void> _refund(BuildContext context, Transaction transaction) async {
    Map<String, dynamic> balance;
    try {
      balance = await context
          .read<LiveRentHubController>()
          .paymentBalance(transaction.bookingId);
    } catch (exception) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(exception))));
      }
      return;
    }
    if (!context.mounted) return;
    final held = (balance['held'] as num).toDouble();
    if (held <= 0 || balance['reconciliationRequired'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'No refundable held balance remains. Previous refunds and Owner payments cannot be paid again.')));
      return;
    }
    final amount = TextEditingController(
        text: (held < transaction.amount ? held : transaction.amount)
            .toStringAsFixed(2));
    final reason = TextEditingController(text: 'Administrator-approved refund');
    final accepted = await InputValidation.showFormDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Issue simulated refund?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
                'Still held: ${formatMoney(held)}. Prior refunds, deposit releases and Owner payouts are excluded.'),
            TextFormField(
              controller: amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: (const InputDecoration(labelText: 'Amount (RM)'))
                  .copyWith(counterText: '', errorMaxLines: 3),
              validator: (value) {
                final error = InputRules.amountRm.validate(value);
                if (error != null) return error;
                final parsed = double.tryParse(value ?? '');
                return parsed == null || parsed <= 0 || parsed > held
                    ? 'Enter an amount up to ${formatMoney(held)}.'
                    : null;
              },
              inputFormatters:
                  InputValidation.formatters(InputRules.amountRm, amount),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              maxLength: InputRules.amountRm.maxLength,
              maxLengthEnforcement: InputValidation.lengthEnforcement,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: reason,
              decoration: (const InputDecoration(labelText: 'Reason'))
                  .copyWith(counterText: '', errorMaxLines: 3),
              validator: InputRules.reason.validate,
              inputFormatters:
                  InputValidation.formatters(InputRules.reason, reason),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              maxLength: InputRules.reason.maxLength,
              maxLengthEnforcement: InputValidation.lengthEnforcement,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => InputValidation.popIfValid(context, true),
            child: const Text('Refund'),
          ),
        ],
      ),
    );
    final parsed = double.tryParse(amount.text);
    if (accepted == true && parsed != null && parsed > 0 && context.mounted) {
      try {
        await context.read<LiveRentHubController>().refundTransaction(
              transaction.id,
              parsed,
              reason.text,
            );
      } catch (exception) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(friendlyError(exception))));
        }
      }
    }
    amount.dispose();
    reason.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<LiveRentHubController>();
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Bookings', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        for (final booking in data.adminWorkspace.bookings)
          Card(
            child: ListTile(
              title: Text(booking.listingTitle),
              subtitle: Text(
                '${booking.id} · ${formatMoney(booking.total)} · Payment ${booking.paymentStatus}',
              ),
              trailing: StatusBadge(booking.status),
            ),
          ),
        const SizedBox(height: 24),
        Text('Transactions', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        for (final transaction in data.transactions)
          Card(
            child: ListTile(
              title: Text(transaction.type.replaceAll('_', ' ')),
              subtitle: Text('${transaction.id} · ${transaction.bookingId}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(formatMoney(transaction.amount)),
                  if (transaction.type == 'capture' &&
                      transaction.status == 'succeeded') ...[
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () => _refund(context, transaction),
                      child: const Text('Refund'),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _AdminDisputesClaims extends StatelessWidget {
  const _AdminDisputesClaims();

  void _showError(BuildContext context, Object exception) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(friendlyError(exception))));
  }

  Future<void> _viewCase(BuildContext context, Dispute dispute) async {
    try {
      final record = await context
          .read<LiveRentHubController>()
          .loadDisputeCase(dispute.id);
      if (!context.mounted) return;
      final caseContext =
          record['caseContext'] as Map<String, dynamic>? ?? const {};
      final agreement =
          caseContext['agreement'] as Map<String, dynamic>? ?? const {};
      final inspection =
          caseContext['inspection'] as Map<String, dynamic>? ?? const {};
      final messages = caseContext['conversation'] as List? ?? const [];
      final pricing = agreement['pricing'] as Map<String, dynamic>? ?? const {};
      final handover =
          inspection['handover'] as Map<String, dynamic>? ?? const {};
      final returned =
          inspection['returnSubmission'] as Map<String, dynamic>? ?? const {};
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Case file ${dispute.id}'),
          content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Agreement',
                      style: Theme.of(context).textTheme.titleMedium),
                  Text(dispute.listingTitle),
                  Text(
                    '${adminLabel(dispute.listingType == 'physical' ? agreement['fulfilmentMethod'] : agreement['serviceVenue'])} • ${adminMoney(pricing['total'])}',
                  ),
                  const Divider(height: 28),
                  Text('Evidence & inspection',
                      style: Theme.of(context).textTheme.titleMedium),
                  Text('Dispute attachments: ${dispute.evidence.length}'),
                  if (dispute.listingType == 'physical') ...[
                    Text(
                        'Handover condition: ${handover['condition'] ?? 'Not recorded'}'),
                    Text(
                        'Return condition: ${returned['condition'] ?? 'Not recorded'}'),
                    Text(
                      'Inspection attachments: ${(handover['evidence'] as List?)?.length ?? 0} handover, ${(returned['evidence'] as List?)?.length ?? 0} return',
                    ),
                  ] else
                    Text(
                      'Service delivered: ${adminDate(inspection['serviceDeliveredAt'])}',
                    ),
                  const Divider(height: 28),
                  Text('Conversation history',
                      style: Theme.of(context).textTheme.titleMedium),
                  if (messages.isEmpty)
                    const Text('No booking conversation messages.')
                  else
                    for (final raw in messages)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: const Icon(Icons.chat_bubble_outline),
                        title: Text(
                          (raw as Map<String, dynamic>)['senderName']
                                  as String? ??
                              (raw['senderId'] == record['raisedById']
                                  ? dispute.raisedByName
                                  : raw['senderId'] == record['respondentId']
                                      ? dispute.respondentName
                                      : 'Participant'),
                        ),
                        subtitle: Text(raw['text'] as String),
                      ),
                  if (dispute.responses.isNotEmpty) ...[
                    const Divider(height: 28),
                    Text('Case responses',
                        style: Theme.of(context).textTheme.titleMedium),
                    for (final item in dispute.responses)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(item.role),
                        subtitle: Text(item.text),
                        trailing: Text('${item.evidence.length} files'),
                      ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (exception) {
      if (context.mounted) _showError(context, exception);
    }
  }

  Future<void> _updateStatus(
    BuildContext context,
    Dispute dispute,
    String status,
  ) async {
    final note = TextEditingController();
    final accepted = await InputValidation.showFormDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          status == 'escalated'
              ? 'Escalate dispute?'
              : 'Request more evidence?',
        ),
        content: TextFormField(
          controller: note,
          minLines: 3,
          maxLines: 5,
          decoration: (const InputDecoration(labelText: 'Required note'))
              .copyWith(counterText: '', errorMaxLines: 3),
          validator: InputRules.requiredNote.validate,
          inputFormatters:
              InputValidation.formatters(InputRules.requiredNote, note),
          autovalidateMode: AutovalidateMode.onUserInteraction,
          maxLength: InputRules.requiredNote.maxLength,
          maxLengthEnforcement: InputValidation.lengthEnforcement,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => InputValidation.popIfValid(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (accepted == true && note.text.trim().length >= 5 && context.mounted) {
      try {
        await context
            .read<LiveRentHubController>()
            .updateDisputeStatus(dispute, status, note.text);
      } catch (exception) {
        if (context.mounted) _showError(context, exception);
      }
    } else if (accepted == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('A note of at least 5 characters is required.')),
      );
    }
    note.dispose();
  }

  Future<void> _resolve(BuildContext context, Dispute dispute) async {
    Map<String, dynamic> balance;
    try {
      balance = await context
          .read<LiveRentHubController>()
          .paymentBalance(dispute.bookingId);
    } catch (exception) {
      if (context.mounted) _showError(context, exception);
      return;
    }
    if (!context.mounted) return;
    final held = (balance['held'] as num).toDouble();
    var outcome = 'release_to_renter';
    var responsibleParty = 'undetermined';
    final renterAmount = TextEditingController();
    final ownerAmount = TextEditingController();
    final notes = TextEditingController();
    final accepted = await InputValidation.showFormDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Record dispute decision'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                      'Remaining held balance: ${formatMoney(held)}. Only this balance will be allocated; previous refunds and payouts stay unchanged.'),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: outcome,
                    decoration: const InputDecoration(labelText: 'Outcome'),
                    items: const [
                      DropdownMenuItem(
                        value: 'release_to_renter',
                        child: Text('Release to renter'),
                      ),
                      DropdownMenuItem(value: 'split', child: Text('Split')),
                      DropdownMenuItem(
                        value: 'release_to_owner',
                        child: Text('Release to Owner'),
                      ),
                      DropdownMenuItem(
                        value: 'dismissed',
                        child: Text('Dismiss dispute'),
                      ),
                    ],
                    onChanged: (value) => setState(() => outcome = value!),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: responsibleParty,
                      decoration: const InputDecoration(
                          labelText: 'Responsibility finding'),
                      items: const [
                        DropdownMenuItem(
                            value: 'undetermined',
                            child: Text('Not determined')),
                        DropdownMenuItem(
                            value: 'none', child: Text('Neither participant')),
                        DropdownMenuItem(
                            value: 'renter', child: Text('Renter')),
                        DropdownMenuItem(value: 'owner', child: Text('Owner')),
                        DropdownMenuItem(
                            value: 'both', child: Text('Both participants'))
                      ],
                      onChanged: (value) => setState(
                          () => responsibleParty = value ?? 'undetermined')),
                  const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                          'Choose a participant only when the evidence establishes responsibility. Refund amounts alone do not determine fault. This finding can affect the trust score.')),
                  if (outcome == 'split') ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: renterAmount,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: (const InputDecoration(
                              labelText: 'Renter amount (RM)'))
                          .copyWith(counterText: '', errorMaxLines: 3),
                      validator: InputRules.renterAmountRm.validate,
                      inputFormatters: InputValidation.formatters(
                          InputRules.renterAmountRm, renterAmount),
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      maxLength: InputRules.renterAmountRm.maxLength,
                      maxLengthEnforcement: InputValidation.lengthEnforcement,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: ownerAmount,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: (const InputDecoration(
                              labelText: 'Owner amount (RM)'))
                          .copyWith(counterText: '', errorMaxLines: 3),
                      validator: (value) {
                        final error = InputRules.ownerAmountRm.validate(value);
                        if (error != null) return error;
                        final renter = double.tryParse(renterAmount.text);
                        final owner = double.tryParse(value ?? '');
                        if (renter == null ||
                            owner == null ||
                            renter <= 0 ||
                            owner <= 0) {
                          return 'Enter a positive amount for both participants.';
                        }
                        return (renter * 100).round() + (owner * 100).round() ==
                                (held * 100).round()
                            ? null
                            : 'The split must total ${formatMoney(held)}.';
                      },
                      inputFormatters: InputValidation.formatters(
                          InputRules.ownerAmountRm, ownerAmount),
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      maxLength: InputRules.ownerAmountRm.maxLength,
                      maxLengthEnforcement: InputValidation.lengthEnforcement,
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: notes,
                    minLines: 3,
                    maxLines: 5,
                    decoration:
                        (const InputDecoration(labelText: 'Decision notes'))
                            .copyWith(counterText: '', errorMaxLines: 3),
                    validator: InputRules.decisionNotes.validate,
                    inputFormatters: InputValidation.formatters(
                        InputRules.decisionNotes, notes),
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    maxLength: InputRules.decisionNotes.maxLength,
                    maxLengthEnforcement: InputValidation.lengthEnforcement,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'This records demonstration payouts, without moving real money. Divide the full remaining balance between the participants.',
                    style: TextStyle(color: AppColors.secondaryText),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => InputValidation.popIfValid(context, true),
              child: const Text('Record Decision'),
            ),
          ],
        ),
      ),
    );
    final renter = double.tryParse(renterAmount.text);
    final owner = double.tryParse(ownerAmount.text);
    final splitValid = outcome != 'split' ||
        (renter != null && renter > 0 && owner != null && owner > 0);
    if (accepted == true &&
        notes.text.trim().length >= 10 &&
        splitValid &&
        context.mounted) {
      try {
        await context.read<LiveRentHubController>().resolveDispute(
              dispute: dispute,
              outcome: outcome,
              responsibleParty: responsibleParty,
              notes: notes.text,
              renterAmount: outcome == 'split' ? renter : null,
              ownerAmount: outcome == 'split' ? owner : null,
            );
      } catch (exception) {
        if (context.mounted) _showError(context, exception);
      }
    } else if (accepted == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter decision notes and valid split amounts.'),
        ),
      );
    }
    renterAmount.dispose();
    ownerAmount.dispose();
    notes.dispose();
  }

  Future<void> _decideClaim(
    BuildContext context,
    InsuranceClaim claim,
    String status,
  ) async {
    final reason = TextEditingController();
    final amount = TextEditingController(
      text:
          status == 'approved' ? claim.amountRequested.toStringAsFixed(2) : '',
    );
    final accepted = await InputValidation.showFormDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${status == 'approved' ? 'Approve' : 'Reject'} claim?'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (status == 'approved')
                const Text(
                    'Approval records the amount only. Payout stays pending until a funded demo protection pool is available; no money is paid now.'),
              if (status == 'approved')
                TextFormField(
                  controller: amount,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      (const InputDecoration(labelText: 'Approved amount (RM)'))
                          .copyWith(counterText: '', errorMaxLines: 3),
                  validator: InputRules.approvedAmountRm.validate,
                  inputFormatters: InputValidation.formatters(
                      InputRules.approvedAmountRm, amount),
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  maxLength: InputRules.approvedAmountRm.maxLength,
                  maxLengthEnforcement: InputValidation.lengthEnforcement,
                ),
              if (status == 'approved') const SizedBox(height: 12),
              TextFormField(
                controller: reason,
                minLines: 2,
                maxLines: 4,
                decoration:
                    (const InputDecoration(labelText: 'Decision reason'))
                        .copyWith(counterText: '', errorMaxLines: 3),
                validator: InputRules.decisionReason.validate,
                inputFormatters: InputValidation.formatters(
                    InputRules.decisionReason, reason),
                autovalidateMode: AutovalidateMode.onUserInteraction,
                maxLength: InputRules.decisionReason.maxLength,
                maxLengthEnforcement: InputValidation.lengthEnforcement,
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
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    final parsed = double.tryParse(amount.text);
    if (accepted == true &&
        reason.text.trim().length >= 5 &&
        (status == 'rejected' || parsed != null) &&
        context.mounted) {
      try {
        await context.read<LiveRentHubController>().decideClaim(
              claim: claim,
              status: status,
              reason: reason.text,
              approvedAmount: status == 'approved' ? parsed : null,
            );
      } catch (exception) {
        if (context.mounted) _showError(context, exception);
      }
    }
    reason.dispose();
    amount.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<LiveRentHubController>();
    return RefreshIndicator(
      onRefresh: data.loadAdmin,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Dispute queue', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (data.adminDisputes.isEmpty)
            const Card(
              child: ListTile(
                title: Text('No disputes'),
                subtitle: Text('Participant disputes will appear here.'),
              ),
            ),
          for (final dispute in data.adminDisputes)
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
                    const SizedBox(height: 6),
                    Text('${dispute.listingTitle} • ${dispute.id}'),
                    Text(
                      '${dispute.raisedByName} vs ${dispute.respondentName}',
                      style: const TextStyle(color: AppColors.secondaryText),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: () => _viewCase(context, dispute),
                          child: const Text('View Case File'),
                        ),
                        if (!dispute.closed) ...[
                          OutlinedButton(
                            onPressed: () => _updateStatus(
                              context,
                              dispute,
                              'more_evidence_required',
                            ),
                            child: const Text('Request Evidence'),
                          ),
                          OutlinedButton(
                            onPressed: () => _updateStatus(
                              context,
                              dispute,
                              'escalated',
                            ),
                            child: const Text('Escalate'),
                          ),
                          FilledButton(
                            onPressed: () => _resolve(context, dispute),
                            child: const Text('Resolve'),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 28),
          Text('Damage-waiver claims',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (data.adminClaims.isEmpty)
            const Card(
              child: ListTile(
                title: Text('No claims'),
                subtitle: Text('Physical-item claims will appear here.'),
              ),
            ),
          for (final claim in data.adminClaims)
            Card(
              child: ListTile(
                title: Text(claim.listingTitle),
                subtitle: Text(
                  '${claim.id} • Requested ${formatMoney(claim.amountRequested)}\n${claim.description}${claim.payoutStatus == 'pending_funding' ? '\nApproved; payout awaits a funded demo protection pool. No money has been paid.' : ''}',
                ),
                isThreeLine: true,
                trailing: claim.status == 'pending'
                    ? Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: () =>
                                _decideClaim(context, claim, 'rejected'),
                            child: const Text('Reject'),
                          ),
                          FilledButton(
                            onPressed: () =>
                                _decideClaim(context, claim, 'approved'),
                            child: const Text('Approve'),
                          ),
                        ],
                      )
                    : StatusBadge(claim.status),
              ),
            ),
        ],
      ),
    );
  }
}

class _AdminReportingPanel extends StatelessWidget {
  const _AdminReportingPanel({this.controlsOnly = false});
  final bool controlsOnly;

  static const reportTypes = {
    'platform_summary': 'Platform summary',
    'bookings': 'Bookings',
    'payments': 'Payments',
    'users': 'Users',
    'listings': 'Listings',
    'disputes': 'Disputes',
  };

  void _showError(BuildContext context, Object exception) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(friendlyError(exception))),
    );
  }

  Future<void> _generate(BuildContext context) async {
    var reportType = 'platform_summary';
    var rangeDays = 30;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Generate CSV report'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: reportType,
                  decoration: const InputDecoration(labelText: 'Report type'),
                  items: [
                    for (final entry in reportTypes.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: (value) => setDialogState(
                    () => reportType = value ?? reportType,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: rangeDays,
                  decoration: const InputDecoration(labelText: 'Date range'),
                  items: const [
                    DropdownMenuItem(value: 7, child: Text('Last 7 days')),
                    DropdownMenuItem(value: 30, child: Text('Last 30 days')),
                    DropdownMenuItem(value: 90, child: Text('Last 90 days')),
                    DropdownMenuItem(value: 365, child: Text('Last 365 days')),
                  ],
                  onChanged: (value) => setDialogState(
                    () => rangeDays = value ?? rangeDays,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => InputValidation.popIfValid(dialogContext, true),
              child: const Text('Generate'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true || !context.mounted) return;
    try {
      await context.read<LiveRentHubController>().generateAdminReport(
            reportType: reportType,
            rangeDays: rangeDays,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CSV report generated.')),
      );
    } catch (exception) {
      if (context.mounted) _showError(context, exception);
    }
  }

  Future<void> _schedule(BuildContext context) async {
    final name = TextEditingController(text: 'Monthly platform summary');
    var reportType = 'platform_summary';
    var cadence = 'monthly';
    var rangeDays = 30;
    final accepted = await InputValidation.showFormDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create report schedule'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: name,
                    decoration: (const InputDecoration(labelText: 'Name'))
                        .copyWith(counterText: '', errorMaxLines: 3),
                    validator: InputRules.name.validate,
                    inputFormatters:
                        InputValidation.formatters(InputRules.name, name),
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    maxLength: InputRules.name.maxLength,
                    maxLengthEnforcement: InputValidation.lengthEnforcement,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: reportType,
                    decoration: const InputDecoration(labelText: 'Report type'),
                    items: [
                      for (final entry in reportTypes.entries)
                        DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                    ],
                    onChanged: (value) => setDialogState(
                      () => reportType = value ?? reportType,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: cadence,
                    decoration: const InputDecoration(labelText: 'Frequency'),
                    items: const [
                      DropdownMenuItem(value: 'daily', child: Text('Daily')),
                      DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                      DropdownMenuItem(
                          value: 'monthly', child: Text('Monthly')),
                    ],
                    onChanged: (value) => setDialogState(
                      () => cadence = value ?? cadence,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: rangeDays,
                    decoration:
                        const InputDecoration(labelText: 'Included date range'),
                    items: const [
                      DropdownMenuItem(value: 7, child: Text('Last 7 days')),
                      DropdownMenuItem(value: 30, child: Text('Last 30 days')),
                      DropdownMenuItem(value: 90, child: Text('Last 90 days')),
                      DropdownMenuItem(
                          value: 365, child: Text('Last 365 days')),
                    ],
                    onChanged: (value) => setDialogState(
                      () => rangeDays = value ?? rangeDays,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => InputValidation.popIfValid(
                dialogContext,
                name.text.trim().length >= 3,
              ),
              child: const Text('Create Schedule'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true && context.mounted) {
      try {
        await context.read<LiveRentHubController>().createReportSchedule(
              name: name.text.trim(),
              reportType: reportType,
              cadence: cadence,
              rangeDays: rangeDays,
            );
      } catch (exception) {
        if (context.mounted) _showError(context, exception);
      }
    }
    name.dispose();
  }

  Future<void> _download(
    BuildContext context,
    Map<String, dynamic> report,
  ) async {
    try {
      final saved = await context
          .read<LiveRentHubController>()
          .downloadAdminReport(report);
      if (saved && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report saved.')),
        );
      }
    } catch (exception) {
      if (context.mounted) _showError(context, exception);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<LiveRentHubController>();
    if (controlsOnly) {
      return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
                onPressed: data.loading ? null : () => _schedule(context),
                icon: const Icon(Icons.schedule),
                label: const Text('New Schedule')),
            FilledButton.icon(
                onPressed: data.loading ? null : () => _generate(context),
                icon: const Icon(Icons.add_chart),
                label: const Text('Generate CSV')),
          ]));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Operational reports',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const Text(
                    'Generate auditable CSV exports or automate recurring snapshots.',
                    style: TextStyle(color: AppColors.secondaryText),
                  ),
                ],
              ),
            ),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: data.loading ? null : () => _schedule(context),
                  icon: const Icon(Icons.schedule),
                  label: const Text('New Schedule'),
                ),
                FilledButton.icon(
                  onPressed: data.loading ? null : () => _generate(context),
                  icon: const Icon(Icons.add_chart),
                  label: const Text('Generate CSV'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Schedules', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (data.reportSchedules.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(Icons.schedule_outlined),
              title: Text('No report schedules'),
              subtitle: Text('Create a daily, weekly, or monthly schedule.'),
            ),
          ),
        for (final schedule in data.reportSchedules)
          Card(
            child: SwitchListTile(
              value: schedule['enabled'] as bool? ?? false,
              onChanged: data.loading
                  ? null
                  : (value) async {
                      try {
                        await context
                            .read<LiveRentHubController>()
                            .setReportScheduleEnabled(schedule, value);
                      } catch (exception) {
                        if (context.mounted) _showError(context, exception);
                      }
                    },
              title: Text(schedule['name'] as String),
              subtitle: Text(
                '${reportTypes[schedule['reportType']] ?? schedule['reportType']} | '
                '${schedule['cadence']} | Next: ${schedule['nextRunAt']}',
              ),
              secondary: const Icon(Icons.event_repeat_outlined),
            ),
          ),
        const SizedBox(height: 20),
        Text('Generated files', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (data.generatedReports.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(Icons.description_outlined),
              title: Text('No generated reports'),
              subtitle: Text('Generate a CSV to make it available here.'),
            ),
          ),
        for (final report in data.generatedReports.take(20))
          Card(
            child: ListTile(
              leading: const Icon(Icons.table_view_outlined),
              title: Text(report['fileName'] as String),
              subtitle: Text(
                '${report['rowCount']} rows | ${report['generationKind']} | '
                '${adminDate(report['createdAt'])}',
              ),
              trailing: OutlinedButton.icon(
                onPressed:
                    data.loading ? null : () => _download(context, report),
                icon: const Icon(Icons.download),
                label: const Text('Download'),
              ),
            ),
          ),
      ],
    );
  }
}

class _AdminMessageReports extends StatelessWidget {
  const _AdminMessageReports();

  Future<void> _resolve(
    BuildContext context,
    Map<String, dynamic> report,
    String status, {
    required bool messageReport,
  }) async {
    final resolution = TextEditingController();
    final accepted = await InputValidation.showFormDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title:
            Text(status == 'resolved' ? 'Resolve report?' : 'Dismiss report?'),
        content: TextFormField(
          controller: resolution,
          minLines: 2,
          maxLines: 4,
          decoration: (const InputDecoration(
            labelText: 'Required resolution note',
          )).copyWith(counterText: '', errorMaxLines: 3),
          validator: InputRules.requiredResolutionNote.validate,
          inputFormatters: InputValidation.formatters(
              InputRules.requiredResolutionNote, resolution),
          autovalidateMode: AutovalidateMode.onUserInteraction,
          maxLength: InputRules.requiredResolutionNote.maxLength,
          maxLengthEnforcement: InputValidation.lengthEnforcement,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => InputValidation.popIfValid(
              context,
              resolution.text.trim().length >= 5,
            ),
            child: Text(status == 'resolved' ? 'Resolve' : 'Dismiss'),
          ),
        ],
      ),
    );
    if (accepted != true || !context.mounted) {
      resolution.dispose();
      return;
    }
    try {
      final controller = context.read<LiveRentHubController>();
      final id = (report['publicId'] ?? report['id']) as String;
      if (messageReport) {
        await controller.resolveMessageReport(id, status, resolution.text);
      } else {
        await controller.resolveModerationReport(id, status, resolution.text);
      }
    } catch (exception) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(exception))));
      }
    }
    resolution.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<LiveRentHubController>();
    final moderationReports = data.moderationReports;
    final messageReports = data.messageReports;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const _AdminReportingPanel(),
        const SizedBox(height: 32),
        Text('Safety reports',
            style: Theme.of(context).textTheme.headlineSmall),
        const Text(
          'Review safety reports about accounts, listings, reviews and messages.',
          style: TextStyle(color: AppColors.secondaryText),
        ),
        const SizedBox(height: 16),
        if (moderationReports.isEmpty && messageReports.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(Icons.verified_user_outlined),
              title: Text('No safety reports'),
              subtitle: Text(
                'User, listing, review, and message reports will appear here.',
              ),
            ),
          ),
        for (final report in moderationReports) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        switch (report['targetType']) {
                          'user' => Icons.person_off_outlined,
                          'listing' => Icons.inventory_2_outlined,
                          _ => Icons.rate_review_outlined,
                        },
                        color: AppColors.warning,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${report['targetType']} • ${report['targetLabel']}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      StatusBadge(report['status'] as String),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Reason: ${report['reason']}'),
                  if ((report['details'] as String? ?? '').isNotEmpty)
                    Text(
                      report['details'] as String,
                      style: const TextStyle(color: AppColors.secondaryText),
                    ),
                  Text(
                    'Reporter: ${report['reporterId']} • Target: ${report['targetId']}',
                    style: const TextStyle(color: AppColors.secondaryText),
                  ),
                  if (report['status'] == 'open') ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: () => _resolve(
                            context,
                            report,
                            'dismissed',
                            messageReport: false,
                          ),
                          child: const Text('Dismiss'),
                        ),
                        FilledButton(
                          onPressed: () => _resolve(
                            context,
                            report,
                            'resolved',
                            messageReport: false,
                          ),
                          child: const Text('Resolve'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (messageReports.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Message reports',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
        ],
        for (final report in messageReports) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('Reason: ${report['reason']}'),
                      ),
                      StatusBadge(report['status'] as String),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('“${report['messageText']}”'),
                  Text(
                    report['details'] as String? ?? '',
                    style: const TextStyle(color: AppColors.secondaryText),
                  ),
                  if (report['status'] == 'open') ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: () => _resolve(
                            context,
                            report,
                            'dismissed',
                            messageReport: true,
                          ),
                          child: const Text('Dismiss'),
                        ),
                        FilledButton(
                          onPressed: () => _resolve(
                            context,
                            report,
                            'resolved',
                            messageReport: true,
                          ),
                          child: const Text('Resolve'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _AdminReviews extends StatelessWidget {
  const _AdminReviews();

  Future<void> _moderate(
    BuildContext context,
    Review review,
    String status,
  ) async {
    final reason = TextEditingController();
    final accepted = await InputValidation.showFormDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(status == 'hidden' ? 'Hide review?' : 'Restore review?'),
        content: status == 'hidden'
            ? TextFormField(
                controller: reason,
                minLines: 2,
                maxLines: 4,
                decoration: (const InputDecoration(
                  labelText: 'Moderation reason',
                )).copyWith(counterText: '', errorMaxLines: 3),
                validator: InputRules.moderationReason.validate,
                inputFormatters: InputValidation.formatters(
                    InputRules.moderationReason, reason),
                autovalidateMode: AutovalidateMode.onUserInteraction,
                maxLength: InputRules.moderationReason.maxLength,
                maxLengthEnforcement: InputValidation.lengthEnforcement,
              )
            : Text(review.text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => InputValidation.popIfValid(context, true),
            child: Text(status == 'hidden' ? 'Hide' : 'Restore'),
          ),
        ],
      ),
    );
    if (accepted != true || !context.mounted) {
      reason.dispose();
      return;
    }
    if (status == 'hidden' && reason.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A moderation reason is required.')),
      );
      reason.dispose();
      return;
    }
    try {
      await context.read<LiveRentHubController>().moderateReview(
            review.id,
            status,
            reason: reason.text,
          );
    } catch (exception) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(exception))));
      }
    }
    reason.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reviews = context.watch<LiveRentHubController>().adminReviews;
    if (reviews.isEmpty) {
      return const RentHubFeedbackState(
        kind: FeedbackKind.empty,
        title: 'No reviews yet',
        message: 'Completed-order reviews and flags will appear here.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: reviews.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final review = reviews[index];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${review.authorName} reviewed ${review.subjectName}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (review.flagged) ...[
                      const StatusBadge('Flagged'),
                      const SizedBox(width: 8),
                    ],
                    StatusBadge(review.status),
                  ],
                ),
                const SizedBox(height: 6),
                Text('${review.rating}/5 • ${review.listingTitle}'),
                Text(review.text),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: review.status == 'hidden'
                      ? OutlinedButton(
                          onPressed: () =>
                              _moderate(context, review, 'published'),
                          child: const Text('Restore Review'),
                        )
                      : FilledButton.tonal(
                          onPressed: () => _moderate(context, review, 'hidden'),
                          child: const Text('Hide Review'),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AdminPlatformSettings extends StatefulWidget {
  const _AdminPlatformSettings({this.showRecords = true});
  final bool showRecords;

  @override
  State<_AdminPlatformSettings> createState() => _AdminPlatformSettingsState();
}

class _AdminPlatformSettingsState extends State<_AdminPlatformSettings> {
  final formKey = GlobalKey<FormState>();
  final platformFormKey = GlobalKey<FormState>();
  final physicalPoints = TextEditingController();
  final servicePoints = TextEditingController();
  final referralPoints = TextEditingController();
  final friendReward = TextEditingController();
  final rewardRows = <(TextEditingController, TextEditingController)>[];
  final marketplaceFee = TextEditingController();
  final highValueThreshold = TextEditingController();
  final reportThreshold = TextEditingController();
  final ocrThreshold = TextEditingController();
  final reviewThreshold = TextEditingController();
  final minimumAge = TextEditingController();
  final supportEmail = TextEditingController();
  final bookingPolicy = TextEditingController();
  final contentPolicy = TextEditingController();
  final bookingApprovedTemplate = TextEditingController();
  final verificationTemplate = TextEditingController();
  final reportResolvedTemplate = TextEditingController();
  bool enabled = true;
  bool initialized = false;
  bool platformInitialized = false;
  bool maintenanceMode = false;
  bool highValueKycEnabled = true;
  final categoryStates = <String, bool>{};
  final kycDocuments = <String, Set<String>>{};
  final kycHighValueOnly = <String, bool>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context.watch<LiveRentHubController>();
    final config = controller.loyaltyConfig;
    if (!initialized && config.isNotEmpty) {
      initialized = true;
      enabled = config['enabled'] as bool? ?? true;
      physicalPoints.text = '${config['physicalCompletionPoints'] ?? 120}';
      servicePoints.text = '${config['serviceCompletionPoints'] ?? 100}';
      referralPoints.text = '${config['referralRewardPoints'] ?? 250}';
      friendReward.text = '${config['refereeDiscountAmount'] ?? 5}';
      for (final raw in config['redemptionOptions'] as List? ?? const []) {
        final option = raw as Map;
        rewardRows.add((
          TextEditingController(text: '${option['points']}'),
          TextEditingController(text: '${option['discountAmount']}')
        ));
      }
      if (rewardRows.isEmpty) {
        rewardRows.add((TextEditingController(), TextEditingController()));
      }
    }
    final platform = controller.platformSettings;
    if (!platformInitialized && platform.isNotEmpty) {
      platformInitialized = true;
      marketplaceFee.text = '${platform['marketplaceFeePercent'] ?? 5}';
      maintenanceMode = platform['maintenanceMode'] as bool? ?? false;
      highValueKycEnabled = platform['highValueKycEnabled'] as bool? ?? true;
      highValueThreshold.text = '${platform['highValueThreshold'] ?? 1000}';
      reportThreshold.text = '${platform['reportAutoHideThreshold'] ?? 3}';
      ocrThreshold.text = '${platform['verificationOcrThreshold'] ?? 80}';
      reviewThreshold.text =
          '${((platform['verificationManualReviewThreshold'] as num?) ?? 0.8) * 100}';
      minimumAge.text = '${platform['minimumVerificationAge'] ?? 18}';
      supportEmail.text =
          platform['supportEmail'] as String? ?? 'support@renthub.my';
      bookingPolicy.text = platform['bookingPolicy'] as String? ?? '';
      contentPolicy.text = platform['contentPolicy'] as String? ?? '';
      final templates =
          platform['notificationTemplates'] as Map<String, dynamic>? ??
              const {};
      bookingApprovedTemplate.text =
          templates['bookingApproved'] as String? ?? '';
      verificationTemplate.text =
          templates['verificationUpdate'] as String? ?? '';
      reportResolvedTemplate.text =
          templates['reportResolved'] as String? ?? '';
      for (final raw in platform['categories'] as List? ?? const []) {
        final category = raw as Map<String, dynamic>;
        categoryStates[category['name'] as String] =
            category['active'] as bool? ?? true;
      }
      for (final raw in platform['kycRequirements'] as List? ?? const []) {
        final rule = Map<String, dynamic>.from(raw as Map);
        final category = rule['category'] as String;
        kycDocuments[category] = {
          ...(rule['documentTypes'] as List? ?? const [])
              .cast<String>()
              .where((type) => type != 'passport'),
          'mykad',
          if (category == 'Vehicles') 'driving_licence'
        };
        kycHighValueOnly[category] = rule['highValueOnly'] as bool? ?? false;
      }
      const defaults = {
        'Devices': {'mykad'},
        'Vehicles': {'mykad', 'driving_licence'},
        'Equipment': {'mykad'},
        'Services': {'mykad'},
        'Clothing': {'mykad'},
        'Books': {'mykad'},
      };
      for (final entry in defaults.entries) {
        kycDocuments.putIfAbsent(entry.key, () => {...entry.value});
        kycHighValueOnly.putIfAbsent(
          entry.key,
          () => ['Devices', 'Equipment'].contains(entry.key),
        );
      }
    }
  }

  @override
  void dispose() {
    physicalPoints.dispose();
    servicePoints.dispose();
    referralPoints.dispose();
    friendReward.dispose();
    for (final row in rewardRows) {
      row.$1.dispose();
      row.$2.dispose();
    }
    marketplaceFee.dispose();
    highValueThreshold.dispose();
    reportThreshold.dispose();
    ocrThreshold.dispose();
    reviewThreshold.dispose();
    minimumAge.dispose();
    supportEmail.dispose();
    bookingPolicy.dispose();
    contentPolicy.dispose();
    bookingApprovedTemplate.dispose();
    verificationTemplate.dispose();
    reportResolvedTemplate.dispose();
    super.dispose();
  }

  Future<void> _savePlatform() async {
    if (!platformFormKey.currentState!.validate()) return;
    try {
      await context.read<LiveRentHubController>().updatePlatformSettings({
        'marketplaceFeePercent': double.parse(marketplaceFee.text),
        'maintenanceMode': maintenanceMode,
        'highValueKycEnabled': highValueKycEnabled,
        'highValueThreshold': double.parse(highValueThreshold.text),
        'reportAutoHideThreshold': int.parse(reportThreshold.text),
        'verificationOcrThreshold': int.parse(ocrThreshold.text),
        'verificationManualReviewThreshold':
            double.parse(reviewThreshold.text) / 100,
        'minimumVerificationAge': int.parse(minimumAge.text),
        'kycRequirements': kycDocuments.entries
            .map(
              (entry) => {
                'category': entry.key,
                'documentTypes': entry.value.toList()..sort(),
                'highValueOnly': kycHighValueOnly[entry.key] ?? false,
              },
            )
            .toList(),
        'supportEmail': supportEmail.text.trim(),
        'bookingPolicy': bookingPolicy.text.trim(),
        'contentPolicy': contentPolicy.text.trim(),
        'notificationTemplates': {
          'bookingApproved': bookingApprovedTemplate.text.trim(),
          'verificationUpdate': verificationTemplate.text.trim(),
          'reportResolved': reportResolvedTemplate.text.trim(),
        },
        'categories': categoryStates.entries
            .map((entry) => {'name': entry.key, 'active': entry.value})
            .toList(),
      });
      if (mounted) {
        showMockSuccess(context, 'Platform settings saved.');
      }
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(exception))));
      }
    }
  }

  List<Map<String, dynamic>>? _parseOptions() {
    final options = <Map<String, dynamic>>[];
    for (final row in rewardRows) {
      final points = int.tryParse(row.$1.text);
      final amount = double.tryParse(row.$2.text);
      if (points == null || points < 1 || amount == null || amount <= 0) {
        return null;
      }
      options.add({'points': points, 'discountAmount': amount});
    }
    if (options.isEmpty ||
        options.map((item) => item['points']).toSet().length !=
            options.length) {
      return null;
    }
    return options;
  }

  Future<void> _save() async {
    if (!formKey.currentState!.validate()) return;
    final options = _parseOptions();
    if (options == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Each reward must use a different points amount and a valid discount.'),
        ),
      );
      return;
    }
    try {
      await context.read<LiveRentHubController>().updateLoyaltyConfig({
        'enabled': enabled,
        'physicalCompletionPoints': int.parse(physicalPoints.text),
        'serviceCompletionPoints': int.parse(servicePoints.text),
        'referralRewardPoints': int.parse(referralPoints.text),
        'refereeDiscountAmount': double.parse(friendReward.text),
        'redemptionOptions': options,
      });
      if (mounted) showMockSuccess(context, 'Reward settings saved.');
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(exception))));
      }
    }
  }

  String? _wholeNumber(String? value) {
    final parsed = int.tryParse(value ?? '');
    return parsed == null || parsed < 0 ? 'Enter zero or more' : null;
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<LiveRentHubController>();
    if (data.loyaltyConfig.isEmpty || data.platformSettings.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return Center(
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: ListView(
              key: const ValueKey('admin-settings-form'),
              padding: const EdgeInsets.all(24),
              children: [
                Text('Platform Settings',
                    style: Theme.of(context).textTheme.headlineSmall),
                const Text(
                  'Manage fees, identity checks, support messages and rewards. Changes take effect after you save.',
                  style: TextStyle(color: AppColors.secondaryText),
                ),
                const SizedBox(height: 16),
                Form(
                  key: platformFormKey,
                  child: Column(
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text('Fees and identity checks',
                                  style:
                                      Theme.of(context).textTheme.titleLarge),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 16,
                                runSpacing: 12,
                                children: [
                                  _RuleField(
                                    controller: marketplaceFee,
                                    label: 'Marketplace fee (%)',
                                    validator: (value) {
                                      final number =
                                          double.tryParse(value ?? '');
                                      return number == null ||
                                              number < 0 ||
                                              number > 20
                                          ? 'Enter 0 to 20'
                                          : null;
                                    },
                                    rule: const InputRule('Marketplace fee',
                                        kind: InputKind.decimal,
                                        maxLength: 30,
                                        max: 20),
                                  ),
                                  _RuleField(
                                    controller: highValueThreshold,
                                    label: 'Additional-document threshold (RM)',
                                    validator: (value) =>
                                        (double.tryParse(value ?? '') ?? -1) < 0
                                            ? 'Enter zero or more'
                                            : null,
                                    rule: const InputRule(
                                        'Additional-document threshold',
                                        kind: InputKind.money,
                                        maxLength: 30,
                                        max: 1000000),
                                  ),
                                  _RuleField(
                                    controller: reportThreshold,
                                    label: 'Auto-hide report threshold',
                                    validator: (value) {
                                      final number = int.tryParse(value ?? '');
                                      return number == null ||
                                              number < 1 ||
                                              number > 100
                                          ? 'Enter 1 to 100'
                                          : null;
                                    },
                                    rule: const InputRule(
                                        'Auto-hide report threshold',
                                        kind: InputKind.integer,
                                        maxLength: 30,
                                        min: 1,
                                        max: 100),
                                  ),
                                  _RuleField(
                                    controller: ocrThreshold,
                                    label: 'Text readability requirement (%)',
                                    validator: (value) {
                                      final number = int.tryParse(value ?? '');
                                      return number == null ||
                                              number < 0 ||
                                              number > 100
                                          ? 'Enter 0 to 100'
                                          : null;
                                    },
                                    rule: const InputRule(
                                        'OCR confidence threshold',
                                        kind: InputKind.integer,
                                        maxLength: 30,
                                        max: 100),
                                  ),
                                  _RuleField(
                                    controller: reviewThreshold,
                                    label: 'Manual review requirement (%)',
                                    validator: (value) {
                                      final number =
                                          double.tryParse(value ?? '');
                                      return number == null ||
                                              number < 0 ||
                                              number > 100
                                          ? 'Enter 0 to 100'
                                          : null;
                                    },
                                    rule: const InputRule(
                                        'Manual-review threshold',
                                        kind: InputKind.decimal,
                                        maxLength: 30,
                                        max: 100),
                                  ),
                                  _RuleField(
                                    controller: minimumAge,
                                    label: 'Minimum verification age',
                                    validator: (value) {
                                      final number = int.tryParse(value ?? '');
                                      return number == null ||
                                              number < 18 ||
                                              number > 100
                                          ? 'Enter 18 to 100'
                                          : null;
                                    },
                                    rule: const InputRule(
                                        'Minimum verification age',
                                        kind: InputKind.integer,
                                        maxLength: 30,
                                        min: 18,
                                        max: 100),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text(
                                    'Enable high-value additional-document rules'),
                                value: highValueKycEnabled,
                                onChanged: (value) =>
                                    setState(() => highValueKycEnabled = value),
                              ),
                              const Divider(height: 28),
                              Text(
                                'Identity requirements',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const Text(
                                'MyKad approval is required before renting or publishing a listing. Vehicle renters also need an approved driving licence.',
                                style:
                                    TextStyle(color: AppColors.secondaryText),
                              ),
                              for (final category in kycDocuments.keys)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading:
                                      const Icon(Icons.verified_user_outlined),
                                  title: Text(category),
                                  subtitle: Text(category == 'Vehicles'
                                      ? 'MyKad • Driving licence for renters'
                                      : 'MyKad'),
                                  trailing: const Tooltip(
                                      message: 'Required by RentHub policy',
                                      child:
                                          Icon(Icons.lock_outline, size: 20)),
                                ),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Maintenance mode'),
                                subtitle: const Text(
                                  'Use during planned maintenance. Save to apply the change.',
                                ),
                                value: maintenanceMode,
                                onChanged: (value) =>
                                    setState(() => maintenanceMode = value),
                              ),
                              TextFormField(
                                controller: supportEmail,
                                decoration: (const InputDecoration(
                                        labelText: 'Support email'))
                                    .copyWith(
                                        counterText: '', errorMaxLines: 3),
                                validator: InputValidation.compose(
                                    InputRules.supportEmail.validate,
                                    (value) => value != null &&
                                            RegExp(r'^[^@]+@[^@]+\.[^@]+$')
                                                .hasMatch(value)
                                        ? null
                                        : 'Enter a valid email'),
                                inputFormatters: InputValidation.formatters(
                                    InputRules.supportEmail, supportEmail),
                                autovalidateMode:
                                    AutovalidateMode.onUserInteraction,
                                maxLength: InputRules.supportEmail.maxLength,
                                maxLengthEnforcement:
                                    InputValidation.lengthEnforcement,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text('Support and customer messages',
                                  style:
                                      Theme.of(context).textTheme.titleLarge),
                              const SizedBox(height: 12),
                              for (final field in [
                                (bookingPolicy, 'Booking policy', 10),
                                (contentPolicy, 'Content policy', 10),
                                (
                                  bookingApprovedTemplate,
                                  'Booking-approved message',
                                  5
                                ),
                                (
                                  verificationTemplate,
                                  'Verification-update message',
                                  5
                                ),
                                (
                                  reportResolvedTemplate,
                                  'Report-resolved message',
                                  5
                                ),
                              ]) ...[
                                TextFormField(
                                  controller: field.$1,
                                  minLines: field.$2.contains('policy') ? 2 : 1,
                                  maxLines: field.$2.contains('policy') ? 4 : 2,
                                  decoration:
                                      (InputDecoration(labelText: field.$2))
                                          .copyWith(
                                              counterText: '',
                                              errorMaxLines: 3),
                                  validator: InputValidation.compose(
                                      InputRule(field.$2,
                                              minLength: field.$1 ==
                                                          bookingPolicy ||
                                                      field.$1 == contentPolicy
                                                  ? 10
                                                  : 5,
                                              maxLength: field.$1 ==
                                                          bookingPolicy ||
                                                      field.$1 == contentPolicy
                                                  ? 3000
                                                  : 300)
                                          .validate,
                                      (value) => (value?.trim().length ?? 0) <
                                              field.$3
                                          ? 'Enter at least ${field.$3} characters'
                                          : null),
                                  inputFormatters: InputValidation.formatters(
                                      InputRule(field.$2,
                                          minLength:
                                              field.$1 == bookingPolicy ||
                                                      field.$1 == contentPolicy
                                                  ? 10
                                                  : 5,
                                          maxLength:
                                              field.$1 == bookingPolicy ||
                                                      field.$1 == contentPolicy
                                                  ? 3000
                                                  : 300),
                                      field.$1),
                                  autovalidateMode:
                                      AutovalidateMode.onUserInteraction,
                                  maxLength: InputRule(field.$2,
                                          minLength:
                                              field.$1 == bookingPolicy ||
                                                      field.$1 == contentPolicy
                                                  ? 10
                                                  : 5,
                                          maxLength:
                                              field.$1 == bookingPolicy ||
                                                      field.$1 == contentPolicy
                                                  ? 3000
                                                  : 300)
                                      .maxLength,
                                  maxLengthEnforcement:
                                      InputValidation.lengthEnforcement,
                                ),
                                const SizedBox(height: 12),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text('Listing categories',
                                  style:
                                      Theme.of(context).textTheme.titleLarge),
                              const Text(
                                'Choose which categories are available. Category names stay the same.',
                                style:
                                    TextStyle(color: AppColors.secondaryText),
                              ),
                              for (final entry in categoryStates.entries)
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  secondary: const Icon(Icons.lock_outline),
                                  title: Text(entry.key),
                                  subtitle: const Text(
                                      'Available to Owners and renters'),
                                  value: entry.value,
                                  onChanged: (value) => setState(
                                    () => categoryStates[entry.key] = value,
                                  ),
                                ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: FilledButton.icon(
                                  onPressed:
                                      data.loading ? null : _savePlatform,
                                  icon: const Icon(Icons.save_outlined),
                                  label: const Text('Save settings'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                Text('Points and referral rewards',
                    style: Theme.of(context).textTheme.headlineSmall),
                const Text(
                  'Changes apply to future completions, referrals and redemptions and are written to the administrator audit log.',
                  style: TextStyle(color: AppColors.secondaryText),
                ),
                const SizedBox(height: 16),
                Form(
                  key: formKey,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Loyalty programme enabled'),
                            subtitle: const Text(
                              'Pausing prevents future automatic awards and redemptions.',
                            ),
                            value: enabled,
                            onChanged: (value) =>
                                setState(() => enabled = value),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 16,
                            runSpacing: 12,
                            children: [
                              _RuleField(
                                controller: physicalPoints,
                                label: 'Points per completed item rental',
                                validator: _wholeNumber,
                                rule: const InputRule(
                                    'Points per completed item rental',
                                    kind: InputKind.integer,
                                    maxLength: 30,
                                    max: 10000),
                              ),
                              _RuleField(
                                controller: servicePoints,
                                label: 'Points per completed service',
                                validator: _wholeNumber,
                                rule: const InputRule(
                                    'Points per completed service',
                                    kind: InputKind.integer,
                                    maxLength: 30,
                                    max: 10000),
                              ),
                              _RuleField(
                                controller: referralPoints,
                                label: 'Points for inviting a friend',
                                validator: _wholeNumber,
                                rule: const InputRule(
                                    'Points for inviting a friend',
                                    kind: InputKind.integer,
                                    maxLength: 30,
                                    max: 10000),
                              ),
                              _RuleField(
                                controller: friendReward,
                                label: 'New friend discount (RM)',
                                validator: (value) {
                                  final amount = double.tryParse(value ?? '');
                                  return amount == null || amount < 0
                                      ? 'Enter zero or more'
                                      : null;
                                },
                                rule: const InputRule('Friend reward',
                                    kind: InputKind.money,
                                    maxLength: 30,
                                    max: 1000),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text('Discount rewards',
                              style: Theme.of(context).textTheme.titleMedium),
                          const Text(
                              'Choose how many points a renter exchanges for a discount.'),
                          const SizedBox(height: 12),
                          for (final row in rewardRows)
                            Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Wrap(
                                    spacing: 12,
                                    runSpacing: 8,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      _RuleField(
                                          controller: row.$1,
                                          label: 'Points needed',
                                          validator: (v) =>
                                              (int.tryParse(v ?? '') ?? 0) < 1
                                                  ? 'Enter at least 1 point'
                                                  : null,
                                          rule: const InputRule('Points needed',
                                              kind: InputKind.integer,
                                              maxLength: 7,
                                              min: 1,
                                              max: 100000)),
                                      _RuleField(
                                          controller: row.$2,
                                          label: 'Discount (RM)',
                                          validator: (v) =>
                                              (double.tryParse(v ?? '') ?? 0) <=
                                                      0
                                                  ? 'Enter a positive amount'
                                                  : null,
                                          rule: const InputRule('Discount',
                                              kind: InputKind.money,
                                              maxLength: 10,
                                              min: 0.01,
                                              max: 10000)),
                                      IconButton(
                                          tooltip: 'Remove reward',
                                          onPressed: rewardRows.length <= 1
                                              ? null
                                              : () => setState(() {
                                                    rewardRows.remove(row);
                                                    row.$1.dispose();
                                                    row.$2.dispose();
                                                  }),
                                          icon:
                                              const Icon(Icons.delete_outline)),
                                    ])),
                          Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                  onPressed: rewardRows.length >= 10
                                      ? null
                                      : () => setState(() => rewardRows.add((
                                            TextEditingController(),
                                            TextEditingController()
                                          ))),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Add reward'))),
                          const SizedBox(height: 16),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.icon(
                              onPressed: data.loading ? null : _save,
                              icon: const Icon(Icons.save_outlined),
                              label: const Text('Save rewards'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (widget.showRecords) ...[
                  const SizedBox(height: 24),
                  Text('Referral activity',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  if (data.adminReferrals.isEmpty)
                    const Card(
                      child:
                          ListTile(title: Text('No referral applications yet')),
                    ),
                  for (final referral in data.adminReferrals)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.people_outline),
                        title: Text(
                            '${referral['referrerId']} → ${referral['refereeId']}'),
                        subtitle: Text(referral['referralCode'] as String),
                        trailing: StatusBadge(referral['status'] as String),
                      ),
                    ),
                  const SizedBox(height: 24),
                  Text('Recent points ledger',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  for (final entry in data.adminRewardLedger.take(20))
                    Card(
                      child: ListTile(
                        title: Text(entry['description'] as String),
                        subtitle: Text('${entry['userId']} • ${entry['type']}'),
                        trailing: Text(
                          '${(entry['points'] as num) > 0 ? '+' : ''}${entry['points']}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                ],
              ],
            )));
  }
}

class _RuleField extends StatelessWidget {
  const _RuleField({
    required this.controller,
    required this.label,
    required this.validator,
    required this.rule,
  });

  final TextEditingController controller;
  final String label;
  final String? Function(String?) validator;
  final InputRule rule;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 260,
        child: TextFormField(
          controller: controller,
          keyboardType: rule.kind == InputKind.integer
              ? TextInputType.number
              : const TextInputType.numberWithOptions(decimal: true),
          maxLength: rule.maxLength,
          maxLengthEnforcement: InputValidation.lengthEnforcement,
          decoration: (InputDecoration(labelText: label))
              .copyWith(counterText: '', errorMaxLines: 3),
          validator: InputValidation.compose(rule.validate, validator),
          inputFormatters: InputValidation.formatters(rule, controller),
          autovalidateMode: AutovalidateMode.onUserInteraction,
        ),
      );
}

class _DeferredAdminModule extends StatelessWidget {
  const _DeferredAdminModule({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => RentHubFeedbackState(
        kind: FeedbackKind.empty,
        title: '$title remains in prototype mode',
        message:
            'This module has no Phase 1–5 backend contract yet. Its existing UI remains available in mock mode.',
      );
}
