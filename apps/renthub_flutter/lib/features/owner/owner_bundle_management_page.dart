import '../../core/validation/input_validation.dart';
import '../../core/validation/input_rules.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/mock_data/mock_data.dart';
import '../../shared/models/domain_models.dart';
import '../../shared/widgets/account_components.dart';
import '../../shared/widgets/renthub_components.dart';

class OwnerBundleManagementPage extends StatefulWidget {
  const OwnerBundleManagementPage({super.key});

  @override
  State<OwnerBundleManagementPage> createState() =>
      _OwnerBundleManagementPageState();
}

class _BundleRecord {
  _BundleRecord({
    required this.name,
    required this.itemIds,
    required this.discount,
  });

  final String name;
  final List<String> itemIds;
  final int discount;
  bool active = true;
}

class _OwnerBundleManagementPageState extends State<OwnerBundleManagementPage> {
  final bundles = <_BundleRecord>[
    _BundleRecord(
      name: 'Photography Starter Bundle',
      itemIds: const ['l-camera', 'l-tent'],
      discount: 10,
    ),
  ];

  List<Listing> get eligibleListings =>
      MockData.listings.where((listing) => !listing.isService).take(6).toList();

  Future<void> _create() async {
    final record = await Navigator.push<_BundleRecord>(
      context,
      MaterialPageRoute(
        builder: (_) => _CreateBundlePage(listings: eligibleListings),
      ),
    );
    if (record == null || !mounted) return;
    setState(() => bundles.add(record));
    showMockSuccess(context, '${record.name} saved as Active');
  }

  Future<void> _delete(int index) async {
    final accepted = await confirmAction(
      context,
      title: 'Delete this bundle?',
      message:
          'The individual listings will remain active. Only this bundle offer will be removed.',
      action: 'Delete Bundle',
      destructive: true,
    );
    if (accepted && mounted) setState(() => bundles.removeAt(index));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Bundle Listings')),
        floatingActionButton: FloatingActionButton.extended(
          key: const Key('create-bundle'),
          onPressed: _create,
          icon: const Icon(Icons.add),
          label: const Text('New Bundle'),
        ),
        body: SafeArea(
          child: bundles.isEmpty
              ? RentHubFeedbackState(
                  kind: FeedbackKind.empty,
                  title: 'No bundles yet',
                  message:
                      'Combine two or more physical-item listings into one discounted offer.',
                  actionLabel: 'Create Bundle',
                  onAction: _create,
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: bundles.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final bundle = bundles[index];
                    final items = bundle.itemIds
                        .map((id) => MockData.listings
                            .firstWhere((listing) => listing.id == id))
                        .toList();
                    final standard = items.fold<double>(
                      0,
                      (total, listing) => total + listing.dailyPrice,
                    );
                    final bundlePrice =
                        standard * (100 - bundle.discount) / 100;
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const CircleAvatar(
                                  backgroundColor: AppColors.primaryLight,
                                  child: Icon(Icons.inventory_2_outlined,
                                      color: AppColors.primaryDark),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(bundle.name,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium),
                                      Text(
                                        '${items.length} items • ${bundle.discount}% bundle discount',
                                        style: const TextStyle(
                                            color: AppColors.secondaryText),
                                      ),
                                    ],
                                  ),
                                ),
                                StatusBadge(
                                    bundle.active ? 'Active' : 'Paused'),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final item in items)
                                  Chip(label: Text(item.title)),
                              ],
                            ),
                            const Divider(height: 24),
                            Text(
                              '${formatBundleMoney(bundlePrice)} / day',
                              style: const TextStyle(
                                color: AppColors.primaryDark,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton(
                                  onPressed: () => setState(
                                    () => bundle.active = !bundle.active,
                                  ),
                                  child:
                                      Text(bundle.active ? 'Pause' : 'Resume'),
                                ),
                                TextButton(
                                  onPressed: () => _delete(index),
                                  child: const Text(
                                    'Delete',
                                    style: TextStyle(color: AppColors.error),
                                  ),
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
      );
}

String formatBundleMoney(double amount) => 'RM ${amount.toStringAsFixed(2)}';

class _CreateBundlePage extends StatefulWidget {
  const _CreateBundlePage({required this.listings});

  final List<Listing> listings;

  @override
  State<_CreateBundlePage> createState() => _CreateBundlePageState();
}

class _CreateBundlePageState extends State<_CreateBundlePage> {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController();
  final selected = <String>{};
  double discount = 10;
  bool submitted = false;

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  void _save() {
    setState(() => submitted = true);
    if (!formKey.currentState!.validate() || selected.length < 2) return;
    InputValidation.popIfValid(
      context,
      _BundleRecord(
        name: name.text.trim(),
        itemIds: selected.toList(),
        discount: discount.round(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Create Bundle')),
        body: SafeArea(
          child: Form(
            key: formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                TextFormField(
                  controller: name,
                  decoration: (const InputDecoration(labelText: 'Bundle name'))
                      .copyWith(counterText: '', errorMaxLines: 3),
                  validator: InputValidation.compose(
                      InputRules.bundleName.validate,
                      (value) => (value?.trim().length ?? 0) < 3
                          ? 'Enter a bundle name'
                          : null),
                  inputFormatters:
                      InputValidation.formatters(InputRules.bundleName, name),
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  maxLength: InputRules.bundleName.maxLength,
                  maxLengthEnforcement: InputValidation.lengthEnforcement,
                ),
                const SizedBox(height: 16),
                Text('Choose at least two items',
                    style: Theme.of(context).textTheme.titleMedium),
                if (submitted && selected.length < 2)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'Select at least two physical-item listings.',
                      style: TextStyle(color: AppColors.error),
                    ),
                  ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      for (final listing in widget.listings)
                        CheckboxListTile(
                          value: selected.contains(listing.id),
                          title: Text(listing.title),
                          subtitle: Text(formatBundleMoney(listing.dailyPrice)),
                          onChanged: (value) => setState(() {
                            value == true
                                ? selected.add(listing.id)
                                : selected.remove(listing.id);
                          }),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text('Discount: ${discount.round()}%'),
                Slider(
                  value: discount,
                  min: 5,
                  max: 25,
                  divisions: 4,
                  label: '${discount.round()}%',
                  onChanged: (value) => setState(() => discount = value),
                ),
                const SizedBox(height: 16),
                RentHubActionButton(
                  key: const Key('save-bundle'),
                  label: 'Save Bundle',
                  onPressed: _save,
                ),
              ],
            ),
          ),
        ),
      );
}
