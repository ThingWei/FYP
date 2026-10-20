import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/idempotency_key.dart';
import '../../core/network/user_facing_error.dart';
import '../../shared/models/domain_models.dart';
import '../../modules/user/controllers/auth_controller.dart';
import '../renter/booking/booking_flow.dart' show formatMoney;
import 'live_authenticated_page.dart';
import 'live_renthub_controller.dart';

Future<void> showExtensionCheckout(BuildContext context, String rentalId) =>
    Navigator.push<void>(
        context,
        MaterialPageRoute(
            builder: (_) => LiveAuthenticatedPage(
                renterOnly: true,
                child: LiveExtensionCheckout(rentalId: rentalId))));

class LiveExtensionCheckout extends StatefulWidget {
  const LiveExtensionCheckout({super.key, required this.rentalId});
  final String rentalId;
  @override
  State<LiveExtensionCheckout> createState() => _LiveExtensionCheckoutState();
}

class _LiveExtensionCheckoutState extends State<LiveExtensionCheckout> {
  Rental? rental;
  bool busy = true, uncertain = false;
  String method = 'card', outcome = 'success';
  String? error, message, attemptKey;
  LiveRentHubController get data => context.read<LiveRentHubController>();
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final updated = await data.extensionRental(widget.rentalId);
      if (!mounted) return;
      setState(() {
        if (rental?.extension?.id != updated.extension?.id) attemptKey = null;
        rental = updated;
        uncertain = false;
        if (updated.extension?.paymentStatus == 'authorized') {
          message =
              'Demo payment complete — awaiting Owner approval. Your rental dates have not changed yet.';
        } else if (updated.extension?.paymentStatus == 'captured') {
          message = 'The Owner approved and the extra days are paid.';
        }
      });
    } catch (exception) {
      if (mounted) setState(() => error = friendlyError(exception));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _pay(String selectedOutcome) async {
    if (busy || uncertain || rental?.extension?.payable != true) return;
    final extensionId = rental!.extension!.id;
    final userId = context.read<AuthController>().user?.id;
    final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Simulate extension payment?'),
              content: Text(
                  '${formatMoney(rental!.extension!.amount)} for extra days only. No real payment details are needed. Owner approval is still required.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(selectedOutcome == 'success'
                        ? 'Demo success'
                        : 'Demo decline'))
              ],
            ));
    if (!mounted || accepted != true) return;
    final auth = context.read<AuthController>();
    if (!auth.authenticated ||
        auth.user?.id != userId ||
        auth.selectedRole != UserRole.renter) {
      return;
    }
    outcome = attemptKey == null ? selectedOutcome : outcome;
    attemptKey ??= newCheckoutIdempotencyKey();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final current = await data.extensionRental(widget.rentalId);
      if (current.extension?.id != extensionId) {
        throw StateError('The extension changed. Review it again.');
      }
      if (current.extension?.paymentStatus != 'unpaid') {
        await _load();
        return;
      }
      final updated = await data.payExtension(current,
          method: method, outcome: outcome, attemptKey: attemptKey!);
      if (!mounted) return;
      setState(() {
        rental = updated;
        if (updated.extension?.paymentStatus == 'authorized') {
          message =
              'Demo payment complete — awaiting Owner approval. Your rental dates have not changed yet.';
        } else {
          message =
              'Demo payment declined. You can try again or leave this request unpaid.';
          attemptKey = null;
        }
      });
    } catch (exception) {
      if (mounted) {
        setState(() {
          error = friendlyError(exception);
          uncertain = true;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final quote = rental?.extension;
    final payable = rental?.extensionStatus == 'pending' &&
        ['active', 'overdue'].contains(rental?.status) &&
        quote?.payable == true;
    return Scaffold(
        appBar: AppBar(title: const Text('Extra rental days')),
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(padding: const EdgeInsets.all(20), children: [
                  const Text('Demo checkout',
                      style:
                          TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  if (quote != null && quote.id.isNotEmpty) ...[
                    Text(
                        '${quote.extraDays} extra day(s) × ${formatMoney(quote.dailyRate)} per day'),
                    if (quote.end != null)
                      Text(
                          'Requested return: ${quote.end!.day}/${quote.end!.month}/${quote.end!.year}'),
                    const SizedBox(height: 8),
                    Text('Total ${formatMoney(quote.amount)}',
                        style: Theme.of(context).textTheme.headlineSmall),
                    const Text(
                        'Original booked rate. No second deposit, delivery or damage-waiver charge.'),
                  ] else if (!busy)
                    const Text(
                        'This older extension needs a new quote before payment.'),
                  if (message != null)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(message!)),
                  if (!payable && !busy && message == null)
                    const Text(
                        'This extension is no longer payable. Return to your rental and request a new quote.'),
                  if (error != null)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error))),
                  if (busy) const Center(child: CircularProgressIndicator()),
                  if (payable && !uncertain) ...[
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: method,
                        decoration:
                            const InputDecoration(labelText: 'Demo method'),
                        items: const [
                          DropdownMenuItem(
                              value: 'card', child: Text('Demo Card')),
                          DropdownMenuItem(
                              value: 'fpx', child: Text('Demo FPX')),
                          DropdownMenuItem(
                              value: 'wallet', child: Text('Demo Wallet'))
                        ],
                        onChanged: busy || attemptKey != null
                            ? null
                            : (value) => setState(() => method = value!)),
                    const SizedBox(height: 16),
                    FilledButton(
                        onPressed: busy
                            ? null
                            : () =>
                                _pay(attemptKey == null ? 'success' : outcome),
                        child: Text(attemptKey == null
                            ? 'Continue demo payment'
                            : 'Retry same attempt')),
                    if (attemptKey == null)
                      TextButton(
                          onPressed: busy ? null : () => _pay('declined'),
                          child: const Text('Test a decline')),
                  ],
                  TextButton(
                      onPressed: busy ? null : _load,
                      child: Text(uncertain
                          ? 'Check payment status before retry'
                          : 'Refresh status')),
                  TextButton(
                      onPressed: busy ? null : () => Navigator.pop(context),
                      child: const Text('Back to rental')),
                ]))));
  }
}
