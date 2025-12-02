import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:lions_app_3/api_client.dart';
import 'package:lions_app_3/auth_store.dart';

class ManageClubsPage extends StatefulWidget {
  const ManageClubsPage({super.key});

  @override
  State<ManageClubsPage> createState() => _ManageClubsPageState();
}

class _ManageClubsPageState extends State<ManageClubsPage> {
  List<dynamic> _clubs = [];
  bool _loading = true;
  String? _error;
  bool _isSuper = false;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    _isSuper = await AuthStore.isSuper();
    if (!_isSuper && mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Super user access required')),
      );
      return;
    }
    _loadClubs();
  }

  Future<void> _loadClubs() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    print('DEBUG: About to call ApiClient.get("/clubs")');
    try {
      final res = await ApiClient.get('/clubs');
      print('DEBUG: Response status=${res.statusCode} body=${res.body}');
      if (res.statusCode == 200) {
        setState(() {
          _clubs = json.decode(res.body) as List;
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load clubs: ${res.statusCode}';
          _loading = false;
        });
      }
    } catch (e) {
      print('DEBUG: Exception caught: $e');
      setState(() {
        _error = 'Error: $e';
        _loading = false;
      });
    }
  }

  Future<void> _createClub() async {
    final nameCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create New Club'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(
            labelText: 'Club Name',
            hintText: 'e.g., Mudgeeraba Lions Club',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (ok != true || nameCtrl.text.trim().isEmpty) return;

    try {
      final res = await ApiClient.post('/clubs', body: {'name': nameCtrl.text.trim()});
      
      if (!mounted) return;

      if (res.statusCode == 200) {
        await _loadClubs();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Club created successfully')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: ${res.body}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _editClub(Map<String, dynamic> club) async {
    final nameCtrl = TextEditingController(text: club['name']?.toString() ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Club'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(labelText: 'Club Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (ok != true || nameCtrl.text.trim().isEmpty) return;

    try {
      final res = await ApiClient.put('/clubs/${club['id']}', body: {'name': nameCtrl.text.trim()});
      
      if (!mounted) return;

      if (res.statusCode == 200) {
        await _loadClubs();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Club updated successfully')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: ${res.body}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _deleteClub(int clubId, String clubName) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Club?'),
        content: Text('Are you sure you want to delete "$clubName"?\n\nThis will affect all associated events and members.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      final res = await ApiClient.delete('/clubs/$clubId');
      
      if (!mounted) return;

      if (res.statusCode == 200 || res.statusCode == 204) {
        await _loadClubs();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Club deleted successfully')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: ${res.body}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Clubs'),
        backgroundColor: Colors.red,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadClubs,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadClubs,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _clubs.isEmpty
                  ? const Center(child: Text('No clubs found'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _clubs.length,
                      itemBuilder: (context, index) {
                        final club = _clubs[index] as Map<String, dynamic>;
                        final clubId = int.tryParse(club['id']?.toString() ?? '');
                        final clubName = club['name']?.toString() ?? 'Unnamed Club';

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: Colors.red,
                              child: Icon(Icons.groups, color: Colors.white),
                            ),
                            title: Text(
                              clubName,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text('ID: ${club['id']}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, color: Colors.blue),
                                  onPressed: () => _editClub(club),
                                  tooltip: 'Edit',
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: clubId != null
                                      ? () => _deleteClub(clubId, clubName)
                                      : null,
                                  tooltip: 'Delete',
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createClub,
        icon: const Icon(Icons.add),
        label: const Text('Create Club'),
        backgroundColor: Colors.red,
      ),
    );
  }
}