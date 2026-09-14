import 'package:flutter/foundation.dart';

import '../../../../shared/mock_data/mock_data.dart';

abstract final class RenterPrototypeState {
  static final wishlist = ValueNotifier<Set<String>>(
    Set<String>.from(MockData.initialWishlistIds),
  );
  static final blockedOwners = ValueNotifier<Set<String>>(<String>{});
  static final reportedListings = ValueNotifier<Set<String>>(<String>{});
}
