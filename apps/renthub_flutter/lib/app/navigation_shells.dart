import 'package:flutter/material.dart';
import '../shared/models/domain_models.dart';
import '../modules/listing/views/listing_screen.dart';
import '../modules/booking/views/booking_screen.dart';
import '../modules/admin/views/admin_dashboard.dart';

class RoleHome extends StatelessWidget {
  const RoleHome({super.key, required this.user});
  final User user;
  @override
  Widget build(BuildContext context) => user.roles.contains(UserRole.admin)
      ? const AdminShell()
      : const MobileShell();
}

class MobileShell extends StatefulWidget {
  const MobileShell({super.key});
  @override
  State<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<MobileShell> {
  int index = 0;
  final pages = const [
    ListingScreen(),
    BookingScreen(),
    Center(child: Text('Messages')),
    Center(child: Text('Profile')),
  ];
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('RentHub')),
        body: pages[index],
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (v) => setState(() => index = v),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.search), label: 'Explore'),
            NavigationDestination(
              icon: Icon(Icons.calendar_month),
              label: 'Bookings',
            ),
            NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline),
              label: 'Inbox',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              label: 'Profile',
            ),
          ],
        ),
      );
}

class AdminShell extends StatelessWidget {
  const AdminShell({super.key});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, size) {
          final destinations = const [
            NavigationRailDestination(
              icon: Icon(Icons.dashboard),
              label: Text('Dashboard'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.people),
              label: Text('Users'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.list),
              label: Text('Listings'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.flag),
              label: Text('Disputes'),
            ),
          ];
          if (size.maxWidth < 700) {
            return Scaffold(
              appBar: AppBar(title: const Text('RentHub Admin')),
              drawer: const Drawer(
                child: SafeArea(
                  child: Text('Dashboard\nUsers\nListings\nDisputes'),
                ),
              ),
              body: const AdminDashboard(),
            );
          }
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  extended: size.maxWidth > 1000,
                  selectedIndex: 0,
                  destinations: destinations,
                ),
                const VerticalDivider(width: 1),
                const Expanded(child: AdminDashboard()),
              ],
            ),
          );
        },
      );
}
