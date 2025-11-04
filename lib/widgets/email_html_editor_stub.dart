import 'package:flutter/material.dart';

class EmailHtmlEditorController {
  final TextEditingController textController = TextEditingController();
  Future<String> getHtml() async => textController.text;
}

class EmailHtmlEditor extends StatefulWidget {
  final EmailHtmlEditorController controller;
  final String initialHtml;
  const EmailHtmlEditor({super.key, required this.controller, required this.initialHtml});

  @override
  State<EmailHtmlEditor> createState() => _EmailHtmlEditorState();
}

class _EmailHtmlEditorState extends State<EmailHtmlEditor> {
  late final TextEditingController _ctrl = widget.controller.textController;

  @override
  void initState() {
    super.initState();
    _ctrl.text = widget.initialHtml;
  }

  void _wrapSelection(String before, String after) {
    final sel = _ctrl.selection;
    final text = _ctrl.text;
    final start = sel.start.clamp(0, text.length);
    final end = sel.end.clamp(0, text.length);
    final selected = (start >= 0 && end >= 0 && start <= end) ? text.substring(start, end) : '';
    final newText = text.replaceRange(start, end, '$before$selected$after');
    final newPos = start + before.length + selected.length + after.length;
    _ctrl.value = TextEditingValue(text: newText, selection: TextSelection.collapsed(offset: newPos));
  }

  Future<void> _insertLink() async {
    final sel = _ctrl.selection;
    final selected = sel.isValid && !sel.isCollapsed
        ? _ctrl.text.substring(sel.start, sel.end)
        : 'link text';
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final urlCtrl = TextEditingController(text: 'https://');
        return AlertDialog(
          title: const Text('Insert link'),
          content: TextField(controller: urlCtrl, decoration: const InputDecoration(labelText: 'URL')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, urlCtrl.text.trim()), child: const Text('Insert')),
          ],
        );
      },
    );
    if (url == null || url.isEmpty) return;
    _wrapSelection('<a href="$url">', '</a>');
  }

  void _makeList({required bool ordered}) {
    final text = _ctrl.text;
    final sel = _ctrl.selection;
    final start = sel.start.clamp(0, text.length);
    final end = sel.end.clamp(0, text.length);

    // Expand to full lines
    final lineStart = text.lastIndexOf('\n', start - 1) + 1;
    final lineEnd = text.indexOf('\n', end);
    final selectionEnd = lineEnd == -1 ? text.length : lineEnd;
    final block = text.substring(lineStart, selectionEnd);
    final lines = block.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    if (lines.isEmpty) {
      _wrapSelection(ordered ? '<ol><li>' : '<ul><li>', '</li></${ordered ? 'ol' : 'ul'}>');
      return;
    }
    final li = lines.map((l) => '<li>$l</li>').join();
    final wrapped = '${ordered ? '<ol>' : '<ul>'}$li</${ordered ? 'ol' : 'ul'}>';
    final newText = text.replaceRange(lineStart, selectionEnd, wrapped);
    _ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: lineStart + wrapped.length),
    );
  }

  void _clearSimpleFormatting() {
    final t = _ctrl.text;
    final cleaned = t
        .replaceAll(RegExp(r'</?(b|strong|i|em|u|h[1-6]|p|span)[^>]*>', caseSensitive: false), '')
        .replaceAll(RegExp(r'</?(ul|ol|li)[^>]*>', caseSensitive: false), '')
        .replaceAll(RegExp(r'</?a[^>]*>', caseSensitive: false), '');
    _ctrl.value = TextEditingValue(text: cleaned, selection: TextSelection.collapsed(offset: cleaned.length));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Wrap(
          spacing: 4,
          children: [
            IconButton(tooltip: 'Bold', icon: const Icon(Icons.format_bold), onPressed: () => _wrapSelection('<b>', '</b>')),
            IconButton(tooltip: 'Italic', icon: const Icon(Icons.format_italic), onPressed: () => _wrapSelection('<i>', '</i>')),
            IconButton(tooltip: 'Underline', icon: const Icon(Icons.format_underline), onPressed: () => _wrapSelection('<u>', '</u>')),
            IconButton(tooltip: 'H2', icon: const Icon(Icons.title), onPressed: () => _wrapSelection('<h2>', '</h2>')),
            IconButton(tooltip: 'Paragraph', icon: const Icon(Icons.short_text), onPressed: () => _wrapSelection('<p>', '</p>')),
            IconButton(tooltip: 'Bulleted list', icon: const Icon(Icons.format_list_bulleted), onPressed: () => _makeList(ordered: false)),
            IconButton(tooltip: 'Numbered list', icon: const Icon(Icons.format_list_numbered), onPressed: () => _makeList(ordered: true)),
            IconButton(tooltip: 'Link', icon: const Icon(Icons.link), onPressed: _insertLink),
            IconButton(tooltip: 'Clear formatting', icon: const Icon(Icons.format_clear), onPressed: _clearSimpleFormatting),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: TextField(
            controller: _ctrl,
            maxLines: null,
            expands: true,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ),
      ],
    );
  }
}