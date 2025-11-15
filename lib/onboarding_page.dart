import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart';
import 'config.dart';
import 'dart:math';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  List<dynamic> _clubs = [];
  List<dynamic> _members = [];
  int? _selectedClubId;
  int? _selectedMemberId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadClubs();
  }

  Future<void> _loadClubs() async {
    try {
      debugPrint('DEBUG: onboarding _fetchClubs -> $apiBase/clubs');
      final res = await http.get(Uri.parse('$apiBase/clubs'));
      debugPrint('DEBUG: onboarding /clubs status=${res.statusCode} content-type=${res.headers['content-type']}');
      // guard: if server returned HTML (index.html) show informative error
      final body = res.body;
      if (!(res.headers['content-type']?.contains('application/json') ?? false) || body.trimLeft().startsWith('<')) {
        final start = body.trimLeft();
        final end = start.length < 200 ? start.length : 200;
        debugPrint('ERROR: /clubs returned non-JSON (likely wrong host/origin). Response start: ${start.substring(0, end)}');
        setState(() => _isLoading = false);
        return;
      }
      if (res.statusCode == 200) {
        setState(() {
          _clubs = json.decode(body) as List<dynamic>;
          _isLoading = false;
        });
        debugPrint('DEBUG: _loadClubs completed, clubs.length=${_clubs.length}');
      } else {
        debugPrint('DEBUG: _loadClubs non-200 ${res.statusCode} body=${res.body}');
        setState(() => _isLoading = false);
      }
    } catch (e, st) {
      debugPrint('ERROR: onboarding _loadClubs exception: $e\n$st');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMembers(int clubId) async {
    setState(() => _isLoading = true);
    try {
      final res = await http.get(Uri.parse('$apiBase/members?club_id=$clubId'));
      if (res.statusCode == 200) {
        setState(() {
          _members = json.decode(res.body) as List;
          _selectedMemberId = null;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveAndContinue() async {
  if (_selectedClubId == null || _selectedMemberId == null) return;

  final member = _members.firstWhere((m) => m['id'].toString() == _selectedMemberId.toString());
  
  // Fix: Handle MySQL Blob/binary data for is_admin
  final isAdminRaw = member['is_admin'];
  final isAdmin = isAdminRaw == 1 || 
                  isAdminRaw == true || 
                  isAdminRaw == '1' ||
                  (isAdminRaw is List && isAdminRaw.isNotEmpty && isAdminRaw[0] == 1);

  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt('club_id', _selectedClubId!);
  await prefs.setInt('member_id', _selectedMemberId!);
  await prefs.setBool('is_admin', isAdmin);

  if (!mounted) return;
  Navigator.of(context).pushReplacement(
    MaterialPageRoute(builder: (_) => const MainScreen()),
  );
}

  @override
  Widget build(BuildContext context) {
    print('BUILD: isLoading=$_isLoading clubs=${_clubs.length} selectedClub=$_selectedClubId selectedMember=$_selectedMemberId');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Welcome to Lions Club'),
        backgroundColor: Colors.red,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Select your club:', style: TextStyle(fontSize: 18)),
                  const SizedBox(height: 16),
                  // Debug: show count so we know items were loaded
                 Text('Clubs count: ${_clubs.length}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                 const SizedBox(height: 8),
                 // Wrap with Listener to detect pointer events without consuming them
                 Listener(
                   onPointerDown: (_) => print('DEBUG: club dropdown pointer down'),
                   onPointerUp: (_) => print('DEBUG: club dropdown pointer up'),
                   child: DropdownButton<int>(
                     isExpanded: true,
                     hint: const Text('Choose Club'),
                     value: _selectedClubId,
                     items: _clubs.map((c) {
                       final id = (c['id'] is num) ? (c['id'] as num).toInt() : int.parse(c['id'].toString());
                       return DropdownMenuItem<int>(value: id, child: Text(c['name'].toString()));
                     }).toList(),
                     onChanged: (v) {
                       print('DEBUG: club dropdown onChanged -> $v');
                       setState(() => _selectedClubId = v);
                       if (v != null) _loadMembers(v);
                     },
                   ),
                 ),
                  const SizedBox(height: 32),
                  if (_members.isNotEmpty) ...[
                    const Text('Who are you?', style: TextStyle(fontSize: 18)),
                    const SizedBox(height: 16),
                    DropdownButton<int>(
                      isExpanded: true,
                      hint: const Text('Choose Member'),
                      value: _selectedMemberId,
                      items: _members.map((m) {
                        final id = (m['id'] is num) ? (m['id'] as num).toInt() : int.parse(m['id'].toString());
                        return DropdownMenuItem<int>(value: id, child: Text(m['name'].toString()));
                      }).toList(),
                      onChanged: (v) => setState(() => _selectedMemberId = v),
                    ),
                  ],
                  const SizedBox(height: 48),
                  FilledButton(
                    onPressed: (_selectedClubId != null && _selectedMemberId != null) ? _saveAndContinue : null,
                    child: const Text('Continue'),
                  ),
                ],
              ),
            ),
    );
  }
}