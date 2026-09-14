import 'package:flutter_test/flutter_test.dart';
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
}
