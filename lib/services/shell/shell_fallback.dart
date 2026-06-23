import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, Process;
import '../vfs/vfs_service.dart';
import 'shell_state.dart';
import 'shell_result.dart';

class ShellFallback {
  final ShellState state;
  final VfsService _vfs = VfsService();

  ShellFallback(this.state);

  String get _vfsRoot => _vfs.rootPath;

  Future<ShellResult> runInShell(String command) async {
    final result = await _runShellCommand(
      command,
      workingDirectory: state.cwd,
      extraEnv: {
        ...state.env,
        'PWD': state.cwd,
        'OLDPWD': state.previousCwd,
      },
    );
    return ShellResult(
      exitCode: result.exitCode,
      stdout: result.stdout,
      stderr: result.stderr,
    );
  }

  String _resolveVfsPath(String vfsPath) {
    if (vfsPath.startsWith('/')) {
      return '$_vfsRoot$vfsPath';
    }
    return '$_vfsRoot/$vfsPath';
  }

  Future<_ProcessResult> _runShellCommand(
    String command, {
    String? workingDirectory,
    Duration timeout = const Duration(seconds: 30),
    Map<String, String>? extraEnv,
  }) async {
    final isAndroid = Platform.isAndroid;
    final workDir = workingDirectory != null
        ? _resolveVfsPath(workingDirectory)
        : _vfsRoot;

    final env = <String, String>{
      'HOME': _vfsRoot,
      'PATH': isAndroid
          ? '$_vfsRoot:/system/bin:/system/xbin'
          : '$_vfsRoot:/usr/bin:/usr/local/bin:/bin',
      'VFS_ROOT': _vfsRoot,
      ...?extraEnv,
    };

    try {
      final executable = isAndroid ? '/system/bin/sh' : '/bin/sh';
      final process = await Process.start(
        executable,
        ['-c', command],
        workingDirectory: workDir,
        environment: env,
      );

      await process.stdin.close();

      final stdoutBuf = StringBuffer();
      final stderrBuf = StringBuffer();
      var stdoutLen = 0;
      var stderrLen = 0;
      const maxOutput = 50 * 1024;

      await Future.wait([
        process.stdout.transform(utf8.decoder).forEach((chunk) {
          if (stdoutLen < maxOutput) {
            stdoutBuf.write(chunk);
            stdoutLen += chunk.length;
          }
        }),
        process.stderr.transform(utf8.decoder).forEach((chunk) {
          if (stderrLen < maxOutput) {
            stderrBuf.write(chunk);
            stderrLen += chunk.length;
          }
        }),
      ]);

      final exitCode =
          await process.exitCode.timeout(timeout, onTimeout: () {
        process.kill();
        return -1;
      });

      var stdout = stdoutBuf.toString();
      var stderr = stderrBuf.toString();

      if (stdoutLen >= maxOutput) stdout += '\n... (truncated)';
      if (stderrLen >= maxOutput) stderr += '\n... (truncated)';

      return _ProcessResult(
        exitCode: exitCode,
        stdout: stdout,
        stderr: stderr,
      );
    } on TimeoutException {
      return _ProcessResult(
        exitCode: -1,
        stdout: '',
        stderr: 'Execution timed out after ${timeout.inSeconds} seconds',
      );
    } catch (e) {
      return _ProcessResult(
        exitCode: -1,
        stdout: '',
        stderr: 'Failed to execute command: $e',
      );
    }
  }
}

class _ProcessResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  const _ProcessResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });
}
