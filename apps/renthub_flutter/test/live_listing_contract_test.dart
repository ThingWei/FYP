import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/features/live/live_renter_shell.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';

void main() {
  test('parses the strict listing API contract with its stable public ID', () {
    final listing = Listing.fromJson({
      'publicId': 'l-camera',
      'id': 'l-camera',
      'title': 'Sony Alpha a7S III Mirrorless Camera',
      'category': 'Devices',
      'dailyPrice': 85,
      'condition': 'Excellent',
      'ownerName': 'Sarah J.',
      'location': 'Bukit Bintang, Kuala Lumpur',
      'verified': true,
      'isService': false,
      'rating': 4.9,
    });

    expect(listing.id, 'l-camera');
    expect(listing.ownerName, 'Sarah J.');
    expect(listing.dailyPrice, 85);
    expect(listing.verified, isTrue);
  });

  test('parses a service without physical-item fields', () {
    final listing = Listing.fromJson({
      'publicId': 'l-photo',
      'title': 'Event Photography Package',
      'category': 'Services',
      'dailyPrice': 450,
      'ownerName': 'Aina Rahman',
      'location': 'Kuala Lumpur',
      'verified': true,
      'isService': true,
      'rating': 5,
    });

    expect(listing.id, 'l-photo');
    expect(listing.isService, isTrue);
  });

  testWidgets('renders a truthful recommendation reason on renter Home',
      (tester) async {
    final controller =
        LiveRentHubController(ApiClient('http://example.invalid'));
    controller.recommendedListings = [
      Listing.fromJson({
        'publicId': 'l-camera',
        'title': 'Canon EOS R50 Camera',
        'category': 'Devices',
        'subcategory': 'Cameras',
        'dailyPrice': 70,
        'condition': 'Excellent',
        'ownerName': 'Aina',
        'location': 'Kuala Lumpur',
        'status': 'active',
        'recommendation': {
          'score': 0.82,
          'reason':
              'Similar to listings you saved, booked, completed, or reviewed',
          'adapter': 'content-cosine-with-popularity-fallback-v1',
        },
      })
    ];
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          home: LiveMarketplacePage(
            title: 'RentHub',
            featuredOnly: true,
            onOpenBookings: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Recommended for you'), findsOneWidget);
    expect(
      find.text(
          'Similar to listings you saved, booked, completed, or reviewed'),
      findsOneWidget,
    );
  });
}
