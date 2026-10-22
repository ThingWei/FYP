import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../shared/models/domain_models.dart';
import 'live_renthub_controller.dart';
import 'live_photo_widgets.dart';
import 'live_item_photo_summary.dart';

/// Display evidence without turning object confidence into an authenticity score.
class ItemVerificationPanel extends StatelessWidget {
  const ItemVerificationPanel(
      {super.key, required this.listing, this.showDiagnostics = false});

  final Listing listing;
  final bool showDiagnostics;

  @override
  Widget build(BuildContext context) {
    if (listing.isService) return const SizedBox.shrink();
    final summary = ItemPhotoSummary(listing);
    final notes = summary.notes;
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(listing.itemPhotoCheckLabel,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(summary.explanation),
          for (final note in notes.take(3))
            Padding(
                padding: const EdgeInsets.only(top: 8), child: Text('• $note')),
          const SizedBox(height: 12),
          Text('Photos alone cannot prove an item is genuine or who owns it.',
              style: Theme.of(context).textTheme.bodySmall),
          if (summary.evidence.isNotEmpty)
            ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Photo details'),
                childrenPadding: const EdgeInsets.only(bottom: 12),
                children: [
                  Align(
                      alignment: Alignment.centerLeft,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                '${listing.category}${listing.subcategory.isEmpty ? '' : ' · ${listing.subcategory}'}'),
                            Text(summary.typeSummary),
                            for (final note in notes.skip(3))
                              Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text('• $note')),
                            for (var index = 0;
                                index < summary.images.length;
                                index++)
                              Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                      'Photo ${_photoNumber(summary.images[index], index)}: ${summary.photoNote(summary.images[index])}')),
                          ]))
                ]),
          if (showDiagnostics && summary.evidence.isNotEmpty)
            ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Technical details'),
                children: [
                  Align(
                      alignment: Alignment.centerLeft,
                      child: _ItemTechnicalDetails(listing: listing))
                ]),
        ]);
  }

  static int _photoNumber(Map image, int fallback) {
    final index = image['imageIndex'];
    return index is num &&
            index.isFinite &&
            index >= 0 &&
            index == index.roundToDouble()
        ? index.toInt() + 1
        : fallback + 1;
  }
}

/// Raw model evidence is deliberately opt-in on the administrator review screen.
class _ItemTechnicalDetails extends StatelessWidget {
  const _ItemTechnicalDetails({required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    if (listing.isService) return const SizedBox.shrink();
    final evidence = listing.itemVerification;
    final summary = ItemPhotoSummary(listing);
    final fields = summary.fields;
    final models = summary.models;
    final images = summary.images;
    final concerns = summary.concerns;
    final reasons = summary.reasons;
    final matched = fields['categoryMatched'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (evidence.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Item type: ${listing.category}'
              '${listing.subcategory.isEmpty ? '' : ' → ${listing.subcategory}'}'),
          Text(
              'Category check: ${matched == true ? 'Possible expected type detected, not verified' : matched == false ? 'Expected type not detected clearly' : 'Not established / unsupported'}'),
          if (fields['matchingViewCount'] is num)
            Text(
                'Possible expected type detected in ${fields['matchingViewCount']} of ${fields['submittedViewCount']} submitted views.'),
          if (fields['categoryMatchStatus'] == 'partial_views')
            const Text(
                'Partial match only. A high score in one view does not clear the other photos.'),
          const Text(
              'Detection scores are not authenticity probabilities. Check every photo and highlighted box.'),
          const Text(
              'A matching object label does not establish that this is a photo of the listed physical item.'),
          Text(
              'Object detector: ${models['detectorAvailable'] == true ? models['detectorSource'] == 'general_pretrained' ? 'General pretrained model (limited coverage)' : 'Configured item model' : 'Unavailable'}'),
          for (final detector in ItemPhotoSummary.maps(models['detectors']))
            Text(
                'Detection source: ${detector['source']} (${detector['version']})'),
          if (ItemPhotoSummary.map(fields['categoryCoverage']).isNotEmpty) ...[
            Text(
                'Category coverage: ${ItemPhotoSummary.map(fields['categoryCoverage'])['status']}'),
            const Text(
                'Label coverage is not measured subcategory accuracy. Book genre, garment type and exact product identity still require review.'),
          ],
          Text(
              'Image-risk classifier: ${models['riskClassifierAvailable'] == true ? 'Available — advisory signal only' : 'Unavailable — not assessed'}'),
          if (ItemPhotoSummary.strings(models['riskTrainingSource'])
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
            Text(
                'Photo ${ItemVerificationPanel._photoNumber(image, images.indexOf(image))}',
                style: Theme.of(context).textTheme.labelLarge),
            if (ItemPhotoSummary.maps(image['detections']).isEmpty)
              const Text('No supported object detected clearly in this photo.'),
            for (final detection in ItemPhotoSummary.maps(image['detections']))
              Text('${detection['label']}: '
                  '${(((detection['confidence'] as num?)?.toDouble() ?? 0) * 100).toStringAsFixed(0)}% object-detection confidence'
                  '${detection['matchesCategory'] == true ? ' (expected type)' : ''}'
                  '${detection['rotationDegrees'] is num && detection['rotationDegrees'] != 0 ? ' · rotation ${detection['rotationDegrees']}°' : ''}'),
            if (ItemPhotoSummary.map(image['quality'])['isBlurry'] == true)
              const Text('Quality concern: blurry photo.'),
            if (ItemPhotoSummary.map(image['quality'])['isTooDark'] == true ||
                ItemPhotoSummary.map(image['quality'])['isTooBright'] == true)
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

Future<void> showItemPhotoReview(BuildContext context, Listing listing,
    {bool showDiagnostics = false}) {
  final controller = context.read<LiveRentHubController>();
  final fields =
      ItemPhotoSummary.map(listing.itemVerification['extracted_fields']);
  final images = ItemPhotoSummary.maps(fields['images']);
  final evidenceByIndex = <int, Map>{
    for (var index = 0; index < images.length; index++)
      ItemVerificationPanel._photoNumber(images[index], index) - 1:
          images[index],
  };
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Item photos'),
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
              ItemVerificationPanel(
                  listing: listing, showDiagnostics: showDiagnostics),
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
