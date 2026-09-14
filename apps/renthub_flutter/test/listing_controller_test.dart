import 'package:flutter_test/flutter_test.dart';
import 'package:renthub_flutter/modules/listing/controllers/listing_controller.dart';
import 'package:renthub_flutter/modules/listing/repositories/listing_repository.dart';

void main() {
  test('loads mock listings and creates one', () async {
    final controller = ListingController(MockListingRepository());
    await controller.load();
    final initialCount = controller.listings.length;
    expect(initialCount, greaterThan(1));
    await controller.create('Tent', 'Equipment & Tools', 15);
    expect(controller.listings.length, initialCount + 1);
    expect(controller.listings.last.title, 'Tent');
  });
}
