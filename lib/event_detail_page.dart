import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'widgets/email_html_editor.dart'; // selector: exports stub for Windows
import 'config.dart';

class EventDetailPage extends StatefulWidget {
  final dynamic eventId;
  final bool autoOpenSendAll;
  final bool autoOpenNewEventPreview;

  const EventDetailPage({
    super.key,
    required this.eventId,
    this.autoOpenSendAll = false,
    this.autoOpenNewEventPreview = false,
  });

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
  //String? _clubEmail;
  //String? _clubPhone;

  final TextEditingController _notesController = TextEditingController();
  bool _isEditingNotes = false;
  bool _openedAutoPreview = false;

  bool get _isOther {
    final t = _event?['event_type']?.toString() ?? '';
    final idStr = _event?['event_type_id']?.toString() ?? '';
    return t == 'Other' || idStr == '4';
  }

  bool get _hasUnassigned =>
      _roles.any((r) => (r['volunteer_name']?.toString().trim().isEmpty ?? true));

  int get _assignedCount =>
      _roles.where((r) => (r['volunteer_name']?.toString().trim().isNotEmpty ?? false)).length;
  int get _unassignedCount => _roles.length - _assignedCount;

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

  Future<Map<String, String>?> _showEmailPreview({required String mode}) async {
    final flags = <String, dynamic>{'dry_run': true};
    if (mode == 'assigned') flags['only_assigned'] = true;
    if (mode == 'resend') flags['resend_unfilled'] = true;

    http.Response res;
    try {
      debugPrint('DEBUG: EventDetailPage _showEmailPreview -> $apiBase/events/${widget.eventId}/notify');
      res = await http.post(
        Uri.parse('$apiBase/events/${widget.eventId}/notify'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(flags),
      );
      debugPrint('DEBUG: EventDetailPage _showEmailPreview status=${res.statusCode} body=${res.body}');
    } catch (e) {
      if (!mounted) return null;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(title: const Text('Preview failed'), content: Text('Network error: $e')),
      );
      return null;
    }
    if (res.statusCode != 200) {
      if (!mounted) return null;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(title: const Text('Preview failed'), content: Text(res.body)),
      );
      return null;
    }

    final data = json.decode(res.body) as Map<String, dynamic>;
    final subjectCtrl = TextEditingController(text: (data['subject'] ?? '').toString());
    String bodyHtml = (data['body_html'] ?? '').toString();
    final recipients = data['recipients']?.toString() ?? '';

    final eventNotes = _event?['notes']?.toString() ?? '';
    final onlyAssigned = mode == 'assigned';

    // Patch notes + roles (supports {{roles_html}} or UL-wrapped token or an existing UL/OL under the heading)
    bodyHtml = _patchNotesAndRoles(
      bodyHtml,
      notes: eventNotes,
      onlyAssigned: onlyAssigned,
    );

    final editorCtrl = EmailHtmlEditorController();
    final editableHtml = _extractBodyHtml(bodyHtml);
    String previewHtml = bodyHtml;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        bool showEditor = false;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => DefaultTabController(
            length: 2,
            child: AlertDialog(
              title: Text(switch (mode) {
                'assigned' => 'Preview: Email Assigned',
                'new' => 'Preview: New Event Email',
                _ => 'Preview: Resend to All',
              }),
              content: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 900,
                  maxHeight: MediaQuery.of(context).size.height * 0.8,
                ),
                child: SizedBox(
                  width: 820,
                  child: Column(
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Recipients: $recipients', style: const TextStyle(color: Colors.grey)),
                      ),
                      const SizedBox(height: 8),
                      TextField(controller: subjectCtrl, decoration: const InputDecoration(labelText: 'Subject')),
                      const SizedBox(height: 12),
                      TabBar(
                        tabs: const [Tab(text: 'Preview'), Tab(text: 'Edit')],
                        onTap: (i) async {
                          if (i == 1 && !showEditor) {
                            Future.delayed(const Duration(milliseconds: 10), () {
                              setDialogState(() => showEditor = true);
                            });
                          }
                          if (i == 0) {
                            final edited = (await editorCtrl.getHtml()).trim();
                            final merged = _mergeIntoBody(bodyHtml, edited.isEmpty ? editableHtml : edited);
                            setDialogState(() => previewHtml = merged);
                          }
                        },
                      ),
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
                                if (!showEditor) {
                                  return const Center(child: CircularProgressIndicator());
                                }
                                return EmailHtmlEditor(
                                  controller: editorCtrl,
                                  initialHtml: editableHtml,
                                );
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

    if (ok == true) {
      final editedHtml = (await editorCtrl.getHtml()).trim();
      final mergedHtml = _mergeIntoBody(bodyHtml, editedHtml.isEmpty ? editableHtml : editedHtml);
      return {
        'subject': subjectCtrl.text.trim(),
        'body_html': mergedHtml,
      };
    }
    return null;
  }

  // Replace {{notes}} and roles section with our table/list including volunteer_name
  String _patchNotesAndRoles(
    String html, {
    required String notes,
    required bool onlyAssigned,
  }) {
    var out = html;

    // notes
    out = out.replaceAll(
      RegExp(r'{{\s*notes\s*}}', caseSensitive: false),
      _escapeHtml(notes),
    );

    final rolesTable = _buildRolesTableHtml(onlyAssigned: onlyAssigned);

    // explicit token
    out = out.replaceAll(
      RegExp(r'{{\s*roles_html\s*}}', caseSensitive: false),
      rolesTable,
    );

    // common wrapped form <ul><li>{{roles_html}}</li></ul>
    out = out.replaceAll(
      RegExp(r'<ul[^>]*>\s*<li[^>]*>\s*{{\s*roles_html\s*}}\s*</li>\s*</ul>',
          caseSensitive: false, dotAll: true),
      rolesTable,
    );

    // replace a UL/OL directly following "Volunteer Roles" heading
    out = out.replaceAllMapped(
      RegExp(
        r'(<h[23][^>]*>\s*Volunteer Roles\s*:?<\/h[23]>\s*)(?:<ul[^>]*>[\s\S]*?<\/ul>|<ol[^>]*>[\s\S]*?<\/ol>)',
        caseSensitive: false,
      ),
      (m) => '${m.group(1)}$rolesTable',
    );

    return out;
  }

  // Build a horizontally scrollable roles table
  String _buildRolesTableHtml({required bool onlyAssigned}) {
    final buffer = StringBuffer();
    buffer.write('''
<div style="max-width:100%; overflow-x:auto;">
  <table style="border-collapse:collapse; min-width:650px; width:800px;">
    <thead>
      <tr>
        <th style="text-align:left; padding:8px; border:1px solid #ddd; background:#f5f5f5;">Role</th>
        <th style="text-align:left; padding:8px; border:1px solid #ddd; background:#f5f5f5;">Time In</th>
        <th style="text-align:left; padding:8px; border:1px solid #ddd; background:#f5f5f5;">Time Out</th>
        <th style="text-align:left; padding:8px; border:1px solid #ddd; background:#f5f5f5;">Volunteer</th>
      </tr>
    </thead>
    <tbody>
''');

    for (final r in _roles) {
      if (r is! Map) continue;
      final role = _escapeHtml(r['role_name']?.toString() ?? '');
      final timeIn = _escapeHtml(_fmtTime(r['time_in']?.toString()));
      final timeOut = _escapeHtml(_fmtTime(r['time_out']?.toString()));
      final rawName = (r['volunteer_name'] ?? r['name'])?.toString() ?? '';
      final hasName = rawName.trim().isNotEmpty;

      if (onlyAssigned && !hasName) continue;

      final volunteerName = hasName ? _escapeHtml(rawName) : 'Unassigned';

      buffer.write('''
      <tr>
        <td style="padding:8px; border:1px solid #ddd;">$role</td>
        <td style="padding:8px; border:1px solid #ddd; white-space:nowrap;">$timeIn</td>
        <td style="padding:8px; border:1px solid #ddd; white-space:nowrap;">$timeOut</td>
        <td style="padding:8px; border:1px solid #ddd;">$volunteerName</td>
      </tr>
''');
    }

    buffer.write('''
    </tbody>
  </table>
</div>
''');
    return buffer.toString();
  }

  String _fmtTime(String? t) {
    if (t == null) return '';
    final m = RegExp(r'^(\d{1,2}:\d{2})').firstMatch(t);
    return m != null ? m.group(1)! : t;
  }

  // Extract just the <body> inner HTML for editing
  String _extractBodyHtml(String html) {
    final lower = html.toLowerCase();
    final bodyOpen = lower.indexOf('<body');
    if (bodyOpen >= 0) {
      final openEnd = html.indexOf('>', bodyOpen);
      if (openEnd >= 0) {
        final bodyClose = lower.indexOf('</body>', openEnd + 1);
        if (bodyClose > openEnd) {
          final inner = html.substring(openEnd + 1, bodyClose);
          return _sanitizeFragment(inner);
        }
      }
    }
    return _sanitizeFragment(html);
  }

  String _sanitizeFragment(String html) {
    return html
        .replaceAll(RegExp(r'<!DOCTYPE[^>]*>', caseSensitive: false), '')
        .replaceAll(RegExp(r'</?(html|head|body)[^>]*>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false), '')
        .trim();
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

  String _escapeHtml(String s) {
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
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
    debugPrint('DEBUG: EventDetailPage _load eventId=${widget.eventId}');
    try {
      final res = await http.get(Uri.parse('$apiBase/events/${widget.eventId}'));
      debugPrint('DEBUG: EventDetail GET /events/${widget.eventId} status=${res.statusCode} body=${res.body}');
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        debugPrint('DEBUG: EventDetail parsed payload keys=${data.keys.toList()} rolesPresent=${data.containsKey("roles")}');
        _event = data['event'] as Map<String, dynamic>;
        _roles = data['roles'] as List<dynamic>;
        _notesController.text = _event!['notes']?.toString() ?? '';
        debugPrint('DEBUG: EventDetail roles.length=${_roles.length}');
        setState(() => _loading = false);

        if (!_openedAutoPreview) {
          _openedAutoPreview = true;
          if (widget.autoOpenNewEventPreview) {
            await _sendNewEventWithPreview();
          } else if (widget.autoOpenSendAll) {
            await _sendResendToAll();
          }
        }
      } else {
        setState(() {
          _error = 'Failed: ${res.statusCode} ${res.body}';
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
    final draft = await _showEmailPreview(mode: 'resend');
    if (draft == null) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sending email to all...')));
    try {
      debugPrint('DEBUG: EventDetailPage _sendResendToAll -> $apiBase/events/${widget.eventId}/notify');
      final res = await http.post(
        Uri.parse('$apiBase/events/${widget.eventId}/notify'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'resend_unfilled': true,
          'subject': draft['subject'],
          'body_html': draft['body_html'],
        }),
      );
      debugPrint('DEBUG: EventDetailPage _sendResendToAll status=${res.statusCode} body=${res.body}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.statusCode == 200 ? 'Email sent to all members.' : 'Failed (${res.statusCode}): ${res.body}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _sendAssignedReminder() async {
     final draft = await _showEmailPreview(mode: 'resend');
    if (draft == null) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sending email to all...')));
    try {
      debugPrint('DEBUG: EventDetailPage _sendResendToAll sending -> $apiBase/events/${widget.eventId}/notify payloadKeys=${draft.keys.length}');
      final res = await http.post(
        Uri.parse('$apiBase/events/${widget.eventId}/notify'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'resend_unfilled': true,
          'subject': draft['subject'],
          'body_html': draft['body_html'],
        }),
      );
      debugPrint('DEBUG: EventDetailPage _sendResendToAll status=${res.statusCode} body=${res.body}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Email sent to all members.')));
      } else {
        // show dialog with server response to help diagnose
       await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Send failed'),
            content: Text('Status: ${res.statusCode}\n\n${res.body}'),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
          ),
        );
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed (${res.statusCode}): ${res.body}')));
      }
    } catch (e) {
      debugPrint('ERROR: EventDetailPage _sendResendToAll exception: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(title: const Text('Send failed (network)'), content: Text('Error: $e')),
      );
    }

    /*final draft = await _showEmailPreview(mode: 'assigned');
    if (draft == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sending reminder to assigned volunteers...')));
    try {
      debugPrint('DEBUG: EventDetailPage _sendResendToAll sending -> $apiBase/events/${widget.eventId}/notify payloadKeys=${draft.keys.length}');
      final res = await http.post(
        Uri.parse('$apiBase/events/${widget.eventId}/notify'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'only_assigned': true,
          'subject': draft['subject'],
          'body_html': draft['body_html'],
        }),
      );
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.statusCode == 200 ? 'Reminder sent to assigned volunteers.' : 'Failed (${res.statusCode}): ${res.body}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }*/
  }

  Future<void> _sendNewEventWithPreview() async {
    final draft = await _showEmailPreview(mode: 'new');
    if (draft == null) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sending new event email...')));
    try {
      debugPrint('DEBUG: EventDetailPage _sendNewEventWithPreview -> $apiBase/events/${widget.eventId}/notify');
      final res = await http.post(
        Uri.parse('$apiBase/events/${widget.eventId}/notify'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'subject': draft['subject'],
          'body_html': draft['body_html'],
        }),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.statusCode == 200 ? 'New event email sent.' : 'Failed (${res.statusCode}): ${res.body}')),
      );
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
                  return [r['role_name'] ?? '', r['time_in'] ?? '', r['time_out'] ?? '', volunteer, ''];
                }).toList(),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                cellAlignment: pw.Alignment.centerLeft,
                border: pw.TableBorder.all(),
                columnWidths: {
                  0: const pw.FlexColumnWidth(2),
                  1: const pw.FlexColumnWidth(1.5),
                  2: const pw.FlexColumnWidth(1.5),
                  3: const pw.FlexColumnWidth(2),
                  4: const pw.FlexColumnWidth(2.5),
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
      final eventTypeId =
          _event!['event_type_id'] is int ? _event!['event_type_id'] : int.parse(_event!['event_type_id'].toString());
      final clubId = _event!['club_id'] is int ? _event!['club_id'] : int.parse(_event!['club_id'].toString());

      debugPrint('DEBUG: EventDetailPage _saveNotes -> PUT $apiBase/events/${widget.eventId}');
      final res = await http.put(
        Uri.parse('$apiBase/events/${widget.eventId}'),
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
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
    debugPrint('DEBUG: EventDetailPage _volunteerSelf -> POST $apiBase/events/${widget.eventId}/volunteer');
    final post = await http.post(
      Uri.parse('$apiBase/events/${widget.eventId}/volunteer'),
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
            const Text('We understand that circumstances change!', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const Text('To withdraw from your volunteer commitment, please contact the club secretary:'),
            const SizedBox(height: 16),]
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
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
    debugPrint('DEBUG: EventDetailPage _pickVolunteer -> GET $apiBase/members?club_id=$clubId');
    final res = await http.get(Uri.parse('$apiBase/members?club_id=$clubId'));
    if (res.statusCode != 200) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to load members')));
      }
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
                      ...members.map(
                        (m) => RadioListTile<dynamic>(
                          value: m['id'],
                          groupValue: selectedMemberId,
                          title: Text(m['name'] ?? ''),
                          subtitle: Text(m['email'] ?? ''),
                          onChanged: (v) => setDialogState(() => selectedMemberId = v),
                        ),
                      ),
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
    debugPrint('DEBUG: EventDetailPage _pickVolunteer -> POST $apiBase/events/${widget.eventId}/volunteer');
    final post = await http.post(
      Uri.parse('$apiBase/events/${widget.eventId}/volunteer'),
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

    debugPrint('DEBUG: EventDetailPage _addRole -> POST $apiBase/events/${widget.eventId}/roles');
    final res = await http.post(
      Uri.parse('$apiBase/events/${widget.eventId}/roles'),
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

  Future<void> _deleteRole(int roleId) async {
    if (!_isAdmin || !_isOther) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Role?'),
        content: const Text('This will remove the role and any volunteer assignment for this event.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );

    if (ok != true) return;

    debugPrint('DEBUG: EventDetailPage _deleteRole -> DELETE $apiBase/events/${widget.eventId}/roles/$roleId');
    final res = await http.delete(Uri.parse('$apiBase/events/${widget.eventId}/roles/$roleId'));
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
                FloatingActionButton.extended(
                  heroTag: 'fab-email-assigned',
                  onPressed: _sendAssignedReminder,
                  icon: const Icon(Icons.mark_email_unread_outlined),
                  label: const Text('Email Assigned'),
                  backgroundColor: Colors.blue,
                ),
                const SizedBox(height: 10),
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
                                return DataRow(
                                  cells: [
                                    DataCell(Text(r['role_name'] ?? '')),
                                    DataCell(Text(r['time_in'] ?? '')),
                                    DataCell(Text(r['time_out'] ?? '')),
                                    DataCell(Text(
                                      hasVolunteer ? volunteer : 'Unassigned',
                                      style: TextStyle(
                                        color: hasVolunteer ? Colors.black : Colors.grey,
                                        fontWeight: isCurrentUser ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    )),
                                    DataCell(
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
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
                                  ],
                                );
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
                                          _event!['notes']?.toString().isEmpty ?? true
                                              ? 'No notes yet'
                                              : _event!['notes'].toString(),
                                          style: TextStyle(
                                            color: _event!['notes']?.toString().isEmpty ?? true
                                                ? Colors.grey
                                                : Colors.black,
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