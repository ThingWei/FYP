import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/domain_models.dart';
import '../../../shared/widgets/account_components.dart';
import '../controllers/auth_controller.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.onAuthenticated,
    this.administrator = false,
    this.initialEmail = 'demo@renthub.my',
  });

  final VoidCallback? onAuthenticated;
  final bool administrator;
  final String initialEmail;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final formKey = GlobalKey<FormState>();
  late final email = TextEditingController(text: widget.initialEmail);
  final password = TextEditingController(text: 'password');

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final controller = context.read<AuthController>();
    if (!controller.usesExternalProvider && !formKey.currentState!.validate()) {
      return;
    }
    await controller.login(email.text.trim(), password.text);
    if (mounted && controller.authenticated) widget.onAuthenticated?.call();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AuthController>();
    return AccountScaffold(
      child: AutofillGroup(
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.administrator
                    ? 'Administrator portal. Sign in with your RentHub account.'
                    : 'Welcome back. Please enter your details.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.secondaryText),
              ),
              const SizedBox(height: 24),
              if (!widget.administrator) ...[
                SegmentedButton<UserRole>(
                  segments: const [
                    ButtonSegment(
                      value: UserRole.renter,
                      icon: Icon(Icons.search),
                      label: Text('Renter'),
                    ),
                    ButtonSegment(
                      value: UserRole.owner,
                      icon: Icon(Icons.inventory_2_outlined),
                      label: Text('Owner'),
                    ),
                  ],
                  selected: {controller.selectedRole},
                  onSelectionChanged: controller.loading
                      ? null
                      : (selection) => controller.selectRole(selection.first),
                ),
                const SizedBox(height: 16),
              ],
              AccountCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    RentHubTextField(
                      controller: email,
                      label: 'Email',
                      hint: 'Enter your email',
                      icon: Icons.mail_outline,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      validator: (value) => value != null &&
                              RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(value)
                          ? null
                          : 'Enter a valid email address',
                    ),
                    const SizedBox(height: 16),
                    RentHubTextField(
                      controller: password,
                      label: 'Password',
                      hint: 'Enter your password',
                      icon: Icons.lock_outline,
                      obscure: true,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      validator: (value) => (value?.length ?? 0) >= 6
                          ? null
                          : 'Password must be at least 6 characters',
                      onFieldSubmitted: (_) => _login(),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => const ForgotPasswordScreen(),
                          ),
                        ),
                        child: const Text('Forgot Password?'),
                      ),
                    ),
                    if (controller.error != null) ...[
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          controller.error!,
                          style: const TextStyle(color: AppColors.error),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    RentHubActionButton(
                      label: 'Log In',
                      loading: controller.loading,
                      onPressed: _login,
                    ),
                    if (!widget.administrator) ...[
                      if (controller.usesExternalProvider) ...[
                        const SizedBox(height: 18),
                        const Row(
                          children: [
                            Expanded(child: Divider()),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                'or',
                                style:
                                    TextStyle(color: AppColors.secondaryText),
                              ),
                            ),
                            Expanded(child: Divider()),
                          ],
                        ),
                        const SizedBox(height: 18),
                        RentHubActionButton(
                          label: 'Continue with Auth0',
                          icon: Icons.account_circle_outlined,
                          style: RentHubButtonStyle.secondary,
                          onPressed: _login,
                        ),
                      ],
                      const SizedBox(height: 16),
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text("Don't have an account?"),
                          TextButton(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => const RegisterScreen(),
                              ),
                            ),
                            child: const Text('Create Account'),
                          ),
                        ],
                      ),
                    ] else ...[
                      const SizedBox(height: 12),
                      Text(
                        controller.usesExternalProvider
                            ? 'Authentication is handled by Auth0 Universal Login.'
                            : 'Development authentication is active. Administrative actions create audit entries.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.secondaryText,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
