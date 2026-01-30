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
    final emailSubdomainCtrl = TextEditingController();
    final replyToEmailCtrl = TextEditingController();
    final fromNameCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create New Club'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Club Name *',
                  hintText: 'e.g., Mudgeeraba Lions Club',
                ),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: emailSubdomainCtrl,
                decoration: const InputDecoration(
                  labelText: 'Email Subdomain',
                  hintText: 'e.g., mudgeeraba',
                  helperText: 'Emails will be sent from: noreply@subdomain.thelionsapp.com',
                  helperMaxLines: 2,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: replyToEmailCtrl,
                decoration: const InputDecoration(
                  labelText: 'Reply-To Email',
                  hintText: 'e.g., secretary@mudgeerabalions.org.au',
                  helperText: 'Club\'s actual email address for replies',
                  helperMaxLines: 2,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: fromNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'From Name',
                  hintText: 'e.g., Mudgeeraba Lions Club',
                  helperText: 'Display name shown to recipients',
                  helperMaxLines: 2,
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
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (ok != true || nameCtrl.text.trim().isEmpty) return;

    try {
      final res = await ApiClient.post('/clubs', body: {
        'name': nameCtrl.text.trim(),
        'email_subdomain': emailSubdomainCtrl.text.trim(),
        'reply_to_email': replyToEmailCtrl.text.trim(),
        'from_name': fromNameCtrl.text.trim(),
      });
      
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
    final emailSubdomainCtrl = TextEditingController(text: club['email_subdomain']?.toString() ?? '');
    final replyToEmailCtrl = TextEditingController(text: club['reply_to_email']?.toString() ?? '');
    final fromNameCtrl = TextEditingController(text: club['from_name']?.toString() ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Club'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Club Name *',
                ),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: emailSubdomainCtrl,
                decoration: const InputDecoration(
                  labelText: 'Email Subdomain',
                  hintText: 'e.g., mudgeeraba',
                  helperText: 'Emails will be sent from: noreply@subdomain.thelionsapp.com',
                  helperMaxLines: 2,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: replyToEmailCtrl,
                decoration: const InputDecoration(
                  labelText: 'Reply-To Email',
                  hintText: 'e.g., secretary@mudgeerabalions.org.au',
                  helperText: 'Club\'s actual email address for replies',
                  helperMaxLines: 2,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: fromNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'From Name',
                  hintText: 'e.g., Mudgeeraba Lions Club',
                  helperText: 'Display name shown to recipients',
                  helperMaxLines: 2,
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
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (ok != true || nameCtrl.text.trim().isEmpty) return;

    try {
      final res = await ApiClient.put('/clubs/${club['id']}', body: {
        'name': nameCtrl.text.trim(),
        'email_subdomain': emailSubdomainCtrl.text.trim(),
        'reply_to_email': replyToEmailCtrl.text.trim(),
        'from_name': fromNameCtrl.text.trim(),
      });
      
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
                        final emailSubdomain = club['email_subdomain']?.toString();
                        final hasEmailConfig = emailSubdomain != null && emailSubdomain.isNotEmpty;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: hasEmailConfig ? Colors.green : Colors.red,
                              child: Icon(
                                hasEmailConfig ? Icons.email : Icons.groups, 
                                color: Colors.white,
                              ),
                            ),
                            title: Text(
                              clubName,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('ID: ${club['id']}'),
                                if (hasEmailConfig)
                                  Text(
                                    'Email: noreply@$emailSubdomain.thelionsapp.com',
                                    style: const TextStyle(fontSize: 12, color: Colors.green),
                                  )
                                else
                                  const Text(
                                    'Email not configured',
                                    style: TextStyle(fontSize: 12, color: Colors.orange),
                                  ),
                              ],
                            ),
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