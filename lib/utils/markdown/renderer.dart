import 'package:flutter/material.dart';
import 'ast.dart';
import 'parser.dart';

class MarkdownStyle {
  final Color textColor;
  final Color secondaryTextColor;
  final Color codeColor;
  final Color codeBackground;
  final Color blockquoteBar;
  final Color blockquoteBg;
  final Color linkColor;
  final Color tableBorder;
  final Color hrColor;
  final Color checkboxChecked;
  final Color checkboxBorder;
  final double bodySize;
  final double codeSize;
  final double lineHeight;
  final EdgeInsets bodyPadding;
  final EdgeInsets headingPadding;
  final EdgeInsets codeBlockPadding;
  final EdgeInsets blockquotePadding;
  final EdgeInsets listPadding;
  final EdgeInsets tablePadding;
  final double borderRadius;

  const MarkdownStyle({
    this.textColor = const Color(0xFF1A1A2E),
    this.secondaryTextColor = const Color(0xFF6B7280),
    this.codeColor = const Color(0xFFD97706),
    this.codeBackground = const Color(0xFFF3F4F6),
    this.blockquoteBar = const Color(0xFF3B82F6),
    this.blockquoteBg = const Color(0xFFEFF6FF),
    this.linkColor = const Color(0xFF2563EB),
    this.tableBorder = const Color(0xFFE5E7EB),
    this.hrColor = const Color(0xFFE5E7EB),
    this.checkboxChecked = const Color(0xFF3B82F6),
    this.checkboxBorder = const Color(0xFF9CA3AF),
    this.bodySize = 15,
    this.codeSize = 13,
    this.lineHeight = 1.6,
    this.bodyPadding = const EdgeInsets.only(bottom: 8),
    this.headingPadding = const EdgeInsets.only(top: 12, bottom: 6),
    this.codeBlockPadding = const EdgeInsets.all(16),
    this.blockquotePadding = const EdgeInsets.fromLTRB(14, 10, 14, 10),
    this.listPadding = const EdgeInsets.only(left: 4),
    this.tablePadding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    this.borderRadius = 12,
  });

  factory MarkdownStyle.from(BuildContext context) {
    final theme = Theme.of(context);
    final bright = theme.brightness == Brightness.light;
    return MarkdownStyle(
      textColor: theme.colorScheme.onSurface,
      secondaryTextColor: theme.colorScheme.onSurface.withValues(alpha: 0.6),
      codeColor: bright ? const Color(0xFFD97706) : const Color(0xFFFBBF24),
      codeBackground: bright ? const Color(0xFFF3F4F6) : const Color(0xFF1F2937),
      blockquoteBar: theme.colorScheme.primary,
      blockquoteBg: theme.colorScheme.primary.withValues(alpha: 0.08),
      linkColor: theme.colorScheme.primary,
      tableBorder: theme.dividerColor,
      hrColor: theme.dividerColor,
      checkboxChecked: theme.colorScheme.primary,
      checkboxBorder: theme.colorScheme.onSurface.withValues(alpha: 0.4),
    );
  }

  double headingSize(int level) {
    return switch (level) {
      1 => 24, 2 => 20, 3 => 17, 4 => 15, 5 => 14, _ => 13,
    };
  }

  FontWeight headingWeight(int level) {
    return switch (level) {
      1 || 2 => FontWeight.w700,
      3 || 4 => FontWeight.w600,
      _ => FontWeight.w500,
    };
  }

  EdgeInsets headingPad(int level) {
    final top = switch (level) { 1 => 16, 2 => 14, 3 => 12, _ => 10 };
    return EdgeInsets.only(top: top.toDouble(), bottom: 4);
  }

  TextStyle baseText() => TextStyle(
    color: textColor, fontSize: bodySize, height: lineHeight,
  );
}

class MarkdownRender extends StatelessWidget {
  final String data;
  final bool selectable;
  final MarkdownStyle? style;

  const MarkdownRender({
    super.key,
    required this.data,
    this.selectable = false,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final s = style ?? MarkdownStyle.from(context);
    final blocks = parseMarkdown(data);
    if (blocks.isEmpty) return const SizedBox.shrink();

    final widgets = <Widget>[];
    for (final block in blocks) {
      final w = _buildBlock(block, context, s);
      if (w != null) widgets.add(w);
    }

    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );

    if (selectable) return SelectionArea(child: column);
    return column;
  }

  Widget? _buildBlock(BlockNode node, BuildContext context, MarkdownStyle s) {
    return switch (node) {
      HeadingBlock(:final level, :final children) =>
        Padding(
          padding: s.headingPad(level),
          child: Text.rich(
            _inlineSpan(children, s, baseStyle: TextStyle(
              color: s.textColor,
              fontSize: s.headingSize(level),
              fontWeight: s.headingWeight(level),
              height: 1.3,
            )),
          ),
        ),
      ParagraphBlock(:final children) =>
        Padding(
          padding: s.bodyPadding,
          child: Text.rich(
            _inlineSpan(children, s),
          ),
        ),
      CodeBlockNode(:final code) =>
        Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Container(
            width: double.infinity,
            padding: s.codeBlockPadding,
            decoration: BoxDecoration(
              color: s.codeBackground,
              borderRadius: BorderRadius.circular(s.borderRadius),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(
                code.endsWith('\n') ? code.substring(0, code.length - 1) : code,
                style: TextStyle(
                  color: s.codeColor,
                  fontSize: s.codeSize,
                  fontFamily: 'monospace',
                  height: 1.5,
                ),
              ),
            ),
          ),
        ),
      BlockquoteBlock(:final children) =>
        Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Container(
            width: double.infinity,
            padding: s.blockquotePadding,
            decoration: BoxDecoration(
              color: s.blockquoteBg,
              borderRadius: BorderRadius.circular(8),
              border: Border(left: BorderSide(color: s.blockquoteBar, width: 3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children.map((b) => _buildBlock(b, context, s) ?? const SizedBox.shrink()).toList(),
            ),
          ),
        ),
      ListBlock(:final items, :final ordered, :final start) =>
        Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: items.asMap().entries.map((e) {
              final idx = e.key;
              final item = e.value;
              return _buildListItem(item, idx, ordered, start, context, s);
            }).toList(),
          ),
        ),
      TableBlock(:final rows) =>
        Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: s.tableBorder),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Table(
                border: TableBorder.all(color: s.tableBorder, width: 0.5),
                columnWidths: _buildTableColWidths(rows),
                children: rows.map((row) {
                  return TableRow(
                    decoration: row.isHeader
                        ? BoxDecoration(color: s.codeBackground)
                        : null,
                    children: row.cells.map((cell) {
                      return Padding(
                        padding: s.tablePadding,
                        child: Text.rich(
                          _inlineSpan(cell.children, s, baseStyle: TextStyle(
                            color: s.textColor,
                            fontSize: s.bodySize - 1,
                            fontWeight: row.isHeader ? FontWeight.w600 : null,
                          )),
                        ),
                      );
                    }).toList(),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ThematicBreak() =>
        Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Container(height: 1, color: s.hrColor),
        ),
      _ => null,
    };
  }

  Map<int, TableColumnWidth> _buildTableColWidths(List<TableRowData> rows) {
    if (rows.isEmpty || rows.first.cells.isEmpty) return {};
    final n = rows.first.cells.length;
    return {for (int i = 0; i < n; i++) i: const FlexColumnWidth()};
  }

  Widget _buildListItem(
    ListItem item, int index, bool ordered, int start,
    BuildContext context, MarkdownStyle s,
  ) {
    final bullet = ordered ? '${start + index}.' : null;
    return Padding(
      padding: s.listPadding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: item.checked != null
                ? _checkbox(item.checked!, s)
                : Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Text(
                        bullet ?? '\u2022',
                        style: TextStyle(
                          color: s.textColor,
                          fontSize: s.bodySize,
                          height: s.lineHeight,
                        ),
                      ),
                    ),
                  ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: item.children.map((b) => _buildBlock(b, context, s) ?? const SizedBox.shrink()).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _checkbox(bool checked, MarkdownStyle s) {
    return Padding(
      padding: EdgeInsets.only(top: 3, right: 8),
      child: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: checked ? s.checkboxChecked : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: s.checkboxBorder, width: 1.5),
        ),
        child: checked
            ? const Icon(Icons.check, size: 12, color: Colors.white)
            : null,
      ),
    );
  }

  InlineSpan _inlineSpan(
    List<InlineNode> nodes,
    MarkdownStyle s, {
    TextStyle? baseStyle,
  }) {
    final spans = <InlineSpan>[];
    for (final node in nodes) {
      switch (node) {
        case TextNode(:final text):
          spans.add(TextSpan(text: text));
        case BoldNode(:final children):
          spans.add(TextSpan(
            style: TextStyle(fontWeight: FontWeight.w700),
            children: [_inlineSpan(children, s, baseStyle: baseStyle)],
          ));
        case ItalicNode(:final children):
          spans.add(TextSpan(
            style: TextStyle(fontStyle: FontStyle.italic),
            children: [_inlineSpan(children, s, baseStyle: baseStyle)],
          ));
        case StrikethroughNode(:final children):
          spans.add(TextSpan(
            style: TextStyle(decoration: TextDecoration.lineThrough),
            children: [_inlineSpan(children, s, baseStyle: baseStyle)],
          ));
        case InlineCodeNode(:final code):
          spans.add(TextSpan(
            text: code,
            style: TextStyle(
              color: s.codeColor,
              fontSize: s.codeSize,
              fontFamily: 'monospace',
              backgroundColor: s.codeBackground,
            ),
          ));
        case LinkNode(:final children):
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: GestureDetector(
              onTap: () {/* link tap handled upstream */},
              child: Text.rich(
                _inlineSpan(children, s, baseStyle: baseStyle),
                style: TextStyle(
                  color: s.linkColor,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ));
        case ImageNode(:final url, :final alt):
          final label = alt ?? url;
          spans.add(TextSpan(
            text: '[image: $label]',
            style: TextStyle(color: s.secondaryTextColor, fontSize: s.codeSize, fontStyle: FontStyle.italic),
          ));
        case SoftBreak():
          spans.add(TextSpan(text: ' '));
        case HardBreak():
          spans.add(TextSpan(text: '\n'));
      }
    }
    return TextSpan(children: spans, style: baseStyle ?? s.baseText());
  }
}
