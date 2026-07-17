import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'api_client.dart';
import 'auth_store.dart';
import 'conference_ideas_page.dart';

class ConferencePage extends StatefulWidget {
  const ConferencePage({super.key});

  @override
  State<ConferencePage> createState() => _ConferencePageState();
}

class _ConferencePageState extends State<ConferencePage> {
  Map<String, dynamic> _conference = {};
  bool _isLoading = true;
  bool _canEdit = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadConference();
  }

  Future<void> _loadConference() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final permissions = await Future.wait([
        AuthStore.isSuper(),
        AuthStore.isConferenceMember(),
      ]);
      _canEdit = permissions[0] || permissions[1];

      final res = await ApiClient.get('/conference');
      if (res.statusCode != 200) {
        throw Exception('Failed to load conference: ${res.body}');
      }

      _conference = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _displayText(String key, {String empty = 'Not set yet'}) {
    final value = (_conference[key] ?? '').toString().trim();
    return value.isEmpty ? empty : value;
  }

  String _displayDate() {
    final raw = (_conference['conference_date'] ?? '').toString().trim();
    if (raw.isEmpty) return 'Not set yet';
    final date = DateTime.tryParse(raw);
    if (date == null) return raw;
    return DateFormat('d MMMM yyyy').format(date);
  }

  Future<void> _openEditDialog() async {
    final titleCtrl = TextEditingController(text: _displayText('title', empty: 'Conference'));
    final themeCtrl = TextEditingController(text: _displayText('theme', empty: ''));
    final locationsCtrl = TextEditingController(text: _displayText('locations_notes', empty: ''));
    final breakoutCtrl = TextEditingController(text: _displayText('breakout_sessions_notes', empty: ''));
    final notesCtrl = TextEditingController(text: _displayText('general_notes', empty: ''));
    DateTime? selectedDate = DateTime.tryParse(
      (_conference['conference_date'] ?? '').toString(),
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Edit Conference'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(labelText: 'Title'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    readOnly: true,
                    controller: TextEditingController(
                      text: selectedDate == null
                          ? ''
                        : DateFormat('yyyy-MM-dd').format(selectedDate!),
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Conference Date',
                      suffixIcon: Icon(Icons.calendar_today),
                    ),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: selectedDate ?? DateTime.now(),
                        firstDate: DateTime(2026),
                        lastDate: DateTime(2035),
                      );
                      if (picked != null) {
                        setDlg(() => selectedDate = picked);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: themeCtrl,
                    decoration: const InputDecoration(labelText: 'Theme'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: locationsCtrl,
                    decoration: const InputDecoration(labelText: 'Possible Locations'),
                    minLines: 3,
                    maxLines: 6,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: breakoutCtrl,
                    decoration: const InputDecoration(labelText: 'Breakout Sessions'),
                    minLines: 3,
                    maxLines: 6,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: notesCtrl,
                    decoration: const InputDecoration(labelText: 'General Notes'),
                    minLines: 4,
                    maxLines: 10,
                  ),
                ],
              ),
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
      ),
    );

    if (ok != true) return;

    final res = await ApiClient.put('/conference', body: {
      'title': titleCtrl.text.trim(),
      'conference_date': selectedDate == null
          ? null
          : DateFormat('yyyy-MM-dd').format(selectedDate!),
      'theme': themeCtrl.text.trim(),
      'locations_notes': locationsCtrl.text.trim(),
      'breakout_sessions_notes': breakoutCtrl.text.trim(),
      'general_notes': notesCtrl.text.trim(),
    });

    if (!mounted) return;
    if (res.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Conference updated')),
      );
      _loadConference();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: ${res.body}')),
      );
    }
  }

  Widget _buildSection({
    required IconData icon,
    required String title,
    required String content,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.red),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(content),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Conference'),
        backgroundColor: Colors.red,
        actions: [
          IconButton(
            tooltip: 'Conference Ideas',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ConferenceIdeasPage()),
              );
            },
            icon: const Icon(Icons.lightbulb_outline),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadConference,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _displayText('title', empty: 'Conference'),
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                const Icon(Icons.event, color: Colors.red),
                                const SizedBox(width: 8),
                                Text('Date: ${_displayDate()}'),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.palette_outlined, color: Colors.red),
                                const SizedBox(width: 8),
                                Expanded(child: Text('Theme: ${_displayText('theme')}')),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildSection(
                      icon: Icons.place_outlined,
                      title: 'Possible Locations',
                      content: _displayText('locations_notes'),
                    ),
                    _buildSection(
                      icon: Icons.schedule,
                      title: 'Breakout Sessions',
                      content: _displayText('breakout_sessions_notes'),
                    ),
                    _buildSection(
                      icon: Icons.note_alt_outlined,
                      title: 'General Notes',
                      content: _displayText('general_notes'),
                    ),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Last updated by ${(_conference['last_updated_by_name'] ?? 'Unknown').toString()}${(_conference['updated_at'] ?? '').toString().isEmpty ? '' : ' on ${_conference['updated_at']}'}',
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ),
                    ),
                  ],
                ),
      floatingActionButton: _canEdit
          ? FloatingActionButton.extended(
              onPressed: _openEditDialog,
              backgroundColor: Colors.red,
              icon: const Icon(Icons.edit),
              label: const Text('Edit Conference'),
            )
          : null,
    );
  }
}
