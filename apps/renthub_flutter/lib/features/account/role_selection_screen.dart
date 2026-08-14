import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/domain_models.dart';
import '../../shared/widgets/account_components.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key, this.initialRole});
  final UserRole? initialRole;

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  UserRole? selected;

  @override
  void initState() {
    super.initState();
    selected = widget.initialRole;
  }

  @override
  Widget build(BuildContext context) => AccountScaffold(
        child: AccountCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'How will you use RentHub?',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Select a primary role to personalize your experience. You can switch later if your account supports both.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.secondaryText),
              ),
              const SizedBox(height: 24),
              RoleOptionCard(
                role: UserRole.renter,
                selected: selected == UserRole.renter,
                onTap: () => setState(() => selected = UserRole.renter),
              ),
              const SizedBox(height: 12),
              RoleOptionCard(
                role: UserRole.owner,
                selected: selected == UserRole.owner,
                onTap: () => setState(() => selected = UserRole.owner),
              ),
              const SizedBox(height: 20),
              RentHubActionButton(
                label: 'Continue',
                onPressed: selected == null
                    ? null
                    : () => Navigator.pop(context, selected),
              ),
              const SizedBox(height: 4),
              RentHubActionButton(
                label: 'Cancel',
                style: RentHubButtonStyle.text,
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      );
}
