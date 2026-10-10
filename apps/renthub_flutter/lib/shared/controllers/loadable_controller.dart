import '../../core/network/user_facing_error.dart';
import 'package:flutter/foundation.dart';

abstract class LoadableController extends ChangeNotifier {
  bool loading = false;
  String? error;
  Object? lastError;
  Future<void> run(Future<void> Function() operation) async {
    loading = true;
    error = null;
    lastError = null;
    notifyListeners();
    try {
      await operation();
    } catch (e) {
      lastError = e;
      error = friendlyError(e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}
