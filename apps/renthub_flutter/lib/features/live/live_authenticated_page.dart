import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../modules/user/controllers/auth_controller.dart';
import '../../shared/models/domain_models.dart';

/// A pushed route must stop exposing its child when the underlying session changes.
class LiveAuthenticatedPage extends StatefulWidget {
  const LiveAuthenticatedPage(
      {super.key,
      required this.child,
      this.renterOnly = false,
      this.sessionMessage});
  final Widget child;
  final bool renterOnly;
  final String? sessionMessage;
  @override
  State<LiveAuthenticatedPage> createState() => _LiveAuthenticatedPageState();
}

class _LiveAuthenticatedPageState extends State<LiveAuthenticatedPage> {
  String? userId;
  bool bound = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!bound) {
      userId = context.read<AuthController>().user?.id;
      bound = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final allowed = auth.authenticated &&
        userId != null &&
        auth.user!.id == userId &&
        (!widget.renterOnly ||
            auth.user!.roles.contains(UserRole.renter) &&
                auth.selectedRole == UserRole.renter);
    if (allowed) return widget.child;
    return Scaffold(
        appBar: AppBar(title: const Text('Sign in required')),
        body: Center(
            child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.lock_outline, size: 48),
                  const SizedBox(height: 16),
                  Text(widget.sessionMessage ??
                      (widget.renterOnly
                          ? 'Sign in with the booking\u2019s renter account to continue. This page is not available to other accounts.'
                          : 'Your session changed. Return to the app and sign in with an account that can access this agreement.')),
                  TextButton(
                      onPressed: () =>
                          Navigator.popUntil(context, (route) => route.isFirst),
                      child: const Text('Back to app')),
                ]))));
  }
}
