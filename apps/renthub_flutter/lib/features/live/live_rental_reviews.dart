import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/user_facing_error.dart';
import '../../shared/models/domain_models.dart';
import 'live_rental_progress.dart';
import 'live_renthub_controller.dart';
import 'live_review_page.dart';
import 'live_subject_reviews.dart';

class RentalReviewPair {
  const RentalReviewPair({this.written, this.received});
  final Review? written, received;
  factory RentalReviewPair.fromJson(dynamic value) {
    if (value is! Map ||
        !value.containsKey('writtenReview') ||
        !value.containsKey('receivedReview')) {
      throw const FormatException('Invalid review response');
    }
    Review? parse(dynamic row) => row == null
        ? null
        : Review.fromJson(Map<String, dynamic>.from(row as Map));
    return RentalReviewPair(
        written: parse(value['writtenReview']),
        received: parse(value['receivedReview']));
  }
}

class RentalReviewsButton extends StatelessWidget {
  const RentalReviewsButton(
      {super.key, required this.rental, this.owner = false});
  final Rental rental;
  final bool owner;
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
      onPressed: () => Navigator.push<void>(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  LiveRentalReviewsPage(rental: rental, owner: owner))),
      icon: const Icon(Icons.rate_review_outlined),
      label: const Text('Reviews'));
}

class LiveRentalReviewsPage extends StatefulWidget {
  const LiveRentalReviewsPage(
      {super.key, required this.rental, this.owner = false});
  final Rental rental;
  final bool owner;
  @override
  State<LiveRentalReviewsPage> createState() => _LiveRentalReviewsPageState();
}

class _LiveRentalReviewsPageState extends State<LiveRentalReviewsPage> {
  RentalReviewPair? pair;
  bool loading = true;
  Object? error;
  late final int account;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    account = context.read<LiveRentHubController>().accountGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) load();
    });
  }

  bool allowed(LiveRentHubController c) =>
      c.accountGeneration == account &&
      c.profile?.id ==
          (widget.owner ? widget.rental.ownerId : widget.rental.renterId);
  Future<void> load() async {
    final c = context.read<LiveRentHubController>(), request = ++generation;
    if (!allowed(c)) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = RentalReviewPair.fromJson(await c.api.request(
          'GET', '/reviews/rental/${Uri.encodeComponent(widget.rental.id)}'));
      if (mounted && allowed(c) && request == generation) {
        setState(() => pair = result);
      }
    } catch (e) {
      if (mounted && allowed(c) && request == generation) {
        setState(() => error = e);
      }
    } finally {
      if (mounted && allowed(c) && request == generation) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> edit(Review? existing) async {
    await Navigator.push<void>(
        context,
        MaterialPageRoute(
            builder: (_) => LiveReviewPage(
                rental: widget.rental,
                subject: widget.owner ? 'Renter review' : 'Owner review',
                reviewingRenter: widget.owner,
                existing: existing)));
    if (mounted) await load();
  }

  Widget reviewCard(String title, Review? review) => Card(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (review == null)
              const Text('No review yet.')
            else ...[
              Row(children: [
                for (var i = 1; i <= 5; i++)
                  Icon(i <= review.rating ? Icons.star : Icons.star_outline,
                      size: 20, color: Theme.of(context).colorScheme.primary)
              ]),
              const SizedBox(height: 8),
              Text(reviewAuthorLabel(review)),
              Text(rentalEventTime(review.createdAt),
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              Text(review.text),
              if (review.status != 'published')
                const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Not published')),
            ],
          ])));
  @override
  Widget build(BuildContext context) {
    final c = context.watch<LiveRentHubController>(), saved = pair;
    return Scaffold(
        appBar: AppBar(title: const Text('Reviews')),
        body: !allowed(c)
            ? const Center(
                child: Text('These reviews are unavailable to this account.'))
            : Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child:
                        ListView(padding: const EdgeInsets.all(16), children: [
                      if (loading) const LinearProgressIndicator(),
                      if (error != null)
                        Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(friendlyError(error!)),
                              TextButton(
                                  onPressed: loading ? null : load,
                                  child: const Text('Retry'))
                            ]),
                      if (saved != null) ...[
                        reviewCard('Your review', saved.written),
                        if (!loading &&
                            error == null &&
                            widget.rental.status == 'completed' &&
                            (saved.written == null || saved.written!.canEdit))
                          TextButton.icon(
                              onPressed: () => edit(saved.written),
                              icon: const Icon(Icons.edit_outlined),
                              label: Text(saved.written == null
                                  ? widget.owner
                                      ? 'Review renter'
                                      : 'Review Owner'
                                  : 'Edit your review')),
                        const SizedBox(height: 16),
                        reviewCard(
                            widget.owner ? "Renter's review" : "Owner's review",
                            saved.received),
                      ],
                    ]))));
  }
}
