import 'live_payment_countdown.dart';
import '../../shared/widgets/renthub_dialog.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/network/idempotency_key.dart';
import '../../core/network/user_facing_error.dart';
import '../../core/theme/app_theme.dart';
import '../../modules/user/controllers/auth_controller.dart';
import '../../shared/models/domain_models.dart';
import '../renter/booking/booking_flow.dart' show formatDateRange, formatMoney;
import 'live_authenticated_page.dart';
import 'live_booking_charges.dart';
import 'live_renthub_controller.dart';
import 'live_agreement.dart';

Future<void> showLiveCheckout(BuildContext context, String bookingId,
    {double? estimatedTotal, String initialMethod = 'card'}) async {
  await Navigator.push<void>(
      context,
      MaterialPageRoute(
          builder: (_) => LiveAuthenticatedPage(
              renterOnly: true,
              child: LiveCheckoutPage(
                  bookingId: bookingId,
                  estimatedTotal: estimatedTotal,
                  initialMethod: initialMethod))));
}

class LiveCheckoutPage extends StatefulWidget {
  const LiveCheckoutPage(
      {super.key,
      required this.bookingId,
      this.estimatedTotal,
      this.initialMethod = 'card'});
  final String bookingId, initialMethod;
  final double? estimatedTotal;
  @override
  State<LiveCheckoutPage> createState() => _LiveCheckoutPageState();
}

class _LiveCheckoutPageState extends State<LiveCheckoutPage> {
  Booking? booking;
  bool loading = true,
      paying = false,
      uncertain = false,
      blocked = false,
      acceptedFinalTotal = false,
      recorded = false;
  bool choosing = false, revisedTotal = false;
  String? error, message, attemptKey;
  String attemptOutcome = 'success';
  late String method = widget.initialMethod;
  LiveRentHubController get controller => context.read<LiveRentHubController>();
  bool get changedTotal =>
      revisedTotal ||
      (widget.estimatedTotal != null &&
          booking != null &&
          (widget.estimatedTotal! - booking!.total).abs() > .01);
  bool get payable =>
      booking != null &&
      booking!.canContinuePayment &&
      booking!.charges != null &&
      !blocked;
  bool get ready =>
      payable &&
      !paying &&
      !loading &&
      !uncertain &&
      !choosing &&
      error == null &&
      (!changedTotal || acceptedFinalTotal);
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final value = await controller.getBooking(widget.bookingId);
      if (!mounted) return;
      if (value.renterId != context.read<AuthController>().user?.id) {
        throw ApiException(403, 'This checkout belongs to another renter');
      }
      final attempts =
          await controller.bookingPaymentAttempts(widget.bookingId);
      if (!mounted) return;
      final successful = attempts.where((item) => item.status == 'authorized');
      final current = attempts
          .where((item) => item.key == attemptKey && attemptKey != null);
      setState(() {
        if (booking != null && (booking!.total - value.total).abs() > .01) {
          acceptedFinalTotal = false;
          revisedTotal = true;
        }
        booking = value;
        uncertain = false;
        recorded = successful.isNotEmpty &&
            value.paymentStatus == 'unpaid' &&
            value.status == 'pending';
        if (recorded) {
          attemptKey = successful.first.key;
          method = successful.first.method;
          attemptOutcome = 'success';
          message =
              'Your demo payment is recorded. Finish updating this request without making another payment.';
        } else if (current.isNotEmpty && current.first.status == 'failed') {
          attemptKey = null;
          message =
              'The demo payment was declined. Your request is still unpaid; choose a method and try again.';
        } else if (value.paymentStatus == 'authorized' &&
            value.status == 'pending') {
          message = 'Demo payment complete — awaiting Owner approval';
        } else if (value.paymentStatus != 'unpaid' ||
            value.status != 'pending') {
          message =
              'This request does not need another payment. Its current booking status is ${value.status}.';
        }
      });
    } catch (exception) {
      if (mounted) {
        setState(() {
          error = friendlyError(exception);
          uncertain = attemptKey != null;
          blocked = exception is ApiException &&
              [401, 403, 404].contains(exception.status);
        });
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _openDemo() async {
    if (!ready) return;
    if (attemptKey != null) {
      await _pay(attemptOutcome);
      return;
    }
    setState(() => choosing = true);
    final sessionUserId = context.read<AuthController>().user?.id;
    final selected = await showDialog<String>(
        context: context,
        builder: (context) =>
            Consumer<AuthController>(builder: (context, auth, _) {
              if (!auth.authenticated ||
                  auth.user?.id != sessionUserId ||
                  auth.selectedRole != UserRole.renter) {
                return rentHubDialog(
                    title: const Text('Session changed'),
                    content: const Text(
                        'Return to the app before continuing payment.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Close'))
                    ]);
              }
              return _DemoPaymentDialog(
                  method: method, total: booking!.total, booking: booking!);
            }));
    if (!mounted) return;
    setState(() => choosing = false);
    if (selected == null) return;
    if (selected == 'cancel') {
      setState(() => message = booking!.canContinuePayment
          ? 'Payment cancelled. Continue from Bookings before the countdown ends.'
          : 'Your payment window expired. No payment was taken.');
      return;
    }
    await _pay(selected);
  }

  Future<void> _pay(String outcome) async {
    if (!ready) return;
    setState(() {
      paying = true;
      error = null;
      message = null;
    });
    var writeStarted = false;
    try {
      final fresh = await controller.getBooking(widget.bookingId);
      if (!mounted) return;
      if (fresh.renterId != context.read<AuthController>().user?.id) {
        throw ApiException(403, 'This checkout belongs to another renter');
      }
      final previousTotal = booking!.total;
      setState(() => booking = fresh);
      if (!payable) {
        setState(() => message =
            'This request is no longer payable. Check its current status in Bookings.');
        return;
      }
      if ((fresh.total - previousTotal).abs() > .01) {
        setState(() {
          acceptedFinalTotal = false;
          revisedTotal = true;
          message =
              'The final total changed. Review the charges before continuing.';
        });
        return;
      }
      attemptKey ??= newCheckoutIdempotencyKey();
      attemptOutcome = outcome;
      writeStarted = true;
      final result = await controller.authorizeBookingPayment(
          bookingId: widget.bookingId,
          method: method,
          idempotencyKey: attemptKey!,
          simulationOutcome: outcome);
      if (!mounted) return;
      if (!result.succeeded) {
        setState(() {
          attemptKey = null;
          message =
              'The demo payment was declined. Your request is still unpaid; you can try again.';
        });
      }
      await _load();
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        error = friendlyError(exception);
        uncertain = writeStarted;
        blocked = exception is ApiException &&
            [401, 403, 404].contains(exception.status);
      });
      if (writeStarted && !blocked) {
        // Read-only reconciliation; never automatically repeat a payment write.
        await _load();
        if (mounted && payable && message == null) {
          setState(() => message =
              'No completed payment was found. You may retry the same demo attempt.');
        }
      }
    } finally {
      if (mounted) setState(() => paying = false);
    }
  }

  Widget card(List<Widget> children) => Card(
      child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children)));
  @override
  Widget build(BuildContext context) => booking == null
      ? _body(context, null, false)
      : BookingPaymentClock(
          booking: booking!,
          onExpired: _load,
          builder: (context, remaining, expired) =>
              _body(context, remaining, expired));

  Widget _body(BuildContext context, Duration? remaining, bool expired) =>
      Scaffold(
          appBar: AppBar(title: const Text('Checkout')),
          body: SafeArea(
              child: Center(
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: blocked
                          ? Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(error ??
                                  'Sign in again to access this checkout.'))
                          : loading && booking == null
                              ? const Center(child: CircularProgressIndicator())
                              : ListView(
                                  padding: const EdgeInsets.all(16),
                                  children: [
                                      card([
                                        Text('RentHub demo checkout',
                                            style: Theme.of(context)
                                                .textTheme
                                                .headlineSmall),
                                        const SizedBox(height: 8),
                                        const Text(
                                            'No real money is taken. Payment does not confirm the booking; the Owner must still approve your request.')
                                      ]),
                                      if (booking?.awaitingPayment == true)
                                        card([
                                          PaymentCountdownLabel(
                                              remaining: remaining,
                                              expired: expired),
                                          const SizedBox(height: 8),
                                          const Text(
                                              'Complete payment within 10 minutes of starting checkout. Leaving this page does not restart the timer.'),
                                        ]),
                                      if (loading || paying)
                                        const LinearProgressIndicator(),
                                      if (error != null)
                                        card([
                                          Text(error!),
                                          OutlinedButton(
                                              onPressed: loading || paying
                                                  ? null
                                                  : _load,
                                              child: const Text(
                                                  'Check payment status'))
                                        ]),
                                      if (message != null)
                                        card([
                                          Text(message!,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w600))
                                        ]),
                                      if (booking != null) ...[
                                        card([
                                          Text(booking!.listingTitle,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleLarge),
                                          const SizedBox(height: 8),
                                          Text('Booking ${booking!.id}'),
                                          Text(formatDateRange(
                                              booking!.start, booking!.end)),
                                          const SizedBox(height: 16),
                                          LiveBookingCharges(booking: booking!),
                                          if (changedTotal) ...[
                                            const SizedBox(height: 12),
                                            Text(widget.estimatedTotal == null
                                                ? 'The saved total changed. Review the final charges above before paying.'
                                                : 'Your earlier estimate was ${formatMoney(widget.estimatedTotal!)}. The final total above is saved with this request.'),
                                            CheckboxListTile(
                                                contentPadding: EdgeInsets.zero,
                                                value: acceptedFinalTotal,
                                                onChanged: paying
                                                    ? null
                                                    : (v) => setState(() =>
                                                        acceptedFinalTotal =
                                                            v ?? false),
                                                title: const Text(
                                                    'I have reviewed the final charges'))
                                          ],
                                          TextButton(
                                              onPressed: () =>
                                                  showBookingAgreement(context,
                                                      widget.bookingId),
                                              child:
                                                  const Text('View agreement'))
                                        ]),
                                        if (payable)
                                          card([
                                            Text('Choose a demo payment method',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium),
                                            const SizedBox(height: 8),
                                            for (final entry in const [
                                              (
                                                'card',
                                                'Demo Card',
                                                Icons.credit_card
                                              ),
                                              (
                                                'fpx',
                                                'Demo FPX',
                                                Icons.account_balance_outlined
                                              ),
                                              (
                                                'wallet',
                                                'Demo Wallet',
                                                Icons
                                                    .account_balance_wallet_outlined
                                              )
                                            ])
                                              ListTile(
                                                  contentPadding:
                                                      EdgeInsets.zero,
                                                  leading: Icon(entry.$3),
                                                  title: Text(entry.$2),
                                                  trailing: Icon(method ==
                                                          entry.$1
                                                      ? Icons
                                                          .radio_button_checked
                                                      : Icons.radio_button_off),
                                                  onTap: paying ||
                                                          loading ||
                                                          attemptKey != null
                                                      ? null
                                                      : () => setState(() =>
                                                          method = entry.$1)),
                                            const SizedBox(height: 16),
                                            FilledButton(
                                                onPressed:
                                                    ready ? _openDemo : null,
                                                child: Text(recorded
                                                    ? 'Finish recording payment'
                                                    : 'Continue demo payment'))
                                          ]),
                                        if (booking!.charges == null)
                                          const Text(
                                              'The saved charge breakdown is unavailable. Please contact support before paying.'),
                                      ],
                                      if (uncertain && error == null)
                                        OutlinedButton(
                                            onPressed: paying || loading
                                                ? null
                                                : _load,
                                            child: const Text(
                                                'Check payment status')),
                                      OutlinedButton(
                                          onPressed: paying
                                              ? null
                                              : () => Navigator.pop(context),
                                          child:
                                              const Text('Back to Bookings')),
                                      if (payable)
                                        const Padding(
                                            padding: EdgeInsets.all(8),
                                            child: Text(
                                                'You can leave now. Your unpaid request stays in Bookings until it expires.')),
                                    ])))));
}

class _DemoPaymentDialog extends StatelessWidget {
  const _DemoPaymentDialog(
      {required this.method, required this.total, required this.booking});
  final Booking booking;
  final String method;
  final double total;

  @override
  Widget build(BuildContext context) => BookingPaymentClock(
      booking: booking,
      builder: (context, remaining, expired) =>
          _dialog(context, remaining, expired));

  Widget _dialog(BuildContext context, Duration? remaining, bool expired) =>
      rentHubDialog(
        backgroundColor: AppColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        constraints: const BoxConstraints(maxWidth: 420),
        title: Row(children: [
          Icon(
              switch (method) {
                'fpx' => Icons.account_balance_outlined,
                'wallet' => Icons.account_balance_wallet_outlined,
                _ => Icons.credit_card,
              },
              color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
              child: Text(switch (method) {
            'fpx' => 'Demo FPX',
            'wallet' => 'Demo Wallet',
            _ => 'Demo Card',
          })),
        ]),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (booking.awaitingPayment) ...[
                  PaymentCountdownLabel(remaining: remaining, expired: expired),
                  const SizedBox(height: 12)
                ],
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.blueSurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Demo total'),
                        const SizedBox(height: 4),
                        Text(formatMoney(total),
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(switch (method) {
                  'fpx' => 'Test bank selected. No banking login is needed.',
                  'wallet' =>
                    'Test wallet selected. No wallet credentials are needed.',
                  _ =>
                    'Test card ending 4242. Do not enter a real card number.',
                }),
                const SizedBox(height: 8),
                const Text(
                    'No real money will be taken. Owner approval is still required.',
                    style: TextStyle(color: AppColors.secondaryText)),
              ],
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: const Text('Cancel', textAlign: TextAlign.center)),
          OutlinedButton(
              onPressed:
                  expired ? null : () => Navigator.pop(context, 'declined'),
              child: const Text('Decline', textAlign: TextAlign.center)),
          FilledButton(
              onPressed:
                  expired ? null : () => Navigator.pop(context, 'success'),
              child: const Text('Pay demo', textAlign: TextAlign.center)),
        ],
      );
}
