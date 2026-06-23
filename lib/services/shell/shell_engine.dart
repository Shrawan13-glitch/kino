import 'dart:async';
import 'dart:io' show File;
import '../vfs/vfs_parser.dart';
import '../vfs/vfs_service.dart';
import '../tool_execution.dart';
import 'ast/ast_interpreter.dart';
import 'shell_arithmetic.dart';
import 'shell_builtin.dart';
import 'shell_expand.dart';
import 'shell_fallback.dart';
import 'shell_result.dart';
import 'shell_state.dart';

enum _CompoundOp { and, or, semicolon }

class _CompoundSegment {
  final String command;
  final _CompoundOp? separator;
  _CompoundSegment(this.command, [this.separator]);
}

enum RedirectKind { output, error, outputBoth, fdMerge }

class RedirectInfo {
  final int srcFd;
  final RedirectKind kind;
  final String target;
  final int? dstFd;
  final bool isAppend;

  RedirectInfo({
    required this.srcFd,
    required this.kind,
    required this.target,
    this.dstFd,
    this.isAppend = false,
  });
}

class ParsedRedirects {
  final String cmd;
  final List<RedirectInfo> redirects;
  ParsedRedirects(this.cmd, this.redirects);
}

class ShellEngine {
  final ShellState state;
  late final ShellExpander expander;
  late final ShellArithmetic arithmetic;
  late final ShellFallback fallback;
  late final BuiltinRegistry builtins;
  final VfsService vfs;
  final ToolExecutionService toolExec;

  late final ShellContext _context;
  late final AstInterpreter _interpreter;

  ShellEngine({
    required this.state,
    required this.vfs,
    required this.toolExec,
  }) {
    expander = ShellExpander(state);
    arithmetic = ShellArithmetic(state);
    fallback = ShellFallback(state);
    builtins = BuiltinRegistry();
    _context = ShellContext(
      state: state,
      expander: expander,
      arithmetic: arithmetic,
      fallback: fallback,
      vfs: vfs,
      toolExec: toolExec,
      builtins: builtins,
      execute: _executeString,
    );
    _interpreter = AstInterpreter(
      ctx: _context,
      executeWords: _executeWords,
      executeString: _executeString,
    );
  }

  Future<ShellResult> execute(String command) async {
    final trimmed = command.trim();
    if (trimmed.isEmpty) {
      return ShellResult.ok;
    }

    state.history.add(trimmed);
    if (state.history.length > ShellState.historyMax) {
      state.history.removeRange(
        0, state.history.length - ShellState.historyMax,
      );
    }
    state.underscore =
        trimmed.split(RegExp(r'\s+')).lastOrNull ?? '';

    try {
      if (_containsControlFlow(trimmed)) {
        String input = expander.expandAliases(trimmed);
        try {
          final parser = ShellParser.tryParse(input);
          if (parser != null) {
            final ast = parser.parse();
            final result = await _interpreter.interpret(ast);
            state.lastExitCode = result.exitCode;
            state.pipeStatusString = state.lastExitCode.toString();
            if (state.exitRequested) state.exitRequested = false;
            return result;
          }
        } catch (_) {}

        final result = await fallback.runInShell(input);
        state.lastExitCode = result.exitCode;
        state.pipeStatusString = state.lastExitCode.toString();
        return result;
      }

      String input = expander.expandAliases(trimmed);
      final segments = _splitCompound(input);
      final result = await _executeChain(segments);
      state.pipeStatusString = state.lastExitCode.toString();
      if (state.lastError.isNotEmpty) {
        return ShellResult(
          exitCode: result.exitCode,
          stdout: result.stdout,
          stderr: result.stderr.contains(state.lastError)
              ? result.stderr
              : '${result.stderr}${state.lastError}\n',
        );
      }
      return result;
    } catch (e) {
      return ShellResult(
        exitCode: -1,
        stdout: '',
        stderr: 'Shell error: $e',
      );
    }
  }

  Future<ShellResult> _executeString(String command) async {
    return execute(command);
  }

  Future<ShellResult> _executeWords(List<String> words) async {
    if (words.isEmpty) return ShellResult.ok;
    final cmd = words[0];
    final args = words.sublist(1);

    if (builtins.containsKey(cmd)) {
      state.underscore = args.isNotEmpty ? args.last : cmd;
      return builtins.call(cmd, _context, args);
    }

    if (state.functions.containsKey(cmd)) {
      final ast = state.functions[cmd]!;
      final savedParams = List<String>.from(state.positionalParams);
      state.positionalParams = args;
      state.env['@'] = args.join(' ');
      state.env['#'] = state.positionalParams.length.toString();
      final funcResult = await _interpreter.interpret(ast);
      state.returnFromFunction = false;
      state.positionalParams = savedParams;
      state.env['@'] = savedParams.join(' ');
      state.env['#'] = savedParams.length.toString();
      return funcResult;
    }

    return fallback.runInShell(words.join(' '));
  }

  Future<ShellResult> _executeChain(List<_CompoundSegment> segments) async {
    var skip = false;
    var lastResult = ShellResult.ok;

    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i];
      final cmd = seg.command.trim();
      if (cmd.isEmpty) continue;

      if (i > 0 && seg.separator != null) {
        switch (seg.separator!) {
          case _CompoundOp.and:
            if (!lastResult.success) { skip = true; continue; }
            skip = false;
          case _CompoundOp.or:
            if (lastResult.success) { skip = true; continue; }
            skip = false;
          case _CompoundOp.semicolon:
            skip = false;
        }
      }

      if (skip) {
        if (segments.length > i + 1 &&
            segments[i + 1].separator == _CompoundOp.semicolon) {
          skip = false;
        }
        continue;
      }

      lastResult = await _executeSegment(cmd);
      if (state.exitRequested) break;
    }

    state.lastExitCode = lastResult.exitCode;
    return lastResult;
  }

  Future<ShellResult> _executeSegment(String cmd) async {
    if (_isCdCommand(cmd)) {
      return _handleCd(cmd);
    }

    if (_needsRealShell(cmd)) {
      return fallback.runInShell(cmd);
    }

    final parser = ShellParser.tryParse(cmd);
    if (parser != null) {
      try {
        final ast = parser.parse();
        return await _interpreter.interpret(ast);
      } catch (_) {}
    }

    final firstWord = _extractFirstWord(cmd);
    if (firstWord == null) {
      return ShellResult.ok;
    }

    if (builtins.containsKey(firstWord)) {
      return _executeBuiltin(cmd);
    }

    if (state.functions.containsKey(firstWord)) {
      return _executeFunction(cmd, firstWord);
    }

    return fallback.runInShell(cmd);
  }

  Future<ShellResult> _executeBuiltin(String cmd) async {
    final rawTokens = _tokenize(cmd);
    if (rawTokens.isEmpty) {
      return ShellResult.ok;
    }

    final expanded = <String>[];
    for (var i = 1; i < rawTokens.length; i++) {
      final token = rawTokens[i];
      for (final braced in expander.expandBraces(token)) {
        var t = braced;
        t = expander.expandVars(t);
        t = expander.expandTilde(t);
        final globbed = expander.expandGlob(t);
        expanded.addAll(globbed);
      }
    }

    final cmdName = rawTokens[0];
    // Retokenize the original cmd to find redirects
    final parsedRedirects = _parseRedirects(cmd, rawTokens);
    if (parsedRedirects != null) {
      return _executeWithRedirects(cmdName, expanded, parsedRedirects);
    }

    state.underscore = expanded.isNotEmpty ? expanded.last : cmdName;
    return builtins.call(cmdName, _context, expanded);
  }

  Future<ShellResult> _executeWithRedirects(
    String cmdName,
    List<String> args,
    ParsedRedirects parsed,
  ) async {
    final baseResult = await builtins.call(cmdName, _context, args);

    var stdout = baseResult.stdout;
    var stderr = baseResult.stderr;

    for (final r in parsed.redirects) {
      if (r.kind == RedirectKind.fdMerge) {
        if (r.srcFd == 2 && r.dstFd == 1) {
          stdout = '$stdout\n$stderr';
          stderr = '';
        } else if (r.srcFd == 1 && r.dstFd == 2) {
          stderr = '$stdout\n$stderr';
          stdout = '';
        }
        continue;
      }

      final target = expander.resolvePath(r.target);
      final abs = _context.vfsAbsolute(target);

      if (r.kind == RedirectKind.outputBoth) {
        final content = '${stdout.trim()}\n${stderr.trim()}'.trim();
        if (r.isAppend) {
          await vfs.writeFile(target, '${_existingContent(abs)}\n$content');
        } else {
          await vfs.writeFile(target, content);
        }
        stdout = '';
        stderr = '';
      } else if (r.kind == RedirectKind.output) {
        if (r.isAppend) {
          await vfs.writeFile(
            target, '${_existingContent(abs)}\n$stdout',
          );
        } else {
          await vfs.writeFile(target, stdout);
        }
        stdout = '';
      } else if (r.kind == RedirectKind.error) {
        if (r.isAppend) {
          await vfs.writeFile(
            target, '${_existingContent(abs)}\n$stderr',
          );
        } else {
          await vfs.writeFile(target, stderr);
        }
        stderr = '';
      }
    }

    return ShellResult(
      exitCode: baseResult.exitCode,
      stdout: stdout,
      stderr: stderr,
    );
  }

  Future<ShellResult> _executeFunction(String cmd, String name) async {
    final rawTokens = _tokenize(cmd);
    final args = rawTokens.length > 1 ? rawTokens.sublist(1) : <String>[];
    final ast = state.functions[name]!;

    final expanded = <String>[];
    for (final arg in args) {
      for (final braced in expander.expandBraces(arg)) {
        var t = braced;
        t = expander.expandVars(t);
        t = expander.expandTilde(t);
        final globbed = expander.expandGlob(t);
        expanded.addAll(globbed);
      }
    }

    final savedParams = List<String>.from(state.positionalParams);
    state.positionalParams = expanded;
    state.env['@'] = expanded.join(' ');
    state.env['#'] = state.positionalParams.length.toString();

    final funcResult = await _interpreter.interpret(ast);
    state.returnFromFunction = false;

    state.positionalParams = savedParams;
    state.env['@'] = savedParams.join(' ');
    state.env['#'] = savedParams.length.toString();

    state.underscore = expanded.isNotEmpty ? expanded.last : name;
    return funcResult;
  }

  // ===========================================================================
  // CD HANDLING
  // ===========================================================================

  Future<ShellResult> _handleCd(String cmd) async {
    final rest = cmd.substring(2).trimLeft();
    final dirEnd = _findOperandEnd(rest);
    String? dir;
    String? trailing;

    if (dirEnd > 0) {
      dir = rest.substring(0, dirEnd).trim();
      trailing = rest.substring(dirEnd).trim();
    } else {
      dir = rest.trim();
      trailing = '';
    }

    if (dir.isEmpty) {
      dir = state.env['HOME'] ?? '/';
    }

    if (dir == '-') {
      final tmp = state.previousCwd;
      state.previousCwd = state.cwd;
      state.cwd = tmp;
      state.env['PWD'] = state.cwd;
      state.env['OLDPWD'] = state.previousCwd;
      return ShellResult(exitCode: 0, stdout: '$state.cwd\n', stderr: '');
    }

    var target = dir;
    if (state.shopt['cdable_vars'] == true && state.env.containsKey(dir)) {
      target = state.env[dir]!;
    }

    if (target == '~') {
      target = state.env['HOME'] ?? '/';
    } else if (target.startsWith('~/')) {
      target = '${state.env['HOME'] ?? '/'}${target.substring(1)}';
    }

    final resolved = expander.resolvePath(target);
    state.previousCwd = state.cwd;
    state.cwd = resolved;
    state.env['PWD'] = state.cwd;
    state.env['OLDPWD'] = state.previousCwd;

    if (trailing.isNotEmpty) {
      return execute(trailing);
    }
    return ShellResult.ok;
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  bool _containsControlFlow(String cmd) {
    final trimmed = cmd.trimLeft();
    if (trimmed.startsWith('if ') || trimmed.startsWith('if\t') ||
        trimmed.startsWith('for ') || trimmed.startsWith('for\t') ||
        trimmed.startsWith('while ') || trimmed.startsWith('while\t') ||
        trimmed.startsWith('until ') || trimmed.startsWith('until\t') ||
        trimmed.startsWith('case ') || trimmed.startsWith('case\t') ||
        trimmed.startsWith('function ') || trimmed.startsWith('function\t') ||
        trimmed.startsWith('{') ||
        trimmed.startsWith('((') ||
        trimmed.startsWith('[[ ') || trimmed.startsWith('[[') ||
        cmd.contains('function ')) {
      return true;
    }
    if (RegExp(
      r'\b(if|for|while|until|case|function|then|else|elif|fi|do|done|esac|select)\b',
    ).hasMatch(cmd)) {
      return true;
    }
    return false;
  }

  bool _isCdCommand(String cmd) {
    final trimmed = cmd.trimLeft();
    return trimmed.startsWith('cd ') || trimmed == 'cd';
  }

  bool _needsRealShell(String cmd) {
    final trimmed = cmd.trimLeft();
    return trimmed.startsWith('time ') || trimmed.startsWith('eval ');
  }

  String? _extractFirstWord(String cmd) {
    final trimmed = cmd.trimLeft();
    if (trimmed.isEmpty) return null;
    final result = StringBuffer();
    var inSingle = false;
    var inDouble = false;
    for (var i = 0; i < trimmed.length; i++) {
      final c = trimmed[i];
      if (inSingle) {
        if (c == '\'') inSingle = false;
        continue;
      }
      if (inDouble) {
        if (c == '"') inDouble = false;
        if (c == '\\') i++;
        continue;
      }
      if (c == '\'') { inSingle = true; continue; }
      if (c == '"') { inDouble = true; continue; }
      if (c == '\\') { i++; continue; }
      if (c == ' ' || c == '\t') break;
      result.write(c);
    }
    return result.isEmpty ? null : result.toString();
  }

  List<String> _tokenize(String cmd) {
    final tokens = <String>[];
    final current = StringBuffer();
    var inSingle = false;
    var inDouble = false;

    for (var i = 0; i < cmd.length; i++) {
      final c = cmd[i];
      if (inSingle) {
        if (c == '\'') { inSingle = false; } else { current.write(c); }
        continue;
      }
      if (inDouble) {
        if (c == '"') { inDouble = false; } else if (c == '\\') {
          i++; if (i < cmd.length) current.write(cmd[i]);
        } else { current.write(c); }
        continue;
      }
      if (c == '\'') { inSingle = true; continue; }
      if (c == '"') { inDouble = true; continue; }
      if (c == '\\') { i++; if (i < cmd.length) current.write(cmd[i]); continue; }

      if (c == ' ' || c == '\t') {
        if (current.isNotEmpty) { tokens.add(current.toString()); current.clear(); }
      } else if (c == '>' || c == '<' || c == '&') {
        if (current.isNotEmpty) { tokens.add(current.toString()); current.clear(); }
        // Skip redirect operators
        if (c == '>' && i + 1 < cmd.length && cmd[i + 1] == '>') { i++; }
        else if (c == '<' && i + 1 < cmd.length && cmd[i + 1] == '<') {
          i++;
          if (i + 1 < cmd.length && cmd[i + 1] == '<') i++;
        } else if (c == '&' && i + 1 < cmd.length && cmd[i + 1] == '>') { i++; }
        else if (c == '>' && i + 1 < cmd.length && cmd[i + 1] == '&') { i++; }
      } else {
        current.write(c);
      }
    }

    if (current.isNotEmpty) tokens.add(current.toString());
    return tokens;
  }

  int _findOperandEnd(String s) {
    var depth = 0;
    var inSingle = false;
    var inDouble = false;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (inSingle) {
        if (c == '\'') inSingle = false;
        continue;
      }
      if (inDouble) {
        if (c == '"') inDouble = false;
        if (c == '\\') i++;
        continue;
      }
      if (c == '\'') { inSingle = true; continue; }
      if (c == '"') { inDouble = true; continue; }
      if (c == '\\') { i++; continue; }
      if (c == '(' || c == '{') { depth++; continue; }
      if (c == ')' || c == '}') { depth--; continue; }
      if (depth > 0) continue;
      if (c == ';' || c == '|' || c == '&' || c == '>') return i;
    }
    return -1;
  }

  List<_CompoundSegment> _splitCompound(String cmd) {
    final segments = <_CompoundSegment>[];
    var start = 0;
    var depth = 0;
    var inSingle = false;
    var inDouble = false;

    void flush(int end, [_CompoundOp? op]) {
      final s = cmd.substring(start, end).trim();
      if (s.isNotEmpty) segments.add(_CompoundSegment(s, op));
      start = end + (op == _CompoundOp.and ? 2 : op == _CompoundOp.or ? 2 : 1);
    }

    for (var i = 0; i < cmd.length; i++) {
      final c = cmd[i];
      if (inSingle) {
        if (c == '\'') inSingle = false;
        continue;
      }
      if (inDouble) {
        if (c == '"') inDouble = false;
        if (c == '\\') i++;
        continue;
      }
      if (c == '\'') { inSingle = true; continue; }
      if (c == '"') { inDouble = true; continue; }
      if (c == '\\') { i++; continue; }

      if (c == '(' || c == '{') { depth++; continue; }
      if (c == ')' || c == '}') { depth--; continue; }
      if (depth > 0) continue;

      if (c == ';') {
        flush(i, _CompoundOp.semicolon);
      } else if (c == '&' && i + 1 < cmd.length && cmd[i + 1] == '&') {
        flush(i, _CompoundOp.and);
        i++;
      } else if (c == '|' && i + 1 < cmd.length && cmd[i + 1] == '|') {
        flush(i, _CompoundOp.or);
        i++;
      }
    }

    final rest = cmd.substring(start).trim();
    if (rest.isNotEmpty) segments.add(_CompoundSegment(rest));
    if (segments.isEmpty) segments.add(_CompoundSegment(''));
    return segments;
  }

  ParsedRedirects? _parseRedirects(String cmd, List<String> tokens) {
    final redirects = <RedirectInfo>[];
    final baseTokens = <String>[];
    var i = 0;

    while (i < tokens.length) {
      final t = tokens[i];

      if (t == '>' && i + 1 < tokens.length) {
        redirects.add(RedirectInfo(
          srcFd: 1, kind: RedirectKind.output, target: tokens[i + 1],
        ));
        i += 2;
      } else if (t == '>>' && i + 1 < tokens.length) {
        redirects.add(RedirectInfo(
          srcFd: 1, kind: RedirectKind.output, target: tokens[i + 1],
          isAppend: true,
        ));
        i += 2;
      } else if (t == '2>' && i + 1 < tokens.length) {
        redirects.add(RedirectInfo(
          srcFd: 2, kind: RedirectKind.error, target: tokens[i + 1],
        ));
        i += 2;
      } else if (t == '2>>' && i + 1 < tokens.length) {
        redirects.add(RedirectInfo(
          srcFd: 2, kind: RedirectKind.error, target: tokens[i + 1],
          isAppend: true,
        ));
        i += 2;
      } else if (t == '&>' && i + 1 < tokens.length) {
        redirects.add(RedirectInfo(
          srcFd: -1, kind: RedirectKind.outputBoth, target: tokens[i + 1],
        ));
        i += 2;
      } else if (t == '&>>' && i + 1 < tokens.length) {
        redirects.add(RedirectInfo(
          srcFd: -1, kind: RedirectKind.outputBoth, target: tokens[i + 1],
          isAppend: true,
        ));
        i += 2;
      } else if (t.endsWith('>&1') || t.endsWith('>&2')) {
        final parts = t.split('>&');
        if (parts.length == 2) {
          final srcFd = int.tryParse(parts[0]);
          final dstFd = int.tryParse(parts[1]);
          if (srcFd != null && dstFd != null) {
            redirects.add(RedirectInfo(
              srcFd: srcFd, kind: RedirectKind.fdMerge, target: '',
              dstFd: dstFd,
            ));
            i++;
            continue;
          }
        }
        baseTokens.add(t); i++;
      } else {
        baseTokens.add(t);
        i++;
      }
    }

    if (redirects.isEmpty) return null;
    return ParsedRedirects(baseTokens.join(' '), redirects);
  }

  String _existingContent(String abs) {
    try {
      return File(abs).readAsStringSync();
    } catch (_) {
      return '';
    }
  }
}
