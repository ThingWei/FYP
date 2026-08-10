import '../../../shared/controllers/loadable_controller.dart';
import '../../../shared/models/domain_models.dart';
import '../repositories/listing_repository.dart';
class ListingController extends LoadableController { ListingController(this.repository); final ListingRepository repository; List<Listing> listings=[]; Future<void> load()=>run(() async=>listings=await repository.list()); Future<void> create(String title,String category,double price)=>run(() async {await repository.create({'title':title,'category':category,'dailyPrice':price});listings=await repository.list();}); }

