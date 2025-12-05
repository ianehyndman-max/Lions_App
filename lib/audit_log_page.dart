import 'dart:convert';
import 'package:flutter/material.dart';
import 'api_client.dart';

class AuditLogPage extends StatefulWidget {
  const AuditLogPage({super.key});

  @override
  State<AuditLogPage> createState() => _AuditLogPageState();
}

class _AuditLogPageState extends State<AuditLogPage> {
  List<dynamic> _logs = [];
  bool _loading = true;
  String? _error;

  // Filters
  String? _filterEntityType;
  String? _filterAction;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Build query params
      final params = <String, String>{};
      if (_filterEntityType != null) params['entity_type'] = _filterEntityType!;
      if (_filterAction != null) params['action'] = _filterAction!;

      final qs = params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
      final path = qs.isEmpty ? '/audit_logs' : '/audit_logs?$qs';

      final res = await ApiClient.get(path);

      if (res.statusCode == 200) {
        final logs = (json.decode(res.body) as List);
        setState(() {
          _logs = logs;
          _loading = false;
        });
      } else if (res.statusCode == 403) {
        setState(() {
          _error = 'Access denied: Super user required';
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load audit logs: ${res.statusCode}';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audit Log'),
        backgroundColor: Colors.red,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadLogs,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Filters - FIXED FOR MOBILE
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                // Entity Type Filter
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<String?>(
                    value: _filterEntityType,
                    decoration: const InputDecoration(
                      labelText: 'Entity Type',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('All Types')),
                      DropdownMenuItem(value: 'member', child: Text('Member')),
                      DropdownMenuItem(value: 'event', child: Text('Event')),
                      DropdownMenuItem(value: 'club', child: Text('Club')),
                    ],
                    onChanged: (val) {
                      setState(() => _filterEntityType = val);
                      _loadLogs();
                    },
                  ),
                ),
                const SizedBox(width: 16),
                // Action Filter
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<String?>(
                    value: _filterAction,
                    decoration: const InputDecoration(
                      labelText: 'Action',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('All Actions')),
                      DropdownMenuItem(value: 'CREATE', child: Text('Create')),
                      DropdownMenuItem(value: 'UPDATE', child: Text('Update')),
                      DropdownMenuItem(value: 'DELETE', child: Text('Delete')),
                    ],
                    onChanged: (val) {
                      setState(() => _filterAction = val);
                      _loadLogs();
                    },
                  ),
                ),
                const SizedBox(width: 16),
                // Clear Filters Button
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _filterEntityType = null;
                      _filterAction = null;
                    });
                    _loadLogs();
                  },
                  icon: const Icon(Icons.clear),
                  label: const Text('Clear'),
                ),
              ],
            ),
          ),

          // Table
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      )
                    : _logs.isEmpty
                        ? const Center(child: Text('No audit logs found'))
                        : SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                                headingRowColor: MaterialStateProperty.all(Colors.red.shade100),
                                border: TableBorder.all(color: Colors.grey.shade300),
                                columns: const [
                                  DataColumn(label: Text('Timestamp', style: TextStyle(fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('Entity', style: TextStyle(fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('Action', style: TextStyle(fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('Changed By', style: TextStyle(fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('Details', style: TextStyle(fontWeight: FontWeight.bold))),
                                ],
                                rows: _logs.map((log) {
                                  final timestamp = log['changed_at']?.toString() ?? '';
                                  final entityType = log['entity_type']?.toString() ?? '';
                                  final entityId = log['entity_id']?.toString() ?? '';
                                  final action = log['action']?.toString() ?? '';
                                  final changedBy = log['changed_by_name']?.toString() ?? 'System';

                                  return DataRow(cells: [
                                    DataCell(Text(timestamp.split('.')[0])),
                                    DataCell(Text('$entityType #$entityId')),
                                    DataCell(
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: action == 'CREATE'
                                              ? Colors.green.shade100
                                              : action == 'UPDATE'
                                                  ? Colors.blue.shade100
                                                  : Colors.red.shade100,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(action),
                                      ),
                                    ),
                                    DataCell(Text(changedBy)),
                                    DataCell(
                                      IconButton(
                                        icon: const Icon(Icons.info_outline, size: 20),
                                        onPressed: () => _showDetailsDialog(
                                          context,
                                          entityType,
                                          entityId,
                                          action,
                                          timestamp,
                                          changedBy,
                                          log['old_value']?.toString() ?? '',
                                          log['new_value']?.toString() ?? '',
                                        ),
                                        tooltip: 'View Details',
                                      ),
                                    ),
                                  ]);
                                }).toList(),
                              ),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  void _showDetailsDialog(
    BuildContext context,
    String entityType,
    String entityId,
    String action,
    String timestamp,
    String changedBy,
    String oldValue,
    String newValue,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$action $entityType #$entityId'),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Timestamp: $timestamp', style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('Changed by: $changedBy'),
                const SizedBox(height: 16),
                if (oldValue.isNotEmpty) ...[
                  const Text('Old Value:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: SelectableText(
                      _formatJson(oldValue),
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (newValue.isNotEmpty) ...[
                  const Text('New Value:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: SelectableText(
                      _formatJson(newValue),
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _formatJson(String raw) {
    try {
      final obj = json.decode(raw);
      return const JsonEncoder.withIndent('  ').convert(obj);
    } catch (_) {
      return raw;
    }
  }
}