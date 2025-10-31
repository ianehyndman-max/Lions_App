import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'event_detail_page.dart';
import 'create_event_dialog.dart';

class EventsPage extends StatefulWidget {
  EventsPage({super.key});

  @override
  State<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends State<EventsPage> {
  List<dynamic> _events = [];
  List<dynamic> _eventTypes = [];
  List<dynamic> _clubs = [];
  bool _loading = true;
  String? _error;
  String _fmtYmd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  int? _userClubId;
  bool _isAdmin = false;

  // Same helper as MembersPage
  int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    _userClubId = prefs.getInt('club_id');
    _isAdmin = prefs.getBool('is_admin') ?? false;
    _load(); // do not setState here; _load() handles it
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final url = _userClubId == null
          ? 'http://localhost:8080/events'
          : 'http://localhost:8080/events?club_id=$_userClubId';
      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200) {
        _events = (json.decode(res.body) as List);
      } else {
        _error = 'Failed to load events: ${res.statusCode}';
      }
    } catch (e) {
      _error = 'Error: $e';
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadEventTypes() async {
    //final res = await http.get(Uri.parse('http://localhost:8080/event-types'));
    final res = await http.get(Uri.parse('http://localhost:8080/event_types'));
    if (res.statusCode == 200) {
      setState(() => _eventTypes = json.decode(res.body) as List);
    }
  }

  Future<void> _loadClubs() async {
    final res = await http.get(Uri.parse('http://localhost:8080/clubs'));
    if (res.statusCode == 200) {
      setState(() => _clubs = json.decode(res.body) as List);
    }
  }

  Future<void> _sendEventNotificationEmails(int eventId) async {
    try {
      final res = await http.post(
        Uri.parse('http://localhost:8080/events/$eventId/notify'),
        headers: {'Content-Type': 'application/json'},
      );
      if (!mounted) return;

      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✉️ Email notifications sent to all members'), backgroundColor: Colors.green),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('⚠️ Emails failed to send: ${res.body}'), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('⚠️ Email error: $e'), backgroundColor: Colors.orange),
      );
    }
  }

  // ...existing code...
  Future<void> _openCreateEventDialog() async {
    // Opens the shared dialog (handles roles for “Other” and does the POST)
    final newId = await showCreateEventDialog(context);
    if (!mounted || newId == null) return;

    // Refresh the table
    await _load();

    // Notify users (same as before)
    final idInt = int.tryParse(newId);
    if (idInt != null) {
      await _sendEventNotificationEmails(idInt);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ Event created successfully')),
   );
  }
// ...existing code...
  Future<void> _openEditEventDialog(Map<String, dynamic> event) async {
    if (!_isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Admin access required')));
      return;
    }

    await _loadEventTypes();
    await _loadClubs();
    if (!mounted) return;

    int? eventTypeId = _toInt(event['event_type_id']);
    int? clubId = _toInt(event['club_id'] ?? event['lions_club_id']);
    DateTime? date = event['date'] != null
        ? DateTime.tryParse(event['date'].toString())
        : (event['event_date'] != null ? DateTime.tryParse(event['event_date'].toString()) : null);
    final locationCtrl = TextEditingController(text: event['location']?.toString() ?? '');
    final notesCtrl = TextEditingController(text: event['notes']?.toString() ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Event'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  value: eventTypeId,
                  decoration: const InputDecoration(labelText: 'Event Type'),
                  items: _eventTypes
                      .map((et) {
                        final id = _toInt(et['id']);
                        if (id == null) return null;
                        return DropdownMenuItem<int>(
                          value: id,
                          child: Text(et['name']?.toString() ?? et['id'].toString()),
                        );
                      })
                      .whereType<DropdownMenuItem<int>>()
                      .toList(),
                  onChanged: (v) => setDialogState(() => eventTypeId = v),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  value: clubId,
                  decoration: const InputDecoration(labelText: 'Club'),
                  items: _clubs
                      .map((c) {
                        final id = _toInt(c['id']);
                        if (id == null) return null;
                        return DropdownMenuItem<int>(
                          value: id,
                          child: Text(c['name']?.toString() ?? c['id'].toString()),
                        );
                      })
                      .whereType<DropdownMenuItem<int>>()
                      .toList(),
                  onChanged: (v) => setDialogState(() => clubId = v),
                ),
                const SizedBox(height: 8),
                ListTile(
                  title: Text(date == null ? 'Select Date' : date.toString().split(' ')[0]),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: date ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) setDialogState(() => date = picked);
                  },
                ),
                TextField(
                  controller: locationCtrl,
                  decoration: const InputDecoration(labelText: 'Location'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: notesCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Notes (optional)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );

    if (ok != true || eventTypeId == null || clubId == null || date == null) return;

    final d = date!;
    final eventDate = _fmtYmd(d);
    
    final put = await http.put(
      Uri.parse('http://localhost:8080/events/${event['id']}'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'event_type_id': eventTypeId,
        'lions_club_id': clubId,
        'event_date': eventDate,
        'location': locationCtrl.text,
        'notes': notesCtrl.text,
      }),
    );

    if (!mounted) return;

    if (put.statusCode == 200) {
      await _load();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Event updated')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: ${put.body}')));
    }
  }

  Future<void> _deleteEvent(int eventId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Event?'),
        content: const Text('This will remove the event and all volunteer assignments.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final res = await http.delete(Uri.parse('http://localhost:8080/events/$eventId'));
    if (!mounted) return;

    if (res.statusCode == 200) {
      await _load();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Event deleted')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: ${res.body}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Events'),
        backgroundColor: Colors.red,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : _events.isEmpty
                  ? const Center(child: Text('No events found'))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingRowColor: MaterialStateProperty.all(Colors.red.shade100),
                          border: TableBorder.all(color: Colors.grey.shade300),
                          columns: [
                            const DataColumn(label: Text('Event Type', style: TextStyle(fontWeight: FontWeight.bold))),
                            const DataColumn(label: Text('Club', style: TextStyle(fontWeight: FontWeight.bold))),
                            const DataColumn(label: Text('Date', style: TextStyle(fontWeight: FontWeight.bold))),
                            const DataColumn(label: Text('Location', style: TextStyle(fontWeight: FontWeight.bold))),
                            if (_isAdmin)
                              const DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                          ],
                          rows: _events.map((e) {
                            final eventId = _toInt(e['id']) ?? 0;
                            return DataRow(
                              cells: [
                                DataCell(
                                  Text(e['event_type']?.toString() ?? ''),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => EventDetailPage(eventId: eventId)),
                                  ),
                                ),
                                DataCell(
                                  Text(e['club_name']?.toString() ?? ''),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => EventDetailPage(eventId: eventId)),
                                  ),
                                ),
                                DataCell(
                                  Text(e['date']?.toString() ?? e['event_date']?.toString() ?? ''),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => EventDetailPage(eventId: eventId)),
                                  ),
                                ),
                                DataCell(
                                  Text(e['location']?.toString() ?? ''),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => EventDetailPage(eventId: eventId)),
                                  ),
                                ),
                                if (_isAdmin)
                                  DataCell(
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
                                          onPressed: () => _openEditEventDialog(e as Map<String, dynamic>),
                                          tooltip: 'Edit',
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                                          onPressed: () => _deleteEvent(eventId),
                                          tooltip: 'Delete',
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
      floatingActionButton: _isAdmin
          ? FloatingActionButton.extended(
              onPressed: _openCreateEventDialog,
              icon: const Icon(Icons.add),
              label: const Text('Create Event'),
              backgroundColor: Colors.red,
            )
          : null,
    );
  }
}