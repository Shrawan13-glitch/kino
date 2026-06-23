import 'dart:io';
import 'package:path/path.dart' as p;
import '../vfs/vfs_service.dart';
import 'shell_state.dart';

class ShellExpander {
  final ShellState state;
  final VfsService _vfs = VfsService();

  ShellExpander(this.state);

  String _vfsAbsolute(String vfsPath) {
    final parts = vfsPath.split('/').where((s) => s.isNotEmpty).toList();
    final clean = parts.join('/');
    return p.join(_vfs.rootPath, clean);
  }

  String resolvePath(String path) {
    if (path.isEmpty) return state.cwd;
    if (path == '-') return state.previousCwd;
    if (path == '~') return state.env['HOME'] ?? '/';
    if (path.startsWith('~/')) return p.join(state.env['HOME'] ?? '/', path.substring(2));
    if (path.startsWith('/')) return path;

    final resolved = p.normalize(p.join(state.cwd, path));
    if (!resolved.startsWith('/')) return '/$resolved';
    return resolved;
  }

  int lastBraceVarConsumed = 0;

  String expandVars(String s) {
    final result = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (s[i] == '\'') {
        final end = s.indexOf('\'', i + 1);
        if (end == -1) { result.write(s.substring(i)); break; }
        result.write(s.substring(i, end + 1));
        i = end;
        continue;
      }

      if (s[i] == '\\') {
        i++;
        if (i < s.length) result.write(s[i]);
        continue;
      }

      if (s[i] != r'$') {
        result.write(s[i]);
        continue;
      }

      i++;
      if (i >= s.length) {
        result.write(r'$');
        break;
      }

      if (s[i] == r'$') {
        result.write('0');
        continue;
      }

      if (s[i] == '?') {
        result.write(state.lastExitCode);
        continue;
      }

      if (s[i] == '!') {
        result.write(state.lastBgPid);
        continue;
      }

      if (s[i] == '0') {
        result.write('kino');
        continue;
      }

      if (s[i] == '#') {
        result.write(state.positionalParams.length);
        continue;
      }

      if (s[i] == '@') {
        result.write(state.positionalParams.join(' '));
        continue;
      }

      if (s[i] == '*') {
        result.write(state.positionalParams.join(' '));
        continue;
      }

      if (s[i].codeUnitAt(0) >= 49 && s[i].codeUnitAt(0) <= 57) {
        final idx = int.parse(s[i]) - 1;
        result.write(idx < state.positionalParams.length ? state.positionalParams[idx] : '');
        continue;
      }

      if (s[i] == '(' && i + 1 < s.length && s[i + 1] == '(') {
        final end = _findMatchingClose(s, i + 2, ')', ')');
        if (end == -1) { result.write(r'$(('); i++; continue; }
        final expr = s.substring(i + 2, end);
        final value = _evalArithmetic(expr);
        result.write(value);
        i = end + 1;
        continue;
      }

      if (s[i] == '{') {
        final resultStr = _expandBraceVar(s, i + 1);
        if (resultStr == null) {
          result.write(r'$');
          i--;
          continue;
        }
        result.write(resultStr);
        i = i + lastBraceVarConsumed;
        continue;
      }

      if (_isVarChar(s[i], first: true)) {
        final start = i;
        while (i < s.length && _isVarChar(s[i], first: false)) { i++; }
        final varName = s.substring(start, i);
        result.write(state.lookupVar(varName));
        i--;
      } else {
        result.write(r'$');
        result.write(s[i]);
      }
    }

    return result.toString();
  }

  String _evalArithmetic(String expr) {
    // Delegate to a simple evaluator; full arithmetic is in ShellArithmetic
    try {
      final trimmed = expr.trim();
      if (trimmed.isEmpty) return '0';
      // Simple case: just a number or a variable
      final parsed = int.tryParse(trimmed);
      if (parsed != null) return parsed.toString();
      final varVal = state.lookupVar(trimmed);
      if (varVal.isNotEmpty) {
        final v = int.tryParse(varVal);
        if (v != null) return v.toString();
      }
      return '0';
    } catch (_) {
      return '0';
    }
  }

  String? _expandBraceVar(String s, int start) {
    final end = _findMatchingClose(s, start, '}', '{');
    if (end == -1) return null;

    final contents = s.substring(start, end);
    lastBraceVarConsumed = end - start + 1;

    if (contents.isEmpty) return null;

    if (contents.startsWith('#')) {
      final rest = contents.substring(1);
      if (rest.endsWith('[@]') || rest.endsWith('[*]')) {
        final arrName = rest.substring(0, rest.length - 3);
        if (state.assocArrays.containsKey(arrName)) {
          return state.assocArrays[arrName]!.length.toString();
        }
        if (state.arrays.containsKey(arrName)) {
          return state.arrays[arrName]!.length.toString();
        }
        return '0';
      }
      final varName = _extractVarName(rest);
      final val = state.lookupVar(varName);
      return val.length.toString();
    }

    final bracketOpen = contents.indexOf('[');
    if (bracketOpen > 0 && contents.endsWith(']')) {
      final arrName = contents.substring(0, bracketOpen);
      final key = contents.substring(bracketOpen + 1, contents.length - 1);
      if (state.assocArrays.containsKey(arrName)) {
        return state.assocArrays[arrName]![key] ?? '';
      }
      if (state.arrays.containsKey(arrName)) {
        final idx = int.tryParse(key);
        if (idx != null && idx >= 0 && idx < state.arrays[arrName]!.length) {
          return state.arrays[arrName]![idx];
        }
        return '';
      }
      return '';
    }

    if (contents.startsWith('!')) {
      final inner = contents.substring(1);
      if (inner.endsWith('[@]') || inner.endsWith('[*]')) {
        final arrName = inner.substring(0, inner.length - 3);
        if (state.assocArrays.containsKey(arrName)) {
          return state.assocArrays[arrName]!.keys.join(' ');
        }
        if (state.arrays.containsKey(arrName)) {
          return List.generate(state.arrays[arrName]!.length, (i) => i.toString()).join(' ');
        }
        return '';
      }
      if (!_isSimpleVarName(inner)) {
        final prefix = inner;
        final matching = <String>[];
        for (final key in state.env.keys) {
          if (key.startsWith(prefix)) matching.add(key);
        }
        for (final key in state.arrays.keys) {
          if (key.startsWith(prefix)) matching.add(key);
        }
        for (final key in state.assocArrays.keys) {
          if (key.startsWith(prefix)) matching.add(key);
        }
        matching.sort();
        return matching.join(' ');
      }
      final innerVal = state.lookupVar(inner);
      return state.lookupVar(innerVal);
    }

    final sliceMatch = RegExp(r'^([_a-zA-Z][_a-zA-Z0-9]*)\[@\]:(\d+)(?::(\d+))?$').firstMatch(contents);
    if (sliceMatch != null) {
      final arrName = sliceMatch.group(1)!;
      final offset = int.parse(sliceMatch.group(2)!);
      final length = sliceMatch.group(3) != null ? int.parse(sliceMatch.group(3)!) : null;
      if (state.arrays.containsKey(arrName)) {
        final arr = state.arrays[arrName]!;
        if (offset >= arr.length) return '';
        final slice = length != null
            ? arr.sublist(offset, (offset + length).clamp(0, arr.length))
            : arr.sublist(offset);
        return slice.join(' ');
      }
      if (state.assocArrays.containsKey(arrName)) {
        final entries = state.assocArrays[arrName]!.entries.toList();
        if (offset >= entries.length) return '';
        final slice = length != null
            ? entries.sublist(offset, (offset + length).clamp(0, entries.length))
            : entries.sublist(offset);
        return slice.map((e) => e.value).join(' ');
      }
    }
    final sliceStarMatch = RegExp(r'^([_a-zA-Z][_a-zA-Z0-9]*)\[\*\]:(\d+)(?::(\d+))?$').firstMatch(contents);
    if (sliceStarMatch != null) {
      final arrName = sliceStarMatch.group(1)!;
      final offset = int.parse(sliceStarMatch.group(2)!);
      final length = sliceStarMatch.group(3) != null ? int.parse(sliceStarMatch.group(3)!) : null;
      if (state.arrays.containsKey(arrName)) {
        final arr = state.arrays[arrName]!;
        if (offset >= arr.length) return '';
        final slice = length != null
            ? arr.sublist(offset, (offset + length).clamp(0, arr.length))
            : arr.sublist(offset);
        return slice.join(' ');
      }
    }

    final opMatch = RegExp(r'^([_a-zA-Z][_a-zA-Z0-9]*)([:#%^,/!?].*)$').firstMatch(contents);
    if (opMatch == null) {
      final varName = contents.trim();
      if (!_isSimpleVarName(varName)) return null;
      return state.lookupVar(varName);
    }

    final varName = opMatch.group(1)!;
    final rest = opMatch.group(2)!;
    final varValue = state.lookupVar(varName);

    if (rest.startsWith(':-')) {
      final word = rest.substring(2);
      if (varValue.isEmpty) return expandVars(word);
      return varValue;
    }
    if (rest.startsWith(':=')) {
      final word = rest.substring(2);
      if (varValue.isEmpty) {
        final expanded = expandVars(word);
        state.env[varName] = expanded;
        return expanded;
      }
      return varValue;
    }
    if (rest.startsWith(':+')) {
      final word = rest.substring(2);
      if (varValue.isNotEmpty) return expandVars(word);
      return '';
    }
    if (rest.startsWith(':?')) {
      final word = rest.substring(2);
      if (varValue.isEmpty) {
        final msg = word.isEmpty ? 'parameter $varName is not set' : word;
        state.lastError = msg;
        return '';
      }
      return varValue;
    }

    if (rest.startsWith('##')) {
      final pattern = rest.substring(2);
      return _removeLongestPrefix(varValue, pattern);
    }
    if (rest.startsWith('#')) {
      final pattern = rest.substring(1);
      return _removeShortestPrefix(varValue, pattern);
    }

    if (rest.startsWith('%%')) {
      final pattern = rest.substring(2);
      return _removeLongestSuffix(varValue, pattern);
    }
    if (rest.startsWith('%')) {
      final pattern = rest.substring(1);
      return _removeShortestSuffix(varValue, pattern);
    }

    if (rest.startsWith('//')) {
      final slashPos = rest.indexOf('/', 2);
      if (slashPos == -1) return varValue;
      final pattern = rest.substring(2, slashPos);
      final replacement = rest.substring(slashPos + 1);
      return varValue.replaceAll(_globToRegexStr(pattern), replacement);
    }
    if (rest.startsWith('/')) {
      final slashPos = rest.indexOf('/', 1);
      if (slashPos == -1) return varValue;
      final pattern = rest.substring(1, slashPos);
      final replacement = rest.substring(slashPos + 1);
      return varValue.replaceFirstMapped(
          RegExp(_globToRegexStr(pattern)), (_) => replacement);
    }

    if (rest.startsWith('^^')) {
      final pattern = rest.substring(2);
      if (pattern.isEmpty) return varValue.toUpperCase();
      return varValue.splitMapJoin(RegExp(_globToRegexStr(pattern)),
          onMatch: (m) => m.group(0)!.toUpperCase(),
          onNonMatch: (s) => s);
    }
    if (rest.startsWith('^')) {
      final pattern = rest.substring(1);
      if (pattern.isEmpty) {
        if (varValue.isEmpty) return varValue;
        return varValue[0].toUpperCase() + varValue.substring(1);
      }
      return varValue.splitMapJoin(RegExp(_globToRegexStr(pattern)),
          onMatch: (m) => m.group(0)!.toUpperCase(),
          onNonMatch: (s) => s);
    }
    if (rest.startsWith(',,')) {
      final pattern = rest.substring(2);
      if (pattern.isEmpty) return varValue.toLowerCase();
      return varValue.splitMapJoin(RegExp(_globToRegexStr(pattern)),
          onMatch: (m) => m.group(0)!.toLowerCase(),
          onNonMatch: (s) => s);
    }
    if (rest.startsWith(',')) {
      final pattern = rest.substring(1);
      if (pattern.isEmpty) {
        if (varValue.isEmpty) return varValue;
        return varValue[0].toLowerCase() + varValue.substring(1);
      }
      return varValue.splitMapJoin(RegExp(_globToRegexStr(pattern)),
          onMatch: (m) => m.group(0)!.toLowerCase(),
          onNonMatch: (s) => s);
    }

    if (rest.startsWith(':')) {
      final parts = rest.substring(1).split(':');
      if (parts.isEmpty) return varValue;
      final offset = int.tryParse(parts[0].trim()) ?? 0;
      if (parts.length >= 2) {
        final length = int.tryParse(parts[1].trim());
        if (length != null) {
          final safeOffset = offset < 0 ? varValue.length + offset : offset;
          if (safeOffset < 0 || safeOffset >= varValue.length) return '';
          return varValue.substring(safeOffset, (safeOffset + length).clamp(0, varValue.length));
        }
      }
      final safeOffset = offset < 0 ? varValue.length + offset : offset;
      if (safeOffset < 0 || safeOffset >= varValue.length) return '';
      return varValue.substring(safeOffset);
    }

    return state.lookupVar(varName);
  }

  String _removeShortestPrefix(String value, String pattern) {
    final regex = RegExp('^${_globToRegexStr(pattern)}\$');
    for (var i = 1; i <= value.length; i++) {
      if (regex.hasMatch(value.substring(0, i))) return value.substring(i);
    }
    return value;
  }

  String _removeLongestPrefix(String value, String pattern) {
    final regex = RegExp('^${_globToRegexStr(pattern)}\$');
    for (var i = value.length; i >= 0; i--) {
      if (regex.hasMatch(value.substring(0, i))) return value.substring(i);
    }
    return value;
  }

  String _removeShortestSuffix(String value, String pattern) {
    final regex = RegExp('^${_globToRegexStr(pattern)}\$');
    for (var i = value.length; i >= 0; i--) {
      if (regex.hasMatch(value.substring(i))) return value.substring(0, i);
    }
    return value;
  }

  String _removeLongestSuffix(String value, String pattern) {
    final regex = RegExp('^${_globToRegexStr(pattern)}\$');
    for (var i = 0; i <= value.length; i++) {
      if (regex.hasMatch(value.substring(i))) return value.substring(0, i);
    }
    return value;
  }

  int _findMatchingClose(String s, int start, String closeChar, String openChar) {
    var depth = 0;
    for (var i = start; i < s.length; i++) {
      if (s[i] == openChar && openChar != closeChar) { depth++; continue; }
      if (s[i] == closeChar) {
        if (depth == 0) return i;
        depth--;
      }
    }
    return -1;
  }

  String _globToRegexStr(String pattern) {
    final buf = StringBuffer();
    for (var i = 0; i < pattern.length; i++) {
      final c = pattern[i];
      if (c == '*') {
        buf.write('.*');
      } else if (c == '?') {
        buf.write('.');
      } else if (c == '.') {
        buf.write(r'\.');
      } else {
        buf.write(c);
      }
    }
    return buf.toString();
  }

  // ===========================================================================
  // Alias expansion
  // ===========================================================================

  String expandAliases(String cmd) {
    if (state.aliases.isEmpty) return cmd;
    final first = _extractFirstWord(cmd);
    if (first == null) return cmd;
    final alias = state.aliases[first];
    if (alias == null) return cmd;
    return alias + cmd.substring(first.length);
  }

  String? _extractFirstWord(String cmd) {
    final trimmed = cmd.trimLeft();
    if (trimmed.isEmpty) return null;
    final result = StringBuffer();
    var inSingle = false;
    var inDouble = false;
    for (var i = 0; i < trimmed.length; i++) {
      final c = trimmed[i];
      if (inSingle) {
        if (c == '\'') inSingle = false;
        continue;
      }
      if (inDouble) {
        if (c == '"') inDouble = false;
        continue;
      }
      if (c == '\'') {
        inSingle = true;
        continue;
      }
      if (c == '"') {
        inDouble = true;
        continue;
      }
      if (c == '\\') {
        i++;
        continue;
      }
      if (c == ' ' || c == '\t') break;
      result.write(c);
    }
    return result.isEmpty ? null : result.toString();
  }

  // ===========================================================================
  // Brace expansion {a,b,c} {1..5}
  // ===========================================================================

  List<String> expandBraces(String s) {
    if (!s.contains('{') && !s.contains('}')) return [s];

    final results = <String>[];
    _expandBraceRecursive(s, 0, results);
    if (results.isEmpty) results.add(s);
    return results;
  }

  void _expandBraceRecursive(String s, int start, List<String> out) {
    var i = start;
    var inSingle = false;
    var inDouble = false;

    while (i < s.length) {
      final c = s[i];
      if (c == '\'') { inSingle = !inSingle; i++; continue; }
      if (c == '"') { inDouble = !inDouble; i++; continue; }
      if (c == '\\') { i += 2; continue; }
      if (inSingle || inDouble) { i++; continue; }

      if (c == '{') {
        final result = _parseBraceGroup(s, i);
        if (result != null) {
          final (prefix, parts, suffix) = result;
          for (final part in parts) {
            final expanded = prefix + part + suffix;
            if (expanded.contains('{')) {
              _expandBraceRecursive(expanded, 0, out);
            } else {
              out.add(expanded);
            }
          }
          return;
        }
        i++;
        continue;
      }
      i++;
    }

    out.add(s);
  }

  (String, List<String>, String)? _parseBraceGroup(String s, int start) {
    if (start >= s.length || s[start] != '{') return null;

    final prefix = s.substring(0, start);

    final seqMatch = RegExp(r'^\{(-?\d+)\.\.(-?\d+)(?:\.\.(-?\d+))?\}').firstMatch(s.substring(start));
    if (seqMatch != null) {
      final startNum = int.parse(seqMatch.group(1)!);
      final endNum = int.parse(seqMatch.group(2)!);
      final step = seqMatch.group(3) != null ? int.parse(seqMatch.group(3)!).abs() : 1;
      final parts = <String>[];
      if (startNum <= endNum) {
        for (var n = startNum; n <= endNum; n += step) {
          parts.add(n.toString());
        }
      } else {
        for (var n = startNum; n >= endNum; n -= step) {
          parts.add(n.toString());
        }
      }
      final suffix = s.substring(start + seqMatch.group(0)!.length);
      return (prefix, parts, suffix);
    }

    final braceContent = _findBraceContent(s, start);
    if (braceContent == null) return null;

    final (content, end) = braceContent;
    final parts = _splitBraceContent(content);
    if (parts.isEmpty) return null;

    final suffix = s.substring(end + 1);
    return (prefix, parts, suffix);
  }

  (String, int)? _findBraceContent(String s, int start) {
    if (start >= s.length || s[start] != '{') return null;
    var depth = 1;
    var lastComma = -1;
    for (var i = start + 1; i < s.length; i++) {
      if (s[i] == '{') { depth++; continue; }
      if (s[i] == '}') {
        depth--;
        if (depth == 0) {
          if (lastComma >= 0 || _looksLikeSequence(s, start, i)) {
            return (s.substring(start + 1, i), i);
          }
          return null;
        }
      }
      if (s[i] == ',' && depth == 1) {
        lastComma = i;
      }
    }
    return null;
  }

  bool _looksLikeSequence(String s, int braceOpen, int braceClose) {
    final inner = s.substring(braceOpen + 1, braceClose);
    return RegExp(r'^-?\d+\.\.-?\d+(\.\.-?\d+)?$').hasMatch(inner);
  }

  List<String> _splitBraceContent(String content) {
    final parts = <String>[];
    var depth = 0;
    var currentStart = 0;
    for (var i = 0; i < content.length; i++) {
      if (content[i] == '{') { depth++; continue; }
      if (content[i] == '}') { depth--; continue; }
      if (content[i] == ',' && depth == 0) {
        parts.add(content.substring(currentStart, i));
        currentStart = i + 1;
      }
    }
    parts.add(content.substring(currentStart));
    return parts;
  }

  // ===========================================================================
  // Tilde expansion
  // ===========================================================================

  String expandTilde(String s) {
    if (s == '~') return state.env['HOME'] ?? '/';
    if (s.startsWith('~/')) return (state.env['HOME'] ?? '/') + s.substring(1);
    return s;
  }

  // ===========================================================================
  // Glob expansion
  // ===========================================================================

  List<String> expandGlob(String token) {
    final hasGlob = token.contains('*') || token.contains('?') || token.contains('[');
    final hasExtGlob = state.shopt['extglob'] == true &&
        RegExp(r'[@*+?!]\(.*\)').hasMatch(token);

    if (!hasGlob && !hasExtGlob) return [token];

    final dirPart = p.dirname(token);
    final pattern = p.basename(token);
    final resolvedDir = dirPart == '.'
        ? state.cwd
        : resolvePath(dirPart);

    final absDir = _vfsAbsolute(resolvedDir);
    final dir = Directory(absDir);
    if (!dir.existsSync()) {
      if (state.shopt['nullglob'] == true) return [];
      return [token];
    }

    final regex = _globToRegex(pattern);
    final matches = <String>[];
    try {
      final entities = dir.listSync();
      for (final e in entities) {
        final name = p.basename(e.path);
        if (state.shopt['dotglob'] != true && name.startsWith('.')) continue;
        if (regex.hasMatch(name)) {
          final vfsPath = resolvedDir == '/'
              ? '/$name'
              : '$resolvedDir/$name';
          matches.add(vfsPath);
        }
      }
    } catch (_) {}

    matches.sort();

    if (state.globIgnore != null && state.globIgnore!.isNotEmpty && matches.isNotEmpty) {
      final ignorePatterns = state.globIgnore!.split(':');
      matches.removeWhere((path) {
        for (final pattern in ignorePatterns) {
          if (pattern.isEmpty) continue;
          try {
            if (RegExp('^${_globToRegexStr(pattern)}\$').hasMatch(p.basename(path))) return true;
          } catch (_) {}
        }
        return false;
      });
    }

    if (matches.isEmpty) {
      if (state.shopt['nullglob'] == true) return [];
      if (state.shopt['failglob'] == true) {
        state.lastError = 'glob: no matches for: $token';
        state.lastExitCode = 1;
      }
      return [token];
    }
    return matches;
  }

  RegExp _globToRegex(String pattern) {
    if (state.shopt['extglob'] == true) {
      pattern = _expandExtGlob(pattern);
    }

    final sb = StringBuffer('^');
    for (var i = 0; i < pattern.length; i++) {
      final c = pattern[i];
      if (c == '*' && i + 1 < pattern.length && pattern[i + 1] == '*') {
        if (state.shopt['globstar'] == true) {
          sb.write('.*');
          i++;
        } else {
          sb.write('[^/]*');
        }
      } else if (c == '*') {
        sb.write('[^/]*');
      } else if (c == '?') {
        sb.write('[^/]');
      } else if (c == '.') {
        sb.write('\\.');
      } else if (c == '[') {
        var closed = false;
        for (var j = i + 1; j < pattern.length; j++) {
          if (pattern[j] == ']') {
            sb.write(pattern.substring(i, j + 1));
            i = j;
            closed = true;
            break;
          }
        }
        if (!closed) sb.write(RegExp.escape(c));
      } else {
        sb.write(RegExp.escape(c));
      }
    }
    sb.write(r'$');
    return RegExp(sb.toString(), caseSensitive: state.shopt['nocaseglob'] != true);
  }

  String _expandExtGlob(String pattern) {
    var result = pattern;
    result = result.replaceAllMapped(
      RegExp(r'\(\?([^()]+)\)'),
      (m) => '(${m.group(1)})?',
    );
    result = result.replaceAllMapped(
      RegExp(r'\(\+([^()]+)\)'),
      (m) => '(${m.group(1)})+',
    );
    result = result.replaceAllMapped(
      RegExp(r'\(@([^()]+)\)'),
      (m) => '(${m.group(1)})',
    );
    result = result.replaceAllMapped(
      RegExp(r'\(!([^()]+)\)'),
      (m) => '(?!${m.group(1)}).*',
    );
    result = result.replaceAllMapped(
      RegExp(r'\(\*([^()]+)\)'),
      (m) => '(${m.group(1)})*',
    );
    return result;
  }

  // ===========================================================================
  // Character tests
  // ===========================================================================

  bool _isVarChar(String c, {bool first = false}) {
    if (c == '_') return true;
    if (first) {
      return (c.codeUnitAt(0) >= 65 && c.codeUnitAt(0) <= 90) ||
             (c.codeUnitAt(0) >= 97 && c.codeUnitAt(0) <= 122);
    }
    return (c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57) ||
           (c.codeUnitAt(0) >= 65 && c.codeUnitAt(0) <= 90) ||
           (c.codeUnitAt(0) >= 97 && c.codeUnitAt(0) <= 122) ||
           c == '_';
  }

  bool _isSimpleVarName(String s) {
    if (s.isEmpty) return false;
    if (!_isVarChar(s[0], first: true)) return false;
    for (var i = 1; i < s.length; i++) {
      if (!_isVarChar(s[i], first: false)) return false;
    }
    return true;
  }

  String _extractVarName(String s) {
    final trimmed = s.trim();
    final match = RegExp(r'^[_a-zA-Z][_a-zA-Z0-9]*').firstMatch(trimmed);
    if (match == null) return '';
    return match.group(0)!;
  }
}
