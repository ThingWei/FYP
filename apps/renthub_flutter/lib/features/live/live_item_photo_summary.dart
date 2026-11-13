import '../../shared/models/domain_models.dart';

/// Presentation only. Never changes an AI result or the moderation decision.
class ItemPhotoSummary {
  ItemPhotoSummary(this.listing);
  final Listing listing;

  static String photoGuidance(String category) => switch (category) {
        'Books' =>
          'Show the cover, spine or back cover, and an inside page. Keep the page edges visible.',
        'Clothing' =>
          'Show the whole garment, its other side, and the fabric or care label.',
        'Devices' =>
          'Show the whole device, its other side, and details such as ports or labels.',
        'Vehicles' =>
          'Show the whole vehicle, another angle, and details of its condition.',
        _ =>
          'Show the whole item, another angle, and useful details such as attachments or labels.',
      };

  static Map map(Object? value) => value is Map ? value : const {};
  static List<Map> maps(Object? value) =>
      value is List ? value.whereType<Map>().toList() : const [];
  static List<String> strings(Object? value) =>
      value is List ? value.whereType<String>().toList() : const [];

  Map get evidence => listing.itemVerification;
  Map get fields => map(evidence['extracted_fields']);
  Map get models => map(fields['models']);
  List<Map> get images => maps(fields['images']);
  List<String> get concerns => strings(evidence['risk_indicators']);
  List<String> get reasons => strings(evidence['reasons']);
  String get _signals => [...concerns, ...reasons].join(' ').toLowerCase();

  String get explanation => switch (listing.itemVerificationOutcome) {
        'approved' ||
        'approved_candidate' =>
          'No issues were flagged in these photos.',
        'unavailable' =>
          'The photo check could not be completed. Admin review is needed.',
        'warning' ||
        'rejected' ||
        'rescan_required' =>
          'Review the photo notes below.',
        'manual_review' => 'An admin needs to take a closer look.',
        _ => 'Your photos will be checked when you submit the listing.',
      };

  bool _qualityFlag(String flag) =>
      images.any((image) => map(image['quality'])[flag] == true);

  bool get _contextNeedsReview =>
      fields['photoContextReviewRequired'] == true ||
      fields['categoryMatchStatus'] == 'context_needs_review' ||
      images.any((image) =>
          map(image['photoContext'])['status'] == 'needs_review' ||
          image['objectEvidenceStatus'] == 'context_needs_review');

  bool get _rotationNeedsReview => images.any((image) =>
      map(image['photoContext'])['rotationEvidenceReviewRequired'] == true);

  bool get _depictedNeedsReview => images.any((image) {
        final context = map(image['photoContext']);
        return context['depictedContentReviewRequired'] == true ||
            ((context['status'] == 'needs_review' ||
                    image['objectEvidenceStatus'] == 'context_needs_review') &&
                context['rotationEvidenceReviewRequired'] != true);
      });

  List<String> get notes {
    final result = <String>[];
    if (_rotationNeedsReview) {
      result.add(
          'The item type is unclear in some photos. An admin will take a closer look.');
    }
    if (_depictedNeedsReview ||
        (_contextNeedsReview && !_rotationNeedsReview)) {
      result.add(
          'Some photos may show a document, illustration or screen. Include clear photos of the actual item.');
    }
    if (_contextNeedsReview) {
      result.add(photoGuidance(listing.category));
    }
    if (_signals.contains('at least three')) {
      result.add('Add at least three clear photos from different angles.');
    }
    if (_qualityFlag('isBlurry')) result.add('Retake blurry photos.');
    if (_qualityFlag('isTooDark') || _qualityFlag('isTooBright')) {
      result.add('Use even lighting so the item is easy to see.');
    }
    if (images.any(
        (image) => map(image['quality'])['hasUsableResolution'] == false)) {
      result.add('Upload clearer, higher-quality photos.');
    }
    if ((map(evidence['quality'])['duplicateCount'] is num &&
            (map(evidence['quality'])['duplicateCount'] as num) > 0) ||
        _signals.contains('repeated') ||
        _signals.contains('visually similar')) {
      result.add('Replace repeated photos with different views.');
    }
    if (fields['categoryMatchStatus'] == 'partial_views' ||
        fields['categoryMatchStatus'] == 'not_detected' ||
        fields['categoryMatched'] == false) {
      result.add(
          'Some views could not be identified automatically. An admin will review them.');
      result.add(photoGuidance(listing.category));
    }
    if (fields['categoryMatchStatus'] == 'unsupported') {
      result.add('This item type needs a manual check.');
      result.add(photoGuidance(listing.category));
    }
    if (fields['openVocabularyEvidenceUsed'] == true) {
      result.add('An admin will check the suggested item type.');
    }
    if (fields['syntheticRiskOnly'] == true) {
      result
          .add('The photo-risk check is experimental. Admin review is needed.');
    }
    if (result.isEmpty && _signals.contains('focus, lighting or resolution')) {
      result.add('Use clear, well-lit photos of the whole item.');
    }
    if (concerns.isNotEmpty && result.isEmpty) {
      result.add('Some photos need a closer look during review.');
    }
    if (models['detectorAvailable'] == false ||
        models['riskClassifierAvailable'] == false ||
        fields['categoryMatchStatus'] == 'analysis_incomplete' ||
        images.any((image) =>
            image['detectorUnavailable'] == true ||
            image['riskClassifierUnavailable'] == true)) {
      result.add('Some photo checks are unavailable. Admin review is needed.');
    }
    return result.toSet().toList();
  }

  String get typeSummary {
    if (_contextNeedsReview) return 'Photo content needs review.';
    if (fields['categoryMatchStatus'] == 'unsupported' ||
        models['detectorAvailable'] == false) {
      return 'Item type needs a manual check.';
    }
    final matched = fields['matchingViewCount'];
    final total = fields['submittedViewCount'];
    if (matched is num &&
        total is num &&
        matched.isFinite &&
        total.isFinite &&
        matched == matched.roundToDouble() &&
        total == total.roundToDouble() &&
        total > 0 &&
        matched >= 0 &&
        matched <= total) {
      return matched == 0
          ? 'Item type could not be identified.'
          : 'Possible item type detected in ${matched.toInt()} of ${total.toInt()} photos. Admin review is needed.';
    }
    return fields['categoryMatched'] == true &&
            fields['categoryMatchStatus'] != 'analysis_incomplete'
        ? 'Possible item type detected. Admin review is needed.'
        : 'Item type needs review.';
  }

  String photoNote(Map image) {
    final quality = map(image['quality']);
    final notes = <String>[];
    if (quality['isBlurry'] == true) notes.add('Retake for a clearer photo');
    if (quality['isTooDark'] == true || quality['isTooBright'] == true) {
      notes.add('Improve lighting');
    }
    if (quality['hasUsableResolution'] == false) {
      notes.add('Use a higher-quality photo');
    }
    if (image['detectorUnavailable'] == true ||
        image['riskClassifierUnavailable'] == true) {
      notes.add('Checks incomplete');
    }
    final context = map(image['photoContext']);
    final rotationReview = context['rotationEvidenceReviewRequired'] == true;
    if (rotationReview) {
      notes.add('Item type needs a closer look');
    }
    if (context['depictedContentReviewRequired'] == true ||
        (!rotationReview &&
            (context['status'] == 'needs_review' ||
                image['objectEvidenceStatus'] == 'context_needs_review'))) {
      notes.add('Document or on-screen content needs review');
    } else if (!rotationReview && image['categoryMatched'] == true) {
      notes.add('Possible item type detected; not a confirmed match');
    } else if (image['categoryMatched'] == false) {
      notes.add('Item type needs manual review');
    } else if (image['objectEvidenceStatus'] == 'not_detected' ||
        image['objectEvidenceStatus'] == 'category_not_covered') {
      notes.add('Item type needs manual review');
    }
    return notes.isEmpty ? 'Needs a closer look' : notes.join(' · ');
  }
}

/// Administrator findings describe saved evidence, not how an Owner should
/// retake photos. These are presentation labels, never moderation decisions.
class AdminItemPhotoSummary extends ItemPhotoSummary {
  AdminItemPhotoSummary(super.listing);

  @override
  String get explanation => evidence.isEmpty
      ? 'No saved photo check is available.'
      : listing.itemVerificationOutcome == 'unavailable'
          ? 'Photo analysis is unavailable; no automated conclusion is available.'
          : typeSummary;

  @override
  String get typeSummary {
    if (evidence.isEmpty) return 'No saved item-type result is available.';
    if (_depictedNeedsReview ||
        (_contextNeedsReview && !_rotationNeedsReview)) {
      return 'A document, illustration or screen may be present; the listed item is not confirmed.';
    }
    if (_rotationNeedsReview) {
      return 'Item-type evidence is uncertain; a match is not established.';
    }
    if (fields['categoryMatchStatus'] == 'unsupported') {
      return 'This item type is outside the available automatic checks.';
    }
    if (models['detectorAvailable'] == false ||
        fields['categoryMatchStatus'] == 'analysis_incomplete') {
      return 'Item-type analysis is incomplete; a match is not established.';
    }
    final matched = fields['matchingViewCount'];
    final total = fields['submittedViewCount'];
    if (matched is num &&
        total is num &&
        matched.isFinite &&
        total.isFinite &&
        matched == matched.roundToDouble() &&
        total == total.roundToDouble() &&
        total > 0 &&
        matched >= 0 &&
        matched <= total) {
      return matched == 0
          ? 'The listed item type was not identified clearly.'
          : 'Possible item type detected in ${matched.toInt()} of ${total.toInt()} photos; not a confirmed match.';
    }
    if (fields['categoryMatched'] == true) {
      return 'Possible item type detected; not a confirmed match.';
    }
    return fields['categoryMatched'] == false ||
            fields['categoryMatchStatus'] == 'not_detected'
        ? 'The listed item type was not identified clearly.'
        : 'Item type could not be established from the saved checks.';
  }

  @override
  List<String> get notes {
    final result = <String>[];
    if (_rotationNeedsReview) {
      result.add('Item-type evidence is uncertain in some views.');
    }
    if (_depictedNeedsReview ||
        (_contextNeedsReview && !_rotationNeedsReview)) {
      result.add(
          'Some photos may contain a document, illustration or on-screen content.');
    }
    if (_signals.contains('at least three')) {
      result.add('The submitted views were flagged as insufficient.');
    }
    if (_qualityFlag('isBlurry')) result.add('Some photos appear blurry.');
    if (_qualityFlag('isTooDark') || _qualityFlag('isTooBright')) {
      result.add('Lighting may obscure item details.');
    }
    if (images.any((image) =>
        ItemPhotoSummary.map(image['quality'])['hasUsableResolution'] ==
        false)) {
      result.add('Some photos have low resolution.');
    }
    final duplicates =
        ItemPhotoSummary.map(evidence['quality'])['duplicateCount'];
    if ((duplicates is num && duplicates > 0) ||
        _signals.contains('repeated') ||
        _signals.contains('visually similar')) {
      result.add('Possible repeated photos detected.');
    }
    if (fields['categoryMatchStatus'] == 'partial_views') {
      result.add('Only some views support the listed item type.');
    }
    if (fields['openVocabularyEvidenceUsed'] == true) {
      result.add('The suggested item type is tentative.');
    }
    if (fields['syntheticRiskOnly'] == true) {
      result.add(
          'Image-risk results are experimental; they do not establish authenticity.');
    }
    if (models['detectorAvailable'] == false ||
        images.any((image) => image['detectorUnavailable'] == true)) {
      result.add('Item-type detection is unavailable for some or all photos.');
    }
    if (models['riskClassifierAvailable'] == false ||
        images.any((image) => image['riskClassifierUnavailable'] == true)) {
      result
          .add('Image-risk assessment is unavailable for some or all photos.');
    }
    if (fields['categoryMatchStatus'] == 'analysis_incomplete') {
      result.add('Some image checks could not be completed.');
    }
    if (result.isEmpty && concerns.isNotEmpty) {
      result.add('The saved image checks flagged concerns.');
    }
    return result.toSet().toList();
  }

  @override
  String photoNote(Map image) {
    final quality = ItemPhotoSummary.map(image['quality']);
    final context = ItemPhotoSummary.map(image['photoContext']);
    final notes = <String>[];
    if (quality['isBlurry'] == true) notes.add('Photo appears blurry');
    if (quality['isTooDark'] == true || quality['isTooBright'] == true) {
      notes.add('Lighting may obscure details');
    }
    if (quality['hasUsableResolution'] == false) {
      notes.add('Low-resolution photo');
    }
    if (image['detectorUnavailable'] == true) {
      notes.add('Item-type detection unavailable');
    }
    if (image['riskClassifierUnavailable'] == true) {
      notes.add('Image-risk assessment unavailable');
    }
    final uncertain = context['rotationEvidenceReviewRequired'] == true;
    if (context['depictedContentReviewRequired'] == true ||
        (!uncertain &&
            (context['status'] == 'needs_review' ||
                image['objectEvidenceStatus'] == 'context_needs_review'))) {
      notes.add(
          'Document, illustration or on-screen content may be present; item match not confirmed');
    } else if (uncertain) {
      notes.add('Item-type evidence is uncertain');
    } else if (image['detectorUnavailable'] != true &&
        image['categoryMatched'] == true) {
      notes.add('Possible item type detected; not a confirmed match');
    } else if (image['categoryMatched'] == false ||
        image['objectEvidenceStatus'] == 'not_detected') {
      notes.add('Listed item type not identified clearly');
    } else if (image['objectEvidenceStatus'] == 'category_not_covered') {
      notes.add('Item type outside the available automatic checks');
    }
    final labels = ItemPhotoSummary.maps(image['detections'])
        .map((detection) => detection['label'])
        .whereType<String>()
        .map((label) => label.trim().replaceAll('_', ' '))
        .where((label) => label.isNotEmpty && label.length <= 80)
        .toSet()
        .take(5)
        .toList();
    if (labels.isNotEmpty) {
      notes.add('Tentative object labels: ${labels.join(', ')}');
    }
    return notes.isEmpty
        ? 'No conclusive item-type result recorded for this photo'
        : notes.join(' \u00b7 ');
  }
}
