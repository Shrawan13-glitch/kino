import 'dart:io';
import '../shell_builtin.dart';
import '../shell_result.dart';

Map<String, BuiltinFunction> testBuiltins() => {
      'test': _cmdTest,
      '[': _cmdLeftBracket,
      '[[': _cmdDoubleBracket,
    };

// =============================================================================
// test
// =============================================================================

Future<ShellResult> _cmdTest(ShellContext ctx, List<String> args) async {
  if (args.isEmpty) return _false;

  var i = 0;
  if (args[0] == '!') {
    final innerResult = await _cmdTest(ctx, args.sublist(1));
    return innerResult.exitCode == 0 ? _false : _true;
  }

  if (args[i] == '-n') {
    if (args.length < 2) return _false;
    return args[1].isNotEmpty ? _true : _false;
  }

  if (args[i] == '-z') {
    if (args.length < 2) return _false;
    return args[1].isEmpty ? _true : _false;
  }

  if (args[i] == '-d') {
    if (args.length < 2) return _false;
    final target = ctx.expander.resolvePath(args[1]);
    final abs = ctx.vfsAbsolute(target);
    return FileSystemEntity.isDirectorySync(abs) ? _true : _false;
  }

  if (args[i] == '-f') {
    if (args.length < 2) return _false;
    final target = ctx.expander.resolvePath(args[1]);
    final abs = ctx.vfsAbsolute(target);
    return FileSystemEntity.isFileSync(abs) ? _true : _false;
  }

  if (args[i] == '-e') {
    if (args.length < 2) return _false;
    final target = ctx.expander.resolvePath(args[1]);
    final abs = ctx.vfsAbsolute(target);
    return FileSystemEntity.typeSync(abs) != FileSystemEntityType.notFound
        ? _true
        : _false;
  }

  if (args[i] == '-s') {
    if (args.length < 2) return _false;
    final target = ctx.expander.resolvePath(args[1]);
    final abs = ctx.vfsAbsolute(target);
    try {
      final stat = File(abs).statSync();
      return stat.size > 0 ? _true : _false;
    } catch (_) {
      return _false;
    }
  }

  if (args[i] == '-r') {
    if (args.length < 2) return _false;
    final target = ctx.expander.resolvePath(args[1]);
    final abs = ctx.vfsAbsolute(target);
    final stat = File(abs).statSync();
    return (stat.mode & 0x100) != 0 ? _true : _false;
  }

  if (args[i] == '-w') {
    if (args.length < 2) return _false;
    final target = ctx.expander.resolvePath(args[1]);
    final abs = ctx.vfsAbsolute(target);
    final stat = File(abs).statSync();
    return (stat.mode & 0x80) != 0 ? _true : _false;
  }

  if (args[i] == '-x') {
    if (args.length < 2) return _false;
    final target = ctx.expander.resolvePath(args[1]);
    final abs = ctx.vfsAbsolute(target);
    final stat = File(abs).statSync();
    return (stat.mode & 0x40) != 0 ? _true : _false;
  }

  if (args[i] == '-nt' && i + 2 < args.length) {
    try {
      final a = ctx.expander.resolvePath(args[i + 1]);
      final b = ctx.expander.resolvePath(args[i + 2]);
      final statA = await ctx.vfs.stat(a);
      final statB = await ctx.vfs.stat(b);
      return statA.modifiedAt.isAfter(statB.modifiedAt) ? _true : _false;
    } catch (_) {
      return _false;
    }
  }

  if (args[i] == '-ot' && i + 2 < args.length) {
    try {
      final a = ctx.expander.resolvePath(args[i + 1]);
      final b = ctx.expander.resolvePath(args[i + 2]);
      final statA = await ctx.vfs.stat(a);
      final statB = await ctx.vfs.stat(b);
      return statA.modifiedAt.isBefore(statB.modifiedAt) ? _true : _false;
    } catch (_) {
      return _false;
    }
  }

  if (args[i] == '-ef' && i + 2 < args.length) {
    final a = ctx.vfsAbsolute(ctx.expander.resolvePath(args[i + 1]));
    final b = ctx.vfsAbsolute(ctx.expander.resolvePath(args[i + 2]));
    return a == b ? _true : _false;
  }

  if (i + 2 < args.length && args[i + 1] == '=') {
    return args[i] == args[i + 2] ? _true : _false;
  }

  if (i + 2 < args.length && args[i + 1] == '!=') {
    return args[i] != args[i + 2] ? _true : _false;
  }

  if (i + 2 < args.length && args[i + 1] == '<') {
    return args[i].compareTo(args[i + 2]) < 0 ? _true : _false;
  }

  if (i + 2 < args.length && args[i + 1] == '>') {
    return args[i].compareTo(args[i + 2]) > 0 ? _true : _false;
  }

  if (i + 2 < args.length) {
    final cmpOps = {'-eq', '-ne', '-lt', '-le', '-gt', '-ge'};
    if (cmpOps.contains(args[i + 1])) {
      final a = int.tryParse(args[i]);
      final b = int.tryParse(args[i + 2]);
      if (a == null || b == null) return _false;
      bool cmp;
      switch (args[i + 1]) {
        case '-eq':
          cmp = a == b;
        case '-ne':
          cmp = a != b;
        case '-lt':
          cmp = a < b;
        case '-le':
          cmp = a <= b;
        case '-gt':
          cmp = a > b;
        case '-ge':
          cmp = a >= b;
        default:
          cmp = false;
      }
      return cmp ? _true : _false;
    }
  }

  return args[0].isNotEmpty ? _true : _false;
}

// =============================================================================
// [
// =============================================================================

Future<ShellResult> _cmdLeftBracket(ShellContext ctx, List<String> args) async {
  if (args.isNotEmpty && args.last == ']') {
    return _cmdTest(ctx, args.sublist(0, args.length - 1));
  }
  return _cmdTest(ctx, args);
}

// =============================================================================
// [[
// =============================================================================

Future<ShellResult> _cmdDoubleBracket(
    ShellContext ctx, List<String> args) async {
  if (args.isEmpty) return _false;
  var inner = args;
  if (inner.last == ']]') {
    inner = inner.sublist(0, inner.length - 1);
  }
  if (inner.isEmpty) return _false;
  if (inner.first == '[[') {
    inner = inner.sublist(1);
  }
  if (inner.isEmpty) return _false;
  return _evalBracketExpr(ctx, inner, 0);
}

Future<ShellResult> _evalBracketExpr(
    ShellContext ctx, List<String> args, int start) async {
  if (args[start] == '(') {
    var depth = 1;
    var end = start + 1;
    while (end < args.length && depth > 0) {
      if (args[end] == '(') {
        depth++;
      } else if (args[end] == ')') {
        depth--;
      }
      if (depth > 0) end++;
    }
    final innerResult = await _evalBracketExpr(ctx, args, start + 1);
    var result = innerResult.exitCode == 0;
    var i = end + 1;
    while (i < args.length) {
      if (args[i] == '&&') {
        i++;
        final right = await _evalBracketExpr(ctx, args, i);
        result = result && right.exitCode == 0;
        break;
      } else if (args[i] == '||') {
        i++;
        final right = await _evalBracketExpr(ctx, args, i);
        result = result || right.exitCode == 0;
        break;
      }
      break;
    }
    return ShellResult(exitCode: result ? 0 : 1, stdout: '', stderr: '');
  }
  final result = await _cmdTest(ctx, args.sublist(start));
  return result;
}

const _true = ShellResult(exitCode: 0, stdout: '', stderr: '');
const _false = ShellResult(exitCode: 1, stdout: '', stderr: '');
