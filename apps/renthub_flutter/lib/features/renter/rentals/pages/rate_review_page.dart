import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/account_components.dart';
import '../../../../shared/widgets/renthub_components.dart';
import '../../shared/widgets/renter_flow_components.dart';

class ReviewSubmissionPage extends StatefulWidget {
  const ReviewSubmissionPage({
    super.key,
    required this.subject,
    required this.ownerName,
    this.service = false,
  });

  final String subject;
  final String ownerName;
  final bool service;

  @override
  State<ReviewSubmissionPage> createState() => _ReviewSubmissionPageState();
}

class _ReviewSubmissionPageState extends State<ReviewSubmissionPage> {
  int rating = 5;
  final review = TextEditingController();

  @override
  void dispose() {
    review.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Rate & Review')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              RenterFlowCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(widget.subject,
                        style: Theme.of(context).textTheme.titleMedium),
                    Text(widget.ownerName,
                        style: const TextStyle(color: AppColors.secondaryText)),
                    const SizedBox(height: 16),
                    Wrap(
                      alignment: WrapAlignment.center,
                      children: [
                        for (var i = 1; i <= 5; i++)
                          IconButton(
                            tooltip: '$i stars',
                            onPressed: () => setState(() => rating = i),
                            icon: Icon(
                              i <= rating ? Icons.star : Icons.star_border,
                              color: AppColors.warning,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: review,
                      minLines: 3,
                      maxLines: 5,
                      decoration: InputDecoration(
                        labelText: widget.service
                            ? 'Review the service'
                            : 'Review the rental and Owner',
                      ),
                    ),
                    const SizedBox(height: 20),
                    RentHubActionButton(
                      label: 'Submit Review',
                      onPressed: () {
                        showMockSuccess(context, 'Review submitted');
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}
