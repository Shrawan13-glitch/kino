import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as p;
import '../vfs/vfs_service.dart';
import '../tool_execution.dart';

typedef BuiltinHandler = Future<ToolResult> Function(
  List<String> args, {
  String? stdin,
  String? workingDirectory,
  Map<String, String>? environment,
  Duration timeout,
});

final Map<String, BuiltinHandler> builtinHandlers = {
  'jq': _jsonTool,
  'json': _jsonTool,
  'rg': _searchTool,
  'search': _searchTool,
  'sqlite3': _sqlTool,
};

String _vfsPath(String vfsPath) {
  final root = VfsService().rootPath;
  if (vfsPath.startsWith('/')) return '$root$vfsPath';
  return '$root/$vfsPath';
}

// ─── JSON / jq tool ───────────────────────────────────────────────

Future<ToolResult> _jsonTool(
  List<String> args, {
  String? stdin,
  String? workingDirectory,
  Map<String, String>? environment,
  Duration timeout = const Duration(seconds: 30),
}) async {
  try {
    var rawOutput = false;
    var compact = false;
    var slurp = false;
    String? query;
    String? filePath;
    final fileArgs = <String>[];

    for (var i = 0; i < args.length; i++) {
      final a = args[i];
      if (a == '-r' || a == '--raw-output') {
        rawOutput = true;
      } else if (a == '-c' || a == '--compact') {
        compact = true;
      } else if (a == '-s' || a == '--slurp') {
        slurp = true;
      } else if ((a == '-f' || a == '--from-file') && i + 1 < args.length) {
        query = await File(_vfsPath(args[++i])).readAsString();
      } else if ((a == '-f' || a == '--file') && i + 1 < args.length) {
        filePath = _vfsPath(args[++i]);
      } else if (a.startsWith('-') && a.length > 1) {
        if (a.contains('r')) rawOutput = true;
        if (a.contains('c')) compact = true;
      } else if (query == null && !a.startsWith('-')) {
        query = a;
      } else if (!a.startsWith('-')) {
        fileArgs.add(a);
      }
    }

    if (query == null || query.isEmpty) {
      return ToolResult(
        exitCode: 2,
        stdout: '',
        stderr: 'Usage: jq [-r] [-c] [-s] [--file path] <query> [file...]\n'
            'Query language:\n'
            '  .key              — field access\n'
            '  .key1.key2        — nested field access\n'
            '  .[index]          — array index (negative = from end)\n'
            '  [] or .[]         — iterate array elements\n'
            '  select(cond)      — filter: .field > 5, .name == "val", !=, <, >=, <=\n'
            '  {a: .x, b: .y}   — object projection\n'
            '  [.x, .y]          — array projection\n'
            '  sort_by(.key)     — sort array by field\n'
            '  group_by(.key)    — group array by field\n'
            '  length            — array/string length\n'
            '  keys              — object keys\n'
            '  |                 — pipe steps together\n'
            '  empty             — output nothing (for conditional filtering)\n'
            '  del(.key)         — remove a key\n'
            '  map(.key)         — shortcut for [] | .key\n'
            'Flags:\n'
            '  -r  raw output (unquoted strings)\n'
            '  -c  compact output (no pretty-print)\n'
            '  -s  slurp all input arrays into one array',
      );
    }

    dynamic input;

    if (filePath != null && filePath.isNotEmpty) {
      final f = File(filePath);
      if (!await f.exists()) {
        return ToolResult(
          exitCode: 1,
          stdout: '',
          stderr: 'File not found: ${fileArgs.isNotEmpty ? fileArgs.first : filePath}',
        );
      }
      input = jsonDecode(await f.readAsString());
    } else if (fileArgs.isNotEmpty) {
      final f = File(_vfsPath(fileArgs.first));
      if (!await f.exists()) {
        return ToolResult(
          exitCode: 1,
          stdout: '',
          stderr: 'File not found: ${fileArgs.first}',
        );
      }
      input = jsonDecode(await f.readAsString());
    } else if (stdin != null && stdin.trim().isNotEmpty) {
      input = jsonDecode(stdin);
    } else {
      input = null;
    }

    if (input == null) {
      return ToolResult(exitCode: 0, stdout: '', stderr: '');
    }

    if (slurp && input is List) {
      input = [input];
    }

    final steps = parseQuery(query);
    final outputs = <dynamic>[];
    final iterable = input is List ? input : [input];

    for (final item in iterable) {
      final result = executeSteps(item, steps);
      if (result is List) {
        outputs.addAll(result);
      } else if (result != _jqEmpty) {
        outputs.add(result);
      }
    }

    if (outputs.isEmpty) {
      return ToolResult(exitCode: 0, stdout: '', stderr: '');
    }

    final sb = StringBuffer();
    for (var i = 0; i < outputs.length; i++) {
      if (i > 0) sb.writeln();
      final val = outputs[i];
      if (rawOutput && val is String) {
        sb.write(val);
      } else if (rawOutput && val is num) {
        sb.write(val);
      } else if (rawOutput && val is bool) {
        sb.write(val);
      } else {
        sb.write(compact ? jsonEncode(val) : _prettyJson(val));
      }
    }

    return ToolResult(exitCode: 0, stdout: sb.toString(), stderr: '');
  } catch (e) {
    return ToolResult(
      exitCode: 1,
      stdout: '',
      stderr: 'jq error: $e\n\n'
          'Usage: jq [-r] [-c] <query> [file]\n'
          'See "jq" with no args for query language reference.',
    );
  }
}

String _prettyJson(dynamic v, {int indent = 0}) {
  if (v == null) return 'null';
  if (v is bool) return v.toString();
  if (v is num) return v.toString();
  if (v is String) return jsonEncode(v);
  if (v is List) {
    if (v.isEmpty) return '[]';
    final inner = v.map((e) => _prettyJson(e, indent: indent + 1)).join(',\n');
    return '[\n${'  ' * (indent + 1)}$inner\n${'  ' * indent}]';
  }
  if (v is Map) {
    if (v.isEmpty) return '{}';
    final entries = v.entries.map((e) {
      final key = jsonEncode(e.key);
      final val = _prettyJson(e.value, indent: indent + 1);
      return '${'  ' * (indent + 1)}$key: $val';
    }).join(',\n');
    return '{\n$entries\n${'  ' * indent}}';
  }
  return v.toString();
}

final _jqEmpty = Object();

dynamic executeSteps(dynamic input, List<JqStep> steps) {
  var current = input;
  for (final step in steps) {
    current = step.execute(current);
    if (current == _jqEmpty) return _jqEmpty;
  }
  return current;
}

abstract class JqStep {
  dynamic execute(dynamic input);
}

class JqField extends JqStep {
  final List<dynamic> keys;
  JqField(this.keys);
  @override
  dynamic execute(dynamic input) {
    var cur = input;
    for (final k in keys) {
      if (cur == null || cur == _jqEmpty) return _jqEmpty;
      if (k is int) {
        if (cur is! List) return _jqEmpty;
        final idx = k < 0 ? cur.length + k : k;
        if (idx < 0 || idx >= cur.length) return _jqEmpty;
        cur = cur[idx];
      } else {
        if (cur is! Map) return _jqEmpty;
        if (k is String) {
          cur = cur[k];
        } else {
          return _jqEmpty;
        }
      }
    }
    return cur;
  }
}

class JqArrayIter extends JqStep {
  final JqStep? inner;
  JqArrayIter([this.inner]);
  @override
  dynamic execute(dynamic input) {
    if (input is! List) return _jqEmpty;
    final results = <dynamic>[];
    for (final item in input) {
      if (inner != null) {
        final r = inner!.execute(item);
        if (r is List) {
          results.addAll(r);
        } else if (r != _jqEmpty) {
          results.add(r);
        }
      } else {
        results.add(item);
      }
    }
    return results;
  }
}

class JqSelect extends JqStep {
  final String field;
  final String op;
  final dynamic value;
  JqSelect(this.field, this.op, this.value);

  @override
  dynamic execute(dynamic input) {
    if (input is! List) {
      return _matches(input) ? input : _jqEmpty;
    }
    return (input).where((item) => _matches(item)).toList();
  }

  bool _matches(dynamic item) {
    final actual = _resolveField(item, field);
    if (op == '==') return actual == value;
    if (op == '!=') return actual != value;
    if (op == '>') {
      if (actual is num && value is num) return actual > value;
      if (actual is String && value is String) return actual.compareTo(value) > 0;
      return false;
    }
    if (op == '<') {
      if (actual is num && value is num) return actual < value;
      if (actual is String && value is String) return actual.compareTo(value) < 0;
      return false;
    }
    if (op == '>=') {
      if (actual is num && value is num) return actual >= value;
      return false;
    }
    if (op == '<=') {
      if (actual is num && value is num) return actual <= value;
      return false;
    }
    if (op == 'contains') {
      if (actual is String && value is String) return actual.contains(value);
      if (actual is List) return actual.contains(value);
      return false;
    }
    if (op == 'match') {
      if (actual is String && value is String) {
        try {
          return RegExp(value).hasMatch(actual);
        } catch (_) {
          return false;
        }
      }
      return false;
    }
    if (op == 'in') {
      if (value is List) return value.contains(actual);
      return false;
    }
    if (op == 'has') {
      if (actual is Map && value is String) return actual.containsKey(value);
      return false;
    }
    return false;
  }
}

class JqProject extends JqStep {
  final Map<String, String> fields; // outputKey -> inputPath
  JqProject(this.fields);

  @override
  dynamic execute(dynamic input) {
    if (input is! Map && input is! List) return _jqEmpty;
    final result = <String, dynamic>{};
    for (final entry in fields.entries) {
      result[entry.key] = _resolveField(input, entry.value);
    }
    return result;
  }
}

class JqArrayProject extends JqStep {
  final List<String> fields;
  JqArrayProject(this.fields);

  @override
  dynamic execute(dynamic input) {
    if (input is! Map && input is! List) return _jqEmpty;
    return fields.map((f) => _resolveField(input, f)).toList();
  }
}

class JqSortBy extends JqStep {
  final String field;
  JqSortBy(this.field);

  @override
  dynamic execute(dynamic input) {
    if (input is! List) return input;
    final sorted = List<dynamic>.from(input);
    sorted.sort((a, b) {
      final va = _resolveField(a, field);
      final vb = _resolveField(b, field);
      if (va is num && vb is num) return va.compareTo(vb);
      if (va is String && vb is String) return va.compareTo(vb);
      if (va == null && vb == null) return 0;
      if (va == null) return -1;
      if (vb == null) return 1;
      return 0;
    });
    return sorted;
  }
}

class JqGroupBy extends JqStep {
  final String field;
  JqGroupBy(this.field);

  @override
  dynamic execute(dynamic input) {
    if (input is! List) return input;
    final groups = <String, List<dynamic>>{};
    for (final item in input) {
      final key = '${_resolveField(item, field) ?? 'null'}';
      groups.putIfAbsent(key, () => []).add(item);
    }
    return groups.entries.map((e) => {e.key: e.value}).toList();
  }
}

class JqLength extends JqStep {
  @override
  dynamic execute(dynamic input) {
    if (input is List) return input.length;
    if (input is Map) return input.length;
    if (input is String) return input.length;
    return 0;
  }
}

class JqKeys extends JqStep {
  @override
  dynamic execute(dynamic input) {
    if (input is Map) return input.keys.toList();
    return [];
  }
}

class JqMap extends JqStep {
  final JqStep inner;
  JqMap(this.inner);
  @override
  dynamic execute(dynamic input) {
    if (input is! List) return _jqEmpty;
    final results = <dynamic>[];
    for (final item in input) {
      final r = inner.execute(item);
      if (r is List) {
        results.addAll(r);
      } else if (r != _jqEmpty) {
        results.add(r);
      }
    }
    return results;
  }
}

class JqUnique extends JqStep {
  final String? field;
  JqUnique({this.field});
  @override
  dynamic execute(dynamic input) {
    if (input is! List) return input;
    final seen = <dynamic>{};
    final result = <dynamic>[];
    for (final item in input) {
      final key = field != null ? _resolveField(item, field!) : item;
      if (!seen.contains(key)) {
        seen.add(key);
        result.add(item);
      }
    }
    return result;
  }
}

class JqDel extends JqStep {
  final String field;
  JqDel(this.field);
  @override
  dynamic execute(dynamic input) {
    if (input is! Map) return input;
    final m = Map<String, dynamic>.from(input);
    m.remove(field);
    return m;
  }
}

class JqFlatMap extends JqStep {
  final JqStep inner;
  JqFlatMap(this.inner);
  @override
  dynamic execute(dynamic input) {
    if (input is! List) return _jqEmpty;
    final results = <dynamic>[];
    for (final item in input) {
      final r = inner.execute(item);
      if (r is List) {
        results.addAll(r);
      } else if (r != _jqEmpty) {
        results.add(r);
      }
    }
    return results;
  }
}

dynamic _resolveField(dynamic input, String path) {
  if (path.isEmpty || path == '.') return input;
  final parts = _parseFieldPath(path);
  var cur = input;
  for (final part in parts) {
    if (cur == null) return null;
    if (part is int) {
      if (cur is! List) return null;
      final idx = part < 0 ? cur.length + part : part;
      if (idx < 0 || idx >= cur.length) return null;
      cur = cur[idx];
    } else if (part is String) {
      if (cur is! Map) return null;
      cur = cur[part];
    }
  }
  return cur;
}

List<dynamic> _parseFieldPath(String path) {
  final parts = <dynamic>[];
  var remaining = path.trim();
  if (remaining.startsWith('.')) remaining = remaining.substring(1);

  while (remaining.isNotEmpty) {
    if (remaining.startsWith('[')) {
      final close = remaining.indexOf(']');
      if (close == -1) break;
      final inner = remaining.substring(1, close).trim();
      remaining = remaining.substring(close + 1);
      if (inner.isEmpty) {
        parts.add('[]'); // signal for array iteration
      } else {
        parts.add(int.tryParse(inner) ?? inner);
      }
      if (remaining.startsWith('.')) remaining = remaining.substring(1);
    } else if (remaining.startsWith('.')) {
      remaining = remaining.substring(1);
    } else {
      final dot = remaining.indexOf('.');
      final bracket = remaining.indexOf('[');
      var end = remaining.length;
      if (dot > 0 && dot < end) end = dot;
      if (bracket > 0 && bracket < end) end = bracket;
      parts.add(remaining.substring(0, end));
      remaining = remaining.substring(end);
    }
  }
  return parts;
}

List<JqStep> parseQuery(String query) {
  if (query.trim().isEmpty) return [];

  final steps = <JqStep>[];
  final parts = _splitPipes(query);

  for (final part in parts) {
    steps.add(_parseStep(part.trim()));
  }

  return steps;
}

List<String> _splitPipes(String q) {
  final parts = <String>[];
  var depth = 0;
  var start = 0;
  var inStr = false;
  var strChar = '';
  for (var i = 0; i < q.length; i++) {
    final c = q[i];
    if (inStr) {
      if (c == strChar && (i == 0 || q[i - 1] != '\\')) inStr = false;
      continue;
    }
    if (c == '"' || c == "'") {
      inStr = true;
      strChar = c;
      continue;
    }
    if (c == '(' || c == '[' || c == '{') {
      depth++;
    } else if (c == ')' || c == ']' || c == '}') {
      depth--;
    } else if (c == '|' && depth == 0) {
      parts.add(q.substring(start, i));
      start = i + 1;
    }
  }
  parts.add(q.substring(start));
  return parts;
}

JqStep _parseStep(String s) {
  if (s.startsWith('select(') && s.endsWith(')')) {
    return _parseSelect(s.substring(7, s.length - 1));
  }
  if (s.startsWith('sort_by(') && s.endsWith(')')) {
    final inner = s.substring(8, s.length - 1).trim();
    return JqSortBy(inner.startsWith('.') ? inner.substring(1) : inner);
  }
  if (s.startsWith('group_by(') && s.endsWith(')')) {
    final inner = s.substring(9, s.length - 1).trim();
    return JqGroupBy(inner.startsWith('.') ? inner.substring(1) : inner);
  }
  if (s.startsWith('map(') && s.endsWith(')')) {
    final inner = s.substring(4, s.length - 1).trim();
    return JqMap(_parseStep(inner));
  }
  if (s.startsWith('unique_by(') && s.endsWith(')')) {
    final inner = s.substring(10, s.length - 1).trim();
    return JqUnique(field: inner.startsWith('.') ? inner.substring(1) : inner);
  }
  if (s.startsWith('del(') && s.endsWith(')')) {
    final inner = s.substring(4, s.length - 1).trim();
    return JqDel(inner.startsWith('.') ? inner.substring(1) : inner);
  }
  if (s == 'unique') {
    return JqUnique();
  }
  if (s.startsWith('{') && s.endsWith('}')) {
    return _parseObjectProject(s);
  }
  if (s.startsWith('[') && s.endsWith(']')) {
    return _parseArrayProject(s);
  }
  if (s == 'length') return JqLength();
  if (s == 'keys') return JqKeys();
  if (s == 'empty') return _JqEmptyStep();
  if (s.startsWith('.')) {
    final parts = _parseFieldPath(s);
    return JqField(parts);
  }
  if (s == '.[]' || s == '[]') {
    return JqArrayIter();
  }
  // Treat as raw string - output as-is
  return JqRaw(s);
}

class JqRaw extends JqStep {
  final String value;
  JqRaw(this.value);
  @override
  dynamic execute(dynamic input) => value;
}

class _JqEmptyStep extends JqStep {
  @override
  dynamic execute(dynamic input) => _jqEmpty;
}

JqStep _parseSelect(String cond) {
  cond = cond.trim();

  // Check for boolean combinations with 'and' / 'or'
  if (cond.contains(' and ')) {
    final parts = cond.split(' and ');
    return _JqAndSelect(parts.map((c) => _parseSelect(c.trim())).toList());
  }
  if (cond.contains(' or ')) {
    final parts = cond.split(' or ');
    return _JqOrSelect(parts.map((c) => _parseSelect(c.trim())).toList());
  }

  final ops = ['>=', '<=', '!=', '==', '>', '<'];
  for (final op in ops) {
    final idx = cond.indexOf(op);
    if (idx > 0) {
      final field = cond.substring(0, idx).trim();
      final rawVal = cond.substring(idx + op.length).trim();

      final fieldName = field.startsWith('.') ? field.substring(1) : field;
      final value = _parseValue(rawVal);

      if (op == '>=') return JqSelect(fieldName, '>=', value);
      if (op == '<=') return JqSelect(fieldName, '<=', value);
      if (op == '!=') return JqSelect(fieldName, '!=', value);
      if (op == '==') return JqSelect(fieldName, '==', value);
      if (op == '>') return JqSelect(fieldName, '>', value);
      if (op == '<') return JqSelect(fieldName, '<', value);
    }
  }

  // contains() function
  final containsMatch = RegExp(r'^\.?(\w+)\s*\.\s*contains\s*\(\s*(.+)\s*\)$')
      .firstMatch(cond);
  if (containsMatch != null) {
    return JqSelect(containsMatch.group(1)!, 'contains', _parseValue(containsMatch.group(2)!));
  }

  // match() function (regex)
  final matchMatch = RegExp(r'^\.?(\w+)\s*\.\s*match\s*\(\s*(.+)\s*\)$')
      .firstMatch(cond);
  if (matchMatch != null) {
    return JqSelect(matchMatch.group(1)!, 'match', _parseValue(matchMatch.group(2)!));
  }

  // in operator: .field in [1,2,3]
  final inMatch = RegExp(r'^\.?(\w+)\s+in\s+(.+)$').firstMatch(cond);
  if (inMatch != null) {
    return JqSelect(inMatch.group(1)!, 'in', _parseValue(inMatch.group(2)!));
  }

  // has operator: has("key")
  final hasMatch = RegExp(r'^has\s*\(\s*"([^"]+)"\s*\)$').firstMatch(cond);
  if (hasMatch != null) {
    return JqSelect('', 'has', hasMatch.group(1));
  }

  // Just a path — truthy check
  final path = cond.startsWith('.') ? cond.substring(1) : cond;
  return JqSelect(path, '!=', null);
}

class _JqAndSelect extends JqStep {
  final List<JqStep> conditions;
  _JqAndSelect(this.conditions);
  @override
  dynamic execute(dynamic input) {
    for (final c in conditions) {
      final r = c.execute(input is List ? input : [input]);
      if (r == _jqEmpty || (r is List && r.isEmpty)) return _jqEmpty;
    }
    return input;
  }
}

class _JqOrSelect extends JqStep {
  final List<JqStep> conditions;
  _JqOrSelect(this.conditions);
  @override
  dynamic execute(dynamic input) {
    for (final c in conditions) {
      final r = c.execute(input is List ? input : [input]);
      if (r != _jqEmpty && !(r is List && r.isEmpty)) return input;
    }
    return _jqEmpty;
  }
}

JqStep _parseObjectProject(String s) {
  final inner = s.substring(1, s.length - 1).trim();
  if (inner.isEmpty) return JqRaw('{}');

  final fields = <String, String>{};
  var depth = 0;
  var start = 0;
  var inStr = false;
  var strChar = '';
  for (var i = 0; i < inner.length; i++) {
    final c = inner[i];
    if (inStr) {
      if (c == strChar && (i == 0 || inner[i - 1] != '\\')) inStr = false;
      continue;
    }
    if (c == '"' || c == "'") {
      inStr = true;
      strChar = c;
      continue;
    }
    if (c == '(' || c == '[' || c == '{') {
      depth++;
    } else if (c == ')' || c == ']' || c == '}') {
      depth--;
    } else if (c == ',' && depth == 0) {
      _addField(fields, inner.substring(start, i).trim());
      start = i + 1;
    }
  }
  _addField(fields, inner.substring(start).trim());

  return JqProject(fields);
}

void _addField(Map<String, String> fields, String expr) {
  final colon = expr.indexOf(':');
  if (colon > 0) {
    final key = expr.substring(0, colon).trim().replaceAll('"', '').replaceAll("'", '');
    final val = expr.substring(colon + 1).trim();
    fields[key] = val.startsWith('.') ? val.substring(1) : val;
  } else {
    final e = expr.trim();
    final key = e.startsWith('.') ? e.substring(1) : e;
    fields[key] = key;
  }
}

JqStep _parseArrayProject(String s) {
  final inner = s.substring(1, s.length - 1).trim();
  if (inner.isEmpty) return JqRaw('[]');

  final fields = <String>[];
  var depth = 0;
  var start = 0;
  for (var i = 0; i < inner.length; i++) {
    final c = inner[i];
    if (c == '(' || c == '[' || c == '{') depth++;
    else if (c == ')' || c == ']' || c == '}') depth--;
    else if (c == ',' && depth == 0) {
      fields.add(inner.substring(start, i).trim());
      start = i + 1;
    }
  }
  fields.add(inner.substring(start).trim());

  final processed = fields.map((f) {
    return f.startsWith('.') ? f.substring(1) : f;
  }).toList();

  return JqArrayProject(processed);
}

dynamic _parseValue(String s) {
  s = s.trim();
  if (s == 'null') return null;
  if (s == 'true') return true;
  if (s == 'false') return false;
  if (s.startsWith('"') && s.endsWith('"')) {
    return s.substring(1, s.length - 1);
  }
  if (s.startsWith("'") && s.endsWith("'")) {
    return s.substring(1, s.length - 1);
  }
  if (s.startsWith('[') && s.endsWith(']')) {
    try {
      return jsonDecode(s);
    } catch (_) {
      return s;
    }
  }
  final n = num.tryParse(s);
  if (n != null) return n;
  if (s.startsWith('.') || s.startsWith('[')) return _jqEmpty; // it's a path
  return s;
}

// ─── Search / rg tool ─────────────────────────────────────────────

Future<ToolResult> _searchTool(
  List<String> args, {
  String? stdin,
  String? workingDirectory,
  Map<String, String>? environment,
  Duration timeout = const Duration(seconds: 30),
}) async {
  try {
    String? pattern;
    String? path;
    List<String> globs = [];
    var contextLines = 0;
    var countOnly = false;
    var ignoreCase = false;
    var lineNumbers = true;
    var filesOnly = false;
    var invertMatch = false;
    var fixedStrings = false;
    var maxDepth = 256;
    var includeHidden = false;

    for (var i = 0; i < args.length; i++) {
      final a = args[i];
      if (a == '-i' || a == '--ignore-case') {
        ignoreCase = true;
      } else if (a == '-n' || a == '--line-number') {
        lineNumbers = true;
      } else if (a == '-c' || a == '--count') {
        countOnly = true;
      } else if (a == '-l' || a == '--files-with-matches') {
        filesOnly = true;
      } else if (a == '-v' || a == '--invert-match') {
        invertMatch = true;
      } else if (a == '-F' || a == '--fixed-strings') {
        fixedStrings = true;
      } else if (a == '--no-line-number') {
        lineNumbers = false;
      } else if ((a == '-C' || a == '--context') && i + 1 < args.length) {
        contextLines = int.tryParse(args[++i]) ?? 0;
      } else if ((a == '-g' || a == '--glob') && i + 1 < args.length) {
        globs.add(args[++i]);
      } else if ((a == '--include-hidden')) {
        includeHidden = true;
      } else if ((a == '--max-depth') && i + 1 < args.length) {
        maxDepth = int.tryParse(args[++i]) ?? 256;
      } else if (a.startsWith('-')) {
        // skip unknown flags
      } else if (pattern == null) {
        pattern = a;
      } else if (path == null) {
        path = a;
      }
    }

    if (pattern == null || pattern.isEmpty) {
      return ToolResult(
        exitCode: 2,
        stdout: '',
        stderr: 'Usage: rg [options] <pattern> [path]\n'
            'Options:\n'
            '  -i, --ignore-case     case-insensitive search\n'
            '  -n, --line-number     show line numbers\n'
            '  -c, --count           count matches per file\n'
            '  -l, --files-with-matches  show only filenames\n'
            '  -v, --invert-match    invert match\n'
            '  -F, --fixed-strings   treat pattern as literal\n'
            '  -C N, --context N     show N lines of context\n'
            '  -g GLOB, --glob GLOB  file glob filter\n'
            '  --include-hidden      search hidden files\n'
            '  --max-depth N         max directory depth',
      );
    }

    final searchPath = path != null ? _vfsPath(path) : (workingDirectory ?? VfsService().rootPath);
    final searchDir = Directory(searchPath);

    if (!await searchDir.exists()) {
      return ToolResult(exitCode: 1, stdout: '', stderr: 'Path not found: $path');
    }

    final regex = fixedStrings
        ? RegExp(RegExp.escape(pattern), caseSensitive: !ignoreCase)
        : RegExp(pattern, caseSensitive: !ignoreCase);

    final results = <String>[];
    var totalMatches = 0;
    var fileCount = 0;

    await _walkDir(
      searchDir,
      (File file, List<String> lines, String relPath) {
        final matchLines = <int>[];

        for (var i = 0; i < lines.length; i++) {
          final match = regex.hasMatch(lines[i]);
          if (invertMatch ? !match : match) {
            matchLines.add(i);
            totalMatches++;
          }
        }

        if (matchLines.isEmpty) return;

        fileCount++;

        if (filesOnly) {
          results.add(relPath);
          return;
        }

        if (countOnly) {
          results.add('$relPath:${matchLines.length}');
          return;
        }

        if (fileCount > 1 && !filesOnly) {
          results.add('');
        }

        // Show with context
        var lastShown = -100;
        for (final lineIdx in matchLines) {
          final start = max(0, lineIdx - contextLines);
          final end = min(lines.length - 1, lineIdx + contextLines);

          if (start > lastShown + 1 && results.isNotEmpty) {
            results.add('--');
          }

          for (var i = start; i <= end; i++) {
            if (i <= lastShown) continue;
            final isMatch = matchLines.contains(i);
            final prefix = lineNumbers
                ? (isMatch
                    ? '${relPath}:${i + 1}:'
                    : '${relPath}-${i + 1}-')
                : (isMatch ? '$relPath:' : '$relPath-');
            results.add('$prefix${lines[i]}');
            lastShown = i;
          }
        }
      },
      globs: globs,
      maxDepth: maxDepth,
      includeHidden: includeHidden,
    );

    if (countOnly && fileCount > 1) {
      results.add('$fileCount files, $totalMatches matches');
    }

    return ToolResult(
      exitCode: results.isEmpty ? 1 : 0,
      stdout: results.join('\n'),
      stderr: '',
    );
  } catch (e) {
    return ToolResult(exitCode: 2, stdout: '', stderr: 'rg error: $e');
  }
}

Future<void> _walkDir(
  Directory dir,
  void Function(File file, List<String> lines, String relPath) onFile, {
  List<String> globs = const [],
  int maxDepth = 256,
  bool includeHidden = false,
  int depth = 0,
}) async {
  if (depth > maxDepth) return;

  try {
    await for (final entity in dir.list()) {
      final name = p.basename(entity.path);
      if (!includeHidden && name.startsWith('.')) continue;

      if (entity is Directory) {
        await _walkDir(
          entity,
          onFile,
          globs: globs,
          maxDepth: maxDepth,
          includeHidden: includeHidden,
          depth: depth + 1,
        );
      } else if (entity is File) {
        if (globs.isNotEmpty && !_matchesGlob(name, globs)) continue;

        try {
          final bytes = await entity.length();
          if (bytes > 1024 * 1024) continue; // skip >1MB files
          final lines = await entity.readAsLines();
          final relPath = entity.path;
          onFile(entity, lines, relPath);
        } catch (_) {
          // skip binary/unreadable files
        }
      }
    }
  } catch (_) {}
}

bool _matchesGlob(String name, List<String> globs) {
  if (globs.isEmpty) return true;
  for (final g in globs) {
    final regexStr = g
        .replaceAll('.', '\\.')
        .replaceAll('*', '.*')
        .replaceAll('?', '.');
    try {
      if (RegExp('^$regexStr\$').hasMatch(name)) return true;
    } catch (_) {}
  }
  return false;
}

// ─── SQLite tool ─────────────────────────────────────────────

Future<ToolResult> _sqlTool(
  List<String> args, {
  String? stdin,
  String? workingDirectory,
  Map<String, String>? environment,
  Duration timeout = const Duration(seconds: 30),
}) async {
  try {
    String? dbPath;
    String? query;

    for (var i = 0; i < args.length; i++) {
      final a = args[i];
      if (dbPath == null && !a.startsWith('-')) {
        dbPath = a;
      } else if (query == null && !a.startsWith('-')) {
        query = a;
      }
    }

    if (stdin != null && stdin.trim().isNotEmpty) {
      query = stdin.trim();
    }

    if (dbPath == null) {
      dbPath = p.join(VfsService().rootPath, 'home', 'data.db');
    }

    if (query == null || query.isEmpty) {
      return ToolResult(
        exitCode: 2,
        stdout: '',
        stderr: 'Usage: sqlite3 [database] <query>\n'
            '  Provide the SQL query as an argument or via stdin.\n'
            '  Default database: data.db in home directory.',
      );
    }

    final fullPath = _vfsPath(dbPath);
    final dbDir = Directory(p.dirname(fullPath));
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }

    // Use dart:io Process to run sqlite3 if available.
    // Check if system sqlite3 is available
    final whichResult = await Process.run(
      Platform.isAndroid ? '/system/bin/sh' : 'which',
      Platform.isAndroid ? ['-c', 'command -v sqlite3'] : ['sqlite3'],
    );

    if (whichResult.exitCode == 0) {
      final sqliteBin = (whichResult.stdout as String).trim().split('\n').last.trim();
      final result = await Process.run(
        sqliteBin,
        [fullPath, query],
        workingDirectory: workingDirectory ?? p.dirname(fullPath),
      );
      return ToolResult(
        exitCode: result.exitCode,
        stdout: (result.stdout as String).trim(),
        stderr: (result.stderr as String).trim(),
      );
    }

    // Fallback: implement basic SQL using sqflite-like approach
    // Since this is a Dart-native tool, we provide CSV/JSON-based data manipulation
    // as a lightweight alternative when no sqlite3 binary is available.
    return ToolResult(
      exitCode: 0,
      stdout: 'SQLite query received.\n'
          'Database: $dbPath\n'
          'Query: $query\n\n'
          'No sqlite3 binary available. Install sqlite3 or use the "csv" tool for '
          'data manipulation:\n'
          '  csv --file <path> --query <expression>\n'
          '  json --file <path> <query>',
      stderr: '',
    );
  } catch (e) {
    return ToolResult(exitCode: 1, stdout: '', stderr: 'sqlite3 error: $e');
  }
}
