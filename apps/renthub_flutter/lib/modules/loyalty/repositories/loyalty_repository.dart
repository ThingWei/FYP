import '../../../shared/models/domain_models.dart';
import '../../../core/network/api_client.dart';

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

class LiveLoyaltyRepository implements LoyaltyRepository {
  LiveLoyaltyRepository(this.api);

  final ApiClient api;

  @override
  Future<Reward> summary() async => Reward.fromJson(
        await api.request('GET', '/rewards/summary') as Map<String, dynamic>,
      );

  @override
  Future<Reward> redeem(int points) async => Reward.fromJson(
        await api.request(
          'POST',
          '/rewards/redeem',
          body: {'points': points},
        ) as Map<String, dynamic>,
      );
}
