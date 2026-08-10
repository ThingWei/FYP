enum UserRole { renter, owner, admin }
class User { const User({required this.id, required this.email, required this.name, required this.roles, this.trustScore=0}); final String id,email,name; final Set<UserRole> roles; final double trustScore; }
class Listing { const Listing({required this.id, required this.title, required this.category, required this.dailyPrice, this.condition='Good'}); final String id,title,category,condition; final double dailyPrice; factory Listing.fromJson(Map<String,dynamic> j)=>Listing(id:j['_id']??j['id'],title:j['title'],category:j['category'],dailyPrice:(j['dailyPrice'] as num).toDouble(),condition:j['condition']??'Good'); }
class Booking { const Booking({required this.id, required this.listingId, required this.start, required this.end, required this.status}); final String id,listingId,status; final DateTime start,end; }
class Rental { const Rental(this.id,this.status); final String id,status; }
class Transaction { const Transaction(this.id,this.amount,this.status); final String id,status; final double amount; }
class Message { const Message(this.id,this.threadId,this.text,this.senderId); final String id,threadId,text,senderId; }
class Review { const Review(this.id,this.rating,this.text); final String id,text; final int rating; }
class Dispute { const Dispute(this.id,this.status,this.reason); final String id,status,reason; }
class Reward { const Reward(this.points,this.referralCode); final int points; final String referralCode; }
class VerificationResult { const VerificationResult(this.accepted,this.confidence); final bool accepted; final double confidence; }
class SmartContractRecord { const SmartContractRecord(this.address,this.transactionHash); final String? address,transactionHash; }

