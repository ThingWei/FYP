import '../../../shared/controllers/loadable_controller.dart';
import '../../../shared/models/domain_models.dart';
import '../repositories/loyalty_repository.dart';

class LoyaltyController extends LoadableController {
  LoyaltyController(this.repository);
  final LoyaltyRepository repository;
  int points = 0;
  String referralCode = '';

  Future<void> load() => run(() async => _apply(await repository.summary()));

  Future<void> redeem(int cost) =>
      run(() async => _apply(await repository.redeem(cost)));

  void _apply(Reward reward) {
    points = reward.points;
    referralCode = reward.referralCode;
  }
}
