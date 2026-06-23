import 'dart:io';
import 'package:path/path.dart' as p;
import '../../vfs/vfs_exception.dart';
import '../shell_builtin.dart';
import '../shell_result.dart';

Map<String, BuiltinFunction> textBuiltins() => {
      'echo': _cmdEcho,
      'printf': _cmdPrintf,
      'grep': _cmdGrep,
      'wc': _cmdWc,
      'sort': _cmdSort,
      'uniq': _cmdUniq,
    };

// =============================================================================
// echo
// =============================================================================

Future<ShellResult> _cmdEcho(ShellContext ctx, List<String> args) async {
  var noNewline = false;
  var interpretEscapes = false;
  var i = 0;

  while (i < args.length && args[i].startsWith('-')) {
    if (args[i] == '-n') {
      noNewline = true;
      i++;
    } else if (args[i] == '-e') {
      interpretEscapes = true;
      i++;
    } else if (args[i] == '-E') {
      interpretEscapes = false;
      i++;
    } else {
      break;
    }
  }

  final text = args.sublist(i).join(' ');
  final out = interpretEscapes ? _unescape(text) : text;
  return ShellResult(
    exitCode: 0,
    stdout: out + (noNewline ? '' : '\n'),
    stderr: '',
  );
}

String _unescape(String s) {
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (s[i] == '\\' && i + 1 < s.length) {
      i++;
      switch (s[i]) {
        case 'n':
          b.write('\n');
        case 't':
          b.write('\t');
        case 'r':
          b.write('\r');
        case '\\':
          b.write('\\');
        case '0':
          b.write('\x00');
        default:
          b.write(s[i]);
      }
    } else {
      b.write(s[i]);
    }
  }
  return b.toString();
}

// =============================================================================
// printf
// =============================================================================

Future<ShellResult> _cmdPrintf(ShellContext ctx, List<String> args) async {
  if (args.isEmpty) {
    return ShellResult(
        exitCode: 1, stdout: '', stderr: 'printf: usage: printf format [arguments]\n');
  }
  final format = args[0];
  final fmtArgs = args.sublist(1);

  var argIdx = 0;
  var fmt = format;

  fmt = fmt
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\t', '\t')
      .replaceAll(r'\r', '\r')
      .replaceAll(r'\b', '\x08')
      .replaceAll(r'\f', '\x0c')
      .replaceAll(r'\v', '\x0b')
      .replaceAll(r'\a', '\x07')
      .replaceAll(r'\\', '\\')
      .replaceAll(r'\e', '\x1b')
      .replaceAll(r'\0', '\x00');

  final output = StringBuffer();
  var i = 0;
  while (i < fmt.length) {
    if (fmt[i] == '%' && i + 1 < fmt.length) {
      i++;
      var flags = '';
      while (i < fmt.length && '-+0 #,'.contains(fmt[i])) {
        flags += fmt[i];
        i++;
      }
      String? width;
      if (i < fmt.length && fmt[i] == '*') {
        width = argIdx < fmtArgs.length ? fmtArgs[argIdx++] : '';
        i++;
      } else {
        final wStart = i;
        while (i < fmt.length && fmt[i].codeUnitAt(0) >= 48 && fmt[i].codeUnitAt(0) <= 57) {
          i++;
        }
        if (i > wStart) width = fmt.substring(wStart, i);
      }
      String? precision;
      if (i < fmt.length && fmt[i] == '.') {
        i++;
        if (i < fmt.length && fmt[i] == '*') {
          precision = argIdx < fmtArgs.length ? fmtArgs[argIdx++] : '';
          i++;
        } else {
          final pStart = i;
          while (i < fmt.length && fmt[i].codeUnitAt(0) >= 48 && fmt[i].codeUnitAt(0) <= 57) {
            i++;
          }
          if (i > pStart) precision = fmt.substring(pStart, i);
        }
      }
      if (i >= fmt.length) break;
      final spec = fmt[i];
      i++;

      String arg;
      if (spec == '%') {
        arg = '%';
      } else {
        arg = argIdx < fmtArgs.length ? fmtArgs[argIdx++] : '';
      }

      String formatted;
      switch (spec) {
        case 's':
          formatted = arg;
        case 'd':
        case 'i':
          final n = int.tryParse(arg) ?? 0;
          formatted = n.toString();
        case 'u':
          final n = int.tryParse(arg) ?? 0;
          formatted = (n < 0 ? 0 : n).toString();
        case 'o':
          final n = int.tryParse(arg) ?? 0;
          formatted = n.toRadixString(8);
        case 'x':
          final n = int.tryParse(arg) ?? 0;
          formatted = n.toRadixString(16);
        case 'X':
          final n = int.tryParse(arg) ?? 0;
          formatted = n.toRadixString(16).toUpperCase();
        case 'f':
          final n = double.tryParse(arg) ?? 0.0;
          final prec = precision != null ? int.parse(precision) : 6;
          formatted = n.toStringAsFixed(prec);
        case 'e':
          final n = double.tryParse(arg) ?? 0.0;
          final prec = precision != null ? int.parse(precision) : 6;
          formatted = n.toStringAsExponential(prec);
        case 'E':
          final n = double.tryParse(arg) ?? 0.0;
          final prec = precision != null ? int.parse(precision) : 6;
          formatted = n.toStringAsExponential(prec).toUpperCase();
        case 'g':
        case 'G':
          final n = double.tryParse(arg) ?? 0.0;
          final prec = precision != null ? int.parse(precision) : 6;
          formatted = n.toStringAsPrecision(prec);
          if (spec == 'G') formatted = formatted.toUpperCase();
        case 'a':
        case 'A':
          final n = double.tryParse(arg) ?? 0.0;
          final hex = n.toInt().toRadixString(16);
          formatted = spec == 'A' ? '0X${hex.toUpperCase()}' : '0x$hex';
        case 'n':
          formatted = output.length.toString();
        case 'q':
          formatted = _quoteForShell(arg);
        case 'b':
          formatted = arg
              .replaceAll(r'\n', '\n')
              .replaceAll(r'\t', '\t')
              .replaceAll(r'\r', '\r')
              .replaceAll(r'\b', '\x08')
              .replaceAll(r'\f', '\x0c')
              .replaceAll(r'\v', '\x0b')
              .replaceAll(r'\a', '\x07')
              .replaceAll(r'\\', '\\')
              .replaceAll(r'\0', '\x00')
              .replaceAllMapped(RegExp(r'\\([0-7]{1,3})'),
                  (m) => String.fromCharCode(int.parse(m[1]!, radix: 8)))
              .replaceAllMapped(RegExp(r'\\x([0-9a-fA-F]{1,2})'),
                  (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)));
        default:
          formatted = '%$spec$arg';
      }

      if (width != null) {
        final w = int.tryParse(width) ?? 0;
        if (w.abs() > formatted.length) {
          final padding = w.abs() - formatted.length;
          final padChar = flags.contains('0') && !flags.contains('-') ? '0' : ' ';
          if (flags.contains('-')) {
            formatted = formatted + (padChar * padding);
          } else {
            formatted = (padChar * padding) + formatted;
          }
        }
      }

      if (flags.contains('+') && !formatted.startsWith('-') && spec != 's' && spec != '%') {
        formatted = '+$formatted';
      }
      if (flags.contains(' ') && !formatted.startsWith('-') && !formatted.startsWith('+') && spec != 's' && spec != '%') {
        formatted = ' $formatted';
      }

      output.write(formatted);
    } else {
      output.write(fmt[i]);
      i++;
    }
  }

  return ShellResult(exitCode: 0, stdout: output.toString(), stderr: '');
}

String _quoteForShell(String s) {
  if (s.isEmpty) return "''";
  if (RegExp(r'^[a-zA-Z0-9_./-]+$').hasMatch(s)) return s;
  return "'${s.replaceAll("'", "'\\''")}'";
}

// =============================================================================
// grep
// =============================================================================

Future<ShellResult> _cmdGrep(ShellContext ctx, List<String> args) async {
  if (args.isEmpty) {
    return const ShellResult(
      exitCode: 2, stdout: '', stderr: 'grep: usage: grep [options] pattern [file...]',
    );
  }

  var ignoreCase = false;
  var lineNumbers = false;
  var countOnly = false;
  var invert = false;
  var recursive = false;
  var i = 0;

  while (i < args.length && args[i].startsWith('-')) {
    final opt = args[i];
    if (opt == '-i') {
      ignoreCase = true;
      i++;
    } else if (opt == '-n') {
      lineNumbers = true;
      i++;
    } else if (opt == '-c') {
      countOnly = true;
      i++;
    } else if (opt == '-v') {
      invert = true;
      i++;
    } else if (opt == '-r' || opt == '-R') {
      recursive = true;
      i++;
    } else if (opt == '-iv' || opt == '-vi') {
      ignoreCase = true;
      invert = true;
      i++;
    } else if (opt == '--') {
      i++;
      break;
    } else {
      return ShellResult(
        exitCode: 2, stdout: '', stderr: 'grep: invalid option: $opt',
      );
    }
  }

  if (i >= args.length) {
    return const ShellResult(
      exitCode: 2, stdout: '', stderr: 'grep: missing pattern',
    );
  }

  final pattern = args[i];
  i++;
  final files = args.sublist(i);

  try {
    final regex = RegExp(pattern, caseSensitive: !ignoreCase);
    final output = StringBuffer();
    var matchCount = 0;

    Future<void> searchFile(String filePath, String fileName) async {
      try {
        final content = await ctx.vfs.readFileAsString(filePath);
        final lines = content.split('\n');
        for (var li = 0; li < lines.length; li++) {
          final line = lines[li];
          final matches = regex.hasMatch(line);
          final includeLine = invert ? !matches : matches;
          if (includeLine) {
            matchCount++;
            if (!countOnly) {
              if (files.length > 1 || recursive) {
                output.write('$fileName:');
              }
              if (lineNumbers) output.write('${li + 1}:');
              output.writeln(line);
            }
          }
        }
      } on VfsNotFoundException {
        // skip
      } catch (e) {
        output.writeln('grep: $fileName: $e');
      }
    }

    if (files.isEmpty) {
      final abs = ctx.vfsAbsolute(ctx.state.cwd);
      final dir = Directory(abs);
      if (dir.existsSync()) {
        for (final e in dir.listSync()) {
          if (e is File) {
            final name = p.basename(e.path);
            final vfsPath = ctx.state.cwd == '/' ? '/$name' : '${ctx.state.cwd}/$name';
            await searchFile(vfsPath, name);
          }
        }
      }
    } else {
      for (final file in files) {
        final target = ctx.expander.resolvePath(file);
        final abs = ctx.vfsAbsolute(target);
        final type = FileSystemEntity.typeSync(abs);
        if (type == FileSystemEntityType.directory) {
          final dir = Directory(abs);
          try {
            await for (final e in dir.list(recursive: true)) {
              if (e is File) {
                final rel = p.relative(e.path, from: ctx.vfs.rootPath);
                final vfsPath = '/$rel';
                await searchFile(vfsPath, rel);
              }
            }
          } catch (_) {}
        } else {
          await searchFile(target, file);
        }
      }
    }

    if (countOnly) {
      output.write(matchCount.toString());
      if (files.length > 1 || recursive) output.writeln();
    }

    return ShellResult(
      exitCode: matchCount > 0 ? 0 : 1,
      stdout: output.toString(),
      stderr: '',
    );
  } catch (e) {
    return ShellResult(
      exitCode: 2, stdout: '', stderr: 'grep: invalid regex: $e',
    );
  }
}

// =============================================================================
// wc
// =============================================================================

Future<ShellResult> _cmdWc(ShellContext ctx, List<String> args) async {
  if (args.isEmpty) {
    return const ShellResult(
      exitCode: 1, stdout: '', stderr: 'wc: missing file operand',
    );
  }

  var totalLines = 0;
  var totalWords = 0;
  var totalChars = 0;
  final output = StringBuffer();

  for (final arg in args) {
    final target = ctx.expander.resolvePath(arg);
    try {
      final content = await ctx.vfs.readFileAsString(target);
      final lines = content.split('\n');
      final lineCount = content.isEmpty
          ? 0
          : content.endsWith('\n') ? lines.length - 1 : lines.length;
      final wordCount =
          content.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
      final charCount = content.length;

      totalLines += lineCount;
      totalWords += wordCount;
      totalChars += charCount;

      output.writeln(
          '${lineCount.toString().padLeft(7)}${wordCount.toString().padLeft(7)}${charCount.toString().padLeft(7)} $arg');
    } on VfsNotFoundException {
      output.writeln('wc: $arg: No such file');
    } catch (e) {
      output.writeln('wc: $arg: $e');
    }
  }

  if (args.length > 1) {
    output.writeln(
        '${totalLines.toString().padLeft(7)}${totalWords.toString().padLeft(7)}${totalChars.toString().padLeft(7)} total');
  }

  return ShellResult(exitCode: 0, stdout: output.toString(), stderr: '');
}

// =============================================================================
// sort
// =============================================================================

Future<ShellResult> _cmdSort(ShellContext ctx, List<String> args) async {
  var numeric = false;
  var reverse = false;
  var unique = false;
  var files = <String>[];
  var i = 0;

  while (i < args.length) {
    if (args[i] == '-n') {
      numeric = true;
      i++;
    } else if (args[i] == '-r') {
      reverse = true;
      i++;
    } else if (args[i] == '-u') {
      unique = true;
      i++;
    } else if (args[i].startsWith('-')) {
      return ShellResult(
        exitCode: 1, stdout: '', stderr: 'sort: invalid option: ${args[i]}',
      );
    } else {
      files.add(args[i]);
      i++;
    }
  }

  if (files.isEmpty) {
    return const ShellResult(
      exitCode: 1, stdout: '', stderr: 'sort: missing file operand',
    );
  }

  var allLines = <String>[];
  for (final file in files) {
    final target = ctx.expander.resolvePath(file);
    try {
      final content = await ctx.vfs.readFileAsString(target);
      allLines.addAll(content.split('\n'));
    } on VfsNotFoundException {
      return ShellResult(
        exitCode: 1, stdout: '', stderr: 'sort: $file: No such file',
      );
    }
  }

  if (numeric) {
    allLines.sort((a, b) {
      final an = double.tryParse(a.trim()) ?? double.nan;
      final bn = double.tryParse(b.trim()) ?? double.nan;
      if (an.isNaN && bn.isNaN) return a.compareTo(b);
      if (an.isNaN) return 1;
      if (bn.isNaN) return -1;
      return an.compareTo(bn);
    });
  } else {
    allLines.sort();
  }

  if (reverse) allLines = allLines.reversed.toList();

  final output = StringBuffer();
  final seen = <String>{};
  for (final line in allLines) {
    if (unique) {
      if (seen.contains(line)) continue;
      seen.add(line);
    }
    output.writeln(line);
  }

  return ShellResult(exitCode: 0, stdout: output.toString(), stderr: '');
}

// =============================================================================
// uniq
// =============================================================================

Future<ShellResult> _cmdUniq(ShellContext ctx, List<String> args) async {
  var file = '';
  var i = 0;
  while (i < args.length && args[i].startsWith('-')) {
    i++;
  }
  if (i < args.length) file = args[i];

  if (file.isEmpty) {
    return const ShellResult(
      exitCode: 1, stdout: '', stderr: 'uniq: missing file operand',
    );
  }

  try {
    final target = ctx.expander.resolvePath(file);
    final content = await ctx.vfs.readFileAsString(target);
    final lines = content.split('\n');
    final output = StringBuffer();
    String? last;
    for (final line in lines) {
      if (line != last) {
        output.writeln(line);
        last = line;
      }
    }
    return ShellResult(exitCode: 0, stdout: output.toString(), stderr: '');
  } catch (e) {
    return ShellResult(exitCode: 1, stdout: '', stderr: 'uniq: $e\n');
  }
}
