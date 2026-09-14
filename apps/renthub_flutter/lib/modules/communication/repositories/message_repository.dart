import '../../../core/network/api_client.dart';
import '../../../core/network/socket_service.dart';
import '../../../shared/models/domain_models.dart';

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

class LiveMessageRepository implements MessageRepository {
  LiveMessageRepository(this.api, {this.socket}) {
    socket?.initializeListeners();
  }

  final ApiClient api;
  final SocketService? socket;

  @override
  Stream<Message> watch(String threadId) {
    socket?.join(threadId);
    return socket?.messages
            .where((event) => event is Map && event['threadId'] == threadId)
            .map(
              (event) => Message.fromJson(
                Map<String, dynamic>.from(event as Map),
              ),
            ) ??
        const Stream<Message>.empty();
  }

  @override
  Future<void> send(String threadId, String text) async {
    await api.request(
      'POST',
      '/messages/threads/$threadId/messages',
      body: {'text': text},
    );
  }

  Future<List<Conversation>> listThreads() async {
    final data = await api.request('GET', '/messages/threads') as List;
    return data
        .map(
          (item) => Conversation.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<List<Message>> listMessages(String threadId) async {
    final data = await api.request(
      'GET',
      '/messages/threads/$threadId/messages',
    ) as List;
    return data
        .map((item) => Message.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> markRead(String threadId) =>
      api.request('POST', '/messages/threads/$threadId/read');

  Future<void> reportMessage(
    String messageId, {
    required String reason,
    String? details,
  }) =>
      api.request(
        'POST',
        '/messages/$messageId/report',
        body: {
          'reason': reason,
          if (details != null) 'details': details,
        },
      );
}
