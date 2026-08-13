import 'package:flutter/material.dart';

class PaymentStatus extends StatelessWidget {
  const PaymentStatus(this.value, {super.key});
  final String value;
  @override
  Widget build(BuildContext context) => Chip(label: Text(value));
}
