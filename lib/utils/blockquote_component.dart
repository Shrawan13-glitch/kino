import 'package:flutter/material.dart';
import 'package:gpt_markdown/custom_widgets/markdown_config.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

class BeautifulBlockQuote extends InlineMd {
  @override
  bool get inline => false;

  @override
  RegExp get exp => RegExp(
    r"(?:(?:^)\ *>[^\n]+)(?:(?:\n)\ *>[^\n]+)*",
    dotAll: true,
    multiLine: true,
  );

  @override
  InlineSpan span(BuildContext context, String text, GptMarkdownConfig config) {
    final lines = text.split('\n');
    final buf = StringBuffer();
    for (final line in lines) {
      var s = line.trimLeft();
      if (s.startsWith('>')) {
        s = s.substring(1);
        if (s.startsWith(' ')) s = s.substring(1);
      }
      buf.writeln(s);
    }
    final content = buf.toString().trim();
    final innerSpans = MarkdownComponent.generate(context, content, config, true);
    final theme = Theme.of(context);

    return TextSpan(
      children: [
        WidgetSpan(
          alignment: PlaceholderAlignment.top,
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border(
                left: BorderSide(color: theme.colorScheme.primary, width: 3),
              ),
            ),
            child: config.getRich(TextSpan(children: innerSpans)),
          ),
        ),
      ],
    );
  }
}

/// Filters blockquote markers out of content (for streaming).
String stripBlockquotes(String text) {
  if (!text.contains('>')) return text;
  return text.split('\n').map((line) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('>')) {
      var rest = trimmed.substring(1);
      if (rest.startsWith(' ')) rest = rest.substring(1);
      return rest;
    }
    return line;
  }).join('\n');
}
