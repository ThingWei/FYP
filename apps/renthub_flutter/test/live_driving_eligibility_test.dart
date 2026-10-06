import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/features/live/live_shared_pages.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';

class _RecordingApi extends ApiClient {
  _RecordingApi() : super('http://example.invalid');
  final calls = <(String, String, Object?)>[];
  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    calls.add((method, path, body));
    return {
      '_id': 'synthetic-user-id',
      'authId': 'u-synthetic',
      'displayName': 'Synthetic User',
      'email': 'synthetic@example.test',
      'roles': ['renter', 'owner']
    };
  }
}

void main() {
  test(
      'controller uses dedicated driving endpoints and submits admin attestations',
      () async {
    final api = _RecordingApi();
    final controller = LiveRentHubController(api);
    addTearDown(controller.dispose);
    await controller
        .submitIdentityVerification('driving_licence', ['upload://SYNTHETIC']);
    expect(api.calls.single.$2, '/users/me/driving-eligibility');
    await controller.reviewIdentityVerification('synthetic-user-id', 'approved',
        driving: true,
        attemptId: 'KYC-000000000000000000000001',
        licenceClasses: ['D'],
        expiresAt: '2035-01-01',
        identityMatchConfirmed: true,
        classReviewConfirmed: true);
    expect(api.calls.last.$2, '/users/synthetic-user-id/driving-eligibility');
    final body = api.calls.last.$3 as Map;
    expect(body['licenceClasses'], ['D']);
    expect(body['expiresAt'], '2035-01-01');
    expect(body['identityMatchConfirmed'], true);
    expect(body['classReviewConfirmed'], true);
  });

  for (final width in [360.0, 390.0]) {
    testWidgets('separate MyKad and expired driving sections at $width pixels',
        (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = LiveRentHubController(_RecordingApi());
      controller.profile = User.fromJson({
        'authId': 'u-synthetic',
        'displayName': 'Synthetic User',
        'roles': ['renter'],
        'verification': {
          'status': 'approved',
          'documents': [
            {'documentType': 'mykad', 'status': 'approved'}
          ]
        },
        'drivingEligibility': {
          'status': 'approved',
          'licenceClasses': ['D'],
          'expiresAt': '2000-01-01T15:59:59.999Z',
          'identityMatchConfirmed': true,
          'classReviewConfirmed': true
        },
      });
      addTearDown(controller.dispose);
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: controller,
          child: MaterialApp(
              theme: AppTheme.light,
              home: const LiveVerificationPage(driving: true))));
      await tester.pumpAndSettle();
      expect(find.text('Identity Verification — MyKad'), findsOneWidget);
      expect(find.text('Vehicle Driving Eligibility'), findsNWidgets(2));
      expect(find.text('expired'), findsOneWidget);
      expect(find.text('Licence class: D'), findsOneWidget);
      expect(find.text('Valid until: 2000-01-01'), findsOneWidget);
      expect(find.text('Passport'), findsNothing);
      await tester.ensureVisible(find.text('Capture driving evidence'));
      expect(find.text('Capture driving evidence'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
