import 'dart:async';
import 'dart:io' show stdout, Process;
import '../shell_builtin.dart';
import '../shell_result.dart';

Map<String, BuiltinFunction> jobsBuiltins() => {
      'jobs': _cmdJobs,
      'fg': _cmdFg,
      'bg': _cmdBg,
      'kill': _cmdKill,
      'wait': _cmdWait,
      'disown': _cmdDisown,
    };

Future<ShellResult> _cmdJobs(ShellContext ctx, List<String> args) async {
  if (ctx.state.jobs.isEmpty) {
    return ShellResult.ok;
  }
  final buf = StringBuffer();
  final sorted = ctx.state.jobs.keys.toList()..sort();
  for (final id in sorted) {
    final job = ctx.state.jobs[id]!;
    buf.writeln('[${job.id}]  ${job.status.padRight(8)}${job.command}');
  }
  return ShellResult(exitCode: 0, stdout: buf.toString(), stderr: '');
}

Future<ShellResult> _cmdBg(ShellContext ctx, List<String> args) async {
  int? jobId;
  if (args.isNotEmpty) {
    jobId = int.tryParse(args[0].replaceAll(RegExp(r'[%\[\]]'), ''));
  }
  if (jobId == null) {
    if (ctx.state.jobs.isEmpty) {
      return ShellResult(
          exitCode: 1, stdout: '', stderr: 'bg: no current job\n');
    }
    jobId = ctx.state.jobs.keys.last;
  }
  final job = ctx.state.jobs[jobId];
  if (job == null) {
    return ShellResult(
        exitCode: 1, stdout: '', stderr: 'bg: $jobId: no such job\n');
  }
  job.status = 'running';
  unawaited(job.process.exitCode.then((code) {
    if (ctx.state.jobs.containsKey(jobId)) {
      ctx.state.jobs[jobId]!.status = 'done';
      ctx.state.jobs[jobId]!.exitCode = code;
    }
  }));
  stdout.write('[${job.id}] $jobId\n');
  return ShellResult.ok;
}

Future<ShellResult> _cmdFg(ShellContext ctx, List<String> args) async {
  int? jobId;
  if (args.isNotEmpty) {
    jobId = int.tryParse(args[0].replaceAll(RegExp(r'[%\[\]]'), ''));
  }
  if (jobId == null) {
    if (ctx.state.jobs.isEmpty) {
      return ShellResult(
          exitCode: 1, stdout: '', stderr: 'fg: no current job\n');
    }
    jobId = ctx.state.jobs.keys.last;
  }
  final job = ctx.state.jobs[jobId];
  if (job == null) {
    return ShellResult(
        exitCode: 1, stdout: '', stderr: 'fg: $jobId: no such job\n');
  }
  stdout.write('${job.command}\n');
  final code = await job.process.exitCode;
  ctx.state.jobs.remove(jobId);
  return ShellResult(exitCode: code, stdout: '', stderr: '');
}

Future<ShellResult> _cmdKill(ShellContext ctx, List<String> args) async {
  if (args.isEmpty) {
    return ShellResult(
      exitCode: 1, stdout: '', stderr: 'kill: usage: kill [-s sigspec | -signum] pid...',
    );
  }
  var pids = <String>[];
  var i = 0;
  if (args[0] == '-l') {
    return ShellResult(
      exitCode: 0,
      stdout:
          ' 1) SIGHUP  2) SIGINT  3) SIGQUIT  4) SIGILL  5) SIGTRAP\n'
          ' 6) SIGABRT  7) SIGBUS  8) SIGFPE  9) SIGKILL 10) SIGUSR1\n'
          '11) SIGSEGV 12) SIGUSR2 13) SIGPIPE 14) SIGALRM 15) SIGTERM\n',
      stderr: '',
    );
  }
  if (args[i] == '-s' && i + 1 < args.length) {
    i += 2;
  } else if (args[i].startsWith('-') && args[i].length > 1) {
    i++;
  }
  for (; i < args.length; i++) {
    pids.add(args[i]);
  }
  if (pids.isEmpty) {
    return ShellResult(
        exitCode: 1, stdout: '', stderr: 'kill: usage: kill pid...');
  }
  for (final pid in pids) {
    try {
      Process.killPid(int.parse(pid));
    } catch (_) {}
  }
  return ShellResult.ok;
}

Future<ShellResult> _cmdWait(ShellContext ctx, List<String> args) async {
  if (args.isEmpty) {
    for (final job in ctx.state.jobs.values.toList()) {
      final code = await job.process.exitCode;
      job.status = 'done';
      job.exitCode = code;
    }
    return ShellResult.ok;
  }
  for (final arg in args) {
    final jobId = int.tryParse(arg.replaceAll(RegExp(r'[%\[\]]'), ''));
    if (jobId != null && ctx.state.jobs.containsKey(jobId)) {
      final job = ctx.state.jobs[jobId]!;
      final code = await job.process.exitCode;
      job.status = 'done';
      job.exitCode = code;
      ctx.state.jobs.remove(jobId);
    }
    final pid = int.tryParse(arg);
    if (pid != null) {
      try {
        Process.killPid(pid);
      } catch (_) {}
    }
  }
  return ShellResult.ok;
}

Future<ShellResult> _cmdDisown(ShellContext ctx, List<String> args) async {
  if (args.isEmpty) {
    if (ctx.state.jobs.isEmpty) return ShellResult.ok;
    final lastId = ctx.state.jobs.keys.last;
    ctx.state.jobs.remove(lastId);
    return ShellResult.ok;
  }
  for (final arg in args) {
    final jobId = int.tryParse(arg.replaceAll(RegExp(r'[%\[\]]'), ''));
    if (jobId != null) ctx.state.jobs.remove(jobId);
  }
  return ShellResult.ok;
}
