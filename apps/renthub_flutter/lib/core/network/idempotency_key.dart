import 'dart:math';

String newCheckoutIdempotencyKey() {
  final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
  final random =
      Random.secure().nextInt(0x100000000).toRadixString(16).padLeft(8, '0');
  return 'checkout:$timestamp:$random';
}
