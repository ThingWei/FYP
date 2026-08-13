abstract interface class AdminRepository {
  Future<Map<String, int>> metrics();
}

class MockAdminRepository implements AdminRepository {
  @override
  Future<Map<String, int>> metrics() async => {'users': 4892, 'listings': 1248};
}
