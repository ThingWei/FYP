import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/account_components.dart';

enum _ResetStep { email, code, password, success }

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final formKey = GlobalKey<FormState>();
  final email = TextEditingController();
  final code = TextEditingController();
  final password = TextEditingController();
  final confirmPassword = TextEditingController();
  _ResetStep step = _ResetStep.email;
  bool loading = false;
  String? error;

  @override
  void dispose() {
    email.dispose();
    code.dispose();
    password.dispose();
    confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _advance() async {
    if (!formKey.currentState!.validate()) return;
    setState(() {
      loading = true;
      error = null;
    });
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    if (step == _ResetStep.code && code.text != '123456') {
      setState(() {
        loading = false;
        error = 'Use mock code 123456 to continue.';
      });
      return;
    }
    setState(() {
      loading = false;
      step = _ResetStep.values[step.index + 1];
    });
  }

  @override
  Widget build(BuildContext context) => AccountScaffold(
        child: AccountCard(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: step == _ResetStep.success
                ? RentHubFeedbackState(
                    key: const ValueKey('success'),
                    kind: FeedbackKind.success,
                    title: 'Password Updated',
                    message: 'Your mock password has been reset successfully.',
                    actionLabel: 'Return to Login',
                    onAction: () => Navigator.pop(context),
                  )
                : Form(
                    key: formKey,
                    child: Column(
                      key: ValueKey(step),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: const BoxDecoration(
                              color: AppColors.blueSurface,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(_icon, color: AppColors.primaryDark),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          _title,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _message,
                          textAlign: TextAlign.center,
                          style:
                              const TextStyle(color: AppColors.secondaryText),
                        ),
                        const SizedBox(height: 24),
                        ..._fields,
                        if (error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.error),
                          ),
                        ],
                        const SizedBox(height: 20),
                        RentHubActionButton(
                          label: _buttonLabel,
                          loading: loading,
                          onPressed: _advance,
                        ),
                        if (step == _ResetStep.code)
                          TextButton(
                            onPressed: loading
                                ? null
                                : () =>
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content:
                                            Text('A new mock code was sent.'),
                                      ),
                                    ),
                            child: const Text('Resend code'),
                          )
                        else
                          TextButton.icon(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.arrow_back, size: 18),
                            label: const Text('Return to login'),
                          ),
                      ],
                    ),
                  ),
          ),
        ),
      );

  IconData get _icon => switch (step) {
        _ResetStep.email => Icons.lock_reset,
        _ResetStep.code => Icons.mark_email_read_outlined,
        _ResetStep.password => Icons.password,
        _ResetStep.success => Icons.check,
      };

  String get _title => switch (step) {
        _ResetStep.email => 'Reset your password',
        _ResetStep.code => 'Check your inbox',
        _ResetStep.password => 'Create new password',
        _ResetStep.success => 'Password Updated',
      };

  String get _message => switch (step) {
        _ResetStep.email =>
          'Enter the email associated with your account and we’ll send a reset code.',
        _ResetStep.code =>
          'Enter the six-digit code sent to ${email.text}. For this prototype, use 123456.',
        _ResetStep.password =>
          'Choose a strong password with at least eight characters.',
        _ResetStep.success => '',
      };

  String get _buttonLabel => switch (step) {
        _ResetStep.email => 'Send Reset Link',
        _ResetStep.code => 'Verify Code',
        _ResetStep.password => 'Update Password',
        _ResetStep.success => 'Return to Login',
      };

  List<Widget> get _fields => switch (step) {
        _ResetStep.email => [
            RentHubTextField(
              controller: email,
              label: 'Email Address',
              hint: 'name@example.com',
              icon: Icons.mail_outline,
              keyboardType: TextInputType.emailAddress,
              validator: (value) => value != null && value.contains('@')
                  ? null
                  : 'Enter a valid email address',
            ),
          ],
        _ResetStep.code => [
            RentHubTextField(
              controller: code,
              label: 'Six-digit code',
              hint: '123456',
              icon: Icons.pin_outlined,
              keyboardType: TextInputType.number,
              validator: (value) => RegExp(r'^\d{6}$').hasMatch(value ?? '')
                  ? null
                  : 'Enter all six digits',
            ),
          ],
        _ResetStep.password => [
            RentHubTextField(
              controller: password,
              label: 'New Password',
              obscure: true,
              icon: Icons.lock_outline,
              validator: (value) => (value?.length ?? 0) >= 8
                  ? null
                  : 'Use at least 8 characters',
            ),
            const SizedBox(height: 16),
            RentHubTextField(
              controller: confirmPassword,
              label: 'Confirm Password',
              obscure: true,
              icon: Icons.lock_outline,
              validator: (value) =>
                  value == password.text ? null : 'Passwords do not match',
            ),
          ],
        _ResetStep.success => const [],
      };
}
