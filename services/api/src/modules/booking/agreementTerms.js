import { createHash } from 'node:crypto';

const legacyDetails = [
  'The item, rental dates, collection method, and charges shown are correct.',
  'The renter will take reasonable care of the item, record its condition, and return it on time.',
  'The Owner may approve or reject the request. Payment follows RentHub cancellation and dispute rules.',
  'After approval, RentHub creates a protected record that supports the rental and any future dispute review.',
];
const common = [
  { title: 'Request, payment and approval', detail: 'Check the dates, arrangements and final charges before paying. Payment is simulated: no real money is taken. The request remains pending until the Owner approves it. A pending request does not reserve physical-item dates.' },
  { title: 'Changes and cancellation', detail: 'Use RentHub to request changes or cancel an eligible booking. Do not assume a change is agreed until it is confirmed. RentHub releases a simulated payment hold when an eligible pending or approved booking is cancelled or a pending request is rejected or expires.' },
  { title: 'Problems and disputes', detail: 'Contact the other participant through RentHub and keep relevant messages and evidence. Use the dispute process if the problem cannot be resolved. An administrator reviews the evidence; a booking or payment record is not a guarantee of a particular outcome.' },
];
const physical = [
  { title: 'Collection and condition', detail: 'Follow the agreed pickup or delivery arrangement. Check the item together where possible and record its condition at handover. Do not treat listing verification as a guarantee of authenticity or fitness for every purpose.' },
  { title: 'Care, return and extensions', detail: 'Take reasonable care of the item and return it by the agreed end date. Request an extension through RentHub rather than assuming extra days are available. Record the return condition and raise any disagreement through the platform.' },
  { title: 'Deposit and optional protection', detail: 'The deposit and any selected damage-waiver fee are shown separately. A deposit deduction must be recorded through RentHub and can be reviewed through its dispute process. Optional protection does not promise coverage for every loss; review the applicable details before selecting it.' },
  { title: 'Supporting rental record', detail: 'After Owner approval, RentHub can record rental amounts and status changes to support later review. The current demonstration network uses test funds. It does not store the full agreement text or personal documents and is not proof of legal certification.' },
];
const service = [
  { title: 'Service and venue', detail: 'Check the service, scheduled time and agreed venue or online arrangement. The Owner supplies the booked service; confirm any changes in RentHub before proceeding.' },
  { title: 'Delivery and completion', detail: 'Both participants should communicate promptly and keep evidence of the service delivered. Use RentHub to confirm completion or raise a problem. Physical-item return, security-deposit and item-condition duties do not apply to service bookings.' },
  { title: 'Booking record', detail: 'RentHub keeps the booking details and recorded acceptance for review. Service agreements do not use the extra physical-rental record. This demonstration payment does not transfer real money.' },
];
function terms(version, listingType, sections, hashText) {
  return Object.freeze({ version, listingType, title: listingType === 'service' ? 'Service booking agreement' : 'Rental agreement',
    sections: Object.freeze(sections.map(section => Object.freeze({ ...section }))),
    termsHash: createHash('sha256').update(hashText ?? JSON.stringify(sections)).digest('hex') });
}
const registry = new Map([
  ['renthub-booking-v1', terms('renthub-booking-v1', 'legacy', legacyDetails.map((detail, i) => ({ title: ['Booking details', 'Care and return', 'Approval and payment', 'RentHub protection'][i], detail })), legacyDetails.join('\n'))],
  ['renthub-rental-v2', terms('renthub-rental-v2', 'physical', [...common, ...physical])],
  ['renthub-service-v2', terms('renthub-service-v2', 'service', [...common, ...service])],
]);
export const agreementVersions = [...registry.keys()];
export const agreementTerms = (version) => registry.get(version);
export const currentAgreementTerms = (listingType) => registry.get(listingType === 'service' ? 'renthub-service-v2' : 'renthub-rental-v2');
