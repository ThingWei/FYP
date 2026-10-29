import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/domain_models.dart';
import 'live_renthub_controller.dart';
import 'user_record_pagination.dart';

class LiveReviewsListPage extends StatefulWidget {
  const LiveReviewsListPage(
      {super.key, this.listingId, this.received = false, this.onFlag});
  final String? listingId;
  final bool received;
  final ValueChanged<Review>? onFlag;
  @override
  State<LiveReviewsListPage> createState() => _LiveReviewsListPageState();
}

class _LiveReviewsListPageState extends State<LiveReviewsListPage> {
  String? account;
  bool bound = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!bound) {
      account = context.read<LiveRentHubController>().profile?.id;
      bound = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<LiveRentHubController>(),
        key = widget.listingId == null
            ? widget.received
                ? 'received-reviews'
                : 'reviews'
            : 'listing-reviews:${widget.listingId}';
    if (c.profile?.id != account) {
      return Scaffold(
          appBar: AppBar(title: const Text('Reviews')),
          body: const Center(
              child: Text('Your session changed. Return to the app.')));
    }
    final rows = widget.listingId != null
        ? c.listingReviewPages[widget.listingId] ?? const <Review>[]
        : widget.received
            ? c.receivedReviews
            : c.reviews;
    return Scaffold(
        appBar: AppBar(
            title: Text(widget.listingId != null
                ? 'Listing reviews'
                : widget.received
                    ? 'Reviews received'
                    : 'My reviews')),
        bottomNavigationBar: UserRecordPagination(collection: key),
        body: RefreshIndicator(
            onRefresh: () => c.loadUserRecords(key),
            child: rows.isEmpty
                ? ListView(children: [
                    Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(c.userRecordPages[key]?.loading == true
                            ? 'Loading reviews…'
                            : 'No reviews on this page.'))
                  ])
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final r = rows[i];
                      return Card(
                          child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      const Icon(Icons.star,
                                          color: AppColors.warning),
                                      const SizedBox(width: 8),
                                      Expanded(
                                          child: Text(
                                              '${r.rating} / 5 · ${r.authorName}')),
                                      if (widget.onFlag != null && !r.flagged)
                                        IconButton(
                                            tooltip: 'Flag review',
                                            onPressed: () => widget.onFlag!(r),
                                            icon:
                                                const Icon(Icons.flag_outlined))
                                    ]),
                                    Text(r.listingTitle,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall),
                                    const SizedBox(height: 8),
                                    Text(r.text)
                                  ])));
                    })));
  }
}
