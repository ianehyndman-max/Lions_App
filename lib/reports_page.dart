import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';
import 'api_client.dart';
import 'package:intl/intl.dart';

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

  // ✅ FEATURE 1: Event Type Filter
  int? _selectedEventTypeId;
  List<Map<String, dynamic>> _eventTypes = [];
  
  // ✅ FEATURE 2: Predefined Date Ranges
  String _dateRangePreset = 'custom'; // week, month, quarter, year, custom


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

    // ✅ Load event types for filtering
    await _loadEventTypes();
    
    if (_isSuper) {
      await _loadClubs();
    }
    
    _loadReports();
  }

  // ✅ FEATURE 1: Load Event Types
  Future<void> _loadEventTypes() async {
    try {
      final res = await http.get(Uri.parse('${getApiBase()}/event_types'));
      if (res.statusCode == 200) {
        final List<dynamic> data = json.decode(res.body);
        setState(() {
          _eventTypes = data.map((item) {
            return {
              'id': int.parse(item['id'].toString()),
              'name': item['name'],
            };
          }).toList();
        });
      }
    } catch (e) {
      debugPrint('Error loading event types: $e');
    }
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

  // ✅ FEATURE 2: Predefined Date Ranges
  void _setDateRangePreset(String preset) {
    final now = DateTime.now();
    setState(() {
      _dateRangePreset = preset;
      
      switch (preset) {
        case 'week':
          _startDate = now.subtract(Duration(days: now.weekday - 1));
          _endDate = _startDate.add(const Duration(days: 6));
          break;
        case 'month':
          _startDate = DateTime(now.year, now.month, 1);
          _endDate = DateTime(now.year, now.month + 1, 0);
          break;
        case 'quarter':
          final quarter = ((now.month - 1) / 3).floor();
          _startDate = DateTime(now.year, quarter * 3 + 1, 1);
          _endDate = DateTime(now.year, quarter * 3 + 4, 0);
          break;
        case 'year':
          _startDate = DateTime(now.year, 1, 1);
          _endDate = DateTime(now.year, 12, 31);
          break;
        case 'custom':
          // Keep existing dates
          return;
      }
    });
    
    _loadReports();
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

      // ✅ FEATURE 1: Add event type filter
      if (_selectedEventTypeId != null) {
        params['event_type_id'] = _selectedEventTypeId.toString();
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

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );

    if (picked != null) {
      setState(() {
        _dateRangePreset = 'custom'; // ✅ Set preset to custom when manually picking
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _loadReports();
    }
  }

  // ✅ FEATURE 3: Export to CSV
  Future<void> _exportToCSV() async {
    try {
      // Create CSV content
      final csvLines = <String>[];
      
      // Header
      csvLines.add('Lions Club Report');
      csvLines.add('Generated: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}');
      csvLines.add('Period: ${DateFormat('MMM d, y').format(_startDate)} - ${DateFormat('MMM d, y').format(_endDate)}');
      csvLines.add('');
      
      // Event Statistics
      if (_eventStats != null) {
        csvLines.add('EVENT STATISTICS');
        csvLines.add('Total Events,${_eventStats!['total_events']}');
        csvLines.add('');
        csvLines.add('Event Type,Count');
        final byType = (_eventStats!['by_type'] as List?) ?? [];
        for (var item in byType) {
          csvLines.add('${item['event_type']},${item['count']}');
        }
        csvLines.add('');
      }
      
      // Volunteer Statistics
      if (_volunteerStats != null) {
        csvLines.add('VOLUNTEER STATISTICS');
        csvLines.add('Total Hours,${_volunteerStats!['total_hours']}');
        csvLines.add('');
        csvLines.add('Name,Hours');
        final topVolunteers = (_volunteerStats!['top_volunteers'] as List?) ?? [];
        for (var v in topVolunteers) {
          csvLines.add('${v['name']},${v['hours']}');
        }
        csvLines.add('');
      }
      
      // Fill Rate Statistics
      if (_fillRateStats != null) {
        csvLines.add('FILL RATE STATISTICS');
        csvLines.add('Overall Fill Rate,${(_fillRateStats!['overall_fill_rate'] * 100).toStringAsFixed(1)}%');
        csvLines.add('');
        csvLines.add('Event,Date,Fill Rate');
        final byEvent = (_fillRateStats!['by_event'] as List?) ?? [];
        for (var e in byEvent) {
          final fillRate = (e['fill_rate'] ?? 0) * 100;
          csvLines.add('${e['event_type']},${e['date']},${fillRate.toStringAsFixed(1)}%');
        }
      }
      
      final csvContent = csvLines.join('\n');
      
      // For web: trigger download
      // For mobile: share or save to downloads
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('CSV Export ready! (Download feature coming soon)'),
            action: SnackBarAction(
              label: 'Copy',
              onPressed: () {
                // TODO: Copy to clipboard
                debugPrint(csvContent);
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        backgroundColor: Colors.red,
        actions: [
           // ✅ FEATURE 3: Export button
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _exportToCSV,
            tooltip: 'Export CSV',
          ),
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
                      
                      // ✅ FEATURE 4: Summary Statistics Panel
                      _buildSummaryPanel(),
                      const SizedBox(height: 24),
                      
                      // Event Statistics
                      _buildEventStats(),
                      const SizedBox(height: 24),
                      
                      // ✅ FEATURE 5: Member-Specific Reports (Enhanced Volunteer Stats)
                      _buildVolunteerStats(),
                      const SizedBox(height: 24),
                      
                      // Fill Rate Statistics
                      _buildFillRateStats(),
                      const SizedBox(height: 24),
                      
                      // ✅ FEATURE 6: Club Comparison (Super Admin Only)
                      if (_isSuper) _buildClubComparison(),
                    ],
                  ),
                ),
    );
  }

  // ✅ FEATURE 4: Summary Statistics Panel
  Widget _buildSummaryPanel() {
    if (_eventStats == null && _volunteerStats == null && _fillRateStats == null) {
      return const SizedBox.shrink();
    }

    final totalEvents = _eventStats?['total_events'] ?? 0;
    final totalHours = _volunteerStats?['total_hours'] ?? 0;
    final overallFillRate = _fillRateStats?['overall_fill_rate'] ?? 0;
    final activeMembers = _volunteerStats?['active_members'] ?? 0;

    return Card(
      elevation: 4,
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics, color: Colors.blue.shade700, size: 28),
                const SizedBox(width: 12),
                Text(
                  'Summary',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 24,
              runSpacing: 16,
              children: [
                _buildSummaryStat(
                  'Total Events',
                  totalEvents.toString(),
                  Icons.event,
                  Colors.red,
                ),
                _buildSummaryStat(
                  'Total Hours',
                  totalHours.toStringAsFixed(1),
                  Icons.access_time,
                  Colors.orange,
                ),
                _buildSummaryStat(
                  'Active Members',
                  activeMembers.toString(),
                  Icons.people,
                  Colors.blue,
                ),
                _buildSummaryStat(
                  'Fill Rate',
                  '${(overallFillRate * 100).toStringAsFixed(1)}%',
                  Icons.trending_up,
                  overallFillRate >= 0.8 ? Colors.green : Colors.orange,
                ),
                if (totalEvents > 0)
                  _buildSummaryStat(
                    'Avg Hours/Event',
                    (totalHours / totalEvents).toStringAsFixed(1),
                    Icons.calculate,
                    Colors.purple,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryStat(String label, String value, IconData icon, Color color) {
    return Container(
      constraints: const BoxConstraints(minWidth: 140),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: Colors.grey[700],
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ✅ FEATURE 6: Club Comparison Report (Super Admin Only)
  Widget _buildClubComparison() {
    return FutureBuilder<http.Response>(
      future: _loadClubComparison(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        if (snapshot.hasError || snapshot.data?.statusCode != 200) {
          return const SizedBox.shrink();
        }

        final data = json.decode(snapshot.data!.body) as Map<String, dynamic>;
        final clubs = (data['clubs'] as List?) ?? [];

        if (clubs.isEmpty) {
          return const SizedBox.shrink();
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.compare, color: Colors.purple),
                    const SizedBox(width: 8),
                    const Text(
                      'Club Comparison',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const Divider(),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Club Name')),
                      DataColumn(label: Text('Events'), numeric: true),
                      DataColumn(label: Text('Members'), numeric: true),
                      DataColumn(label: Text('Hours'), numeric: true),
                      DataColumn(label: Text('Fill Rate')),
                    ],
                    rows: clubs.map<DataRow>((club) {
                      final fillRate = (club['fill_rate'] ?? 0) * 100;
                      return DataRow(cells: [
                        DataCell(Text(club['name']?.toString() ?? 'Unknown')),
                        DataCell(Text(club['total_events']?.toString() ?? '0')),
                        DataCell(Text(club['active_members']?.toString() ?? '0')),
                        DataCell(Text(club['total_hours']?.toStringAsFixed(1) ?? '0')),
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: fillRate >= 80
                                  ? Colors.green
                                  : fillRate >= 50
                                      ? Colors.orange
                                      : Colors.red,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${fillRate.toStringAsFixed(0)}%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ]);
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<http.Response> _loadClubComparison() async {
    final params = <String, String>{
      'start_date': _startDate.toIso8601String().split('T').first,
      'end_date': _endDate.toIso8601String().split('T').first,
    };
    
    if (_selectedEventTypeId != null) {
      params['event_type_id'] = _selectedEventTypeId.toString();
    }

    final qs = params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
    return ApiClient.get('/reports/club_comparison?$qs');
  }

  // Update _buildVolunteerStats to include more detail (FEATURE 5):
  Widget _buildVolunteerStats() {
    if (_volunteerStats == null) return const SizedBox.shrink();

    final totalHours = _volunteerStats!['total_hours'] ?? 0;
    final topVolunteers = (_volunteerStats!['top_volunteers'] as List?) ?? [];
    final activeMembers = _volunteerStats!['active_members'] ?? 0;
    final avgHoursPerMember = activeMembers > 0 ? totalHours / activeMembers : 0;

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
            
            // ✅ Enhanced summary stats
            Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                _buildInlineStatPair('Total Hours:', totalHours.toStringAsFixed(1)),
                _buildInlineStatPair('Active Members:', activeMembers.toString()),
                _buildInlineStatPair('Avg Hours/Member:', avgHoursPerMember.toStringAsFixed(1)),
              ],
            ),
            
            const SizedBox(height: 20),
            const Text('Top Volunteers:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            
            if (topVolunteers.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No volunteer data available', style: TextStyle(color: Colors.grey)),
              )
            else
              ...topVolunteers.asMap().entries.map((entry) {
                final index = entry.key;
                final v = entry.value;
                final hours = double.tryParse(v['hours']?.toString() ?? '0') ?? 0;
                final eventCount = v['event_count'] ?? 0;
                
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    backgroundColor: index < 3 ? Colors.amber : Colors.grey,
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Text(
                    v['name']?.toString() ?? 'Unknown',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text('$eventCount events'),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      '${hours.toStringAsFixed(1)} hrs',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade900,
                      ),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildInlineStatPair(String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(color: Colors.grey[700])),
        const SizedBox(width: 6),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ],
    );
  }


  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.all(12.0), // ✅ Reduced from 16 to 12
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Filters', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          
          // ✅ FEATURE 2: Predefined Date Range Chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('This Week'),
                selected: _dateRangePreset == 'week',
                onSelected: (_) => _setDateRangePreset('week'),
              ),
              ChoiceChip(
                label: const Text('This Month'),
                selected: _dateRangePreset == 'month',
                onSelected: (_) => _setDateRangePreset('month'),
              ),
              ChoiceChip(
                label: const Text('This Quarter'),
                selected: _dateRangePreset == 'quarter',
                onSelected: (_) => _setDateRangePreset('quarter'),
              ),
              ChoiceChip(
                label: const Text('This Year'),
                selected: _dateRangePreset == 'year',
                onSelected: (_) => _setDateRangePreset('year'),
              ),
              ChoiceChip(
                label: const Text('Custom'),
                selected: _dateRangePreset == 'custom',
                onSelected: (_) => _selectDateRange(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Date Range + Filters Row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Date Range Display
                OutlinedButton.icon(
                  onPressed: _selectDateRange,
                  icon: const Icon(Icons.date_range, size: 18),
                  label: Text(
                    '${DateFormat('MMM d, y').format(_startDate)} - ${DateFormat('MMM d, y').format(_endDate)}',
                    style: const TextStyle(fontSize: 13),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                const SizedBox(width: 12),
                
                // ✅ FEATURE 1: Event Type Filter (PopupMenuButton - no strikethrough)
                SizedBox(
                  width: 180,
                  child: PopupMenuButton<int?>(
                    initialValue: _selectedEventTypeId,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(4),
                        color: Colors.white,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              _selectedEventTypeId == null 
                                  ? 'All Types' 
                                  : _eventTypes.firstWhere(
                                      (t) => t['id'] == _selectedEventTypeId, 
                                      orElse: () => {'name': 'All Types'}
                                    )['name'],
                              style: const TextStyle(fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Icon(Icons.arrow_drop_down, size: 20),
                        ],
                      ),
                    ),
                    itemBuilder: (context) => [
                      const PopupMenuItem<int?>(
                        value: null,
                        child: Text('All Types'),
                      ),
                      ..._eventTypes.map((type) => PopupMenuItem<int?>(
                        value: type['id'],
                        child: Text(type['name']),
                      )),
                    ],
                    onSelected: (val) {
                      setState(() => _selectedEventTypeId = val);
                      _loadReports();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                
                // ✅ Club Filter (super only) - PopupMenuButton to match Event Type
                if (_isSuper)
                  SizedBox(
                    width: 180,
                    child: PopupMenuButton<int?>(
                      initialValue: _filterClubId,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(4),
                          color: Colors.white,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                _filterClubId == null 
                                    ? 'All Clubs' 
                                    : _clubs.firstWhere(
                                        (c) => int.tryParse(c['id'].toString()) == _filterClubId, 
                                        orElse: () => {'name': 'All Clubs'}
                                      )['name']?.toString() ?? 'All Clubs',
                                style: const TextStyle(fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down, size: 20),
                          ],
                        ),
                      ),
                      itemBuilder: (context) => [
                        const PopupMenuItem<int?>(
                          value: null,
                          child: Text('All Clubs'),
                        ),
                        // ✅ Deduplicate clubs by ID
                        ...{for (var c in _clubs) int.tryParse(c['id'].toString()): c}
                            .entries
                            .map((entry) => PopupMenuItem<int?>(
                              value: entry.key,
                              child: Text(
                                entry.value['name']?.toString() ?? '',
                                overflow: TextOverflow.ellipsis,
                              ),
                            )),
                      ],
                      onSelected: (val) {
                        setState(() => _filterClubId = val);
                        _loadReports();
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
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