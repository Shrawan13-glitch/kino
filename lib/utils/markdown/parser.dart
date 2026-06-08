import 'ast.dart';

List<BlockNode> parseMarkdown(String text) {
  if (text.isEmpty) return [];
  final lines = text.split('\n').map((s) => _Line(s)).toList();
  final blocks = <BlockNode>[];
  int i = 0;

  while (i < lines.length) {
    final line = lines[i];
    if (line.isBlank) { i++; continue; }
    if (line.isThematicBreak) { blocks.add(ThematicBreak()); i++; continue; }
    if (line.heading != null) { blocks.add(HeadingBlock(line.heading!.$1, _parseInlines(line.heading!.$2))); i++; continue; }

    if (line.fence != null) {
      final fenceInfo = line.fence!;
      final codeLines = <String>[];
      int j = i + 1;
      while (j < lines.length) {
        final l = lines[j];
        if (l.fence != null && l.fence!.char == fenceInfo.char && l.fence!.length >= fenceInfo.length && !l.fence!.hasInfo) {
          j++;
          break;
        }
        codeLines.add(l.content);
        j++;
      }
      blocks.add(CodeBlockNode(codeLines.join('\n'), language: fenceInfo.info));
      i = j;
      continue;
    }

    if (line.bqDepth > 0) {
      final quoteLines = <String>[];
      while (i < lines.length && lines[i].bqDepth > 0) {
        quoteLines.add(lines[i].bqContent);
        i++;
      }
      blocks.add(BlockquoteBlock(parseMarkdown(quoteLines.join('\n'))));
      continue;
    }

    if (line.listMarker != null) {
      final items = <ListItem>[];
      while (i < lines.length) {
        final l = lines[i];
        if (l.listMarker == null) break;
        final marker = l.listMarker!;
        final itemLines = <String>[l.content.substring(marker.end).trimLeft()];
        i++;
        while (i < lines.length) {
          final n = lines[i];
          if (n.isBlank) {
            if (i + 1 < lines.length && lines[i + 1].listMarker != null) { i++; break; }
            i++; continue;
          }
          if (n.listMarker != null) break;
          if (n.bqDepth > 0 || n.fence != null) break;
          itemLines.add(n.content);
          i++;
        }
        final innerText = itemLines.join('\n');
        final innerBlocks = innerText.contains('\n')
            ? parseMarkdown(innerText)
            : <BlockNode>[ParagraphBlock(_parseInlines(innerText))];
        items.add(ListItem(innerBlocks, checked: marker.checked));
      }
      final ordered = items.isNotEmpty && lines[0].listMarker!.ordered;
      final start = ordered ? lines[0].listMarker!.start : 1;
      blocks.add(ListBlock(items, ordered: ordered, start: start));
      continue;
    }

    if (line.tableCells != null) {
      final rows = <TableRowData>[];
      while (i < lines.length) {
        final l = lines[i];
        if (l.tableCells == null) break;
        final cells = l.tableCells!;
        final isHeader = i + 1 < lines.length && lines[i + 1].isTableSep;
        rows.add(TableRowData(cells.map((c) => TableCellData(_parseInlines(c.trim()))).toList(), isHeader: isHeader));
        i++;
        if (isHeader && i < lines.length && lines[i].isTableSep) i++;
      }
      blocks.add(TableBlock(rows));
      continue;
    }

    final paraLines = <String>[];
    while (i < lines.length && _isParaLine(lines[i])) { paraLines.add(lines[i].content); i++; }
    blocks.add(ParagraphBlock(_parseInlines(paraLines.join('\n'))));
  }

  return blocks;
}

bool _isParaLine(_Line l) => !l.isBlank && l.heading == null && !l.isThematicBreak && l.fence == null && l.bqDepth == 0 && l.listMarker == null && l.tableCells == null;

class _Line {
  final String content;
  late final bool isBlank = content.trim().isEmpty;
  _FenceInfo? fence;
  bool isThematicBreak = false;
  (int, String)? heading;
  int bqDepth = 0;
  String bqContent = '';
  _ListMarker? listMarker;
  List<String>? tableCells;
  bool isTableSep = false;

  _Line(String raw) : content = raw { _classify(); }

  void _classify() {
    if (isBlank) return;
    final trimmed = content.trimLeft();
    final indent = content.length - trimmed.length;

    final f = RegExp(r'^(```|~~~)(\S*)\s*$').firstMatch(trimmed);
    if (f != null) {
      final char = f.group(1)!;
      final info = f.group(2) ?? '';
      fence = _FenceInfo(char, char.length, info.isNotEmpty ? info : null);
      return;
    }

    if (indent < 4 && RegExp(r'^(-{3,}|\*{3,}|_{3,})\s*$').hasMatch(trimmed)) {
      isThematicBreak = true;
      return;
    }

    if (indent < 4) {
      final h = RegExp(r'^(#{1,6})(?:\s+|$)(.*?)(?:\s+#+\s*)?$').firstMatch(trimmed);
      if (h != null) {
        heading = (h.group(1)!.length, h.group(2)?.trimLeft() ?? '');
        return;
      }
    }

    bqDepth = _bqDepth(trimmed);
    if (bqDepth > 0) { bqContent = trimmed.substring(bqDepth).trimLeft(); return; }

    if (indent < 4) {
      final m = _parseListMarker(trimmed);
      if (m != null) { listMarker = m; return; }
    }

    final t = RegExp(r'^\|(.+)\|$').firstMatch(trimmed);
    if (t != null) {
      tableCells = t.group(1)!.split('|').map((s) => s.trim()).toList();
      isTableSep = tableCells!.isNotEmpty && tableCells!.every((c) => RegExp(r'^:?-{3,}:?$').hasMatch(c.trim()));
      return;
    }
  }
}

int _bqDepth(String s) {
  int d = 0, i = 0;
    while (i < s.length) {
      while (i < s.length && s[i] == ' ') { i++; }
      if (i < s.length && s[i] == '>') { d++; i++; } else { break; }
    }
  return d;
}

class _FenceInfo {
  final String char;
  final int length;
  final String? info;
  bool get hasInfo => info != null;
  _FenceInfo(this.char, this.length, this.info);
}

class _ListMarker {
  final bool ordered;
  final int start;
  final int end;
  final bool? checked;
  _ListMarker({this.ordered = false, this.start = 1, required this.end, this.checked});
}

_ListMarker? _parseListMarker(String trimmed) {
  var m = RegExp(r'^[-*+]\s+\[([ xX])\]\s+').firstMatch(trimmed);
  if (m != null) return _ListMarker(end: m.end, checked: m.group(1) == 'x' || m.group(1) == 'X');
  m = RegExp(r'^[-*+](?:\s+|$)').firstMatch(trimmed);
  if (m != null) return _ListMarker(end: m.end);
  m = RegExp(r'^(\d+)[.](?:\s+|$)').firstMatch(trimmed);
  if (m != null) return _ListMarker(ordered: true, start: int.parse(m.group(1)!), end: m.end);
  return null;
}

List<InlineNode> _parseInlines(String text) {
  if (text.isEmpty) return [];
  final nodes = <InlineNode>[];
  int i = 0;

  void flush(int s, int e) { if (e > s) nodes.add(TextNode(text.substring(s, e))); }

  while (i < text.length) {
    final start = i;
    final c = text[i];

    if (c == '\\' && i + 1 < text.length) {
      nodes.add(TextNode(text[i + 1]));
      i += 2;
      continue;
    }

    if (c == '`') {
      int len = 0;
      while (i + len < text.length && text[i + len] == '`') { len++; }
      final delim = text.substring(i, i + len);
      final buf = StringBuffer();
      i += len;
      bool found = false;
      while (i < text.length) {
        if (i + len <= text.length && text.substring(i, i + len) == delim) {
          if (i + len < text.length && text[i + len] == '`') { buf.write(text[i]); i++; continue; }
          i += len;
          found = true;
          break;
        }
        buf.write(text[i] == '\n' ? ' ' : text[i]);
        i++;
      }
      String code = buf.toString();
      if (code.length >= 2 && code.startsWith(' ') && code.endsWith(' ')) {
        code = code.substring(1, code.length - 1);
      }
      nodes.add(InlineCodeNode(found ? code : '$delim$code'));
      continue;
    }

    if ((c == '*' || c == '_') && _leftFlanking(text, i)) {
      final char = c;
      int len = 0;
      while (i + len < text.length && text[i + len] == char) { len++; }
      bool done = false;

      if (len >= 2) {
        int j = i + 2;
        while (j < text.length - 1) {
          if (text[j] == char && text[j + 1] == char && _rightFlanking(text, j)) {
            nodes.add(BoldNode(_parseInlines(text.substring(i + 2, j))));
            i = j + 2;
            done = true;
            break;
          }
          j++;
        }
      }

      if (!done && len >= 1) {
        int j = i + 1;
        while (j < text.length) {
          if (text[j] == char && _rightFlanking(text, j) && (j + 1 >= text.length || text[j + 1] != char)) {
            if (j > i + 1) {
              nodes.add(ItalicNode(_parseInlines(text.substring(i + 1, j))));
              i = j + 1;
              done = true;
            }
            break;
          }
          if (text[j] == char && j + 1 < text.length && text[j + 1] == char) {
            j += 2;
          } else {
            j++;
          }
        }
      }

      if (!done) { nodes.add(TextNode(text.substring(i, i + len))); i += len; }
      continue;
    }

    if (c == '~' && i + 1 < text.length && text[i + 1] == '~') {
      int j = i + 2;
      bool found = false;
      while (j < text.length - 1) {
        if (text[j] == '~' && text[j + 1] == '~') {
          nodes.add(StrikethroughNode(_parseInlines(text.substring(i + 2, j))));
          i = j + 2; found = true; break;
        }
        j++;
      }
      if (!found) { nodes.add(TextNode('~~')); i += 2; }
      continue;
    }

    if (c == '!' && i + 1 < text.length && text[i + 1] == '[') {
      final altEnd = _findBracket(text, i + 1);
      if (altEnd != null && altEnd + 1 < text.length && text[altEnd + 1] == '(') {
        final parenEnd = text.indexOf(')', altEnd + 2);
        if (parenEnd > altEnd + 1) {
          final (url, title) = _parseUrl(text.substring(altEnd + 2, parenEnd));
          nodes.add(ImageNode(url, alt: text.substring(i + 2, altEnd), title: title));
          i = parenEnd + 1; continue;
        }
      }
      nodes.add(TextNode('!')); i++;
      continue;
    }

    if (c == '[') {
      final textEnd = _findBracket(text, i);
      if (textEnd != null && textEnd + 1 < text.length && text[textEnd + 1] == '(') {
        final parenEnd = text.indexOf(')', textEnd + 2);
        if (parenEnd > textEnd + 1) {
          final (url, title) = _parseUrl(text.substring(textEnd + 2, parenEnd));
          nodes.add(LinkNode(url, _parseInlines(text.substring(i + 1, textEnd)), title: title));
          i = parenEnd + 1; continue;
        }
      }
      nodes.add(TextNode('[')); i++;
      continue;
    }

    if (c == '\n') {
      if (i >= 2 && text[i - 1] == ' ' && text[i - 2] == ' ') {
        nodes.add(HardBreak());
      } else {
        nodes.add(SoftBreak());
      }
      i++;
      continue;
    }

    i++;
      while (i < text.length && !_spec(text[i])) { i++; }
    flush(start, i);
  }

  return _merge(nodes);
}

int? _findBracket(String s, int start) {
  int d = 0;
  for (int i = start; i < s.length; i++) {
    if (s[i] == '[') {
      d++;
    } else if (s[i] == ']') {
      if (d == 0) return i;
      d--;
    } else if (s[i] == '\\' && i + 1 < s.length) {
      i++;
    }
  }
  return null;
}

(String, String?) _parseUrl(String raw) {
  raw = raw.trim();
  if (raw.isEmpty) return ('', null);
  var m = RegExp(r'^(\S+)\s+"(.*?)"\s*$').firstMatch(raw);
  if (m != null) return (m.group(1)!, m.group(2));
  m = RegExp(r"^(\S+)\s+'(.*?)'\s*$").firstMatch(raw);
  if (m != null) return (m.group(1)!, m.group(2));
  return (raw, null);
}

bool _leftFlanking(String s, int i) => i == 0 || s[i - 1] == ' ' || s[i - 1] == '\n' || s[i - 1] == '*' || s[i - 1] == '_';
bool _rightFlanking(String s, int i) => i + 1 >= s.length || s[i + 1] == ' ' || s[i + 1] == '\n' || s[i + 1] == '*' || s[i + 1] == '_';
bool _spec(String c) => c == '*' || c == '_' || c == '~' || c == '`' || c == '[' || c == '!' || c == '\\' || c == '\n';

List<InlineNode> _merge(List<InlineNode> nodes) {
  final r = <InlineNode>[];
  for (final n in nodes) {
    if (n is TextNode && r.isNotEmpty && r.last is TextNode) {
      final last = r.last as TextNode;
      r[r.length - 1] = TextNode('${last.text}${n.text}');
    } else {
      r.add(n);
    }
  }
  return r;
}
