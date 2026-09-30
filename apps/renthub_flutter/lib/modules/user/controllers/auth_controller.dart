import '../../../shared/controllers/loadable_controller.dart';
import '../../../shared/models/domain_models.dart';
import '../repositories/auth_repository.dart';
import '../../../core/notifications/push_notification_service.dart';

class AuthController extends LoadableController {
  AuthController(this.repository, {this.pushNotifications});
  final AuthRepository repository;
  final PushNotificationService? pushNotifications;
  User? user;
  UserRole selectedRole = UserRole.renter;
  bool get authenticated => user != null;
  bool get usesExternalProvider => repository.usesExternalProvider;
  void selectRole(UserRole role) {
    selectedRole = role;
    repository.selectRole(role);
    notifyListeners();
  }

  Future<void> login(String email, String password) => run(() async {
        user = await repository.login(email, password, selectedRole);
        if (user?.pushNotifications ?? false) {
          await pushNotifications?.enableForCurrentUser();
        }
      });
  Future<void> register(String name, String email, String password) =>
      run(() async {
        user = await repository.register(name, email, password, selectedRole);
        if (user?.pushNotifications ?? false) {
          await pushNotifications?.enableForCurrentUser();
        }
      });
  Future<void> logout() => run(() async {
        try {
          await pushNotifications?.disableForCurrentUser();
          await repository.logout();
        } finally {
          user = null;
        }
      });
}
