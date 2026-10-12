class BookingCharges {
  const BookingCharges(
      {required this.base,
      required this.deposit,
      required this.waiver,
      required this.platform,
      required this.total});
  final double base, deposit, waiver, platform, total;
  factory BookingCharges.fromJson(Map<String, dynamic> row) {
    double amount(String key) {
      final value = row[key];
      if (value is! num || !value.isFinite || value < 0) {
        throw const FormatException('Invalid booking charges');
      }
      return value.toDouble();
    }

    final result = BookingCharges(
        base: amount('baseAmount'),
        deposit: amount('securityDeposit'),
        waiver: amount('damageWaiverFee'),
        platform: amount('platformFee'),
        total: amount('total'));
    if (row['currency'] != 'MYR' ||
        (result.base +
                    result.deposit +
                    result.waiver +
                    result.platform -
                    result.total)
                .abs() >
            .011) {
      throw const FormatException('Invalid booking charges');
    }
    return result;
  }
}

class AgreementSection {
  const AgreementSection(this.title, this.detail);
  final String title, detail;
}

class AgreementTerms {
  const AgreementTerms(this.version, this.title, this.sections);
  final String version, title;
  final List<AgreementSection> sections;
  factory AgreementTerms.fromJson(Map<String, dynamic> row) {
    if (row['version'] is! String ||
        row['title'] is! String ||
        row['sections'] is! List ||
        (row['sections'] as List).isEmpty) {
      throw const FormatException('Invalid agreement terms');
    }
    return AgreementTerms(
        row['version'],
        row['title'],
        (row['sections'] as List).map((section) {
          if (section is! Map ||
              section['title'] is! String ||
              section['detail'] is! String) {
            throw const FormatException('Invalid agreement section');
          }
          return AgreementSection(section['title'], section['detail']);
        }).toList());
  }
}

class PaymentAttempt {
  const PaymentAttempt(this.id, this.status, this.amount,
      {this.key = '', this.method = 'card'});
  final String id, status;
  final double amount;
  final String key, method;
  bool get succeeded => status == 'authorized';
  factory PaymentAttempt.fromJson(Map<String, dynamic> row) {
    final id = row['publicId'] ?? row['id'];
    if (id is! String ||
        row['status'] is! String ||
        row['amount'] is! num ||
        !(row['amount'] as num).isFinite ||
        (row['amount'] as num) < 0 ||
        row['simulated'] != true) {
      throw const FormatException('Invalid demo payment');
    }
    if (!['pending', 'authorized', 'failed', 'voided']
        .contains(row['status'])) {
      throw const FormatException('Invalid payment state');
    }
    return PaymentAttempt(id, row['status'], (row['amount'] as num).toDouble(),
        key: row['idempotencyKey'] as String? ?? '',
        method: row['method'] as String? ?? 'card');
  }
}
