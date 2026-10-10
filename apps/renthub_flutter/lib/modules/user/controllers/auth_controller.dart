import '../../../core/network/user_facing_error.dart';
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
  bool externalLoginInProgress = false;
  bool _externalLoginCancelled = false;
  bool get authenticated => user != null;
  bool get usesExternalProvider => repository.usesExternalProvider;
  bool get supportsExternalProvider => repository.supportsExternalProvider;

  Future<void> restoreSession({Set<UserRole>? allowedRoles}) => run(() async {
        final restoredUser = await repository.restoreSession();
        if (restoredUser == null) return;
        final permittedRoles = allowedRoles == null
            ? restoredUser.roles
            : restoredUser.roles.intersection(allowedRoles);
        if (permittedRoles.isEmpty) {
          await repository.logout();
          return;
        }
        user = restoredUser;
        final restoredRole = restoredUser.activeRole;
        selectedRole =
            restoredRole != null && permittedRoles.contains(restoredRole)
                ? restoredRole
                : permittedRoles.first;
        if (selectedRole != restoredRole) {
          user = await repository.selectRole(selectedRole);
        }
        if (user?.pushNotifications ?? false) {
          await pushNotifications?.enableForCurrentUser();
        }
      });
  Future<void> selectRole(UserRole role) async {
    if (user == null) {
      selectedRole = role;
      notifyListeners();
      return;
    }
    loading = true;
    error = null;
    notifyListeners();
    try {
      final updated = await repository.selectRole(role);
      user = updated;
      selectedRole = updated.activeRole ?? role;
    } catch (exception) {
      lastError = exception;
      error = friendlyError(exception);
      rethrow;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> login(String email, String password) => run(() async {
        user = await repository.login(email, password, selectedRole);
        if (user?.pushNotifications ?? false) {
          await pushNotifications?.enableForCurrentUser();
        }
      });
  Future<void> loginWithAuth0() async {
    if (externalLoginInProgress) return;
    externalLoginInProgress = true;
    _externalLoginCancelled = false;
    notifyListeners();
    await run(() async {
      user = await repository.loginWithExternalProvider(selectedRole);
      if (user?.pushNotifications ?? false) {
        await pushNotifications?.enableForCurrentUser();
      }
    });
    externalLoginInProgress = false;
    if (_externalLoginCancelled) error = null;
    notifyListeners();
  }

  Future<void> cancelAuth0Login() async {
    if (!externalLoginInProgress) return;
    _externalLoginCancelled = true;
    await repository.cancelExternalLogin();
  }

  Future<void> register(String name, String email, String password) =>
      run(() async {
        user = await repository.register(name, email, password, selectedRole);
        if (user?.pushNotifications ?? false) {
          await pushNotifications?.enableForCurrentUser();
        }
      });
  Future<void> requestPasswordReset(String email) =>
      run(() => repository.requestPasswordReset(email));
  Future<void> confirmPasswordReset(
    String email,
    String code,
    String password,
  ) =>
      run(() async {
        await repository.confirmPasswordReset(email, code, password);
        user = null;
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
