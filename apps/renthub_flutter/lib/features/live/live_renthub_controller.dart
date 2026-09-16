import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';
import '../../core/network/socket_service.dart';
import '../../shared/models/domain_models.dart';

class LiveRentHubController extends ChangeNotifier {
  LiveRentHubController(
    this.api, {
    this.socketUrl = 'http://localhost:3000',
  });

  final ApiClient api;
  final String socketUrl;
  final _realtimeMessages = StreamController<Message>.broadcast();
  SocketService? _socket;
  StreamSubscription<dynamic>? _socketSubscription;
  String? _socketUserId;

  bool loading = false;
  String? error;
  User? profile;
  List<Listing> listings = [];
  List<Listing> ownerListings = [];
  List<Listing> adminListings = [];
  List<Booking> bookings = [];
  List<Rental> rentals = [];
  List<Conversation> conversations = [];
  List<RentHubNotification> notifications = [];
  List<Transaction> transactions = [];
  List<Review> reviews = [];
  List<Review> receivedReviews = [];
  List<Review> adminReviews = [];
  List<Map<String, dynamic>> users = [];
  List<Map<String, dynamic>> messageReports = [];

  Future<T> _perform<T>(Future<T> Function() operation) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      return await operation();
    } catch (exception) {
      error = exception.toString();
      rethrow;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  List<T> _models<T>(dynamic data, T Function(Map<String, dynamic>) parse) =>
      (data as List)
          .map((item) => parse(item as Map<String, dynamic>))
          .toList();

  Future<void> loadRenter() => _perform(() async {
        final results = await Future.wait([
          api.request('GET', '/users/me'),
          api.request('GET', '/listings'),
          api.request('GET', '/bookings/mine'),
          api.request('GET', '/rentals/mine'),
          api.request('GET', '/messages/threads'),
          api.request('GET', '/reviews/mine'),
        ]);
        profile = User.fromJson(results[0] as Map<String, dynamic>);
        _connectRealtime(profile!.id);
        listings = _models(results[1], Listing.fromJson);
        bookings = _models(results[2], Booking.fromJson);
        rentals = _models(results[3], Rental.fromJson);
        conversations = _models(results[4], Conversation.fromJson);
        reviews = _models(results[5], Review.fromJson);
      });

  Future<void> loadOwner() => _perform(() async {
        final results = await Future.wait([
          api.request('GET', '/users/me'),
          api.request('GET', '/listings/owner/mine'),
          api.request('GET', '/bookings/owner'),
          api.request('GET', '/rentals/owner'),
          api.request('GET', '/messages/threads'),
          api.request('GET', '/reviews/received'),
          api.request('GET', '/reviews/mine'),
        ]);
        profile = User.fromJson(results[0] as Map<String, dynamic>);
        _connectRealtime(profile!.id);
        ownerListings = _models(results[1], Listing.fromJson);
        bookings = _models(results[2], Booking.fromJson);
        rentals = _models(results[3], Rental.fromJson);
        conversations = _models(results[4], Conversation.fromJson);
        receivedReviews = _models(results[5], Review.fromJson);
        reviews = _models(results[6], Review.fromJson);
      });

  Future<void> loadAdmin() => _perform(() async {
        final results = await Future.wait([
          api.request('GET', '/users/me'),
          api.request('GET', '/users'),
          api.request('GET', '/listings/admin'),
          api.request('GET', '/bookings/admin'),
          api.request('GET', '/rentals/admin'),
          api.request('GET', '/payments'),
          api.request('GET', '/messages/reports'),
          api.request('GET', '/reviews/admin'),
        ]);
        profile = User.fromJson(results[0] as Map<String, dynamic>);
        users = (results[1] as List).cast<Map<String, dynamic>>();
        adminListings = _models(results[2], Listing.fromJson);
        bookings = _models(results[3], Booking.fromJson);
        rentals = _models(results[4], Rental.fromJson);
        transactions = _models(results[5], Transaction.fromJson);
        messageReports = (results[6] as List).cast<Map<String, dynamic>>();
        adminReviews = _models(results[7], Review.fromJson);
      });

  void _connectRealtime(String userId) {
    if (_socketUserId == userId) return;
    _socketSubscription?.cancel();
    _socket?.dispose();
    _socketUserId = userId;
    _socket = SocketService(socketUrl, userId: userId)..initializeListeners();
    _socketSubscription = _socket!.messages.listen((event) {
      if (event is! Map) return;
      final message = Message.fromJson(Map<String, dynamic>.from(event));
      _realtimeMessages.add(message);
      unawaited(refreshConversations().catchError((_) {}));
    });
    _socket!.connect();
  }

  Stream<Message> watchThread(String threadId) {
    _socket?.join(threadId);
    return _realtimeMessages.stream
        .where((message) => message.threadId == threadId);
  }

  Future<List<Review>> listingReviews(String listingId) async => _models(
        await api.request('GET', '/reviews/listing/$listingId'),
        Review.fromJson,
      );

  Future<Booking> createAndAuthorizeBooking({
    required Listing listing,
    required DateTime start,
    required DateTime end,
    required String paymentMethod,
    String fulfilmentMethod = 'pickup',
    String serviceVenue = 'To be confirmed',
    bool damageWaiverSelected = false,
    String renterNote = '',
  }) =>
      _perform(() async {
        final bookingData = await api.request(
          'POST',
          '/bookings',
          body: {
            'listingId': listing.id,
            'startDate': start.toUtc().toIso8601String(),
            'endDate': end.toUtc().toIso8601String(),
            if (listing.isService) 'serviceVenue': serviceVenue,
            if (!listing.isService) 'fulfilmentMethod': fulfilmentMethod,
            if (!listing.isService)
              'damageWaiverSelected': damageWaiverSelected,
            if (renterNote.trim().isNotEmpty) 'renterNote': renterNote.trim(),
          },
        ) as Map<String, dynamic>;
        var booking = Booking.fromJson(bookingData);
        await api.request(
          'POST',
          '/payments/authorizations',
          body: {
            'bookingId': booking.id,
            'method': paymentMethod,
            'idempotencyKey': 'checkout:${booking.id}',
          },
        );
        booking = Booking.fromJson(
          await api.request('GET', '/bookings/${booking.id}')
              as Map<String, dynamic>,
        );
        bookings.insert(0, booking);
        notifyListeners();
        return booking;
      });

  Future<void> cancelBooking(String id, String reason) => _perform(() async {
        final updated = Booking.fromJson(
          await api.request(
            'POST',
            '/bookings/$id/cancel',
            body: {'reason': reason},
          ) as Map<String, dynamic>,
        );
        _replaceBooking(updated);
      });

  Future<Review> submitReview({
    required Rental rental,
    required int overallRating,
    required int communicationRating,
    int? conditionRating,
    int? valueRating,
    required String text,
  }) =>
      _perform(() async {
        final review = Review.fromJson(
          await api.request(
            'POST',
            '/reviews',
            body: {
              'rentalId': rental.id,
              'overallRating': overallRating,
              'communicationRating': communicationRating,
              if (rental.listingType == 'physical' && conditionRating != null)
                'conditionRating': conditionRating,
              if (valueRating != null) 'valueRating': valueRating,
              'text': text.trim(),
            },
          ) as Map<String, dynamic>,
        );
        reviews.insert(0, review);
        notifyListeners();
        return review;
      });

  Future<Review> editReview({
    required Review existing,
    required Rental rental,
    required int overallRating,
    required int communicationRating,
    int? conditionRating,
    int? valueRating,
    required String text,
  }) =>
      _perform(() async {
        final review = Review.fromJson(
          await api.request(
            'PATCH',
            '/reviews/${existing.id}',
            body: {
              'overallRating': overallRating,
              'communicationRating': communicationRating,
              if (rental.listingType == 'physical' && conditionRating != null)
                'conditionRating': conditionRating,
              if (valueRating != null) 'valueRating': valueRating,
              'text': text.trim(),
            },
          ) as Map<String, dynamic>,
        );
        final index = reviews.indexWhere((item) => item.id == review.id);
        if (index >= 0) reviews[index] = review;
        notifyListeners();
        return review;
      });

  Future<void> flagReview(String id, String reason) => _perform(() async {
        await api.request(
          'POST',
          '/reviews/$id/flag',
          body: {'reason': reason.trim()},
        );
        final index = receivedReviews.indexWhere((item) => item.id == id);
        if (index >= 0) {
          final previous = receivedReviews[index];
          receivedReviews[index] = Review(
            previous.id,
            previous.rating,
            previous.text,
            rentalId: previous.rentalId,
            listingId: previous.listingId,
            listingTitle: previous.listingTitle,
            authorId: previous.authorId,
            authorName: previous.authorName,
            subjectId: previous.subjectId,
            subjectName: previous.subjectName,
            status: previous.status,
            flagged: true,
            createdAt: previous.createdAt,
          );
        }
        notifyListeners();
      });

  Future<void> moderateReview(
    String id,
    String status, {
    String reason = '',
  }) =>
      _perform(() async {
        await api.request(
          'PATCH',
          '/reviews/$id/moderation',
          body: {
            'status': status,
            if (reason.trim().isNotEmpty) 'reason': reason.trim(),
          },
        );
        await loadAdmin();
      });

  Future<void> decideBooking(
    String id,
    String status, {
    String reason = '',
  }) =>
      _perform(() async {
        final updated = Booking.fromJson(
          await api.request(
            'PATCH',
            '/bookings/$id/decision',
            body: {
              'status': status,
              if (reason.trim().isNotEmpty) 'reason': reason.trim(),
            },
          ) as Map<String, dynamic>,
        );
        _replaceBooking(updated);
        if (status == 'approved') await _reloadOwnerRentals();
      });

  void _replaceBooking(Booking booking) {
    final index = bookings.indexWhere((item) => item.id == booking.id);
    if (index < 0) {
      bookings.insert(0, booking);
    } else {
      bookings[index] = booking;
    }
    notifyListeners();
  }

  Future<void> _reloadOwnerRentals() async {
    rentals = _models(
      await api.request('GET', '/rentals/owner'),
      Rental.fromJson,
    );
    notifyListeners();
  }

  Future<void> runRentalAction(
    Rental rental,
    String action, {
    Map<String, dynamic>? body,
    bool owner = false,
  }) =>
      _perform(() async {
        final method = action == 'extension-decision' ? 'PATCH' : 'POST';
        final path = switch (action) {
          'handover' => '/rentals/${rental.id}/handover',
          'start-service' => '/rentals/${rental.id}/start-service',
          'extension' => '/rentals/${rental.id}/extensions',
          'extension-decision' => '/rentals/${rental.id}/extensions/decision',
          'return' => '/rentals/${rental.id}/return',
          'return-confirm' => '/rentals/${rental.id}/return/confirm',
          'service-delivered' => '/rentals/${rental.id}/service-delivered',
          'service-completion' => '/rentals/${rental.id}/service-completion',
          _ => throw ArgumentError('Unknown rental action: $action'),
        };
        await api.request(method, path, body: body);
        rentals = _models(
          await api.request(
            'GET',
            owner ? '/rentals/owner' : '/rentals/mine',
          ),
          Rental.fromJson,
        );
      });

  Future<List<Message>> loadMessages(String threadId) async => _models(
        await api.request('GET', '/messages/threads/$threadId/messages'),
        Message.fromJson,
      );

  Future<Message> sendMessage(String threadId, String text) =>
      _perform(() async {
        final message = Message.fromJson(
          await api.request(
            'POST',
            '/messages/threads/$threadId/messages',
            body: {'text': text},
          ) as Map<String, dynamic>,
        );
        await refreshConversations();
        return message;
      });

  Future<void> markThreadRead(String threadId) async {
    await api.request('POST', '/messages/threads/$threadId/read');
    await refreshConversations();
  }

  Future<void> reportMessage(
    String messageId,
    String reason,
    String details,
  ) =>
      _perform(() async {
        await api.request(
          'POST',
          '/messages/$messageId/report',
          body: {
            'reason': reason,
            if (details.trim().isNotEmpty) 'details': details.trim(),
          },
        );
      });

  Future<void> refreshConversations() async {
    conversations = _models(
      await api.request('GET', '/messages/threads'),
      Conversation.fromJson,
    );
    notifyListeners();
  }

  Future<void> loadNotifications({String? category}) => _perform(() async {
        final suffix = category == null ? '' : '?category=$category';
        notifications = _models(
          await api.request('GET', '/messages/notifications$suffix'),
          RentHubNotification.fromJson,
        );
      });

  Future<void> markNotificationRead(String id) => _perform(() async {
        await api.request('POST', '/messages/notifications/$id/read');
        await loadNotifications();
      });

  Future<void> markAllNotificationsRead() => _perform(() async {
        await api.request('POST', '/messages/notifications/read-all');
        await loadNotifications();
      });

  Future<void> removeNotification(String id) => _perform(() async {
        await api.request('DELETE', '/messages/notifications/$id');
        notifications.removeWhere((item) => item.id == id);
      });

  Future<void> clearNotifications() => _perform(() async {
        await api.request('DELETE', '/messages/notifications');
        notifications = [];
      });

  Future<Listing> createOwnerListing(Map<String, dynamic> payload) =>
      _perform(() async {
        var listing = Listing.fromJson(
          await api.request('POST', '/listings', body: payload)
              as Map<String, dynamic>,
        );
        listing = Listing.fromJson(
          await api.request('POST', '/listings/${listing.id}/submit')
              as Map<String, dynamic>,
        );
        ownerListings.insert(0, listing);
        notifyListeners();
        return listing;
      });

  Future<void> deactivateListing(String id) => _perform(() async {
        final listing = Listing.fromJson(
          await api.request('DELETE', '/listings/$id') as Map<String, dynamic>,
        );
        final index = ownerListings.indexWhere((item) => item.id == id);
        if (index >= 0) ownerListings[index] = listing;
      });

  Future<void> changeAccountStatus(
    String mongoId,
    String status,
    String reason,
  ) =>
      _perform(() async {
        await api.request(
          'PATCH',
          '/users/$mongoId/status',
          body: {'status': status, 'reason': reason},
        );
        await loadAdmin();
      });

  Future<void> resolveMessageReport(
    String id,
    String status,
    String resolution,
  ) =>
      _perform(() async {
        await api.request(
          'PATCH',
          '/messages/reports/$id',
          body: {'status': status, 'resolution': resolution},
        );
        await loadAdmin();
      });

  Future<void> moderateListing(
    String id,
    String status, {
    String reason = '',
  }) =>
      _perform(() async {
        await api.request(
          'PATCH',
          '/listings/$id/moderation',
          body: {
            'status': status,
            if (reason.trim().isNotEmpty) 'reason': reason.trim(),
          },
        );
        await loadAdmin();
      });

  Future<void> refundTransaction(
    String id,
    double amount,
    String reason,
  ) =>
      _perform(() async {
        await api.request(
          'POST',
          '/payments/$id/refunds',
          body: {
            'amount': amount,
            'reason': reason,
            'idempotencyKey':
                'admin-refund:$id:${DateTime.now().millisecondsSinceEpoch}',
          },
        );
        await loadAdmin();
      });

  @override
  void dispose() {
    _socketSubscription?.cancel();
    _socket?.dispose();
    _realtimeMessages.close();
    super.dispose();
  }
}
