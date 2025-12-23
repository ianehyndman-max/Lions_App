import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'event_detail_page.dart';
import 'create_event_dialog.dart';
import 'config.dart';
import 'widgets/email_html_editor.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'api_client.dart';
import 'event_type_management_page.dart';
import 'auth_store.dart';

class EventsPage extends StatefulWidget {
  EventsPage({super.key});

  @override
  State<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends State<EventsPage> {
  List<dynamic> _events = [];
  //List<dynamic> _eventTypes = [];
  List<Map<String, dynamic>> _eventTypes = [];
  List<dynamic> _clubs = [];
  bool _loading = true;
  String? _error;
  String _fmtYmd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  int? _userClubId;
  bool _isAdmin = false;

   // Filter state
  int? _filterEventTypeId; // null = "All Types"
  String? _filterDateRange; // null = "All Dates", "today", "week", "month"
  
  // Same helper as MembersPage
  int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }
  
    // ---- Email preview helpers (adapted from EventDetailPage) ----
  String _escapeHtml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');

  String _fmtTime(String? t) {
    if (t == null) return '';
    final m = RegExp(r'^(\d{1,2}:\d{2})').firstMatch(t);
    return m != null ? m.group(1)! : t;
  }

  String _buildRolesTableHtml(List roles) {
    final buffer = StringBuffer();
    buffer.write('''
<div style="max-width:100%; overflow-x:auto;">
<table style="border-collapse:collapse; min-width:650px; width:800px;">
<thead><tr>
<th style="text-align:left; padding:8px; border:1px solid #ddd; background:#f5f5f5;">Role</th>
<th style="text-align:left; padding:8px; border:1px solid #ddd; background:#f5f5f5;">Time In</th>
<th style="text-align:left; padding:8px; border:1px solid #ddd; background:#f5f5f5;">Time Out</th>
<th style="text-align:left; padding:8px; border:1px solid #ddd; background:#f5f5f5;">Volunteer</th>
</tr></thead><tbody>
''');
    for (final r in roles) {
      if (r is! Map) continue;
      final rawName = (r['volunteer_name'] ?? r['name'])?.toString() ?? '';
      final hasName = rawName.trim().isNotEmpty;
      buffer.write('''
<tr>
<td style="padding:8px; border:1px solid #ddd;">${_escapeHtml(r['role_name']?.toString() ?? '')}</td>
<td style="padding:8px; border:1px solid #ddd; white-space:nowrap;">${_escapeHtml(_fmtTime(r['time_in']?.toString()))}</td>
<td style="padding:8px; border:1px solid #ddd; white-space:nowrap;">${_escapeHtml(_fmtTime(r['time_out']?.toString()))}</td>
<td style="padding:8px; border:1px solid #ddd;">${hasName ? _escapeHtml(rawName) : 'Unassigned'}</td>
</tr>
''');
    }
    buffer.write('</tbody></table></div>');
    return buffer.toString();
  }

  String _extractBodyHtml(String html) {
    final lower = html.toLowerCase();
    final bodyOpen = lower.indexOf('<body');
    if (bodyOpen >= 0) {
      final openEnd = html.indexOf('>', bodyOpen);
      if (openEnd >= 0) {
        final bodyClose = lower.indexOf('</body>', openEnd + 1);
        if (bodyClose > openEnd) {
          return html.substring(openEnd + 1, bodyClose);
        }
      }
    }
    return html;
  }

  String _mergeIntoBody(String original, String fragment) {
    final lower = original.toLowerCase();
    final bodyOpen = lower.indexOf('<body');
    if (bodyOpen >= 0) {
      final openEnd = original.indexOf('>', bodyOpen);
      if (openEnd >= 0) {
        final bodyClose = lower.indexOf('</body>', openEnd + 1);
        if (bodyClose > openEnd) {
          return original.substring(0, openEnd + 1) + fragment + original.substring(bodyClose);
        }
      }
    }
    return fragment;
  }

  String _patchNotesAndRoles(String html, {required String notes, required List roles}) {
    var out = html.replaceAll(RegExp(r'{{\s*notes\s*}}', caseSensitive: false), _escapeHtml(notes));
    final rolesTable = _buildRolesTableHtml(roles);
    out = out.replaceAll(RegExp(r'{{\s*roles_html\s*}}', caseSensitive: false), rolesTable);
    out = out.replaceAll(
        RegExp(r'<ul[^>]*>\s*<li[^>]*>\s*{{\s*roles_html\s*}}\s*</li>\s*</ul>', caseSensitive: false, dotAll: true),
        rolesTable);
    out = out.replaceAllMapped(
        RegExp(r'(<h[23][^>]*>\s*Volunteer Roles\s*:?<\/h[23]>\s*)(?:<ul[^>]*>[\s\S]*?<\/ul>|<ol[^>]*>[\s\S]*?<\/ol>)',
            caseSensitive: false),
        (m) => '${m.group(1)}$rolesTable');
    return out;
  }

  /// Show email preview + editor, then send new‑event notification.
  Future<void> _composeAndSendNewEventEmail(int eventId) async {
    debugPrint('DEBUG: EventsPage _composeAndSendNewEventEmail -> START eventId=$eventId');
      // Load event detail (to patch notes/roles).
    http.Response detail;
    try {
      debugPrint('DEBUG: EventsPage _composeAndSendNewEventEmail -> fetching event details');
      detail = await http.get(Uri.parse('$apiBase/events/$eventId'));
      debugPrint('DEBUG: EventsPage _composeAndSendNewEventEmail -> event detail status=${detail.statusCode}');
      debugPrint('DEBUG: EventsPage _composeAndSendNewEventEmail -> event detail body=${detail.body}');
    } catch (e) {
      debugPrint('ERROR: EventsPage _composeAndSendNewEventEmail -> event fetch failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Event load failed: $e')));
      return;
    }
    if (detail.statusCode != 200) {
      debugPrint('ERROR: EventsPage _composeAndSendNewEventEmail -> event detail failed: ${detail.body}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Event load failed: ${detail.body}')));
      return;
    }
    final parsed = json.decode(detail.body) as Map<String, dynamic>;
    final event = parsed['event'] as Map<String, dynamic>;
    final roles = (parsed['roles'] as List?) ?? [];
    debugPrint('DEBUG: EventsPage _composeAndSendNewEventEmail -> parsed event, roles.length=${roles.length}');
    // Dry run to get template.
    http.Response preview;
    try {
      debugPrint('DEBUG: EventsPage _composeAndSendNewEventEmail -> fetching preview (dry_run)');
      preview = await http.post(
        Uri.parse('$apiBase/events/$eventId/notify'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'dry_run': true}),
      );
       debugPrint('DEBUG: EventsPage _composeAndSendNewEventEmail -> preview status=${preview.statusCode}');
       debugPrint('DEBUG: EventsPage _composeAndSendNewEventEmail -> preview body=${preview.body}');  // ⬅️ ADD THIS LINE
    } catch (e) {
      debugPrint('ERROR: EventsPage _composeAndSendNewEventEmail -> preview fetch failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Preview failed: $e')));
      return;
    }
    if (preview.statusCode != 200) {
      debugPrint('ERROR: EventsPage _composeAndSendNewEventEmail -> preview failed: ${preview.body}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Preview failed: ${preview.body}')));
      return;
    }
    final data = json.decode(preview.body) as Map<String, dynamic>;
     debugPrint('DEBUG: EventsPage _composeAndSendNewEventEmail -> preview data keys=${data.keys}');
    final subjectCtrl = TextEditingController(text: (data['subject'] ?? '').toString());
    String bodyHtml = (data['body_html'] ?? '').toString();
    bodyHtml = _patchNotesAndRoles(bodyHtml, notes: event['notes']?.toString() ?? '', roles: roles);
    final editorCtrl = EmailHtmlEditorController();
    final editable = _extractBodyHtml(bodyHtml);
    String previewHtml = bodyHtml;
    debugPrint('DEBUG: EventsPage _composeAndSendNewEventEmail -> showing preview dialog');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        bool showEditor = false;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => DefaultTabController(
            length: 2,
            child: AlertDialog(
              title: const Text('Preview: New Event Email'),
              content: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 900,
                  maxHeight: MediaQuery.of(context).size.height * .8,
                ),
                child: SizedBox(
                  width: 820,
                  child: Column(
                    children: [
                      TextField(controller: subjectCtrl, decoration: const InputDecoration(labelText: 'Subject')),
                      const SizedBox(height: 12),
                      TabBar(tabs: const [Tab(text: 'Preview'), Tab(text: 'Edit')], onTap: (i) async {
                        if (i == 1 && !showEditor) {
                          Future.delayed(const Duration(milliseconds: 10),
                              () => setDialogState(() => showEditor = true));
                        }
                        if (i == 0) {
                          final edited = (await editorCtrl.getHtml()).trim();
                          final merged = _mergeIntoBody(bodyHtml, edited.isEmpty ? editable : edited);
                          setDialogState(() => previewHtml = merged);
                        }
                      }),
                      Expanded(
                        child: TabBarView(
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: SingleChildScrollView(child: HtmlWidget(previewHtml)),
                            ),
                            Builder(
                              builder: (_) {
                                if (!showEditor) return const Center(child: CircularProgressIndicator());
                                return EmailHtmlEditor(controller: editorCtrl, initialHtml: editable);
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send')),
              ],
            ),
          ),
        );
      },
    );
    if (ok != true) return;
    final editedHtml = (await editorCtrl.getHtml()).trim();
    final mergedHtml = _mergeIntoBody(bodyHtml, editedHtml.isEmpty ? editable : editedHtml);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sending new event email...')));
    try {
      final sendRes = await http.post(
        Uri.parse('$apiBase/events/$eventId/notify'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'subject': subjectCtrl.text.trim(), 'body_html': mergedHtml}),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(sendRes.statusCode == 200
              ? 'New event email sent.'
              : 'Send failed (${sendRes.statusCode}): ${sendRes.body}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Send error: $e')));
    }
  }


  @override
  void initState() {
    super.initState();
    debugPrint('DEBUG: EventsPage initState');
    _loadUserProfile();
    _loadEventTypes();
  }

  Future<void> _loadUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    _userClubId = prefs.getInt('club_id');
    _isAdmin = prefs.getBool('is_admin') ?? false;
    _load(); // do not setState here; _load() handles it
  }


  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    debugPrint('DEBUG: EventsPage _load start (clubId=$_userClubId)');
    try {
      // Build query params for server-side filtering
      final params = <String, String>{};
      if (_userClubId != null) params['club_id'] = _userClubId!.toString();
      if (_filterEventTypeId != null) params['type_id'] = _filterEventTypeId!.toString();
      if (_filterDateRange != null) params['date_range'] = _filterDateRange!; // today|week|month

      final qs = params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
      final path = qs.isEmpty ? '/events' : '/events?$qs';

      // IMPORTANT: call ApiClient with the path that includes query params
      final res = await ApiClient.get(path);
      debugPrint('DEBUG: EventsPage _load status=${res.statusCode} path=$path');

      //final url = _userClubId == null
        //  ? '$apiBase/events'
          //: '$apiBase/events?club_id=$_userClubId';
      // ApiClient will add x-member-id header automatically
      // Server-side filtering now happens based on that header
      //final res = await ApiClient.get('/events');
      debugPrint('DEBUG: EventsPage _load status=${res.statusCode}');
      if (res.statusCode == 200) {
      var events = (json.decode(res.body) as List);
      
      
      setState(() {
        _events = events;
        _loading = false;
      });
    } else {
      setState(() {
        _error = 'Failed to load events: ${res.statusCode}';
        _loading = false;
      });
    }
  } catch (e) {
    debugPrint('ERROR: EventsPage _load -> $e');
    setState(() {
      _error = 'Error: $e';
      _loading = false;
    });
  }
}

  Future<void> _loadEventTypes() async {
    debugPrint('DEBUG: EventsPage _loadEventTypes');
    final res = await http.get(Uri.parse('$apiBase/event_types'));
    if (res.statusCode == 200) {
      final list = (json.decode(res.body) as List).cast<Map<String, dynamic>>();
    setState(() => _eventTypes = list);
    } else {
      debugPrint('ERROR: EventsPage _loadEventTypes status=${res.statusCode}');
    }
  }

  Future<void> _loadClubs() async {
    debugPrint('DEBUG: EventsPage _loadClubs');
    final res = await http.get(Uri.parse('$apiBase/clubs'));
    if (res.statusCode == 200) {
      setState(() => _clubs = json.decode(res.body) as List);
    } else {
      debugPrint('ERROR: EventsPage _loadClubs status=${res.statusCode}');
    }
  }

  
  // ...existing code...
  // Direct send removed; EventDetailPage handles preview + send.
  Future<void> _openCreateEventDialog() async {
    await _loadEventTypes();
    await _loadClubs();
    
      // SIMPLIFIED: Remove the local variable, just pass true directly
  debugPrint('DEBUG: EventsPage _openCreateEventDialog -> showing dialog with defaultSendEmails=true');
  final result = await showCreateEventDialog(
    context,
    showSendEmailsToggle: true,
    defaultSendEmails: true, // ✅ Direct value instead of variable
    userClubId: _userClubId,
  );
  debugPrint('DEBUG: EventsPage _openCreateEventDialog -> result=$result');
  if (result == null) return;

  // Extract eventId and sendEmails from result
  final eventIdStr = result.eventId;
  final sendEmails = result.sendEmails;
  debugPrint('DEBUG: EventsPage _openCreateEventDialog -> eventId=$eventIdStr sendEmails=$sendEmails');
  
  if (eventIdStr.isEmpty) return;
  
  final eventId = int.parse(eventIdStr);
  debugPrint('DEBUG: EventsPage _openCreateEventDialog -> parsed eventId=$eventId, checking sendEmails=$sendEmails mounted=$mounted');
  if (sendEmails && mounted) {
     debugPrint('DEBUG: EventsPage _openCreateEventDialog -> calling _composeAndSendNewEventEmail');
    await _composeAndSendNewEventEmail(eventId);
  }
  debugPrint('DEBUG: EventsPage _openCreateEventDialog -> navigating to EventDetailPage');
  if (mounted) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => EventDetailPage(eventId: eventId)));
  }
}

    
// ...existing code...
  Future<void> _openEditEventDialog(Map<String, dynamic> event) async {
    if (!_isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Admin access required')));
      return;
    }

    await _loadEventTypes();
    await _loadClubs();
    if (!mounted) return;

    int? eventTypeId = _toInt(event['event_type_id']);
    int? clubId = _toInt(event['club_id'] ?? event['lions_club_id']);
    DateTime? date = event['date'] != null
        ? DateTime.tryParse(event['date'].toString())
        : (event['event_date'] != null ? DateTime.tryParse(event['event_date'].toString()) : null);
    final locationCtrl = TextEditingController(text: event['location']?.toString() ?? '');
    final notesCtrl = TextEditingController(text: event['notes']?.toString() ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Event'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  value: eventTypeId,
                  decoration: const InputDecoration(labelText: 'Event Type'),
                  items: _eventTypes
                      .map((et) {
                        final id = _toInt(et['id']);
                        if (id == null) return null;
                        return DropdownMenuItem<int>(
                          value: id,
                          child: Text(et['name']?.toString() ?? et['id'].toString()),
                        );
                      })
                      .whereType<DropdownMenuItem<int>>()
                      .toList(),
                  onChanged: (v) => setDialogState(() => eventTypeId = v),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  value: clubId,
                  decoration: const InputDecoration(labelText: 'Club'),
                  items: _clubs
                      .map((c) {
                        final id = _toInt(c['id']);
                        if (id == null) return null;
                        return DropdownMenuItem<int>(
                          value: id,
                          child: Text(c['name']?.toString() ?? c['id'].toString()),
                        );
                      })
                      .whereType<DropdownMenuItem<int>>()
                      .toList(),
                  onChanged: (v) => setDialogState(() => clubId = v),
                ),
                const SizedBox(height: 8),
                ListTile(
                  title: Text(date == null ? 'Select Date' : date.toString().split(' ')[0]),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: date ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) setDialogState(() => date = picked);
                  },
                ),
                TextField(
                  controller: locationCtrl,
                  decoration: const InputDecoration(labelText: 'Location'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: notesCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Notes (optional)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );

    if (ok != true || eventTypeId == null || clubId == null || date == null) return;

    final d = date!;
    final eventDate = _fmtYmd(d);
    
    final put = await http.put(
      Uri.parse('$apiBase/events/${event['id']}'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'event_type_id': eventTypeId,
        'lions_club_id': clubId,
        'event_date': eventDate,
        'location': locationCtrl.text,
        'notes': notesCtrl.text,
      }),
    );

    if (!mounted) return;

    if (put.statusCode == 200) {
      await _load();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Event updated')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: ${put.body}')));
    }
  }

  Future<void> _deleteEvent(int eventId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Event?'),
        content: const Text('This will remove the event and all volunteer assignments.'),
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

    final url = '$apiBase/events/$eventId';
    debugPrint('DEBUG: EventsPage delete eventId=$eventId apiBase=$apiBase url=$url');
    try {
      final res = await http.delete(Uri.parse(url));
      debugPrint('DEBUG: EventsPage delete response status=${res.statusCode} body=${res.body}');
      if (!mounted) return;

      if (res.statusCode == 200 || res.statusCode == 204) {
        await _load();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Event deleted')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: ${res.statusCode} ${res.body}')));
      }
    } catch (e, st) {
      debugPrint('ERROR: _deleteEvent exception: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete error: $e')));
    }
  }

@override
Widget build(BuildContext context) {
  print('DEBUG: EventsPage build');
  return Scaffold(
    appBar: AppBar(
      title: const Text('Events'),
      backgroundColor: Colors.red,
      actions: [
        // NEW: Event Type Management button (admin/super only)
        FutureBuilder<bool>(
          future: Future.wait([AuthStore.isAdmin(), AuthStore.isSuper()])
              .then((results) => results[0] || results[1]),
          builder: (context, snapshot) {
            if (snapshot.data != true) return const SizedBox.shrink();
            return IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Manage Event Types & Templates',
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                final memberId = prefs.getInt('member_id') ?? 0;
                if (!mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EventTypeManagementPage(memberId: memberId),
                  ),
                );
              },
            );
          },
        ),
        IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
            : Column(
                children: [
                  // Filter Row - FIXED: Remove Card, add generous padding
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal, // ✅ Mobile fix stays
                      child: Row(
                        children: [
                          // Event Type Filter
                          SizedBox(
                            width: 220, // ✅ Back to comfortable width
                            child: DropdownButtonFormField<int?>(
                              value: _filterEventTypeId,
                              decoration: const InputDecoration(
                                hintText: 'Event Type',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              ),
                              style: const TextStyle(
                                color: Colors.black,
                                decoration: TextDecoration.none,
                                fontSize: 14,
                              ),
                              items: [
                                const DropdownMenuItem<int?>(
                                  value: null,
                                  child: Text(
                                    'All Types',
                                    style: TextStyle(decoration: TextDecoration.none),
                                  ),
                                ),
                                ..._eventTypes.map((et) => DropdownMenuItem<int?>(
                                      value: _toInt(et['id']),
                                      child: Text(
                                        et['name']?.toString() ?? '',
                                        style: const TextStyle(decoration: TextDecoration.none),
                                      ),
                                    )),
                              ],
                              onChanged: (val) {
                                setState(() => _filterEventTypeId = val);
                                _load();
                              },
                            ),
                          ),
                          const SizedBox(width: 16), // ✅ More breathing room
                          // Date Range Filter
                          SizedBox(
                            width: 200, // ✅ Comfortable width
                            child: DropdownButtonFormField<String?>(
                              value: _filterDateRange,
                              decoration: const InputDecoration(
                                hintText: 'Date Range',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              ),
                              style: const TextStyle(
                                color: Colors.black,
                                decoration: TextDecoration.none,
                                fontSize: 14,
                              ),
                              items: const [
                                DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('All Dates', style: TextStyle(decoration: TextDecoration.none)),
                                ),
                                DropdownMenuItem<String?>(
                                  value: 'today',
                                  child: Text('Today', style: TextStyle(decoration: TextDecoration.none)),
                                ),
                                DropdownMenuItem<String?>(
                                  value: 'week',
                                  child: Text('Next 7 Days', style: TextStyle(decoration: TextDecoration.none)),
                                ),
                                DropdownMenuItem<String?>(
                                  value: 'month',
                                  child: Text('Next 30 Days', style: TextStyle(decoration: TextDecoration.none)),
                                ),
                              ],
                              onChanged: (val) {
                                setState(() => _filterDateRange = val);
                                _load();
                              },
                            ),
                          ),
                          const SizedBox(width: 16), // ✅ More breathing room
                          // Clear Filters Button
                          ElevatedButton.icon(
                            onPressed: () {
                              setState(() {
                                _filterEventTypeId = null;
                                _filterDateRange = null;
                              });
                              _load();
                            },
                            icon: const Icon(Icons.clear),
                            label: const Text('Clear'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Table
                  Expanded(
                    child: _events.isEmpty
                        ? const Center(child: Text('No events found'))
                        : SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                                headingRowColor: MaterialStateProperty.all(Colors.red.shade100),
                                border: TableBorder.all(color: Colors.grey.shade300),
                                columns: [
                                  const DataColumn(label: Text('Event Type', style: TextStyle(fontWeight: FontWeight.bold))),
                                  const DataColumn(label: Text('Club', style: TextStyle(fontWeight: FontWeight.bold))),
                                  const DataColumn(label: Text('Date', style: TextStyle(fontWeight: FontWeight.bold))),
                                  const DataColumn(label: Text('Location', style: TextStyle(fontWeight: FontWeight.bold))),
                                  if (_isAdmin)
                                    const DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                                ],
                                rows: _events.map((e) {
                                  final eventId = _toInt(e['id']) ?? 0;
                                  return DataRow(
                                    cells: [
                                      DataCell(
                                        Text(e['event_type']?.toString() ?? ''),
                                        onTap: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(builder: (_) => EventDetailPage(eventId: eventId)),
                                        ),
                                      ),
                                      DataCell(
                                        Text(e['club_name']?.toString() ?? ''),
                                        onTap: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(builder: (_) => EventDetailPage(eventId: eventId)),
                                        ),
                                      ),
                                      DataCell(
                                        Text(e['date']?.toString() ?? e['event_date']?.toString() ?? ''),
                                        onTap: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(builder: (_) => EventDetailPage(eventId: eventId)),
                                        ),
                                      ),
                                      DataCell(
                                        Text(e['location']?.toString() ?? ''),
                                        onTap: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(builder: (_) => EventDetailPage(eventId: eventId)),
                                        ),
                                      ),
                                      if (_isAdmin)
                                        DataCell(
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
                                                onPressed: () => _openEditEventDialog(e as Map<String, dynamic>),
                                                tooltip: 'Edit',
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                                                onPressed: () => _deleteEvent(eventId),
                                                tooltip: 'Delete',
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
    // Move floatingActionButton inside the Scaffold:
    floatingActionButton: _isAdmin
        ? FloatingActionButton.extended(
            onPressed: _openCreateEventDialog,
            icon: const Icon(Icons.add),
            label: const Text('Create Event'),
            backgroundColor: Colors.red,
          )
        : null,
  );
  }
}