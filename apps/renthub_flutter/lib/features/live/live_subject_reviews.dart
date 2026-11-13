import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/network/user_facing_error.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/domain_models.dart';
import '../../shared/widgets/dot_pagination.dart';
import '../../shared/widgets/record_list_header.dart';
import 'live_renthub_controller.dart';
import 'live_rental_progress.dart';

class SubjectReviewsSection extends StatefulWidget {
  const SubjectReviewsSection(
      {super.key, required this.userId, this.role = 'overall'});
  final String userId, role;
  @override
  State<SubjectReviewsSection> createState() => _SubjectReviewsSectionState();
}

class _SubjectReviewsSectionState extends State<SubjectReviewsSection> {
  List<Review> rows = [];
  int page = 1, limit = 20, total = 0, generation = 0;
  bool loading = false, bound = false;
  String? account;
  Object? error;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!bound) {
      bound = true;
      account = context.read<LiveRentHubController>().profile?.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) load();
      });
    }
  }

  @override
  void didUpdateWidget(covariant SubjectReviewsSection old) {
    super.didUpdateWidget(old);
    if (old.userId != widget.userId || old.role != widget.role) {
      generation++;
      rows = [];
      total = 0;
      page = 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) load();
      });
    }
  }

  Future<void> load({int? nextPage, int? nextLimit}) async {
    final c = context.read<LiveRentHubController>();
    if (account == null || c.profile?.id != account) return;
    final request = ++generation, accountGeneration = c.accountGeneration;
    final requestedPage = nextPage ?? page, requestedLimit = nextLimit ?? limit;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await c.api.request(
          'GET',
          '/reviews/subjects/${Uri.encodeComponent(widget.userId)}?${Uri(queryParameters: {
                'role': widget.role,
                'page': '$requestedPage',
                'limit': '$requestedLimit'
              }).query}');
      if (!mounted ||
          request != generation ||
          c.profile?.id != account ||
          c.accountGeneration != accountGeneration) {
        return;
      }
      if (data is! List) throw const FormatException('Invalid review response');
      final count = data is ApiItems ? data.meta['total'] : data.length;
      if (count is! num || !count.isFinite || count < 0 || count % 1 != 0) {
        throw const FormatException('Invalid review total');
      }
      final last = (count / requestedLimit).ceil().clamp(1, 1000000);
      if (requestedPage > last) {
        await load(nextPage: last, nextLimit: requestedLimit);
        return;
      }
      final parsed = data
          .map((r) => Review.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
      setState(() {
        rows = parsed;
        total = count.toInt();
        page = requestedPage;
        limit = requestedLimit;
      });
    } catch (e) {
      if (mounted &&
          request == generation &&
          c.profile?.id == account &&
          c.accountGeneration == accountGeneration) {
        setState(() => error = e);
      }
    } finally {
      if (mounted && request == generation) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (account == null ||
        context.watch<LiveRentHubController>().profile?.id != account) {
      return const SizedBox.shrink();
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Reviews about this user',
          style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      if (loading) const LinearProgressIndicator(),
      if (error != null)
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(friendlyError(error!)),
          TextButton(
              onPressed: loading ? null : load,
              child: const Text('Retry reviews'))
        ]),
      RecordListHeader(
          summary: '$total published review${total == 1 ? '' : 's'}',
          limit: limit,
          loading: loading,
          onLimit: (value) => load(nextPage: 1, nextLimit: value)),
      if (!loading && error == null && rows.isEmpty)
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('No published reviews yet.')),
      for (final review in rows)
        Card(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Icon(Icons.star,
                                color: AppColors.warning, size: 20),
                            Text('${review.rating} / 5',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            Text(review.authorName),
                          ]),
                      if (review.subjectRole.isNotEmpty)
                        Text(
                            review.subjectRole == 'owner'
                                ? 'Review as Owner'
                                : 'Review as renter',
                            style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 8),
                      Text(review.text),
                      if (review.listingTitle.isNotEmpty)
                        Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(review.listingTitle,
                                style: Theme.of(context).textTheme.bodySmall)),
                      Text(rentalEventTime(review.createdAt),
                          style: Theme.of(context).textTheme.bodySmall),
                    ]))),
      if (total > 0)
        DotPagination(
            page: page,
            pageCount: (total / limit).ceil(),
            loading: loading,
            onPage: (value) => load(nextPage: value)),
    ]);
  }
}
