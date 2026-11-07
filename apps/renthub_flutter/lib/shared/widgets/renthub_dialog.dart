import 'package:flutter/material.dart';

/// Equal-width, separated actions instead of OverflowBar's crowded fallback.
/// Labels wrap inside their own button; text scaling never hides an action.
class RentHubDialogActions extends StatelessWidget {
  const RentHubDialogActions({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    ButtonStyle style(ButtonStyle? base) =>
        (base ?? const ButtonStyle()).copyWith(
            padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 8, vertical: 12)),
            minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
            alignment: Alignment.center);
    return Theme(
        data: theme.copyWith(
            textButtonTheme:
                TextButtonThemeData(style: style(theme.textButtonTheme.style)),
            outlinedButtonTheme: OutlinedButtonThemeData(
                style: style(theme.outlinedButtonTheme.style)),
            filledButtonTheme: FilledButtonThemeData(
                style: style(theme.filledButtonTheme.style))),
        child: SizedBox(
            width: double.maxFinite,
            child: IntrinsicHeight(
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(
                        child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 48),
                            child: children[i])),
                  ],
                ]))));
  }
}

/// Returns a regular AlertDialog, retaining form validation, semantics and tests.
AlertDialog rentHubDialog(
        {Key? key,
        Widget? icon,
        EdgeInsetsGeometry? iconPadding,
        Color? iconColor,
        Widget? title,
        EdgeInsetsGeometry? titlePadding,
        TextStyle? titleTextStyle,
        Widget? content,
        EdgeInsetsGeometry? contentPadding,
        TextStyle? contentTextStyle,
        List<Widget>? actions,
        EdgeInsetsGeometry? actionsPadding,
        MainAxisAlignment? actionsAlignment,
        OverflowBarAlignment? actionsOverflowAlignment,
        VerticalDirection? actionsOverflowDirection,
        double? actionsOverflowButtonSpacing,
        EdgeInsetsGeometry? buttonPadding,
        Color? backgroundColor,
        double? elevation,
        Color? shadowColor,
        Color? surfaceTintColor,
        String? semanticLabel,
        EdgeInsets? insetPadding,
        Clip? clipBehavior,
        ShapeBorder? shape,
        AlignmentGeometry? alignment,
        BoxConstraints? constraints,
        bool scrollable = false}) =>
    AlertDialog(
        key: key,
        icon: icon,
        iconPadding: iconPadding,
        iconColor: iconColor,
        title: title,
        titlePadding: titlePadding,
        titleTextStyle: titleTextStyle,
        content: content,
        contentPadding: contentPadding,
        contentTextStyle: contentTextStyle,
        actions: actions == null || actions.isEmpty
            ? null
            : [RentHubDialogActions(children: actions)],
        actionsPadding:
            actionsPadding ?? const EdgeInsets.fromLTRB(20, 12, 20, 20),
        backgroundColor: backgroundColor,
        elevation: elevation,
        shadowColor: shadowColor,
        surfaceTintColor: surfaceTintColor,
        semanticLabel: semanticLabel,
        insetPadding: insetPadding,
        clipBehavior: clipBehavior,
        shape: shape,
        alignment: alignment,
        constraints: constraints,
        scrollable: scrollable);

bool _logoutPromptOpen = false;

Future<void> confirmLogout(
    BuildContext context, Future<void> Function() logout) async {
  if (_logoutPromptOpen) return;
  _logoutPromptOpen = true;
  try {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => rentHubDialog(
                icon: const Icon(Icons.logout),
                title: const Text('Log out of RentHub?'),
                content: const Text(
                    'You can sign in again to access your bookings and messages.'),
                actions: [
                  OutlinedButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Stay signed in',
                          textAlign: TextAlign.center)),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('Log out', textAlign: TextAlign.center))
                ]));
    if (confirmed == true && context.mounted) await logout();
  } finally {
    _logoutPromptOpen = false;
  }
}
