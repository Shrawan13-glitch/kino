import 'dart:io' show stdout, stderr, stdin, File;
import 'package:path/path.dart' as p;
import '../shell_builtin.dart';
import '../shell_result.dart';

Map<String, BuiltinFunction> miscBuiltins() => {
      'alias': _cmdAlias,
      'unalias': _cmdUnalias,
      'history': _cmdHistory,
      'shopt': _cmdShopt,
      'type': _cmdType,
      'which': _cmdWhich,
      'help': _cmdHelp,
      'clear': _cmdClear,
      'command': _cmdCommand,
      'builtin': _cmdBuiltin,
      'hash': _cmdHash,
      'fc': _cmdFc,
      'ulimit': _cmdUlimit,
      'umask': _cmdUmask,
      'logout': _cmdLogout,
      'suspend': _cmdSuspend,
      'times': _cmdTimes,
      'caller': _cmdCaller,
      'bind': _cmdBind,
      'complete': _cmdComplete,
      'compgen': _cmdCompgen,
      'enable': _cmdEnable,
      'getopts': _cmdGetopts,
      'select': _cmdSelect,
      'compopt': _cmdCompopt,
    };

// =============================================================================
// alias / unalias
// =============================================================================

Future<ShellResult> _cmdAlias(ShellContext ctx, List<String> args) async {
  if (args.isEmpty) {
    final buf = StringBuffer();
    ctx.state.aliases.forEach((k, v) => buf.writeln('alias $k=\'$v\''));
    return ShellResult(exitCode: 0, stdout: buf.toString(), stderr: '');
  }
  for (final arg in args) {
    final eq = arg.indexOf('=');
    if (eq > 0) {
      var value = arg.substring(eq + 1);
      if ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'"))) {
        value = value.substring(1, value.length - 1);
      }
      ctx.state.aliases[arg.substring(0, eq)] = value;
    } else if (ctx.state.aliases.containsKey(arg)) {
      return ShellResult(
        exitCode: 0,
        stdout: 'alias $arg=\'${ctx.state.aliases[arg]}\'\n',
        stderr: '',
      );
    } else {
      return ShellResult(
        exitCode: 1, stdout: '',
        stderr: 'alias: $arg: not found\n',
      );
    }
  }
  return ShellResult.ok;
}

Future<ShellResult> _cmdUnalias(ShellContext ctx, List<String> args) async {
  if (args.isEmpty) return ShellResult.ok;
  for (final arg in args) {
    if (arg == '-a') {
      ctx.state.aliases.clear();
      return ShellResult.ok;
    }
    ctx.state.aliases.remove(arg);
  }
  return ShellResult.ok;
}

// =============================================================================
// history
// =============================================================================

Future<ShellResult> _cmdHistory(ShellContext ctx, List<String> args) async {
  if (ctx.state.history.isEmpty) return ShellResult.ok;

  if (args.isNotEmpty && args[0] == '-c') {
    ctx.state.history.clear();
    return ShellResult.ok;
  }
  if (args.isNotEmpty && args[0] == '-r') {
    return ShellResult.ok;
  }
  if (args.isNotEmpty && args[0] == '-w') {
    return ShellResult.ok;
  }

  final buf = StringBuffer();
  for (var i = 0; i < ctx.state.history.length; i++) {
    buf.writeln('  ${i + 1}  ${ctx.state.history[i]}');
  }
  return ShellResult(exitCode: 0, stdout: buf.toString(), stderr: '');
}

// =============================================================================
// shopt
// =============================================================================

Future<ShellResult> _cmdShopt(ShellContext ctx, List<String> args) async {
  if (args.isEmpty) {
    final buf = StringBuffer();
    ctx.state.shopt.forEach((k, v) => buf.writeln('shopt -s $k'));
    return ShellResult(exitCode: 0, stdout: buf.toString(), stderr: '');
  }

  var setFlag = false;
  var unsetFlag = false;
  var i = 0;

  if (args[i] == '-s') { setFlag = true; i++; }
  if (args[i] == '-u') { unsetFlag = true; i++; }

  if (setFlag || unsetFlag) {
    for (; i < args.length; i++) {
      ctx.state.shopt[args[i]] = setFlag;
    }
    return ShellResult.ok;
  }

  if (args[i] == '-p') {
    i++;
    final buf = StringBuffer();
    for (; i < args.length; i++) {
      final val = ctx.state.shopt[args[i]] ?? false;
      buf.writeln('shopt ${val ? '-s' : '-u'} ${args[i]}');
    }
    return ShellResult(exitCode: 0, stdout: buf.toString(), stderr: '');
  }
  if (args[i] == '-q') {
    i++;
    var allOk = true;
    for (; i < args.length; i++) {
      if (!(ctx.state.shopt[args[i]] ?? false)) {
        allOk = false;
      }
    }
    return ShellResult(
      exitCode: allOk ? 0 : 1, stdout: '', stderr: '',
    );
  }

  return ShellResult.ok;
}

// =============================================================================
// type
// =============================================================================

Future<ShellResult> _cmdType(ShellContext ctx, List<String> args) async {
  if (args.isEmpty) {
    return ShellResult(
        exitCode: 1, stdout: '', stderr: 'type: missing operand');
  }
  final buf = StringBuffer();
  for (final arg in args) {
    if (ctx.state.aliases.containsKey(arg)) {
      buf.writeln('$arg is aliased to \'${ctx.state.aliases[arg]}\'');
    } else if (ctx.builtins.containsKey(arg)) {
      buf.writeln('$arg is a shell builtin');
    } else if (ctx.state.functions.containsKey(arg)) {
      buf.writeln('$arg is a function');
    } else {
      final found = _findInPath(ctx, arg);
      if (found != null) {
        buf.writeln('$arg is $found');
      } else {
        buf.writeln('$arg: not found');
      }
    }
  }
  return ShellResult(exitCode: 0, stdout: buf.toString(), stderr: '');
}

// =============================================================================
// which
// =============================================================================

Future<ShellResult> _cmdWhich(ShellContext ctx, List<String> args) async {
  if (args.isEmpty) {
    return ShellResult(
        exitCode: 1, stdout: '', stderr: 'which: missing operand');
  }
  final buf = StringBuffer();
  for (final arg in args) {
    if (ctx.builtins.containsKey(arg)) {
      buf.writeln('$arg: shell built-in command');
    } else {
      final found = _findInPath(ctx, arg);
      if (found != null) {
        buf.writeln(found);
      } else {
        buf.writeln('$arg not found');
      }
    }
  }
  return ShellResult(
    exitCode: 0, stdout: buf.toString(), stderr: '',
  );
}

// =============================================================================
// help
// =============================================================================

Future<ShellResult> _cmdHelp(ShellContext ctx, List<String> args) async {
  final allBuiltins = ctx.builtins.names;
  if (args.isEmpty) {
    return ShellResult(
      exitCode: 0,
      stdout:
          'GNU bash, version 5.2.37(1)-release (aarch64-apple-darwin)\n'
          'These shell commands are defined internally.\n\n'
          '${allBuiltins.join(', ')}\n\n',
      stderr: '',
    );
  }
  final topic = args[0];
  if (allBuiltins.contains(topic)) {
    return ShellResult(
      exitCode: 0,
      stdout: '$topic: shell built-in command\n',
      stderr: '',
    );
  }
  return ShellResult(
    exitCode: 1, stdout: '',
    stderr: 'help: no help topics match \'$topic\'\n',
  );
}

// =============================================================================
// clear
// =============================================================================

Future<ShellResult> _cmdClear(ShellContext ctx, List<String> args) async {
  stdout.write('\x1B[2J\x1B[0;0H');
  return ShellResult.ok;
}

// =============================================================================
// command
// =============================================================================

Future<ShellResult> _cmdCommand(ShellContext ctx, List<String> args) async {
  if (args.isEmpty) {
    return ShellResult(
        exitCode: 1, stdout: '', stderr: 'command: missing operand');
  }
  var showV = false;
  var showVv = false;
  var i = 0;
  if (args[i] == '-v') { showV = true; i++; }
  if (args[i] == '-V') { showVv = true; i++; }
  if (i >= args.length) return ShellResult(exitCode: 0, stdout: '', stderr: '');

  if (showV) {
    final cmd = args[i];
    if (ctx.builtins.containsKey(cmd)) {
      return ShellResult(
          exitCode: 0, stdout: '$cmd\n', stderr: '');
    }
    final found = _findInPath(ctx, cmd);
    if (found != null) {
      return ShellResult(
          exitCode: 0, stdout: '$found\n', stderr: '');
    }
    return ShellResult(
        exitCode: 1, stdout: '', stderr: '');
  }
  if (showVv) {
    return ShellResult(
        exitCode: 0, stdout: '${args[i]} is hashed (${_findInPath(ctx, args[i]) ?? args[i]})\n', stderr: '');
  }

  return ShellResult(
    exitCode: 1, stdout: '',
    stderr: 'command: ${args[i]}: not found\n',
  );
}

// =============================================================================
// builtin
// =============================================================================

Future<ShellResult> _cmdBuiltin(ShellContext ctx, List<String> args) async {
  if (args.isEmpty) {
    return ShellResult(
        exitCode: 1, stdout: '', stderr: 'builtin: missing operand');
  }
  final name = args[0];
  if (!ctx.builtins.containsKey(name)) {
    return ShellResult(
      exitCode: 1, stdout: '',
      stderr: 'builtin: $name: not a shell builtin\n',
    );
  }
  return ctx.builtins.call(name, ctx, args.sublist(1));
}

// =============================================================================
// hash
// =============================================================================

Future<ShellResult> _cmdHash(ShellContext ctx, List<String> args) async {
  if (args.contains('-r')) {
    ctx.state.hashTable.clear();
    return ShellResult.ok;
  }
  if (args.isEmpty) {
    final buf = StringBuffer();
    ctx.state.hashTable.forEach((k, v) => buf.writeln('$k=$v'));
    return ShellResult(exitCode: 0, stdout: buf.toString(), stderr: '');
  }
  for (final arg in args) {
    final found = _findInPath(ctx, arg);
    if (found != null) {
      ctx.state.hashTable[arg] = found;
    }
  }
  return ShellResult.ok;
}

// =============================================================================
// fc
// =============================================================================

Future<ShellResult> _cmdFc(ShellContext ctx, List<String> args) async {
  final hist = ctx.state.history;
  if (hist.isEmpty) {
    return ShellResult(
        exitCode: 1, stdout: '', stderr: 'fc: no history');
  }
  if (args.isNotEmpty && args[0] == '-l') {
    final buf = StringBuffer();
    for (var i = 0; i < hist.length; i++) {
      buf.writeln('${i + 1}\t${hist[i]}');
    }
    return ShellResult(
        exitCode: 0, stdout: buf.toString(), stderr: '');
  }
  if (args.isNotEmpty && args[0] == '-r') {
    final buf = StringBuffer();
    for (var i = hist.length - 1; i >= 0; i--) {
      buf.writeln('${i + 1}\t${hist[i]}');
    }
    return ShellResult(
        exitCode: 0, stdout: buf.toString(), stderr: '');
  }
  final last = hist.isNotEmpty ? hist.last : '';
  return ShellResult(exitCode: 0, stdout: '$last\n', stderr: '');
}

// =============================================================================
// ulimit
// =============================================================================

Future<ShellResult> _cmdUlimit(ShellContext ctx, List<String> args) async {
  if (args.isEmpty) {
    return ShellResult(
        exitCode: 0, stdout: 'unlimited\n', stderr: '');
  }
  if (args[0] == '-a') {
    return ShellResult(
      exitCode: 0,
      stdout:
          'core file size          (blocks, -c) 0\n'
          'data seg size           (kbytes, -d) unlimited\n'
          'file size               (blocks, -f) unlimited\n'
          'open files                      (-n) 1024\n'
          'stack size              (kbytes, -s) 8192\n'
          'cpu time               (seconds, -t) unlimited\n'
          'max user processes              (-u) 4096\n'
          'virtual memory          (kbytes, -v) unlimited\n',
      stderr: '',
    );
  }
  if (args[0] == '-n') {
    return ShellResult(
        exitCode: 0, stdout: '1024\n', stderr: '');
  }
  if (args[0] == '-u') {
    return ShellResult(
        exitCode: 0, stdout: '4096\n', stderr: '');
  }
  if (args[0] == '-s') {
    return ShellResult(
        exitCode: 0, stdout: '8192\n', stderr: '');
  }
  return ShellResult(exitCode: 0, stdout: '', stderr: '');
}

// =============================================================================
// umask
// =============================================================================

Future<ShellResult> _cmdUmask(ShellContext ctx, List<String> args) async {
  if (args.isEmpty) {
    return ShellResult(
        exitCode: 0, stdout: '0022\n', stderr: '');
  }
  final mask = int.tryParse(args[0], radix: 8);
  if (mask != null) {
    ctx.state.umask = mask;
  }
  return ShellResult.ok;
}

// =============================================================================
// logout
// =============================================================================

Future<ShellResult> _cmdLogout(ShellContext ctx, List<String> args) async {
  return const ShellResult(
      exitCode: 0, stdout: '', stderr: '');
}

// =============================================================================
// suspend
// =============================================================================

Future<ShellResult> _cmdSuspend(ShellContext ctx, List<String> args) async {
  return ShellResult.ok;
}

// =============================================================================
// times
// =============================================================================

Future<ShellResult> _cmdTimes(ShellContext ctx, List<String> args) async {
  return ShellResult(
      exitCode: 0, stdout: '0m0.000s 0m0.000s\n0m0.000s 0m0.000s\n', stderr: '');
}

// =============================================================================
// caller
// =============================================================================

Future<ShellResult> _cmdCaller(ShellContext ctx, List<String> args) async {
  return ShellResult(
      exitCode: 0, stdout: '0 main\n', stderr: '');
}

// =============================================================================
// bind
// =============================================================================

Future<ShellResult> _cmdBind(ShellContext ctx, List<String> args) async {
  if (args.isEmpty) {
    return ShellResult(
        exitCode: 0, stdout: '', stderr: '');
  }
  if (args[0] == '-p') {
    return ShellResult(
        exitCode: 0, stdout: '', stderr: '');
  }
  return ShellResult.ok;
}

// =============================================================================
// complete / compgen / compopt
// =============================================================================

Future<ShellResult> _cmdComplete(ShellContext ctx, List<String> args) async {
  return ShellResult.ok;
}

Future<ShellResult> _cmdCompgen(ShellContext ctx, List<String> args) async {
  if (args.isEmpty) {
    return ShellResult(exitCode: 0, stdout: '', stderr: '');
  }
  if (args.length >= 2) {
    if (args[0] == '-W' && args[1].isNotEmpty) {
      return ShellResult(
          exitCode: 0, stdout: '${args[1]}\n', stderr: '');
    }
    if (args[0] == '-c') {
      final cmd = args[1];
      if (ctx.builtins.containsKey(cmd)) {
        return ShellResult(
            exitCode: 0, stdout: '$cmd\n', stderr: '');
      }
    }
    if (args[0] == '-a' || args[0] == '-b') {
      final buf = StringBuffer();
      for (final name in ctx.builtins.names) {
        if (name.startsWith(args[1])) {
          buf.writeln(name);
        }
      }
      return ShellResult(
          exitCode: 0, stdout: buf.toString(), stderr: '');
    }
  }
  return ShellResult(exitCode: 0, stdout: '', stderr: '');
}

Future<ShellResult> _cmdCompopt(ShellContext ctx, List<String> args) async {
  return ShellResult.ok;
}

// =============================================================================
// enable
// =============================================================================

Future<ShellResult> _cmdEnable(ShellContext ctx, List<String> args) async {
  if (args.isEmpty) {
    final buf = StringBuffer();
    for (final name in ctx.builtins.names) {
      buf.writeln('enable $name');
    }
    return ShellResult(
        exitCode: 0, stdout: buf.toString(), stderr: '');
  }
  if (args[0] == '-n') {
    return ShellResult.ok;
  }

  // enable individual builtins
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '-a') {
      // enable all — already done
    } else if (args[i] == '-d') {
      // delete a builtin
    }
  }

  return ShellResult.ok;
}

// =============================================================================
// getopts
// =============================================================================

Future<ShellResult> _cmdGetopts(ShellContext ctx, List<String> args) async {
  if (args.length < 2) {
    return ShellResult(
        exitCode: 1, stdout: '', stderr: 'getopts: missing operand');
  }
  ctx.state.env['OPTIND'] = '1';
  ctx.state.env['OPTERR'] = '1';
  return ShellResult.ok;
}

// =============================================================================
// select
// =============================================================================

Future<ShellResult> _cmdSelect(ShellContext ctx, List<String> args) async {
  if (args.isEmpty) {
    return ShellResult(
        exitCode: 1, stdout: '', stderr: 'select: missing operand');
  }
  final varName = args[0];
  final words = args.sublist(1);
  for (var i = 0; i < words.length; i++) {
    stderr.writeln('$i) ${words[i]}');
  }
  stderr.write('#? ');
  final line = stdin.readLineSync() ?? '';
  if (line.isNotEmpty) {
    final idx = int.tryParse(line);
    if (idx != null && idx >= 0 && idx < words.length) {
      ctx.state.env[varName] = words[idx];
    }
  }
  return ShellResult.ok;
}

// =============================================================================
// Helpers
// =============================================================================

String? _findInPath(ShellContext ctx, String cmd) {
  final path = ctx.state.env['PATH'] ?? '/usr/local/bin:/usr/bin:/bin';
  for (final dir in path.split(':')) {
    final fullPath = p.join(dir, cmd);
    try {
      final file = File(fullPath);
      if (file.existsSync()) {
        ctx.state.hashTable[cmd] = fullPath;
        return fullPath;
      }
    } catch (_) {}
  }
  return null;
}
