import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/domain_models.dart';
import '../../shared/widgets/account_components.dart';
import '../../shared/widgets/renthub_components.dart';
import 'live_renthub_controller.dart';

class LiveReviewPage extends StatefulWidget {
  const LiveReviewPage({
    super.key,
    required this.rental,
    required this.subject,
    this.existing,
    this.reviewingRenter = false,
  });

  final Rental rental;
  final String subject;
  final Review? existing;
  final bool reviewingRenter;

  @override
  State<LiveReviewPage> createState() => _LiveReviewPageState();
}

class _LiveReviewPageState extends State<LiveReviewPage> {
  late int overall;
  late int communication;
  late int condition;
  late int value;
  bool submitting = false;
  late final TextEditingController comment;

  @override
  void initState() {
    super.initState();
    overall = widget.existing?.rating ?? 5;
    communication = overall;
    condition = overall;
    value = overall;
    comment = TextEditingController(text: widget.existing?.text ?? '');
  }

  @override
  void dispose() {
    comment.dispose();
    super.dispose();
  }

  Widget _rating(String label, int current, ValueChanged<int> onChanged) => Row(
        children: [
          Expanded(child: Text(label)),
          DropdownButton<int>(
            value: current,
            items: [
              for (var rating = 1; rating <= 5; rating++)
                DropdownMenuItem(
                  value: rating,
                  child: Text('$rating / 5'),
                ),
            ],
            onChanged: submitting
                ? null
                : (rating) {
                    if (rating != null) onChanged(rating);
                  },
          ),
        ],
      );

  Future<void> _submit() async {
    if (comment.text.trim().length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter at least 10 characters.')),
      );
      return;
    }
    setState(() => submitting = true);
    try {
      final controller = context.read<LiveRentHubController>();
      if (widget.existing == null) {
        await controller.submitReview(
          rental: widget.rental,
          overallRating: overall,
          communicationRating: communication,
          conditionRating: widget.reviewingRenter ? null : condition,
          valueRating: widget.reviewingRenter ? null : value,
          text: comment.text,
        );
      } else {
        await controller.editReview(
          existing: widget.existing!,
          rental: widget.rental,
          overallRating: overall,
          communicationRating: communication,
          conditionRating: widget.reviewingRenter ? null : condition,
          valueRating: widget.reviewingRenter ? null : value,
          text: comment.text,
        );
      }
      if (!mounted) return;
      showMockSuccess(
        context,
        widget.existing == null
            ? 'Review saved to MongoDB'
            : 'Review updated in MongoDB',
      );
      Navigator.pop(context);
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(exception.toString())));
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title:
              Text(widget.existing == null ? 'Rate & Review' : 'Edit Review'),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        widget.subject,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.rental.listingType == 'service'
                            ? 'Completed service order'
                            : 'Completed physical rental',
                        style: const TextStyle(color: AppColors.secondaryText),
                      ),
                      const SizedBox(height: 16),
                      _rating('Overall', overall,
                          (rating) => setState(() => overall = rating)),
                      _rating(
                        'Communication',
                        communication,
                        (rating) => setState(() => communication = rating),
                      ),
                      if (!widget.reviewingRenter &&
                          widget.rental.listingType == 'physical')
                        _rating('Item condition', condition,
                            (rating) => setState(() => condition = rating)),
                      if (!widget.reviewingRenter)
                        _rating('Value', value,
                            (rating) => setState(() => value = rating)),
                      const SizedBox(height: 12),
                      TextField(
                        controller: comment,
                        minLines: 3,
                        maxLines: 6,
                        maxLength: 1500,
                        decoration: const InputDecoration(
                          labelText: 'Review',
                          hintText: 'Describe your completed experience',
                        ),
                      ),
                      const SizedBox(height: 16),
                      RentHubActionButton(
                        label: widget.existing == null
                            ? 'Submit Review'
                            : 'Update Review',
                        loading: submitting,
                        onPressed: submitting ? null : _submit,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'You can edit a submitted review through the API for 24 hours. Administrative moderation remains auditable.',
                        style: TextStyle(
                          color: AppColors.secondaryText,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}
