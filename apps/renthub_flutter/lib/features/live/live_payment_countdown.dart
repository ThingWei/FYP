import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/domain_models.dart';

class BookingPaymentClock extends StatefulWidget {
  const BookingPaymentClock(
      {super.key,
      required this.booking,
      required this.builder,
      this.onExpired,
      this.now});
  final Booking booking;
  final Widget Function(BuildContext, Duration?, bool) builder;
  final Future<void> Function()? onExpired;
  final DateTime Function()? now;
  @override
  State<BookingPaymentClock> createState() => _BookingPaymentClockState();
}

class _BookingPaymentClockState extends State<BookingPaymentClock>
    with WidgetsBindingObserver {
  Timer? timer;
  bool notified = false;
  Duration? get remaining => widget.booking.paymentDueAt
      ?.difference(widget.now?.call() ?? widget.booking.serverAdjustedNow);
  bool get expired =>
      widget.booking.awaitingPayment &&
      (widget.booking.displayStatus == 'expired' ||
          remaining?.isNegative == true ||
          remaining == Duration.zero);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void didUpdateWidget(covariant BookingPaymentClock old) {
    super.didUpdateWidget(old);
    if (old.booking.id != widget.booking.id ||
        old.booking.paymentDueAt != widget.booking.paymentDueAt) {
      notified = false;
    }
    _start();
  }

  void _start() {
    timer?.cancel();
    if (widget.booking.awaitingPayment &&
        widget.booking.paymentDueAt != null &&
        !notified) {
      timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {});
          _notify();
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _notify();
      });
    }
  }

  void _notify() {
    if (!expired || notified) return;
    notified = true;
    timer?.cancel();
    final action = widget.onExpired;
    if (action != null) unawaited(action().catchError((Object _) {}));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
      _notify();
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, remaining, expired);
}

class PaymentCountdownLabel extends StatelessWidget {
  const PaymentCountdownLabel(
      {super.key,
      required this.remaining,
      this.expired = false,
      this.compact = false});
  final Duration? remaining;
  final bool expired, compact;
  @override
  Widget build(BuildContext context) {
    final seconds = remaining == null
        ? null
        : ((remaining!.inMilliseconds / 1000).ceil()).clamp(0, 599999);
    final text = expired
        ? 'Payment window expired'
        : seconds == null
            ? 'Refresh to check your payment deadline'
            : 'Pay within ${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
    return Semantics(
        label: text,
        child: Container(
            padding: EdgeInsets.all(compact ? 8 : 12),
            decoration: BoxDecoration(
                color: (expired ? AppColors.error : AppColors.warning)
                    .withValues(alpha: .08),
                borderRadius: BorderRadius.circular(12)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.timer_outlined,
                  size: 20,
                  color: expired ? AppColors.error : AppColors.secondaryText),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(text,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: expired ? AppColors.error : AppColors.text))),
            ])));
  }
}
