import 'dart:io' show File;
import 'package:path/path.dart' as p;
import '../shell_builtin.dart';
import '../shell_result.dart';

Map<String, BuiltinFunction> dataBuiltins() => {
      'date': _cmdDate,
      'basename': _cmdBasename,
      'dirname': _cmdDirname,
      'realpath': _cmdRealpath,
      'sleep': _cmdSleep,
      'true': _cmdTrue,
      'false': _cmdFalse,
      ':': _cmdColon,
    };

// =============================================================================
// date
// =============================================================================

Future<ShellResult> _cmdDate(ShellContext ctx, List<String> args) async {
  if (args.isEmpty) {
    return ShellResult(
        exitCode: 0, stdout: '${DateTime.now()}\n', stderr: '');
  }
  if (args[0] == '-u' || args[0] == '--utc' || args[0] == '--universal') {
    return ShellResult(
        exitCode: 0, stdout: '${DateTime.now().toUtc()}\n', stderr: '');
  }
  if (args[0] == '-I' || args[0] == '--iso-8601') {
    final now = DateTime.now();
    return ShellResult(
      exitCode: 0,
      stdout:
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}\n',
      stderr: '',
    );
  }
  if (args[0] == '-r' && args.length > 1) {
    final target = ctx.expander.resolvePath(args[1]);
    try {
      final abs = ctx.vfsAbsolute(target);
      final stat = File(abs).statSync();
      return ShellResult(
          exitCode: 0, stdout: '${stat.modified}\n', stderr: '');
    } catch (e) {
      return ShellResult(
          exitCode: 1, stdout: '', stderr: 'date: $e\n');
    }
  }
  if (args[0] == '+%s') {
    return ShellResult(
      exitCode: 0,
      stdout: '${DateTime.now().millisecondsSinceEpoch ~/ 1000}\n',
      stderr: '',
    );
  }
  if (args.length >= 2 && args[0] == '-d' && args[1] == '@0') {
    return ShellResult(
        exitCode: 0, stdout: 'Thu Jan  1 00:00:00 UTC 1970\n', stderr: '');
  }
  if (args.length >= 2 && args[0] == '-d' && args[1].startsWith('@')) {
    final secs = int.tryParse(args[1].substring(1));
    if (secs != null) {
      final dt =
          DateTime.fromMillisecondsSinceEpoch(secs * 1000, isUtc: true);
      return ShellResult(
          exitCode: 0, stdout: '$dt\n', stderr: '');
    }
  }
  if (args[0] == '+%Y') {
    return ShellResult(
        exitCode: 0, stdout: '${DateTime.now().year}\n', stderr: '');
  }
  return ShellResult(
      exitCode: 0, stdout: '${DateTime.now()}\n', stderr: '');
}

// =============================================================================
// basename
// =============================================================================

Future<ShellResult> _cmdBasename(ShellContext ctx, List<String> args) async {
  if (args.isEmpty) {
    return const ShellResult(
      exitCode: 1, stdout: '', stderr: 'basename: missing operand',
    );
  }
  var path = args[0];
  var suffix = args.length > 2
      ? args[2]
      : (args.length > 1 && !args[1].startsWith('-') ? args[1] : '');
  final name = p.basename(path);
  if (suffix.isNotEmpty && name.endsWith(suffix)) {
    return ShellResult(
        exitCode: 0,
        stdout: '${name.substring(0, name.length - suffix.length)}\n',
        stderr: '');
  }
  return ShellResult(
      exitCode: 0, stdout: '$name\n', stderr: '');
}

// =============================================================================
// dirname
// =============================================================================

Future<ShellResult> _cmdDirname(ShellContext ctx, List<String> args) async {
  if (args.isEmpty) {
    return const ShellResult(
      exitCode: 1, stdout: '', stderr: 'dirname: missing operand',
    );
  }
  final dir = p.dirname(args[0]);
  return ShellResult(
      exitCode: 0,
      stdout: '${dir.isEmpty ? '.' : dir}\n',
      stderr: '');
}

// =============================================================================
// realpath
// =============================================================================

Future<ShellResult> _cmdRealpath(ShellContext ctx, List<String> args) async {
  if (args.isEmpty) {
    return const ShellResult(
      exitCode: 1, stdout: '', stderr: 'realpath: missing operand',
    );
  }
  try {
    final resolved = ctx.expander.resolvePath(args[0]);
    final abs = ctx.vfsAbsolute(resolved);
    return ShellResult(
        exitCode: 0, stdout: '$abs\n', stderr: '');
  } catch (e) {
    return ShellResult(
        exitCode: 1, stdout: '', stderr: 'realpath: $e\n');
  }
}

// =============================================================================
// sleep
// =============================================================================

Future<ShellResult> _cmdSleep(ShellContext ctx, List<String> args) async {
  if (args.isEmpty) {
    return const ShellResult(
      exitCode: 1, stdout: '', stderr: 'sleep: missing operand',
    );
  }

  final seconds = double.tryParse(args[0]);
  if (seconds == null || seconds < 0) {
    return ShellResult(
      exitCode: 1, stdout: '',
      stderr: 'sleep: invalid time interval: ${args[0]}',
    );
  }

  await Future.delayed(
      Duration(milliseconds: (seconds * 1000).round()));
  return ShellResult.ok;
}

// =============================================================================
// true / false / :
// =============================================================================

Future<ShellResult> _cmdTrue(ShellContext ctx, List<String> args) async =>
    ShellResult.ok;

Future<ShellResult> _cmdFalse(ShellContext ctx, List<String> args) async =>
    const ShellResult(exitCode: 1, stdout: '', stderr: '');

Future<ShellResult> _cmdColon(ShellContext ctx, List<String> args) async =>
    ShellResult.ok;
