import 'package:flutter/foundation.dart';

import '../../../../shared/models/domain_models.dart';

class ComparisonSelectionController extends ChangeNotifier {
  final Set<String> _selectedIds = <String>{};
  String? _category;

  Set<String> get selectedIds => Set.unmodifiable(_selectedIds);
  int get count => _selectedIds.length;
  bool get canCompare => count >= 2;

  String? toggle(Listing listing) {
    if (listing.isService) {
      return 'Services use a separate booking flow and cannot be compared here.';
    }
    if (_selectedIds.remove(listing.id)) {
      if (_selectedIds.isEmpty) _category = null;
      notifyListeners();
      return null;
    }
    if (_selectedIds.length >= 3) {
      return 'You can compare up to 3 listings.';
    }
    if (_category != null && _category != listing.category) {
      return 'Choose listings from the same category.';
    }
    _category = listing.category;
    _selectedIds.add(listing.id);
    notifyListeners();
    return null;
  }

  void remove(String listingId) {
    if (!_selectedIds.remove(listingId)) return;
    if (_selectedIds.isEmpty) _category = null;
    notifyListeners();
  }

  void clear() {
    if (_selectedIds.isEmpty) return;
    _selectedIds.clear();
    _category = null;
    notifyListeners();
  }
}
