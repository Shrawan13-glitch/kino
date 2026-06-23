import 'dart:io';
import 'package:path/path.dart' as p;
import '../../vfs/vfs_exception.dart';
import '../shell_builtin.dart';
import '../shell_result.dart';

Map<String, BuiltinFunction> shellCtrlBuiltins() => {
      'pwd': _cmdPwd,
      'cd': _cmdCd,
      'export': _cmdExport,
      'unset': _cmdUnset,
      'env': _cmdEnv,
      'set': _cmdSet,
      'shift': _cmdShift,
      'exit': _cmdExit,
      'return': _cmdReturn,
      'break': _cmdBreak,
      'continue': _cmdContinue,
      'source': _cmdSource,
      '.': _cmdSource,
      'exec': _cmdExec,
      'eval': _cmdEval,
      'let': _cmdLet,
    };

// =============================================================================
// pwd
// =============================================================================

Future<ShellResult> _cmdPwd(ShellContext ctx, List<String> args) async {
  String pwd;
  if (args.isNotEmpty && args[0] == '-P') {
    final abs = ctx.vfsAbsolute(ctx.state.cwd);
    pwd = FileSystemEntity.isLinkSync(abs)
        ? Directory(abs).resolveSymbolicLinksSync()
        : abs;
  } else {
    pwd = ctx.state.cwd;
  }
  return ShellResult(exitCode: 0, stdout: '$pwd\n', stderr: '');
}

// =============================================================================
// cd
// =============================================================================

Future<ShellResult> _cmdCd(ShellContext ctx, List<String> args) async {
  var target = ctx.state.env['HOME'] ?? '/';
  if (args.isNotEmpty) {
    if (args[0] == '-') {
      target = ctx.state.previousCwd;
    } else {
      final expanded = ctx.expander.expandVars(args[0]);
      final withTilde = ctx.expander.expandTilde(expanded);
      target = p.normalize(withTilde.startsWith('/')
          ? withTilde
          : p.join(ctx.state.cwd, withTilde));
      if (!target.startsWith('/')) target = '/$target';
    }
  }

  final abs = ctx.vfsAbsolute(target);
  final type = FileSystemEntity.typeSync(abs);
  if (type == FileSystemEntityType.notFound) {
    return ShellResult(
      exitCode: 1, stdout: '', stderr: 'cd: ${args.isNotEmpty ? args[0] : ''}: No such directory',
    );
  }
  if (type != FileSystemEntityType.directory) {
    return ShellResult(
      exitCode: 1, stdout: '', stderr: 'cd: ${args.isNotEmpty ? args[0] : ''}: Not a directory',
    );
  }

  ctx.state.previousCwd = ctx.state.cwd;
  ctx.state.cwd = target;
  ctx.state.env['PWD'] = ctx.state.cwd;
  ctx.state.env['OLDPWD'] = ctx.state.previousCwd;
  return ShellResult.ok;
}

// =============================================================================
// export
// =============================================================================

Future<ShellResult> _cmdExport(ShellContext ctx, List<String> args) async {
  if (args.isEmpty) {
    final output = StringBuffer();
    final sorted = ctx.state.env.keys.toList()..sort();
    for (final key in sorted) {
      output.writeln('export $key=${ctx.state.env[key]}');
    }
    return ShellResult(exitCode: 0, stdout: output.toString(), stderr: '');
  }

  for (final arg in args) {
    if (arg.contains('=')) {
      final eq = arg.indexOf('=');
      final name = arg.substring(0, eq);
      var value = arg.substring(eq + 1);
      if ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'"))) {
        value = value.substring(1, value.length - 1);
      }
      ctx.state.env[name] = value;
    }
  }

  return ShellResult.ok;
}

// =============================================================================
// unset
// =============================================================================

Future<ShellResult> _cmdUnset(ShellContext ctx, List<String> args) async {
  for (final arg in args) {
    ctx.state.env.remove(arg);
  }
  return ShellResult.ok;
}

// =============================================================================
// env
// =============================================================================

Future<ShellResult> _cmdEnv(ShellContext ctx, List<String> args) async {
  final output = StringBuffer();
  final sorted = ctx.state.env.keys.toList()..sort();
  for (final key in sorted) {
    output.writeln('$key=${ctx.state.env[key]}');
  }
  return ShellResult(exitCode: 0, stdout: output.toString(), stderr: '');
}

// =============================================================================
// set
// =============================================================================

Future<ShellResult> _cmdSet(ShellContext ctx, List<String> args) async {
  if (args.isEmpty) {
    final buf = StringBuffer();
    ctx.state.env.forEach((k, v) => buf.writeln('$k=$v'));
    ctx.state.arrays.forEach((k, v) => buf.writeln('$k=(${v.join(' ')})'));
    ctx.state.functions.forEach((k, v) => buf.writeln('$k () { ... }'));
    return ShellResult(exitCode: 0, stdout: buf.toString(), stderr: '');
  }

  var i = 0;
  while (i < args.length &&
      (args[i].startsWith('-') || args[i].startsWith('+'))) {
    final arg = args[i];
    final isSet = arg.startsWith('-');

    if (arg == '-o' && i + 1 < args.length) {
      i++;
      ctx.state.setFlags['-o ${args[i]}'] = true;
      i++;
      continue;
    }
    if (arg == '+o' && i + 1 < args.length) {
      i++;
      ctx.state.setFlags['-o ${args[i]}'] = false;
      i++;
      continue;
    }
    if (arg == '-o') {
      ctx.state.setFlags['-o'] = true;
      i++;
      continue;
    }

    for (var j = 1; j < arg.length; j++) {
      switch (arg[j]) {
        case 'e':
          ctx.state.setFlags['-e'] = isSet;
        case 'x':
          ctx.state.setFlags['-x'] = isSet;
        case 'u':
          ctx.state.setFlags['-u'] = isSet;
        case 'v':
          ctx.state.setFlags['-v'] = isSet;
        case 'C':
          ctx.state.setFlags['-C'] = isSet;
        case 'B':
          ctx.state.setFlags['-B'] = isSet;
        case 'f':
          ctx.state.setFlags['-f'] = isSet;
        case 'm':
          ctx.state.setFlags['-m'] = isSet;
        case 'a':
          ctx.state.setFlags['-a'] = isSet;
        case 'b':
          ctx.state.setFlags['-b'] = isSet;
        case 'h':
          ctx.state.setFlags['-h'] = isSet;
        case 'k':
          ctx.state.setFlags['-k'] = isSet;
        case 'n':
          ctx.state.setFlags['-n'] = isSet;
        case 't':
          ctx.state.setFlags['-t'] = isSet;
      }
    }
    i++;
  }

  if (i < args.length && args[i] == '--') {
    i++;
    ctx.state.positionalParams = args.sublist(i);
    ctx.state.env['@'] = ctx.state.positionalParams.join(' ');
    ctx.state.env['#'] = ctx.state.positionalParams.length.toString();
    i = args.length;
  } else if (i < args.length) {
    ctx.state.env['@'] = args.sublist(i).join(' ');
  }

  return ShellResult.ok;
}

// =============================================================================
// shift
// =============================================================================

Future<ShellResult> _cmdShift(ShellContext ctx, List<String> args) async {
  var n = 1;
  if (args.isNotEmpty) {
    n = int.tryParse(args[0]) ?? 1;
  }
  if (n > ctx.state.positionalParams.length) {
    return ShellResult(
      exitCode: 1, stdout: '', stderr: 'shift: shift count out of range',
    );
  }
  ctx.state.positionalParams = ctx.state.positionalParams.sublist(n);
  ctx.state.env['@'] = ctx.state.positionalParams.join(' ');
  ctx.state.env['#'] = ctx.state.positionalParams.length.toString();
  return ShellResult.ok;
}

// =============================================================================
// exit / return / break / continue
// =============================================================================

Future<ShellResult> _cmdExit(ShellContext ctx, List<String> args) async {
  final code = args.isNotEmpty ? int.tryParse(args[0]) ?? 0 : 0;
  ctx.state.exitRequested = true;
  return ShellResult(exitCode: code, stdout: '', stderr: '');
}

Future<ShellResult> _cmdReturn(ShellContext ctx, List<String> args) async {
  final code = args.isNotEmpty ? int.tryParse(args[0]) ?? 0 : 0;
  ctx.state.returnFromFunction = true;
  return ShellResult(exitCode: code, stdout: '', stderr: '');
}

Future<ShellResult> _cmdBreak(ShellContext ctx, List<String> args) async {
  final count = args.isNotEmpty ? int.tryParse(args[0]) ?? 1 : 1;
  ctx.state.breakDepth = count;
  return ShellResult.ok;
}

Future<ShellResult> _cmdContinue(ShellContext ctx, List<String> args) async {
  final count = args.isNotEmpty ? int.tryParse(args[0]) ?? 1 : 1;
  ctx.state.continueDepth = count;
  return ShellResult.ok;
}

// =============================================================================
// source / .
// =============================================================================

Future<ShellResult> _cmdSource(ShellContext ctx, List<String> args) async {
  if (args.isEmpty) {
    return const ShellResult(
      exitCode: 1, stdout: '', stderr: 'source: missing file argument',
    );
  }

  final target = ctx.expander.resolvePath(args[0]);
  try {
    final content = await ctx.vfs.readFileAsString(target);
    final lines = content.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final result = await ctx.execute(trimmed);
      if (!result.success) return result;
    }
    return ShellResult.ok;
  } on VfsNotFoundException {
    return ShellResult(
      exitCode: 1, stdout: '', stderr: 'source: ${args[0]}: No such file',
    );
  }
}

// =============================================================================
// exec
// =============================================================================

Future<ShellResult> _cmdExec(ShellContext ctx, List<String> args) async {
  if (args.isEmpty) {
    return ShellResult.ok;
  }
  final cmdArgs = <String>[];
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '>' && i + 1 < args.length) {
      i++;
      continue;
    } else if (args[i] == '>>' && i + 1 < args.length) {
      i++;
      continue;
    } else if (args[i] == '2>' && i + 1 < args.length) {
      i++;
      continue;
    } else if (args[i] == '&>' && i + 1 < args.length) {
      i++;
      continue;
    } else if (args[i] == '<' && i + 1 < args.length) {
      i++;
      continue;
    } else if (RegExp(r'^\d+>').hasMatch(args[i]) && i + 1 < args.length) {
      i++;
      continue;
    } else {
      cmdArgs.add(args[i]);
    }
  }
  if (cmdArgs.isEmpty) return ShellResult.ok;
  return ctx.fallback.runInShell(cmdArgs.join(' '));
}

// =============================================================================
// eval
// =============================================================================

Future<ShellResult> _cmdEval(ShellContext ctx, List<String> args) async {
  if (args.isEmpty) return ShellResult.ok;
  final cmd = args.join(' ');
  return ctx.execute(cmd);
}

// =============================================================================
// let
// =============================================================================

Future<ShellResult> _cmdLet(ShellContext ctx, List<String> args) async {
  if (args.isEmpty) {
    return const ShellResult(
      exitCode: 1, stdout: '', stderr: 'let: usage: let expression [expression ...]',
    );
  }
  for (final arg in args) {
    final eq = arg.indexOf('=');
    if (eq > 0) {
      final name = arg.substring(0, eq);
      final expr = arg.substring(eq + 1);
      final value = ctx.arithmetic.eval(expr);
      ctx.state.env[name] = value.toString();
    }
  }
  return ShellResult.ok;
}
