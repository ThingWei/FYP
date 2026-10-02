enum UserRole { renter, owner, admin }

UserRole? _userRoleFromJson(dynamic value) {
  if (value is! String) return null;
  for (final role in UserRole.values) {
    if (role.name == value) return role;
  }
  return null;
}

class UserAddress {
  const UserAddress({
    required this.label,
    required this.line1,
    required this.city,
    required this.state,
    required this.postcode,
    this.line2 = '',
    this.isDefault = false,
  });

  final String label, line1, line2, city, state, postcode;
  final bool isDefault;

  factory UserAddress.fromJson(Map<String, dynamic> json) => UserAddress(
        label: json['label'] as String,
        line1: json['line1'] as String,
        line2: json['line2'] as String? ?? '',
        city: json['city'] as String,
        state: json['state'] as String,
        postcode: json['postcode'] as String,
        isDefault: json['isDefault'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'label': label,
        'line1': line1,
        if (line2.isNotEmpty) 'line2': line2,
        'city': city,
        'state': state,
        'postcode': postcode,
        'isDefault': isDefault,
      };

  UserAddress copyWith({bool? isDefault}) => UserAddress(
        label: label,
        line1: line1,
        line2: line2,
        city: city,
        state: state,
        postcode: postcode,
        isDefault: isDefault ?? this.isDefault,
      );
}

class User {
  const User({
    required this.id,
    required this.email,
    required this.name,
    required this.roles,
    this.activeRole,
    this.trustScore = 0,
    this.phone = '',
    this.verificationStatus = 'unverified',
    this.verificationTier = 'none',
    this.verificationReason = '',
    this.addresses = const [],
    this.language = 'en',
    this.pushNotifications = true,
    this.emailNotifications = true,
  });
  final String id, email, name, phone;
  final String verificationStatus, verificationTier, verificationReason;
  final Set<UserRole> roles;
  final UserRole? activeRole;
  final double trustScore;
  final List<UserAddress> addresses;
  final String language;
  final bool pushNotifications, emailNotifications;

  factory User.fromJson(Map<String, dynamic> json) {
    final verification =
        json['verification'] as Map<String, dynamic>? ?? const {};
    final settings = json['settings'] as Map<String, dynamic>? ?? const {};
    return User(
      id: (json['authId'] ?? json['id'] ?? json['_id']) as String,
      email: json['email'] as String? ?? '',
      name: json['displayName'] as String? ?? json['name'] as String,
      roles: ((json['roles'] as List?) ?? const ['renter'])
          .map((role) => UserRole.values.byName(role as String))
          .toSet(),
      activeRole: _userRoleFromJson(json['activeRole']),
      trustScore: (json['trustScore'] as num?)?.toDouble() ?? 0,
      phone: json['phone'] as String? ?? '',
      verificationStatus: verification['status'] as String? ?? 'unverified',
      verificationTier: verification['tier'] as String? ?? 'none',
      verificationReason: verification['reason'] as String? ?? '',
      addresses: ((json['addresses'] as List?) ?? const [])
          .map(
            (address) => UserAddress.fromJson(address as Map<String, dynamic>),
          )
          .toList(),
      language: settings['language'] as String? ?? 'en',
      pushNotifications: settings['pushNotifications'] as bool? ?? true,
      emailNotifications: settings['emailNotifications'] as bool? ?? true,
    );
  }
}

class Listing {
  const Listing({
    required this.id,
    required this.title,
    required this.category,
    required this.dailyPrice,
    this.condition = 'Good',
    this.ownerName = 'RentHub Owner',
    this.ownerTrustScore = 50,
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
    this.promotionActive = false,
    this.promotionLabel = '',
    this.promotionDiscountPercent = 0,
    this.promotionalPrice,
    this.promotionStartsAt,
    this.promotionEndsAt,
    this.bundleTitle = '',
    this.bundleListingIds = const [],
    this.bundleDiscountPercent = 0,
    this.bundleActive = false,
    this.images = const [],
    this.recommendationReason = '',
    this.recommendationScore,
    this.itemVerificationOutcome = '',
    this.itemVerificationReasons = const [],
  });
  final String id, title, category, condition, ownerName, location;
  final String description, status, ownerId, priceUnit;
  final double dailyPrice, rating, ownerTrustScore;
  final double securityDeposit, damageWaiverFee;
  final bool verified, isService;
  final bool damageWaiverAvailable;
  final List<String> fulfilmentMethods;
  final int? serviceDurationMinutes;
  final bool promotionActive, bundleActive;
  final String promotionLabel, bundleTitle;
  final double promotionDiscountPercent, bundleDiscountPercent;
  final double? promotionalPrice;
  final DateTime? promotionStartsAt, promotionEndsAt;
  final List<String> bundleListingIds;
  final List<String> images;
  final String recommendationReason, itemVerificationOutcome;
  final double? recommendationScore;
  final List<String> itemVerificationReasons;

  double get displayPrice => promotionalPrice ?? dailyPrice;

  factory Listing.fromJson(Map<String, dynamic> j) {
    final promotion = j['promotion'] as Map<String, dynamic>?;
    final bundle = j['bundleOffer'] as Map<String, dynamic>?;
    final promotionActive = j['promotionActive'] as bool? ?? false;
    final recommendation =
        j['recommendation'] as Map<String, dynamic>? ?? const {};
    final verification =
        j['itemVerification'] as Map<String, dynamic>? ?? const {};
    return Listing(
      id: j['publicId'] ?? j['id'] ?? j['_id'],
      title: j['title'],
      category: j['category'],
      dailyPrice: (j['dailyPrice'] as num).toDouble(),
      condition: j['condition'] ?? 'Good',
      ownerName: j['ownerName'] ?? 'RentHub Owner',
      ownerTrustScore: (j['ownerTrustScore'] as num?)?.toDouble() ?? 50,
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
      promotionActive: promotionActive,
      promotionLabel: promotion?['label'] as String? ?? '',
      promotionDiscountPercent:
          (promotion?['discountPercent'] as num?)?.toDouble() ?? 0,
      promotionalPrice: promotionActive
          ? (j['effectiveDailyPrice'] as num?)?.toDouble()
          : null,
      promotionStartsAt: promotion?['startsAt'] == null
          ? null
          : DateTime.parse(promotion!['startsAt'] as String),
      promotionEndsAt: promotion?['endsAt'] == null
          ? null
          : DateTime.parse(promotion!['endsAt'] as String),
      bundleTitle: bundle?['title'] as String? ?? '',
      bundleListingIds: ((bundle?['listingIds'] as List?) ?? const [])
          .map((item) => item as String)
          .toList(),
      bundleDiscountPercent:
          (bundle?['discountPercent'] as num?)?.toDouble() ?? 0,
      bundleActive: bundle?['active'] as bool? ?? false,
      images: ((j['images'] as List?) ?? const [])
          .map((item) => item as String)
          .toList(),
      recommendationReason: recommendation['reason'] as String? ?? '',
      recommendationScore: (recommendation['score'] as num?)?.toDouble(),
      itemVerificationOutcome: verification['outcome'] as String? ?? '',
      itemVerificationReasons:
          (verification['reasons'] as List? ?? const []).cast<String>(),
    );
  }
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
    this.agreementVersion = '',
    this.agreementAcceptedAt,
  });
  final String id, listingId, status;
  final String listingTitle, listingType, renterName, ownerId, paymentStatus;
  final String? fulfilmentMethod, serviceVenue;
  final String agreementVersion;
  final DateTime? agreementAcceptedAt;
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
        agreementVersion: (json['agreement']
                as Map<String, dynamic>?)?['version'] as String? ??
            '',
        agreementAcceptedAt:
            (json['agreement'] as Map<String, dynamic>?)?['acceptedAt'] == null
                ? null
                : DateTime.parse(
                    (json['agreement'] as Map<String, dynamic>)['acceptedAt']
                        as String,
                  ),
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
        agreementVersion: agreementVersion,
        agreementAcceptedAt: agreementAcceptedAt,
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
    this.blockchainStatus = 'unavailable',
    this.contractAddress = '',
    this.blockchainTransactionHash = '',
    this.blockchainDeploymentHash = '',
    this.blockchainState = '',
    this.blockchainNetwork = '',
    this.blockchainSignatureHashes = const [],
    this.blockchainError = '',
  });
  final String id, status, bookingId, listingId, listingType, renterId, ownerId;
  final DateTime? start, end;
  final String extensionStatus;
  final String blockchainStatus, contractAddress, blockchainTransactionHash;
  final String blockchainDeploymentHash, blockchainState, blockchainNetwork;
  final List<String> blockchainSignatureHashes;
  final String blockchainError;

  factory Rental.fromJson(Map<String, dynamic> json) {
    final blockchain = json['blockchain'] as Map<String, dynamic>? ?? const {};
    return Rental(
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
      extensionStatus:
          (json['extension'] as Map<String, dynamic>?)?['status'] as String? ??
              'none',
      blockchainStatus: blockchain['status'] as String? ?? 'unavailable',
      contractAddress: blockchain['contractAddress'] as String? ??
          json['contractAddress'] as String? ??
          '',
      blockchainTransactionHash: blockchain['lastTransactionHash'] as String? ??
          json['transactionHash'] as String? ??
          '',
      blockchainDeploymentHash:
          blockchain['deploymentTransactionHash'] as String? ?? '',
      blockchainState: blockchain['contractState'] as String? ?? '',
      blockchainNetwork: blockchain['network'] as String? ?? '',
      blockchainSignatureHashes:
          (blockchain['signatureTransactionHashes'] as List? ?? const [])
              .cast<String>(),
      blockchainError: blockchain['error'] as String? ?? '',
    );
  }
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

class MessageAttachment {
  const MessageAttachment({
    required this.kind,
    required this.url,
    required this.contentType,
    required this.filename,
    required this.size,
  });

  final String kind, url, contentType, filename;
  final int size;

  factory MessageAttachment.fromJson(Map<String, dynamic> json) =>
      MessageAttachment(
        kind: json['kind'] as String,
        url: json['contentUrl'] as String,
        contentType: json['contentType'] as String,
        filename: json['filename'] as String,
        size: (json['size'] as num).toInt(),
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
    this.attachment,
  });
  final String id, threadId, text, senderId, recipientId;
  final DateTime? readAt, createdAt;
  final MessageAttachment? attachment;

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
        attachment: json['attachment'] == null
            ? null
            : MessageAttachment.fromJson(
                Map<String, dynamic>.from(json['attachment'] as Map),
              ),
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
  const Dispute(
    this.id,
    this.status,
    this.reason, {
    this.rentalId = '',
    this.bookingId = '',
    this.listingId = '',
    this.listingTitle = '',
    this.listingType = 'physical',
    this.category = 'other',
    this.description = '',
    this.evidence = const [],
    this.raisedByName = '',
    this.respondentName = '',
    this.responses = const [],
    this.adminNote = '',
    this.outcome,
    this.renterAmount = 0,
    this.ownerAmount = 0,
    this.blockchainReference,
    this.blockchainStatus = 'unavailable',
  });

  final String id, status, reason, rentalId, bookingId, listingId;
  final String listingTitle, listingType, category, description;
  final List<String> evidence;
  final String raisedByName, respondentName, adminNote;
  final List<DisputeResponse> responses;
  final String? outcome, blockchainReference;
  final String blockchainStatus;
  final double renterAmount, ownerAmount;

  bool get closed => status == 'resolved' || status == 'dismissed';

  factory Dispute.fromJson(Map<String, dynamic> json) {
    final resolution = json['resolution'] as Map<String, dynamic>? ?? const {};
    return Dispute(
      (json['publicId'] ?? json['id'] ?? json['_id']) as String,
      json['status'] as String,
      json['summary'] as String? ?? json['reason'] as String? ?? '',
      rentalId: json['rentalId'] as String? ?? '',
      bookingId: json['bookingId'] as String? ?? '',
      listingId: json['listingId'] as String? ?? '',
      listingTitle: json['listingTitle'] as String? ?? '',
      listingType: json['listingType'] as String? ?? 'physical',
      category: json['category'] as String? ?? 'other',
      description: json['description'] as String? ?? '',
      evidence: (json['evidence'] as List? ?? const []).cast<String>(),
      raisedByName: json['raisedByName'] as String? ?? '',
      respondentName: json['respondentName'] as String? ?? '',
      responses: (json['responses'] as List? ?? const [])
          .map((item) => DisputeResponse.fromJson(item as Map<String, dynamic>))
          .toList(),
      adminNote: json['adminNote'] as String? ?? '',
      outcome: resolution['outcome'] as String?,
      renterAmount: (resolution['renterAmount'] as num?)?.toDouble() ?? 0,
      ownerAmount: (resolution['ownerAmount'] as num?)?.toDouble() ?? 0,
      blockchainReference: resolution['blockchainReference'] as String?,
      blockchainStatus:
          resolution['blockchainStatus'] as String? ?? 'unavailable',
    );
  }
}

class DisputeResponse {
  const DisputeResponse({
    required this.userId,
    required this.role,
    required this.text,
    required this.evidence,
    this.submittedAt,
  });

  final String userId, role, text;
  final List<String> evidence;
  final DateTime? submittedAt;

  factory DisputeResponse.fromJson(Map<String, dynamic> json) =>
      DisputeResponse(
        userId: json['userId'] as String? ?? '',
        role: json['role'] as String? ?? '',
        text: json['text'] as String? ?? '',
        evidence: (json['evidence'] as List? ?? const []).cast<String>(),
        submittedAt: json['submittedAt'] == null
            ? null
            : DateTime.parse(json['submittedAt'] as String),
      );
}

class InsuranceClaim {
  const InsuranceClaim({
    required this.id,
    required this.disputeId,
    required this.rentalId,
    required this.listingTitle,
    required this.description,
    required this.amountRequested,
    required this.status,
    this.approvedAmount = 0,
    this.decisionReason = '',
  });

  final String id, disputeId, rentalId, listingTitle, description, status;
  final double amountRequested, approvedAmount;
  final String decisionReason;

  factory InsuranceClaim.fromJson(Map<String, dynamic> json) {
    final decision = json['decision'] as Map<String, dynamic>? ?? const {};
    return InsuranceClaim(
      id: (json['publicId'] ?? json['id'] ?? json['_id']) as String,
      disputeId: json['disputeId'] as String,
      rentalId: json['rentalId'] as String,
      listingTitle: json['listingTitle'] as String? ?? '',
      description: json['description'] as String? ?? '',
      amountRequested: (json['amountRequested'] as num).toDouble(),
      status: json['status'] as String,
      approvedAmount: (decision['approvedAmount'] as num?)?.toDouble() ?? 0,
      decisionReason: decision['reason'] as String? ?? '',
    );
  }
}

class Reward {
  const Reward(
    this.points,
    this.referralCode, {
    this.totalEarned = 0,
    this.totalRedeemed = 0,
    this.ledger = const [],
    this.redemptionOptions = const [],
    this.referral,
    this.rules = const LoyaltyRules(),
    this.canApplyReferral = false,
  });
  final int points;
  final String referralCode;
  final int totalEarned, totalRedeemed;
  final List<RewardLedgerEntry> ledger;
  final List<RedemptionOption> redemptionOptions;
  final ReferralStatus? referral;
  final LoyaltyRules rules;
  final bool canApplyReferral;

  factory Reward.fromJson(Map<String, dynamic> json) => Reward(
        (json['points'] as num?)?.toInt() ?? 0,
        json['referralCode'] as String? ?? '',
        totalEarned: (json['totalEarned'] as num?)?.toInt() ?? 0,
        totalRedeemed: (json['totalRedeemed'] as num?)?.toInt() ?? 0,
        ledger: (json['ledger'] as List? ?? const [])
            .map((item) =>
                RewardLedgerEntry.fromJson(item as Map<String, dynamic>))
            .toList(),
        redemptionOptions: (json['redemptionOptions'] as List? ?? const [])
            .map((item) =>
                RedemptionOption.fromJson(item as Map<String, dynamic>))
            .toList(),
        referral: json['referral'] == null
            ? null
            : ReferralStatus.fromJson(
                json['referral'] as Map<String, dynamic>,
              ),
        rules: LoyaltyRules.fromJson(
          json['rules'] as Map<String, dynamic>? ?? const {},
        ),
        canApplyReferral: json['canApplyReferral'] as bool? ?? false,
      );
}

class RewardLedgerEntry {
  const RewardLedgerEntry({
    required this.id,
    required this.type,
    required this.points,
    required this.balanceAfter,
    required this.description,
    this.rewardCode,
    this.discountAmount,
    this.createdAt,
  });

  final String id, type, description;
  final int points, balanceAfter;
  final String? rewardCode;
  final double? discountAmount;
  final DateTime? createdAt;

  factory RewardLedgerEntry.fromJson(Map<String, dynamic> json) {
    final reward = json['reward'] as Map<String, dynamic>? ?? const {};
    return RewardLedgerEntry(
      id: (json['publicId'] ?? json['id'] ?? json['_id']) as String,
      type: json['type'] as String,
      points: (json['points'] as num).toInt(),
      balanceAfter: (json['balanceAfter'] as num).toInt(),
      description: json['description'] as String,
      rewardCode: reward['code'] as String?,
      discountAmount: (reward['discountAmount'] as num?)?.toDouble(),
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.parse(json['createdAt'] as String),
    );
  }
}

class RedemptionOption {
  const RedemptionOption({
    required this.points,
    required this.discountAmount,
  });

  final int points;
  final double discountAmount;

  factory RedemptionOption.fromJson(Map<String, dynamic> json) =>
      RedemptionOption(
        points: (json['points'] as num).toInt(),
        discountAmount: (json['discountAmount'] as num).toDouble(),
      );
}

class ReferralStatus {
  const ReferralStatus({
    required this.id,
    required this.code,
    required this.status,
    this.rewardAmount = 0,
  });

  final String id, code, status;
  final double rewardAmount;

  factory ReferralStatus.fromJson(Map<String, dynamic> json) => ReferralStatus(
        id: (json['publicId'] ?? json['id'] ?? json['_id']) as String,
        code: json['referralCode'] as String,
        status: json['status'] as String,
        rewardAmount: (json['refereeRewardAmount'] as num?)?.toDouble() ?? 0,
      );
}

class LoyaltyRules {
  const LoyaltyRules({
    this.enabled = true,
    this.physicalCompletionPoints = 120,
    this.serviceCompletionPoints = 100,
    this.referralRewardPoints = 250,
    this.refereeDiscountAmount = 5,
  });

  final bool enabled;
  final int physicalCompletionPoints, serviceCompletionPoints;
  final int referralRewardPoints;
  final double refereeDiscountAmount;

  factory LoyaltyRules.fromJson(Map<String, dynamic> json) => LoyaltyRules(
        enabled: json['enabled'] as bool? ?? true,
        physicalCompletionPoints:
            (json['physicalCompletionPoints'] as num?)?.toInt() ?? 120,
        serviceCompletionPoints:
            (json['serviceCompletionPoints'] as num?)?.toInt() ?? 100,
        referralRewardPoints:
            (json['referralRewardPoints'] as num?)?.toInt() ?? 250,
        refereeDiscountAmount:
            (json['refereeDiscountAmount'] as num?)?.toDouble() ?? 5,
      );
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
