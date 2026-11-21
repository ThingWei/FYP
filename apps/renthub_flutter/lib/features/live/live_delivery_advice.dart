import 'dart:math' as math;
import '../../shared/models/domain_models.dart';
import 'live_location_picker.dart';

String? normalizedRentalState(String value) {
  final state = value.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
  const aliases = {
    'pulaupinang': 'penang',
    'penang': 'penang',
    'melaka': 'melaka',
    'malacca': 'melaka',
    'negerisembilan': 'negerisembilan',
    'johor': 'johor',
    'kedah': 'kedah',
    'kelantan': 'kelantan',
    'pahang': 'pahang',
    'perak': 'perak',
    'perlis': 'perlis',
    'sabah': 'sabah',
    'sarawak': 'sarawak',
    'selangor': 'selangor',
    'terengganu': 'terengganu',
    'kualalumpur': 'kualalumpur',
    'wpkualalumpur': 'kualalumpur',
    'wilayahpersekutuankualalumpur': 'kualalumpur',
    'putrajaya': 'putrajaya',
    'wpputrajaya': 'putrajaya',
    'wilayahpersekutuanputrajaya': 'putrajaya',
    'labuan': 'labuan',
    'wplabuan': 'labuan',
    'wilayahpersekutuanlabuan': 'labuan',
  };
  return aliases[state];
}

/// Approximate straight-line guidance, never a delivery eligibility decision.
bool recommendsDelivery(Listing listing, ListingLocationSelection? area) {
  if (listing.isService ||
      area == null ||
      !listing.fulfilmentMethods.contains('owner_delivery') ||
      listing.latitude == null ||
      listing.longitude == null) {
    return false;
  }
  final from = normalizedRentalState(area.state),
      to = normalizedRentalState(listing.state);
  final latitude = listing.latitude!, longitude = listing.longitude!;
  if (from == null ||
      to == null ||
      !latitude.isFinite ||
      !longitude.isFinite ||
      latitude.abs() > 90 ||
      longitude.abs() > 180 ||
      !area.point.latitude.isFinite ||
      !area.point.longitude.isFinite ||
      area.point.latitude.abs() > 90 ||
      area.point.longitude.abs() > 180) {
    return false;
  }
  final lat1 = area.point.latitude * math.pi / 180,
      lat2 = latitude * math.pi / 180;
  final dLat = lat2 - lat1,
      dLon = (longitude - area.point.longitude) * math.pi / 180;
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLon / 2), 2);
  final km = 6371.0088 * 2 * math.asin(math.sqrt(a.clamp(0, 1)));
  return from != to || km > 25;
}
