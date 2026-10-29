import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/core/trust/trust_profile.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/features/live/live_trust_page.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';

const account = {
  'authId': 'u-trust',
  'email': 'test@example.test',
  'displayName': 'Nur Aisyah 李',
  'roles': ['renter', 'owner']
};
Map<String, dynamic> cohort({bool established = false}) => {
      'status': established ? 'established' : 'insufficient_history',
      'score': established ? 71 : null,
      'completedRentals': established ? 3 : 0,
      'distinctPartners': established ? 2 : 0,
      'reviewCount': established ? 3 : 0,
      'averageRating': established ? 5 : null,
      'timelyRentals': established ? 3 : 0,
      'measuredTimeliness': established ? 3 : 0,
      'confirmedIssues': 0
    };
Map<String, dynamic> profile({bool real = false, bool demo = false}) => {
      'version': 'renthub-trust-v1',
      for (final role in ['overall', 'owner', 'renter'])
        role: {
          'marketplace': cohort(established: real),
          'demo': cohort(established: demo)
        }
    };

class TrustApi extends ApiClient {
  TrustApi() : super('http://example.invalid');
  final calls = <String>[];
  dynamic response = profile(real: true);
  bool fail = false;
  Completer<dynamic>? pending;
  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    calls.add('$method $path');
    if (pending != null) return pending!.future;
    if (fail) throw ApiException(503, 'private server path');
    return response;
  }
}

Widget host(Widget page, LiveRentHubController c, {double scale = 1}) =>
    ChangeNotifierProvider.value(
        value: c,
        child: MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: page));
void main() {
  test('a superseded own-account response cannot overwrite newer trust data',
      () async {
    final first = Completer<dynamic>(), second = Completer<dynamic>();
    final api = TrustApi()..pending = first;
    final c = LiveRentHubController(api)..profile = User.fromJson(account);
    addTearDown(c.dispose);
    final earlier = c.loadTrustProfile('u-trust');
    api.pending = second;
    final later = c.loadTrustProfile('u-trust');
    second.complete(profile(real: true));
    await later;
    first.complete(profile(demo: true));
    await earlier;
    expect(c.profile!.trustProfile.owner.marketplace.score, 71);
    expect(c.profile!.trustProfile.owner.demo.score, isNull);
  });
  test(
      'typed summaries preserve role/provenance and reject legacy or malformed scores',
      () {
    expect(TrustProfile.fromJson({'trustScore': 98}).supported, isFalse);
    final p = TrustProfile.fromJson(profile(demo: true));
    expect(p.owner.marketplace.score, isNull);
    expect(p.owner.demo.score, 71);
    for (final bad in [double.nan, double.infinity, -1, 101, '98']) {
      expect(
          TrustCohort.fromJson({'status': 'established', 'score': bad})
              .established,
          isFalse);
    }
    final user = User.fromJson(account)
        .withTrustProfile(TrustProfile.fromJson(profile(real: true)));
    expect(user.name, account['displayName']);
    expect(user.id, account['authId']);
    expect(user.trustScore, 71);
  });
  for (final width in [360.0, 390.0, 1024.0]) {
    testWidgets('trust history separates demo evidence and fits width $width',
        (t) async {
      t.view.physicalSize = Size(width, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final api = TrustApi()..response = profile(demo: true);
      final c = LiveRentHubController(api)..profile = User.fromJson(account);
      addTearDown(c.dispose);
      await t.pumpWidget(host(
          const LiveTrustPage(userId: 'u-trust', role: 'owner'), c,
          scale: 1.4));
      await t.pumpAndSettle();
      expect(find.text('Not enough rental history'), findsOneWidget);
      expect(api.calls, ['GET /users/me/trust']);
      expect(c.profile!.trustScore, 50);
      await t.scrollUntilVisible(find.text('Demo activity'), 300,
          scrollable: find.byType(Scrollable).first, maxScrolls: 30);
      await t.pumpAndSettle();
      expect(find.text('Demo score 71 / 100'), findsOneWidget);
      expect(find.textContaining('not genuine marketplace history'),
          findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
      'unavailable reload retains the previous score and explicit retry recovers',
      (t) async {
    final api = TrustApi(), c = LiveRentHubController(TrustApi());
    final controller = LiveRentHubController(api)
      ..profile = User.fromJson(account);
    addTearDown(c.dispose);
    addTearDown(controller.dispose);
    await t
        .pumpWidget(host(const LiveTrustPage(userId: 'u-trust'), controller));
    await t.pumpAndSettle();
    expect(find.text('71 / 100'), findsOneWidget);
    api.fail = true;
    await t.tap(find.byTooltip('Refresh trust score'));
    await t.pumpAndSettle();
    expect(find.text('71 / 100'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.textContaining('private server'), findsNothing);
    api.fail = false;
    await t.tap(find.text('Try again'));
    await t.pumpAndSettle();
    expect(find.text('Try again'), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets('account switching hides scores and ignores late responses',
      (t) async {
    final api = TrustApi()..pending = Completer<dynamic>();
    final c = LiveRentHubController(api)..profile = User.fromJson(account);
    addTearDown(c.dispose);
    await t.pumpWidget(host(const LiveTrustPage(userId: 'u-trust'), c));
    await t.pump();
    c.profile = User.fromJson({...account, 'authId': 'u-other'});
    c.notifyListeners();
    await t.pump();
    api.pending!.complete(profile(real: true));
    await t.pumpAndSettle();
    expect(find.text('71 / 100'), findsNothing);
    expect(find.textContaining('Your session changed'), findsOneWidget);
    expect(c.profile!.id, 'u-other');
    expect(c.profile!.trustProfile.supported, isFalse);
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'other-account lookup uses an encoded ID and malformed data is safe',
      (t) async {
    final api = TrustApi()..response = {'trustScore': 100};
    final c = LiveRentHubController(api)..profile = User.fromJson(account);
    addTearDown(c.dispose);
    await t.pumpWidget(
        host(const LiveTrustPage(userId: 'auth0|other', role: 'renter'), c));
    await t.pumpAndSettle();
    expect(api.calls, ['GET /users/auth0%7Cother/trust']);
    expect(find.text('100 / 100'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
