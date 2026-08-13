import '../../../shared/controllers/loadable_controller.dart';
import '../repositories/loyalty_repository.dart';

class LoyaltyController extends LoadableController {
  LoyaltyController(this.repository);
  final LoyaltyRepository repository;
  int points = 0;
  Future<void> load() => run(() async => points = await repository.points());
}
