import 'package:flutter_test/flutter_test.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/modules/communication/repositories/message_repository.dart';
import 'package:renthub_flutter/modules/communication/repositories/notification_repository.dart';

class RecordingApiClient extends ApiClient {
  RecordingApiClient(this.responses) : super('http://example.invalid');

  final List<dynamic> responses;
  final List<(String, String, Object?)> calls = [];

  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    calls.add((method, path, body));
    return responses.removeAt(0);
  }
}

void main() {
  test('live messaging uses server-scoped thread and sender contracts',
      () async {
    final api = RecordingApiClient([
      null,
      [
        {
          'publicId': 'MSG-ABC123',
          'threadId': 'THR-ABC123',
          'senderId': 'u-owner',
          'recipientId': 'u-renter',
          'text': 'The item is ready.',
          'createdAt': '2026-09-14T02:24:00.000Z',
        },
      ],
    ]);
    final repository = LiveMessageRepository(api);

    await repository.send('THR-ABC123', 'I will arrive at 10 AM.');
    final messages = await repository.listMessages('THR-ABC123');

    final body = api.calls.first.$3 as Map<String, dynamic>;
    expect(body, {'text': 'I will arrive at 10 AM.'});
    expect(body.containsKey('senderId'), isFalse);
    expect(messages.single.senderId, 'u-owner');
    expect(messages.single.recipientId, 'u-renter');
  });

  test('live notification repository maps filters and stable IDs', () async {
    final api = RecordingApiClient([
      [
        {
          'publicId': 'NTF-ABC123',
          'category': 'booking',
          'title': 'Booking approved',
          'body': 'Your booking is confirmed.',
          'entityId': 'RH-BKG-2026-09142',
          'read': false,
        },
      ],
    ]);

    final notifications = await LiveNotificationRepository(api)
        .list(category: 'booking', read: false);

    expect(
      api.calls.single.$2,
      '/messages/notifications?category=booking&read=false',
    );
    expect(notifications.single.id, 'NTF-ABC123');
    expect(notifications.single.read, isFalse);
  });
}
