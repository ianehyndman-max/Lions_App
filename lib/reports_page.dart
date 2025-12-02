import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';
import 'api_client.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  bool _loading = false;
  String? _error;
  int? _userClubId;
  bool _isSuper = false;

  // Report data
  Map<String, dynamic>? _eventStats;
  Map<String, dynamic>? _volunteerStats;
  Map<String, dynamic>? _fillRateStats;

  // Filters
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now().add(const Duration(days: 30));
  int? _filterClubId;
  List<dynamic> _clubs = [];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userClubId = prefs.getInt('club_id');
      _isSuper = prefs.getBool('is_super') ?? false;
      _filterClubId = _userClubId; // Default to user's club
    });
    
    if (_isSuper) {
      await _loadClubs();
    }
    
    _loadReports();
  }

  Future<void> _loadClubs() async {
    try {
      final res = await http.get(Uri.parse('$apiBase/clubs'));
      if (res.statusCode == 200) {
        setState(() => _clubs = json.decode(res.body) as List);
      }
    } catch (e) {
      debugPrint('ERROR loading clubs: $e');
    }
  }

  Future<void> _loadReports() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final params = <String, String>{
        'start_date': _startDate.toIso8601String().split('T').first,
        'end_date': _endDate.toIso8601String().split('T').first,
      };
      
      if (_filterClubId != null) {
        params['club_id'] = _filterClubId.toString();
      }

      final qs = params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');

      // Load all three reports in parallel
      final results = await Future.wait([
        ApiClient.get('/reports/events?$qs'),
        ApiClient.get('/reports/volunteers?$qs'),
        ApiClient.get('/reports/fill_rates?$qs'),
      ]);

      setState(() {
        _eventStats = results[0].statusCode == 200 ? json.decode(results[0].body) : null;
        _volunteerStats = results[1].statusCode == 200 ? json.decode(results[1].body) : null;
        _fillRateStats = results[2].statusCode == 200 ? json.decode(results[2].body) : null;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error loading reports: $e';
        _loading = false;
      });
    }
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _loadReports();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        backgroundColor: Colors.red,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadReports,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Filters
                      _buildFilters(),
                      const SizedBox(height: 24),
                      
                      // Event Statistics
                      _buildEventStats(),
                      const SizedBox(height: 24),
                      
                      // Volunteer Statistics
                      _buildVolunteerStats(),
                      const SizedBox(height: 24),
                      
                      // Fill Rate Statistics
                      _buildFillRateStats(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildFilters() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Filters', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              children: [
                // Date Range
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDateRange,
                    icon: const Icon(Icons.date_range),
                    label: Text(
                      '${_startDate.toIso8601String().split('T').first} to ${_endDate.toIso8601String().split('T').first}',
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                
                // Club Filter (super only)
                if (_isSuper)
                  Expanded(
                    child: DropdownButtonFormField<int?>(
                      value: _filterClubId,
                      decoration: const InputDecoration(
                        labelText: 'Club',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('All Clubs')),
                        ..._clubs.map((c) => DropdownMenuItem<int?>(
                              value: int.tryParse(c['id'].toString()),
                              child: Text(c['name']?.toString() ?? ''),
                            )),
                      ],
                      onChanged: (val) {
                        setState(() => _filterClubId = val);
                        _loadReports();
                      },
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventStats() {
    if (_eventStats == null) return const SizedBox.shrink();

    final totalEvents = _eventStats!['total_events'] ?? 0;
    final byType = (_eventStats!['by_type'] as List?) ?? [];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.event, color: Colors.red),
                const SizedBox(width: 8),
                const Text('Event Statistics', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(),
            Text('Total Events: $totalEvents', style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 12),
            const Text('Events by Type:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...byType.map((item) => Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(item['event_type']?.toString() ?? 'Unknown'),
                      Chip(label: Text(item['count']?.toString() ?? '0')),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildVolunteerStats() {
    if (_volunteerStats == null) return const SizedBox.shrink();

    final totalHours = _volunteerStats!['total_hours'] ?? 0;
    final topVolunteers = (_volunteerStats!['top_volunteers'] as List?) ?? [];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.people, color: Colors.blue),
                const SizedBox(width: 8),
                const Text('Volunteer Statistics', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(),
            Text('Total Volunteer Hours: ${totalHours.toStringAsFixed(1)}', style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 12),
            const Text('Top Volunteers:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...topVolunteers.map((v) => ListTile(
                  dense: true,
                  leading: CircleAvatar(child: Text((topVolunteers.indexOf(v) + 1).toString())),
                  title: Text(v['name']?.toString() ?? 'Unknown'),
                  trailing: Text('${v['hours']?.toString() ?? '0'} hrs'),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildFillRateStats() {
    if (_fillRateStats == null) return const SizedBox.shrink();

    final overallRate = _fillRateStats!['overall_fill_rate'] ?? 0;
    final byEvent = (_fillRateStats!['by_event'] as List?) ?? [];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.assessment, color: Colors.green),
                const SizedBox(width: 8),
                const Text('Fill Rate Statistics', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(),
            Text('Overall Fill Rate: ${(overallRate * 100).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 12),
            const Text('By Event:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...byEvent.map((e) {
              final fillRate = (e['fill_rate'] ?? 0) * 100;
              return ListTile(
                dense: true,
                title: Text('${e['event_type']} - ${e['date']}'),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: fillRate >= 80 ? Colors.green : fillRate >= 50 ? Colors.orange : Colors.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${fillRate.toStringAsFixed(0)}%',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}