import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/features/live/live_identity_policy.dart';
import 'package:renthub_flutter/features/live/live_owner_shell.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/features/live/live_shared_pages.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';

Map<String, dynamic> profileJson(String status,
        {String documentType = 'mykad'}) =>
    {
      'authId': 'u-member',
      'displayName': 'Synthetic User',
      'email': 'member@example.com',
      'roles': ['renter', 'owner'],
      'verification': {
        'status': status,
        'documentType': documentType,
        'documents': [
          {'documentType': documentType, 'status': status}
        ],
      },
    };

Map<String, dynamic> draftJson() => {
      'publicId': 'l-draft',
      'title': 'Synthetic listing',
      'category': 'Books',
      'dailyPrice': 10,
      'ownerId': 'u-member',
      'status': 'draft',
    };

class IdentityApi extends ApiClient {
  IdentityApi(this.responses) : super('http://example.invalid');
  final List<dynamic> responses;
  final List<(String, String)> calls = [];
  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    calls.add((method, path));
    final response = responses.removeAt(0);
    if (response is Exception) throw response;
    return response;
  }
}

void main() {
  test('only approved MyKad qualifies; upload/pending/passport/licence do not',
      () {
    for (final status in [
      'unverified',
      'pending',
      'rejected',
      'resubmission_required',
      'expired'
    ]) {
      expect(marketplaceIdentityApproved(User.fromJson(profileJson(status))),
          isFalse);
    }
    expect(marketplaceIdentityApproved(null), isFalse);
    expect(marketplaceIdentityApproved(User.fromJson(profileJson('approved'))),
        isTrue);
    for (final type in ['passport', 'driving_licence']) {
      expect(
          marketplaceIdentityApproved(
              User.fromJson(profileJson('approved', documentType: type))),
          isFalse);
    }
    final stale = profileJson('approved');
    (stale['verification'] as Map)['documents'] = [
      {'documentType': 'mykad', 'status': 'pending'}
    ];
    expect(marketplaceIdentityApproved(User.fromJson(stale)), isFalse);
    expect(marketplaceIdentityMessage('pending', 'submit a booking'),
        contains('not yet approval'));
  });

  test('saving drafts does not call submit or demand identity approval',
      () async {
    final api = IdentityApi([draftJson(), draftJson()]);
    final controller = LiveRentHubController(api);
    addTearDown(controller.dispose);
    await controller.createOwnerListing({'title': 'Synthetic listing'},
        submitForReview: false);
    await controller.updateOwnerListing('l-draft', {'dailyPrice': 10},
        submitForReview: false);
    expect(api.calls, [('POST', '/listings'), ('PATCH', '/listings/l-draft')]);
    expect(controller.ownerListings.single.status, 'draft');
  });

  test(
      'server submit rejection retains the saved draft and creates no duplicate',
      () async {
    final api = IdentityApi([
      draftJson(),
      ApiException(403, 'Verification required', code: 'KYC_REQUIRED')
    ]);
    final controller = LiveRentHubController(api);
    addTearDown(controller.dispose);
    await expectLater(
        controller.createOwnerListing({'title': 'Synthetic listing'}),
        throwsA(isA<ApiException>()));
    expect(controller.ownerListings.single.id, 'l-draft');
    expect(controller.ownerListings.single.status, 'draft');
    expect(api.calls,
        [('POST', '/listings'), ('POST', '/listings/l-draft/submit')]);
  });

  testWidgets('unverified Owner can save a physical draft without images',
      (tester) async {
    final draft = {
      ...draftJson(),
      'location': 'Kuala Lumpur',
      'listingType': 'physical',
      'securityDeposit': 0,
      'itemProfile': {'subcategory': 'Fiction'},
    };
    final api = IdentityApi([draft]);
    final controller = LiveRentHubController(api)
      ..profile = User.fromJson(profileJson('unverified'))
      ..ownerListings = [Listing.fromJson(draft)];
    addTearDown(controller.dispose);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: controller,
      child: MaterialApp(
        home:
            LiveListingForm(isService: false, listing: Listing.fromJson(draft)),
      ),
    ));
    await tester.scrollUntilVisible(find.text('Save Draft'), 350,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Save Draft'));
    await tester.pumpAndSettle();
    expect(api.calls, [('PATCH', '/listings/l-draft')]);
    expect(controller.ownerListings.single.status, 'draft');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'pending preflight shows approval requirement and does not mutate marketplace records',
      (tester) async {
    final api = IdentityApi([profileJson('pending')]);
    final controller = LiveRentHubController(api);
    addTearDown(controller.dispose);
    bool? allowed;
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                      body: TextButton(
                    onPressed: () async => allowed =
                        await ensureMarketplaceIdentity(context,
                            action: 'submit a booking request'),
                    child: const Text('Request booking'),
                  ))),
        )));
    await tester.tap(find.text('Request booking'));
    await tester.pumpAndSettle();
    expect(find.text('Identity verification required'), findsOneWidget);
    expect(find.text('View verification status'), findsOneWidget);
    expect(find.textContaining('not yet approval'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(allowed, isFalse);
    expect(api.calls, [('GET', '/users/me')]);
  });

  testWidgets(
      'fresh server approval overrides stale profile; unavailable check fails closed',
      (tester) async {
    for (final response in [
      profileJson('approved'),
      ApiException(503, 'Unavailable')
    ]) {
      final api = IdentityApi([response]);
      final controller = LiveRentHubController(api)
        ..profile = User.fromJson(profileJson('pending'));
      bool? allowed;
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: controller,
          child: MaterialApp(
            home: Builder(
                builder: (context) => Scaffold(
                        body: TextButton(
                      onPressed: () async => allowed =
                          await ensureMarketplaceIdentity(context,
                              action: 'publish a listing'),
                      child: const Text('Submit'),
                    ))),
          )));
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      expect(allowed, response is Map);
      expect(api.calls, [('GET', '/users/me')]);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    }
  });
}
