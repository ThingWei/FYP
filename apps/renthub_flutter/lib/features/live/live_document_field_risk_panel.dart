import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Research assistance only: a low score must never be shown as genuine/approved.
class DocumentFieldRiskPanel extends StatelessWidget {
  const DocumentFieldRiskPanel({super.key, required this.evidence});

  final Map<String, dynamic> evidence;

  @override
  Widget build(BuildContext context) {
    final status = evidence['status'] as String? ?? 'unavailable';
    final elevated = evidence['signal'] == 'elevated_signal';
    final score = (evidence['riskScore'] as num?)?.toDouble();
    final images = (evidence['images'] as List? ?? const []).whereType<Map>();
    final message = switch (status) {
      'available' => elevated
          ? 'Elevated field-risk signal — inspect the document carefully.'
          : 'No elevated signal in the scored fields. This does not prove the document is genuine.',
      'partial' =>
        'Only some fields could be analysed. Review both images manually.',
      'disabled' =>
        'Field-risk assistance is disabled. Review the document manually.',
      _ =>
        'Field-risk assistance is unavailable. Review the document manually.',
    };
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.science_outlined,
                  color:
                      elevated ? AppColors.warning : AppColors.secondaryText),
              const SizedBox(width: 8),
              const Expanded(child: Text('MyKad field-risk assistance')),
            ],
          ),
          const SizedBox(height: 8),
          const Text('Synthetic research · Administrator review required'),
          const SizedBox(height: 4),
          Text(message),
          if (score != null && score.isFinite) ...[
            const SizedBox(height: 4),
            Text(
                'Highest field-risk score: ${(score * 100).toStringAsFixed(1)}%'
                ' · ${evidence['scoredFieldCount'] ?? 0} field(s) scored'),
            const Text(
              'An uncalibrated classifier score, not an authenticity probability.',
            ),
          ],
          if (images.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Field coverage and signals'),
              children: [
                for (final image in images)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${image['side'] ?? 'Document'} image'),
                        if ((image['missingRequiredFields'] as List? ??
                                const [])
                            .isNotEmpty)
                          const Text(
                              'Required identity-number field not scored.'),
                        if (image['analysisError'] == true)
                          const Text('Some field analysis failed.'),
                        for (final field
                            in (image['fields'] as List? ?? const [])
                                .whereType<Map>())
                          Text(
                              '${(field['field'] ?? 'Field').toString().replaceAll('_', ' ')}: '
                              '${field['signal'] == 'elevated_signal' ? 'elevated signal' : 'no elevated signal'}'),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
