/*import 'package:flutter/material.dart';
import 'package:html_editor_enhanced/html_editor.dart';

class EmailHtmlEditorController {
  final HtmlEditorController htmlController = HtmlEditorController();
  Future<String> getHtml() async => await htmlController.getText();
}

class EmailHtmlEditor extends StatefulWidget {
  final EmailHtmlEditorController controller;
  final String initialHtml;
  const EmailHtmlEditor({super.key, required this.controller, required this.initialHtml});

  @override
  State<EmailHtmlEditor> createState() => _EmailHtmlEditorState();
}

class _EmailHtmlEditorState extends State<EmailHtmlEditor> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        Expanded(
          child: HtmlEditor(
            controller: widget.controller.htmlController,
            htmlEditorOptions: HtmlEditorOptions(
              hint: 'Edit email body...',
              initialText: widget.initialHtml, // raw HTML
              shouldEnsureVisible: true,
            ),
            // Use default toolbar; avoids version-specific button classes
            otherOptions: const OtherOptions(height: double.infinity),
          ),
        ),
      ],
    );
  }
}*/