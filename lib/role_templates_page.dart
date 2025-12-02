import 'dart:convert';
import 'package:flutter/material.dart';
import 'api_client.dart';

class RoleTemplatesPage extends StatefulWidget {
  const RoleTemplatesPage({super.key});

  @override
  State<RoleTemplatesPage> createState() => _RoleTemplatesPageState();
}

class _RoleTemplatesPageState extends State<RoleTemplatesPage> {
  List<dynamic> _eventTypes = [];
  int? _selectedEventTypeId;
  String? _selectedEventTypeName;
  List<dynamic> _templates = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadEventTypes();
  }

  Future<void> _loadEventTypes() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await ApiClient.get('/event_types');
      if (res.statusCode == 200) {
        final types = json.decode(res.body) as List;
        setState(() {
          _eventTypes = types;
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load event types: ${res.statusCode}';
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

  Future<void> _loadTemplates(int eventTypeId) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await ApiClient.get('/event_types/$eventTypeId/role_templates');
      if (res.statusCode == 200) {
        final templates = json.decode(res.body) as List;
        setState(() {
          _templates = templates;
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load templates: ${res.statusCode}';
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

  void _selectEventType(int id, String name) {
    setState(() {
      _selectedEventTypeId = id;
      _selectedEventTypeName = name;
    });
    _loadTemplates(id);
  }

  Future<void> _saveTemplate({
  int? templateId,
  required String roleName,
  required String timeIn,
  required String timeOut,
  }) async {
   if (_selectedEventTypeId == null) return;

   try {
    // Pass as Map, not JSON string - ApiClient.post will encode it
    final res = await ApiClient.post(
      '/event_types/$_selectedEventTypeId/role_templates',
      body: {
        'id': templateId,
        'role_name': roleName,
        'time_in': timeIn,
        'time_out': timeOut,
      },
    );

    if (res.statusCode == 200) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(templateId == null ? 'Template created' : 'Template updated')),
        );
      }
      _loadTemplates(_selectedEventTypeId!);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save template: ${res.statusCode}')),
        );
      }
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }
}

  Future<void> _deleteTemplate(int templateId) async {
    try {
      final res = await ApiClient.delete('/role_templates/$templateId');

      if (res.statusCode == 204) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Template deleted')),
          );
        }
        _loadTemplates(_selectedEventTypeId!);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete: ${res.statusCode}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _showTemplateDialog({Map<String, dynamic>? template}) {
    final isEdit = template != null;
    final roleNameController = TextEditingController(text: template?['role_name'] ?? '');
    final timeInController = TextEditingController(text: template?['time_in'] ?? '');
    final timeOutController = TextEditingController(text: template?['time_out'] ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? 'Edit Template' : 'Add Template'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: roleNameController,
                decoration: const InputDecoration(
                  labelText: 'Role Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: timeInController,
                decoration: const InputDecoration(
                  labelText: 'Time In (HH:MM)',
                  border: OutlineInputBorder(),
                  hintText: '09:00',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: timeOutController,
                decoration: const InputDecoration(
                  labelText: 'Time Out (HH:MM)',
                  border: OutlineInputBorder(),
                  hintText: '14:00',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final roleName = roleNameController.text.trim();
              final timeIn = timeInController.text.trim();
              final timeOut = timeOutController.text.trim();

              if (roleName.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Role name required')),
                );
                return;
              }

              Navigator.pop(ctx);
              _saveTemplate(
                templateId: template?['id'],
                roleName: roleName,
                timeIn: timeIn,
                timeOut: timeOut,
              );
            },
            child: Text(isEdit ? 'Update' : 'Create'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Role Templates'),
        backgroundColor: Colors.red,
      ),
      body: Row(
        children: [
          // Left panel: Event Types
          Container(
            width: 250,
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.red.shade50,
                  child: const Text(
                    'Event Types',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
                          : ListView.builder(
                              itemCount: _eventTypes.length,
                              itemBuilder: (ctx, i) {
                                final type = _eventTypes[i];
                                final id = type['id'];
                                final name = type['name'] ?? '';
                                final isSelected = id == _selectedEventTypeId;

                                return ListTile(
                                  selected: isSelected,
                                  selectedTileColor: Colors.red.shade100,
                                  title: Text(name),
                                  onTap: () => _selectEventType(id, name),
                                );
                              },
                            ),
                ),
              ],
            ),
          ),

          // Right panel: Templates
          Expanded(
            child: _selectedEventTypeId == null
                ? const Center(
                    child: Text('Select an event type to manage templates'),
                  )
                : Column(
                    children: [
                      // Header
                      Container(
                        padding: const EdgeInsets.all(16),
                        color: Colors.red.shade50,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Templates for $_selectedEventTypeName',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: () => _showTemplateDialog(),
                              icon: const Icon(Icons.add),
                              label: const Text('Add Template'),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                            ),
                          ],
                        ),
                      ),

                      // Templates table
                      Expanded(
                        child: _loading
                            ? const Center(child: CircularProgressIndicator())
                            : _templates.isEmpty
                                ? const Center(child: Text('No templates defined yet'))
                                : SingleChildScrollView(
                                    padding: const EdgeInsets.all(16),
                                    child: DataTable(
                                      headingRowColor: MaterialStateProperty.all(Colors.red.shade100),
                                      border: TableBorder.all(color: Colors.grey.shade300),
                                      columns: const [
                                        DataColumn(label: Text('Role Name', style: TextStyle(fontWeight: FontWeight.bold))),
                                        DataColumn(label: Text('Time In', style: TextStyle(fontWeight: FontWeight.bold))),
                                        DataColumn(label: Text('Time Out', style: TextStyle(fontWeight: FontWeight.bold))),
                                        DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                                      ],
                                      rows: _templates.map((template) {
                                        final id = template['id'];
                                        final roleName = template['role_name'] ?? '';
                                        final timeIn = template['time_in'] ?? '';
                                        final timeOut = template['time_out'] ?? '';

                                        return DataRow(cells: [
                                          DataCell(Text(roleName)),
                                          DataCell(Text(timeIn)),
                                          DataCell(Text(timeOut)),
                                          DataCell(
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(
                                                  icon: const Icon(Icons.edit, size: 20, color: Colors.blue),
                                                  onPressed: () => _showTemplateDialog(template: template),
                                                  tooltip: 'Edit',
                                                ),
                                                IconButton(
                                                  icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                                                  onPressed: () {
                                                    showDialog(
                                                      context: context,
                                                      builder: (ctx) => AlertDialog(
                                                        title: const Text('Delete Template'),
                                                        content: Text('Delete "$roleName" template?'),
                                                        actions: [
                                                          TextButton(
                                                            onPressed: () => Navigator.pop(ctx),
                                                            child: const Text('Cancel'),
                                                          ),
                                                          ElevatedButton(
                                                            onPressed: () {
                                                              Navigator.pop(ctx);
                                                              _deleteTemplate(id);
                                                            },
                                                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                                            child: const Text('Delete'),
                                                          ),
                                                        ],
                                                      ),
                                                    );
                                                  },
                                                  tooltip: 'Delete',
                                                ),
                                              ],
                                            ),
                                          ),
                                        ]);
                                      }).toList(),
                                    ),
                                  ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}