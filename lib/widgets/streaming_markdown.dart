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
    _displayContent = widget.content;
  }

  @override
  void didUpdateWidget(StreamingMarkdown old) {
    super.didUpdateWidget(old);
    if (widget.content.isEmpty) {
      _displayContent = '';
      return;
    }
    _displayContent = widget.content;
  }

  @override
  Widget build(BuildContext context) {
    if (_displayContent.isEmpty) return const SizedBox.shrink();

    return RepaintBoundary(
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.92,
          ),
          padding: const EdgeInsets.only(right: 24),
          child: _wrapAntiShrink(
            GptMarkdown(
              _displayContent,
              tableBuilder: tableWidget,
              components: _components(context),
            ),
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
