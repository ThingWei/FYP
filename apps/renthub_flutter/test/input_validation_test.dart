import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renthub_flutter/core/validation/input_rules.dart';
import 'package:renthub_flutter/core/validation/input_validation.dart';

TextEditingValue value(String text, {int? cursor}) => TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: cursor ?? text.length));

void main() {
  test('rejects a complete mixed paste, exponent, signs and decimal integers',
      () {
    final formatter = InputRules.typicalRentalDays.formatters.single;
    final old = value('12', cursor: 1);
    for (final text in ['abc123', '1e2', '12.5', '-1', '+1', '12 3']) {
      expect(formatter.formatEditUpdate(old, value(text)), old);
    }
    expect(formatter.formatEditUpdate(old, value('123', cursor: 2)),
        value('123', cursor: 2));
    expect(formatter.formatEditUpdate(value('123'), value('')), value(''));
  });
  test('money permits unfinished edits and deletion but rejects overprecision',
      () {
    final formatter = InputRules.priceRm.formatters.single;
    for (final text in ['', '.', '12.', '12.3', '12.34']) {
      expect(formatter.formatEditUpdate(value(''), value(text)), value(text));
    }
    final old = value('12.34');
    for (final text in ['12.345', '12..34', 'abc123', '1e2']) {
      expect(formatter.formatEditUpdate(old, value(text)), old);
    }
    expect(InputRules.priceRm.validate('12.'), isNotNull);
    expect(InputRules.priceRm.validate('12.34'), isNull);
  });
  test('leading zeros, selection and active composition survive', () {
    final formatter = InputRules.sixDigitCode.formatters.single;
    final old = value('00123', cursor: 2);
    expect(formatter.formatEditUpdate(value(''), old), old);
    final composing = old.copyWith(
        text: '00123a', composing: const TextRange(start: 5, end: 6));
    expect(formatter.formatEditUpdate(old, composing), composing);
    expect(formatter.formatEditUpdate(composing, value('00123a')), old);
    expect(formatter.formatEditUpdate(old, value('001234')), value('001234'));
    expect(formatter.formatEditUpdate(value('001234'), value('0012345')),
        value('001234'));
  });
  test('controller-scoped formatters persist across rebuilds', () {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    expect(
        identical(InputValidation.formatters(InputRules.priceRm, controller),
            InputValidation.formatters(InputRules.priceRm, controller)),
        isTrue);
  });
  test('numeric boundaries, finite values and independent precision contracts',
      () {
    for (final text in ['abc123', '1e2', 'NaN', 'Infinity', '-1', '.', '']) {
      expect(InputRules.itemAgeYears.validate(text), isNotNull);
    }
    for (final text in ['0', '1.234', '100']) {
      expect(InputRules.itemAgeYears.validate(text), isNull);
    }
    expect(InputRules.itemAgeYears.validate('100.001'), isNotNull);
    expect(InputRules.typicalRentalDays.validate('1.0'), isNotNull);
    expect(InputRules.typicalRentalDays.validate('365'), isNull);
    expect(InputRules.typicalRentalDays.validate('366'), isNotNull);
    expect(InputRules.priceRm.validate('1000000.00'), isNull);
    expect(InputRules.priceRm.validate('1000000.01'), isNotNull);
    expect(InputRules.discountPercentage.validate('5.12345'), isNull);
  });
  test('emails, Malaysian mobile, passwords and Unicode text', () {
    for (final email in ['a+rent@example.my', 'thing.wei@example.com']) {
      expect(InputRules.email.validate(email), isNull);
    }
    for (final email in [
      'a@',
      'a..b@example.com',
      'a b@example.com',
      'a@example'
    ]) {
      expect(InputRules.email.validate(email), isNotNull);
    }
    for (final phone in ['012-345 6789', '+60 12-345 6789', '01112345678']) {
      expect(InputRules.mobileNumber.validate(phone), isNull);
    }
    for (final phone in ['+6512345678', '0312345678', '012abc3456789']) {
      expect(InputRules.mobileNumber.validate(phone), isNotNull);
    }
    expect(InputRules.phoneNumber.validate(''), isNull);
    expect(InputRules.mobileNumber.validate(''), isNotNull);
    expect(InputRules.password.validate('  secret  '), isNull);
    expect(InputRules.password.validate('1234567'), isNotNull);
    expect(InputRules.password.validate('x' * 129), isNotNull);
    final confirmation = InputValidation.compose(
        InputRules.confirmPassword.validate,
        (value) => value == '  secret  ' ? null : 'Passwords must match');
    expect(confirmation('  secret  '), isNull);
    expect(confirmation('secret  '), isNotNull);
    expect(InputRules.fullName.validate('陈 Thing-Wei bin Ahmad'), isNull);
    expect(InputRules.productModel.validate('α7 III / 2026 Edition'), isNull);
  });
  test('OTP, postcode, referral, licence classes, calendar and reward formats',
      () {
    expect(InputRules.sixDigitCode.validate('001234'), isNull);
    expect(InputRules.sixDigitCode.validate('12345'), isNotNull);
    const postcode = InputRule('Postcode',
        kind: InputKind.digits, maxLength: 5, exactLength: 5);
    expect(postcode.validate('01000'), isNull);
    expect(postcode.validate('10a00'), isNotNull);
    expect(InputRules.referralCode.validate('rh-member123'), isNull);
    expect(InputRules.referralCode.validate('12345'), isNotNull);
    expect(InputRules.reviewedLicenceClassesEGDB2.validate('D, B2'), isNull);
    expect(InputRules.reviewedLicenceClassesEGDB2.validate('D, D'), isNotNull);
    expect(InputRules.reviewedLicenceClassesEGDB2.validate('Z'), isNotNull);
    expect(InputRules.validUntilYyyyMmDd.validate('2028-02-29'), isNull);
    expect(InputRules.validUntilYyyyMmDd.validate('2026-02-30'), isNotNull);
    const time = InputRule('Time', kind: InputKind.time);
    expect(time.validate('23:59'), isNull);
    expect(time.validate('24:00'), isNotNull);
    expect(
        InputRules.rewardOptionsPointsRm.validate('500:5,1000:10.50'), isNull);
    for (final rewards in ['500:5,0500:10', '500:5.001', '0:5', '500:abc']) {
      expect(InputRules.rewardOptionsPointsRm.validate(rewards), isNotNull);
    }
  });
}
