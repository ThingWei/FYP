import 'package:flutter/material.dart';
import '../../core/network/user_facing_error.dart';

class AsyncActionButton extends StatefulWidget {
  const AsyncActionButton(
      {super.key,
      required this.label,
      required this.onPressed,
      this.busyLabel = 'Processing',
      this.icon = Icons.check_circle_outline});
  final String label, busyLabel;
  final Future<void> Function()? onPressed;
  final IconData icon;
  @override
  State<AsyncActionButton> createState() => _AsyncActionButtonState();
}

class _AsyncActionButtonState extends State<AsyncActionButton> {
  bool busy = false;
  Future<void> run() async {
    if (busy || widget.onPressed == null) return;
    setState(() => busy = true);
    try {
      await widget.onPressed!();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(error))));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
      liveRegion: true,
      child: FilledButton(
          onPressed: busy || widget.onPressed == null ? null : run,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            busy && (ModalRoute.of(context)?.isCurrent ?? true)
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(widget.icon),
            const SizedBox(width: 8),
            Flexible(
                child: Text(busy ? widget.busyLabel : widget.label,
                    textAlign: TextAlign.center))
          ])));
}
