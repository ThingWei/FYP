import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/domain_models.dart';
import 'renthub_components.dart';

class AccountScaffold extends StatelessWidget {
  const AccountScaffold({
    super.key,
    required this.child,
    this.showTopLogo = true,
    this.maxWidth = 420,
  });

  final Widget child;
  final bool showTopLogo;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                16,
                constraints.maxHeight < 700 ? 16 : 28,
                16,
                24 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 52,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (showTopLogo) ...[
                          const RentHubLogo(),
                          const SizedBox(height: 24),
                        ],
                        child,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class AccountCard extends StatelessWidget {
  const AccountCard({super.key, required this.child, this.padding});
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: padding ?? const EdgeInsets.all(20),
          child: child,
        ),
      );
}

enum RentHubButtonStyle { primary, secondary, outline, text, destructive }

class RentHubActionButton extends StatelessWidget {
  const RentHubActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.style = RentHubButtonStyle.primary,
    this.icon,
    this.loading = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final RentHubButtonStyle style;
  final IconData? icon;
  final bool loading;
  final bool expand;

  Widget _content() => loading
      ? const SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      : Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 19),
              const SizedBox(width: 8),
            ],
            Flexible(child: Text(label)),
          ],
        );

  @override
  Widget build(BuildContext context) {
    final callback = loading ? null : onPressed;
    final button = switch (style) {
      RentHubButtonStyle.primary => FilledButton(
          onPressed: callback,
          child: _content(),
        ),
      RentHubButtonStyle.secondary => FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryLight,
            foregroundColor: AppColors.primaryDark,
          ),
          onPressed: callback,
          child: _content(),
        ),
      RentHubButtonStyle.outline => OutlinedButton(
          onPressed: callback,
          child: _content(),
        ),
      RentHubButtonStyle.text => TextButton(
          onPressed: callback,
          child: _content(),
        ),
      RentHubButtonStyle.destructive => FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          onPressed: callback,
          child: _content(),
        ),
    };
    return SizedBox(width: expand ? double.infinity : null, child: button);
  }
}

class RentHubTextField extends StatefulWidget {
  const RentHubTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.icon,
    this.validator,
    this.keyboardType,
    this.textInputAction,
    this.obscure = false,
    this.autofillHints,
    this.onFieldSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData? icon;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscure;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onFieldSubmitted;

  @override
  State<RentHubTextField> createState() => _RentHubTextFieldState();
}

class _RentHubTextFieldState extends State<RentHubTextField> {
  late bool obscured = widget.obscure;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: widget.controller,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        obscureText: obscured,
        autofillHints: widget.autofillHints,
        onFieldSubmitted: widget.onFieldSubmitted,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          prefixIcon: widget.icon == null ? null : Icon(widget.icon, size: 20),
          suffixIcon: widget.obscure
              ? IconButton(
                  tooltip: obscured ? 'Show password' : 'Hide password',
                  onPressed: () => setState(() => obscured = !obscured),
                  icon: Icon(
                    obscured ? Icons.visibility_outlined : Icons.visibility_off,
                  ),
                )
              : null,
        ),
        validator: widget.validator,
      );
}

class RoleOptionCard extends StatelessWidget {
  const RoleOptionCard({
    super.key,
    required this.role,
    required this.selected,
    required this.onTap,
  });

  final UserRole role;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final renter = role == UserRole.renter;
    return Semantics(
      selected: selected,
      button: true,
      label: renter ? 'Use RentHub as a renter' : 'Use RentHub as an owner',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: selected ? AppColors.blueSurface : AppColors.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  renter ? Icons.shopping_cart_outlined : Icons.storefront,
                  color: AppColors.primaryDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      renter
                          ? 'Rent items or book services'
                          : 'List items or offer services',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      renter
                          ? 'Find equipment, spaces, or local professionals.'
                          : 'Earn by sharing equipment, spaces, or expertise.',
                      style: const TextStyle(color: AppColors.secondaryText),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? AppColors.primary : AppColors.secondaryText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum FeedbackKind { loading, empty, success, error }

class RentHubFeedbackState extends StatelessWidget {
  const RentHubFeedbackState({
    super.key,
    required this.kind,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final FeedbackKind kind;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (kind) {
      FeedbackKind.loading => (Icons.hourglass_top, AppColors.info),
      FeedbackKind.empty => (Icons.inbox_outlined, AppColors.secondaryText),
      FeedbackKind.success => (Icons.check_circle_outline, AppColors.success),
      FeedbackKind.error => (Icons.error_outline, AppColors.error),
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (kind == FeedbackKind.loading)
              const CircularProgressIndicator()
            else
              Icon(icon, size: 48, color: color),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.secondaryText),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 20),
              RentHubActionButton(
                label: actionLabel!,
                onPressed: onAction,
                expand: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class RentHubBackAppBar extends StatelessWidget implements PreferredSizeWidget {
  const RentHubBackAppBar({super.key, required this.title, this.actions});
  final String title;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) => AppBar(
        title: Text(title),
        centerTitle: true,
        actions: actions,
      );
}
