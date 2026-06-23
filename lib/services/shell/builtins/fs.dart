import 'dart:io';
import 'package:path/path.dart' as p;
import '../../vfs/vfs_exception.dart';
import '../shell_builtin.dart';
import '../shell_result.dart';

Map<String, BuiltinFunction> fsBuiltins() => {
      'ls': _cmdLs,
      'cat': _cmdCat,
      'mkdir': _cmdMkdir,
      'rm': _cmdRm,
      'cp': _cmdCp,
      'mv': _cmdMv,
      'touch': _cmdTouch,
      'head': _cmdHead,
      'tail': _cmdTail,
    };

// =============================================================================
// ls
// =============================================================================

Future<ShellResult> _cmdLs(ShellContext ctx, List<String> args) async {
  var showAll = false;
  var longFormat = false;
  var dirs = <String>[];

  for (final arg in args) {
    if (arg == '-la' || arg == '-al') {
      showAll = true;
      longFormat = true;
    } else if (arg == '-l') {
      longFormat = true;
    } else if (arg == '-a') {
      showAll = true;
    } else if (arg.startsWith('-')) {
      return ShellResult(
        exitCode: 1, stdout: '', stderr: 'ls: invalid option: $arg',
      );
    } else {
      dirs.add(arg);
    }
  }

  if (dirs.isEmpty) dirs.add(ctx.state.cwd);

  final output = StringBuffer();
  for (var di = 0; di < dirs.length; di++) {
    final target = ctx.expander.resolvePath(dirs[di]);
    final abs = ctx.vfsAbsolute(target);
    final type = FileSystemEntity.typeSync(abs);

    if (type == FileSystemEntityType.notFound) {
      output.writeln('ls: ${dirs[di]}: No such file or directory');
      continue;
    }

    if (type == FileSystemEntityType.directory) {
      if (dirs.length > 1) output.writeln('${di > 0 ? '\n' : ''}${dirs[di]}:');
      try {
        var entities = Directory(abs).listSync();
        if (!showAll) {
          entities.removeWhere((e) => p.basename(e.path).startsWith('.'));
        }
        if (entities.isEmpty) continue;

        if (longFormat) {
          for (final e in entities) {
            final name = p.basename(e.path);
            final stat = e.statSync();
            output.writeln(
                '${_permissions(e)} ${_formatSize(stat.size)} ${_formatTime(stat.modified)} $name');
          }
        } else {
          const maxCol = 80;
          var line = '';
          for (final e in entities) {
            final name = p.basename(e.path);
            final display = e is Directory ? '$name/' : name;
            if (line.length + display.length + 1 > maxCol) {
              output.writeln(line);
              line = display;
            } else {
              line += line.isEmpty ? display : '  $display';
            }
          }
          if (line.isNotEmpty) output.writeln(line);
        }
      } catch (e) {
        output.writeln('ls: reading ${dirs[di]}: $e');
      }
    } else {
      final stat = File(abs).statSync();
      if (longFormat) {
        output.writeln(
            '${_permissions(File(abs))} ${_formatSize(stat.size)} ${_formatTime(stat.modified)} ${p.basename(abs)}');
      } else {
        output.writeln(p.basename(abs));
      }
    }
  }

  return ShellResult(exitCode: 0, stdout: output.toString(), stderr: '');
}

// =============================================================================
// cat
// =============================================================================

Future<ShellResult> _cmdCat(ShellContext ctx, List<String> args) async {
  if (args.isEmpty) {
    return const ShellResult(exitCode: 0, stdout: '', stderr: '');
  }

  final output = StringBuffer();
  for (final arg in args) {
    final target = ctx.expander.resolvePath(arg);
    try {
      final content = await ctx.vfs.readFileAsString(target);
      output.write(content);
      if (!content.endsWith('\n')) output.writeln();
    } on VfsNotFoundException {
      output.writeln('cat: $arg: No such file');
    } catch (e) {
      output.writeln('cat: $arg: $e');
    }
  }

  return ShellResult(exitCode: 0, stdout: output.toString(), stderr: '');
}

// =============================================================================
// mkdir
// =============================================================================

Future<ShellResult> _cmdMkdir(ShellContext ctx, List<String> args) async {
  var parents = false;
  var dirs = <String>[];

  for (final arg in args) {
    if (arg == '-p') {
      parents = true;
    } else if (arg.startsWith('-')) {
      return ShellResult(
        exitCode: 1, stdout: '', stderr: 'mkdir: invalid option: $arg',
      );
    } else {
      dirs.add(arg);
    }
  }

  if (dirs.isEmpty) {
    return const ShellResult(
      exitCode: 1, stdout: '', stderr: 'mkdir: missing operand',
    );
  }

  final output = StringBuffer();
  for (final dir in dirs) {
    final target = ctx.expander.resolvePath(dir);
    try {
      if (parents) {
        await Directory(ctx.vfsAbsolute(target)).create(recursive: true);
      } else {
        await ctx.vfs.createDirectory(target);
      }
    } on VfsAlreadyExistsException {
      output.writeln('mkdir: $dir: File exists');
    } catch (e) {
      output.writeln('mkdir: $dir: $e');
    }
  }

  return ShellResult(exitCode: 0, stdout: output.toString(), stderr: '');
}

// =============================================================================
// rm
// =============================================================================

Future<ShellResult> _cmdRm(ShellContext ctx, List<String> args) async {
  var recursive = false;
  var force = false;
  var targets = <String>[];

  for (final arg in args) {
    if (arg == '-rf' || arg == '-fr') {
      recursive = true;
      force = true;
    } else if (arg == '-r' || arg == '-R') {
      recursive = true;
    } else if (arg == '-f') {
      force = true;
    } else if (arg.startsWith('-')) {
      return ShellResult(
        exitCode: 1, stdout: '', stderr: 'rm: invalid option: $arg',
      );
    } else {
      targets.add(arg);
    }
  }

  if (targets.isEmpty) {
    return const ShellResult(
      exitCode: 1, stdout: '', stderr: 'rm: missing operand',
    );
  }

  final output = StringBuffer();
  for (final target in targets) {
    final resolved = ctx.expander.resolvePath(target);
    try {
      final abs = ctx.vfsAbsolute(resolved);
      final type = FileSystemEntity.typeSync(abs);
      if (type == FileSystemEntityType.notFound) {
        if (!force) output.writeln('rm: $target: No such file');
        continue;
      }
      if (type == FileSystemEntityType.directory && !recursive) {
        output.writeln('rm: $target: is a directory');
        continue;
      }
      await ctx.vfs.delete(resolved);
    } catch (e) {
      if (!force) output.writeln('rm: $target: $e');
    }
  }

  return ShellResult(exitCode: 0, stdout: output.toString(), stderr: '');
}

// =============================================================================
// cp
// =============================================================================

Future<ShellResult> _cmdCp(ShellContext ctx, List<String> args) async {
  if (args.length < 2) {
    return const ShellResult(
      exitCode: 1, stdout: '', stderr: 'cp: missing file operand',
    );
  }

  final src = ctx.expander.resolvePath(args[0]);
  final dest = ctx.expander.resolvePath(args[1]);

  try {
    await ctx.vfs.copy(src, dest);
    return const ShellResult(exitCode: 0, stdout: '', stderr: '');
  } on VfsNotFoundException {
    return ShellResult(
      exitCode: 1, stdout: '',
      stderr: 'cp: ${args[0]}: No such file or directory',
    );
  } catch (e) {
    return ShellResult(exitCode: 1, stdout: '', stderr: 'cp: $e');
  }
}

// =============================================================================
// mv
// =============================================================================

Future<ShellResult> _cmdMv(ShellContext ctx, List<String> args) async {
  if (args.length < 2) {
    return const ShellResult(
      exitCode: 1, stdout: '', stderr: 'mv: missing file operand',
    );
  }

  final src = ctx.expander.resolvePath(args[0]);
  final dest = ctx.expander.resolvePath(args[1]);

  try {
    await ctx.vfs.move(src, dest);
    return const ShellResult(exitCode: 0, stdout: '', stderr: '');
  } on VfsNotFoundException {
    return ShellResult(
      exitCode: 1, stdout: '',
      stderr: 'mv: ${args[0]}: No such file or directory',
    );
  } catch (e) {
    return ShellResult(exitCode: 1, stdout: '', stderr: 'mv: $e');
  }
}

// =============================================================================
// touch
// =============================================================================

Future<ShellResult> _cmdTouch(ShellContext ctx, List<String> args) async {
  if (args.isEmpty) {
    return const ShellResult(
      exitCode: 1, stdout: '', stderr: 'touch: missing file operand',
    );
  }

  for (final arg in args) {
    final target = ctx.expander.resolvePath(arg);
    final file = File(ctx.vfsAbsolute(target));
    if (await file.exists()) {
      await file.setLastModified(DateTime.now());
    } else {
      await file.create(recursive: true);
    }
  }

  return const ShellResult(exitCode: 0, stdout: '', stderr: '');
}

// =============================================================================
// head
// =============================================================================

Future<ShellResult> _cmdHead(ShellContext ctx, List<String> args) async {
  var n = 10;
  var files = <String>[];
  var i = 0;

  while (i < args.length) {
    if (args[i] == '-n' && i + 1 < args.length) {
      n = int.tryParse(args[i + 1]) ?? 10;
      i += 2;
    } else if (args[i].startsWith('-') &&
        RegExp(r'^-\d+$').hasMatch(args[i])) {
      n = int.parse(args[i].substring(1));
      i++;
    } else if (args[i].startsWith('-')) {
      return ShellResult(
        exitCode: 1, stdout: '', stderr: 'head: invalid option: ${args[i]}',
      );
    } else {
      files.add(args[i]);
      i++;
    }
  }

  if (files.isEmpty) {
    return const ShellResult(exitCode: 0, stdout: '', stderr: '');
  }

  final output = StringBuffer();
  for (var fi = 0; fi < files.length; fi++) {
    final target = ctx.expander.resolvePath(files[fi]);
    if (files.length > 1) output.writeln('==> ${files[fi]} <==');
    try {
      final content = await ctx.vfs.readFileAsString(target);
      final lines = content.split('\n');
      for (var j = 0; j < n && j < lines.length; j++) {
        output.writeln(lines[j]);
      }
    } on VfsNotFoundException {
      output.writeln('head: ${files[fi]}: No such file');
    } catch (e) {
      output.writeln('head: ${files[fi]}: $e');
    }
    if (fi < files.length - 1) output.writeln();
  }

  return ShellResult(exitCode: 0, stdout: output.toString(), stderr: '');
}

// =============================================================================
// tail
// =============================================================================

Future<ShellResult> _cmdTail(ShellContext ctx, List<String> args) async {
  var n = 10;
  var files = <String>[];
  var i = 0;

  while (i < args.length) {
    if (args[i] == '-n' && i + 1 < args.length) {
      n = int.tryParse(args[i + 1]) ?? 10;
      i += 2;
    } else if (args[i].startsWith('-') &&
        RegExp(r'^-\d+$').hasMatch(args[i])) {
      n = int.parse(args[i].substring(1));
      i++;
    } else if (args[i].startsWith('-')) {
      return ShellResult(
        exitCode: 1, stdout: '', stderr: 'tail: invalid option: ${args[i]}',
      );
    } else {
      files.add(args[i]);
      i++;
    }
  }

  if (files.isEmpty) {
    return const ShellResult(exitCode: 0, stdout: '', stderr: '');
  }

  final output = StringBuffer();
  for (var fi = 0; fi < files.length; fi++) {
    final target = ctx.expander.resolvePath(files[fi]);
    if (files.length > 1) output.writeln('==> ${files[fi]} <==');
    try {
      final content = await ctx.vfs.readFileAsString(target);
      final lines = content.split('\n');
      final start = lines.length > n ? lines.length - n : 0;
      for (var j = start; j < lines.length; j++) {
        output.writeln(lines[j]);
      }
    } on VfsNotFoundException {
      output.writeln('tail: ${files[fi]}: No such file');
    } catch (e) {
      output.writeln('tail: ${files[fi]}: $e');
    }
    if (fi < files.length - 1) output.writeln();
  }

  return ShellResult(exitCode: 0, stdout: output.toString(), stderr: '');
}

// =============================================================================
// Utilities
// =============================================================================

String _permissions(FileSystemEntity entity) {
  final stat = entity.statSync();
  final buf = StringBuffer();
  buf.write(entity is Directory ? 'd' : '-');
  buf.write(stat.mode & 0x100 != 0 ? 'r' : '-');
  buf.write(stat.mode & 0x80 != 0 ? 'w' : '-');
  buf.write(stat.mode & 0x40 != 0 ? 'x' : '-');
  buf.write(stat.mode & 0x20 != 0 ? 'r' : '-');
  buf.write(stat.mode & 0x10 != 0 ? 'w' : '-');
  buf.write(stat.mode & 0x8 != 0 ? 'x' : '-');
  buf.write(stat.mode & 0x4 != 0 ? 'r' : '-');
  buf.write(stat.mode & 0x2 != 0 ? 'w' : '-');
  buf.write(stat.mode & 0x1 != 0 ? 'x' : '-');
  return buf.toString();
}

String _formatSize(int bytes) {
  if (bytes < 1024) return '$bytes';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)}K';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}M';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}G';
}

String _formatTime(DateTime dt) {
  final now = DateTime.now();
  if (dt.year == now.year) {
    return '${_abbrMonth(dt.month)} ${dt.day.toString().padLeft(2, ' ')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
  return '${_abbrMonth(dt.month)} ${dt.day.toString().padLeft(2, ' ')}  ${dt.year}';
}

String _abbrMonth(int m) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return months[m - 1];
}
