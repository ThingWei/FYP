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

  List<String> get notes {
    final result = <String>[];
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
      return 'Item type looks consistent in ${matched.toInt()} of ${total.toInt()} photos.';
    }
    return fields['categoryMatched'] == true &&
            fields['categoryMatchStatus'] != 'analysis_incomplete'
        ? 'Item type looks consistent.'
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
    if (image['categoryMatched'] == true) {
      notes.add('Item type looks consistent');
    } else if (image['categoryMatched'] == false) {
      notes.add('Item type needs manual review');
    } else if (image['objectEvidenceStatus'] == 'not_detected' ||
        image['objectEvidenceStatus'] == 'category_not_covered') {
      notes.add('Item type needs manual review');
    }
    return notes.isEmpty ? 'Needs a closer look' : notes.join(' · ');
  }
}
