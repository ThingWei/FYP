import '../../../core/network/api_client.dart';
import '../../../shared/models/domain_models.dart';

class LiveNotificationRepository {
  LiveNotificationRepository(this.api);

  final ApiClient api;

  Future<List<RentHubNotification>> list({
    String? category,
    bool? read,
  }) async {
    final parameters = <String>[
      if (category != null) 'category=${Uri.encodeQueryComponent(category)}',
      if (read != null) 'read=$read',
    ];
    final suffix = parameters.isEmpty ? '' : '?${parameters.join('&')}';
    final data =
        await api.request('GET', '/messages/notifications$suffix') as List;
    return data
        .map(
          (item) => RentHubNotification.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<void> markRead(String notificationId) => api.request(
        'POST',
        '/messages/notifications/$notificationId/read',
      );

  Future<void> markAllRead() =>
      api.request('POST', '/messages/notifications/read-all');

  Future<void> remove(String notificationId) =>
      api.request('DELETE', '/messages/notifications/$notificationId');

  Future<void> clearAll() => api.request('DELETE', '/messages/notifications');
}
