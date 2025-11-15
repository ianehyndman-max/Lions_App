import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:table_calendar/table_calendar.dart';
import 'event_detail_page.dart';
import 'create_event_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  bool _isLoading = true;
  String? _error;
  final Map<DateTime, List<Map<String, dynamic>>> _eventsByDay = {};
  bool _isAdmin = false;

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    debugPrint('DEBUG: CalendarPage initState');
    _loadAdminFlag();
    _fetchEvents();
  }

  DateTime _onlyDate(DateTime d) => DateTime(d.year, d.month, d.day);

  String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _fetchEvents() async {
    debugPrint('DEBUG: CalendarPage _loadCalendar start');
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final res = await http.get(Uri.parse('$apiBase/events'));
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

  Future<void> _loadAdminFlag() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _isAdmin = prefs.getBool('is_admin') ?? false);
  }

  Future<void> _sendEventEmailsFromCalendar(String eventId) async {
    try {
      await http.post(
        Uri.parse('http://localhost:8080/events/$eventId/notify'),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (_) {}
  }

    Future<void> _openCreateEventDialogFromCalendar(DateTime day) async {
    final result = await showCreateEventDialog(
      context,
      initialDate: day,
      showSendEmailsToggle: true,  // user can choose
      defaultSendEmails: false,    // default OFF on Calendar
    );
    if (!mounted || result == null) return;

    await _fetchEvents();

   if (result.sendEmails) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EventDetailPage(
          eventId: int.tryParse(result.eventId) ?? result.eventId,
          autoOpenNewEventPreview: true, // <-- use NEW event preview
        ),
      ),
    );
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ Event created')),
    );
  }
}



  @override
  Widget build(BuildContext context) {
    debugPrint('DEBUG: CalendarPage build');
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
            onPressed: () => _openCreateEventDialogFromCalendar(_selectedDay ?? DateTime.now()), // <-- fix
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
      floatingActionButton: _isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _openCreateEventDialogFromCalendar(_focusedDay),
              icon: const Icon(Icons.add),
              label: const Text('Create Event'),
              backgroundColor: Colors.red,
            )
          : null,
      );
  }
}