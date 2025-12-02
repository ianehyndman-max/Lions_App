import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';
import 'auth_store.dart';
import 'api_client.dart';
import 'manage_clubs_page.dart';

class MembersPage extends StatefulWidget {
  const MembersPage({super.key});

  @override
  State<MembersPage> createState() => _MembersPageState();
}

class _MembersPageState extends State<MembersPage> {
  List<dynamic> _members = [];
  Map<String, String> _clubNames = {};
  bool _isLoading = true;
  String? _error;
  
  // User profile
  int? _userClubId;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    _userClubId = prefs.getInt('club_id');
    _isAdmin = prefs.getBool('is_admin') ?? false;
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      // Load clubs (id -> name)
      final clubsRes = await http.get(Uri.parse('$apiBase/clubs'));
      if (clubsRes.statusCode == 200) {
        final clubs = json.decode(clubsRes.body) as List;
        _clubNames = {
          for (final c in clubs)
            (c['id']?.toString() ?? ''): (c['name']?.toString() ?? '')
        };
      }

      // Load members (filtered by user's club if set)
      
      final membersUrl = _userClubId == null
          ? '$apiBase/members'
          : '$apiBase/members?club_id=$_userClubId';
      final membersRes = await http.get(Uri.parse(membersUrl));
      if (membersRes.statusCode == 200) {
        _members = json.decode(membersRes.body) as List;
        // Sort alphabetically
        _members.sort((a, b) {
          final nameA = (a['name'] ?? '').toString().toLowerCase();
          final nameB = (b['name'] ?? '').toString().toLowerCase();
          return nameA.compareTo(nameB);
        });
      } else {
        _error = 'Failed to load members: ${membersRes.statusCode}';
      }
    } catch (e) {
      _error = 'Error: $e';
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _clubNameFor(dynamic m) {
    final joined = (m['club_name'] ?? m['club'] ?? m['clubName'])?.toString();
    if (joined != null && joined.isNotEmpty) return joined;

    final idStr = m['lions_club_id']?.toString() ?? '';
    if (idStr.isEmpty) return '';
    return _clubNames[idStr] ?? idStr;
  }

  int? _toInt(dynamic val) {
    if (val == null) return null;
    if (val is int) return val;
    if (val is num) return val.toInt();
    if (val is String) return int.tryParse(val);
    return null;
  }

  Future<void> _openEditOwnProfileDialog() async {
  final prefs = await SharedPreferences.getInstance();
  final memberId = prefs.getInt('member_id');
  if (memberId == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Member ID not found')),
    );
    return;
  }

  // Find current member in the list
  final member = _members.firstWhere(
    (m) => _toInt(m['id']) == memberId,
    orElse: () => <String, dynamic>{},
  );

  if (member.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Your profile not found')),
    );
    return;
  }

  final nameCtrl = TextEditingController(text: member['name']?.toString() ?? '');
  final emailCtrl = TextEditingController(text: member['email']?.toString() ?? '');
  final phoneCtrl = TextEditingController(text: member['phone_number']?.toString() ?? '');

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Edit My Profile'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: emailCtrl,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: phoneCtrl,
              decoration: const InputDecoration(labelText: 'Phone number'),
            ),
            const SizedBox(height: 16),
            const Text(
              'Note: Club and admin status can only be changed by administrators.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: nameCtrl.text.trim().isEmpty
              ? null
              : () => Navigator.pop(ctx, true),
          child: const Text('Save'),
        ),
      ],
    ),
  );

  if (ok == true) {
    final payload = {
      'name': nameCtrl.text.trim(),
      'email': emailCtrl.text.trim(),
      'phone_number': phoneCtrl.text.trim(),
    };

    debugPrint('DEBUG: About to update own profile memberId=$memberId with payload: $payload');

    final res = await ApiClient.put('/members/$memberId', body: payload);
    debugPrint('DEBUG: Update own profile response status=${res.statusCode} body=${res.body}');

    if (!mounted) return;
    if (res.statusCode == 200) {
      // Update local SharedPreferences with new name
      await prefs.setString('name', nameCtrl.text.trim());
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated')),
      );
      _loadData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update failed: ${res.body}')),
      );
    }
  }
}

  Future<void> _openCreateMemberDialog() async {
    if (!_isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Admin access required')),
      );
      return;
    }

    List<dynamic> clubs = [];
    try {
      final res = await http.get(Uri.parse('$apiBase/clubs'));
       if (res.statusCode == 200) {
         clubs = json.decode(res.body) as List;
       }
    } catch (_) {}

    final isSuper = await AuthStore.isSuper();
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    // Default to user's club if set
    int? selectedClubId;
    if (!isSuper && _userClubId != null) {
      selectedClubId = _userClubId;
    } else if (clubs.isNotEmpty) {
      selectedClubId = _toInt(clubs.first['id']);
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Add Member'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(labelText: 'Phone number'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  value: selectedClubId,
                  items: clubs
                      .map((c) {
                        final id = _toInt(c['id']);
                        return DropdownMenuItem<int>(
                          value: id,
                          child: Text(c['name']?.toString() ?? c['id'].toString()),
                        );
                      })
                      .where((e) => e.value != null)
                      .toList(),
                  onChanged: isSuper ? (v) => setDlg(() => selectedClubId = v) : null,  // Lock for non-super users
                  decoration: InputDecoration(
                    labelText: 'Club',
                    suffixIcon: isSuper ? null : const Icon(Icons.lock, size: 16),
                    helperText: isSuper ? null : 'Locked to your club',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: (nameCtrl.text.trim().isEmpty || selectedClubId == null)
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      final payload = {
        'name': nameCtrl.text.trim(),
        'email': emailCtrl.text.trim(),
        'phone_number': phoneCtrl.text.trim(),
        'lions_club_id': selectedClubId,
      };

      final res = await ApiClient.post('/members', body: payload);

      if (!mounted) return;
      if (res.statusCode == 200 || res.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Member created')),
        );
        _loadData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Create failed: ${res.body}')),
        );
      }
    }
  }

  Future<void> _openEditMemberDialog(dynamic member) async {
    if (!_isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Admin access required')),
      );
      return;
    }

    final isSuper = await AuthStore.isSuper();  // Add this line

    List<dynamic> clubs = [];
    try {
      final res = await http.get(Uri.parse('http://localhost:8080/clubs'));
      if (res.statusCode == 200) {
        clubs = json.decode(res.body) as List;
      }
    } catch (_) {}

    final idStr = member['id']?.toString() ?? '';
    final nameCtrl = TextEditingController(text: member['name']?.toString() ?? '');
    final emailCtrl = TextEditingController(text: member['email']?.toString() ?? '');
    final phoneCtrl = TextEditingController(text: member['phone_number']?.toString() ?? '');

    int? selectedClubId = _toInt(member['lions_club_id']);
    bool isAdminMember = member['is_admin'] == 1 || member['is_admin'] == true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Edit Member'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(labelText: 'Phone number'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  value: selectedClubId,
                  items: clubs
                      .map((c) {
                        final id = _toInt(c['id']);
                        return DropdownMenuItem<int>(
                          value: id,
                          child: Text(c['name']?.toString() ?? c['id'].toString()),
                        );
                      })
                      .where((e) => e.value != null)
                      .toList(),
                  onChanged: isSuper ? (v) => setDlg(() => selectedClubId = v) : null,  // Lock for non-super users
                  decoration: InputDecoration(
                    labelText: 'Club',
                    suffixIcon: isSuper ? null : const Icon(Icons.lock, size: 16),
                    helperText: isSuper ? null : 'Locked to your club',
                  ),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: isAdminMember,
                  onChanged: (val) {
                    setDlg(() {
                      isAdminMember = val ?? false;
                    });
                  },
                  title: const Text('Admin Access'),
                  subtitle: const Text('Can create/edit members and events'),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: (nameCtrl.text.trim().isEmpty || selectedClubId == null)
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      final payload = {
        'name': nameCtrl.text.trim(),
        'email': emailCtrl.text.trim(),
        'phone_number': phoneCtrl.text.trim(),
        'lions_club_id': selectedClubId,
        'is_admin': isAdminMember ? 1 : 0,
      };

      debugPrint('DEBUG: About to update member $idStr with payload: $payload');

      final res = await ApiClient.put('/members/$idStr', body: payload);
      debugPrint('DEBUG: Update response status=${res.statusCode} body=${res.body}');

      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Member updated')),
        );
        _loadData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update failed: ${res.body}')),
        );
      }
    }
  }

  Future<void> _deleteMember(String idStr) async {
    if (!_isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Admin access required')),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Member?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final res = await http.delete(Uri.parse('$apiBase/members/$idStr'));

    if (!mounted) return;
    if (res.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Member deleted')),
      );
      _loadData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: ${res.body}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    print('DEBUG: MembersPage build');
    return Scaffold(
      appBar: AppBar(
  title: const Text('Members'),
  backgroundColor: Colors.red,
  actions: [
    // My Profile button (visible to all users)
    IconButton(
      icon: const Icon(Icons.account_circle),
      tooltip: 'My Profile',
      onPressed: _openEditOwnProfileDialog,
    ),
    // Refresh button (visible to all users)
    IconButton(
      icon: const Icon(Icons.refresh),
      tooltip: 'Refresh',
      onPressed: _loadData,
    ),
    // Add Member button (admin/super only)
    if (_isAdmin)
      IconButton(
        icon: const Icon(Icons.person_add),
        tooltip: 'Add Member',
        onPressed: _openCreateMemberDialog,
      ),
    // Manage Clubs button (super only)
    FutureBuilder<bool>(
      future: AuthStore.isSuper(),
      builder: (context, snapshot) {
        if (snapshot.data == true) {
          return IconButton(
            icon: const Icon(Icons.business),
            tooltip: 'Manage Clubs',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ManageClubsPage()),
              );
            },
          );
        }
        return const SizedBox.shrink();
      },
    ),
  ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : _members.isEmpty
                  ? const Center(child: Text('No members found'))
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: DataTable(
                            headingRowColor: MaterialStatePropertyAll(Colors.red.shade100),
                            border: TableBorder.all(color: Colors.grey.shade300),
                            columns: [
                              const DataColumn(label: Text('ID', style: TextStyle(fontWeight: FontWeight.bold))),
                              const DataColumn(label: Text('Name', style: TextStyle(fontWeight: FontWeight.bold))),
                              const DataColumn(label: Text('Email', style: TextStyle(fontWeight: FontWeight.bold))),
                              const DataColumn(label: Text('Phone', style: TextStyle(fontWeight: FontWeight.bold))),
                              const DataColumn(label: Text('Club', style: TextStyle(fontWeight: FontWeight.bold))),
                              if (_isAdmin)
                                const DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                            ],
                            rows: _members.map((m) {
                              final idStr = m['id']?.toString() ?? '';
                              return DataRow(cells: [
                                DataCell(Text(idStr)),
                                DataCell(Text(m['name']?.toString() ?? '')),
                                DataCell(Text(m['email']?.toString() ?? '')),
                                DataCell(Text(m['phone_number']?.toString() ?? '')),
                                DataCell(Text(_clubNameFor(m))),
                                if (_isAdmin)
                                  DataCell(
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: 'Edit',
                                          icon: const Icon(Icons.edit, size: 20),
                                          onPressed: () => _openEditMemberDialog(m),
                                        ),
                                        IconButton(
                                          tooltip: 'Delete',
                                          icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                                          onPressed: () => _deleteMember(idStr),
                                        ),
                                      ],
                                    ),
                                  ),
                              ]);
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
      floatingActionButton: _isAdmin
          ? FloatingActionButton.extended(
              onPressed: _openCreateMemberDialog,
              icon: const Icon(Icons.person_add),
              label: const Text('Add Member'),
              backgroundColor: Colors.red,
            )
          : null,
    );
  }
}