abstract interface class RentalRepository {
  Future<List<Object>> list();
}

class MockRentalRepository implements RentalRepository {
  @override
  Future<List<Object>> list() async => [];
}
