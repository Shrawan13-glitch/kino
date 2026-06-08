sealed class BlockNode {}

class DocumentBlock extends BlockNode {
  final List<BlockNode> children;
  DocumentBlock(this.children);
}

class HeadingBlock extends BlockNode {
  final int level;
  final List<InlineNode> children;
  HeadingBlock(this.level, this.children);
}

class ParagraphBlock extends BlockNode {
  final List<InlineNode> children;
  ParagraphBlock(this.children);
}

class CodeBlockNode extends BlockNode {
  final String code;
  final String? language;
  CodeBlockNode(this.code, {this.language});
}

class BlockquoteBlock extends BlockNode {
  final List<BlockNode> children;
  BlockquoteBlock(this.children);
}

class ListBlock extends BlockNode {
  final List<ListItem> items;
  final bool ordered;
  final int start;
  ListBlock(this.items, {this.ordered = false, this.start = 1});
}

class ListItem extends BlockNode {
  final List<BlockNode> children;
  final bool? checked;
  ListItem(this.children, {this.checked});
}

class TableBlock extends BlockNode {
  final List<TableRowData> rows;
  TableBlock(this.rows);
}

class TableRowData {
  final List<TableCellData> cells;
  final bool isHeader;
  TableRowData(this.cells, {this.isHeader = false});
}

class TableCellData {
  final List<InlineNode> children;
  TableCellData(this.children);
}

class ThematicBreak extends BlockNode {}

sealed class InlineNode {}

class TextNode extends InlineNode {
  final String text;
  TextNode(this.text);
}

class BoldNode extends InlineNode {
  final List<InlineNode> children;
  BoldNode(this.children);
}

class ItalicNode extends InlineNode {
  final List<InlineNode> children;
  ItalicNode(this.children);
}

class StrikethroughNode extends InlineNode {
  final List<InlineNode> children;
  StrikethroughNode(this.children);
}

class InlineCodeNode extends InlineNode {
  final String code;
  InlineCodeNode(this.code);
}

class LinkNode extends InlineNode {
  final String url;
  final String? title;
  final List<InlineNode> children;
  LinkNode(this.url, this.children, {this.title});
}

class ImageNode extends InlineNode {
  final String url;
  final String? alt;
  final String? title;
  ImageNode(this.url, {this.alt, this.title});
}

class SoftBreak extends InlineNode {}

class HardBreak extends InlineNode {}
