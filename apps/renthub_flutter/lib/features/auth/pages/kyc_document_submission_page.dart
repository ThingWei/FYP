import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/account_components.dart';
import 'kyc_verification_status_page.dart';

class KycDocumentSubmissionPage extends StatefulWidget {
  const KycDocumentSubmissionPage({super.key});

  @override
  State<KycDocumentSubmissionPage> createState() =>
      _KycDocumentSubmissionPageState();
}

class _KycDocumentSubmissionPageState extends State<KycDocumentSubmissionPage> {
  bool loading = false;
  bool verified = false;

  Future<void> _verify() async {
    setState(() => loading = true);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (mounted) {
      setState(() {
        loading = false;
        verified = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const RentHubBackAppBar(title: 'RentHub'),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: verified
                    ? KycVerificationStatusPage(
                        onReturn: () => Navigator.pop(context, true),
                      )
                    : _gate(),
              ),
            ),
          ),
        ),
      );

  Widget _gate() => Column(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: AppColors.blueSurface,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.primaryLight),
            ),
            child: const Icon(
              Icons.gpp_good_outlined,
              color: AppColors.primaryDark,
              size: 38,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Identity Verification Required',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'RentHub requires verification for high-value rentals to protect our community.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.secondaryText),
          ),
          const SizedBox(height: 24),
          const AccountCard(
            child: Column(
              children: [
                _BenefitRow(
                  icon: Icons.lock_outline,
                  title: 'Secure and trusted bookings',
                  message: 'Your data is encrypted and handled securely.',
                ),
                Divider(height: 28),
                _BenefitRow(
                  icon: Icons.group_outlined,
                  title: 'Verified community members',
                  message: 'Interact only with authentic, vetted renters.',
                ),
                Divider(height: 28),
                _BenefitRow(
                  icon: Icons.support_agent,
                  title: 'Faster dispute support',
                  message: 'Verified accounts receive priority support.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Prototype Notice: This is a mock verification. No real ID documents are uploaded or stored.',
                    style: TextStyle(color: AppColors.secondaryText),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          RentHubActionButton(
            label: 'Verify Identity',
            icon: Icons.badge_outlined,
            loading: loading,
            onPressed: _verify,
          ),
          const SizedBox(height: 10),
          RentHubActionButton(
            label: 'Not Now',
            style: RentHubButtonStyle.secondary,
            onPressed: () => Navigator.pop(context, false),
          ),
        ],
      );
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: const Color(0xFFECFDF5),
            child: Icon(icon, size: 18, color: AppColors.success),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: const TextStyle(color: AppColors.secondaryText),
                ),
              ],
            ),
          ),
        ],
      );
}
