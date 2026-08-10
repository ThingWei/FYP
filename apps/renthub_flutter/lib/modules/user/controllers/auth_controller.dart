import '../../../shared/controllers/loadable_controller.dart';
import '../../../shared/models/domain_models.dart';
import '../repositories/auth_repository.dart';
class AuthController extends LoadableController { AuthController(this.repository); final AuthRepository repository; User? user; UserRole selectedRole=UserRole.renter; bool get authenticated=>user!=null; void selectRole(UserRole role){selectedRole=role;notifyListeners();} Future<void> login(String email,String password)=>run(() async=>user=await repository.login(email,password,selectedRole)); Future<void> register(String name,String email,String password)=>run(() async=>user=await repository.register(name,email,password,selectedRole)); Future<void> logout()=>run(() async {await repository.logout();user=null;}); }

