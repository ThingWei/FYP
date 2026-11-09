import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import 'renthub_dialog.dart';

/// A heading with optional, deliberately requested explanatory help.
class RentHubSectionHeader extends StatelessWidget {
  const RentHubSectionHeader(this.title,
      {super.key, this.help, this.style, this.icon});
  final String title;
  final String? help;
  final TextStyle? style;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: AppColors.primary),
            const SizedBox(width: 10),
          ],
          Flexible(
              child: Semantics(
                  header: true,
                  child: Text(title,
                      style: style ?? Theme.of(context).textTheme.titleLarge))),
          if (help?.trim().isNotEmpty == true) ...[
            const SizedBox(width: 4),
            RentHubHelpButton(topic: title, message: help!),
          ],
        ],
      );
}

class RentHubHelpButton extends StatefulWidget {
  const RentHubHelpButton(
      {super.key, required this.topic, required this.message});
  final String topic, message;
  @override
  State<RentHubHelpButton> createState() => _RentHubHelpButtonState();
}

class _RentHubHelpButtonState extends State<RentHubHelpButton> {
  static final _openNavigators = <NavigatorState>{};
  final _anchor = GlobalKey();
  final _focus = FocusNode();
  NavigatorState? _routeNavigator;

  @override
  void dispose() {
    if (_routeNavigator != null) _openNavigators.remove(_routeNavigator);
    _focus.dispose();
    super.dispose();
  }

  double _height(String text, TextStyle style, double width) {
    final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context))
      ..layout(maxWidth: width);
    final height = painter.height;
    painter.dispose();
    return height;
  }

  Future<void> _show() async {
    if (widget.message.trim().isEmpty) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    if (!_openNavigators.add(navigator)) return;
    _routeNavigator = navigator;
    try {
      final media = MediaQuery.of(context), theme = Theme.of(context);
      final bodyStyle = theme.textTheme.bodyMedium!;
      final titleStyle = theme.textTheme.titleMedium!;
      final box = _anchor.currentContext?.findRenderObject();
      final overlay = navigator.overlay?.context.findRenderObject();
      Rect? anchor;
      if (box is RenderBox && overlay is RenderBox && box.hasSize) {
        anchor = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
      }
      final bodyHeight = _height(widget.message, bodyStyle, 328);
      final titleHeight =
          math.max(48.0, _height(widget.topic, titleStyle, 272));
      final popupHeight = bodyHeight + titleHeight + 40;
      final topEdge = media.padding.top + 16;
      final bottomEdge = media.size.height -
          media.viewInsets.bottom -
          media.padding.bottom -
          16;
      final below = anchor == null ? 0.0 : bottomEdge - anchor.bottom - 8;
      final above = anchor == null ? 0.0 : anchor.top - topEdge - 8;
      final usePopup = media.size.width >= 600 &&
          bodyHeight <= 240 &&
          anchor != null &&
          (below >= popupHeight || above >= popupHeight);

      if (!usePopup) {
        await showDialog<void>(
            context: context,
            useRootNavigator: true,
            barrierDismissible: true,
            builder: (dialogContext) =>
                _escape(dialogContext, _dialog(dialogContext)));
      } else {
        final leftEdge = media.padding.left + 16;
        final maxLeft = media.size.width - media.padding.right - 16 - 360;
        final preferred = Directionality.of(context) == TextDirection.rtl
            ? anchor.right - 360
            : anchor.left;
        final left = preferred.clamp(leftEdge, maxLeft).toDouble();
        final top = below >= popupHeight
            ? anchor.bottom + 8
            : anchor.top - popupHeight - 8;
        await showGeneralDialog<void>(
            context: context,
            useRootNavigator: true,
            barrierDismissible: true,
            barrierLabel: 'Close help',
            barrierColor: Colors.transparent,
            transitionDuration: const Duration(milliseconds: 120),
            pageBuilder: (popupContext, animation, secondaryAnimation) =>
                _escape(popupContext, Builder(builder: (routeContext) {
                  final current = MediaQuery.of(routeContext);
                  if (current.size != media.size ||
                      current.textScaler != media.textScaler ||
                      current.viewInsets != media.viewInsets ||
                      current.padding != media.padding) {
                    return _dialog(routeContext);
                  }
                  return Stack(children: [
                    Positioned(
                        left: left,
                        top: top,
                        width: 360,
                        child: Semantics(
                            scopesRoute: true,
                            explicitChildNodes: true,
                            namesRoute: true,
                            label: widget.topic,
                            child: Material(
                                key: const ValueKey('section-help-popover'),
                                color: theme.colorScheme.surface,
                                elevation: 4,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    side: const BorderSide(
                                        color: AppColors.border)),
                                child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(children: [
                                            Expanded(
                                                child: Text(widget.topic,
                                                    style: titleStyle)),
                                            IconButton(
                                                tooltip: 'Close help',
                                                onPressed: () =>
                                                    _dismiss(popupContext),
                                                icon: const Icon(Icons.close)),
                                          ]),
                                          const SizedBox(height: 8),
                                          Text(widget.message,
                                              style: bodyStyle),
                                        ])))))
                  ]);
                })));
      }
    } finally {
      _openNavigators.remove(navigator);
      _routeNavigator = null;
      if (mounted) {
        _focus.requestFocus();
      }
    }
  }

  void _dismiss(BuildContext routeContext) {
    if (ModalRoute.of(routeContext)?.isCurrent == true) {
      Navigator.pop(routeContext);
    }
  }

  Widget _dialog(BuildContext dialogContext) => rentHubDialog(
          key: const ValueKey('section-help-dialog'),
          constraints: const BoxConstraints(maxWidth: 480),
          insetPadding: const EdgeInsets.all(16),
          scrollable: true,
          title: Text(widget.topic),
          content: SizedBox(width: 432, child: Text(widget.message)),
          actions: [
            TextButton(
                onPressed: () => _dismiss(dialogContext),
                child: const Text('Close'))
          ]);

  Widget _escape(BuildContext routeContext, Widget child) => Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.escape): DismissIntent()
          },
          child: Actions(actions: {
            DismissIntent: CallbackAction<DismissIntent>(onInvoke: (_) {
              _dismiss(routeContext);
              return null;
            })
          }, child: Focus(autofocus: true, child: child)));

  @override
  Widget build(BuildContext context) => Semantics(
      container: true,
      button: true,
      label: 'About ${widget.topic}',
      onTap: _show,
      child: ExcludeSemantics(
          child: IconButton(
              key: _anchor,
              focusNode: _focus,
              tooltip: 'About ${widget.topic}',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              padding: const EdgeInsets.all(12),
              color: AppColors.primary,
              onPressed: _show,
              icon: const Icon(Icons.help_outline, size: 20))));
}
