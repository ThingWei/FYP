import '../../../shared/controllers/loadable_controller.dart';
import '../../../shared/models/domain_models.dart';
import '../repositories/booking_repository.dart';
class BookingController extends LoadableController { BookingController(this.repository); final BookingRepository repository; Booking? latest; Future<void> create(String id,DateTime start,DateTime end)=>run(() async=>latest=await repository.create(id,start,end)); }

