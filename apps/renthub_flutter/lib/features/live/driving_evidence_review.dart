import 'package:flutter/material.dart';

/// Binds a review to the current protected upload and evidence mode, never OCR IDs.
class DrivingEvidenceDraft {
  String? reference;
  String source = 'physical';
  int generation = 0;
  Map<String, dynamic>? result;

  void replace(String? nextReference, String nextSource) {
    reference = nextReference;
    source = nextSource;
    generation++;
    result = null;
  }

  bool accept(int requestGeneration, Map<String, dynamic> response) {
    if (generation != requestGeneration ||
        response['documentRef'] != reference ||
        response['method'] != 'malaysian-driving-ocr-v1') {
      return false;
    }
    result = response;
    return true;
  }

  bool get canSubmit =>
      reference != null &&
      result?['available'] == true &&
      result?['canReview'] == true &&
      const ['ready_for_review', 'needs_review'].contains(result?['status']) &&
      result?['identityMatch'] != 'mismatch';
}

class DrivingEvidenceReview extends StatelessWidget {
  const DrivingEvidenceReview(
      {super.key,
      required this.result,
      required this.checking,
      required this.onRetry});
  final Map<String, dynamic>? result;
  final bool checking;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final classes = result?['licenceClasses'];
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Licence check',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (checking) const LinearProgressIndicator(),
                  Text(checking
                      ? 'Reading your licence details…'
                      : result?['guidance'] as String? ??
                          'Check this image before submitting.'),
                  if (!checking && result != null) ...[
                    Text(
                        'Holder match: ${result!['identityMatch'] == 'matched' ? 'Matches verified MyKad' : result!['identityMatch'] == 'mismatch' ? 'Does not match' : 'Administrator must check'}'),
                    Text(
                        'Licence class: ${classes is List && classes.isNotEmpty ? classes.join(', ') : 'Administrator must check'}'),
                    Text(
                        'Valid until: ${result!['validUntil'] ?? 'Administrator must check'}'),
                  ],
                  const SizedBox(height: 8),
                  const Text(
                      'Administrator review is still required. This check does not confirm authenticity or verify JPJ records.'),
                  TextButton.icon(
                      onPressed: checking ? null : onRetry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry licence check')),
                ])));
  }
}
