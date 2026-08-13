import 'package:flutter_test/flutter_test.dart';
import 'package:renthub_flutter/modules/listing/controllers/listing_controller.dart';
import 'package:renthub_flutter/modules/listing/repositories/listing_repository.dart';

void main() {
  test('loads mock listings and creates one', () async {
    final controller = ListingController(MockListingRepository());
    await controller.load();
    expect(controller.listings.length, 2);
    await controller.create('Tent', 'Equipment & Tools', 15);
    expect(controller.listings.length, 3);
  });
}
