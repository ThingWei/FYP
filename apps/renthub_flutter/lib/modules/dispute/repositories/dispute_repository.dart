abstract interface class DisputeRepository {
  Future<List<Object>> list();
}

class MockDisputeRepository implements DisputeRepository {
  @override
  Future<List<Object>> list() async => [];
}
