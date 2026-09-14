import '../core/config/backend_mode.dart';
import '../core/network/api_client.dart';
import '../core/network/session_identity.dart';
import '../modules/user/repositories/auth_repository.dart';
import '../modules/listing/repositories/listing_repository.dart';
import '../modules/booking/repositories/booking_repository.dart';
import '../modules/loyalty/repositories/loyalty_repository.dart';

class AppDependencies {
  AppDependencies(
    this.api,
    this.session,
    this.authRepository,
    this.listingRepository,
    this.bookingRepository,
    this.loyaltyRepository,
  );
  final ApiClient api;
  final SessionIdentity session;
  final AuthRepository authRepository;
  final ListingRepository listingRepository;
  final BookingRepository bookingRepository;
  final LoyaltyRepository loyaltyRepository;
  factory AppDependencies.create() {
    final session = SessionIdentity();
    final api = ApiClient(
      const String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: 'http://localhost:3000/api/v1',
      ),
      headersProvider: () async => session.mockHeaders,
    );
    return AppDependencies(
      api,
      session,
      BackendMode.useMocks
          ? MockAuthRepository()
          : LiveAuthRepository(api, session),
      BackendMode.useMocks
          ? MockListingRepository()
          : LiveListingRepository(api),
      BackendMode.useMocks
          ? MockBookingRepository()
          : LiveBookingRepository(api),
      MockLoyaltyRepository(),
    );
  }
}
