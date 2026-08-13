import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/domain_models.dart';
import '../../../shared/widgets/renthub_components.dart';
import '../controllers/auth_controller.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final key = GlobalKey<FormState>();
  final email = TextEditingController(text: 'demo@renthub.my'),
      password = TextEditingController(text: 'password');
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AuthController>();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: key,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Center(child: RentHubLogo()),
                        const SizedBox(height: 28),
                        Text(
                          'Welcome back',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const Text(
                          'Rent with confidence across Malaysia.',
                          style: TextStyle(color: AppColors.secondaryText),
                        ),
                        const SizedBox(height: 20),
                        SegmentedButton<UserRole>(
                          segments: const [
                            ButtonSegment(
                              value: UserRole.renter,
                              icon: Icon(Icons.search),
                              label: Text('Renter'),
                            ),
                            ButtonSegment(
                              value: UserRole.owner,
                              icon: Icon(Icons.storefront),
                              label: Text('Owner'),
                            ),
                          ],
                          selected: {c.selectedRole},
                          onSelectionChanged: (s) => c.selectRole(s.first),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(labelText: 'Email'),
                          validator: (v) => v?.contains('@') == true
                              ? null
                              : 'Enter a valid email',
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: password,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                          ),
                          validator: (v) => (v?.length ?? 0) >= 6
                              ? null
                              : 'At least 6 characters',
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => showMockSuccess(
                              context,
                              'Password reset instructions sent',
                            ),
                            child: const Text('Forgot password?'),
                          ),
                        ),
                        if (c.error != null)
                          Text(
                            c.error!,
                            style: const TextStyle(color: AppColors.error),
                          ),
                        FilledButton(
                          onPressed: c.loading
                              ? null
                              : () {
                                  if (key.currentState!.validate()) {
                                    c.login(email.text, password.text);
                                  }
                                },
                          child: Text(c.loading ? 'Signing in…' : 'Sign in'),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => showMockSuccess(
                            context,
                            'Registration form opened',
                          ),
                          child: const Text('New to RentHub? Create account'),
                        ),
                        const Text(
                          'Use demo@renthub.my to preview role switching.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
