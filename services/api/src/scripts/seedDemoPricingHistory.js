import { connectDatabase, disconnectDatabase } from '../config/database.js';
import { BookingModel } from '../modules/booking/booking.model.js';
import { ListingModel } from '../modules/listing/listing.model.js';

const examples = [
  ['Toyota', 'Camry', 'Excellent', 2, 150],
  ['Toyota', 'Camry', 'Very good', 4, 135],
  ['Toyota', 'Camry', 'Good', 6, 118],
  ['Toyota', 'Corolla', 'Excellent', 2, 125],
  ['Toyota', 'Vios', 'Very good', 4, 105],
  ['Honda', 'Civic', 'Excellent', 2, 140],
  ['Honda', 'City', 'Very good', 4, 110],
  ['Perodua', 'Myvi', 'Excellent', 2, 88],
  ['Perodua', 'Bezza', 'Good', 5, 72],
  ['Giant', 'Talon', 'Excellent', 1, 42, 'Bicycles'],
  ['Trek', 'Marlin', 'Very good', 3, 36, 'Bicycles'],
  ['Polygon', 'Xtrada', 'Good', 5, 29, 'Bicycles'],
];

try {
  await connectDatabase();
  for (const [index, item] of examples.entries()) {
    const [brand, model, condition, itemAgeYears, dailyPrice, subcategory = 'Cars'] = item;
    const suffix = String(index + 1).padStart(2, '0');
    const listingId = `l-demo-pricing-${suffix}`;
    const listing = {
      publicId: listingId,
      ownerId: `demo-pricing-owner-${(index % 3) + 1}`,
      ownerName: 'RentHub Demo Owner',
      title: `${brand} ${model} pricing demo`,
      description: 'Clearly labelled development-only pricing evidence.',
      category: 'Vehicles',
      subcategory,
      brand,
      productModel: model,
      productMatchType: 'manual_entry',
      itemAgeYears,
      listingType: 'physical',
      sourceType: 'demo_seed',
      dailyPrice,
      condition,
      securityDeposit: 0,
      fulfilmentMethods: ['pickup'],
      location: index % 2 ? 'Petaling Jaya' : 'Kuala Lumpur',
      state: index % 2 ? 'Selangor' : 'Kuala Lumpur',
      status: 'inactive',
    };
    await ListingModel.findOneAndUpdate(
      { publicId: listingId, sourceType: 'demo_seed' },
      { $set: listing },
      { upsert: true, runValidators: true },
    );

    const startDate = new Date(Date.UTC(2026, 6 + (index % 3), 2 + index));
    const endDate = new Date(startDate);
    endDate.setUTCDate(endDate.getUTCDate() + 2);
    const completedAt = new Date(endDate);
    completedAt.setUTCHours(completedAt.getUTCHours() + 6);
    const baseAmount = dailyPrice * 3;
    await BookingModel.findOneAndUpdate(
      { publicId: `RH-BKG-2026-DEMO${suffix}`, sourceType: 'demo_seed' },
      {
        $set: {
          publicId: `RH-BKG-2026-DEMO${suffix}`,
          listingId,
          listingTitle: listing.title,
          listingType: 'physical',
          sourceType: 'demo_seed',
          renterId: `demo-pricing-renter-${(index % 4) + 1}`,
          renterName: 'RentHub Demo Renter',
          ownerId: listing.ownerId,
          startDate,
          endDate,
          fulfilmentMethod: 'pickup',
          pricing: {
            baseAmount,
            securityDeposit: 0,
            damageWaiverFee: 0,
            platformFee: 0,
            total: baseAmount,
            currency: 'MYR',
          },
          paymentStatus: 'settled',
          status: 'completed',
          completedAt,
        },
      },
      { upsert: true, runValidators: true },
    );
  }
  console.log(JSON.stringify({
    sourceType: 'demo_seed',
    records: examples.length,
    includedInPricingEvidence: false,
    enableWith: 'PRICING_INCLUDE_DEMO_SEED=true (development only)',
  }));
} finally {
  await disconnectDatabase();
}
