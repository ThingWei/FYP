import '../../../shared/models/domain_models.dart';

abstract interface class LoyaltyRepository {
  Future<Reward> summary();
  Future<Reward> redeem(int points);
}

class MockLoyaltyRepository implements LoyaltyRepository {
  int _points = 850;

  @override
  Future<Reward> summary() async => Reward(_points, 'RH-ALEX92');

  @override
  Future<Reward> redeem(int points) async {
    if (points <= 0 || points > _points) {
      throw StateError('Not enough points for this reward.');
    }
    _points -= points;
    return Reward(_points, 'RH-ALEX92');
  }
}
