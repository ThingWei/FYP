import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';

import '../../core/network/api_client.dart';
import '../../core/network/idempotency_key.dart';
import '../../core/network/socket_service.dart';
import '../../core/notifications/push_notification_service.dart';
import '../../core/utils/calendar_date.dart';
import '../../shared/models/domain_models.dart';

class LiveRentHubController extends ChangeNotifier {
  LiveRentHubController(
    this.api, {
    this.socketUrl = 'http://localhost:3000',
    this.pushNotifications,
  });

  final ApiClient api;
  final String socketUrl;
  final PushNotificationService? pushNotifications;
  final _realtimeMessages = StreamController<Message>.broadcast();
  SocketService? _socket;
  StreamSubscription<dynamic>? _socketSubscription;
  String? _socketUserId;

  bool loading = false;
  String? error;
  User? profile;
  List<Listing> listings = [];
  List<Listing> recommendedListings = [];
  List<Listing> savedListings = [];
  List<Listing> comparisonListings = [];
  List<Listing> ownerListings = [];
  List<Listing> adminListings = [];
  List<Booking> bookings = [];
  List<Rental> rentals = [];
  List<Conversation> conversations = [];
  List<RentHubNotification> notifications = [];
  List<Map<String, dynamic>> notificationDevices = [];
  List<Map<String, dynamic>> loginSessions = [];
  List<Transaction> transactions = [];
  List<Review> reviews = [];
  List<Review> receivedReviews = [];
  List<Review> adminReviews = [];
  List<Dispute> disputes = [];
  List<InsuranceClaim> claims = [];
  List<Dispute> adminDisputes = [];
  List<InsuranceClaim> adminClaims = [];
  List<Map<String, dynamic>> users = [];
  List<Map<String, dynamic>> messageReports = [];
  List<Map<String, dynamic>> moderationReports = [];
  List<Map<String, dynamic>> auditLogs = [];
  List<Map<String, dynamic>> generatedReports = [];
  List<Map<String, dynamic>> reportSchedules = [];
  Reward? loyalty;
  Map<String, dynamic> loyaltyConfig = {};
  Map<String, dynamic> platformSettings = {};
  Map<String, dynamic> technologyHealth = {};
  List<Map<String, dynamic>> adminRewardLedger = [];
  List<Map<String, dynamic>> adminReferrals = [];
  int renterTabIndex = 0;

  void selectRenterTab(int index) {
    if (index < 0 || index > 4 || renterTabIndex == index) return;
    renterTabIndex = index;
    notifyListeners();
  }

  Future<String?> pickAndUpload({
    required String purpose,
    bool allowPdf = false,
    bool publicUrl = false,
  }) async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: [
        'jpg',
        'jpeg',
        'png',
        'webp',
        if (allowPdf) 'pdf',
      ],
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) throw ApiException(400, 'The selected file is empty.');
    final uploaded = await _perform(
      () => api.uploadFile(
        '/uploads',
        bytes: bytes,
        filename: file.name,
        purpose: purpose,
      ),
    );
    return uploaded[publicUrl ? 'contentUrl' : 'reference'] as String;
  }

  Future<String> uploadVerificationCapture(
    Uint8List bytes, {
    required String filename,
  }) async {
    if (bytes.isEmpty) throw ApiException(400, 'The captured image is empty.');
    final uploaded = await _perform(
      () => api.uploadFile(
        '/uploads',
        bytes: bytes,
        filename: filename,
        purpose: 'verification_document',
      ),
    );
    return uploaded['reference'] as String;
  }

  Future<Map<String, dynamic>> inspectVerificationFrame(
    Uint8List bytes,
    String documentType, {
    String? expectedSide,
    bool validateCapture = false,
  }) async =>
      Map<String, dynamic>.from(
        await api.request(
          'POST',
          '/users/me/verification/scan-frame',
          body: {
            'contentBase64': base64Encode(bytes),
            'contentType': 'image/jpeg',
            'documentType': documentType,
            if (expectedSide != null) 'expectedSide': expectedSide,
            'validateCapture': validateCapture,
          },
        ) as Map,
      );

  Future<Map<String, dynamic>> verificationRequirements({
    required String category,
    double? dailyPrice,
  }) async {
    final query = Uri(
      queryParameters: {
        'category': category,
        if (dailyPrice != null) 'dailyPrice': '$dailyPrice',
      },
    ).query;
    return Map<String, dynamic>.from(
      await api.request(
        'GET',
        '/users/me/verification/requirements?$query',
      ) as Map,
    );
  }

  Future<void> deleteUpload(String reference) async {
    final match =
        RegExp(r'UPL-[A-Z0-9]+', caseSensitive: false).firstMatch(reference);
    if (match == null) return;
    await api.request('DELETE', '/uploads/${match.group(0)}');
  }

  Future<Uint8List> downloadProtectedUpload(String reference) {
    final match =
        RegExp(r'UPL-[A-Z0-9]+', caseSensitive: false).firstMatch(reference);
    if (match == null) {
      throw ApiException(400, 'The protected upload reference is invalid.');
    }
    return api.downloadBytes('/api/v1/uploads/${match.group(0)}/content');
  }

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
          api.request('GET', '/disputes/mine'),
          api.request('GET', '/disputes/claims/mine'),
          api.request('GET', '/rewards/summary'),
          api.request('GET', '/users/me/saved-listings'),
          api.request('GET', '/users/me/comparison'),
          api.request('GET', '/listings/recommended?limit=10'),
        ]);
        profile = User.fromJson(results[0] as Map<String, dynamic>);
        await _connectRealtime(profile!.id);
        listings = _models(results[1], Listing.fromJson);
        bookings = _models(results[2], Booking.fromJson);
        rentals = _models(results[3], Rental.fromJson);
        conversations = _models(results[4], Conversation.fromJson);
        reviews = _models(results[5], Review.fromJson);
        disputes = _models(results[6], Dispute.fromJson);
        claims = _models(results[7], InsuranceClaim.fromJson);
        loyalty = Reward.fromJson(results[8] as Map<String, dynamic>);
        savedListings = _models(results[9], Listing.fromJson);
        comparisonListings = _models(results[10], Listing.fromJson);
        recommendedListings = _models(results[11], Listing.fromJson);
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
          api.request('GET', '/disputes/mine'),
          api.request('GET', '/disputes/claims/mine'),
          api.request('GET', '/rewards/summary'),
        ]);
        profile = User.fromJson(results[0] as Map<String, dynamic>);
        await _connectRealtime(profile!.id);
        ownerListings = _models(results[1], Listing.fromJson);
        bookings = _models(results[2], Booking.fromJson);
        rentals = _models(results[3], Rental.fromJson);
        conversations = _models(results[4], Conversation.fromJson);
        receivedReviews = _models(results[5], Review.fromJson);
        reviews = _models(results[6], Review.fromJson);
        disputes = _models(results[7], Dispute.fromJson);
        claims = _models(results[8], InsuranceClaim.fromJson);
        loyalty = Reward.fromJson(results[9] as Map<String, dynamic>);
      });

  Future<void> loadAdmin() => _perform(() async {
        final results = await Future.wait([
          api.request('GET', '/users/me'),
          api.request('GET', '/users?limit=100'),
          api.request('GET', '/listings/admin'),
          api.request('GET', '/bookings/admin'),
          api.request('GET', '/rentals/admin'),
          api.request('GET', '/payments'),
          api.request('GET', '/messages/reports'),
          api.request('GET', '/reviews/admin'),
          api.request('GET', '/disputes/admin'),
          api.request('GET', '/disputes/claims/admin'),
          api.request('GET', '/admin'),
          api.request('GET', '/rewards/admin/config'),
          api.request('GET', '/rewards/admin/ledger'),
          api.request('GET', '/rewards/admin/referrals'),
          api.request('GET', '/admin/reports'),
          api.request('GET', '/admin/settings'),
          api.request('GET', '/admin/technology-health'),
          api.request('GET', '/admin/reporting/schedules'),
          api.request('GET', '/admin/reporting/reports'),
        ]);
        profile = User.fromJson(results[0] as Map<String, dynamic>);
        users = (results[1] as List).cast<Map<String, dynamic>>();
        adminListings = _models(results[2], Listing.fromJson);
        bookings = _models(results[3], Booking.fromJson);
        rentals = _models(results[4], Rental.fromJson);
        transactions = _models(results[5], Transaction.fromJson);
        messageReports = (results[6] as List).cast<Map<String, dynamic>>();
        adminReviews = _models(results[7], Review.fromJson);
        adminDisputes = _models(results[8], Dispute.fromJson);
        adminClaims = _models(results[9], InsuranceClaim.fromJson);
        auditLogs = (results[10] as List).cast<Map<String, dynamic>>();
        loyaltyConfig = results[11] as Map<String, dynamic>;
        adminRewardLedger = (results[12] as List).cast<Map<String, dynamic>>();
        adminReferrals = (results[13] as List).cast<Map<String, dynamic>>();
        moderationReports = (results[14] as List).cast<Map<String, dynamic>>();
        platformSettings = results[15] as Map<String, dynamic>;
        technologyHealth = results[16] as Map<String, dynamic>;
        reportSchedules = (results[17] as List).cast<Map<String, dynamic>>();
        generatedReports = (results[18] as List).cast<Map<String, dynamic>>();
      });

  Future<void> runLifecycleAutomation() => _perform(() async {
        await api.request('POST', '/admin/lifecycle/run');
        technologyHealth = await api.request(
          'GET',
          '/admin/technology-health',
        ) as Map<String, dynamic>;
        auditLogs = (await api.request('GET', '/admin') as List)
            .cast<Map<String, dynamic>>();
      });

  Future<void> generateAdminReport({
    required String reportType,
    required int rangeDays,
  }) =>
      _perform(() async {
        final report = await api.request(
          'POST',
          '/admin/reporting/reports',
          body: {'reportType': reportType, 'rangeDays': rangeDays},
        ) as Map<String, dynamic>;
        generatedReports.insert(0, report);
        auditLogs = (await api.request('GET', '/admin') as List)
            .cast<Map<String, dynamic>>();
      });

  Future<void> createReportSchedule({
    required String name,
    required String reportType,
    required String cadence,
    required int rangeDays,
  }) =>
      _perform(() async {
        final schedule = await api.request(
          'POST',
          '/admin/reporting/schedules',
          body: {
            'name': name,
            'reportType': reportType,
            'cadence': cadence,
            'rangeDays': rangeDays,
          },
        ) as Map<String, dynamic>;
        reportSchedules.insert(0, schedule);
      });

  Future<void> setReportScheduleEnabled(
    Map<String, dynamic> schedule,
    bool enabled,
  ) =>
      _perform(() async {
        final id = (schedule['publicId'] ?? schedule['id']) as String;
        final updated = await api.request(
          'PATCH',
          '/admin/reporting/schedules/$id',
          body: {'enabled': enabled},
        ) as Map<String, dynamic>;
        final index = reportSchedules.indexWhere(
          (item) => (item['publicId'] ?? item['id']) == id,
        );
        if (index >= 0) reportSchedules[index] = updated;
      });

  Future<bool> downloadAdminReport(Map<String, dynamic> report) =>
      _perform(() async {
        final id = (report['publicId'] ?? report['id']) as String;
        final payload = await api.request(
          'GET',
          '/admin/reporting/reports/$id/download',
        ) as Map<String, dynamic>;
        final saved = await FilePicker.saveFile(
          fileName: payload['fileName'] as String,
          bytes: Uint8List.fromList(
            utf8.encode(payload['content'] as String),
          ),
          mimeType: payload['mimeType'] as String,
          type: FileType.custom,
          allowedExtensions: const ['csv'],
          dialogTitle: 'Save RentHub report',
        );
        return saved != null;
      });

  Future<List<Listing>> discoverListings(
    Map<String, String> parameters,
  ) async {
    final query = Uri(queryParameters: {
      for (final entry in parameters.entries)
        if (entry.value.trim().isNotEmpty) entry.key: entry.value.trim(),
    }).query;
    return _models(
      await api.request('GET', '/listings${query.isEmpty ? '' : '?$query'}'),
      Listing.fromJson,
    );
  }

  Future<List<Listing>> recommendListings(
    Map<String, String> parameters,
  ) async {
    final query = Uri(queryParameters: {
      for (final entry in parameters.entries)
        if (entry.value.trim().isNotEmpty) entry.key: entry.value.trim(),
    }).query;
    return _models(
      await api.request(
        'GET',
        '/listings/recommended${query.isEmpty ? '' : '?$query'}',
      ),
      Listing.fromJson,
    );
  }

  bool isSaved(String listingId) =>
      savedListings.any((listing) => listing.id == listingId);

  bool isCompared(String listingId) =>
      comparisonListings.any((listing) => listing.id == listingId);

  Future<void> toggleSavedListing(Listing listing) => _perform(() async {
        if (isSaved(listing.id)) {
          await api.request('DELETE', '/users/me/saved-listings/${listing.id}');
          savedListings.removeWhere((item) => item.id == listing.id);
        } else {
          final saved = Listing.fromJson(
            await api.request('PUT', '/users/me/saved-listings/${listing.id}')
                as Map<String, dynamic>,
          );
          savedListings.insert(0, saved);
        }
      });

  Future<void> toggleComparisonListing(Listing listing) => _perform(() async {
        final ids = comparisonListings.map((item) => item.id).toList();
        if (ids.remove(listing.id)) {
          // The item was already selected and is now removed.
        } else {
          if (ids.length >= 4) {
            throw ApiException(
              409,
              'You can compare up to four listings at a time.',
              code: 'COMPARISON_LIMIT',
            );
          }
          ids.add(listing.id);
        }
        comparisonListings = _models(
          await api.request(
            'PUT',
            '/users/me/comparison',
            body: {'listingIds': ids},
          ),
          Listing.fromJson,
        );
      });

  Future<void> clearComparison() => _perform(() async {
        await api.request(
          'PUT',
          '/users/me/comparison',
          body: {'listingIds': <String>[]},
        );
        comparisonListings = [];
      });

  Future<void> submitModerationReport({
    required String targetType,
    required String targetId,
    required String reason,
    String details = '',
  }) =>
      _perform(() async {
        await api.request(
          'POST',
          '/admin/reports',
          body: {
            'targetType': targetType,
            'targetId': targetId,
            'reason': reason,
            'details': details.trim(),
          },
        );
      });

  Future<void> blockUser(String userId) => _perform(() async {
        profile = User.fromJson(
          await api.request('POST', '/users/me/blocked-users/$userId')
              as Map<String, dynamic>,
        );
      });

  Future<void> loadRewards() => _perform(() async {
        loyalty = Reward.fromJson(
          await api.request('GET', '/rewards/summary') as Map<String, dynamic>,
        );
      });

  Future<void> redeemReward(int points) => _perform(() async {
        loyalty = Reward.fromJson(
          await api.request(
            'POST',
            '/rewards/redeem',
            body: {'points': points},
          ) as Map<String, dynamic>,
        );
      });

  Future<void> applyReferralCode(String code) => _perform(() async {
        await api.request(
          'POST',
          '/rewards/referrals/apply',
          body: {'referralCode': code.trim().toUpperCase()},
        );
        loyalty = Reward.fromJson(
          await api.request('GET', '/rewards/summary') as Map<String, dynamic>,
        );
      });

  Future<void> updateProfile({
    required String displayName,
    required String phone,
  }) =>
      _perform(() async {
        profile = User.fromJson(
          await api.request(
            'PATCH',
            '/users/me',
            body: {
              'displayName': displayName.trim(),
              'phone': phone.trim(),
            },
          ) as Map<String, dynamic>,
        );
      });

  Future<void> updateAddresses(List<UserAddress> addresses) =>
      _perform(() async {
        profile = User.fromJson(
          await api.request(
            'PATCH',
            '/users/me',
            body: {
              'addresses': addresses.map((item) => item.toJson()).toList(),
            },
          ) as Map<String, dynamic>,
        );
      });

  Future<void> updateAccountSettings({
    required String language,
    required bool pushNotifications,
    required bool emailNotifications,
  }) =>
      _perform(() async {
        profile = User.fromJson(
          await api.request(
            'PATCH',
            '/users/me',
            body: {
              'settings': {
                'language': language,
                'pushNotifications': pushNotifications,
                'emailNotifications': emailNotifications,
              },
            },
          ) as Map<String, dynamic>,
        );
        final service = this.pushNotifications;
        if (service != null) {
          if (pushNotifications) {
            await service.enableForCurrentUser();
          } else {
            await service.disableForCurrentUser();
          }
        }
      });

  Future<void> deactivateAccount(String reason) => _perform(() async {
        await api.request(
          'POST',
          '/users/me/deactivate',
          body: {'confirmation': true, 'reason': reason.trim()},
        );
        await _socketSubscription?.cancel();
        _socketSubscription = null;
        _socket?.dispose();
        _socket = null;
        _socketUserId = null;
        pushNotifications?.forgetCurrentUser();
        profile = null;
      });

  Future<void> submitIdentityVerification(
    String documentType,
    List<String> documentRefs,
  ) =>
      _perform(() async {
        profile = User.fromJson(
          await api.request(
            'POST',
            documentType == 'driving_licence'
                ? '/users/me/driving-eligibility'
                : '/users/me/verification',
            body: {
              'documentType': documentType,
              'documentRefs': documentRefs,
            },
          ) as Map<String, dynamic>,
        );
      });

  Future<void> reviewIdentityVerification(
    String userId,
    String status, {
    String tier = 'basic',
    String reason = '',
    String? attemptId,
    bool driving = false,
    List<String>? licenceClasses,
    String? expiresAt,
    bool identityMatchConfirmed = false,
    bool classReviewConfirmed = false,
  }) =>
      _perform(() async {
        final updated = await api.request(
          'PATCH',
          driving
              ? '/users/$userId/driving-eligibility'
              : '/users/$userId/verification',
          body: {
            'status': status,
            if (status == 'approved') 'tier': tier,
            if (reason.trim().isNotEmpty) 'reason': reason.trim(),
            if (attemptId != null) 'attemptId': attemptId,
            if (driving && status == 'approved') ...{
              'licenceClasses': licenceClasses,
              'expiresAt': expiresAt,
              'identityMatchConfirmed': identityMatchConfirmed,
              'classReviewConfirmed': classReviewConfirmed,
            },
          },
        ) as Map<String, dynamic>;
        final index = users.indexWhere((item) => item['_id'] == userId);
        if (index >= 0) users[index] = updated;
      });

  Future<void> updateLoyaltyConfig(Map<String, dynamic> input) =>
      _perform(() async {
        loyaltyConfig = await api.request(
          'PUT',
          '/rewards/admin/config',
          body: input,
        ) as Map<String, dynamic>;
        adminRewardLedger = (await api.request(
          'GET',
          '/rewards/admin/ledger',
        ) as List)
            .cast<Map<String, dynamic>>();
        auditLogs = (await api.request('GET', '/admin') as List)
            .cast<Map<String, dynamic>>();
      });

  Dispute? disputeForRental(String rentalId) {
    for (final dispute in disputes) {
      if (dispute.rentalId == rentalId) return dispute;
    }
    return null;
  }

  InsuranceClaim? claimForRental(String rentalId) {
    for (final claim in claims) {
      if (claim.rentalId == rentalId) return claim;
    }
    return null;
  }

  Future<Map<String, dynamic>> loadDisputeCase(String id) async =>
      (await api.request('GET', '/disputes/$id')) as Map<String, dynamic>;

  Future<Dispute> createDispute({
    required Rental rental,
    required String category,
    required String summary,
    required String description,
    List<String> evidence = const [],
  }) =>
      _perform(() async {
        final dispute = Dispute.fromJson(
          await api.request(
            'POST',
            '/disputes',
            body: {
              'rentalId': rental.id,
              'category': category,
              'summary': summary.trim(),
              'description': description.trim(),
              'evidence': evidence,
            },
          ) as Map<String, dynamic>,
        );
        disputes.insert(0, dispute);
        rentals = rentals
            .map((item) => item.id == rental.id
                ? Rental(
                    item.id,
                    'disputed',
                    bookingId: item.bookingId,
                    listingId: item.listingId,
                    listingType: item.listingType,
                    renterId: item.renterId,
                    ownerId: item.ownerId,
                    start: item.start,
                    end: item.end,
                    extensionStatus: item.extensionStatus,
                    blockchainStatus: item.blockchainStatus,
                    contractAddress: item.contractAddress,
                    blockchainTransactionHash: item.blockchainTransactionHash,
                  )
                : item)
            .toList();
        notifyListeners();
        return dispute;
      });

  Future<Dispute> respondToDispute(
    Dispute dispute,
    String text, {
    List<String> evidence = const [],
  }) =>
      _perform(() async {
        final updated = Dispute.fromJson(
          await api.request(
            'POST',
            '/disputes/${dispute.id}/responses',
            body: {'text': text.trim(), 'evidence': evidence},
          ) as Map<String, dynamic>,
        );
        _replaceDispute(updated, disputes);
        return updated;
      });

  Future<InsuranceClaim> submitClaim({
    required Dispute dispute,
    required String description,
    required double amount,
    required List<String> evidence,
  }) =>
      _perform(() async {
        final claim = InsuranceClaim.fromJson(
          await api.request(
            'POST',
            '/disputes/${dispute.id}/claims',
            body: {
              'description': description.trim(),
              'amountRequested': amount,
              'evidence': evidence,
            },
          ) as Map<String, dynamic>,
        );
        claims.insert(0, claim);
        notifyListeners();
        return claim;
      });

  Future<void> updateDisputeStatus(
    Dispute dispute,
    String status,
    String note,
  ) =>
      _perform(() async {
        final updated = Dispute.fromJson(
          await api.request(
            'PATCH',
            '/disputes/${dispute.id}/review-status',
            body: {'status': status, 'note': note.trim()},
          ) as Map<String, dynamic>,
        );
        _replaceDispute(updated, adminDisputes);
      });

  Future<void> resolveDispute({
    required Dispute dispute,
    required String outcome,
    required String notes,
    double? renterAmount,
    double? ownerAmount,
  }) =>
      _perform(() async {
        final updated = Dispute.fromJson(
          await api.request(
            'PATCH',
            '/disputes/${dispute.id}/resolve',
            body: {
              'outcome': outcome,
              'notes': notes.trim(),
              if (renterAmount != null) 'renterAmount': renterAmount,
              if (ownerAmount != null) 'ownerAmount': ownerAmount,
            },
          ) as Map<String, dynamic>,
        );
        _replaceDispute(updated, adminDisputes);
      });

  Future<void> decideClaim({
    required InsuranceClaim claim,
    required String status,
    required String reason,
    double? approvedAmount,
  }) =>
      _perform(() async {
        final updated = InsuranceClaim.fromJson(
          await api.request(
            'PATCH',
            '/disputes/claims/${claim.id}/decision',
            body: {
              'status': status,
              'reason': reason.trim(),
              if (approvedAmount != null) 'approvedAmount': approvedAmount,
            },
          ) as Map<String, dynamic>,
        );
        final index = adminClaims.indexWhere((item) => item.id == updated.id);
        if (index >= 0) adminClaims[index] = updated;
        notifyListeners();
      });

  void _replaceDispute(Dispute dispute, List<Dispute> target) {
    final index = target.indexWhere((item) => item.id == dispute.id);
    if (index < 0) {
      target.insert(0, dispute);
    } else {
      target[index] = dispute;
    }
    notifyListeners();
  }

  Future<void> _connectRealtime(String userId) async {
    if (_socketUserId == userId) return;
    _socketSubscription?.cancel();
    _socket?.dispose();
    _socketUserId = userId;
    _socket = SocketService(
      socketUrl,
      userId: userId,
      tokenProvider: api.authenticationToken,
    )..initializeListeners();
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
    required bool agreementAccepted,
    String? idempotencyKey,
  }) =>
      _perform(() async {
        final checkoutKey = idempotencyKey ?? newCheckoutIdempotencyKey();
        final bookingData = await api.request(
          'POST',
          '/bookings',
          body: {
            'listingId': listing.id,
            'idempotencyKey': checkoutKey,
            'startDate': listing.isService
                ? start.toUtc().toIso8601String()
                : calendarDateApiValue(start),
            'endDate': listing.isService
                ? end.toUtc().toIso8601String()
                : calendarDateApiValue(end),
            if (listing.isService) 'serviceVenue': serviceVenue,
            if (!listing.isService) 'fulfilmentMethod': fulfilmentMethod,
            if (!listing.isService)
              'damageWaiverSelected': damageWaiverSelected,
            if (renterNote.trim().isNotEmpty) 'renterNote': renterNote.trim(),
            'agreementAccepted': agreementAccepted,
            'agreementVersion': 'renthub-booking-v1',
          },
        ) as Map<String, dynamic>;
        var booking = Booking.fromJson(bookingData);
        await api.request(
          'POST',
          '/payments/authorizations',
          body: {
            'bookingId': booking.id,
            'method': paymentMethod,
            'idempotencyKey': checkoutKey,
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
        if (status == 'approved') await _reloadOwnerBookingState();
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

  Future<void> _reloadOwnerBookingState() async {
    final results = await Future.wait([
      api.request('GET', '/bookings/owner'),
      api.request('GET', '/rentals/owner'),
    ]);
    bookings = _models(results[0], Booking.fromJson);
    rentals = _models(results[1], Rental.fromJson);
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

  Future<Message> sendMessage(
    String threadId,
    String text, {
    String? attachmentRef,
  }) =>
      _perform(() async {
        final message = Message.fromJson(
          await api.request(
            'POST',
            '/messages/threads/$threadId/messages',
            body: {
              if (text.trim().isNotEmpty) 'text': text.trim(),
              if (attachmentRef != null) 'attachmentRef': attachmentRef,
            },
          ) as Map<String, dynamic>,
        );
        await refreshConversations();
        return message;
      });

  Future<Message?> pickAndSendMessageImage(String threadId) async {
    final reference = await pickAndUpload(purpose: 'message_image');
    if (reference == null) return null;
    try {
      return await sendMessage(threadId, '', attachmentRef: reference);
    } catch (_) {
      try {
        await deleteUpload(reference);
      } catch (_) {}
      rethrow;
    }
  }

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

  Future<void> loadNotificationDevices() => _perform(() async {
        notificationDevices = (await api.request(
          'GET',
          '/messages/push/devices',
        ) as List)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
      });

  Future<void> removeNotificationDevice(String deviceId) => _perform(() async {
        await api.request('DELETE', '/messages/push/devices/$deviceId');
        notificationDevices.removeWhere(
          (item) => item['deviceId'] == deviceId,
        );
      });

  Future<void> loadLoginSessions() => _perform(() async {
        loginSessions = (await api.request(
          'GET',
          '/users/me/sessions',
        ) as List)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
      });

  Future<void> revokeLoginSession(String sessionId) => _perform(() async {
        await api.request('DELETE', '/users/me/sessions/$sessionId');
        loginSessions.removeWhere((item) => item['id'] == sessionId);
      });

  Future<void> revokeOtherLoginSessions() => _perform(() async {
        await api.request('POST', '/users/me/sessions/revoke-others');
        loginSessions.removeWhere((item) => item['current'] != true);
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

  Future<Map<String, dynamic>> getPriceRecommendation({
    required String category,
    required String subcategory,
    required String condition,
    required String state,
    required String brand,
    required String productModel,
    required double itemAgeYears,
    required int rentalDurationDays,
    String? excludeListingId,
    String? canonicalProductId,
    String? catalogBrandId,
    String productMatchType = 'manual_entry',
    String? catalogSource,
    String? location,
  }) =>
      _perform(() async => await api.request(
            'POST',
            '/listings/price-recommendation',
            body: {
              'itemProfile': {
                'category': category,
                'subcategory': subcategory,
                'condition': condition,
                'brand': brand.trim().isEmpty ? 'Unknown' : brand.trim(),
                'product_model': productModel.trim(),
                'state': state,
                'item_age_years': itemAgeYears,
                'productMatchType': productMatchType,
                if (canonicalProductId?.isNotEmpty ?? false)
                  'canonicalProductId': canonicalProductId,
                if (catalogBrandId?.isNotEmpty ?? false)
                  'catalogBrandId': catalogBrandId,
                if (catalogSource?.isNotEmpty ?? false)
                  'catalogSource': catalogSource,
                if (location?.isNotEmpty ?? false) 'location': location,
              },
              'rentalDurationDays': rentalDurationDays,
              if (excludeListingId != null)
                'excludeListingId': excludeListingId,
            },
          ) as Map<String, dynamic>);

  Future<List<Map<String, dynamic>>> searchCatalogBrands({
    required String category,
    required String subcategory,
    required String query,
  }) async {
    final parameters = Uri(queryParameters: {
      'category': category,
      'subcategory': subcategory,
      'query': query,
    }).query;
    return (await api.request('GET', '/catalog/brands?$parameters') as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> searchCatalogModels({
    required String category,
    required String subcategory,
    required String brand,
    String query = '',
    String? catalogBrandId,
  }) async {
    final parameters = Uri(queryParameters: {
      'category': category,
      'subcategory': subcategory,
      'brand': brand,
      'query': query,
      if (catalogBrandId?.isNotEmpty ?? false)
        'catalogBrandId': catalogBrandId!,
    }).query;
    return (await api.request('GET', '/catalog/models?$parameters') as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  void _replaceOwnerListing(Listing listing) {
    final index = ownerListings.indexWhere((item) => item.id == listing.id);
    if (index >= 0) ownerListings[index] = listing;
  }

  Future<Listing> updateOwnerListing(
    String id,
    Map<String, dynamic> payload,
  ) =>
      _perform(() async {
        var listing = Listing.fromJson(
          await api.request('PATCH', '/listings/$id', body: payload)
              as Map<String, dynamic>,
        );
        if (listing.status == 'draft') {
          listing = Listing.fromJson(
            await api.request('POST', '/listings/$id/submit')
                as Map<String, dynamic>,
          );
        }
        _replaceOwnerListing(listing);
        return listing;
      });

  Future<Map<String, dynamic>> getListingAvailability(String id) async =>
      await api.request('GET', '/listings/$id/availability')
          as Map<String, dynamic>;

  Future<ListingAvailability> getRenterListingAvailability(String id) async =>
      ListingAvailability.fromJson(
        await api.request('GET', '/listings/$id/availability')
            as Map<String, dynamic>,
      );

  Future<void> saveListingAvailability(
    String id,
    Map<String, dynamic> payload,
  ) =>
      _perform(() async {
        await api.request('PUT', '/listings/$id/availability', body: payload);
      });

  Future<void> saveListingPromotion(
    String id,
    Map<String, dynamic> payload,
  ) =>
      _perform(() async {
        final listing = Listing.fromJson(
          await api.request('PUT', '/listings/$id/promotion', body: payload)
              as Map<String, dynamic>,
        );
        _replaceOwnerListing(listing);
      });

  Future<void> clearListingPromotion(String id) => _perform(() async {
        final listing = Listing.fromJson(
          await api.request('DELETE', '/listings/$id/promotion')
              as Map<String, dynamic>,
        );
        _replaceOwnerListing(listing);
      });

  Future<void> saveListingBundle(
    String id,
    Map<String, dynamic> payload,
  ) =>
      _perform(() async {
        final listing = Listing.fromJson(
          await api.request('PUT', '/listings/$id/bundle', body: payload)
              as Map<String, dynamic>,
        );
        _replaceOwnerListing(listing);
      });

  Future<void> clearListingBundle(String id) => _perform(() async {
        final listing = Listing.fromJson(
          await api.request('DELETE', '/listings/$id/bundle')
              as Map<String, dynamic>,
        );
        _replaceOwnerListing(listing);
      });

  Future<void> deactivateListing(String id) => _perform(() async {
        final listing = Listing.fromJson(
          await api.request('DELETE', '/listings/$id') as Map<String, dynamic>,
        );
        _replaceOwnerListing(listing);
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

  Future<void> resolveModerationReport(
    String id,
    String status,
    String resolution,
  ) =>
      _perform(() async {
        await api.request(
          'PATCH',
          '/admin/reports/$id',
          body: {'status': status, 'resolution': resolution},
        );
        await loadAdmin();
      });

  Future<void> updatePlatformSettings(Map<String, dynamic> input) =>
      _perform(() async {
        platformSettings = await api.request(
          'PUT',
          '/admin/settings',
          body: input,
        ) as Map<String, dynamic>;
        auditLogs = (await api.request('GET', '/admin') as List)
            .cast<Map<String, dynamic>>();
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
