import '../../../shared/models/domain_models.dart';

abstract interface class AuthRepository {
  Future<User> login(String email, String password, UserRole role);
  Future<User> register(
    String name,
    String email,
    String password,
    UserRole role,
  );
  Future<void> logout();
}

class MockAuthRepository implements AuthRepository {
  User _user(String email, UserRole role) => User(
        id: 'demo-user',
        email: email,
        name:
            email == 'demo@renthub.my' ? 'Nur Izzati' : email.split('@').first,
        roles: email == 'demo@renthub.my'
            ? {UserRole.renter, UserRole.owner}
            : {role},
        trustScore: 4.7,
      );
  @override
  Future<User> login(String e, String p, UserRole r) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return _user(e, r);
  }

  @override
  Future<User> register(String n, String e, String p, UserRole r) async =>
      User(id: 'demo-user', email: e, name: n, roles: {r});
  @override
  Future<void> logout() async {}
}
