import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../shared/models/domain_models.dart';
import '../../core/network/user_facing_error.dart';
import 'live_renter_shell.dart' show LiveBookingPage;
import 'live_renthub_controller.dart';

class BookingListingLink extends StatefulWidget {
  const BookingListingLink({super.key, required this.booking});
  final Booking booking;
  @override
  State<BookingListingLink> createState() => _BookingListingLinkState();
}

class _BookingListingLinkState extends State<BookingListingLink> {
  bool loading = false;
  Future<void> open() async {
    if (loading) return;
    final c = context.read<LiveRentHubController>(),
        account = context.read<LiveRentHubController>().accountGeneration;
    setState(() => loading = true);
    try {
      final raw = await c.api.request(
          'GET', '/listings/${Uri.encodeComponent(widget.booking.listingId)}');
      if (!mounted || c.accountGeneration != account) return;
      final listing = Listing.fromJson(Map<String, dynamic>.from(raw as Map));
      await Navigator.push<void>(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  LiveBookingPage(listing: listing, onSubmitted: () {})));
    } catch (error) {
      if (mounted && c.accountGeneration == account) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'This listing is currently unavailable. ${friendlyError(error)}')));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => TextButton.icon(
      onPressed: loading ? null : open,
      icon: loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.inventory_2_outlined),
      label: Text(widget.booking.listingTitle, textAlign: TextAlign.start));
}
