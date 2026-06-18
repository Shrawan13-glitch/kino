import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'vfs/vfs_service.dart';

class ToolResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  const ToolResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  bool get success => exitCode == 0;
  String get combined => stdout.trim().isEmpty ? stderr.trim() : stdout.trim();

  String get full {
    final parts = <String>[];
    if (stdout.trim().isNotEmpty) parts.add('STDOUT:\n$stdout');
    if (stderr.trim().isNotEmpty) parts.add('STDERR:\n$stderr');
    parts.add('Exit code: $exitCode');
    return parts.join('\n\n');
  }
}

class ToolExecutionService {
  ToolExecutionService._();
  static final ToolExecutionService _instance = ToolExecutionService._();
  factory ToolExecutionService() => _instance;

  static const _maxOutputSize = 50 * 1024;

  String get _vfsRoot => VfsService().rootPath;

  String _resolvePath(String tool) {
    if (tool.startsWith('/')) {
      return '$_vfsRoot$tool';
    }
    return '$_vfsRoot/tools/$tool';
  }

  String _resolveVfsPath(String vfsPath) {
    if (vfsPath.startsWith('/')) {
      return '$_vfsRoot$vfsPath';
    }
    return '$_vfsRoot/home/$vfsPath';
  }

  Future<ToolResult> runTool(
    String tool,
    List<String> args, {
    String? stdin,
    String? workingDirectory,
    Duration timeout = const Duration(seconds: 30),
    Map<String, String>? extraEnv,
  }) async {
    final toolPath = _resolvePath(tool);
    final toolFile = File(toolPath);

    if (!await toolFile.exists()) {
      return ToolResult(
        exitCode: -1,
        stdout: '',
        stderr: 'Tool not found: $tool (looked at $toolPath)\n'
            'Available tools can be listed with list_dir(path: "/tools")',
      );
    }

    final workDir = workingDirectory != null
        ? _resolveVfsPath(workingDirectory)
        : '$_vfsRoot/home';

    final env = <String, String>{
      'HOME': '$_vfsRoot/home',
      'PATH': '$_vfsRoot/tools',
      'VFS_ROOT': _vfsRoot,
      ...?extraEnv,
    };

    try {
      final process = await Process.start(
        toolPath,
        args,
        workingDirectory: workDir,
        environment: env,
      );

      if (stdin != null && stdin.isNotEmpty) {
        process.stdin.write(stdin);
        await process.stdin.close();
      } else {
        await process.stdin.close();
      }

      final stdoutBuf = StringBuffer();
      final stderrBuf = StringBuffer();
      var stdoutLen = 0;
      var stderrLen = 0;

      await Future.wait([
        process.stdout
            .transform(utf8.decoder)
            .forEach((chunk) {
              if (stdoutLen < _maxOutputSize) {
                stdoutBuf.write(chunk);
                stdoutLen += chunk.length;
              }
            }),
        process.stderr
            .transform(utf8.decoder)
            .forEach((chunk) {
              if (stderrLen < _maxOutputSize) {
                stderrBuf.write(chunk);
                stderrLen += chunk.length;
              }
            }),
      ]);

      final exitCode = await process.exitCode.timeout(timeout, onTimeout: () {
        process.kill();
        return -1;
      });

      var stdout = stdoutBuf.toString();
      var stderr = stderrBuf.toString();

      if (stdoutLen >= _maxOutputSize) stdout += '\n... (truncated)';
      if (stderrLen >= _maxOutputSize) stderr += '\n... (truncated)';

      return ToolResult(
        exitCode: exitCode,
        stdout: stdout,
        stderr: stderr,
      );
    } on TimeoutException {
      return ToolResult(
        exitCode: -1,
        stdout: '',
        stderr: 'Execution timed out after ${timeout.inSeconds} seconds',
      );
    } catch (e) {
      return ToolResult(
        exitCode: -1,
        stdout: '',
        stderr: 'Failed to execute tool: $e',
      );
    }
  }

  Future<String> writeFile(String vfsPath, String content) async {
    try {
      final abs = _resolveVfsPath(vfsPath);
      final file = File(abs);
      await file.parent.create(recursive: true);
      await file.writeAsString(content);
      return 'Successfully wrote ${content.length} bytes to $vfsPath';
    } catch (e) {
      return 'Error writing file: $e';
    }
  }

  Future<String> readFile(String vfsPath) async {
    try {
      final abs = _resolveVfsPath(vfsPath);
      final file = File(abs);
      if (!await file.exists()) return 'File not found: $vfsPath';
      final content = await file.readAsString();
      if (content.length > _maxOutputSize) {
        return '${content.substring(0, _maxOutputSize)}\n... (truncated, ${content.length} total bytes)';
      }
      return content;
    } catch (e) {
      return 'Error reading file: $e';
    }
  }

  Future<String> listDirectory(String vfsPath) async {
    try {
      final abs = _resolveVfsPath(vfsPath);
      final dir = Directory(abs);
      if (!await dir.exists()) return 'Directory not found: $vfsPath';

      final entities = await dir.list().toList();
      if (entities.isEmpty) return '(empty)';

      final lines = <String>[];
      for (final e in entities) {
        final name = p.basename(e.path);
        if (name.startsWith('.')) continue;
        final isDir = e is Directory;
        final stat = await e.stat();
        final size = isDir ? '' : ' (${_formatSize(stat.size)})';
        lines.add('${isDir ? '[DIR]' : '[FILE]'}  $name$size');
      }

      return lines.join('\n');
    } catch (e) {
      return 'Error listing directory: $e';
    }
  }

  Future<String> deleteFile(String vfsPath) async {
    try {
      final abs = _resolveVfsPath(vfsPath);
      final entity = FileSystemEntity.typeSync(abs);
      if (entity == FileSystemEntityType.notFound) {
        return 'Not found: $vfsPath';
      }
      if (entity == FileSystemEntityType.directory) {
        await Directory(abs).delete(recursive: true);
      } else {
        await File(abs).delete();
      }
      return 'Deleted: $vfsPath';
    } catch (e) {
      return 'Error deleting: $e';
    }
  }

  Future<String> createDirectory(String vfsPath) async {
    try {
      final abs = _resolveVfsPath(vfsPath);
      await Directory(abs).create(recursive: true);
      return 'Created directory: $vfsPath';
    } catch (e) {
      return 'Error creating directory: $e';
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
