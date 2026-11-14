import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/core/trust/trust_profile.dart';
import 'package:renthub_flutter/core/utils/calendar_date.dart';
import 'package:renthub_flutter/features/live/comparison_summary.dart';
import 'package:renthub_flutter/features/live/live_agreement.dart';
import 'package:renthub_flutter/features/live/live_appointments.dart';
import 'package:renthub_flutter/features/live/live_extension_dates.dart';
import 'package:renthub_flutter/features/live/live_owner_shell.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/features/live/live_shared_pages.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';
import 'package:renthub_flutter/shared/widgets/trust_indicator.dart';
import 'mykad_pair_replacement_test.dart' as pair;
import 'live_checkout_agreement_test.dart' as checkout;
import 'compact_trust_owner_test.dart' as preview;

class ReviewApi extends ApiClient {
  ReviewApi() : super('https://example.invalid');
  final calls = <String>[];
  bool fail = false;
  Completer<dynamic>? delay;
  late final end = malaysiaCalendarToday().add(const Duration(days: 5));
  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    calls.add('$method $path');
    if (delay != null) return delay!.future;
    if (fail) throw ApiException(503, 'private URL');
    if (path == '/rentals/R-EXTRA') {
      return {
        'publicId': 'R-EXTRA',
        'status': 'active',
        'renterId': 'renter',
        'ownerId': 'owner',
        'listingType': 'physical',
        'listingId': 'l-extra',
        'startDate':
            calendarDateApiValue(end.subtract(const Duration(days: 2))),
        'endDate': calendarDateApiValue(end),
        'returnTime': '18:00',
      };
    }
    if (path == '/listings/l-extra/availability') {
      return {
        'listingId': 'l-extra',
        'unavailableRanges': [
          {
            'start':
                calendarDateApiValue(end.subtract(const Duration(days: 2))),
            'end': calendarDateApiValue(end.add(const Duration(days: 1))),
            'allDay': true
          },
          {
            'start': calendarDateApiValue(end.add(const Duration(days: 3))),
            'end': calendarDateApiValue(end.add(const Duration(days: 5))),
            'allDay': true
          },
        ]
      };
    }
    return [];
  }
}

class ProofApi extends checkout.CheckoutApi {
  Map<String, dynamic> proofRecord = {};
  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    final result = await super.request(method, path, body: body);
    if (path.contains('/agreement')) result['record'] = proofRecord;
    return result;
  }
}

User account(String id) => User(
    id: id,
    email: '$id@example.invalid',
    name: 'Test user',
    roles: const {UserRole.renter, UserRole.owner});
Widget host(LiveRentHubController controller, Widget child,
        {double scale = 1}) =>
    ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: child));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (Platform.environment['RENTHUB_CAPTURE_TEST_UI'] != 'true') return;
    final fonts = {
      'RentHubPreview':
          File('${Platform.environment['WINDIR']}/Fonts/segoeui.ttf'),
      'MaterialIcons': File(
          '${File(Platform.resolvedExecutable).parent.parent.parent.parent.path}/artifacts/material_fonts/MaterialIcons-Regular.otf'),
    };
    for (final font in fonts.entries) {
      if (await font.value.exists()) {
        await (FontLoader(font.key)
              ..addFont(font.value.readAsBytes().then(ByteData.sublistView)))
            .load();
      }
    }
  });
  for (final score in [0, 40, 49, 50, 70, 79, 80, 100]) {
    testWidgets(
        'trust $score percent has the correct range colour and accessible label',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: TrustIndicator(
                  cohort: TrustCohort(status: 'established', score: score)))));
      final indicator = tester.widget<CircularProgressIndicator>(
          find.byType(CircularProgressIndicator));
      expect(indicator.value, score / 100);
      expect(
          indicator.color,
          score >= 80
              ? AppColors.success
              : score >= 50
                  ? AppColors.warning
                  : AppColors.error);
      expect(find.bySemanticsLabel('Trust score: $score%'), findsOneWidget);
    });
  }
  testWidgets(
      'unestablished trust is neutral and does not display a zero percent score',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: TrustIndicator(cohort: TrustCohort()))));
    expect(find.text('0%'), findsNothing);
    expect(find.bySemanticsLabel('Trust score: \u2014'), findsOneWidget);
    expect(
        tester
            .widget<CircularProgressIndicator>(
                find.byType(CircularProgressIndicator))
            .color,
        AppColors.secondaryText);
  });

  List<Listing> items() => [
        const Listing(
            id: 'l-a',
            title: 'Affordable camera',
            category: 'Devices',
            subcategory: 'Cameras',
            dailyPrice: 40,
            securityDeposit: 150,
            condition: 'Good',
            rating: 4.8,
            reviewCount: 12),
        const Listing(
            id: 'l-b',
            title: 'Excellent camera',
            category: 'Devices',
            subcategory: 'Cameras',
            dailyPrice: 60,
            securityDeposit: 100,
            condition: 'Excellent',
            rating: 4.5,
            reviewCount: 3),
      ];
  test(
      'comparison uses distinct actual factors, ties and missing review information',
      () {
    final result = Map.fromEntries(
        comparisonHighlights(items()).map((row) => MapEntry(row.$1, row.$2)));
    expect(result['Lowest daily price'], 'Affordable camera');
    expect(result['Lowest refundable deposit'], 'Excellent camera');
    expect(result['Highest listing rating'], 'Affordable camera');
    expect(result['Best stated condition'], 'Excellent camera');
    expect(
        Map.fromEntries(comparisonHighlights([
          ...items(),
          const Listing(
              id: 'like-new',
              title: 'Like new camera',
              category: 'Devices',
              dailyPrice: 80,
              condition: 'Like New'),
        ]).map((row) => MapEntry(row.$1, row.$2)))['Best stated condition'],
        'Like new camera');
    final missing = Listing.fromJson({
      'publicId': 'missing',
      'title': 'No stated condition',
      'category': 'Devices',
      'dailyPrice': 30
    });
    expect(missing.conditionRecorded, isFalse);
    expect(
        comparisonHighlights([items().first, missing])
            .any((row) => row.$1 == 'Best stated condition'),
        isFalse);
    final tied = [
      for (var i = 0; i < 2; i++)
        Listing(
            id: 'l-$i',
            title: 'Item $i',
            category: 'Devices',
            dailyPrice: 50,
            condition: 'Unknown')
    ];
    final sparse = comparisonHighlights(tied);
    expect(sparse.every((e) => e.$2 == 'All compared items are tied.'), isTrue);
    expect(sparse.any((e) => e.$1 == 'Highest listing rating'), isFalse);
    expect(sparse.any((e) => e.$1 == 'Best stated condition'), isFalse);
    expect(comparisonHighlights([items().first]), isEmpty);
  });
  for (final width in [360.0, 390.0, 1024.0, 1440.0]) {
    testWidgets('comparison summary is readable at $width with larger text',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final c = LiveRentHubController(ReviewApi());
      addTearDown(c.dispose);
      await tester.pumpWidget(host(
          c,
          Scaffold(
              body: SingleChildScrollView(
                  child: ComparisonSummary(items: items()))),
          scale: 1.6));
      expect(find.text('Top picks'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  test('appointment formatting and historical records do not invent times', () {
    expect(appointmentTime('00:05'), '12:05 am');
    expect(appointmentTime('18:00'), '6:00 pm');
    expect(appointmentTime(null), 'Time not specified');
    expect(appointmentTime('25:00'), 'Time not specified');
    final old = Booking.fromJson({
      'id': 'old',
      'listingId': 'l-old',
      'startDate': '2026-11-14',
      'endDate': '2026-11-14',
      'status': 'completed'
    });
    expect(old.pickupTime, isNull);
    expect(old.returnTime, isNull);
  });

  testWidgets(
      'extension disables a reserved day and dates crossing it without making writes',
      (tester) async {
    final api = ReviewApi(), c = LiveRentHubController(ReviewApi());
    final controller = LiveRentHubController(api)..profile = account('renter');
    addTearDown(c.dispose);
    addTearDown(controller.dispose);
    DateTime? selected;
    await tester.pumpWidget(host(
        controller,
        Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () async => selected = await chooseExtensionDate(
                        context,
                        const Rental('R-EXTRA', 'active',
                            renterId: 'renter', listingId: 'l-extra')),
                    child: const Text('Extra days'))))));
    await tester.tap(find.text('Extra days'));
    await tester.pumpAndSettle();
    final dialog =
        tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
    expect(dialog.selectableDayPredicate!(api.end.add(const Duration(days: 1))),
        isTrue);
    expect(dialog.selectableDayPredicate!(api.end.add(const Duration(days: 2))),
        isTrue);
    expect(dialog.selectableDayPredicate!(api.end.add(const Duration(days: 3))),
        isFalse);
    expect(dialog.selectableDayPredicate!(api.end.add(const Duration(days: 6))),
        isFalse);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    expect(api.calls.every((call) => call.startsWith('GET ')), isTrue);
  });
  testWidgets(
      'unavailable extension checks offer retry and do not open an unchecked calendar',
      (tester) async {
    final api = ReviewApi()..fail = true;
    final c = LiveRentHubController(api)..profile = account('renter');
    addTearDown(c.dispose);
    await tester.pumpWidget(host(
        c,
        Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => chooseExtensionDate(
                        context, const Rental('R-EXTRA', 'active')),
                    child: const Text('Extra days'))))));
    await tester.tap(find.text('Extra days'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(find.textContaining('Could not check extra days.'), findsOneWidget);
    expect(api.calls, hasLength(1));
  });

  testWidgets('MyKad requires a holder photo independently of a matched pair',
      (tester) async {
    final c = pair.DraftController();
    addTearDown(c.dispose);
    await tester.pumpWidget(host(
        c,
        LiveVerificationPage(
            holderPhotoPicker: (_) async => 'upload://UPL-HOLDER')));
    await pair.tapVisible(tester, find.byTooltip('Upload document image'));
    await pair.tapVisible(tester, find.byTooltip('Upload document image'));
    c.replies[0].complete(pair.result([pair.front, pair.back]));
    await tester.pumpAndSettle();
    expect(await pair.canSubmit(tester), isFalse);
    await pair.tapVisible(tester, find.text('Add holder photo'));
    expect(await pair.canSubmit(tester), isTrue);
    await pair.tapVisible(tester, find.text('Submit for Review'));
    expect(c.submissions, 1);
  });

  testWidgets(
      'stale holder selection cannot enter a different verification flow',
      (tester) async {
    final pending = Completer<String?>(), c = pair.DraftController();
    addTearDown(c.dispose);
    await tester.pumpWidget(host(
        c, LiveVerificationPage(holderPhotoPicker: (_) => pending.future)));
    await pair.tapVisible(tester, find.text('Add holder photo'));
    final selector = find.byType(DropdownButtonFormField<String>);
    await tester.scrollUntilVisible(selector, -200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Driving licence / MyJPJ evidence').last);
    await tester.pumpAndSettle();
    pending.complete('upload://UPL-HOLDER');
    await tester.pumpAndSettle();
    expect(find.text('You holding your MyKad'), findsNothing);
    expect(find.text('Add holder photo'), findsNothing);
  });

  testWidgets(
      'vehicle grants are clearly private and required only for Cars and Motorcycles',
      (tester) async {
    final c = LiveRentHubController(ReviewApi())..profile = account('owner');
    addTearDown(c.dispose);
    for (final category in ['Cars', 'Motorcycles', 'Bicycles']) {
      await tester.pumpWidget(host(
          c,
          LiveListingForm(
              key: ValueKey(category),
              isService: false,
              listing: Listing(
                  id: 'l-$category',
                  title: 'Vehicle $category',
                  category: 'Vehicles',
                  subcategory: category,
                  dailyPrice: 50,
                  status: 'draft'))));
      await tester.scrollUntilVisible(find.text('Photos'), 250,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(find.text('Vehicle registration document'),
          category == 'Bicycles' ? findsNothing : findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  if (Platform.environment['RENTHUB_CAPTURE_TEST_UI'] == 'true') {
    testWidgets('capture readable review improvements', (tester) async {
      final c = pair.DraftController();
      addTearDown(c.dispose);
      for (final width in [360.0, 390.0, 1024.0, 1440.0]) {
        await tester.binding.setSurfaceSize(Size(width, 1100));
        await tester.pumpWidget(preview.host(
            c,
            Scaffold(
                body: SingleChildScrollView(
                    child: Column(children: [
              const SizedBox(height: 24),
              const TrustIndicator(
                  cohort: TrustCohort(status: 'established', score: 85)),
              const Text('Trust score'),
              const RentalAppointments(pickup: '09:00', returnTime: '18:00'),
              ComparisonSummary(items: [
                ...items(),
                const Listing(
                    id: 'preview-third',
                    title: 'Compact camera',
                    category: 'Devices',
                    subcategory: 'Cameras',
                    dailyPrice: 80,
                    securityDeposit: 200,
                    condition: 'Fair',
                    rating: 4,
                    reviewCount: 1)
              ]),
            ]))),
            scale: 1.6));
        await tester.pumpAndSettle();
        await preview.capture(tester, 'review-summary-${width.toInt()}');
        expect(tester.takeException(), isNull);
      }
      await tester.binding.setSurfaceSize(const Size(390, 1100));
      await tester.pumpWidget(preview.host(
          c, LiveVerificationPage(holderPhotoPicker: (_) async => null),
          scale: 1.3));
      await tester.scrollUntilVisible(
          find.text('Photo of you holding your MyKad'), 250,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await preview.capture(tester, 'review-holder-390');
      await tester.pumpWidget(preview.host(
          c,
          const LiveListingForm(
              isService: false,
              listing: Listing(
                  id: 'vehicle',
                  title: 'Car',
                  category: 'Vehicles',
                  subcategory: 'Cars',
                  dailyPrice: 50,
                  status: 'draft')),
          scale: 1.3));
      await tester.scrollUntilVisible(
          find.text('Vehicle registration document'), 250,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await preview.capture(tester, 'review-grant-390');
      expect(tester.takeException(), isNull);
      await tester.binding.setSurfaceSize(null);
    });
  }
  testWidgets(
      'blockchain proof stays collapsed and shows saved references on demand',
      (tester) async {
    final api = ProofApi();
    final hash = '0x${List.filled(64, 'a').join()}',
        address = '0x${List.filled(40, 'b').join()}';
    api.proofRecord = {
      'status': 'saved',
      'demonstrationNetwork': true,
      'proof': {
        'network': 'Local demonstration blockchain',
        'contractAddress': address,
        'lastTransactionHash': hash,
        'recordedState': 'active',
        'signatureTransactionHashes': []
      }
    };
    await checkout.mount(tester, api,
        page: const LiveAgreementPage(bookingId: 'BKG-TEST'));
    await tester.scrollUntilVisible(find.text('Blockchain proof'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.text(hash), findsNothing);
    await tester.tap(find.text('Blockchain proof'));
    await tester.pumpAndSettle();
    expect(find.text(hash), findsOneWidget);
    expect(find.text(address), findsOneWidget);
    expect(find.text('Local test network'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
