import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;


class EventDetailPage extends StatefulWidget {
  final dynamic eventId;
  const EventDetailPage({super.key, required this.eventId});

  @override
  State<EventDetailPage> createState() => _EventDetailPageState();
}

class _EventDetailPageState extends State<EventDetailPage> {
  Map<String, dynamic>? _event;
  List<dynamic> _roles = [];
  bool _loading = true;
  String? _error;
  
  int? _userMemberId;
  bool _isAdmin = false;
  String? _clubEmail;
  String? _clubPhone;
  
  final TextEditingController _notesController = TextEditingController();
  bool _isEditingNotes = false;

  bool get _isOther {
    final t = _event?['event_type']?.toString() ?? '';
    final idStr = _event?['event_type_id']?.toString() ?? '';
    return t == 'Other' || idStr == '4';
  }

  bool get _hasUnassigned =>
      _roles.any((r) => (r['volunteer_name']?.toString().trim().isEmpty ?? true));

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    _userMemberId = prefs.getInt('member_id');
    _isAdmin = prefs.getBool('is_admin') ?? false;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await http.get(Uri.parse('http://localhost:8080/events/${widget.eventId}'));
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        setState(() {
          _event = data['event'] as Map<String, dynamic>;
          _roles = data['roles'] as List<dynamic>;
          _notesController.text = _event!['notes']?.toString() ?? '';
          _clubEmail = _event!['club_email']?.toString();
          _clubPhone = _event!['club_phone']?.toString();
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load: ${res.statusCode}';
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

  Future<void> _sendResendToAll() async {
  final proceed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Resend event details to all?'),
      content: Text(_hasUnassigned
          ? 'There are unassigned shifts. We will include a note asking for volunteers.'
          : 'There are no unassigned shifts. Resend anyway?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send')),
      ],
    ),
  );
  if (proceed != true) return;

  if (!mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Sending email to all...')),
  );

  try {
    final res = await http.post(
      Uri.parse('http://localhost:8080/events/${widget.eventId}/notify'),
      headers: {'Content-Type': 'application/json'},
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    if (res.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email sent to all members.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: ${res.body}')),
      );
    }
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
  }
}

  Future<void> _sendAssignedReminder() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send reminder to assigned volunteers?'),
        content: const Text('We’ll email only assigned volunteers with the event details.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send')),
        ],
      ),
    );
    if (proceed != true) return;

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sending reminder to assigned volunteers...')),
    );

    try {
      // Try common API shapes in order:
      final urls = <Uri>[
        Uri.parse('http://localhost:8080/events/${widget.eventId}/notify_assigned'),      // 1) dedicated route
        Uri.parse('http://localhost:8080/events/${widget.eventId}/notify?only_assigned=true'), // 2) query flag
      ];

      http.Response? res;
      for (final u in urls) {
        final r = await http.post(u, headers: {'Content-Type': 'application/json'});
        // If this endpoint exists (not 404), use its result and stop trying others.
        if (r.statusCode != 404) {
          res = r;
          break;
        }
      }

      // 3) Fallback: same /notify with JSON body flag
      res ??= await http.post(
        Uri.parse('http://localhost:8080/events/${widget.eventId}/notify'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'only_assigned': true}),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();

      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reminder sent to assigned volunteers.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed (${res.statusCode}): ${res.body}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

    Future<void> _printEvent() async {
    if (_event == null) return;

    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                '${_event!['event_type']} - ${_event!['club_name']}',
                style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 20),
              pw.Text('Date: ${_event!['date'] ?? ''}', style: const pw.TextStyle(fontSize: 14)),
              pw.Text('Location: ${_event!['location'] ?? ''}', style: const pw.TextStyle(fontSize: 14)),
              pw.SizedBox(height: 20),
              pw.Text('Volunteer Roles', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              pw.TableHelper.fromTextArray(
                headers: ['Role', 'Time In', 'Time Out', 'Volunteer', 'Signature'],
                data: _roles.map((r) {
                  final volunteer = r['volunteer_name']?.toString() ?? 'Unassigned';
                  return [
                    r['role_name'] ?? '',
                    r['time_in'] ?? '',
                    r['time_out'] ?? '',
                    volunteer,
                    '', // Empty signature column
                  ];
                }).toList(),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                cellAlignment: pw.Alignment.centerLeft,
                border: pw.TableBorder.all(),
                columnWidths: {
                  0: const pw.FlexColumnWidth(2),
                  1: const pw.FlexColumnWidth(1.5),
                  2: const pw.FlexColumnWidth(1.5),
                  3: const pw.FlexColumnWidth(2),
                  4: const pw.FlexColumnWidth(2.5), // Wider for signature
                },
              ),
              pw.SizedBox(height: 20),
              if (_event!['notes']?.toString().isNotEmpty ?? false) ...[
                pw.Text('Notes', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 10),
                pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(border: pw.Border.all()),
                  child: pw.Text(_event!['notes']?.toString() ?? ''),
                ),
              ],
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }

  Future<void> _saveNotes() async {
    if (_event == null) return;
    setState(() => _loading = true);
    try {
      final eventTypeId = _event!['event_type_id'] is int 
          ? _event!['event_type_id'] 
          : int.parse(_event!['event_type_id'].toString());
      
      final clubId = _event!['club_id'] is int 
          ? _event!['club_id'] 
          : int.parse(_event!['club_id'].toString());

      final res = await http.put(
        Uri.parse('http://localhost:8080/events/${widget.eventId}'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'event_type_id': eventTypeId,
          'lions_club_id': clubId,
          'event_date': _event!['date'],
          'location': _event!['location'] ?? '',
          'notes': _notesController.text,
        }),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() {
          _isEditingNotes = false;
          _event!['notes'] = _notesController.text;
          _loading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Notes saved')));
        await _load();
      } else {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: ${res.body}')));
      }
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _volunteerSelf(Map<String, dynamic> role) async {
    if (_userMemberId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please set up your profile first')));
      return;
    }
    final currentMemberId = role['member_id'];
    if (currentMemberId != null && currentMemberId.toString().isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This slot is already taken')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Volunteer for this role?'),
        content: Text('Role: ${role['role_name']}\n${role['time_in']} - ${role['time_out']}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign Up')),
        ],
      ),
    );
    if (ok != true) return;
    final post = await http.post(
      Uri.parse('http://localhost:8080/events/${widget.eventId}/volunteer'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'role_id': role['role_id'], 'member_id': _userMemberId}),
    );
    if (!mounted) return;
    if (post.statusCode == 200) {
      await _load();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You are signed up!')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: ${post.body}')));
    }
  }

  Future<void> _showChangeMyMindDialog() async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change Your Mind?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'We understand that circumstances change!',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'To withdraw from your volunteer commitment, please contact the club secretary:',
            ),
            const SizedBox(height: 16),
            if (_clubPhone != null && _clubPhone!.isNotEmpty) ...[
              Row(
                children: [
                  const Icon(Icons.phone, size: 20),
                  const SizedBox(width: 8),
                  Text(_clubPhone!, style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
            ],
            if (_clubEmail != null && _clubEmail!.isNotEmpty) ...[
              Row(
                children: [
                  const Icon(Icons.email, size: 20),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(_clubEmail!, style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
            if ((_clubPhone == null || _clubPhone!.isEmpty) && 
                (_clubEmail == null || _clubEmail!.isEmpty)) ...[
              const Text(
                'Please contact your club secretary.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickVolunteer(Map<String, dynamic> role) async {
    if (!_isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Admin access required')));
      return;
    }
    if (_event == null) return;
    final clubId = _event!['club_id'];
    final res = await http.get(Uri.parse('http://localhost:8080/members?club_id=$clubId'));
    if (res.statusCode != 200) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to load members')));
      return;
    }
    final members = (json.decode(res.body) as List).cast<Map<String, dynamic>>();
    dynamic selectedMemberId = role['member_id'];
    if (!mounted) return;
    final choice = await showDialog<dynamic>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Assign "${role['role_name']}"'),
          content: SizedBox(
            width: 400,
            height: 400,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Choose member:'),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    children: [
                      RadioListTile<dynamic>(
                        value: null,
                        groupValue: selectedMemberId,
                        title: const Text('Clear assignment'),
                        onChanged: (v) => setDialogState(() => selectedMemberId = v),
                      ),
                      ...members.map((m) => RadioListTile<dynamic>(
                            value: m['id'],
                            groupValue: selectedMemberId,
                            title: Text(m['name'] ?? ''),
                            subtitle: Text(m['email'] ?? ''),
                            onChanged: (v) => setDialogState(() => selectedMemberId = v),
                          )),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, selectedMemberId), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (choice == null && role['member_id'] != null) return;
    final post = await http.post(
      Uri.parse('http://localhost:8080/events/${widget.eventId}/volunteer'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'role_id': role['role_id'], 'member_id': choice}),
    );
    if (!mounted) return;
    if (post.statusCode == 200) {
      await _load();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: ${post.body}')));
    }
  }

   // Add role (admins, Other only)
  Future<void> _addRole() async {
    if (!_isAdmin || !_isOther) return;

    final nameCtrl = TextEditingController();
    final timeInCtrl = TextEditingController();
    final timeOutCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Role'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Role name')),
            TextField(controller: timeInCtrl, decoration: const InputDecoration(labelText: 'Time in (e.g. 08:00)')),
            TextField(controller: timeOutCtrl, decoration: const InputDecoration(labelText: 'Time out (e.g. 12:00)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );

    if (ok != true) return;
    final roleName = nameCtrl.text.trim();
    if (roleName.isEmpty) return;

    final res = await http.post(
      Uri.parse('http://localhost:8080/events/${widget.eventId}/roles'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'role_name': roleName,
        'time_in': timeInCtrl.text.trim(),
        'time_out': timeOutCtrl.text.trim(),
      }),
    );

    if (!mounted) return;
    if (res.statusCode == 201 || res.statusCode == 200) {
      await _load();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Role added')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: ${res.body}')));
    }
  }

  // Delete role (admins, Other only)
  Future<void> _deleteRole(int roleId) async {
    if (!_isAdmin || !_isOther) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Role?'),
        content: const Text('This will remove the role and any volunteer assignment for this event.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final res = await http.delete(
      Uri.parse('http://localhost:8080/events/${widget.eventId}/roles/$roleId'),
    );

    if (!mounted) return;
    if (res.statusCode == 200 || res.statusCode == 204) {
      await _load();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Role deleted')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: ${res.body}')));
    }
  }

  @override
    Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_event == null ? 'Event' : '${_event!['event_type']} · ${_event!['club_name']}'),
        backgroundColor: Colors.red,
        actions: [
          if (_event != null)
            IconButton(
              icon: const Icon(Icons.print),
              tooltip: 'Print Event Details',
              onPressed: _printEvent,
            ),
        ],
      ),

             floatingActionButton: _isAdmin
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Email assigned volunteers
                FloatingActionButton.extended(
                  heroTag: 'fab-email-assigned',
                  onPressed: _sendAssignedReminder,
                  icon: const Icon(Icons.mark_email_unread_outlined),
                  label: const Text('Email Assigned'),
                  backgroundColor: Colors.blue,
                ),
                const SizedBox(height: 10),
                // Resend to all (disabled visually if none unassigned? we allow but show note)
                FloatingActionButton.extended(
                  heroTag: 'fab-resend-all',
                  onPressed: _sendResendToAll,
                  icon: const Icon(Icons.outgoing_mail),
                  label: Text(_hasUnassigned ? 'Resend (unfilled)' : 'Resend to All'),
                  backgroundColor: _hasUnassigned ? Colors.orange : Colors.grey.shade700,
                ),
                const SizedBox(height: 10),
                if (_isOther)
                  FloatingActionButton.extended(
                    heroTag: 'fab-add-role',
                    onPressed: _addRole,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Role'),
                    backgroundColor: Colors.red,
                  ),
              ],
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : _event == null
                  ? const Center(child: Text('Event not found'))
                  : Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: ListView(
                        children: [
                          Card(
                            elevation: 0,
                            color: Colors.red.shade50,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_event!['event_type'] ?? '', style: theme.textTheme.titleLarge),
                                  const SizedBox(height: 8),
                                  Text('Club: ${_event!['club_name'] ?? ''}'),
                                  Text('Date: ${_event!['date'] ?? ''}'),
                                  Text('Location: ${_event!['location'] ?? ''}'),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              headingRowColor: MaterialStateProperty.all(Colors.red.shade100),
                              border: TableBorder.all(color: Colors.grey.shade300),
                              columns: const [
                                DataColumn(label: Text('Role', style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('Time In', style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('Time Out', style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('Volunteer', style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('Action', style: TextStyle(fontWeight: FontWeight.bold))),
                              ],
                              rows: _roles.map((r) {
                                final volunteer = r['volunteer_name'] ?? '';
                                final hasVolunteer = volunteer.toString().isNotEmpty;
                                final currentMemberId = r['member_id'];
                                final isCurrentUser = _userMemberId != null &&
                                    currentMemberId != null &&
                                    currentMemberId.toString() == _userMemberId.toString();
                                return DataRow(cells: [
                                  DataCell(Text(r['role_name'] ?? '')),
                                  DataCell(Text(r['time_in'] ?? '')),
                                  DataCell(Text(r['time_out'] ?? '')),
                                  DataCell(Text(hasVolunteer ? volunteer : 'Unassigned',
                                      style: TextStyle(
                                        color: hasVolunteer ? Colors.black : Colors.grey,
                                        fontWeight: isCurrentUser ? FontWeight.bold : FontWeight.normal,
                                      ))),
                                  DataCell(
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Primary action (unchanged)
                                        _isAdmin
                                            ? TextButton(
                                                onPressed: () => _pickVolunteer(r),
                                                child: Text(hasVolunteer ? 'Change' : 'Assign'),
                                              )
                                            : isCurrentUser
                                                ? TextButton(
                                                    onPressed: _showChangeMyMindDialog,
                                                    style: TextButton.styleFrom(foregroundColor: Colors.orange),
                                                    child: const Text('Change My Mind'),
                                                  )
                                                : hasVolunteer
                                                    ? const SizedBox.shrink()
                                                    : TextButton(
                                                        onPressed: () => _volunteerSelf(r),
                                                        child: const Text('Volunteer'),
                                                      ),
                                        // Delete (admins on “Other” only)
                                        if (_isAdmin && _isOther)
                                          IconButton(
                                            tooltip: 'Delete role',
                                            icon: const Icon(Icons.delete, color: Colors.red),
                                            onPressed: () {
                                              final roleId = int.tryParse(r['role_id']?.toString() ?? '');
                                              if (roleId != null) _deleteRole(roleId);
                                            },
                                          ),
                                      ],
                                    ),
                                  ),
                                ]);
                              }).toList(),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Card(
                            elevation: 0,
                            color: Colors.grey.shade50,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Notes', style: theme.textTheme.titleMedium),
                                      if (_isAdmin)
                                        _isEditingNotes
                                            ? Row(
                                                children: [
                                                  TextButton(
                                                    onPressed: () {
                                                      setState(() {
                                                        _isEditingNotes = false;
                                                        _notesController.text = _event!['notes']?.toString() ?? '';
                                                      });
                                                    },
                                                    child: const Text('Cancel'),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  FilledButton(onPressed: _saveNotes, child: const Text('Save')),
                                                ],
                                              )
                                            : IconButton(
                                                icon: const Icon(Icons.edit),
                                                tooltip: 'Edit notes',
                                                onPressed: () {
                                                  setState(() {
                                                    _isEditingNotes = true;
                                                    _notesController.text = _event!['notes']?.toString() ?? '';
                                                  });
                                                },
                                              ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  _isEditingNotes
                                      ? TextField(
                                          controller: _notesController,
                                          maxLines: 6,
                                          decoration: const InputDecoration(
                                            hintText: 'Add event notes here...',
                                            border: OutlineInputBorder(),
                                          ),
                                        )
                                      : Text(
                                          _event!['notes']?.toString().isEmpty ?? true ? 'No notes yet' : _event!['notes'].toString(),
                                          style: TextStyle(
                                            color: _event!['notes']?.toString().isEmpty ?? true ? Colors.grey : Colors.black,
                                          ),
                                        ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
    );
  }
}