import '../core/config/backend_mode.dart';
import '../core/auth/auth0_gateway.dart';
import '../core/network/api_client.dart';
import '../core/network/session_identity.dart';
import '../core/notifications/push_notification_service.dart';
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
    this.pushNotifications,
  );
  final ApiClient api;
  final SessionIdentity session;
  final AuthRepository authRepository;
  final ListingRepository listingRepository;
  final BookingRepository bookingRepository;
  final LoyaltyRepository loyaltyRepository;
  final PushNotificationService pushNotifications;
  factory AppDependencies.create() {
    final session = SessionIdentity();
    const auth0Domain = String.fromEnvironment('AUTH0_DOMAIN');
    const auth0ClientId = String.fromEnvironment('AUTH0_CLIENT_ID');
    const auth0Audience = String.fromEnvironment('AUTH0_AUDIENCE');
    const auth0CallbackUrl = String.fromEnvironment('AUTH0_CALLBACK_URL');
    const auth0DatabaseConnection = String.fromEnvironment(
      'AUTH0_DATABASE_CONNECTION',
      defaultValue: 'Username-Password-Authentication',
    );
    final auth0Enabled = !BackendMode.useMocks &&
        auth0Domain.isNotEmpty &&
        auth0ClientId.isNotEmpty &&
        auth0Audience.isNotEmpty &&
        auth0CallbackUrl.isNotEmpty;
    final auth0Gateway = auth0Enabled
        ? Auth0Gateway(
            domain: auth0Domain,
            clientId: auth0ClientId,
            audience: auth0Audience,
            callbackUrl: auth0CallbackUrl,
            databaseConnection: auth0DatabaseConnection,
          )
        : null;
    final api = ApiClient(
      const String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: 'http://localhost:3000/api/v1',
      ),
      tokenProvider: session.token,
    );
    final pushNotifications = PushNotificationService(api);
    return AppDependencies(
      api,
      session,
      BackendMode.useMocks
          ? MockAuthRepository()
          : auth0Enabled
              ? HybridAuthRepository(
                  LiveAuthRepository(api, session),
                  Auth0AuthRepository(api, session, auth0Gateway!),
                  session,
                  auth0Gateway,
                )
              : LiveAuthRepository(api, session),
      BackendMode.useMocks
          ? MockListingRepository()
          : LiveListingRepository(api),
      BackendMode.useMocks
          ? MockBookingRepository()
          : LiveBookingRepository(api),
      BackendMode.useMocks
          ? MockLoyaltyRepository()
          : LiveLoyaltyRepository(api),
      pushNotifications,
    );
  }
}
