import 'input_validation.dart';

/// Explicit field contracts. These limits mirror Express; labels do not decide validation at runtime.
class InputRules {
  static const describeWhatHappened =
      InputRule('Describe what happened', minLength: 15, maxLength: 3000);
  static const review = InputRule('Review', minLength: 10, maxLength: 1500);
  static const details =
      InputRule('Details', optional: true, minLength: 0, maxLength: 1000);
  static const writeAMessage =
      InputRule('Write a message', optional: true, minLength: 0);
  static const displayName =
      InputRule('Display name', minLength: 2, maxLength: 80);
  static const phoneNumber = InputRule('Phone number',
      kind: InputKind.phone, optional: true, maxLength: 24);
  static const reasonForLeaving =
      InputRule('Reason for leaving', minLength: 5, maxLength: 500);
  static const searchItemsVehiclesServices = InputRule(
      'Search items, vehicles, services…',
      optional: true,
      minLength: 0,
      maxLength: 100);
  static const searchPhysicalItems = InputRule('Search physical items',
      optional: true, minLength: 0, maxLength: 100);
  static const searchConversations = InputRule('Search conversations',
      optional: true, minLength: 0, maxLength: 100);
  static const searchRentalsAndServices = InputRule(
      'Search rentals and services',
      optional: true,
      minLength: 0,
      maxLength: 100);
  static const location =
      InputRule('Location', optional: true, minLength: 0, maxLength: 100);
  static const minRm =
      InputRule('Min RM', kind: InputKind.money, optional: true, maxLength: 30);
  static const maxRm =
      InputRule('Max RM', kind: InputKind.money, optional: true, maxLength: 30);
  static const serviceVenue =
      InputRule('Service venue', minLength: 2, maxLength: 240);
  static const noteToOwnerOptional = InputRule('Note to Owner (optional)',
      optional: true, minLength: 0, maxLength: 1000);
  static const cancellationReason =
      InputRule('Cancellation reason', minLength: 3, maxLength: 500);
  static const reasonForAdministratorReview = InputRule(
      'Reason for administrator review',
      minLength: 5,
      maxLength: 500);
  static const title = InputRule('Title', minLength: 3, maxLength: 120);
  static const description =
      InputRule('Description', optional: true, minLength: 0, maxLength: 3000);
  static const brandMaker =
      InputRule('Brand / maker', optional: true, minLength: 0, maxLength: 100);
  static const productModel = InputRule('Product / model',
      optional: true, minLength: 0, maxLength: 120);
  static const itemAgeYears = InputRule('Item age (years)',
      kind: InputKind.decimal, maxLength: 30, max: 100);
  static const typicalRentalDays = InputRule('Typical rental days',
      kind: InputKind.integer, maxLength: 30, min: 1, max: 365);
  static const priceRm = InputRule('Price (RM)',
      kind: InputKind.money, maxLength: 30, min: 1, max: 1000000);
  static const location2 = InputRule('Location', minLength: 2, maxLength: 160);
  static const durationMinutes = InputRule('Duration (minutes)',
      kind: InputKind.integer, maxLength: 30, min: 15, max: 10080);
  static const securityDepositRm = InputRule('Security deposit (RM)',
      kind: InputKind.money, maxLength: 30, max: 1000000);
  static const reasonOptional = InputRule('Reason (optional)',
      optional: true, minLength: 0, maxLength: 120);
  static const minimumNoticeHours = InputRule('Minimum notice (hours)',
      kind: InputKind.integer, maxLength: 30, max: 8760);
  static const bufferHours = InputRule('Buffer (hours)',
      kind: InputKind.integer, maxLength: 30, max: 168);
  static const promotionLabel =
      InputRule('Promotion label', minLength: 2, maxLength: 80);
  static const discountPercentage = InputRule('Discount percentage',
      kind: InputKind.decimal, maxLength: 30, min: 5, max: 80);
  static const bundleTitle =
      InputRule('Bundle title', minLength: 3, maxLength: 100);
  static const bundleDiscount = InputRule('Bundle discount (%)',
      kind: InputKind.decimal, maxLength: 30, min: 5, max: 50);
  static const reason = InputRule('Reason', minLength: 3, maxLength: 500);
  static const referralCode =
      InputRule('Referral code', kind: InputKind.referral, maxLength: 23);
  static const packageDetails = InputRule('Package details',
      optional: true, minLength: 0, maxLength: 3000);
  static const duration = InputRule('Duration',
      kind: InputKind.integer,
      optional: true,
      maxLength: 30,
      min: 15,
      max: 10080);
  static const securityDepositRm2 = InputRule('Security deposit (RM)',
      kind: InputKind.money, optional: true, maxLength: 30, max: 1000000);
  static const dailyPriceRm = InputRule('Daily price (RM)',
      kind: InputKind.money,
      optional: true,
      maxLength: 30,
      min: 1,
      max: 1000000);
  static const reasonRequired =
      InputRule('Reason required', minLength: 5, maxLength: 500);
  static const describeTheIssue =
      InputRule('Describe the issue', minLength: 15, maxLength: 3000);
  static const claimAmountRm = InputRule('Claim amount (RM)',
      kind: InputKind.money, maxLength: 30, min: 0.01);
  static const incidentDetails =
      InputRule('Incident details', minLength: 20, maxLength: 3000);
  static const ownerResponse = InputRule('Owner response', minLength: 5);
  static const bundleName =
      InputRule('Bundle name', minLength: 3, maxLength: 100);
  static const venueOrServiceLocation =
      InputRule('Venue or service location', minLength: 2, maxLength: 240);
  static const eventRequirements =
      InputRule('Event requirements', minLength: 10, maxLength: 1000);
  static const brieflyExplainWhatYouWillUseTheItemFor = InputRule(
      'Briefly explain what you will use the item for.',
      optional: true,
      minLength: 0,
      maxLength: 1000);
  static const pickupDeliveryLocation =
      InputRule('Pickup/delivery location', maxLength: 240);
  static const amountRequestedRm = InputRule('Amount requested (RM)',
      kind: InputKind.money, maxLength: 30, min: 0.01);
  static const damageAndRepairDetails =
      InputRule('Damage and repair details', minLength: 20, maxLength: 3000);
  static const shortSummary =
      InputRule('Short summary', minLength: 5, maxLength: 160);
  static const whatHappened =
      InputRule('What happened?', minLength: 20, maxLength: 3000);
  static const addInformationOrAResponse =
      InputRule('Add information or a response', minLength: 5, maxLength: 2000);
  static const searchTitle =
      InputRule('Search \$title', optional: true, minLength: 0, maxLength: 100);
  static const requiredReasonAuditNote =
      InputRule('Required reason / audit note', minLength: 5, maxLength: 500);
  static const prototypePlatformFee = InputRule('Prototype platform fee (%)',
      kind: InputKind.decimal, maxLength: 30, max: 20);
  static const successfulReferralPoints = InputRule(
      'Successful referral points',
      kind: InputKind.integer,
      maxLength: 30,
      max: 10000);
  static const currentPassword = InputRule('Current password',
      kind: InputKind.password, minLength: 8, maxLength: 128);
  static const reviewedLicenceClassesEGDB2 = InputRule(
      'Reviewed licence classes (e.g. D, B2)',
      kind: InputKind.licenceClasses,
      maxLength: 80);
  static const validUntilYyyyMmDd = InputRule('Valid until (YYYY-MM-DD)',
      kind: InputKind.date, maxLength: 10);
  static const requiredReason =
      InputRule('Required reason', minLength: 5, maxLength: 500);
  static const rejectionReason =
      InputRule('Rejection reason', minLength: 5, maxLength: 500);
  static const amountRm =
      InputRule('Amount (RM)', kind: InputKind.money, maxLength: 30, min: 0.01);
  static const requiredNote = InputRule('Required note', minLength: 5);
  static const renterAmountRm =
      InputRule('Renter amount (RM)', kind: InputKind.money, maxLength: 30);
  static const ownerAmountRm =
      InputRule('Owner amount (RM)', kind: InputKind.money, maxLength: 30);
  static const decisionNotes = InputRule('Decision notes', minLength: 10);
  static const approvedAmountRm =
      InputRule('Approved amount (RM)', kind: InputKind.money, maxLength: 30);
  static const decisionReason =
      InputRule('Decision reason', minLength: 5, maxLength: 1000);
  static const name = InputRule('Name', minLength: 3, maxLength: 120);
  static const requiredResolutionNote =
      InputRule('Required resolution note', minLength: 3, maxLength: 1000);
  static const moderationReason =
      InputRule('Moderation reason', minLength: 5, maxLength: 500);
  static const supportEmail =
      InputRule('Support email', kind: InputKind.email, maxLength: 254);
  static const rewardOptionsPointsRm = InputRule('Reward options (points:RM)',
      kind: InputKind.rewards, maxLength: 300);
  static const searchProfessionalServices = InputRule(
      'Search professional services',
      optional: true,
      minLength: 0,
      maxLength: 100);
  static const emailAddress =
      InputRule('Email Address', kind: InputKind.email, maxLength: 254);
  static const sixDigitCode = InputRule('Six-digit code',
      kind: InputKind.digits, maxLength: 6, exactLength: 6);
  static const newPassword = InputRule('New Password',
      kind: InputKind.password, minLength: 8, maxLength: 128);
  static const confirmPassword = InputRule('Confirm Password',
      kind: InputKind.password, minLength: 8, maxLength: 128);
  static const email =
      InputRule('Email', kind: InputKind.email, maxLength: 254);
  static const password = InputRule('Password',
      kind: InputKind.password, minLength: 8, maxLength: 128);
  static const fullName = InputRule('Full Name', minLength: 2, maxLength: 80);
  static const mobileNumber =
      InputRule('Mobile Number', kind: InputKind.phone, maxLength: 24);
  static const fullName2 = InputRule('Full name', minLength: 2, maxLength: 80);
  static const emailAddress2 =
      InputRule('Email address', kind: InputKind.email, maxLength: 254);
  static const primaryAddress = InputRule('Primary address',
      optional: true, minLength: 0, maxLength: 240);
  static const howCanWeHelp =
      InputRule('How can we help?', minLength: 10, maxLength: 3000);
  static const malaysianAddress =
      InputRule('Malaysian address', minLength: 10, maxLength: 240);
  static const lastFourDigits = InputRule('Last four digits',
      kind: InputKind.digits, maxLength: 4, exactLength: 4);
}
