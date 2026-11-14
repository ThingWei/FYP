import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/trust/trust_profile.dart';

class TrustIndicator extends StatelessWidget {
  const TrustIndicator({super.key, required this.cohort, this.size = 88});
  final TrustCohort cohort;
  final double size;
  @override
  Widget build(BuildContext context) {
    final score = cohort.established ? cohort.score : null;
    final color = score == null
        ? AppColors.secondaryText
        : score >= 80
            ? AppColors.success
            : score >= 50
                ? AppColors.warning
                : AppColors.error;
    return Semantics(
        label: 'Trust score: ${cohort.label}',
        child: ExcludeSemantics(
            child: SizedBox(
                width: size,
                height: size,
                child: Stack(alignment: Alignment.center, children: [
                  SizedBox.expand(
                      child: CircularProgressIndicator(
                          value: score == null ? 0 : score / 100,
                          strokeWidth: size < 50 ? 3 : 6,
                          color: color,
                          backgroundColor: AppColors.border)),
                  Padding(
                      padding: const EdgeInsets.all(8),
                      child: FittedBox(
                          child: score == null
                              ? const Text('—', style: TextStyle(fontSize: 24))
                              : Text('$score%',
                                  style: TextStyle(
                                      fontSize: size < 50 ? 14 : 24,
                                      fontWeight: FontWeight.w700)))),
                ]))));
  }
}
