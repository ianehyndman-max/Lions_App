import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'event_detail_page.dart';

class EventsPage extends StatefulWidget {
  const EventsPage({super.key});

  @override
  State<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends State<EventsPage> {
  List<dynamic> _events = [];
  List<dynamic> _eventTypes = [];
  List<dynamic> _clubs = [];
  bool _loading = true;
  String? _error;
  
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
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final clubParam = _userClubId != null ? '?club_id=$_userClubId' : '';
      final res = await http.get(Uri.parse('http://localhost:8080/events$clubParam'));
      if (res.statusCode == 200) {
        setState(() {
          _events = (json.decode(res.body) as List).cast<Map<String, dynamic>>();
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Failed: ${res.statusCode}';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _loading = false;
      });
    }
  }

  Future<void> _loadEventTypes() async {
    final res = await http.get(Uri.parse('http://localhost:8080/event-types'));
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

  Future<void> _openCreateEventDialog() async {
    await _loadEventTypes();
    await _loadClubs();
    if (!mounted) return;

    int? eventTypeId;
    int? clubId = _userClubId;
    DateTime? date;
    final locationCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create Event'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  value: eventTypeId,
                  decoration: const InputDecoration(labelText: 'Event Type'),
                  items: _eventTypes.map((et) {
                    final id = (et['id'] as num).toInt();
                    return DropdownMenuItem(value: id, child: Text(et['name'].toString()));
                  }).toList(),
                  onChanged: (v) => setDialogState(() => eventTypeId = v),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  value: clubId,
                  decoration: const InputDecoration(labelText: 'Club'),
                  items: _clubs.map((c) {
                    final id = (c['id'] as num).toInt();
                    return DropdownMenuItem(value: id, child: Text(c['name'].toString()));
                  }).toList(),
                  onChanged: (v) => setDialogState(() => clubId = v),
                ),
                const SizedBox(height: 8),
                ListTile(
                  title: Text(date == null ? 'Select Date' : date.toString().split(' ')[0]),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
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
                  decoration: const InputDecoration(labelText: 'Notes (optional)', border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
          ],
        ),
      ),
    );

    if (ok != true || eventTypeId == null || clubId == null || date == null) return;

    final post = await http.post(
      Uri.parse('http://localhost:8080/events'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'event_type_id': eventTypeId,
        'lions_club_id': clubId,
        'event_date': '${date!.year}-${date!.month.toString().padLeft(2, '0')}-${date!.day.toString().padLeft(2, '0')}',
        'location': locationCtrl.text,
        'notes': notesCtrl.text,
      }),
    );

    if (!mounted) return;

    if (post.statusCode == 201) {
      await _load();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Event created')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: ${post.body}')));
    }
  }

  Future<void> _openEditEventDialog(Map<String, dynamic> event) async {
    await _loadEventTypes();
    await _loadClubs();
    if (!mounted) return;

    int? eventTypeId = event['event_type_id'] as int?;
    int? clubId = event['club_id'] as int?;
    DateTime? date = event['date'] != null ? DateTime.tryParse(event['date'].toString()) : null;
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
                  items: _eventTypes.map((et) {
                    final id = (et['id'] as num).toInt();
                    return DropdownMenuItem(value: id, child: Text(et['name'].toString()));
                  }).toList(),
                  onChanged: (v) => setDialogState(() => eventTypeId = v),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  value: clubId,
                  decoration: const InputDecoration(labelText: 'Club'),
                  items: _clubs.map((c) {
                    final id = (c['id'] as num).toInt();
                    return DropdownMenuItem(value: id, child: Text(c['name'].toString()));
                  }).toList(),
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
                  decoration: const InputDecoration(labelText: 'Notes (optional)', border: OutlineInputBorder()),
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

    final put = await http.put(
      Uri.parse('http://localhost:8080/events/${event['id']}'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'event_type_id': eventTypeId,
        'lions_club_id': clubId,
        'event_date': '${date!.year}-${date!.month.toString().padLeft(2, '0')}-${date!.day.toString().padLeft(2, '0')}',
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
          if (_isAdmin)
            IconButton(icon: const Icon(Icons.add), onPressed: _openCreateEventDialog),
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
                            return DataRow(
                              cells: [
                                DataCell(
                                  Text(e['event_type'] ?? ''),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => EventDetailPage(eventId: e['id']),
                                      ),
                                    );
                                  },
                                ),
                                DataCell(
                                  Text(e['club_name'] ?? ''),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => EventDetailPage(eventId: e['id']),
                                      ),
                                    );
                                  },
                                ),
                                DataCell(
                                  Text(e['date']?.toString() ?? ''),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => EventDetailPage(eventId: e['id']),
                                      ),
                                    );
                                  },
                                ),
                                DataCell(
                                  Text(e['location']?.toString() ?? ''),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => EventDetailPage(eventId: e['id']),
                                      ),
                                    );
                                  },
                                ),
                                if (_isAdmin)
                                  DataCell(
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
                                          onPressed: () => _openEditEventDialog(e),
                                          tooltip: 'Edit',
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                                          onPressed: () => _deleteEvent(e['id'] as int),
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
    );
  }
}