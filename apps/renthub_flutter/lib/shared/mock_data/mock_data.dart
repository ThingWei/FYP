import '../../core/constants/renthub_categories.dart';
import '../models/domain_models.dart';

class ListingComparisonDetails {
  const ListingComparisonDetails({
    required this.deposit,
    required this.distanceKm,
    required this.reviewCount,
    required this.trustScore,
    required this.fulfilmentMethod,
    required this.availability,
  });

  final double deposit;
  final double distanceKm;
  final int reviewCount;
  final int trustScore;
  final String fulfilmentMethod;
  final String availability;
}

abstract final class MockData {
  static const renter = User(
    id: 'u-renter',
    email: 'renter@renthub.my',
    name: 'Alex Tan',
    roles: {UserRole.renter},
    trustScore: 4.6,
  );
  static const owner = User(
    id: 'u-owner',
    email: 'owner@renthub.my',
    name: 'Sarah J.',
    roles: {UserRole.owner},
    trustScore: 4.9,
  );
  static const dual = User(
    id: 'u-dual',
    email: 'demo@renthub.my',
    name: 'Nur Izzati',
    roles: {UserRole.renter, UserRole.owner},
    trustScore: 4.7,
  );
  static const admin = User(
    id: 'u-admin',
    email: 'admin@renthub.my',
    name: 'Admin Farah',
    roles: {UserRole.admin},
    trustScore: 5,
  );

  static const listings = <Listing>[
    Listing(
      id: 'l-camera',
      title: 'Sony Alpha a7S III Mirrorless Camera',
      category: RentHubCategories.devices,
      dailyPrice: 85,
      condition: 'Excellent',
      ownerName: 'Sarah J.',
      location: 'Bukit Bintang, Kuala Lumpur',
      verified: true,
      isService: false,
      rating: 4.9,
    ),
    Listing(
      id: 'l-canon-r5',
      title: 'Canon EOS R5 Camera',
      category: RentHubCategories.devices,
      dailyPrice: 120,
      condition: 'Like New',
      ownerName: 'LensLab KL',
      location: 'Mont Kiara, Kuala Lumpur',
      verified: true,
      isService: false,
      rating: 5,
    ),
    Listing(
      id: 'l-fujifilm-xt4',
      title: 'Fujifilm X-T4 Camera',
      category: RentHubCategories.devices,
      dailyPrice: 70,
      condition: 'Good',
      ownerName: 'Aisha Rahman',
      location: 'Subang Jaya, Selangor',
      verified: false,
      isService: false,
      rating: 4.7,
    ),
    Listing(
      id: 'l-car',
      title: 'Perodua Myvi 2022',
      category: RentHubCategories.vehicles,
      dailyPrice: 150,
      condition: 'Very good',
      ownerName: 'Amir Hakim',
      location: 'Shah Alam, Selangor',
      verified: true,
      isService: false,
      rating: 4.8,
    ),
    Listing(
      id: 'l-honda-city',
      title: 'Honda City 2021',
      category: RentHubCategories.vehicles,
      dailyPrice: 165,
      condition: 'Excellent',
      ownerName: 'Nadia Mobility',
      location: 'Cheras, Kuala Lumpur',
      verified: true,
      isService: false,
      rating: 4.9,
    ),
    Listing(
      id: 'l-photo',
      title: 'Event Photography Package',
      category: RentHubCategories.services,
      dailyPrice: 450,
      ownerName: 'Aina Rahman',
      location: 'Kuala Lumpur',
      verified: true,
      isService: true,
      rating: 5,
    ),
    Listing(
      id: 'l-tent',
      title: 'Four-person Camping Tent',
      category: RentHubCategories.equipment,
      dailyPrice: 45,
      condition: 'Good',
      ownerName: 'Jason Lee',
      location: 'Subang Jaya, Selangor',
      verified: false,
      isService: false,
      rating: 4.5,
    ),
    Listing(
      id: 'l-tutor',
      title: 'SPM Mathematics Tutoring',
      category: RentHubCategories.services,
      dailyPrice: 80,
      ownerName: 'Siti Nabila',
      location: 'Online / Bangi',
      verified: true,
      isService: true,
      rating: 4.9,
    ),
    Listing(
      id: 'l-dress',
      title: 'Modern Kurung Set',
      category: RentHubCategories.clothing,
      dailyPrice: 55,
      condition: 'Excellent',
      ownerName: 'Farah Atelier',
      location: 'Kuala Lumpur',
      verified: true,
      isService: false,
      rating: 4.8,
    ),
    Listing(
      id: 'l-evening-dress',
      title: 'Emerald Evening Dress',
      category: RentHubCategories.clothing,
      dailyPrice: 75,
      condition: 'Like New',
      ownerName: 'Nora Wardrobe',
      location: 'Bangsar, Kuala Lumpur',
      verified: true,
      isService: false,
      rating: 4.9,
    ),
    Listing(
      id: 'l-book',
      title: 'Engineering Reference Bundle',
      category: RentHubCategories.books,
      dailyPrice: 18,
      condition: 'Good',
      ownerName: 'Hafiz Rahman',
      location: 'Bangi, Selangor',
      verified: true,
      isService: false,
      rating: 4.7,
    ),
    Listing(
      id: 'l-medical-books',
      title: 'Medical Textbook Collection',
      category: RentHubCategories.books,
      dailyPrice: 22,
      condition: 'Very good',
      ownerName: 'Campus Reads',
      location: 'Petaling Jaya, Selangor',
      verified: true,
      isService: false,
      rating: 4.8,
    ),
    Listing(
      id: 'l-drill',
      title: 'Makita Cordless Drill Set',
      category: RentHubCategories.equipment,
      dailyPrice: 38,
      condition: 'Very good',
      ownerName: 'ToolShare PJ',
      location: 'Petaling Jaya, Selangor',
      verified: true,
      isService: false,
      rating: 4.9,
    ),
  ];

  static const comparisonDetails = <String, ListingComparisonDetails>{
    'l-camera': ListingComparisonDetails(
      deposit: 300,
      distanceKm: 2.4,
      reviewCount: 128,
      trustScore: 96,
      fulfilmentMethod: 'Pickup or Owner delivery',
      availability: 'Available today',
    ),
    'l-canon-r5': ListingComparisonDetails(
      deposit: 800,
      distanceKm: 3.5,
      reviewCount: 204,
      trustScore: 99,
      fulfilmentMethod: 'Self Pickup',
      availability: 'Available from 19 Aug',
    ),
    'l-fujifilm-xt4': ListingComparisonDetails(
      deposit: 300,
      distanceKm: 0.8,
      reviewCount: 76,
      trustScore: 91,
      fulfilmentMethod: 'Owner delivery available',
      availability: 'Limited dates',
    ),
    'l-car': ListingComparisonDetails(
      deposit: 1000,
      distanceKm: 4.1,
      reviewCount: 89,
      trustScore: 94,
      fulfilmentMethod: 'Self Pickup',
      availability: 'Available this weekend',
    ),
    'l-honda-city': ListingComparisonDetails(
      deposit: 1200,
      distanceKm: 6.4,
      reviewCount: 112,
      trustScore: 97,
      fulfilmentMethod: 'Pickup or Owner delivery',
      availability: 'Available from 21 Aug',
    ),
    'l-tent': ListingComparisonDetails(
      deposit: 100,
      distanceKm: 5.6,
      reviewCount: 43,
      trustScore: 82,
      fulfilmentMethod: 'Self Pickup',
      availability: 'Unavailable this week',
    ),
    'l-drill': ListingComparisonDetails(
      deposit: 150,
      distanceKm: 2.3,
      reviewCount: 67,
      trustScore: 95,
      fulfilmentMethod: 'Pickup or Owner delivery',
      availability: 'Available today',
    ),
    'l-dress': ListingComparisonDetails(
      deposit: 180,
      distanceKm: 2.8,
      reviewCount: 58,
      trustScore: 93,
      fulfilmentMethod: 'Owner delivery available',
      availability: 'Available this week',
    ),
    'l-evening-dress': ListingComparisonDetails(
      deposit: 250,
      distanceKm: 4.6,
      reviewCount: 94,
      trustScore: 97,
      fulfilmentMethod: 'Self Pickup',
      availability: 'Available from 18 Aug',
    ),
    'l-book': ListingComparisonDetails(
      deposit: 60,
      distanceKm: 8.2,
      reviewCount: 35,
      trustScore: 90,
      fulfilmentMethod: 'Pickup or Owner delivery',
      availability: 'Available today',
    ),
    'l-medical-books': ListingComparisonDetails(
      deposit: 80,
      distanceKm: 3.1,
      reviewCount: 51,
      trustScore: 94,
      fulfilmentMethod: 'Owner delivery available',
      availability: 'Available this week',
    ),
  };

  static ListingComparisonDetails comparisonFor(Listing listing) =>
      comparisonDetails[listing.id] ??
      ListingComparisonDetails(
        deposit: 200,
        distanceKm: 5,
        reviewCount: 0,
        trustScore: (listing.rating * 20).round(),
        fulfilmentMethod: 'Contact Owner for fulfilment',
        availability: 'Check availability',
      );

  static const initialWishlistIds = <String>{
    'l-camera',
    'l-canon-r5',
    'l-fujifilm-xt4',
  };

  static const bookingStatuses = [
    'Pending',
    'Approved',
    'Active',
    'Completed',
    'Disputed',
  ];
  static const notifications = [
    'Your camera booking was approved',
    'Daniel sent you a message',
    'You earned 120 loyalty points',
  ];
}
