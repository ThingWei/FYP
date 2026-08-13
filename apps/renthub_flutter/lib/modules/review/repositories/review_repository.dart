abstract interface class ReviewRepository {
  Future<List<Object>> list();
}

class MockReviewRepository implements ReviewRepository {
  @override
  Future<List<Object>> list() async => [];
}
