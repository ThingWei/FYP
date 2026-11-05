import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';

import '../../shared/models/domain_models.dart';
import 'live_renthub_controller.dart';
import 'live_photo_widgets.dart';
import 'live_item_photo_summary.dart';

/// Display evidence without turning object confidence into an authenticity score.
class ItemVerificationPanel extends StatelessWidget {
  const ItemVerificationPanel(
      {super.key,
      required this.listing,
      this.showDiagnostics = false,
      this.selectedPhotoIndex});

  final Listing listing;
  final bool showDiagnostics;
  final int? selectedPhotoIndex;

  @override
  Widget build(BuildContext context) {
    if (listing.isService) return const SizedBox.shrink();
    final summary = ItemPhotoSummary(listing);
    final notes = summary.notes;
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(12)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(listing.itemPhotoCheckLabel,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(summary.explanation),
                    for (final note in notes.take(3))
                      Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.info_outline,
                                    size: 20, color: AppColors.secondaryText),
                                const SizedBox(width: 8),
                                Expanded(child: Text(note)),
                              ])),
                  ])),
          const SizedBox(height: 12),
          Text('Photos alone cannot prove an item is genuine or who owns it.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.secondaryText)),
          const SizedBox(height: 8),
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
                            const SizedBox(height: 8),
                            Text(summary.typeSummary),
                            const SizedBox(height: 8),
                            for (final note in notes.skip(3))
                              Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text('• $note')),
                            for (var index = 0;
                                index < summary.images.length;
                                index++)
                              if (selectedPhotoIndex == null ||
                                  _photoNumber(summary.images[index], index) -
                                          1 ==
                                      selectedPhotoIndex)
                                Container(
                                    width: double.infinity,
                                    margin: const EdgeInsets.only(top: 12),
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                        color: AppColors.surface,
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                              'Photo ${_photoNumber(summary.images[index], index)}',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleSmall),
                                          const SizedBox(height: 8),
                                          for (final note in summary
                                              .photoNote(summary.images[index])
                                              .split(' \u00b7 '))
                                            Padding(
                                                padding: const EdgeInsets.only(
                                                    bottom: 8),
                                                child: Text(note)),
                                        ])),
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
        {bool showDiagnostics = false}) =>
    showDialog<void>(
        context: context,
        builder: (_) => _ItemPhotoReviewDialog(
            listing: listing,
            controller: context.read<LiveRentHubController>(),
            showDiagnostics: showDiagnostics));

class _ItemPhotoReviewDialog extends StatefulWidget {
  const _ItemPhotoReviewDialog(
      {required this.listing,
      required this.controller,
      required this.showDiagnostics});
  final Listing listing;
  final LiveRentHubController controller;
  final bool showDiagnostics;
  @override
  State<_ItemPhotoReviewDialog> createState() => _ItemPhotoReviewDialogState();
}

class _ItemPhotoReviewDialogState extends State<_ItemPhotoReviewDialog> {
  final pages = PageController();
  int selected = 0;
  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  void move(int index) => pages.animateToPage(index,
      duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  @override
  Widget build(BuildContext context) {
    final listing = widget.listing;
    final images = ItemPhotoSummary(listing).images;
    final evidenceByIndex = <int, Map>{
      for (var index = 0; index < images.length; index++)
        ItemVerificationPanel._photoNumber(images[index], index) - 1:
            images[index],
    };
    final screen = MediaQuery.sizeOf(context);
    return Dialog(
        backgroundColor: AppColors.background,
        insetPadding: EdgeInsets.symmetric(
            horizontal: screen.width < 600 ? 12 : 32, vertical: 24),
        child: ConstrainedBox(
            constraints:
                BoxConstraints(maxWidth: 720, maxHeight: screen.height - 48),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
                  child: Row(children: [
                    Expanded(
                        child: Text('Item photos',
                            style: Theme.of(context).textTheme.titleLarge)),
                    IconButton(
                        tooltip: 'Close item photos',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close)),
                  ])),
              const Divider(height: 1),
              Flexible(
                  child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(listing.title,
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 16),
                            if (listing.images.isEmpty)
                              const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 24),
                                  child: Text('No photos added yet.'))
                            else ...[
                              LayoutBuilder(
                                  builder: (context, box) => SizedBox(
                                      height: (box.maxWidth * 0.75).clamp(
                                          120.0,
                                          (screen.height * 0.42)
                                              .clamp(120.0, 360.0)),
                                      child: PageView.builder(
                                        controller: pages,
                                        itemCount: listing.images.length,
                                        onPageChanged: (index) =>
                                            setState(() => selected = index),
                                        itemBuilder: (context, index) => Padding(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 2),
                                            child: LivePhotoThumbnail(
                                                key: ValueKey(
                                                    '$index:${listing.images[index]}'),
                                                reference:
                                                    listing.images[index],
                                                label:
                                                    'Listing photo ${index + 1}',
                                                controller: widget.controller,
                                                evidence:
                                                    evidenceByIndex[index],
                                                width: box.maxWidth,
                                                height: double.infinity)),
                                      ))),
                              Row(children: [
                                IconButton(
                                    tooltip: 'Previous photo',
                                    onPressed: selected > 0
                                        ? () => move(selected - 1)
                                        : null,
                                    icon: const Icon(Icons.chevron_left)),
                                Expanded(
                                    child: Semantics(
                                        liveRegion: true,
                                        child: Text(
                                            'Photo ${selected + 1} of ${listing.images.length}',
                                            textAlign: TextAlign.center))),
                                IconButton(
                                    tooltip: 'Next photo',
                                    onPressed:
                                        selected + 1 < listing.images.length
                                            ? () => move(selected + 1)
                                            : null,
                                    icon: const Icon(Icons.chevron_right)),
                              ]),
                              const Center(
                                  child: Text(
                                      'Swipe to browse. Tap a photo to enlarge.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: AppColors.secondaryText))),
                            ],
                            const SizedBox(height: 24),
                            ItemVerificationPanel(
                                listing: listing,
                                selectedPhotoIndex: selected,
                                showDiagnostics: widget.showDiagnostics),
                          ]))),
              const Divider(height: 1),
              Padding(
                  padding: const EdgeInsets.all(12),
                  child: Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Close')))),
            ])));
  }
}
