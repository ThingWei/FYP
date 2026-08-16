abstract final class RentHubCategories {
  static const clothing = 'Clothing';
  static const vehicles = 'Vehicles';
  static const services = 'Services';
  static const devices = 'Devices';
  static const books = 'Books';
  static const equipment = 'Equipment';

  static const values = <String>[
    clothing,
    vehicles,
    services,
    devices,
    books,
    equipment,
  ];

  static bool isProtected(String value) => values.contains(value);
}
