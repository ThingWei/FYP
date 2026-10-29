export function trustFacts(count = 3, simulated = false) {
  return {
    bookings: Array.from({length:count},(_,i)=>({publicId:`B${i}`,ownerId:'owner',renterId:`renter${i%2}`,listingId:'listing',listingType:'physical',sourceType:'marketplace',status:'completed',completedAt:'2026-10-21T08:00:00Z',pricing:{baseAmount:80}})),
    rentals: Array.from({length:count},(_,i)=>({publicId:`R${i}`,bookingId:`B${i}`,listingId:'listing',listingType:'physical',ownerId:'owner',renterId:`renter${i%2}`,status:'completed',startDate:'2026-10-19T00:00:00Z',endDate:'2026-10-20T00:00:00Z',handover:{recordedAt:'2026-10-19T04:00:00Z'},returnSubmission:{recordedAt:'2026-10-20T08:00:00Z'}})),
    payments: Array.from({length:count},(_,i)=>({publicId:`P${i}`,bookingId:`B${i}`,type:'capture',status:'succeeded',amount:80,currency:'MYR',simulated,gatewayReference:simulated?`sim_${i}`:`gateway_${i}`,createdAt:'2026-10-19T04:00:00Z'})),
    reviews: Array.from({length:count},(_,i)=>({rentalId:`R${i}`,bookingId:`B${i}`,authorId:`renter${i%2}`,authorRole:'renter',subjectId:'owner',subjectRole:'owner',status:'published',overallRating:5,createdAt:'2026-10-21T08:00:00Z'})),
    disputes:[],listings:[{publicId:'listing',sourceType:'marketplace'}],
  };
}
