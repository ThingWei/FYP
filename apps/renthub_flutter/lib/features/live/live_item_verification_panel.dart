import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../shared/models/domain_models.dart';
import 'live_renthub_controller.dart';

/// Display evidence without turning object confidence into an authenticity score.
class ItemVerificationPanel extends StatelessWidget {
  const ItemVerificationPanel({super.key, required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    if (listing.isService) return const SizedBox.shrink();
    final evidence = listing.itemVerification;
    final fields = evidence['extracted_fields'] as Map? ?? const {};
    final models = fields['models'] as Map? ?? const {};
    final images = (fields['images'] as List? ?? const []).whereType<Map>();
    final concerns =
        (evidence['risk_indicators'] as List? ?? const []).whereType<String>();
    final reasons =
        (evidence['reasons'] as List? ?? const []).whereType<String>();
    final matched = fields['categoryMatched'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(listing.itemPhotoCheckLabel,
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text(
            'Photo checks assist administrator review. They do not prove '
            'authenticity, ownership, exact brand/model or item condition.'),
        if (evidence.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Item type: ${listing.category}'
              '${listing.subcategory.isEmpty ? '' : ' → ${listing.subcategory}'}'),
          Text(
              'Category check: ${matched == true ? 'Expected type detected' : matched == false ? 'Expected type not detected clearly' : 'Not assessed / unsupported'}'),
          Text(
              'Object detector: ${models['detectorAvailable'] == true ? models['detectorSource'] == 'general_pretrained' ? 'General pretrained model (limited coverage)' : 'Configured item model' : 'Unavailable'}'),
          Text(
              'Image-risk classifier: ${models['riskClassifierAvailable'] == true ? 'Available — advisory signal only' : 'Unavailable — not assessed'}'),
          if ((models['riskTrainingSource'] as List? ?? const [])
              .contains('synthetic_manipulation'))
            const Text(
                'Risk training includes synthetic examples; research assistance only.'),
          const Text('Stated condition: requires manual review'),
          for (final concern in concerns)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Review concern: $concern'),
            ),
          for (final reason in reasons)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(reason),
            ),
          for (final image in images) ...[
            const SizedBox(height: 12),
            Text('Photo ${((image['imageIndex'] as num?)?.toInt() ?? 0) + 1}',
                style: Theme.of(context).textTheme.labelLarge),
            for (final detection
                in (image['detections'] as List? ?? const []).whereType<Map>())
              Text('${detection['label']}: '
                  '${(((detection['confidence'] as num?)?.toDouble() ?? 0) * 100).toStringAsFixed(0)}% object-detection confidence'
                  '${detection['matchesCategory'] == true ? ' (expected type)' : ''}'),
            if (image['imageRiskScore'] is num)
              Text('Learned image-risk score: '
                  '${((image['imageRiskScore'] as num) * 100).toStringAsFixed(0)}% (not probability of a fake item)'),
            if (image['detectorUnavailable'] == true ||
                image['riskClassifierUnavailable'] == true)
              const Text('Analysis incomplete for this photo.'),
          ],
        ],
      ],
    );
  }
}

Future<void> showItemPhotoReview(BuildContext context, Listing listing) {
  final controller = context.read<LiveRentHubController>();
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Listing photos & checks'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(listing.title),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var index = 0; index < listing.images.length; index++)
                    SizedBox(
                      width: 128,
                      height: 128,
                      child: FutureBuilder<Uint8List>(
                        future: Future<Uint8List>.sync(() => controller
                            .downloadProtectedUpload(listing.images[index])),
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return Center(
                                child: Text('Photo ${index + 1} unavailable'));
                          }
                          if (!snapshot.hasData) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }
                          return Semantics(
                            label: 'Enlarge listing photo ${index + 1}',
                            button: true,
                            child: InkWell(
                              onTap: () => showDialog<void>(
                                context: context,
                                builder: (context) => Dialog(
                                  child: Column(children: [
                                    Align(
                                      alignment: Alignment.topRight,
                                      child: IconButton(
                                        tooltip: 'Close photo',
                                        onPressed: () => Navigator.pop(context),
                                        icon: const Icon(Icons.close),
                                      ),
                                    ),
                                    Expanded(
                                        child: InteractiveViewer(
                                      child: Image.memory(snapshot.data!,
                                          fit: BoxFit.contain),
                                    )),
                                  ]),
                                ),
                              ),
                              child: Image.memory(snapshot.data!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Center(
                                      child: Text('Photo unavailable'))),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              ItemVerificationPanel(listing: listing),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Close'))
      ],
    ),
  );
}
