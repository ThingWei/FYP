import 'package:flutter/material.dart';

class PointsBadge extends StatelessWidget {
  const PointsBadge(this.points, {super.key});
  final int points;
  @override
  Widget build(BuildContext context) => Chip(label: Text('$points points'));
}
