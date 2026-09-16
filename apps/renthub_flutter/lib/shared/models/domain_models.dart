enum UserRole { renter, owner, admin }

class User {
  const User({
    required this.id,
    required this.email,
    required this.name,
    required this.roles,
    this.trustScore = 0,
  });
  final String id, email, name;
  final Set<UserRole> roles;
  final double trustScore;

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: (json['authId'] ?? json['id'] ?? json['_id']) as String,
        email: json['email'] as String? ?? '',
        name: json['displayName'] as String? ?? json['name'] as String,
        roles: ((json['roles'] as List?) ?? const ['renter'])
            .map((role) => UserRole.values.byName(role as String))
            .toSet(),
        trustScore: (json['trustScore'] as num?)?.toDouble() ?? 0,
      );
}

class Listing {
  const Listing({
    required this.id,
    required this.title,
    required this.category,
    required this.dailyPrice,
    this.condition = 'Good',
    this.ownerName = 'RentHub Owner',
    this.location = 'Kuala Lumpur',
    this.verified = false,
    this.isService = false,
    this.rating = 4.5,
    this.description = '',
    this.status = 'active',
    this.ownerId = '',
    this.priceUnit = 'day',
    this.securityDeposit = 0,
    this.damageWaiverAvailable = false,
    this.damageWaiverFee = 0,
    this.fulfilmentMethods = const [],
    this.serviceDurationMinutes,
  });
  final String id, title, category, condition, ownerName, location;
  final String description, status, ownerId, priceUnit;
  final double dailyPrice, rating;
  final double securityDeposit, damageWaiverFee;
  final bool verified, isService;
  final bool damageWaiverAvailable;
  final List<String> fulfilmentMethods;
  final int? serviceDurationMinutes;
  factory Listing.fromJson(Map<String, dynamic> j) => Listing(
        id: j['publicId'] ?? j['id'] ?? j['_id'],
        title: j['title'],
        category: j['category'],
        dailyPrice: (j['dailyPrice'] as num).toDouble(),
        condition: j['condition'] ?? 'Good',
        ownerName: j['ownerName'] ?? 'RentHub Owner',
        location: j['location'] ?? 'Kuala Lumpur',
        verified: j['verified'] ?? false,
        isService: j['isService'] ?? false,
        rating: (j['rating'] as num?)?.toDouble() ?? 4.5,
        description: j['description'] as String? ?? '',
        status: j['status'] as String? ?? 'active',
        ownerId: j['ownerId'] as String? ?? '',
        priceUnit: j['priceUnit'] as String? ?? 'day',
        securityDeposit: (j['securityDeposit'] as num?)?.toDouble() ?? 0,
        damageWaiverAvailable: j['damageWaiverAvailable'] as bool? ?? false,
        damageWaiverFee: (j['damageWaiverFee'] as num?)?.toDouble() ?? 0,
        fulfilmentMethods: ((j['fulfilmentMethods'] as List?) ?? const [])
            .map((item) => item as String)
            .toList(),
        serviceDurationMinutes: (j['serviceDetails']
            as Map<String, dynamic>?)?['durationMinutes'] as int?,
      );
}

class Booking {
  const Booking({
    required this.id,
    required this.listingId,
    required this.start,
    required this.end,
    required this.status,
    this.listingTitle = '',
    this.listingType = 'physical',
    this.renterName = '',
    this.ownerId = '',
    this.paymentStatus = 'unpaid',
    this.total = 0,
    this.fulfilmentMethod,
    this.serviceVenue,
  });
  final String id, listingId, status;
  final String listingTitle, listingType, renterName, ownerId, paymentStatus;
  final String? fulfilmentMethod, serviceVenue;
  final double total;
  final DateTime start, end;

  factory Booking.fromJson(Map<String, dynamic> json) => Booking(
        id: (json['publicId'] ?? json['id'] ?? json['_id']) as String,
        listingId: json['listingId'] as String,
        start: DateTime.parse((json['startDate'] ?? json['start']) as String),
        end: DateTime.parse((json['endDate'] ?? json['end']) as String),
        status: json['status'] as String,
        listingTitle: json['listingTitle'] as String? ?? '',
        listingType: json['listingType'] as String? ?? 'physical',
        renterName: json['renterName'] as String? ?? '',
        ownerId: json['ownerId'] as String? ?? '',
        paymentStatus: json['paymentStatus'] as String? ?? 'unpaid',
        total: ((json['pricing'] as Map<String, dynamic>?)?['total'] as num?)
                ?.toDouble() ??
            (json['total'] as num?)?.toDouble() ??
            0,
        fulfilmentMethod: json['fulfilmentMethod'] as String?,
        serviceVenue: json['serviceVenue'] as String?,
      );

  Booking copyWith({String? status}) => Booking(
        id: id,
        listingId: listingId,
        start: start,
        end: end,
        status: status ?? this.status,
        listingTitle: listingTitle,
        listingType: listingType,
        renterName: renterName,
        ownerId: ownerId,
        paymentStatus: paymentStatus,
        total: total,
        fulfilmentMethod: fulfilmentMethod,
        serviceVenue: serviceVenue,
      );
}

class Rental {
  const Rental(
    this.id,
    this.status, {
    this.bookingId = '',
    this.listingId = '',
    this.listingType = 'physical',
    this.renterId = '',
    this.ownerId = '',
    this.start,
    this.end,
    this.extensionStatus = 'none',
  });
  final String id, status, bookingId, listingId, listingType, renterId, ownerId;
  final DateTime? start, end;
  final String extensionStatus;

  factory Rental.fromJson(Map<String, dynamic> json) => Rental(
        (json['publicId'] ?? json['id'] ?? json['_id']) as String,
        json['status'] as String,
        bookingId: json['bookingId'] as String? ?? '',
        listingId: json['listingId'] as String? ?? '',
        listingType: json['listingType'] as String? ?? 'physical',
        renterId: json['renterId'] as String? ?? '',
        ownerId: json['ownerId'] as String? ?? '',
        start: json['startDate'] == null
            ? null
            : DateTime.parse(json['startDate'] as String),
        end: json['endDate'] == null
            ? null
            : DateTime.parse(json['endDate'] as String),
        extensionStatus: (json['extension'] as Map<String, dynamic>?)?['status']
                as String? ??
            'none',
      );
}

class Transaction {
  const Transaction(
    this.id,
    this.amount,
    this.status, {
    this.type = '',
    this.bookingId = '',
  });
  final String id, status, type, bookingId;
  final double amount;

  factory Transaction.fromJson(Map<String, dynamic> json) => Transaction(
        (json['publicId'] ?? json['id'] ?? json['_id']) as String,
        (json['amount'] as num).toDouble(),
        json['status'] as String,
        type: json['type'] as String? ?? '',
        bookingId: json['bookingId'] as String? ?? '',
      );
}

class Message {
  const Message(
    this.id,
    this.threadId,
    this.text,
    this.senderId, {
    this.recipientId = '',
    this.readAt,
    this.createdAt,
  });
  final String id, threadId, text, senderId, recipientId;
  final DateTime? readAt, createdAt;

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        (json['publicId'] ?? json['id'] ?? json['_id']) as String,
        json['threadId'] as String,
        json['text'] as String,
        json['senderId'] as String,
        recipientId: json['recipientId'] as String? ?? '',
        readAt: json['readAt'] == null
            ? null
            : DateTime.parse(json['readAt'] as String),
        createdAt: json['createdAt'] == null
            ? null
            : DateTime.parse(json['createdAt'] as String),
      );
}

class Conversation {
  const Conversation({
    required this.id,
    required this.bookingId,
    required this.listingTitle,
    required this.otherParticipantName,
    required this.unreadCount,
    required this.lastMessageText,
    this.lastMessageAt,
  });

  final String id, bookingId, listingTitle, otherParticipantName;
  final int unreadCount;
  final String lastMessageText;
  final DateTime? lastMessageAt;

  factory Conversation.fromJson(Map<String, dynamic> json) {
    final other = json['otherParticipant'] as Map<String, dynamic>? ?? const {};
    return Conversation(
      id: (json['publicId'] ?? json['id'] ?? json['_id']) as String,
      bookingId: json['bookingId'] as String,
      listingTitle: json['listingTitle'] as String,
      otherParticipantName: other['displayName'] as String? ?? 'RentHub user',
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
      lastMessageText: json['lastMessageText'] as String? ?? '',
      lastMessageAt: json['lastMessageAt'] == null
          ? null
          : DateTime.parse(json['lastMessageAt'] as String),
    );
  }
}

class RentHubNotification {
  const RentHubNotification({
    required this.id,
    required this.category,
    required this.title,
    required this.body,
    required this.entityId,
    required this.read,
    this.createdAt,
  });

  final String id, category, title, body, entityId;
  final bool read;
  final DateTime? createdAt;

  factory RentHubNotification.fromJson(Map<String, dynamic> json) =>
      RentHubNotification(
        id: (json['publicId'] ?? json['id'] ?? json['_id']) as String,
        category: json['category'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
        entityId: json['entityId'] as String,
        read: json['read'] as bool? ?? json['readAt'] != null,
        createdAt: json['createdAt'] == null
            ? null
            : DateTime.parse(json['createdAt'] as String),
      );
}

class Review {
  const Review(
    this.id,
    this.rating,
    this.text, {
    this.rentalId = '',
    this.listingId = '',
    this.listingTitle = '',
    this.authorId = '',
    this.authorName = '',
    this.subjectId = '',
    this.subjectName = '',
    this.status = 'published',
    this.canEdit = false,
    this.flagged = false,
    this.createdAt,
  });
  final String id, text, rentalId, listingId, listingTitle;
  final String authorId, authorName, subjectId, subjectName, status;
  final int rating;
  final bool canEdit, flagged;
  final DateTime? createdAt;

  factory Review.fromJson(Map<String, dynamic> json) => Review(
        (json['publicId'] ?? json['id'] ?? json['_id']) as String,
        (json['overallRating'] ?? json['rating'] as num).toInt(),
        json['text'] as String,
        rentalId: json['rentalId'] as String? ?? '',
        listingId: json['listingId'] as String? ?? '',
        listingTitle: json['listingTitle'] as String? ?? '',
        authorId: json['authorId'] as String? ?? '',
        authorName: json['authorName'] as String? ?? 'RentHub user',
        subjectId: json['subjectId'] as String? ?? '',
        subjectName: json['subjectName'] as String? ?? 'RentHub user',
        status: json['status'] as String? ?? 'published',
        canEdit: json['canEdit'] as bool? ?? false,
        flagged: (json['flag'] as Map<String, dynamic>?)?['flaggedAt'] != null,
        createdAt: json['createdAt'] == null
            ? null
            : DateTime.parse(json['createdAt'] as String),
      );
}

class Dispute {
  const Dispute(this.id, this.status, this.reason);
  final String id, status, reason;
}

class Reward {
  const Reward(this.points, this.referralCode);
  final int points;
  final String referralCode;
}

class VerificationResult {
  const VerificationResult(this.accepted, this.confidence);
  final bool accepted;
  final double confidence;
}

class SmartContractRecord {
  const SmartContractRecord(this.address, this.transactionHash);
  final String? address, transactionHash;
}
