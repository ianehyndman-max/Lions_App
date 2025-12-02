import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'config.dart';
import 'auth_store.dart';
import 'api_client.dart';

class CreateEventResult {
  final String eventId;
  final bool sendEmails;
  CreateEventResult({required this.eventId, required this.sendEmails});

  @override
  String toString() => 'CreateEventResult(eventId: $eventId, sendEmails: $sendEmails)';
}

Future<CreateEventResult?> showCreateEventDialog(
  BuildContext context, {
  DateTime? initialDate,
  bool showSendEmailsToggle = false,
  bool defaultSendEmails = false,
  int? userClubId,
}) async {
  try {
    final isSuper = await AuthStore.isSuper();

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
    int? clubId = (!isSuper && userClubId != null) 
        ? userClubId 
        : (clubs.isNotEmpty ? int.tryParse(clubs.first['id'].toString()) : null);
    DateTime date = initialDate ?? DateTime.now();
    final locationCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    final List<Map<String, TextEditingController>> roleRows = [];
    bool sendEmails = defaultSendEmails;
    bool loadingTemplates = false;

    bool isOtherSelected() {
      final name = eventTypes
          .firstWhere((e) => e['id'].toString() == (eventTypeId?.toString() ?? ''), orElse: () => const {})
          .cast<String, dynamic>()['name']
          ?.toString()
          .toLowerCase();
      return eventTypeId?.toString() == '4' || name == 'other';
    }

    // NEW: Load templates for selected event type
    Future<void> loadTemplatesForEventType(int typeId, Function setState) async {
      debugPrint('🔵 Loading templates for event type $typeId');
      setState(() => loadingTemplates = true);
      
      try {
        final res = await ApiClient.get('/event_types/$typeId/role_templates');
        debugPrint('🔵 Templates response: ${res.statusCode}');
        
        if (res.statusCode == 200) {
          final templates = json.decode(res.body) as List;
          debugPrint('🔵 Found ${templates.length} templates');
          
          // Clear existing role rows
          for (final row in roleRows) {
            row['name']?.dispose();
            row['in']?.dispose();
            row['out']?.dispose();
          }
          roleRows.clear();
          
          // Add templates as editable rows
          for (final template in templates) {
            final roleName = template['role_name']?.toString() ?? '';
            final timeIn = template['time_in']?.toString() ?? '';
            final timeOut = template['time_out']?.toString() ?? '';
            
            debugPrint('🔵 Adding role: $roleName ($timeIn - $timeOut)');
            
            roleRows.add({
              'name': TextEditingController(text: roleName),
              'in': TextEditingController(text: timeIn),
              'out': TextEditingController(text: timeOut),
            });
          }
          
          debugPrint('🔵 roleRows now has ${roleRows.length} items');
          setState(() => loadingTemplates = false);
        } else {
          debugPrint('❌ Failed to load templates: ${res.statusCode}');
          setState(() => loadingTemplates = false);
        }
      } catch (e) {
        debugPrint('❌ Error loading templates: $e');
        setState(() => loadingTemplates = false);
      }
    }

    String? createdId;

     // NEW: Load templates for initial event type
    if (eventTypeId != null) {
      final initialTypeName = eventTypes
          .firstWhere((e) => e['id'].toString() == eventTypeId.toString(), orElse: () => const {})
          .cast<String, dynamic>()['name']
          ?.toString()
          .toLowerCase();
      
      debugPrint('🔵 Initial event type: $initialTypeName (id: $eventTypeId)');
      
      if (initialTypeName != null && initialTypeName != 'other' && eventTypeId.toString() != '4') {
        // Load templates asynchronously before showing dialog
        debugPrint('🔵 Pre-loading templates for initial event type $eventTypeId');
        final res = await ApiClient.get('/event_types/$eventTypeId/role_templates');
        if (res.statusCode == 200) {
          final templates = json.decode(res.body) as List;
          debugPrint('🔵 Initial load found ${templates.length} templates');
          for (final template in templates) {
            roleRows.add({
              'name': TextEditingController(text: template['role_name']?.toString() ?? ''),
              'in': TextEditingController(text: template['time_in']?.toString() ?? ''),
              'out': TextEditingController(text: template['time_out']?.toString() ?? ''),
            });
          }
        } else {
          debugPrint('🔵 No templates found for initial event type (status: ${res.statusCode})');
        }
      }
    }

    await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          void addRoleRow() {
            roleRows.add({'name': TextEditingController(), 'in': TextEditingController(), 'out': TextEditingController()});
            debugPrint('🔵 Added role row, total: ${roleRows.length}');
            setState(() {});
          }

          void removeRoleRow(int i) {
            roleRows[i]['name']!.dispose();
            roleRows[i]['in']!.dispose();
            roleRows[i]['out']!.dispose();
            roleRows.removeAt(i);
            debugPrint('🔵 Removed role row, total: ${roleRows.length}');
            setState(() {});
          }

          // Add this debug output
          debugPrint('🔵 StatefulBuilder rebuild - roleRows.length: ${roleRows.length}, loadingTemplates: $loadingTemplates');

          return AlertDialog(
            title: const Text('Create Event'),
            content: SizedBox(
              width: 600,
              child: SingleChildScrollView(
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
                      onChanged: (v) async {
                        if (v == null) return;
                        
                        debugPrint('🔵 Event type changed to: $v');
                        
                        // IMPORTANT: Update state AFTER loading templates
                        final newTypeName = eventTypes
                            .firstWhere((e) => e['id'].toString() == v.toString(), orElse: () => const {})
                            .cast<String, dynamic>()['name']
                            ?.toString()
                            .toLowerCase();
                        
                        debugPrint('🔵 New type name: $newTypeName');
                        
                        final isOther = v.toString() == '4' || newTypeName == 'other';
                        
                        if (isOther) {
                          debugPrint('🔵 "Other" selected - clearing roles');
                          // Clear roles for "Other"
                          for (final row in roleRows) {
                            row['name']?.dispose();
                            row['in']?.dispose();
                            row['out']?.dispose();
                          }
                          roleRows.clear();
                          setState(() {
                            eventTypeId = v;
                          });
                        } else {
                          // Load templates for non-Other event types
                          debugPrint('🔵 Non-Other selected - loading templates');
                          
                          // Clear existing first
                          for (final row in roleRows) {
                            row['name']?.dispose();
                            row['in']?.dispose();
                            row['out']?.dispose();
                          }
                          roleRows.clear();
                          
                          setState(() {
                            eventTypeId = v;
                            loadingTemplates = true;
                          });
                          
                          // Load templates
                          try {
                            final res = await ApiClient.get('/event_types/$v/role_templates');
                            debugPrint('🔵 Templates response: ${res.statusCode}');
                            
                            if (res.statusCode == 200) {
                              final templates = json.decode(res.body) as List;
                              debugPrint('🔵 Found ${templates.length} templates');
                              
                              // Add templates as editable rows
                              for (final template in templates) {
                                final roleName = template['role_name']?.toString() ?? '';
                                final timeIn = template['time_in']?.toString() ?? '';
                                final timeOut = template['time_out']?.toString() ?? '';
                                
                                debugPrint('🔵 Adding role: $roleName ($timeIn - $timeOut)');
                                
                                roleRows.add({
                                  'name': TextEditingController(text: roleName),
                                  'in': TextEditingController(text: timeIn),
                                  'out': TextEditingController(text: timeOut),
                                });
                              }
                              
                              debugPrint('🔵 roleRows now has ${roleRows.length} items');
                            } else {
                              debugPrint('❌ Failed to load templates: ${res.statusCode}');
                            }
                          } catch (e) {
                            debugPrint('❌ Error loading templates: $e');
                          }
                          
                          setState(() {
                            loadingTemplates = false;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      value: clubId,
                      decoration: InputDecoration(
                        labelText: 'Club',
                        suffixIcon: isSuper ? null : const Icon(Icons.lock, size: 16),
                        helperText: isSuper ? null : 'Locked to your club',
                      ),
                      items: clubs
                          .map((c) => DropdownMenuItem<int>(
                                value: int.tryParse(c['id'].toString()),
                                child: Text(c['name']?.toString() ?? 'Club'),
                              ))
                          .where((e) => e.value != null)
                          .cast<DropdownMenuItem<int>>()
                          .toList(),
                      onChanged: isSuper ? (v) => setState(() => clubId = v) : null,
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
                    
                    // Roles section - ADD KEY HERE
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text('Roles', style: TextStyle(fontWeight: FontWeight.bold)),
                        if (roleRows.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Chip(
                              label: Text('${roleRows.length} roles', style: const TextStyle(fontSize: 11)),
                              backgroundColor: Colors.blue.shade50,
                              avatar: const Icon(Icons.edit, size: 14),
                            ),
                          ),
                        const Spacer(),
                        OutlinedButton.icon(
                          onPressed: addRoleRow,
                          icon: const Icon(Icons.add),
                          label: const Text('Add Role'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    
                    if (loadingTemplates)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      )
                    else if (roleRows.isEmpty)
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('No roles defined. Click "Add Role" to create.', style: TextStyle(color: Colors.grey)),
                      )
                    else
                      // Show all role rows with inputs and delete buttons
                      // ADD KEY to force rebuild
                      Column(
                        key: ValueKey('roles_${roleRows.length}'),
                        children: List.generate(roleRows.length, (i) {
                          final r = roleRows[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: TextField(
                                    controller: r['name'],
                                    decoration: const InputDecoration(
                                      labelText: 'Role name',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 2,
                                  child: TextField(
                                    controller: r['in'],
                                    decoration: const InputDecoration(
                                      labelText: 'Time in',
                                      hintText: 'HH:mm',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 2,
                                  child: TextField(
                                    controller: r['out'],
                                    decoration: const InputDecoration(
                                      labelText: 'Time out',
                                      hintText: 'HH:mm',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  tooltip: 'Remove role',
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () => removeRoleRow(i),
                                ),
                              ],
                            ),
                          );
                        }),
                      ),
                    
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

                  // NEW: Debug the body before sending
                  debugPrint('🔵 Body before roles: $body');
                  debugPrint('🔵 eventTypeId=$eventTypeId clubId=$clubId');
                  
                  // NEW: Always send roles array (from templates or custom)
                  if (roleRows.isNotEmpty) {
                    body['roles'] = roleRows
                        .map((r) => {
                              'role_name': r['name']!.text.trim(),
                              'time_in': r['in']!.text.trim(),
                              'time_out': r['out']!.text.trim(),
                            })
                        .where((m) => (m['role_name'] as String).isNotEmpty)
                        .toList();
                  }

                  debugPrint('🔵 Final body to send: ${json.encode(body)}'); // NEW: see exactly what's sent

                  debugPrint('DEBUG: CreateEventDialog creating event (body keys=${body.keys.length})');
                  final res = await http.post(
                    Uri.parse('$apiBase/events'),
                    headers: {'Content-Type': 'application/json'},
                    body: json.encode(body),
                  );
                  debugPrint('DEBUG: CreateEventDialog create status=${res.statusCode} body=${res.body}');

                  if (res.statusCode == 201 || res.statusCode == 200) {
                    try {
                      final responseData = json.decode(res.body) as Map<String, dynamic>;
                      final id = responseData['event_id'] ?? responseData['id'];
                      createdId = id?.toString();
                      debugPrint('DEBUG: CreateEventDialog extracted createdId=$createdId from response');
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
    debugPrint('DEBUG: CreateEventDialog returning CreateEventResult(eventId: $createdId, sendEmails: $sendEmails)');
    return CreateEventResult(eventId: createdId!, sendEmails: sendEmails);
  } catch (e) {
    debugPrint('ERROR: CreateEventDialog exception: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
    return null;
  }
}