import 'package:flutter/material.dart';
import '../location/confirmed_location.dart';
import '../../shared/models/domain_models.dart';

class DiscoveryFilters {
  const DiscoveryFilters(
      {this.category = 'All',
      this.type = 'all',
      this.location = '',
      this.centre,
      this.radiusKm = 10,
      this.minimumPrice = '',
      this.maximumPrice = '',
      this.verifiedOnly = false,
      this.promotionsOnly = false,
      this.sort = 'recommended',
      this.dates});
  final String category, type, location, minimumPrice, maximumPrice, sort;
  final ListingLocationSelection? centre;
  final int radiusKm;
  final bool verifiedOnly, promotionsOnly;
  final DateTimeRange? dates;
  int get activeCount =>
      (category == 'All' ? 0 : 1) +
      (type == 'all' ? 0 : 1) +
      (location.isEmpty && centre == null ? 0 : 1) +
      (minimumPrice.isEmpty && maximumPrice.isEmpty ? 0 : 1) +
      (verifiedOnly ? 1 : 0) +
      (promotionsOnly ? 1 : 0) +
      (dates == null ? 0 : 1) +
      (sort == 'recommended' ? 0 : 1);
}

/// In-memory, account-scoped screen state. Home and Explore have separate slots.
class MarketplaceViewState {
  DiscoveryFilters filters = const DiscoveryFilters();
  String query = '', viewMode = '';
  String? resultQuery;
  List<Listing>? results;
  int limit = 20;
  bool pending = false;
  DateTime? successfulAt;
}
