import '../../../shared/controllers/loadable_controller.dart'; import '../repositories/payment_repository.dart';
class PaymentController extends LoadableController { PaymentController(this.repository);final PaymentRepository repository;Map<String,dynamic>? result;Future<void> pay(double amount)=>run(()async=>result=await repository.simulate(amount)); }
