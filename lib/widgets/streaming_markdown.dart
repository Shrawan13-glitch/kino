import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import '../utils/table_builder.dart';
import '../utils/blockquote_component.dart';

List<MarkdownComponent> _components(BuildContext context) {
  return [
    ...MarkdownComponent.globalComponents.where((c) => c is! BlockQuote),
    BeautifulBlockQuote(),
  ];
}

class StreamingMarkdown extends StatefulWidget {
  final String content;
  final bool isStreaming;

  const StreamingMarkdown({
    super.key,
    required this.content,
    this.isStreaming = false,
  });

  @override
  State<StreamingMarkdown> createState() => _StreamingMarkdownState();
}

class _StreamingMarkdownState extends State<StreamingMarkdown> {
  String _displayContent = '';

  @override
  void initState() {
    super.initState();
    _displayContent = _preprocess(widget.content);
  }

  @override
  void didUpdateWidget(StreamingMarkdown old) {
    super.didUpdateWidget(old);
    if (widget.content.isEmpty) {
      _displayContent = '';
      return;
    }
    _displayContent = _preprocess(widget.content);
  }

  static String _preprocess(String text) {
    return text.replaceAllMapped(
      RegExp(r'^-{3,}\s*$', multiLine: true),
      (_) => '⸻',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_displayContent.isEmpty) return const SizedBox.shrink();

    return RepaintBoundary(
      child: Align(
        alignment: Alignment.centerLeft,
        child: _wrapAntiShrink(
          GptMarkdown(
            _displayContent,
            tableBuilder: tableWidget,
            components: _components(context),
          ),
        ),
      ),
    );
  }

  Widget _wrapAntiShrink(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          width: constraints.maxWidth,
          child: child,
        );
      },
    );
  }
}
