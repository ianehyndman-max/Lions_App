import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

Future<String?> showCreateEventDialog(
  BuildContext context, {
  DateTime? initialDate,
}) async {
  // Load lookups first
  final etRes = await http.get(Uri.parse('http://localhost:8080/event_types'));
  final clRes = await http.get(Uri.parse('http://localhost:8080/clubs'));
  if (etRes.statusCode != 200 || clRes.statusCode != 200) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
       SnackBar(content: Text('Failed to load lookups (${etRes.statusCode}/${clRes.statusCode})')),
     );
    }
    return null;
  }
  final List eventTypes = json.decode(etRes.body) as List;
  final List clubs = json.decode(clRes.body) as List;

  int? eventTypeId = eventTypes.isNotEmpty ? int.tryParse(eventTypes.first['id'].toString()) : null;
  int? clubId = clubs.isNotEmpty ? int.tryParse(clubs.first['id'].toString()) : null;
  DateTime date = initialDate ?? DateTime.now();
  final locationCtrl = TextEditingController();
  final notesCtrl = TextEditingController();

  final List<Map<String, TextEditingController>> roleRows = [];

  bool isOtherSelected() {
    final name = eventTypes.firstWhere(
      (e) => e['id'].toString() == (eventTypeId?.toString() ?? ''),
      orElse: () => {},
    )['name']?.toString();
    return eventTypeId?.toString() == '4' || (name?.toLowerCase() == 'other');
  }

  String? createdId;

  await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        void addRoleRow() {
          roleRows.add({
            'name': TextEditingController(),
            'in': TextEditingController(),
            'out': TextEditingController(),
          });
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
                // Event type
                DropdownButtonFormField<int>(
                  value: eventTypeId,
                  items: eventTypes
                      .map((e) => DropdownMenuItem<int>(
                            value: int.tryParse(e['id'].toString()),
                            child: Text(e['name']?.toString() ?? 'Type'),
                          ))
                      .where((e) => e.value != null)
                      .cast<DropdownMenuItem<int>>()
                      .toList(),
                  onChanged: (v) => setState(() => eventTypeId = v),
                  decoration: const InputDecoration(labelText: 'Event Type'),
                ),
                const SizedBox(height: 8),
                // Club
                DropdownButtonFormField<int>(
                  value: clubId,
                  items: clubs
                      .map((c) => DropdownMenuItem<int>(
                            value: int.tryParse(c['id'].toString()),
                            child: Text(c['name']?.toString() ?? 'Club'),
                          ))
                      .where((e) => e.value != null)
                      .cast<DropdownMenuItem<int>>()
                      .toList(),
                  onChanged: (v) => setState(() => clubId = v),
                  decoration: const InputDecoration(labelText: 'Club'),
                ),
                const SizedBox(height: 8),
                // Date
                Row(
                  children: [
                    Expanded(child: Text('${date.toIso8601String().split('T').first}')),
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
                      OutlinedButton.icon(
                        onPressed: addRoleRow,
                        icon: const Icon(Icons.add),
                        label: const Text('Add Role'),
                      ),
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
                              Expanded(
                                flex: 4,
                                child: TextField(controller: r['name'], decoration: const InputDecoration(labelText: 'Role name')),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 3,
                                child: TextField(controller: r['in'], decoration: const InputDecoration(labelText: 'Time in (HH:mm)')),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 3,
                                child: TextField(controller: r['out'], decoration: const InputDecoration(labelText: 'Time out (HH:mm)')),
                              ),
                              IconButton(
                                tooltip: 'Remove',
                                icon: const Icon(Icons.close, color: Colors.red),
                                onPressed: () => removeRoleRow(i),
                              ),
                            ],
                          ),
                        );
                      }),
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

                final res = await http.post(
                  Uri.parse('http://localhost:8080/events'),
                  headers: {'Content-Type': 'application/json'},
                  body: json.encode(body),
                );

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

  return createdId;
}