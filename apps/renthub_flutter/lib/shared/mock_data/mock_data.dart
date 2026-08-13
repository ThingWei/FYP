import '../models/domain_models.dart';

abstract final class MockData {
  static const renter = User(
    id: 'u-renter',
    email: 'renter@renthub.my',
    name: 'Aina Rahman',
    roles: {UserRole.renter},
    trustScore: 4.8,
  );
  static const owner = User(
    id: 'u-owner',
    email: 'owner@renthub.my',
    name: 'Daniel Tan',
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
      title: 'Sony Alpha A7 III Camera',
      category: 'Electronics',
      dailyPrice: 120,
      condition: 'Excellent',
      ownerName: 'Daniel Tan',
      location: 'Petaling Jaya, Selangor',
      verified: true,
      isService: false,
      rating: 4.9,
    ),
    Listing(
      id: 'l-car',
      title: 'Perodua Myvi 2022',
      category: 'Vehicles',
      dailyPrice: 150,
      condition: 'Very good',
      ownerName: 'Amir Hakim',
      location: 'Shah Alam, Selangor',
      verified: true,
      isService: false,
      rating: 4.8,
    ),
    Listing(
      id: 'l-photo',
      title: 'Event Photography Package',
      category: 'Services',
      dailyPrice: 650,
      ownerName: 'Mei Lin Studio',
      location: 'Kuala Lumpur',
      verified: true,
      isService: true,
      rating: 5,
    ),
    Listing(
      id: 'l-tent',
      title: 'Four-person Camping Tent',
      category: 'Outdoor',
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
      category: 'Services',
      dailyPrice: 80,
      ownerName: 'Siti Nabila',
      location: 'Online / Bangi',
      verified: true,
      isService: true,
      rating: 4.9,
    ),
  ];

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
