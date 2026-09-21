import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/features/live/live_shared_pages.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';

class RecordingAccountApiClient extends ApiClient {
  RecordingAccountApiClient(this.responses) : super('http://example.invalid');

  final List<Map<String, dynamic>> responses;
  final List<(String, String, Object?)> calls = [];

  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    calls.add((method, path, body));
    return responses.removeAt(0);
  }
}

Map<String, dynamic> userJson({
  String name = 'Alex Tan',
  String phone = '+60 12-345 6789',
  String verificationStatus = 'unverified',
  List<Map<String, dynamic>> addresses = const [],
  String language = 'en',
  bool pushNotifications = true,
  bool emailNotifications = true,
}) =>
    {
      'authId': 'u-renter',
      'email': 'renter@renthub.my',
      'displayName': name,
      'phone': phone,
      'roles': ['renter'],
      'trustScore': 92,
      'verification': {
        'status': verificationStatus,
        'tier': verificationStatus == 'approved' ? 'basic' : 'none',
        'reason': '',
      },
      'addresses': addresses,
      'settings': {
        'language': language,
        'pushNotifications': pushNotifications,
        'emailNotifications': emailNotifications,
      },
    };

void main() {
  test('user model reads live account, address and verification state', () {
    final user = User.fromJson(
      userJson(
        verificationStatus: 'approved',
        language: 'ms',
        pushNotifications: false,
        addresses: const [
          {
            'label': 'Home',
            'line1': '18 Jalan Ampang',
            'city': 'Kuala Lumpur',
            'state': 'Kuala Lumpur',
            'postcode': '50450',
            'isDefault': true,
          },
        ],
      ),
    );

    expect(user.verificationStatus, 'approved');
    expect(user.verificationTier, 'basic');
    expect(user.addresses.single.postcode, '50450');
    expect(user.addresses.single.isDefault, isTrue);
    expect(user.language, 'ms');
    expect(user.pushNotifications, isFalse);
  });

  test('controller persists profile, addresses, settings and verification',
      () async {
    final address = const UserAddress(
      label: 'Home',
      line1: '18 Jalan Ampang',
      city: 'Kuala Lumpur',
      state: 'Kuala Lumpur',
      postcode: '50450',
      isDefault: true,
    );
    final api = RecordingAccountApiClient([
      userJson(name: 'Alex T.'),
      userJson(addresses: [address.toJson()]),
      userJson(language: 'ms', pushNotifications: false),
      userJson(verificationStatus: 'pending'),
    ]);
    final controller = LiveRentHubController(api);
    addTearDown(controller.dispose);

    await controller.updateProfile(displayName: 'Alex T.', phone: '+601234');
    await controller.updateAddresses([address]);
    await controller.updateAccountSettings(
      language: 'ms',
      pushNotifications: false,
      emailNotifications: true,
    );
    await controller.submitIdentityVerification('mykad');

    expect(api.calls.map((call) => '${call.$1} ${call.$2}'), [
      'PATCH /users/me',
      'PATCH /users/me',
      'PATCH /users/me',
      'POST /users/me/verification',
    ]);
    final verificationBody = api.calls.last.$3 as Map<String, dynamic>;
    expect(verificationBody['documentType'], 'mykad');
    expect(verificationBody['documentRefs'], hasLength(2));
    expect(controller.profile?.verificationStatus, 'pending');
  });

  test('administrator review uses the verification endpoint', () async {
    final reviewed = {
      ...userJson(verificationStatus: 'approved'),
      '_id': '507f1f77bcf86cd799439011',
    };
    final api = RecordingAccountApiClient([reviewed]);
    final controller = LiveRentHubController(api)
      ..users = [
        {
          ...userJson(verificationStatus: 'pending'),
          '_id': '507f1f77bcf86cd799439011',
        },
      ];
    addTearDown(controller.dispose);

    await controller.reviewIdentityVerification(
      '507f1f77bcf86cd799439011',
      'approved',
      tier: 'enhanced',
    );

    expect(api.calls.single.$2, '/users/507f1f77bcf86cd799439011/verification');
    final body = api.calls.single.$3 as Map<String, dynamic>;
    expect(body, {'status': 'approved', 'tier': 'enhanced'});
    expect(
      (controller.users.single['verification']
          as Map<String, dynamic>)['status'],
      'approved',
    );
  });

  testWidgets('final live profile edits and persists the display name',
      (tester) async {
    final api = RecordingAccountApiClient([userJson(name: 'Alex Updated')]);
    final controller = LiveRentHubController(api)
      ..profile = User.fromJson(userJson());
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          home: LiveProfilePage(
            role: 'Renter',
            canSwitch: false,
            onSwitch: () {},
            onLogout: () async {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Edit profile'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Display name'),
      'Alex Updated',
    );
    await tester.tap(find.text('Save Profile'));
    await tester.pumpAndSettle();

    expect(api.calls.single.$2, '/users/me');
    expect(controller.profile?.name, 'Alex Updated');
    expect(find.text('Alex Updated'), findsOneWidget);
  });
}
