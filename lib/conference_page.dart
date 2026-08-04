import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'api_client.dart';
import 'auth_store.dart';
import 'config.dart';
import 'conference_ideas_page.dart';
import 'conference_section_tree.dart';

String? buildConferenceAttachmentUrl({
  required String bucket,
  required String storageKey,
  required String defaultS3Region,
  String? thumbnailStorageKey,
}) {
  final normalizedBucket = bucket.trim();
  final resolvedStorageKey = (thumbnailStorageKey ?? storageKey).trim();
  if (normalizedBucket.isEmpty || resolvedStorageKey.isEmpty) {
    return null;
  }

  return 'https://$normalizedBucket.s3.$defaultS3Region.amazonaws.com/$resolvedStorageKey';
}

class ConferencePage extends StatefulWidget {
  const ConferencePage({super.key});

  @override
  State<ConferencePage> createState() => _ConferencePageState();
}

class _ConferencePageState extends State<ConferencePage> {
  static const int _maxAttachmentBytes = 10 * 1024 * 1024;
  static const int _hardAttachmentCapBytes = 15 * 1024 * 1024;
  static const String _defaultS3Region = 'ap-southeast-2';

  static const Map<String, String> _extensionToMime = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'pdf': 'application/pdf',
    'doc': 'application/msword',
    'docx':
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx':
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'txt': 'text/plain',
  };

  static final List<String> _allowedExtensions = _extensionToMime.keys.toList();

  Map<String, dynamic> _conference = {};
  List<Map<String, dynamic>> _customSections = [];
  final Map<int, List<Map<String, dynamic>>> _attachmentsBySection = {};
  final Set<int> _expandedSectionIds = {};
  final Set<int> _loadingAttachmentSectionIds = {};
  final Set<int> _uploadingAttachmentSectionIds = {};
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
      final rawSections = _conference['sections'];
      if (rawSections is List) {
        _customSections = rawSections
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        _customSections.sort((a, b) {
          final aOrder =
              int.tryParse((a['sort_order'] ?? '').toString()) ?? 1 << 30;
          final bOrder =
              int.tryParse((b['sort_order'] ?? '').toString()) ?? 1 << 30;
          if (aOrder != bOrder) return aOrder.compareTo(bOrder);

          final aTitle = (a['section_title'] ?? '').toString().toLowerCase();
          final bTitle = (b['section_title'] ?? '').toString().toLowerCase();
          return aTitle.compareTo(bTitle);
        });
      } else {
        _customSections = [];
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  int? _asInt(dynamic value) => int.tryParse(value?.toString() ?? '');

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }

  String? _mimeFromFilename(String filename) {
    final parts = filename.toLowerCase().split('.');
    if (parts.length < 2) return null;
    return _extensionToMime[parts.last];
  }

  IconData _iconForAttachment(Map<String, dynamic> attachment) {
    final kind = (attachment['file_kind'] ?? '').toString();
    final mime = (attachment['mime_type'] ?? '').toString();
    if (kind == 'image' || mime.startsWith('image/'))
      return Icons.image_outlined;
    if (mime.contains('pdf')) return Icons.picture_as_pdf_outlined;
    if (mime.contains('word') || mime.contains('document')) {
      return Icons.description_outlined;
    }
    if (mime.contains('sheet') || mime.contains('excel'))
      return Icons.table_chart_outlined;
    if (mime.contains('powerpoint') || mime.contains('presentation')) {
      return Icons.slideshow_outlined;
    }
    return Icons.attach_file;
  }

  String? _buildAttachmentUrl(
    Map<String, dynamic> attachment, {
    bool thumbnail = false,
  }) {
    final directDownloadUrl = (attachment['download_url'] ?? '')
        .toString()
        .trim();
    if (directDownloadUrl.isNotEmpty) {
      if (directDownloadUrl.startsWith('http://') ||
          directDownloadUrl.startsWith('https://')) {
        return directDownloadUrl;
      }
      if (directDownloadUrl.startsWith('/')) {
        return '$apiBase$directDownloadUrl';
      }
      return '$apiBase/$directDownloadUrl';
    }

    final bucket = (attachment['bucket'] ?? '').toString();
    final storageKey = (attachment['storage_key'] ?? '').toString();
    final thumbnailStorageKey = (attachment['thumbnail_storage_key'] ?? '')
        .toString();
    return buildConferenceAttachmentUrl(
      bucket: bucket,
      storageKey: storageKey,
      defaultS3Region: _defaultS3Region,
      thumbnailStorageKey: thumbnail ? thumbnailStorageKey : null,
    );
  }

  Widget _buildAttachmentPreview(Map<String, dynamic> attachment) {
    final mime = (attachment['mime_type'] ?? '').toString();
    final kind = (attachment['file_kind'] ?? '').toString();
    final isImage = kind == 'image' || mime.startsWith('image/');

    if (!isImage) {
      return Icon(_iconForAttachment(attachment), color: Colors.red);
    }

    final previewUrl =
        _buildAttachmentUrl(attachment, thumbnail: true) ??
        _buildAttachmentUrl(attachment);
    if (previewUrl == null) {
      return Icon(_iconForAttachment(attachment), color: Colors.red);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 48,
        height: 48,
        child: Image.network(
          previewUrl,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            color: Colors.grey.shade200,
            child: const Icon(Icons.broken_image_outlined),
          ),
        ),
      ),
    );
  }

  Future<void> _loadAttachmentsForSection(
    int sectionId, {
    bool force = false,
  }) async {
    if (!force && _attachmentsBySection.containsKey(sectionId)) return;
    if (_loadingAttachmentSectionIds.contains(sectionId)) return;

    setState(() => _loadingAttachmentSectionIds.add(sectionId));
    try {
      final endpoint = _canEdit
          ? '/conference_sections/$sectionId/attachments?include_archived=true'
          : '/conference_sections/$sectionId/attachments';
      final res = await ApiClient.get(endpoint);
      if (res.statusCode != 200) {
        throw Exception('Failed to load attachments: ${res.body}');
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final items = (data['items'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

      if (!mounted) return;
      setState(() => _attachmentsBySection[sectionId] = items);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) {
        setState(() => _loadingAttachmentSectionIds.remove(sectionId));
      }
    }
  }

  Future<void> _toggleSectionAttachments(int sectionId) async {
    final willExpand = !_expandedSectionIds.contains(sectionId);
    setState(() {
      if (willExpand) {
        _expandedSectionIds.add(sectionId);
      } else {
        _expandedSectionIds.remove(sectionId);
      }
    });

    if (willExpand) {
      await _loadAttachmentsForSection(sectionId);
    }
  }

  Future<void> _uploadAttachment(Map<String, dynamic> section) async {
    final sectionId = _asInt(section['id']);
    if (sectionId == null) return;

    final picked = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: _allowedExtensions,
    );
    if (picked == null || picked.files.isEmpty) return;

    final file = picked.files.first;
    final filename = file.name.trim();
    final mimeType = _mimeFromFilename(filename);
    final fileSizeBytes = file.size;

    if (mimeType == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unsupported file type')));
      return;
    }
    if (fileSizeBytes > _hardAttachmentCapBytes) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'File exceeds hard cap (${_formatBytes(_hardAttachmentCapBytes)}).',
          ),
        ),
      );
      return;
    }
    if (fileSizeBytes > _maxAttachmentBytes) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'File exceeds max size (${_formatBytes(_maxAttachmentBytes)}).',
          ),
        ),
      );
      return;
    }

    setState(() => _uploadingAttachmentSectionIds.add(sectionId));
    try {
      final presignRes = await ApiClient.post(
        '/conference_sections/$sectionId/attachments/presign',
        body: {
          'filename': filename,
          'mime_type': mimeType,
          'file_size_bytes': fileSizeBytes,
        },
      );
      if (presignRes.statusCode != 200) {
        throw Exception('Presign failed: ${presignRes.body}');
      }

      final presignBody = jsonDecode(presignRes.body) as Map<String, dynamic>;
      final uploadUrlRaw = (presignBody['upload_url'] ?? '').toString();
      final storageKey = (presignBody['storage_key'] ?? '').toString();
      final requiredHeaders = Map<String, dynamic>.from(
        presignBody['required_headers'] ?? {},
      );
      final isMock = presignBody['is_mock'] == true;

      if (uploadUrlRaw.isEmpty || storageKey.isEmpty) {
        throw Exception('Invalid presign response');
      }

      final Uint8List? bytes = file.bytes;
      if (bytes == null) {
        throw Exception('Could not read file bytes for upload');
      }

      final uploadHeaders = <String, String>{};
      requiredHeaders.forEach((key, value) {
        uploadHeaders[key] = value.toString();
      });
      uploadHeaders['Content-Type'] = mimeType;

      final uploadUri =
          uploadUrlRaw.startsWith('http://') ||
              uploadUrlRaw.startsWith('https://')
          ? Uri.parse(uploadUrlRaw)
          : Uri.parse('$apiBase$uploadUrlRaw');

      final uploadRes = await http.put(
        uploadUri,
        headers: uploadHeaders,
        body: bytes,
      );
      if (uploadRes.statusCode < 200 || uploadRes.statusCode >= 300) {
        throw Exception('Upload failed (${uploadRes.statusCode})');
      }

      final createRes = await ApiClient.post(
        '/conference_sections/$sectionId/attachments',
        body: {
          'storage_key': storageKey,
          'original_filename': filename,
          'mime_type': mimeType,
          'file_size_bytes': fileSizeBytes,
        },
      );
      if (createRes.statusCode != 201) {
        throw Exception('Attachment save failed: ${createRes.body}');
      }

      await _loadAttachmentsForSection(sectionId, force: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isMock
                ? 'Attachment saved (mock upload mode)'
                : 'Attachment uploaded',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) {
        setState(() => _uploadingAttachmentSectionIds.remove(sectionId));
      }
    }
  }

  Future<void> _archiveAttachment(int sectionId, int attachmentId) async {
    final res = await ApiClient.put(
      '/conference_sections/$sectionId/attachments/$attachmentId/archive',
    );
    if (!mounted) return;

    if (res.statusCode == 200) {
      await _loadAttachmentsForSection(sectionId, force: true);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Attachment archived')));
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Archive failed: ${res.body}')));
    }
  }

  Future<void> _restoreAttachment(int sectionId, int attachmentId) async {
    final res = await ApiClient.put(
      '/conference_sections/$sectionId/attachments/$attachmentId/restore',
    );
    if (!mounted) return;

    if (res.statusCode == 200) {
      await _loadAttachmentsForSection(sectionId, force: true);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Attachment restored')));
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Restore failed: ${res.body}')));
    }
  }

  Future<void> _moveAttachment(
    int sectionId,
    int attachmentId,
    int delta,
  ) async {
    final existing = _attachmentsBySection[sectionId] ?? const [];
    final active = existing
        .where((a) => (a['status'] ?? 'active').toString() != 'archived')
        .toList();
    final archived = existing
        .where((a) => (a['status'] ?? 'active').toString() == 'archived')
        .toList();

    final oldIndex = active.indexWhere((a) => _asInt(a['id']) == attachmentId);
    if (oldIndex == -1) return;
    final newIndex = oldIndex + delta;
    if (newIndex < 0 || newIndex >= active.length) return;

    final reordered = List<Map<String, dynamic>>.from(active);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);

    setState(() {
      _attachmentsBySection[sectionId] = [...reordered, ...archived];
    });

    final payload = {
      'attachment_orders': [
        for (var i = 0; i < reordered.length; i++)
          {'attachment_id': reordered[i]['id'], 'sort_order': i},
      ],
    };
    final res = await ApiClient.put(
      '/conference_sections/$sectionId/attachments/reorder',
      body: payload,
    );

    if (res.statusCode != 200) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Attachment reorder failed: ${res.body}')),
      );
      await _loadAttachmentsForSection(sectionId, force: true);
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

  bool _isImageAttachment(Map<String, dynamic> attachment) {
    final mime = (attachment['mime_type'] ?? '').toString();
    final kind = (attachment['file_kind'] ?? '').toString();
    return kind == 'image' || mime.startsWith('image/');
  }

  Future<void> _openAttachment(Map<String, dynamic> attachment) async {
    final fileUrl = _buildAttachmentUrl(attachment);
    if (fileUrl == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Attachment URL is unavailable')),
      );
      return;
    }

    if (_isImageAttachment(attachment)) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                        child: Text(
                          (attachment['original_filename'] ?? 'Image')
                              .toString(),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const Divider(height: 1),
                Expanded(
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4,
                    child: Image.network(
                      fileUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) =>
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(20),
                              child: Text('Could not load image preview'),
                            ),
                          ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _AttachmentWebViewPage(
          url: fileUrl,
          title: (attachment['original_filename'] ?? 'Attachment').toString(),
        ),
      ),
    );
  }

  Future<void> _openEditDialog() async {
    final titleCtrl = TextEditingController(
      text: _displayText('title', empty: 'Conference'),
    );
    final themeCtrl = TextEditingController(
      text: _displayText('theme', empty: ''),
    );
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

    final res = await ApiClient.put(
      '/conference',
      body: {
        'title': titleCtrl.text.trim(),
        'conference_date': selectedDate == null
            ? null
            : DateFormat('yyyy-MM-dd').format(selectedDate!),
        'theme': themeCtrl.text.trim(),
      },
    );

    if (!mounted) return;
    if (res.statusCode == 200) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Conference updated')));
      _loadConference();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save failed: ${res.body}')));
    }
  }

  Future<void> _openSectionDialog({
    Map<String, dynamic>? existing,
    int? forcedParentId,
  }) async {
    final titleCtrl = TextEditingController(
      text: (existing?['section_title'] ?? '').toString(),
    );
    final bodyCtrl = TextEditingController(
      text: (existing?['section_body'] ?? '').toString(),
    );
    final sortCtrl = TextEditingController(
      text: (existing?['sort_order'] ?? '').toString(),
    );
    final initialParentId = (forcedParentId ?? _asInt(existing?['parent_id']))
        ?.toString();
    String? selectedParentId = initialParentId;
    String? localError;

    final activeParents = _customSections.where((section) {
      final status = (section['status'] ?? 'draft').toString();
      final sectionId = _asInt(section['id']);
      final isArchived = status == 'archived';
      return !isArchived && sectionId != _asInt(existing?['id']);
    }).toList();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(existing == null ? 'Add Section' : 'Edit Section'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Section Title'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: bodyCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Section Content',
                  ),
                  minLines: 4,
                  maxLines: 10,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: sortCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Sort Order (optional)',
                    helperText: 'Lower numbers appear first.',
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  value: selectedParentId,
                  decoration: const InputDecoration(
                    labelText: 'Parent Section',
                    helperText:
                        'Leave as top-level to create a new parent section.',
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Top-level section'),
                    ),
                    ...activeParents.map((section) {
                      final title = (section['section_title'] ?? '').toString();
                      return DropdownMenuItem<String?>(
                        value: _asInt(section['id'])?.toString(),
                        child: Text(title.isEmpty ? 'Untitled section' : title),
                      );
                    }),
                  ],
                  onChanged: (value) => setDlg(() => selectedParentId = value),
                ),
                if (localError != null) ...[
                  const SizedBox(height: 8),
                  Text(localError!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (titleCtrl.text.trim().isEmpty) {
                  setDlg(() => localError = 'Section title is required');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: Text(existing == null ? 'Add' : 'Save'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;

    final sortOrder = int.tryParse(sortCtrl.text.trim());
    final parentIdValue =
        selectedParentId == null || selectedParentId!.trim().isEmpty
        ? null
        : int.tryParse(selectedParentId!);
    final payload = {
      'section_title': titleCtrl.text.trim(),
      'section_body': bodyCtrl.text.trim(),
      if (sortOrder != null) 'sort_order': sortOrder,
      if (parentIdValue != null) 'parent_id': parentIdValue,
      if (parentIdValue == null && existing != null) 'parent_id': null,
    };

    final response = existing == null
        ? await ApiClient.post('/conference_sections', body: payload)
        : await ApiClient.put(
            '/conference_sections/${existing['id']}',
            body: payload,
          );

    if (!mounted) return;
    if (response.statusCode == 200 || response.statusCode == 201) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(existing == null ? 'Section added' : 'Section updated'),
        ),
      );
      _loadConference();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Section save failed: ${response.body}')),
      );
    }
  }

  Future<void> _deleteSection(Map<String, dynamic> section) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete Section'),
            content: Text(
              'Delete "${(section['section_title'] ?? '').toString()}"?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    final res = await ApiClient.delete('/conference_sections/${section['id']}');
    if (!mounted) return;

    if (res.statusCode == 200 || res.statusCode == 204) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Section archived')));
      _loadConference();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Delete failed: ${res.body}')));
    }
  }

  Future<void> _restoreSection(Map<String, dynamic> section) async {
    final sectionId = section['id'];
    final res = await ApiClient.put('/conference_sections/$sectionId/restore');
    if (!mounted) return;

    if (res.statusCode == 200) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Section restored')));
      _loadConference();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Restore failed: ${res.body}')));
    }
  }

  Future<void> _reorderActiveSections(
    List<Map<String, dynamic>> ordered,
  ) async {
    final payload = {
      'section_orders': [
        for (var i = 0; i < ordered.length; i++)
          {'section_id': ordered[i]['id'], 'sort_order': i},
      ],
    };

    final res = await ApiClient.put(
      '/conference_sections/reorder',
      body: payload,
    );
    if (!mounted) return;

    if (res.statusCode != 200) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Reorder failed: ${res.body}')));
      _loadConference();
    }
  }

  Widget _buildStatusChip(String status) {
    final normalized = status.trim().toLowerCase();
    final label = switch (normalized) {
      'in_review' => 'In Review',
      'approved' => 'Approved',
      'archived' => 'Archived',
      _ => 'Draft',
    };

    final colors = switch (normalized) {
      'approved' => (Colors.green.shade50, Colors.green.shade800),
      'in_review' => (Colors.orange.shade50, Colors.orange.shade900),
      'archived' => (Colors.grey.shade300, Colors.grey.shade800),
      _ => (Colors.blue.shade50, Colors.blue.shade800),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.$1,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: colors.$2,
        ),
      ),
    );
  }

  Widget _buildAttachmentPanel(Map<String, dynamic> section) {
    final sectionId = _asInt(section['id']);
    if (sectionId == null) return const SizedBox.shrink();

    final expanded = _expandedSectionIds.contains(sectionId);
    final isLoading = _loadingAttachmentSectionIds.contains(sectionId);
    final isUploading = _uploadingAttachmentSectionIds.contains(sectionId);
    final attachments = _attachmentsBySection[sectionId] ?? const [];
    final active = attachments
        .where((a) => (a['status'] ?? 'active').toString() != 'archived')
        .toList();
    final archived = attachments
        .where((a) => (a['status'] ?? 'active').toString() == 'archived')
        .toList();

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: () => _toggleSectionAttachments(sectionId),
                  icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
                  label: Text('Attachments (${attachments.length})'),
                ),
              ),
              if (_canEdit)
                FilledButton.tonalIcon(
                  onPressed: isUploading
                      ? null
                      : () => _uploadAttachment(section),
                  icon: isUploading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_file_outlined),
                  label: const Text('Upload'),
                ),
            ],
          ),
          if (expanded) ...[
            if (isLoading)
              const Padding(
                padding: EdgeInsets.all(8),
                child: LinearProgressIndicator(),
              )
            else if (attachments.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No attachments yet.'),
              )
            else ...[
              ...active.asMap().entries.map((entry) {
                final index = entry.key;
                final attachment = entry.value;
                final attachmentId = _asInt(attachment['id']);
                final filename =
                    (attachment['original_filename'] ?? 'Attachment')
                        .toString();
                final mime = (attachment['mime_type'] ?? '').toString();
                final bytes = _asInt(attachment['file_size_bytes']) ?? 0;
                final fileUrl = _buildAttachmentUrl(attachment);

                return ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 2),
                  onTap: () => _openAttachment(attachment),
                  leading: _buildAttachmentPreview(attachment),
                  title: Text(filename),
                  subtitle: Text('$mime • ${_formatBytes(bytes)}'),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      if (fileUrl != null)
                        IconButton(
                          tooltip: 'Copy file URL',
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: fileUrl),
                            );
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Attachment URL copied'),
                              ),
                            );
                          },
                          icon: const Icon(Icons.link_outlined),
                        ),
                      if (_canEdit && attachmentId != null) ...[
                        IconButton(
                          tooltip: 'Move up',
                          onPressed: index == 0
                              ? null
                              : () => _moveAttachment(
                                  sectionId,
                                  attachmentId,
                                  -1,
                                ),
                          icon: const Icon(Icons.arrow_upward),
                        ),
                        IconButton(
                          tooltip: 'Move down',
                          onPressed: index == active.length - 1
                              ? null
                              : () =>
                                    _moveAttachment(sectionId, attachmentId, 1),
                          icon: const Icon(Icons.arrow_downward),
                        ),
                        IconButton(
                          tooltip: 'Archive attachment',
                          onPressed: () =>
                              _archiveAttachment(sectionId, attachmentId),
                          icon: const Icon(
                            Icons.archive_outlined,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),
              if (archived.isNotEmpty) ...[
                const Divider(height: 20),
                Text(
                  'Archived Attachments',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 4),
                ...archived.map((attachment) {
                  final attachmentId = _asInt(attachment['id']);
                  final filename =
                      (attachment['original_filename'] ?? 'Attachment')
                          .toString();
                  final mime = (attachment['mime_type'] ?? '').toString();
                  final bytes = _asInt(attachment['file_size_bytes']) ?? 0;

                  return ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 2),
                    onTap: () => _openAttachment(attachment),
                    leading: _buildAttachmentPreview(attachment),
                    title: Text(filename),
                    subtitle: Text('$mime • ${_formatBytes(bytes)}'),
                    trailing: _canEdit && attachmentId != null
                        ? TextButton.icon(
                            onPressed: () =>
                                _restoreAttachment(sectionId, attachmentId),
                            icon: const Icon(Icons.restore),
                            label: const Text('Restore'),
                          )
                        : null,
                  );
                }),
              ],
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required Map<String, dynamic> section,
    required int depth,
    bool isArchived = false,
    bool showReorderHandle = false,
    int? index,
  }) {
    final title = (section['section_title'] ?? '').toString();
    final body = (section['section_body'] ?? '').toString();
    final children = (section['children'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();

    final card = Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: isArchived ? Colors.grey.shade100 : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(width: depth * 18),
                Expanded(
                  child: Text(
                    title.isEmpty ? 'Untitled Section' : title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (isArchived) ...[
                  _buildStatusChip('archived'),
                  const SizedBox(width: 8),
                ],
                if (_canEdit) ...[
                  IconButton(
                    tooltip: 'Edit section',
                    onPressed: () => _openSectionDialog(existing: section),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  if (!isArchived)
                    IconButton(
                      tooltip: 'Add subsection',
                      onPressed: () => _openSectionDialog(
                        forcedParentId: _asInt(section['id']),
                      ),
                      icon: const Icon(Icons.subdirectory_arrow_right),
                    ),
                  if (!isArchived)
                    IconButton(
                      tooltip: 'Archive section',
                      onPressed: () => _deleteSection(section),
                      icon: const Icon(
                        Icons.archive_outlined,
                        color: Colors.red,
                      ),
                    ),
                  if (showReorderHandle)
                    ReorderableDragStartListener(
                      index: index ?? 0,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(Icons.drag_handle),
                      ),
                    ),
                  if (isArchived)
                    TextButton.icon(
                      onPressed: () => _restoreSection(section),
                      icon: const Icon(Icons.restore),
                      label: const Text('Restore'),
                    ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Padding(
              padding: EdgeInsets.only(left: depth * 18),
              child: Text(body.isEmpty ? 'No content yet.' : body),
            ),
            _buildAttachmentPanel(section),
            if (children.isNotEmpty) ...[
              const SizedBox(height: 6),
              ...children.map(
                (child) => _buildSectionCard(
                  section: child,
                  depth: depth + 1,
                  isArchived: isArchived,
                ),
              ),
            ],
          ],
        ),
      ),
    );

    return Padding(
      key: ValueKey('section-${section['id']}'),
      padding: EdgeInsets.only(left: depth == 0 ? 0 : 8),
      child: card,
    );
  }

  Widget _buildCustomSections() {
    final archivedSections = _customSections
        .where((s) => (s['status'] ?? 'draft').toString() == 'archived')
        .toList();
    final activeTree = buildConferenceSectionTree(
      _customSections
          .where((s) => (s['status'] ?? 'draft').toString() != 'archived')
          .toList(),
      includeArchived: false,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.view_agenda_outlined, color: Colors.red),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Custom Sections',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_customSections.isEmpty)
              Text(
                _canEdit
                    ? 'No custom sections yet. Use Add Section to create your first planning section.'
                    : 'No custom sections yet.',
              ),
            if (activeTree.isNotEmpty && _canEdit)
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: activeTree.length,
                onReorder: (oldIndex, newIndex) async {
                  if (newIndex > oldIndex) {
                    newIndex -= 1;
                  }
                  final reordered = List<Map<String, dynamic>>.from(activeTree);
                  final moved = reordered.removeAt(oldIndex);
                  reordered.insert(newIndex, moved);

                  final reorderedRoots = reordered
                      .asMap()
                      .entries
                      .map((entry) {
                        final section = Map<String, dynamic>.from(entry.value);
                        section['sort_order'] = entry.key;
                        return section;
                      })
                      .toList();
                  final rebuilt = <Map<String, dynamic>>[];
                  for (final section in reorderedRoots) {
                    rebuilt.add(section);
                  }
                  for (final section in _customSections) {
                    final sectionId = _asInt(section['id']);
                    final isAlreadyAdded = rebuilt.any(
                      (item) => _asInt(item['id']) == sectionId,
                    );
                    if (!isAlreadyAdded) {
                      final updatedSection = Map<String, dynamic>.from(section);
                      final matchingRoot = reorderedRoots.where(
                        (item) => _asInt(item['id']) == sectionId,
                      );
                      if (matchingRoot.isNotEmpty) {
                        updatedSection['sort_order'] =
                            matchingRoot.first['sort_order'];
                      }
                      rebuilt.add(updatedSection);
                    }
                  }

                  setState(() {
                    _customSections = rebuilt;
                  });

                  await _reorderActiveSections(reorderedRoots);
                },
                itemBuilder: (context, index) {
                  final section = activeTree[index];
                  return _buildSectionCard(
                    section: section,
                    depth: 0,
                    showReorderHandle: true,
                    index: index,
                  );
                },
              )
            else
              ...activeTree.map(
                (section) => _buildSectionCard(section: section, depth: 0),
              ),
            if (archivedSections.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Archived Sections',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
              ...archivedSections.map(
                (section) => _buildSectionCard(
                  section: section,
                  depth: 0,
                  isArchived: true,
                ),
              ),
            ],
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
          ? Center(
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 140),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _displayText('title', empty: 'Conference'),
                                style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (_canEdit)
                              IconButton(
                                tooltip: 'Edit conference header',
                                onPressed: _openEditDialog,
                                icon: const Icon(Icons.edit_outlined),
                              ),
                          ],
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
                            const Icon(
                              Icons.palette_outlined,
                              color: Colors.red,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text('Theme: ${_displayText('theme')}'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (_customSections.isNotEmpty) _buildCustomSections(),
              ],
            ),
      floatingActionButton: _canEdit
          ? FloatingActionButton.extended(
              heroTag: 'addConferenceSectionFab',
              onPressed: () => _openSectionDialog(),
              backgroundColor: Colors.red,
              icon: const Icon(Icons.add),
              label: const Text('Add Section'),
            )
          : null,
    );
  }
}

class _AttachmentWebViewPage extends StatefulWidget {
  const _AttachmentWebViewPage({required this.url, required this.title});

  final String url;
  final String title;

  @override
  State<_AttachmentWebViewPage> createState() => _AttachmentWebViewPageState();
}

class _AttachmentWebViewPageState extends State<_AttachmentWebViewPage> {
  late final WebViewController _controller;
  bool _isLoading = true;

  bool _isOfficeDocumentUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.doc') ||
        lower.contains('.docx') ||
        lower.contains('.xls') ||
        lower.contains('.xlsx') ||
        lower.contains('.ppt') ||
        lower.contains('.pptx');
  }

  @override
  void initState() {
    super.initState();
    final sourceUrl = _isOfficeDocumentUrl(widget.url)
        ? 'https://docs.google.com/gview?embedded=1&url=${Uri.encodeComponent(widget.url)}'
        : widget.url;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
          onWebResourceError: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(sourceUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
        backgroundColor: Colors.red,
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
