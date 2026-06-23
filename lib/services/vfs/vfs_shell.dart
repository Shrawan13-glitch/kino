import 'dart:async';
import 'vfs_service.dart';
import '../tool_execution.dart';
import '../shell/shell_engine.dart';
import '../shell/shell_result.dart';
import '../shell/shell_state.dart';
import '../shell/builtins/fs.dart';
import '../shell/builtins/text.dart';
import '../shell/builtins/shell_ctrl.dart';
import '../shell/builtins/test.dart';
import '../shell/builtins/jobs.dart';
import '../shell/builtins/declare.dart';
import '../shell/builtins/data.dart';
import '../shell/builtins/misc.dart';
import '../shell/builtins/network.dart';

/// Virtual filesystem shell — singleton.
///
/// Delegates all execution to [ShellEngine] and related shell modules.
class VfsShell {
  VfsShell._() {
    _init();
  }

  static final VfsShell _instance = VfsShell._();
  factory VfsShell() => _instance;

  late final ShellEngine _engine;
  late final ShellState _state;

  void _init() {
    _state = ShellState();
    _engine = ShellEngine(
      state: _state,
      vfs: VfsService(),
      toolExec: ToolExecutionService(),
    );

    // Register ALL builtins
    _engine.builtins.registerAll(fsBuiltins());
    _engine.builtins.registerAll(textBuiltins());
    _engine.builtins.registerAll(shellCtrlBuiltins());
    _engine.builtins.registerAll(testBuiltins());
    _engine.builtins.registerAll(jobsBuiltins());
    _engine.builtins.registerAll(declareBuiltins());
    _engine.builtins.registerAll(dataBuiltins());
    _engine.builtins.registerAll(miscBuiltins());
    _engine.builtins.registerAll(networkBuiltins());
  }

  // ===========================================================================
  // Public API
  // ===========================================================================

  String get cwd => _state.cwd;
  int get lastExitCode => _state.lastExitCode;

  void setEnv(String name, String value) {
    _state.env[name] = value;
  }

  String? getEnv(String name) => _state.env[name];

  Future<ShellResult> execute(String command) async {
    // Expand PS1 prompt escapes if this looks like a prompt display
    if (_state.env.containsKey('PS1') && command.isEmpty) {
      return ShellResult(
        exitCode: 0,
        stdout: _state.expandPrompt(_state.env['PS1']!),
        stderr: '',
      );
    }
    return _engine.execute(command);
  }
}
