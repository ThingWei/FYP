import 'package:flutter/material.dart';

class DisputeStatus extends StatelessWidget {
  const DisputeStatus(this.value, {super.key});
  final String value;
  @override
  Widget build(BuildContext context) => Chip(label: Text(value));
}
