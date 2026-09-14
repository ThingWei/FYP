import { connectDatabase, disconnectDatabase } from '../config/database.js';
import { validateEnv } from '../config/env.js';
import { BookingModel } from '../modules/booking/booking.model.js';
import { MessageModel } from '../modules/communication/message.model.js';
import { MessageReportModel } from '../modules/communication/messageReport.model.js';
import { NotificationModel } from '../modules/communication/notification.model.js';
import { ThreadModel } from '../modules/communication/thread.model.js';
import { listingModule } from '../modules/listing/index.js';
import { PaymentModel } from '../modules/payment/payment.model.js';
import { RentalModel } from '../modules/rental/rental.model.js';
import { UserModel } from '../modules/user/user.model.js';

const users = [
  {
    authId: 'u-renter',
    email: 'renter@renthub.my',
    displayName: 'Alex Tan',
    roles: ['renter'],
    activeRole: 'renter',
    trustScore: 92,
    verification: { status: 'approved', tier: 'basic' },
  },
  {
    authId: 'u-owner',
    email: 'owner@renthub.my',
    displayName: 'Sarah J.',
    roles: ['owner'],
    activeRole: 'owner',
    trustScore: 98,
    verification: { status: 'approved', tier: 'enhanced' },
  },
  {
    authId: 'u-aina',
    email: 'aina@renthub.my',
    displayName: 'Aina Rahman',
    roles: ['owner'],
    activeRole: 'owner',
    trustScore: 98,
    verification: { status: 'approved', tier: 'enhanced' },
  },
  {
    authId: 'u-dual',
    email: 'demo@renthub.my',
    displayName: 'Nur Izzati',
    roles: ['renter', 'owner'],
    activeRole: 'renter',
    trustScore: 94,
    verification: { status: 'pending', tier: 'basic' },
  },
  {
    authId: 'u-admin',
    email: 'admin@renthub.my',
    displayName: 'Admin Farah',
    roles: ['admin'],
    activeRole: 'admin',
    trustScore: 100,
    verification: { status: 'approved', tier: 'enhanced' },
  },
];

const listings = [
  {
    publicId: 'l-camera',
    ownerId: 'u-owner',
    ownerName: 'Sarah J.',
    title: 'Sony Alpha a7S III Mirrorless Camera',
    description: 'Professional full-frame camera kit for productions and events.',
    category: 'Devices',
    listingType: 'physical',
    dailyPrice: 85,
    condition: 'Excellent',
    securityDeposit: 300,
    damageWaiverAvailable: true,
    damageWaiverFee: 15,
    fulfilmentMethods: ['pickup', 'owner_delivery'],
    location: 'Bukit Bintang, Kuala Lumpur',
    state: 'Kuala Lumpur',
    status: 'active',
    verified: true,
    rating: 4.9,
    reviewCount: 128,
    promoted: true,
  },
  {
    publicId: 'l-canon-r5',
    ownerId: 'u-lenslab',
    ownerName: 'LensLab KL',
    title: 'Canon EOS R5 Camera',
    category: 'Devices',
    listingType: 'physical',
    dailyPrice: 120,
    condition: 'Like New',
    securityDeposit: 800,
    fulfilmentMethods: ['pickup'],
    location: 'Mont Kiara, Kuala Lumpur',
    state: 'Kuala Lumpur',
    status: 'active',
    verified: true,
    rating: 5,
    reviewCount: 204,
  },
  {
    publicId: 'l-fujifilm-xt4',
    ownerId: 'u-aisha',
    ownerName: 'Aisha Rahman',
    title: 'Fujifilm X-T4 Camera',
    category: 'Devices',
    listingType: 'physical',
    dailyPrice: 70,
    condition: 'Good',
    securityDeposit: 300,
    fulfilmentMethods: ['pickup', 'owner_delivery'],
    location: 'Subang Jaya, Selangor',
    state: 'Selangor',
    status: 'active',
    verified: false,
    rating: 4.7,
    reviewCount: 76,
  },
  {
    publicId: 'l-car',
    ownerId: 'u-amir',
    ownerName: 'Amir Hakim',
    title: 'Perodua Myvi 2022',
    category: 'Vehicles',
    listingType: 'physical',
    dailyPrice: 150,
    condition: 'Very good',
    securityDeposit: 1000,
    fulfilmentMethods: ['pickup'],
    location: 'Shah Alam, Selangor',
    state: 'Selangor',
    status: 'active',
    verified: true,
    rating: 4.8,
    reviewCount: 89,
  },
  {
    publicId: 'l-honda-city',
    ownerId: 'u-nadia',
    ownerName: 'Nadia Mobility',
    title: 'Honda City 2021',
    category: 'Vehicles',
    listingType: 'physical',
    dailyPrice: 165,
    condition: 'Excellent',
    securityDeposit: 1200,
    fulfilmentMethods: ['pickup', 'owner_delivery'],
    location: 'Cheras, Kuala Lumpur',
    state: 'Kuala Lumpur',
    status: 'active',
    verified: true,
    rating: 4.9,
    reviewCount: 112,
  },
  {
    publicId: 'l-photo',
    ownerId: 'u-aina',
    ownerName: 'Aina Rahman',
    title: 'Event Photography Package',
    category: 'Services',
    listingType: 'service',
    dailyPrice: 450,
    priceUnit: 'package',
    serviceDetails: {
      packageName: 'Essential Event Coverage',
      durationMinutes: 180,
      venueMode: 'renter_location',
      inclusions: ['Edited digital gallery', 'One photographer'],
    },
    location: 'Kuala Lumpur',
    state: 'Kuala Lumpur',
    status: 'active',
    verified: true,
    rating: 5,
    reviewCount: 91,
    promoted: true,
  },
  {
    publicId: 'l-tent',
    ownerId: 'u-jason',
    ownerName: 'Jason Lee',
    title: 'Four-person Camping Tent',
    category: 'Equipment',
    listingType: 'physical',
    dailyPrice: 45,
    condition: 'Good',
    securityDeposit: 100,
    fulfilmentMethods: ['pickup'],
    location: 'Subang Jaya, Selangor',
    state: 'Selangor',
    status: 'active',
    verified: false,
    rating: 4.5,
    reviewCount: 43,
  },
  {
    publicId: 'l-tutor',
    ownerId: 'u-siti',
    ownerName: 'Siti Nabila',
    title: 'SPM Mathematics Tutoring',
    category: 'Services',
    listingType: 'service',
    dailyPrice: 80,
    priceUnit: 'session',
    serviceDetails: {
      packageName: 'Focused Revision Session',
      durationMinutes: 90,
      venueMode: 'flexible',
      inclusions: ['Practice questions', 'Progress notes'],
    },
    location: 'Online / Bangi',
    state: 'Selangor',
    status: 'active',
    verified: true,
    rating: 4.9,
    reviewCount: 74,
  },
  {
    publicId: 'l-dress',
    ownerId: 'u-farah-atelier',
    ownerName: 'Farah Atelier',
    title: 'Modern Kurung Set',
    category: 'Clothing',
    listingType: 'physical',
    dailyPrice: 55,
    condition: 'Excellent',
    securityDeposit: 180,
    fulfilmentMethods: ['pickup', 'owner_delivery'],
    location: 'Kuala Lumpur',
    state: 'Kuala Lumpur',
    status: 'active',
    verified: true,
    rating: 4.8,
    reviewCount: 58,
  },
  {
    publicId: 'l-evening-dress',
    ownerId: 'u-nora',
    ownerName: 'Nora Wardrobe',
    title: 'Emerald Evening Dress',
    category: 'Clothing',
    listingType: 'physical',
    dailyPrice: 75,
    condition: 'Like New',
    securityDeposit: 250,
    fulfilmentMethods: ['pickup'],
    location: 'Bangsar, Kuala Lumpur',
    state: 'Kuala Lumpur',
    status: 'active',
    verified: true,
    rating: 4.9,
    reviewCount: 94,
  },
  {
    publicId: 'l-book',
    ownerId: 'u-hafiz',
    ownerName: 'Hafiz Rahman',
    title: 'Engineering Reference Bundle',
    category: 'Books',
    listingType: 'physical',
    dailyPrice: 18,
    condition: 'Good',
    securityDeposit: 60,
    fulfilmentMethods: ['pickup', 'owner_delivery'],
    location: 'Bangi, Selangor',
    state: 'Selangor',
    status: 'active',
    verified: true,
    rating: 4.7,
    reviewCount: 35,
  },
  {
    publicId: 'l-medical-books',
    ownerId: 'u-campus-reads',
    ownerName: 'Campus Reads',
    title: 'Medical Textbook Collection',
    category: 'Books',
    listingType: 'physical',
    dailyPrice: 22,
    condition: 'Very good',
    securityDeposit: 80,
    fulfilmentMethods: ['owner_delivery'],
    location: 'Petaling Jaya, Selangor',
    state: 'Selangor',
    status: 'active',
    verified: true,
    rating: 4.8,
    reviewCount: 51,
  },
  {
    publicId: 'l-drill',
    ownerId: 'u-toolshare',
    ownerName: 'ToolShare PJ',
    title: 'Makita Cordless Drill Set',
    category: 'Equipment',
    listingType: 'physical',
    dailyPrice: 38,
    condition: 'Very good',
    securityDeposit: 150,
    fulfilmentMethods: ['pickup', 'owner_delivery'],
    location: 'Petaling Jaya, Selangor',
    state: 'Selangor',
    status: 'active',
    verified: true,
    rating: 4.9,
    reviewCount: 67,
  },
];

const bookings = [
  {
    publicId: 'RH-BKG-2026-09142',
    listingId: 'l-camera',
    listingTitle: 'Sony Alpha a7S III Mirrorless Camera',
    listingType: 'physical',
    renterId: 'u-renter',
    renterName: 'Alex Tan',
    ownerId: 'u-owner',
    startDate: new Date('2026-09-20T00:00:00+08:00'),
    endDate: new Date('2026-09-22T00:00:00+08:00'),
    fulfilmentMethod: 'pickup',
    damageWaiverSelected: true,
    pricing: {
      baseAmount: 255,
      securityDeposit: 300,
      damageWaiverFee: 15,
      platformFee: 0,
      total: 570,
      currency: 'MYR',
    },
    status: 'active',
    paymentStatus: 'captured',
    paymentAuthorizationId: 'TXN-AUTH-2026-09142',
    decidedAt: new Date('2026-09-15T09:00:00+08:00'),
    activatedAt: new Date('2026-09-20T09:00:00+08:00'),
  },
  {
    publicId: 'RH-SVC-2026-03218',
    listingId: 'l-photo',
    listingTitle: 'Event Photography Package',
    listingType: 'service',
    renterId: 'u-renter',
    renterName: 'Alex Tan',
    ownerId: 'u-aina',
    startDate: new Date('2026-10-03T14:00:00+08:00'),
    endDate: new Date('2026-10-03T17:00:00+08:00'),
    serviceVenue: 'Glasshouse Seputeh, Kuala Lumpur',
    pricing: {
      baseAmount: 450,
      securityDeposit: 0,
      damageWaiverFee: 0,
      platformFee: 22.5,
      total: 472.5,
      currency: 'MYR',
    },
    status: 'pending',
    paymentStatus: 'authorized',
    paymentAuthorizationId: 'TXN-AUTH-2026-03218',
  },
];

const payments = [
  {
    publicId: 'TXN-AUTH-2026-09142',
    bookingId: 'RH-BKG-2026-09142',
    payerId: 'u-renter',
    payeeId: 'u-owner',
    type: 'authorization',
    amount: 570,
    method: 'card',
    status: 'authorized',
    gatewayReference: 'seed_auth_camera',
    idempotencyKey: 'seed:authorization:RH-BKG-2026-09142',
    simulated: true,
  },
  {
    publicId: 'TXN-CAP-2026-09142',
    bookingId: 'RH-BKG-2026-09142',
    payerId: 'u-renter',
    payeeId: 'u-owner',
    type: 'capture',
    amount: 570,
    method: 'card',
    status: 'succeeded',
    gatewayReference: 'seed_capture_camera',
    idempotencyKey: 'capture:RH-BKG-2026-09142',
    parentTransactionId: 'TXN-AUTH-2026-09142',
    simulated: true,
  },
  {
    publicId: 'TXN-AUTH-2026-03218',
    bookingId: 'RH-SVC-2026-03218',
    payerId: 'u-renter',
    payeeId: 'u-aina',
    type: 'authorization',
    amount: 472.5,
    method: 'fpx',
    status: 'authorized',
    gatewayReference: 'seed_auth_service',
    idempotencyKey: 'seed:authorization:RH-SVC-2026-03218',
    simulated: true,
  },
];

const rentals = [
  {
    publicId: 'RH-RNT-2026-09142',
    bookingId: 'RH-BKG-2026-09142',
    listingId: 'l-camera',
    listingType: 'physical',
    renterId: 'u-renter',
    ownerId: 'u-owner',
    startDate: new Date('2026-09-20T00:00:00+08:00'),
    endDate: new Date('2026-09-22T00:00:00+08:00'),
    status: 'active',
    handover: {
      condition: 'Excellent',
      notes: 'Camera body, lens and accessories checked together.',
      evidence: ['local://handover/camera-front.jpg'],
      recordedAt: new Date('2026-09-20T09:00:00+08:00'),
    },
  },
];

const threads = [
  {
    publicId: 'THR-RH-BKG-2026-09142',
    bookingId: 'RH-BKG-2026-09142',
    listingId: 'l-camera',
    listingTitle: 'Sony Alpha a7S III Mirrorless Camera',
    listingType: 'physical',
    renterId: 'u-renter',
    ownerId: 'u-owner',
    participantIds: ['u-renter', 'u-owner'],
    status: 'open',
    lastMessageText: 'Yes, the selected date is available.',
    lastMessageSenderId: 'u-owner',
    lastMessageAt: new Date('2026-09-14T10:24:00+08:00'),
  },
  {
    publicId: 'THR-RH-SVC-2026-03218',
    bookingId: 'RH-SVC-2026-03218',
    listingId: 'l-photo',
    listingTitle: 'Event Photography Package',
    listingType: 'service',
    renterId: 'u-renter',
    ownerId: 'u-aina',
    participantIds: ['u-renter', 'u-aina'],
    status: 'open',
    lastMessageText: 'I reviewed your service requirements.',
    lastMessageSenderId: 'u-aina',
    lastMessageAt: new Date('2026-09-14T11:05:00+08:00'),
  },
];

const messages = [
  {
    publicId: 'MSG-SEED-CAMERA-01',
    threadId: 'THR-RH-BKG-2026-09142',
    senderId: 'u-renter',
    recipientId: 'u-owner',
    text: 'Hi Sarah, is the full camera kit included?',
    readAt: new Date('2026-09-14T10:20:00+08:00'),
  },
  {
    publicId: 'MSG-SEED-CAMERA-02',
    threadId: 'THR-RH-BKG-2026-09142',
    senderId: 'u-owner',
    recipientId: 'u-renter',
    text: 'Yes, the selected date is available.',
  },
  {
    publicId: 'MSG-SEED-SERVICE-01',
    threadId: 'THR-RH-SVC-2026-03218',
    senderId: 'u-renter',
    recipientId: 'u-aina',
    text: 'The event starts at 2 PM at Glasshouse Seputeh.',
    readAt: new Date('2026-09-14T11:02:00+08:00'),
  },
  {
    publicId: 'MSG-SEED-SERVICE-02',
    threadId: 'THR-RH-SVC-2026-03218',
    senderId: 'u-aina',
    recipientId: 'u-renter',
    text: 'I reviewed your service requirements.',
  },
];

const notifications = [
  {
    publicId: 'NTF-SEED-BOOKING-01',
    userId: 'u-renter',
    category: 'booking',
    type: 'booking_approved',
    title: 'Booking approved',
    body: 'Your Sony Alpha a7S III booking is confirmed.',
    entityType: 'booking',
    entityId: 'RH-BKG-2026-09142',
    readAt: new Date('2026-09-15T09:05:00+08:00'),
  },
  {
    publicId: 'NTF-SEED-MESSAGE-01',
    userId: 'u-renter',
    category: 'message',
    type: 'message_new',
    title: 'New message from Sarah J.',
    body: 'Yes, the selected date is available.',
    entityType: 'thread',
    entityId: 'THR-RH-BKG-2026-09142',
  },
  {
    publicId: 'NTF-SEED-PAYMENT-01',
    userId: 'u-owner',
    category: 'payment',
    type: 'payment_authorized',
    title: 'Payment authorized',
    body: 'RM 570.00 is authorized for the camera booking.',
    entityType: 'payment',
    entityId: 'TXN-AUTH-2026-09142',
  },
  {
    publicId: 'NTF-SEED-SERVICE-01',
    userId: 'u-aina',
    category: 'booking',
    type: 'booking_created',
    title: 'New service booking request',
    body: 'Alex Tan requested the Event Photography Package.',
    entityType: 'booking',
    entityId: 'RH-SVC-2026-03218',
  },
];

const messageReports = [
  {
    publicId: 'RPT-MSG-SEED-01',
    messageId: 'MSG-SEED-CAMERA-02',
    threadId: 'THR-RH-BKG-2026-09142',
    reporterId: 'u-renter',
    reportedUserId: 'u-owner',
    messageText: 'Yes, the selected date is available.',
    reason: 'other',
    details: 'Seeded example for the administrator moderation queue.',
    status: 'open',
  },
];

try {
  validateEnv();
  await connectDatabase();
  await UserModel.bulkWrite(
    users.map((user) => ({
      updateOne: {
        filter: { authId: user.authId },
        update: { $set: user },
        upsert: true,
      },
    })),
  );
  await listingModule.Model.bulkWrite(
    listings.map((listing) => ({
      updateOne: {
        filter: { title: listing.title, ownerId: listing.ownerId },
        update: { $set: listing },
        upsert: true,
      },
    })),
  );
  await BookingModel.bulkWrite(
    bookings.map((booking) => ({
      updateOne: {
        filter: { publicId: booking.publicId },
        update: { $set: booking },
        upsert: true,
      },
    })),
  );
  await RentalModel.bulkWrite(
    rentals.map((rental) => ({
      updateOne: {
        filter: { publicId: rental.publicId },
        update: { $set: rental },
        upsert: true,
      },
    })),
  );
  await PaymentModel.bulkWrite(
    payments.map((payment) => ({
      updateOne: {
        filter: { publicId: payment.publicId },
        update: { $set: payment },
        upsert: true,
      },
    })),
  );
  await ThreadModel.bulkWrite(
    threads.map((thread) => ({
      updateOne: {
        filter: { publicId: thread.publicId },
        update: { $set: thread },
        upsert: true,
      },
    })),
  );
  await MessageModel.bulkWrite(
    messages.map((message) => ({
      updateOne: {
        filter: { publicId: message.publicId },
        update: { $set: message },
        upsert: true,
      },
    })),
  );
  await NotificationModel.bulkWrite(
    notifications.map((notification) => ({
      updateOne: {
        filter: { publicId: notification.publicId },
        update: { $set: notification },
        upsert: true,
      },
    })),
  );
  await MessageReportModel.bulkWrite(
    messageReports.map((report) => ({
      updateOne: {
        filter: { publicId: report.publicId },
        update: { $set: report },
        upsert: true,
      },
    })),
  );
  console.log(
    `Seed complete: ${users.length} users, ${listings.length} listings, ` +
      `${bookings.length} bookings, ${rentals.length} rentals, ` +
      `${payments.length} payments, ${threads.length} threads, ` +
      `${messages.length} messages, ${notifications.length} notifications, ` +
      `${messageReports.length} message report`,
  );
} finally {
  await disconnectDatabase();
}

