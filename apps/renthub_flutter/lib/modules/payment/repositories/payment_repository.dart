abstract interface class PaymentRepository { Future<Map<String,dynamic>> simulate(double amount); }
class MockPaymentRepository implements PaymentRepository { @override Future<Map<String,dynamic>> simulate(double amount) async=>{'id':'sim-demo','amount':amount,'status':'succeeded'}; }
