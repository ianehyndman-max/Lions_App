import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config.dart';

class EventTypeManagementPage extends StatefulWidget {
  final int memberId;

  const EventTypeManagementPage({super.key, required this.memberId});

  @override
  State<EventTypeManagementPage> createState() => _EventTypeManagementPageState();
}

class _EventTypeManagementPageState extends State<EventTypeManagementPage> {
  List<Map<String, dynamic>> _eventTypes = [];
  int? _selectedEventTypeId;
  List<Map<String, dynamic>> _roleTemplates = [];
  bool _loading = true;
  bool _loadingTemplates = false;

  @override
  void initState() {
    super.initState();
    _loadEventTypes();
  }

  Future<void> _loadEventTypes() async {
    setState(() => _loading = true);
    try {
      final res = await http.get(Uri.parse('$apiBase/event_types'));
      if (res.statusCode == 200) {
        final List<dynamic> data = json.decode(res.body);
        setState(() {
          // ✅ Convert id to int if it's a string
          _eventTypes = data.map((item) {
            return {
              'id': int.parse(item['id'].toString()),
              'name': item['name'],
            };
          }).toList();
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading event types: $e');
      setState(() => _loading = false);
    }
  }

  Future<void> _loadRoleTemplates(int eventTypeId) async {
    print('🔵 Loading role templates for event type $eventTypeId'); // ✅ ADD THIS
    setState(() {
      _selectedEventTypeId = eventTypeId;
      _loadingTemplates = true;
    });

    try {
      final url = '$apiBase/event_types/$eventTypeId/role_templates';
      print('🔵 Fetching from: $url'); // ✅ ADD THIS
      
      final res = await http.get(
        Uri.parse(url),
        headers: {'X-Member-Id': widget.memberId.toString()},
      );

      print('🔵 Response status: ${res.statusCode}'); // ✅ ADD THIS
      print('🔵 Response body: ${res.body}'); // ✅ ADD THIS

      if (res.statusCode == 200) {
        final data = json.decode(res.body) as List;
        setState(() {
          // ✅ Convert id to int if it's a string
          _roleTemplates = data.map((item) {
            return {
              'id': int.parse(item['id'].toString()),
              'role_name': item['role_name'],
              'time_in': item['time_in'],
              'time_out': item['time_out'],
            };
          }).toList();
          _loadingTemplates = false;
        });
        print('🔵 Loaded ${_roleTemplates.length} role templates');
      } else {
        throw Exception('Failed: ${res.body}');
      }
    } catch (e) {
      print('❌ Error loading role templates: $e'); // ✅ ADD THIS
      setState(() => _loadingTemplates = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _addOrEditEventType({Map<String, dynamic>? existing}) async {
  final nameController = TextEditingController(text: existing?['name'] ?? '');
  
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(existing == null ? 'Add Event Type' : 'Edit Event Type'),
      content: TextField(
        controller: nameController,
        decoration: const InputDecoration(labelText: 'Event Type Name'),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            final name = nameController.text.trim();
            if (name.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Name required')),
              );
              return;
            }

            try {
              final body = {'name': name};
              
              final http.Response res;
              if (existing == null) {
                // CREATE
                res = await http.post(
                  Uri.parse('$apiBase/event_types'),
                  headers: {
                    'Content-Type': 'application/json',
                    'X-Member-Id': widget.memberId.toString(),
                  },
                  body: json.encode(body),
                );
              } else {
                // UPDATE
                res = await http.put(
                  Uri.parse('$apiBase/event_types/${existing['id']}'),
                  headers: {
                    'Content-Type': 'application/json',
                    'X-Member-Id': widget.memberId.toString(),
                  },
                  body: json.encode(body),
                );
              }

              if (res.statusCode == 200) {
                if (ctx.mounted) Navigator.pop(ctx, true);
              } else {
                throw Exception('Failed: ${res.body}');
              }
            } catch (e) {
              if (ctx.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: $e')),
                );
              }
            }
          },
          child: Text(existing == null ? 'Add' : 'Save'),
        ),
      ],
    ),
  );

  if (result == true) {
    await _loadEventTypes();
  }
}

  Future<void> _addOrEditRoleTemplate({Map<String, dynamic>? existing}) async {
    if (_selectedEventTypeId == null) return;

    final nameController = TextEditingController(text: existing?['role_name'] ?? '');
    final timeInController = TextEditingController(text: existing?['time_in'] ?? '');
    final timeOutController = TextEditingController(text: existing?['time_out'] ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Add Role Template' : 'Edit Role Template'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Role Name'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: timeInController,
              decoration: const InputDecoration(
                labelText: 'Start Time (e.g., 08:30:00 or "Start")',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: timeOutController,
              decoration: const InputDecoration(
                labelText: 'End Time (e.g., 11:30:00 or "Finish")',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final roleName = nameController.text.trim();
              final timeIn = timeInController.text.trim();
              final timeOut = timeOutController.text.trim();

              if (roleName.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Role name required')),
                );
                return;
              }

              try {
                final body = {
                  'id': existing?['id'],
                  'role_name': roleName,
                  'time_in': timeIn,
                  'time_out': timeOut,
                };

                final res = await http.post(
                  Uri.parse('$apiBase/event_types/$_selectedEventTypeId/role_templates'),
                  headers: {
                    'Content-Type': 'application/json',
                    'X-Member-Id': widget.memberId.toString(),
                  },
                  body: json.encode(body),
                );

                if (res.statusCode == 200) {
                  Navigator.pop(ctx, true);
                } else {
                  throw Exception('Failed: ${res.body}');
                }
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              }
            },
            child: Text(existing == null ? 'Add' : 'Save'),
          ),
        ],
      ),
    );

    if (result == true) {
      _loadRoleTemplates(_selectedEventTypeId!);
    }
  }

  Future<void> _deleteRoleTemplate(int templateId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Role Template'),
        content: const Text('Are you sure you want to delete this role template?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final res = await http.delete(
          Uri.parse('$apiBase/role_templates/$templateId'),
          headers: {'X-Member-Id': widget.memberId.toString()},
        );

        if (res.statusCode == 204) {
          _loadRoleTemplates(_selectedEventTypeId!);
        } else {
          throw Exception('Failed: ${res.body}');
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Event Type & Role Management'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: MediaQuery.of(context).size.width,
                ),
                child: IntrinsicWidth(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Left panel: Event Types
                      Container(
                        width: 300,
                        constraints: const BoxConstraints(minWidth: 250, maxWidth: 400),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Event Types',
                                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  FilledButton.icon(
                                    onPressed: () => _addOrEditEventType(),
                                    icon: const Icon(Icons.add),
                                    label: const Text('Add Type'),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: ListView.builder(
                                itemCount: _eventTypes.length,
                                itemBuilder: (context, index) {
                                  final type = _eventTypes[index];
                                  final isSelected = type['id'] == _selectedEventTypeId;
                            
                                  return ListTile(
                                    selected: isSelected,
                                    title: Text(type['name']),
                                    onTap: () => _loadRoleTemplates(type['id']),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.edit),
                                      onPressed: () => _addOrEditEventType(existing: type),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const VerticalDivider(width: 1),
                // Right panel: Role Templates
                Container(
                  width: 500,
                  constraints: const BoxConstraints(minWidth: 400, maxWidth: 700),
                  child: _selectedEventTypeId == null
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Text(
                              '← Select an event type to manage roles',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Role Templates',
                                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  FilledButton.icon(
                                    onPressed: () => _addOrEditRoleTemplate(),
                                    icon: const Icon(Icons.add),
                                    label: const Text('Add Role'),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: _loadingTemplates
                                  ? const Center(child: CircularProgressIndicator())
                                  : _roleTemplates.isEmpty
                                      ? const Center(child: Text('No role templates yet'))
                                      : ListView.builder(
                                          itemCount: _roleTemplates.length,
                                          itemBuilder: (context, index) {
                                            final role = _roleTemplates[index];
                                            return Card(
                                              margin: const EdgeInsets.symmetric(
                                                horizontal: 16,
                                                vertical: 4,
                                              ),
                                              child: ListTile(
                                                title: Text(role['role_name']),
                                                subtitle: Text(
                                                  '${role['time_in']} - ${role['time_out']}',
                                                ),
                                                trailing: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    IconButton(
                                                      icon: const Icon(Icons.edit),
                                                      onPressed: () =>
                                                          _addOrEditRoleTemplate(existing: role),
                                                    ),
                                                    IconButton(
                                                      icon: const Icon(Icons.delete, color: Colors.red),
                                                      onPressed: () =>
                                                          _deleteRoleTemplate(role['id']),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}