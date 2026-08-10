import '../core/network/api_client.dart';
import '../modules/user/repositories/auth_repository.dart';
import '../modules/listing/repositories/listing_repository.dart';
import '../modules/booking/repositories/booking_repository.dart';
class AppDependencies { AppDependencies(this.authRepository,this.listingRepository,this.bookingRepository); final AuthRepository authRepository; final ListingRepository listingRepository; final BookingRepository bookingRepository; factory AppDependencies.create(){const useMocks=bool.fromEnvironment('USE_MOCKS',defaultValue:true);final api=ApiClient(const String.fromEnvironment('API_BASE_URL',defaultValue:'http://localhost:3000/api/v1'));return AppDependencies(MockAuthRepository(),useMocks?MockListingRepository():LiveListingRepository(api),MockBookingRepository());} }

