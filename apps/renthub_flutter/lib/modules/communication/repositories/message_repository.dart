abstract interface class MessageRepository {
  Stream<Object> watch(String threadId);
  Future<void> send(String threadId, String text);
}

class MockMessageRepository implements MessageRepository {
  @override
  Stream<Object> watch(String id) => const Stream.empty();
  @override
  Future<void> send(String id, String text) async {}
}
