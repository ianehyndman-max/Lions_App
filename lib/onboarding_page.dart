import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart';

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
      final res = await http.get(Uri.parse('http://localhost:8080/clubs'));
      if (res.statusCode == 200) {
        setState(() {
          _clubs = json.decode(res.body) as List;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMembers(int clubId) async {
    setState(() => _isLoading = true);
    try {
      final res = await http.get(Uri.parse('http://localhost:8080/members?club_id=$clubId'));
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
                  DropdownButton<int>(
                    isExpanded: true,
                    hint: const Text('Choose Club'),
                    value: _selectedClubId,
                    items: _clubs.map((c) {
                      final id = (c['id'] is num) ? (c['id'] as num).toInt() : int.parse(c['id'].toString());
                      return DropdownMenuItem<int>(value: id, child: Text(c['name'].toString()));
                    }).toList(),
                    onChanged: (v) {
                      setState(() => _selectedClubId = v);
                      if (v != null) _loadMembers(v);
                    },
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