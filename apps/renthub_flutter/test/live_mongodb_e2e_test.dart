import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:renthub_flutter/core/config/backend_mode.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/network/session_identity.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';

const _phase = String.fromEnvironment('LIVE_E2E_PHASE');
const _runId = String.fromEnvironment(
  'LIVE_E2E_RUN_ID',
  defaultValue: 'local',
);
const _baseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:3000/api/v1',
);
const _socketUrl = String.fromEnvironment(
  'SOCKET_URL',
  defaultValue: 'http://localhost:3000',
);

const _ownerId = 'u-e2e-owner';
const _renterId = 'u-e2e-renter';
const _listingTitle = 'RentHub E2E Persistence Drill $_runId';
const _messageText = 'E2E persistence message $_runId';
const _persistedRenterName = 'E2E Renter Persisted';

String? _token(String name) {
  final value = Platform.environment[name]?.trim();
  return value == null || value.isEmpty ? null : value;
}

final _ownerToken = _token('RENTHUB_E2E_OWNER_TOKEN');
final _renterToken = _token('RENTHUB_E2E_RENTER_TOKEN');
final _adminToken = _token('RENTHUB_E2E_ADMIN_TOKEN');

final _probePng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

class _LiveClient {
  _LiveClient(this.bearerToken) {
    api = ApiClient(
      _baseUrl,
      tokenProvider: bearerToken == null ? null : () async => bearerToken,
      headersProvider:
          bearerToken == null ? () async => session.mockHeaders : null,
    );
    controller = LiveRentHubController(api, socketUrl: _socketUrl);
  }

  final SessionIdentity session = SessionIdentity();
  final String? bearerToken;
  late final ApiClient api;
  late final LiveRentHubController controller;

  Future<void> start({
    required String id,
    required String email,
    required String name,
    required UserRole role,
  }) async {
    if (bearerToken == null) {
      session.set(
        id: id,
        email: email,
        name: name,
        assignedRoles: {role},
      );
    }
    await api.request('POST', '/users/session');
  }

  Future<String> upload(String purpose, {bool publicUrl = false}) async {
    final result = await api.uploadFile(
      '/uploads',
      bytes: _probePng,
      filename: '$purpose-$_runId.png',
      purpose: purpose,
    );
    return result[publicUrl ? 'contentUrl' : 'reference'] as String;
  }

  void dispose() => controller.dispose();
}

void main() {
  test(
    'writes a complete Flutter to API to MongoDB lifecycle',
    () async {
      expect(BackendMode.useMocks, isFalse);

      final owner = _LiveClient(_ownerToken);
      final renter = _LiveClient(_renterToken);
      final admin = _LiveClient(_adminToken);
      addTearDown(owner.dispose);
      addTearDown(renter.dispose);
      addTearDown(admin.dispose);

      await owner.start(
        id: _ownerId,
        email: 'e2e-owner@renthub.my',
        name: 'E2E Owner',
        role: UserRole.owner,
      );
      await renter.start(
        id: _renterId,
        email: 'e2e-renter@renthub.my',
        name: 'E2E Renter',
        role: UserRole.renter,
      );
      await admin.start(
        id: 'u-admin',
        email: 'admin@renthub.my',
        name: 'Admin Farah',
        role: UserRole.admin,
      );

      await owner.controller.loadOwner();
      final listingImage = await owner.upload(
        'listing_image',
        publicUrl: true,
      );
      final listingImageTwo = await owner.upload(
        'listing_image',
        publicUrl: true,
      );
      final listingImageThree = await owner.upload(
        'listing_image',
        publicUrl: true,
      );
      final listing = await owner.controller.createOwnerListing({
        'title': _listingTitle,
        'description':
            'A persistent physical listing created by the live Flutter controller.',
        'category': 'Equipment',
        'listingType': 'physical',
        'dailyPrice': 41,
        'condition': 'Excellent',
        'securityDeposit': 100,
        'damageWaiverAvailable': false,
        'damageWaiverFee': 0,
        'fulfilmentMethods': ['pickup'],
        'location': 'Petaling Jaya, Selangor',
        'state': 'Selangor',
        'images': [listingImage, listingImageTwo, listingImageThree],
      });
      expect(listing.status, 'pending_review');

      await admin.controller.loadAdmin();
      await admin.controller.moderateListing(listing.id, 'active');
      expect(
        admin.controller.adminListings
            .firstWhere((item) => item.id == listing.id)
            .status,
        'active',
      );

      await renter.controller.loadRenter();
      final visibleListing = renter.controller.listings.firstWhere(
        (item) => item.id == listing.id,
      );
      final checkoutKey = 'checkout:e2e:$_runId:${listing.id}';
      final booking = await renter.controller.createAndAuthorizeBooking(
        listing: visibleListing,
        start: DateTime.utc(2030, 9, 20),
        end: DateTime.utc(2030, 9, 21),
        paymentMethod: 'card',
        fulfilmentMethod: 'pickup',
        renterNote: 'Live MongoDB persistence verification',
        idempotencyKey: checkoutKey,
      );
      expect(booking.paymentStatus, 'authorized');
      expect(booking.total, 182);

      final firstRetry = await renter.api.request(
        'POST',
        '/payments/authorizations',
        body: {
          'bookingId': booking.id,
          'method': 'card',
          'idempotencyKey': checkoutKey,
        },
      ) as Map<String, dynamic>;
      final secondRetry = await renter.api.request(
        'POST',
        '/payments/authorizations',
        body: {
          'bookingId': booking.id,
          'method': 'card',
          'idempotencyKey': checkoutKey,
        },
      ) as Map<String, dynamic>;
      expect(firstRetry['publicId'], secondRetry['publicId']);

      await owner.controller.loadOwner();
      final ownerBooking = owner.controller.bookings.firstWhere(
        (item) => item.id == booking.id,
      );
      expect(ownerBooking.id, booking.id);
      await owner.controller.decideBooking(booking.id, 'approved');
      var rental = owner.controller.rentals.firstWhere(
        (item) => item.bookingId == booking.id,
      );
      final handoverEvidence = await owner.upload('handover_evidence');
      await owner.controller.runRentalAction(
        rental,
        'handover',
        owner: true,
        body: {
          'condition': 'Excellent',
          'notes': 'E2E handover recorded from the live Flutter controller.',
          'evidence': [handoverEvidence],
        },
      );

      await renter.controller.loadRenter();
      rental = renter.controller.rentals.firstWhere(
        (item) => item.bookingId == booking.id,
      );
      expect(rental.status, 'active');
      final conversation = renter.controller.conversations.firstWhere(
        (item) => item.bookingId == booking.id,
      );
      await renter.controller.sendMessage(conversation.id, _messageText);
      final returnEvidence = await renter.upload('return_evidence');
      await renter.controller.runRentalAction(
        rental,
        'return',
        body: {
          'condition': 'Excellent',
          'notes': 'Returned during the E2E persistence verification.',
          'evidence': [returnEvidence],
        },
      );

      await owner.controller.loadOwner();
      rental = owner.controller.rentals.firstWhere(
        (item) => item.bookingId == booking.id,
      );
      expect(rental.status, 'return_submitted');
      await owner.controller.runRentalAction(
        rental,
        'return-confirm',
        owner: true,
        body: {
          'condition': 'Excellent',
          'notes': 'No damage or deposit deduction.',
          'depositDeduction': 0,
        },
      );

      await renter.controller.loadRenter();
      rental = renter.controller.rentals.firstWhere(
        (item) => item.bookingId == booking.id,
      );
      expect(rental.status, 'completed');
      final review = await renter.controller.submitReview(
        rental: rental,
        overallRating: 5,
        communicationRating: 5,
        conditionRating: 5,
        valueRating: 5,
        text: 'The live E2E rental persisted correctly from start to finish.',
      );
      expect(review.listingId, listing.id);

      final updatedProfile = await renter.api.request(
        'PATCH',
        '/users/me',
        body: {'displayName': _persistedRenterName},
      ) as Map<String, dynamic>;
      expect(updatedProfile['displayName'], _persistedRenterName);

      final payments = await renter.api.request(
        'GET',
        '/payments/booking/${booking.id}',
      ) as List;
      expect(payments.length, greaterThanOrEqualTo(4));
      expect(
        payments.map((item) => item['type']),
        containsAll(['authorization', 'capture', 'deposit_release']),
      );
      await renter.controller.loadNotifications();
      expect(
        renter.controller.notifications.any(
          (item) => item.entityId == rental.id || item.entityId == booking.id,
        ),
        isTrue,
      );

      // Printed values are safe deterministic identifiers used by the restart check.
      // ignore: avoid_print
      print('LIVE_E2E_LISTING_ID=${listing.id}');
      // ignore: avoid_print
      print('LIVE_E2E_BOOKING_ID=${booking.id}');
      // ignore: avoid_print
      print('LIVE_E2E_RENTAL_ID=${rental.id}');
    },
    skip: _phase != 'write',
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'reads the same persisted lifecycle after a Flutter process restart',
    () async {
      expect(BackendMode.useMocks, isFalse);

      final owner = _LiveClient(_ownerToken);
      final renter = _LiveClient(_renterToken);
      final admin = _LiveClient(_adminToken);
      addTearDown(owner.dispose);
      addTearDown(renter.dispose);
      addTearDown(admin.dispose);

      await owner.start(
        id: _ownerId,
        email: 'e2e-owner@renthub.my',
        name: 'E2E Owner',
        role: UserRole.owner,
      );
      await renter.start(
        id: _renterId,
        email: 'e2e-renter@renthub.my',
        name: _persistedRenterName,
        role: UserRole.renter,
      );
      await admin.start(
        id: 'u-admin',
        email: 'admin@renthub.my',
        name: 'Admin Farah',
        role: UserRole.admin,
      );

      await renter.controller.loadRenter();
      final renterBooking = renter.controller.bookings.firstWhere(
        (item) => item.listingTitle == _listingTitle,
      );
      final rental = renter.controller.rentals.firstWhere(
        (item) => item.bookingId == renterBooking.id,
      );
      final conversation = renter.controller.conversations.firstWhere(
        (item) => item.bookingId == renterBooking.id,
      );
      final messages = await renter.controller.loadMessages(conversation.id);

      expect(renter.controller.profile?.name, _persistedRenterName);
      expect(renterBooking.status, 'completed');
      expect(renterBooking.paymentStatus, 'settled');
      expect(rental.status, 'completed');
      expect(messages.any((item) => item.text == _messageText), isTrue);
      expect(
        renter.controller.reviews.any(
          (item) => item.listingTitle == _listingTitle && item.rating == 5,
        ),
        isTrue,
      );

      await owner.controller.loadOwner();
      final ownerListing = owner.controller.ownerListings.firstWhere(
        (item) => item.title == _listingTitle,
      );
      final ownerBooking = owner.controller.bookings.firstWhere(
        (item) => item.id == renterBooking.id,
      );
      expect(ownerListing.status, 'active');
      expect(ownerBooking.id, renterBooking.id);
      expect(ownerBooking.status, 'completed');

      await admin.controller.loadAdmin();
      expect(
        admin.controller.transactions.any(
          (item) => item.bookingId == renterBooking.id,
        ),
        isTrue,
      );
      expect(
        admin.controller.adminListings.any(
          (item) => item.id == ownerListing.id && item.status == 'active',
        ),
        isTrue,
      );

      // ignore: avoid_print
      print('LIVE_E2E_RESTART_BOOKING_ID=${renterBooking.id}');
    },
    skip: _phase != 'read',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
