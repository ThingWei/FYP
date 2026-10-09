import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../shared/models/domain_models.dart';
import 'live_renthub_controller.dart';
import 'live_photo_widgets.dart';

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
        const Text(
            'A high detector score can still be wrong, including on wallpapers and illustrations.'),
        if (evidence.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Item type: ${listing.category}'
              '${listing.subcategory.isEmpty ? '' : ' → ${listing.subcategory}'}'),
          Text(
              'Category check: ${matched == true ? 'Expected type detected' : matched == false ? 'Expected type not detected clearly' : 'Not assessed / unsupported'}'),
          if (fields['matchingViewCount'] is num)
            Text(
                'Expected type detected in ${fields['matchingViewCount']} of ${fields['submittedViewCount']} submitted views.'),
          if (fields['categoryMatchStatus'] == 'partial_views')
            const Text(
                'Partial match only. A high score in one view does not clear the other photos.'),
          const Text(
              'Detection scores are not authenticity probabilities. Check every photo and highlighted box.'),
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
            if ((image['detections'] as List? ?? const []).isEmpty)
              const Text('No supported object detected clearly in this photo.'),
            for (final detection
                in (image['detections'] as List? ?? const []).whereType<Map>())
              Text('${detection['label']}: '
                  '${(((detection['confidence'] as num?)?.toDouble() ?? 0) * 100).toStringAsFixed(0)}% object-detection confidence'
                  '${detection['matchesCategory'] == true ? ' (expected type)' : ''}'),
            if ((image['quality'] as Map?)?['isBlurry'] == true)
              const Text('Quality concern: blurry photo.'),
            if ((image['quality'] as Map?)?['isTooDark'] == true ||
                (image['quality'] as Map?)?['isTooBright'] == true)
              const Text('Quality concern: lighting.'),
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
  final fields =
      listing.itemVerification['extracted_fields'] as Map? ?? const {};
  final evidenceByIndex = <int, Map>{
    for (final image
        in (fields['images'] as List? ?? const []).whereType<Map>())
      ((image['imageIndex'] as num?)?.toInt() ?? 0): image,
  };
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
                    LivePhotoThumbnail(
                        reference: listing.images[index],
                        label: 'Listing photo ${index + 1}',
                        controller: controller,
                        evidence: evidenceByIndex[index],
                        width: 128,
                        height: 128),
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
