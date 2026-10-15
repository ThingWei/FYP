import '../../shared/models/domain_models.dart';

class RecommendationSection {
  const RecommendationSection(this.status, [this.items = const []]);
  final String status;
  final List<Listing> items;
  factory RecommendationSection.fromJson(dynamic json) {
    try {
      if (json is! Map ||
          json['items'] is! List ||
          !const ['ready', 'empty', 'unavailable', 'location_required']
              .contains(json['status'])) {
        return const RecommendationSection('unavailable');
      }
      return RecommendationSection(
          json['status'] as String,
          (json['items'] as List)
              .map((row) =>
                  Listing.fromJson(Map<String, dynamic>.from(row as Map)))
              .toList());
    } catch (_) {
      return const RecommendationSection('unavailable');
    }
  }
}

const physicalSubcategories = {
  'Devices': [
    'Smartphones',
    'Cameras',
    'Computers',
    'Audio',
    'Gaming',
    'Other devices'
  ],
  'Vehicles': ['Cars', 'Motorcycles', 'Bicycles', 'Other vehicles'],
  'Equipment': [
    'Tools',
    'Sports equipment',
    'Event equipment',
    'Other equipment'
  ],
  'Books': ['Textbooks', 'Reference books', 'Fiction', 'Other books'],
  'Clothing': ['Formal wear', 'Costumes', 'Traditional wear', 'Other clothing'],
};
String? comparisonGroup(Listing item) => !item.isService &&
        (physicalSubcategories[item.category]?.contains(item.subcategory) ??
            false)
    ? '${item.category}/${item.subcategory}'
    : null;
bool validComparison(List<Listing> items) =>
    items.length <= 3 &&
    (items.isEmpty ||
        comparisonGroup(items.first) != null &&
            items.every((item) =>
                comparisonGroup(item) == comparisonGroup(items.first)));
