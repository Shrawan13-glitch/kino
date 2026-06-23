import 'dart:async';
import 'package:path/path.dart' as p;
import '../vfs/vfs_service.dart';
import '../tool_execution.dart';
import 'shell_result.dart';
import 'shell_state.dart';
import 'shell_expand.dart';
import 'shell_arithmetic.dart';
import 'shell_fallback.dart';

/// Context provided to every builtin invocation.
class ShellContext {
  final ShellState state;
  final ShellExpander expander;
  final ShellArithmetic arithmetic;
  final ShellFallback fallback;
  final VfsService vfs;
  final ToolExecutionService toolExec;
  final BuiltinRegistry builtins;
  final Future<ShellResult> Function(String command) execute;

  ShellContext({
    required this.state,
    required this.expander,
    required this.arithmetic,
    required this.fallback,
    required this.vfs,
    required this.toolExec,
    required this.builtins,
    required this.execute,
  });

  String vfsAbsolute(String vfsPath) {
    final parts = vfsPath.split('/').where((s) => s.isNotEmpty).toList();
    final clean = parts.join('/');
    return p.join(vfs.rootPath, clean);
  }
}

typedef BuiltinFunction = Future<ShellResult> Function(
    ShellContext ctx, List<String> args);

/// Registry of all shell built-in commands.
class BuiltinRegistry {
  final Map<String, BuiltinFunction> _map = {};

  void register(String name, BuiltinFunction fn) {
    _map[name] = fn;
  }

  void registerAll(Map<String, BuiltinFunction> fns) {
    _map.addAll(fns);
  }

  BuiltinFunction? operator [](String name) => _map[name];

  bool containsKey(String name) => _map.containsKey(name);

  Set<String> get names => _map.keys.toSet();

  Future<ShellResult> call(String name, ShellContext ctx, List<String> args) {
    final fn = _map[name];
    if (fn == null) {
      return Future.value(
        ShellResult(exitCode: 1, stdout: '', stderr: 'builtin: $name: not found\n'),
      );
    }
    return fn(ctx, args);
  }
}
