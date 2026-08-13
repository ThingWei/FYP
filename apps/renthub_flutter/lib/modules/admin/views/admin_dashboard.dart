import 'package:flutter/material.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});
  @override
  Widget build(BuildContext context) => GridView.count(
        padding: const EdgeInsets.all(24),
        crossAxisCount: MediaQuery.sizeOf(context).width > 900 ? 4 : 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        children: const [
          _Stat('Active listings', '1,248'),
          _Stat('Active rentals', '316'),
          _Stat('Open disputes', '12'),
          _Stat('Verified users', '4,892'),
        ],
      );
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label),
              const Spacer(),
              Text(value, style: Theme.of(context).textTheme.headlineMedium),
            ],
          ),
        ),
      );
}
