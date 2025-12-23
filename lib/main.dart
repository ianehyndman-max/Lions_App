import 'dart:async';
import 'package:flutter/material.dart';
import 'events_page.dart' as events;
import 'members_page.dart' as members;
import 'calendar_page.dart' as calendar;
import 'news_page.dart' as news;
import 'onboarding_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'manage_clubs_page.dart';
import 'auth_store.dart';
import 'package:lions_app_3/audit_log_page.dart'; 
import 'role_templates_page.dart';
import 'reports_page.dart';

const double _navBreakpoint = 800; // width threshold for switching nav style

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Print synchronous Flutter framework errors to console
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.dumpErrorToConsole(details);
    print('FLUTTER ERROR: ${details.exceptionAsString()}');
    if (details.stack != null) print(details.stack);
  };

  // Catch uncaught async errors and run app after async init
  runZonedGuarded(() async {
    final prefs = await SharedPreferences.getInstance();
    final hasProfile = prefs.containsKey('member_id');
    runApp(LionsApp(showOnboarding: !hasProfile));
  }, (error, stack) {
    print('ASYNC ERROR: $error');
    print(stack);
  });
}

class LionsApp extends StatelessWidget {
  final bool showOnboarding;
  const LionsApp({super.key, required this.showOnboarding});

  @override
  Widget build(BuildContext context) {
      return MaterialApp(
      title: 'Lions Club',
      theme: ThemeData(primarySwatch: Colors.red),
      home: showOnboarding ? OnboardingPage() : const MainScreen(),
    );
  }
}

// Move HomePage HERE, before MainScreen
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= _navBreakpoint;
    if (isWide) {
      // existing large-screen hero view unchanged
      return Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/fun_lion.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: Container(
          alignment: Alignment.center,
          color: Colors.black26,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Welcome to the Lions Club!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  shadows: [Shadow(blurRadius: 4, color: Colors.black, offset: Offset(0, 1))],
                ),
              ),
              const SizedBox(height: 40),
              FutureBuilder<bool>(
                future: AuthStore.isSuper(),
                builder: (context, snapshot) {
                  if (snapshot.data != true) return const SizedBox.shrink();
                  return Column(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => ManageClubsPage()),
                          );
                        },
                        icon: const Icon(Icons.admin_panel_settings),
                        label: const Text('Manage Clubs'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // NEW: Role Templates button (admin/super only)
                      FutureBuilder<bool>(
                        future: AuthStore.isAdmin(),
                        builder: (context, adminSnapshot) {
                          // Show if admin OR super
                          final canManageTemplates = adminSnapshot.data == true || snapshot.data == true;
                          if (!canManageTemplates) return const SizedBox.shrink();
                          
                          return Column(
                            children: [
                              ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => RoleTemplatesPage()),
                                  );
                                },
                                icon: const Icon(Icons.article_outlined),
                                label: const Text('Role Templates'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 16),
                              
                            ],
                          );
                        },
                      ),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => AuditLogPage()),
                          );
                        },
                        icon: const Icon(Icons.history),
                        label: const Text('Audit Log'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  );
                },
              ),
              FutureBuilder<bool>(
                future: AuthStore.isSuper(),
                builder: (context, snapshot) {
                  if (snapshot.data != true) return const SizedBox.shrink();
                  return Column(
                    children: [
                      ElevatedButton(
                        onPressed: () async {
                          final prefs = await SharedPreferences.getInstance();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'member_id: ${prefs.getInt('member_id')}\n'
                                  'club_id: ${prefs.getInt('club_id')}\n'
                                  'is_admin: ${prefs.getBool('is_admin')}\n'
                                  'is_super: ${prefs.getBool('is_super')}',
                                  maxLines: 5,
                                ),
                                duration: const Duration(seconds: 5),
                              ),
                            );
                          }
                        },
                        child: const Text('Debug: Show Profile'),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                        onPressed: () async {
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.clear();
                          if (context.mounted) {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(builder: (_) => OnboardingPage()),
                            );
                          }
                        },
                        child: const Text('Reset Profile (Debug)'),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      );
    }

    // Mobile layout: build items list dynamically
    return FutureBuilder<bool>(
      future: AuthStore.isSuper(),
      builder: (context, snapshot) {
        final isSuper = snapshot.data == true;
        final items = <_DashItem>[
          _DashItem('Events', Icons.event, () => Navigator.push(context, MaterialPageRoute(builder: (_) => events.EventsPage()))),
          _DashItem('Members', Icons.group, () => Navigator.push(context, MaterialPageRoute(builder: (_) => members.MembersPage()))),
          _DashItem('Calendar', Icons.calendar_month, () => Navigator.push(context, MaterialPageRoute(builder: (_) => calendar.CalendarPage()))),
          _DashItem('News', Icons.article, () => Navigator.push(context, MaterialPageRoute(builder: (_) => news.NewsPage()))),
        ];
        if (isSuper) {
          items.add(
            _DashItem('Audit Log', Icons.history, () => Navigator.push(context, MaterialPageRoute(builder: (_) => AuditLogPage()))),
          );
        }

        return GridView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, mainAxisSpacing: 16, crossAxisSpacing: 16,
            ),
            itemBuilder: (ctx, i) {
              final it = items[i];
              return Card(
                elevation: 3,
                child: InkWell(
                  onTap: it.onTap,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(it.icon, size: 44, color: Colors.red),
                      const SizedBox(height: 12),
                      Text(it.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              );
            },
          );
      },
    );
  }
}

class _DashItem {
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  _DashItem(this.title, this.icon, this.onTap);
}
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

// ...existing code...
class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      const HomePage(),
      members.MembersPage(),
      events.EventsPage(),
      calendar.CalendarPage(),
      news.NewsPage(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= _navBreakpoint;

    if (isWide) {
  // Desktop / tablet: NavigationRail
  return Scaffold(
    // ADD THIS ENTIRE appBar SECTION:
    appBar: AppBar(
      title: const Text('Lions Club'),
      backgroundColor: Colors.red,
      actions: [
        // NEW: Reports button (admin/super only)
        FutureBuilder<bool>(
          future: Future.wait([AuthStore.isAdmin(), AuthStore.isSuper()])
              .then((results) => results[0] || results[1]),
          builder: (context, snapshot) {
            if (snapshot.data != true) return const SizedBox.shrink();
            return IconButton(
              icon: const Icon(Icons.assessment),
              tooltip: 'Reports',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ReportsPage()),
                );
              },
            );
          },
        ),
      ],
    ),
    // Your existing body: stays the same
    body: Row(
      children: [
        NavigationRail(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) => setState(() => _selectedIndex = index),
          labelType: NavigationRailLabelType.all,
          destinations: const [
            NavigationRailDestination(icon: Icon(Icons.home), label: Text('Home')),
            NavigationRailDestination(icon: Icon(Icons.group), label: Text('Members')),
            NavigationRailDestination(icon: Icon(Icons.event), label: Text('Events')),
            NavigationRailDestination(icon: Icon(Icons.calendar_month), label: Text('Calendar')),
            NavigationRailDestination(icon: Icon(Icons.article), label: Text('News')),
          ],
        ),
        const VerticalDivider(thickness: 1, width: 1),
        Expanded(child: _pages[_selectedIndex]),
      ],
    ),
  );
}

// Mobile: BottomNavigationBar
return Scaffold(
  // ADD THE SAME appBar HERE TOO:
  appBar: AppBar(
    title: const Text('Lions Club'),
    backgroundColor: Colors.red,
    actions: [
      // NEW: Reports button (admin/super only) - same for mobile
      FutureBuilder<bool>(
        future: Future.wait([AuthStore.isAdmin(), AuthStore.isSuper()])
            .then((results) => results[0] || results[1]),
        builder: (context, snapshot) {
          if (snapshot.data != true) return const SizedBox.shrink();
          return IconButton(
            icon: const Icon(Icons.assessment),
            tooltip: 'Reports',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ReportsPage()),
              );
            },
          );
        },
      ),
    ],
  ),
  // Your existing body and bottomNavigationBar stay the same
  body: _pages[_selectedIndex],
  bottomNavigationBar: BottomNavigationBar(
    currentIndex: _selectedIndex,
    selectedItemColor: Colors.red,
    type: BottomNavigationBarType.fixed,
    onTap: (i) => setState(() => _selectedIndex = i),
    items: const [
      BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
      BottomNavigationBarItem(icon: Icon(Icons.group), label: 'Members'),
      BottomNavigationBarItem(icon: Icon(Icons.event), label: 'Events'),
      BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: 'Calendar'),
      BottomNavigationBarItem(icon: Icon(Icons.article), label: 'News'),
    ],
  ),
);
  }
}