import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'config.dart';

class CreateEventResult {
  final String eventId;
  final bool sendEmails;
  CreateEventResult({required this.eventId, required this.sendEmails});
}

Future<CreateEventResult?> showCreateEventDialog(
  BuildContext context, {
  DateTime? initialDate,
  bool showSendEmailsToggle = false, // Events page: true, Calendar: true
  bool defaultSendEmails = false,    // Events page: true, Calendar: false
}) async {
  try {
    debugPrint('DEBUG: CreateEventDialog loading lookups from $apiBase');
    final etRes = await http.get(Uri.parse('$apiBase/event_types'));
    final clRes = await http.get(Uri.parse('$apiBase/clubs'));
    debugPrint('DEBUG: CreateEventDialog lookup status: event_types=${etRes.statusCode}, clubs=${clRes.statusCode}');
    if (etRes.statusCode != 200 || clRes.statusCode != 200) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load lookups (${etRes.statusCode}/${clRes.statusCode})')),
        );
      }
      return null;
    }

    final List<Map<String, dynamic>> eventTypes =
        (json.decode(etRes.body) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final List<Map<String, dynamic>> clubs =
        (json.decode(clRes.body) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

    int? eventTypeId = eventTypes.isNotEmpty ? int.tryParse(eventTypes.first['id'].toString()) : null;
    int? clubId = clubs.isNotEmpty ? int.tryParse(clubs.first['id'].toString()) : null;
    DateTime date = initialDate ?? DateTime.now();
    final locationCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    final List<Map<String, TextEditingController>> roleRows = [];
    bool sendEmails = defaultSendEmails;

    bool isOtherSelected() {
      final name = eventTypes
          .firstWhere((e) => e['id'].toString() == (eventTypeId?.toString() ?? ''), orElse: () => const {})
          .cast<String, dynamic>()['name']
          ?.toString()
          .toLowerCase();
      return eventTypeId?.toString() == '4' || name == 'other';
    }

    String? createdId;

    await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          void addRoleRow() {
            roleRows.add({'name': TextEditingController(), 'in': TextEditingController(), 'out': TextEditingController()});
            setState(() {});
          }

          void removeRoleRow(int i) {
            roleRows[i]['name']!.dispose();
            roleRows[i]['in']!.dispose();
            roleRows[i]['out']!.dispose();
            roleRows.removeAt(i);
            setState(() {});
          }

          return AlertDialog(
            title: const Text('Create Event'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    value: eventTypeId,
                    decoration: const InputDecoration(labelText: 'Event Type'),
                    items: eventTypes
                        .map((e) => DropdownMenuItem<int>(
                              value: int.tryParse(e['id'].toString()),
                              child: Text(e['name']?.toString() ?? 'Type'),
                            ))
                        .where((e) => e.value != null)
                        .cast<DropdownMenuItem<int>>()
                        .toList(),
                    onChanged: (v) => setState(() => eventTypeId = v),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    value: clubId,
                    decoration: const InputDecoration(labelText: 'Club'),
                    items: clubs
                        .map((c) => DropdownMenuItem<int>(
                              value: int.tryParse(c['id'].toString()),
                              child: Text(c['name']?.toString() ?? 'Club'),
                            ))
                        .where((e) => e.value != null)
                        .cast<DropdownMenuItem<int>>()
                        .toList(),
                    onChanged: (v) => setState(() => clubId = v),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: Text(date.toIso8601String().split('T').first)),
                      TextButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: date,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) setState(() => date = picked);
                        },
                        icon: const Icon(Icons.calendar_today),
                        label: const Text('Pick date'),
                      ),
                    ],
                  ),
                  TextField(controller: locationCtrl, decoration: const InputDecoration(labelText: 'Location')),
                  const SizedBox(height: 8),
                  TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notes')),
                  if (isOtherSelected()) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text('Roles', style: TextStyle(fontWeight: FontWeight.bold)),
                        const Spacer(),
                        OutlinedButton.icon(onPressed: addRoleRow, icon: const Icon(Icons.add), label: const Text('Add Role')),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (roleRows.isEmpty)
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('No roles added yet', style: TextStyle(color: Colors.grey)),
                      )
                    else
                      Column(
                        children: List.generate(roleRows.length, (i) {
                          final r = roleRows[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Expanded(flex: 4, child: TextField(controller: r['name'], decoration: const InputDecoration(labelText: 'Role name'))),
                                const SizedBox(width: 8),
                                Expanded(flex: 3, child: TextField(controller: r['in'], decoration: const InputDecoration(labelText: 'Time in (HH:mm)'))),
                                const SizedBox(width: 8),
                                Expanded(flex: 3, child: TextField(controller: r['out'], decoration: const InputDecoration(labelText: 'Time out (HH:mm)'))),
                                IconButton(tooltip: 'Remove', icon: const Icon(Icons.close, color: Colors.red), onPressed: () => removeRoleRow(i)),
                              ],
                            ),
                          );
                        }),
                      ),
                  ],
                  if (showSendEmailsToggle) ...[
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('Send emails now'),
                      value: sendEmails,
                      onChanged: (v) => setState(() => sendEmails = v ?? defaultSendEmails),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(
                onPressed: () async {
                  if (eventTypeId == null || clubId == null) return;

                  final body = <String, dynamic>{
                    'event_type_id': eventTypeId,
                    'lions_club_id': clubId,
                    'event_date': date.toIso8601String().split('T').first,
                    'location': locationCtrl.text.trim(),
                    'notes': notesCtrl.text.trim(),
                  };
                  if (isOtherSelected() && roleRows.isNotEmpty) {
                    body['roles'] = roleRows
                        .map((r) => {
                              'role_name': r['name']!.text.trim(),
                              'time_in': r['in']!.text.trim(),
                              'time_out': r['out']!.text.trim(),
                            })
                        .where((m) => (m['role_name'] as String).isNotEmpty)
                        .toList();
                  }

                  debugPrint('DEBUG: CreateEventDialog creating event (body keys=${body.keys.length})');
                  final res = await http.post(
                    Uri.parse('$apiBase/events'),
                    headers: {'Content-Type': 'application/json'},
                    body: json.encode(body),
                  );
                  debugPrint('DEBUG: CreateEventDialog create status=${res.statusCode} body=${res.body}');

                  if (res.statusCode == 201 || res.statusCode == 200) {
                    try {
                      final id = (json.decode(res.body) as Map<String, dynamic>)['id'];
                      createdId = id?.toString();
                    } catch (_) {}
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  } else {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Failed: ${res.body}')));
                    }
                  }
                },
                child: const Text('Create'),
              ),
            ],
          );
        },
      ),
    );

    if (createdId == null) return null;
    return CreateEventResult(eventId: createdId!, sendEmails: sendEmails);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
    return null;
  }
}