import 'package:flutter/material.dart';
import 'events_page.dart' as events;
import 'members_page.dart' as members;
import 'calendar_page.dart' as calendar;
import 'news_page.dart' as news;
import 'onboarding_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final hasProfile = prefs.containsKey('member_id');
  runApp(LionsApp(showOnboarding: !hasProfile));
}

class LionsApp extends StatelessWidget {
  final bool showOnboarding;
  const LionsApp({super.key, required this.showOnboarding});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lions Club',
      theme: ThemeData(primarySwatch: Colors.red),
      home: showOnboarding ? const OnboardingPage() : const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  // Not const: allows pages whose constructors aren't const
  final List<Widget> _pages = [
    const HomePage(),
    members.MembersPage(),
    events.EventsPage(),
    calendar.CalendarPage(),
    news.NewsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              setState(() => _selectedIndex = index);
            },
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.home),
                label: Text('Home'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.group),
                label: Text('Members'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.event),
                label: Text('Events'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.calendar_month),
                label: Text('Calendar'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.article),
                label: Text('News'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(child: _pages[_selectedIndex]),
        ],
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/images/mudgeeraba_lions_image.jpg'),
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
            ElevatedButton(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                print('🔍 DEBUG Profile:');
                print('  member_id: ${prefs.getInt('member_id')}');
                print('  club_id: ${prefs.getInt('club_id')}');
                print('  is_admin: ${prefs.getBool('is_admin')}');
                
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'member_id: ${prefs.getInt('member_id')}\n'
                        'club_id: ${prefs.getInt('club_id')}\n'
                        'is_admin: ${prefs.getBool('is_admin')}',
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
                    MaterialPageRoute(builder: (_) => const OnboardingPage()),
                  );
                }
              },
              child: const Text('Reset Profile (Debug)'),
            ),
          ],
        ),
      ),
    );
  }
}