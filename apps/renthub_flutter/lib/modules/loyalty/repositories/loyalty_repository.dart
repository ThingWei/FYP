abstract interface class LoyaltyRepository{Future<int> points();}class MockLoyaltyRepository implements LoyaltyRepository{@override Future<int> points()async=>250;}
