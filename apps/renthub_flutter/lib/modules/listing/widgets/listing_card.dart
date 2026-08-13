import 'package:flutter/material.dart';

class ListingCard extends StatelessWidget {
  const ListingCard({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(child: child);
}
