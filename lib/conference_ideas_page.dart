import 'dart:convert';

import 'package:flutter/material.dart';

import 'api_client.dart';
import 'auth_store.dart';

class ConferenceIdeasPage extends StatefulWidget {
  const ConferenceIdeasPage({super.key});

  @override
  State<ConferenceIdeasPage> createState() => _ConferenceIdeasPageState();
}

class _ConferenceIdeasPageState extends State<ConferenceIdeasPage> {
  List<dynamic> _ideas = [];
  bool _isLoading = true;
  bool _canModerate = false;
  String? _error;

  int? _ideaIdFrom(dynamic value) => int.tryParse(value?.toString() ?? '');

  @override
  void initState() {
    super.initState();
    _loadIdeas();
  }

  Future<void> _loadIdeas() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final permissions = await Future.wait([
        AuthStore.isSuper(),
        AuthStore.isConferenceMember(),
      ]);
      _canModerate = permissions[0] || permissions[1];

      final res = await ApiClient.get('/conference_ideas');
      if (res.statusCode != 200) {
        throw Exception('Failed to load ideas: ${res.body}');
      }

      _ideas = jsonDecode(res.body) as List<dynamic>;
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _openAddIdeaDialog() async {
    final titleCtrl = TextEditingController();
    final categoryCtrl = TextEditingController();
    final descriptionCtrl = TextEditingController();
    String? dialogError;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Add Conference Idea'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: categoryCtrl,
                  decoration: const InputDecoration(labelText: 'Category'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: descriptionCtrl,
                  decoration: const InputDecoration(labelText: 'Description'),
                  minLines: 4,
                  maxLines: 8,
                ),
                if (dialogError != null) ...[
                  const SizedBox(height: 8),
                  Text(dialogError!, style: const TextStyle(color: Colors.red)),
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
                  setDlg(() => dialogError = 'Title is required');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Post'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;

    final res = await ApiClient.post('/conference_ideas', body: {
      'title': titleCtrl.text.trim(),
      'category': categoryCtrl.text.trim(),
      'description': descriptionCtrl.text.trim(),
    });

    if (!mounted) return;
    if (res.statusCode == 201) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Idea posted')),
      );
      _loadIdeas();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Post failed: ${res.body}')),
      );
    }
  }

  Future<void> _updateStatus(int ideaId, String status) async {
    final res = await ApiClient.put('/conference_ideas/$ideaId/status', body: {
      'status': status,
    });

    if (!mounted) return;
    if (res.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Idea updated')),
      );
      _loadIdeas();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update failed: ${res.body}')),
      );
    }
  }

  Future<void> _deleteIdea(int ideaId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Idea'),
        content: const Text('Are you sure you want to remove this idea?'),
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

    if (ok != true) return;

    final res = await ApiClient.delete('/conference_ideas/$ideaId');
    if (!mounted) return;
    if (res.statusCode == 204) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Idea deleted')),
      );
      _loadIdeas();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: ${res.body}')),
      );
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'accepted':
        return Colors.green;
      case 'declined':
        return Colors.red;
      case 'under_review':
        return Colors.orange;
      default:
        return Colors.blueGrey;
    }
  }

  String _prettyStatus(String status) {
    return status
        .split('_')
        .map((part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Conference Ideas'),
        backgroundColor: Colors.red,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadIdeas,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Add Idea',
            onPressed: _openAddIdeaDialog,
            icon: const Icon(Icons.add_comment),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : _ideas.isEmpty
                  ? const Center(child: Text('No conference ideas yet'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _ideas.length,
                      itemBuilder: (context, index) {
                        final idea = _ideas[index] as Map<String, dynamic>;
                        final status = (idea['status'] ?? 'new').toString();
                        final category = (idea['category'] ?? '').toString();
                        final description = (idea['description'] ?? '').toString();
                        final createdBy = (idea['created_by_name'] ?? 'Unknown').toString();
                        final createdAt = (idea['created_at'] ?? '').toString();

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            (idea['title'] ?? '').toString(),
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                    horizontal: 10, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: _statusColor(status).withOpacity(0.12),
                                                  borderRadius: BorderRadius.circular(999),
                                                ),
                                                child: Text(
                                                  _prettyStatus(status),
                                                  style: TextStyle(
                                                    color: _statusColor(status),
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                              if (category.isNotEmpty)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(
                                                      horizontal: 10, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: Colors.grey.shade200,
                                                    borderRadius: BorderRadius.circular(999),
                                                  ),
                                                  child: Text(category),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (_canModerate)
                                      PopupMenuButton<String>(
                                        onSelected: (value) {
                                          final ideaId = _ideaIdFrom(idea['id']);
                                          if (ideaId == null) {
                                            if (!mounted) return;
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                  content: Text('Invalid idea id')),
                                            );
                                            return;
                                          }
                                          if (value == 'delete') {
                                            _deleteIdea(ideaId);
                                          } else {
                                            _updateStatus(ideaId, value);
                                          }
                                        },
                                        itemBuilder: (context) => const [
                                          PopupMenuItem(value: 'new', child: Text('Mark New')),
                                          PopupMenuItem(
                                              value: 'under_review',
                                              child: Text('Mark Under Review')),
                                          PopupMenuItem(value: 'accepted', child: Text('Mark Accepted')),
                                          PopupMenuItem(value: 'declined', child: Text('Mark Declined')),
                                          PopupMenuDivider(),
                                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                                        ],
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                if (description.isNotEmpty) Text(description),
                                const SizedBox(height: 10),
                                Text(
                                  'Posted by $createdBy${createdAt.isNotEmpty ? ' on $createdAt' : ''}',
                                  style: TextStyle(
                                    color: Colors.grey.shade700,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddIdeaDialog,
        backgroundColor: Colors.red,
        icon: const Icon(Icons.lightbulb_outline),
        label: const Text('Add Idea'),
      ),
    );
  }
}
