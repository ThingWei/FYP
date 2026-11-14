import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/core/validation/input_validation.dart';
import 'package:renthub_flutter/core/validation/input_rules.dart';
import 'package:renthub_flutter/features/live/live_contact_profile.dart';
import 'package:renthub_flutter/features/live/live_handover_receipt.dart';
import 'package:renthub_flutter/features/live/live_listing_gallery.dart';
import 'package:renthub_flutter/features/live/live_photo_widgets.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/features/live/live_value_pickers.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';
import 'mykad_pair_replacement_test.dart' as photo;
import 'compact_trust_owner_test.dart' as preview;

class ProfileApi extends photo.PhotosApi {
  final calls = <String>[];
  Completer<dynamic>? waiting;
  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    calls.add(path);
    if (path.startsWith('/reviews/')) {
      return ApiItems([], {'page': 1, 'limit': 20, 'total': 0});
    }
    if (waiting != null) return waiting!.future;
    return {
      'id': 'auth0|owner',
      'displayName': 'Profile Owner',
      'avatarUrl': '/api/v1/uploads/public/UPL-AVATAR/content',
      'verified': true,
      'roles': ['renter', 'owner'],
      'trustProfile': {}
    };
  }
}

Widget root(Widget child,
    {LiveRentHubController? controller, double scale = 1}) {
  final app = MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!),
      home: Scaffold(body: SingleChildScrollView(child: child)));
  return controller == null
      ? app
      : ChangeNotifierProvider<LiveRentHubController>.value(
          value: controller, child: app);
}

void main() {
  setUpAll(() async {
    if (Platform.environment['RENTHUB_CAPTURE_TEST_UI'] != 'true') return;
    final font = File('${Platform.environment['WINDIR']}/Fonts/segoeui.ttf');
    await (FontLoader('RentHubPreview')
          ..addFont(font.readAsBytes().then(ByteData.sublistView)))
        .load();
    final icons = File(
        '${File(Platform.resolvedExecutable).parent.parent.parent.parent.path}/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (await icons.exists()) {
      await (FontLoader('MaterialIcons')
            ..addFont(icons.readAsBytes().then(ByteData.sublistView)))
          .load();
    }
  });
  for (final width in [360.0, 390.0, 1024.0]) {
    testWidgets(
        'fee picker preserves cents, cancellation and numeric bounds at $width',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final text = TextEditingController(text: '12.50');
      addTearDown(text.dispose);
      await tester.pumpWidget(root(
          ListingValuePicker(
              controller: text,
              label: 'Delivery fee',
              rule: const InputRule('Delivery fee',
                  kind: InputKind.money, max: 100000)),
          scale: 1.4));
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
      await tester.tap(find.byType(TextFormField));
      await tester.pumpAndSettle();
      expect(find.text('RM 12.50'), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(text.text, '12.50');
      await tester.tap(find.byType(TextFormField));
      await tester.pumpAndSettle();
      await tester.tap(find.text('RM 20'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use selection'));
      await tester.pumpAndSettle();
      expect(text.text, '20.00');
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'duration picker requires 15 minutes and leaves drafts unchanged on cancel',
      (tester) async {
    final text = TextEditingController(text: '17');
    addTearDown(text.dispose);
    await tester.pumpWidget(root(ListingValuePicker(
        controller: text,
        label: 'Service duration',
        rule: InputRules.durationMinutes,
        duration: true)));
    await tester.tap(find.byType(TextFormField));
    await tester.pumpAndSettle();
    expect(find.text('17m'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(text.text, '17');
    await tester.tap(find.byType(TextFormField));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2h'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use selection'));
    await tester.pumpAndSettle();
    expect(text.text, '120');
    expect(tester.takeException(), isNull);
  });
  testWidgets('money choices stop at zero and the existing maximum',
      (tester) async {
    final text = TextEditingController(text: '0.00');
    addTearDown(text.dispose);
    await tester.pumpWidget(root(ListingValuePicker(
        controller: text,
        label: 'Delivery fee',
        rule:
            const InputRule('Delivery fee', kind: InputKind.money, max: 20))));
    await tester.tap(find.byType(TextFormField));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<IconButton>(find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Decrease amount'))
            .onPressed,
        isNull);
    await tester.tap(find.text('RM 20'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<IconButton>(find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Increase amount'))
            .onPressed,
        isNull);
    expect(find.text('RM 50'), findsNothing);
    await tester.tap(find.text('Use selection'));
    await tester.pumpAndSettle();
    expect(text.text, '20.00');
  });
  testWidgets('return gallery uses renter evidence, not Owner handover photos',
      (tester) async {
    final c = photo.DraftController();
    addTearDown(c.dispose);
    final rental = Rental.fromJson({
      'id': 'r',
      'status': 'return_submitted',
      'listingType': 'physical',
      'handover': {
        'condition': 'Good',
        'evidence': ['upload://UPL-HANDOVER']
      },
      'returnSubmission': {
        'condition': 'Fair',
        'notes': 'Returned with charger',
        'evidence': ['upload://UPL-RETURN1', 'upload://UPL-RETURN2'],
        'recordedAt': '2026-11-14T02:00:00Z'
      }
    });
    await tester
        .pumpWidget(root(ReturnPhotosSection(rental: rental), controller: c));
    await tester.pumpAndSettle();
    expect(find.text('Return'), findsOneWidget);
    expect(find.text('Condition: Fair'), findsOneWidget);
    final gallery =
        tester.widget<ListingPhotoCarousel>(find.byType(ListingPhotoCarousel));
    expect(gallery.photos, ['upload://UPL-RETURN1', 'upload://UPL-RETURN2']);
    expect(
        find.byWidgetPredicate((w) =>
            w is LivePhotoThumbnail && w.reference == 'upload://UPL-HANDOVER'),
        findsNothing);
    expect(find.text('Appointments'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'profile shows name and avatar through an encoded, read-only lookup',
      (tester) async {
    final api = ProfileApi();
    final controller = LiveRentHubController(api)
      ..profile = User(
          id: 'viewer',
          email: 'viewer@example.invalid',
          name: 'Viewer',
          roles: const {UserRole.renter, UserRole.owner});
    addTearDown(controller.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<LiveRentHubController>.value(
        value: controller,
        child: MaterialApp(
            theme: AppTheme.light,
            home: const LiveContactProfilePage(userId: 'auth0|owner'))));
    await tester.pumpAndSettle();
    expect(find.text('Profile Owner'), findsOneWidget);
    expect(api.calls, contains('/users/auth0%7Cowner/profile'));
    expect(find.byType(CircleAvatar), findsOneWidget);
    expect(find.text('Identity verified'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('a delayed profile cannot appear after account switching',
      (tester) async {
    final api = ProfileApi()..waiting = Completer<dynamic>();
    final controller = LiveRentHubController(api)
      ..profile = User(
          id: 'viewer',
          email: 'viewer@example.invalid',
          name: 'Viewer',
          roles: const {UserRole.renter, UserRole.owner});
    addTearDown(controller.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<LiveRentHubController>.value(
        value: controller,
        child:
            MaterialApp(home: const LiveContactProfilePage(userId: 'owner'))));
    await tester.pump();
    controller.profile = User(
        id: 'other',
        email: 'other@example.invalid',
        name: 'Other',
        roles: const {UserRole.renter, UserRole.owner});
    controller.notifyListeners();
    api.waiting!.complete({'id': 'owner', 'displayName': 'Stale profile'});
    await tester.pumpAndSettle();
    expect(find.text('Stale profile'), findsNothing);
    expect(find.text('Your session changed. Go back to continue.'),
        findsOneWidget);
  });
  if (Platform.environment['RENTHUB_CAPTURE_TEST_UI'] == 'true') {
    testWidgets(
        'capture the new selection controls at mobile and desktop widths',
        (tester) async {
      final c = photo.DraftController();
      final money = TextEditingController(text: '12.50');
      final duration = TextEditingController(text: '90');
      addTearDown(c.dispose);
      addTearDown(money.dispose);
      addTearDown(duration.dispose);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final width in [360.0, 390.0, 1024.0, 1440.0]) {
        await tester.binding.setSurfaceSize(Size(width, 1000));
        await tester.pumpWidget(preview.host(
            c,
            Scaffold(
                body: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(children: [
                      ListingValuePicker(
                          controller: money,
                          label: 'Delivery fee',
                          rule: const InputRule('Delivery fee',
                              kind: InputKind.money, max: 100000)),
                      const SizedBox(height: 20),
                      ListingValuePicker(
                          controller: duration,
                          label: 'Service duration',
                          rule: InputRules.durationMinutes,
                          duration: true),
                    ]))),
            scale: 1.4));
        await tester.tap(find.byType(TextFormField).first);
        await tester.pumpAndSettle();
        await preview.capture(tester, 'listing-money-${width.toInt()}');
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(TextFormField).last);
        await tester.pumpAndSettle();
        await preview.capture(tester, 'listing-duration-${width.toInt()}');
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  }
}
