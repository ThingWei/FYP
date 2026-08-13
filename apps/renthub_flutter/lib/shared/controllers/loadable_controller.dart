import 'package:flutter/foundation.dart';

abstract class LoadableController extends ChangeNotifier {
  bool loading = false;
  String? error;
  Future<void> run(Future<void> Function() operation) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await operation();
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}
