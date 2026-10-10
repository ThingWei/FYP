import '../../../core/validation/input_validation.dart';
import '../../../core/validation/input_rules.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/domain_models.dart';
import '../../../shared/widgets/account_components.dart';
import '../../../shared/widgets/renthub_components.dart';
import '../controllers/auth_controller.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final formKeys = List.generate(2, (_) => GlobalKey<FormState>());
  final name = TextEditingController();
  final email = TextEditingController();
  final phone = TextEditingController();
  final password = TextEditingController();
  int step = 0;
  UserRole? role;
  bool acceptedTerms = false;
  bool complete = false;

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    phone.dispose();
    password.dispose();
    super.dispose();
  }

  void _next() {
    if (step < 2 && !formKeys[step].currentState!.validate()) return;
    setState(() => step++);
  }

  Future<void> _submit() async {
    if (role == null || !acceptedTerms) return;
    final auth = context.read<AuthController>();
    await auth.selectRole(role!);
    await auth.register(name.text.trim(), email.text.trim(), password.text);
    if (mounted && auth.error == null) setState(() => complete = true);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    if (complete) {
      return AccountScaffold(
        child: AccountCard(
          child: RentHubFeedbackState(
            kind: FeedbackKind.success,
            title: 'Account created!',
            message:
                'Welcome to RentHub. The ${role!.name} view will open first, and you can switch between Renter and Owner later.',
            actionLabel: 'Continue to RentHub',
            onAction: () =>
                Navigator.popUntil(context, (route) => route.isFirst),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const RentHubLogo(),
        leading: IconButton(
          tooltip: step == 0 ? 'Back to login' : 'Previous step',
          onPressed: () =>
              step == 0 ? Navigator.pop(context) : setState(() => step--),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            16,
            24,
            16,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: (step + 1) / 3,
                      minHeight: 4,
                      backgroundColor: AppColors.border,
                    ),
                  ),
                  const SizedBox(height: 16),
                  AccountCard(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: KeyedSubtree(
                        key: ValueKey(step),
                        child: switch (step) {
                          0 => _detailsStep(),
                          1 => _securityStep(),
                          _ => _roleStep(auth),
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Already have an account? Log in'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _heading(String title, String subtitle) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(subtitle,
              style: const TextStyle(color: AppColors.secondaryText)),
          const SizedBox(height: 20),
        ],
      );

  Widget _detailsStep() => Form(
        key: formKeys[0],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _heading(
                'Create Account', 'Join RentHub to start renting and listing.'),
            RentHubTextField(
              controller: name,
              label: 'Full Name',
              hint: 'Aina Rahman',
              icon: Icons.person_outline,
              textInputAction: TextInputAction.next,
              validator: InputValidation.compose(
                  InputRules.fullName.validate,
                  (value) => (value?.trim().length ?? 0) >= 2
                      ? null
                      : 'Enter your full name'),
              inputFormatters:
                  InputValidation.formatters(InputRules.fullName, name),
              maxLength: InputRules.fullName.maxLength,
            ),
            const SizedBox(height: 16),
            RentHubTextField(
              controller: email,
              label: 'Email Address',
              hint: 'aina@example.com',
              icon: Icons.mail_outline,
              keyboardType: TextInputType.emailAddress,
              validator: InputValidation.compose(
                  InputRules.emailAddress.validate,
                  (value) => value != null && value.contains('@')
                      ? null
                      : 'Enter a valid email address'),
              inputFormatters:
                  InputValidation.formatters(InputRules.emailAddress, email),
              maxLength: InputRules.emailAddress.maxLength,
            ),
            const SizedBox(height: 20),
            RentHubActionButton(
              label: 'Continue',
              icon: Icons.arrow_forward,
              onPressed: _next,
            ),
          ],
        ),
      );

  Widget _securityStep() => Form(
        key: formKeys[1],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _heading('Security & Contact',
                'Keep your account secure and reachable.'),
            RentHubTextField(
              controller: phone,
              label: 'Mobile Number',
              hint: '+60 12 345 6789',
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              validator: InputValidation.compose(
                  InputRules.mobileNumber.validate,
                  (value) =>
                      (value?.replaceAll(RegExp(r'\D'), '').length ?? 0) >= 9
                          ? null
                          : 'Enter a valid Malaysian mobile number'),
              inputFormatters:
                  InputValidation.formatters(InputRules.mobileNumber, phone),
              maxLength: InputRules.mobileNumber.maxLength,
            ),
            const SizedBox(height: 16),
            RentHubTextField(
              controller: password,
              label: 'Password',
              hint: 'At least 8 characters',
              icon: Icons.lock_outline,
              obscure: true,
              validator: InputValidation.compose(
                  InputRules.password.validate,
                  (value) => (value?.length ?? 0) >= 8
                      ? null
                      : 'Use at least 8 characters'),
              inputFormatters:
                  InputValidation.formatters(InputRules.password, password),
              maxLength: InputRules.password.maxLength,
            ),
            const SizedBox(height: 8),
            const Text(
              'Use a mix of letters and numbers.',
              style: TextStyle(color: AppColors.secondaryText, fontSize: 12),
            ),
            const SizedBox(height: 20),
            RentHubActionButton(
              label: 'Continue',
              icon: Icons.arrow_forward,
              onPressed: _next,
            ),
          ],
        ),
      );

  Widget _roleStep(AuthController auth) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(
              'Choose Role', 'Select how you want to start using RentHub.'),
          const Text(
            'Every marketplace account can use both Renter and Owner. This choice only selects the first view.',
            style: TextStyle(color: AppColors.secondaryText),
          ),
          const SizedBox(height: 12),
          RoleOptionCard(
            role: UserRole.renter,
            selected: role == UserRole.renter,
            onTap: () => setState(() => role = UserRole.renter),
          ),
          const SizedBox(height: 12),
          RoleOptionCard(
            role: UserRole.owner,
            selected: role == UserRole.owner,
            onTap: () => setState(() => role = UserRole.owner),
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            value: acceptedTerms,
            onChanged: (value) =>
                setState(() => acceptedTerms = value ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'I agree to the Terms of Service and Privacy Policy.',
              style: TextStyle(fontSize: 13),
            ),
          ),
          if (auth.error != null) ...[
            Text(auth.error!, style: const TextStyle(color: AppColors.error)),
            const SizedBox(height: 12),
          ],
          RentHubActionButton(
            label: 'Create Account',
            loading: auth.loading,
            onPressed: role != null && acceptedTerms ? _submit : null,
          ),
        ],
      );
}
