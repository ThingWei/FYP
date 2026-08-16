import '../../../core/network/api_client.dart';
import '../../../shared/mock_data/mock_data.dart';
import '../../../shared/models/domain_models.dart';

abstract interface class ListingRepository {
  Future<List<Listing>> list();
  Future<Listing> create(Map<String, dynamic> data);
}

class MockListingRepository implements ListingRepository {
  final _items = MockData.listings.toList();
  @override
  Future<List<Listing>> list() async => List.unmodifiable(_items);
  @override
  Future<Listing> create(Map<String, dynamic> d) async {
    final item = Listing(
      id: '${_items.length + 1}',
      title: d['title'],
      category: d['category'],
      dailyPrice: d['dailyPrice'],
    );
    _items.add(item);
    return item;
  }
}

class LiveListingRepository implements ListingRepository {
  LiveListingRepository(this.api);
  final ApiClient api;
  @override
  Future<List<Listing>> list() async =>
      (await api.request('GET', '/listings') as List)
          .map((e) => Listing.fromJson(e))
          .toList();
  @override
  Future<Listing> create(Map<String, dynamic> data) async =>
      Listing.fromJson(await api.request('POST', '/listings', body: data));
}
