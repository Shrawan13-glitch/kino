import 'dart:io' show stdin;
import '../shell_builtin.dart';
import '../shell_result.dart';

Map<String, BuiltinFunction> declareBuiltins() => {
      'declare': _cmdDeclare,
      'local': _cmdLocal,
      'readonly': _cmdReadonly,
      'readarray': _cmdReadarray,
      'mapfile': _cmdReadarray,
      'typeset': _cmdDeclare,
    };

Future<ShellResult> _cmdDeclare(ShellContext ctx, List<String> args) async {
  if (args.isEmpty) {
    final buf = StringBuffer();
    ctx.state.env.forEach((k, v) => buf.writeln('declare -- $k="$v"'));
    ctx.state.arrays.forEach((k, v) {
      buf.writeln(
          'declare -a $k=(${v.map((s) => '"$s"').join(' ')})');
    });
    ctx.state.assocArrays.forEach((k, v) {
      buf.writeln(
          'declare -A $k=(${v.entries.map((e) => '["${e.key}"]="${e.value}"').join(' ')})');
    });
    return ShellResult(exitCode: 0, stdout: buf.toString(), stderr: '');
  }

  var isArray = false;
  var isAssoc = false;
  var i = 0;
  while (i < args.length && args[i].startsWith('-')) {
    if (args[i] == '-p') { i++; continue; }
    if (args[i] == '-a') { isArray = true; i++; continue; }
    if (args[i] == '-A') { isAssoc = true; i++; continue; }
    if (args[i] == '-i') { i++; continue; }
    if (args[i] == '-r') { i++; continue; }
    if (args[i] == '-x') { i++; continue; }
    break;
  }

  for (; i < args.length; i++) {
    final eq = args[i].indexOf('=');
    if (eq > 0) {
      final name = args[i].substring(0, eq);
      var rawValue = args[i].substring(eq + 1);

      if (rawValue.startsWith('(') && rawValue.endsWith(')')) {
        final inner = rawValue.substring(1, rawValue.length - 1);
        if (isAssoc || RegExp(r'\[.*\]=').hasMatch(inner)) {
          final assocMap = <String, String>{};
          var j = 0;
          while (j < inner.length) {
            if (inner[j] == ' ' || inner[j] == '\t') { j++; continue; }
            if (inner[j] == '[') {
              j++;
              final keyStart = j;
              while (j < inner.length && inner[j] != ']') { j++; }
              final key = inner.substring(keyStart, j);
              j++;
              if (j < inner.length && inner[j] == '=') j++;
              if (j < inner.length && (inner[j] == '"' || inner[j] == '\'')) {
                final quote = inner[j];
                j++;
                final valStart = j;
                while (j < inner.length && inner[j] != quote) { j++; }
                assocMap[key] = inner.substring(valStart, j);
                j++;
              } else {
                final valStart = j;
                while (j < inner.length && inner[j] != ' ' && inner[j] != '\t') { j++; }
                assocMap[key] = inner.substring(valStart, j);
              }
            } else {
              j++;
            }
          }
          ctx.state.assocArrays[name] = assocMap;
          ctx.state.env[name] = assocMap.values.join(' ');
        } else {
          final values = _splitArrayValues(inner);
          ctx.state.arrays[name] = values;
          ctx.state.env[name] = values.join(' ');
        }
      } else {
        if (isArray) {
          ctx.state.arrays[name] = [rawValue];
        } else if (isAssoc) {
          ctx.state.assocArrays[name] = {};
        }
        ctx.state.env[name] = rawValue;
      }
    } else if (eq != 0) {
      final isArr = ctx.state.arrays.containsKey(args[i]);
      final isAss = ctx.state.assocArrays.containsKey(args[i]);
      if (isArr) {
        return ShellResult(
          exitCode: 0,
          stdout:
              'declare -a ${args[i]}=(${ctx.state.arrays[args[i]]!.map((s) => '"$s"').join(' ')})\n',
          stderr: '',
        );
      }
      if (isAss) {
        return ShellResult(
          exitCode: 0,
          stdout:
              'declare -A ${args[i]}=(${ctx.state.assocArrays[args[i]]!.entries.map((e) => '["${e.key}"]="${e.value}"').join(' ')})\n',
          stderr: '',
        );
      }
      return ShellResult(
        exitCode: 0,
        stdout: 'declare -- ${args[i]}="${ctx.state.lookupVar(args[i])}"\n',
        stderr: '',
      );
    }
  }

  return ShellResult.ok;
}

List<String> _splitArrayValues(String s) {
  final parts = <String>[];
  var inSingle = false;
  var inDouble = false;
  var current = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (inSingle) {
      if (c == '\'') { inSingle = false; } else { current.write(c); }
      continue;
    }
    if (inDouble) {
      if (c == '"') { inDouble = false; } else if (c == '\\' && i + 1 < s.length) {
        i++;
        current.write(s[i]);
      } else { current.write(c); }
      continue;
    }
    if (c == '\'') { inSingle = true; continue; }
    if (c == '"') { inDouble = true; continue; }
    if (c == ' ' || c == '\t') {
      if (current.isNotEmpty) { parts.add(current.toString()); current.clear(); }
    } else {
      current.write(c);
    }
  }
  if (current.isNotEmpty) parts.add(current.toString());
  return parts;
}

Future<ShellResult> _cmdLocal(ShellContext ctx, List<String> args) async {
  return _cmdDeclare(ctx, args);
}

Future<ShellResult> _cmdReadonly(ShellContext ctx, List<String> args) async {
  if (args.isEmpty) {
    return ShellResult(exitCode: 0, stdout: '', stderr: '');
  }
  for (final arg in args) {
    final eq = arg.indexOf('=');
    if (eq > 0) {
      ctx.state.env[arg.substring(0, eq)] = arg.substring(eq + 1);
    }
  }
  return ShellResult.ok;
}

Future<ShellResult> _cmdReadarray(ShellContext ctx, List<String> args) async {
  var arrayName = 'MAPFILE';
  var maxLines = -1;
  var skipLines = 0;
  var i = 0;

  while (i < args.length && args[i].startsWith('-')) {
    if (args[i] == '-t') { i++; continue; }
    if (args[i] == '-d' && i + 1 < args.length) { i += 2; continue; }
    if (args[i] == '-n' && i + 1 < args.length) {
      maxLines = int.tryParse(args[i + 1]) ?? -1;
      i += 2;
      continue;
    }
    if (args[i] == '-u' && i + 1 < args.length) { i += 2; continue; }
    if (args[i] == '-s' && i + 1 < args.length) {
      skipLines = int.tryParse(args[i + 1]) ?? 0;
      i += 2;
      continue;
    }
    if (args[i] == '-C' && i + 1 < args.length) { i += 2; continue; }
    if (args[i] == '-c' && i + 1 < args.length) { i += 2; continue; }
    break;
  }
  if (i < args.length) arrayName = args[i];

  try {
    final lines = <String>[];
    var count = 0;
    while (maxLines < 0 || count < maxLines) {
      final line = stdin.readLineSync();
      if (line == null) break;
      if (skipLines > 0) { skipLines--; continue; }
      lines.add(line);
      count++;
    }
    ctx.state.arrays[arrayName] = lines;
    ctx.state.env[arrayName] = lines.join(' ');
    return ShellResult.ok;
  } catch (_) {
    ctx.state.arrays[arrayName] = [];
    return ShellResult.ok;
  }
}
