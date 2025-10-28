import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:table_calendar/table_calendar.dart';
import 'event_detail_page.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  bool _isLoading = true;
  String? _error;
  final Map<DateTime, List<Map<String, dynamic>>> _eventsByDay = {};

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    _fetchEvents();
  }

  DateTime _onlyDate(DateTime d) => DateTime(d.year, d.month, d.day);

  String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _fetchEvents() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final res = await http.get(Uri.parse('http://localhost:8080/events'));
      if (res.statusCode != 200) {
        setState(() {
          _error = 'Failed to load events: ${res.statusCode}';
          _isLoading = false;
        });
        return;
      }

      final list = (json.decode(res.body) as List)
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      _eventsByDay.clear();
      for (final ev in list) {
        final dateStr = ev['date']?.toString() ?? '';
        if (dateStr.isEmpty) continue;
        DateTime? d;
        try {
          d = DateTime.parse(dateStr); // supports YYYY-MM-DD
        } catch (_) {
          d = null;
        }
        if (d == null) continue;
        final key = _onlyDate(d);
        _eventsByDay.putIfAbsent(key, () => []).add(ev);
      }

      setState(() {
        _isLoading = false;
        _selectedDay ??= _onlyDate(DateTime.now());
      });
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> _eventsForDay(DateTime day) {
    return _eventsByDay[_onlyDate(day)] ?? const [];
  }

  Future<Map<String, dynamic>?> _loadLookups() async {
    final etRes = await http.get(Uri.parse('http://localhost:8080/event_types'));
    final clRes = await http.get(Uri.parse('http://localhost:8080/clubs'));
    if (etRes.statusCode != 200 || clRes.statusCode != 200) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load lookups')),
        );
      }
      return null;
    }
    final eventTypes = (json.decode(etRes.body) as List).cast<Map<String, dynamic>>();
    final clubs = (json.decode(clRes.body) as List).cast<Map<String, dynamic>>();
    return {'eventTypes': eventTypes, 'clubs': clubs};
  }

  Future<void> _openCreateEventDialog([DateTime? initialDate]) async {
    final lookups = await _loadLookups();
    if (lookups == null) return;

    final eventTypes = lookups['eventTypes'] as List<Map<String, dynamic>>;
    final clubs = lookups['clubs'] as List<Map<String, dynamic>>;

    dynamic eventTypeId = eventTypes.isNotEmpty ? eventTypes.first['id'] : null;
    dynamic clubId = clubs.isNotEmpty ? clubs.first['id'] : null;
    DateTime? date = initialDate ?? _selectedDay ?? DateTime.now();
    final locationCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Create Event'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<dynamic>(
                  value: eventTypeId,
                  items: eventTypes
                      .map((e) => DropdownMenuItem(value: e['id'], child: Text(e['name']?.toString() ?? '')))
                      .toList(),
                  onChanged: (v) => setDlg(() => eventTypeId = v),
                  decoration: const InputDecoration(labelText: 'Event Type'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<dynamic>(
                  value: clubId,
                  items: clubs
                      .map((c) => DropdownMenuItem(value: c['id'], child: Text(c['name']?.toString() ?? '')))
                      .toList(),
                  onChanged: (v) => setDlg(() => clubId = v),
                  decoration: const InputDecoration(labelText: 'Club'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: Text(date == null ? 'No date' : _fmt(date!))),
                    TextButton.icon(
                      icon: const Icon(Icons.date_range),
                      label: const Text('Pick date'),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                          initialDate: date ?? DateTime.now(),
                        );
                        if (picked != null) setDlg(() => date = picked);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: locationCtrl,
                  decoration: const InputDecoration(labelText: 'Location'),
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

    if (confirmed == true && eventTypeId != null && clubId != null && date != null) {
      final res = await http.post(
        Uri.parse('http://localhost:8080/events'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'event_type_id': eventTypeId,
          'lions_club_id': clubId,
          'event_date': _fmt(date!), // assert non-null
          'location': locationCtrl.text,
        }),
      );
      if (res.statusCode == 200 || res.statusCode == 201) {
        await _fetchEvents();
        try {
          final id = (json.decode(res.body) as Map<String, dynamic>)['id'];
          final idStr = id?.toString();
          if (idStr != null && mounted) {
            // ignore: use_build_context_synchronously
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => EventDetailPage(eventId: idStr)));
          }
        } catch (_) {}
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: ${res.body}')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dayEvents = _selectedDay == null ? const <Map<String, dynamic>>[] : _eventsForDay(_selectedDay!);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        backgroundColor: Colors.red,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _fetchEvents,
          ),
          IconButton(
            tooltip: 'Add Event',
            icon: const Icon(Icons.add),
            onPressed: () => _openCreateEventDialog(_selectedDay ?? DateTime.now()),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : Column(
                  children: [
                    TableCalendar<Map<String, dynamic>>(
                      firstDay: DateTime.utc(2020, 1, 1),
                      lastDay: DateTime.utc(2100, 12, 31),
                      focusedDay: _focusedDay,
                      selectedDayPredicate: (day) => _selectedDay != null && _onlyDate(day) == _onlyDate(_selectedDay!),
                      eventLoader: (day) => _eventsForDay(day),
                      onDaySelected: (selectedDay, focusedDay) {
                        setState(() {
                          _selectedDay = _onlyDate(selectedDay);
                          _focusedDay = focusedDay;
                        });
                      },
                      headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true),
                      calendarStyle: const CalendarStyle(
                        todayDecoration: BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                        selectedDecoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                        markersAlignment: Alignment.bottomCenter,
                      ),
calendarBuilders: CalendarBuilders(
                        markerBuilder: (ctx, day, events) {
                          if (events.isEmpty) return null;
                          final count = events.length > 3 ? 3 : events.length; // ensure int
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(
                                count,
                                (_) => Container(
                                  width: 6,
                                  height: 6,
                                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: dayEvents.isEmpty
                          ? const Center(child: Text('No events on this day'))
                          : ListView.separated(
                              itemCount: dayEvents.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (ctx, i) {
                                final e = dayEvents[i];
                                final idStr = e['id']?.toString() ?? '';
                                final title = e['event_type']?.toString() ?? 'Event';
                                final club = e['club_name']?.toString() ?? '';
                                final location = e['location']?.toString() ?? '';
                                return ListTile(
                                  leading: const Icon(Icons.event),
                                  title: Text(title),
                                  subtitle: Text([club, location].where((s) => s.isNotEmpty).join(' • ')),
                                  onTap: () {
                                    Navigator.of(context).push(MaterialPageRoute(
                                      builder: (_) => EventDetailPage(eventId: idStr),
                                    ));
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openCreateEventDialog(_selectedDay ?? DateTime.now()),
        icon: const Icon(Icons.add),
        label: const Text('Add Event'),
        backgroundColor: Colors.red,
      ),
    );
  }
}