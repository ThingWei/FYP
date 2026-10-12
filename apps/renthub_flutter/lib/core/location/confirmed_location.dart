import 'package:latlong2/latlong.dart';

class ListingLocationSelection {
  const ListingLocationSelection(
      {required this.label,
      required this.point,
      this.state = '',
      this.city = '',
      this.postcode = '',
      this.source = 'map',
      this.addressLine1 = '',
      this.addressLine2 = '',
      this.accuracyMeters});
  final String label, state, city, postcode, source;
  final String addressLine1, addressLine2;
  final double? accuracyMeters;
  Map<String, dynamic> toJson() => {
        'coordinates': coordinates,
        'displayAddress': label,
        'city': city,
        'state': state,
        'postcode': postcode,
        'source': source,
        if (addressLine1.isNotEmpty) 'addressLine1': addressLine1,
        if (addressLine2.isNotEmpty) 'addressLine2': addressLine2,
        if (accuracyMeters != null) 'accuracyMeters': accuracyMeters
      };
  ListingLocationSelection copyWith(
          {String? label, String? city, String? state, String? postcode}) =>
      ListingLocationSelection(
          label: label ?? this.label,
          point: point,
          city: city ?? this.city,
          state: state ?? this.state,
          postcode: postcode ?? this.postcode,
          source: source,
          addressLine1: addressLine1,
          addressLine2: addressLine2,
          accuracyMeters: accuracyMeters);
  final LatLng point;
  Map<String, double> get coordinates =>
      {'latitude': point.latitude, 'longitude': point.longitude};
  factory ListingLocationSelection.fromJson(Map<String, dynamic> row) {
    final coordinates = row['coordinates'];
    if (coordinates is! Map ||
        coordinates['latitude'] is! num ||
        coordinates['longitude'] is! num ||
        (row['label'] ?? row['displayAddress']) is! String ||
        ((row['label'] ?? row['displayAddress']) as String).trim().isEmpty) {
      throw const FormatException('Invalid location result');
    }
    final lat = (coordinates['latitude'] as num).toDouble(),
        lon = (coordinates['longitude'] as num).toDouble();
    if (!lat.isFinite || !lon.isFinite || lat.abs() > 90 || lon.abs() > 180) {
      throw const FormatException('Invalid map position');
    }
    return ListingLocationSelection(
        label: row['label'] ?? row['displayAddress'],
        point: LatLng(lat, lon),
        state: row['state'] as String? ?? '',
        city: row['city'] as String? ?? '',
        postcode: row['postcode'] as String? ?? '',
        source: row['source'] as String? ?? 'search',
        addressLine1: row['addressLine1'] as String? ?? '',
        addressLine2: row['addressLine2'] as String? ?? '',
        accuracyMeters: (row['accuracyMeters'] as num?)?.toDouble());
  }
}
