import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../tool_execution.dart';
import 'vfs_service.dart';
import 'vfs_exception.dart';

// =============================================================================
// ShellResult
// =============================================================================

class ShellResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  const ShellResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  bool get success => exitCode == 0;

  String get combined {
    if (stdout.trim().isNotEmpty) return stdout.trim();
    return stderr.trim();
  }

  String get full {
    final parts = <String>[];
    if (stdout.trim().isNotEmpty) parts.add('STDOUT:\n$stdout');
    if (stderr.trim().isNotEmpty) parts.add('STDERR:\n$stderr');
    parts.add('Exit code: $exitCode');
    return parts.join('\n\n');
  }
}

class _Redirect {
  final int srcFd;
  final String op;
  final String target;
  final int? dstFd;
  _Redirect(this.srcFd, this.op, this.target, this.dstFd);
  bool get isInput => srcFd == 0;
  bool get isOutput => srcFd == 1 || srcFd == 2 || srcFd == -1;
  bool get isAppend => op == '>>';
  bool get isFdRedirect => dstFd != null;
}

class _ParsedCommand {
  final String command;
  final List<_Redirect> redirects;
  _ParsedCommand(this.command, this.redirects);
}

// =============================================================================
// Command parser helpers
// =============================================================================

enum _CompoundOp { and, or, semicolon }

class _CompoundSegment {
  final String command;
  final _CompoundOp? separator;
  _CompoundSegment(this.command, [this.separator]);
}

// =============================================================================
// VfsShell
// =============================================================================

class VfsShell {
  VfsShell._();
  static final VfsShell _instance = VfsShell._();
  factory VfsShell() => _instance;

  final VfsService _vfs = VfsService();
  final ToolExecutionService _toolExec = ToolExecutionService();

  // --- shell state ---

  String _cwd = '/';
  String _previousCwd = '/';
  final List<String> _dirStack = [];
  int _lastExitCode = 0;
  bool _exitRequested = false;
  String _lastError = '';
  final Map<String, bool> _setFlags = {};

  final Map<String, String> _env = {
    'HOME': '/',
    'SHELL': '/bin/sh',
    'USER': 'kino',
    'TERM': 'xterm-256color',
  };

  final Map<String, String> _aliases = {};

  // --- public accessors ---

  String get cwd => _cwd;
  int get lastExitCode => _lastExitCode;

  void setEnv(String name, String value) {
    _env[name] = value;
  }

  String? getEnv(String name) => _env[name];

  // ===========================================================================
  // MAIN ENTRY POINT
  // ===========================================================================

  Future<ShellResult> execute(String command) async {
    final trimmed = command.trim();
    if (trimmed.isEmpty) {
      return const ShellResult(exitCode: 0, stdout: '', stderr: '');
    }

    try {
      String input = _expandAliases(trimmed);
      final segments = _splitCompound(input);
      final result = await _executeChain(segments, 0);
      if (_lastError.isNotEmpty) {
        return ShellResult(
          exitCode: result.exitCode,
          stdout: result.stdout,
          stderr: result.stderr.contains(_lastError)
              ? result.stderr
              : '${result.stderr}$_lastError\n',
        );
      }
      return result;
    } catch (e) {
      _lastExitCode = -1;
      return ShellResult(
        exitCode: -1,
        stdout: '',
        stderr: 'Shell error: $e',
      );
    }
  }

  // ===========================================================================
  // ALIAS EXPANSION
  // ===========================================================================

  String _expandAliases(String cmd) {
    if (_aliases.isEmpty) return cmd;
    final first = _extractFirstWord(cmd);
    if (first == null) return cmd;
    final alias = _aliases[first];
    if (alias == null) return cmd;
    return alias + cmd.substring(first.length);
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
        continue;
      }
      if (c == '\'') {
        inSingle = true;
        continue;
      }
      if (c == '"') {
        inDouble = true;
        continue;
      }
      if (c == '\\') {
        i++;
        continue;
      }
      if (c == ' ' || c == '\t') break;
      result.write(c);
    }
    return result.isEmpty ? null : result.toString();
  }

  // ===========================================================================
  // COMPOUND COMMAND SPLITTING
  // ===========================================================================

  /// Split on `&&`, `||`, `;` at the top level (respecting quotes/brackets).
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
      if (c == '\'') {
        inSingle = true;
        continue;
      }
      if (c == '"') {
        inDouble = true;
        continue;
      }
      if (c == '\\') {
        i++;
        continue;
      }

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

  Future<ShellResult> _executeChain(
      List<_CompoundSegment> segments, int idx) async {
    var skip = false; // for || chaining: skip on success
    var lastResult = const ShellResult(exitCode: 0, stdout: '', stderr: '');

    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i];
      final cmd = seg.command.trim();
      if (cmd.isEmpty) continue;

      // Determine if we should skip this segment
      if (i > 0 && seg.separator != null) {
        switch (seg.separator!) {
          case _CompoundOp.and:
            if (!lastResult.success) {
              skip = true;
              continue;
            }
            skip = false;
          case _CompoundOp.or:
            if (lastResult.success) {
              skip = true;
              continue;
            }
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
      if (_exitRequested) break;
    }

    _lastExitCode = lastResult.exitCode;
    return lastResult;
  }

  // ===========================================================================
  // SINGLE SEGMENT EXECUTION
  // ===========================================================================

  Future<ShellResult> _executeSegment(String cmd) async {
    if (_isCdCommand(cmd)) {
      return _handleCd(cmd);
    }

    // Pipes, subcommands, and backgrounding still need the real shell.
    // Simple redirects (> >> < 2>&1 &>) we handle natively.
    if (_needsRealShell(cmd)) {
      return _runInShell(cmd);
    }

    // Try parsing redirects natively
    final parsed = _parseRedirects(cmd);
    if (parsed != null) {
      return _executeWithRedirects(parsed);
    }

    // Plain command — extract first word
    final firstWord = _extractFirstWord(cmd);
    if (firstWord == null) {
      return const ShellResult(exitCode: 0, stdout: '', stderr: '');
    }

    if (_builtins.containsKey(firstWord)) {
      return _executeBuiltin(cmd, firstWord);
    }

    return _runInShell(cmd);
  }

  bool _isCdCommand(String cmd) {
    final trimmed = cmd.trimLeft();
    if (trimmed.startsWith('cd')) {
      if (trimmed.length == 2) return true;
      final c = trimmed[2];
      return c == ' ' || c == '\t';
    }
    return false;
  }

  /// Only flag operations the Dart shell truly cannot handle:
  /// pipes (|), backgrounding (&), and subcommands ($( ) ``).
  /// Simple redirects (>, >>, <, &>) are handled natively.
  bool _needsRealShell(String cmd) {
    for (var i = 0; i < cmd.length; i++) {
      final c = cmd[i];
      if (c == '\'' || c == '"') {
        final close = _findQuoteEnd(cmd, i, c);
        if (close == -1) return false;
        i = close;
        continue;
      }
      if (c == '\\') { i++; continue; }

      if (c == '|') return true; // pipe
      if (c == '&' && (i + 1 >= cmd.length || cmd[i + 1] != '&')) {
        return true; // single & = backgrounding
      }
      if (c == r'$' && i + 1 < cmd.length && cmd[i + 1] == '(') {
        return true; // $(subcommand)
      }
      if (c == '`') return true; // backtick subcommand
    }
    return false;
  }

  int _findQuoteEnd(String s, int start, String quote) {
    for (var i = start + 1; i < s.length; i++) {
      if (s[i] == '\\') { i++; continue; }
      if (s[i] == quote) return i;
    }
    return -1;
  }

  // ===========================================================================
  // REDIRECT PARSING & EXECUTION
  // ===========================================================================

  /// Parse redirects out of a command string.
  /// Returns null if parsing fails (unclosed quotes, etc.), in which case
  /// the caller should delegate to the real shell.
  /// Returns a list of tokens for the base command + parsed redirects.
  _ParsedCommand? _parseRedirects(String cmd) {
    final tokens = _tokenizeWithOps(cmd);
    if (tokens == null) return null;

    final baseTokens = <String>[];
    final redirects = <_Redirect>[];
    var i = 0;

    while (i < tokens.length) {
      final t = tokens[i];

      // Check for prefix fd number attached to a redirect operator
      int? checkFdRedirect(int idx) {
        final s = tokens[idx];
        if (s.isEmpty) return null;
        // Match patterns like 2>, 1>>, 2>&1, etc.
        final opStart = s.indexOf(RegExp(r'[><&]'));
        if (opStart <= 0) return null;
        final fd = int.tryParse(s.substring(0, opStart));
        if (fd == null || fd < 0 || fd > 2) return null;
        return fd;
      }

      int fd = 1;
      String op;

      // Handle &> (redirect both stdout and stderr)
      if (t == '&>' || t == '>|') {
        fd = -1;
        op = t;
      } else if (t == '>&') {
        // Could be &>file or >&file
        fd = -1;
        op = t;
      } else if (t == '>>' || t == '>' || t == '<' || t == '<>') {
        fd = 1; // default
        op = t;
      } else if (t == '<<') {
        fd = 0;
        op = t;
      } else if (t == '<<<') {
        fd = 0;
        op = t;
      } else if (t == '2>&1' || t == '1>&2') {
        // Pre-joined redirect
        final parts = t.split('>&');
        if (parts.length == 2) {
          fd = int.tryParse(parts[0]) ?? 1;
          op = '>&';
          final dst = int.tryParse(parts[1]);
          if (dst == null) { baseTokens.add(t); i++; continue; }
          redirects.add(_Redirect(fd, '>&', t, dst));
          i++;
          continue;
        }
        baseTokens.add(t); i++; continue;
      } else {
        // Check if token has fd prefix like "2>file"
        final check = checkFdRedirect(i);
        if (check != null) {
          final s = tokens[i];
          final opStart = s.indexOf(RegExp(r'[><&]'));
          final rawOp = s.substring(opStart);
          if (rawOp == '>&' && opStart + 2 < s.length) {
            // 2>&1
            fd = check;
            op = '>&';
            final dst = int.tryParse(s.substring(opStart + 2));
            if (dst == null) { baseTokens.add(t); i++; continue; }
            redirects.add(_Redirect(fd, op, s, dst));
            i++;
            continue;
          } else {
            fd = check;
            op = rawOp;
            // The target filename is after the operator chars
            if (opStart + op.length < s.length) {
              final target = s.substring(opStart + op.length);
              if (target.isNotEmpty) {
                redirects.add(_Redirect(fd, op, target, null));
                i++;
                continue;
              }
            }
            // No filename in this token — expect it in the next token
          }
        } else {
          baseTokens.add(t);
          i++;
          continue;
        }
      }

      // Get the target filename from the next token
      if (i + 1 >= tokens.length) {
        // Redirect without target — delegate to shell
        return null;
      }
      final target = tokens[i + 1];
      if (op == '>&' || op == '<>') {
        // Check if target is &N (fd redirect)
        if (target.startsWith('&')) {
          final dst = int.tryParse(target.substring(1));
          if (dst != null) {
            redirects.add(_Redirect(fd, op, target, dst));
            i += 2;
            continue;
          }
        }
      }
      redirects.add(_Redirect(fd, op, target, null));
      i += 2;
    }

    if (redirects.isEmpty) return null;

    final commandStr = baseTokens.join(' ');
    return _ParsedCommand(commandStr, redirects);
  }

  /// Tokenize but keep redirect operators as separate tokens.
  /// Returns null on parse errors.
  List<String>? _tokenizeWithOps(String input) {
    final tokens = <String>[];
    final current = StringBuffer();
    var inSingle = false;
    var inDouble = false;

    for (var i = 0; i < input.length; i++) {
      final c = input[i];

      if (inSingle) {
        if (c == '\'') { inSingle = false; } else { current.write(c); }
        continue;
      }
      if (inDouble) {
        if (c == '"') { inDouble = false; } else if (c == '\\') {
          i++; if (i < input.length) current.write(input[i]);
        } else { current.write(c); }
        continue;
      }
      if (c == '\'') { inSingle = true; continue; }
      if (c == '"') { inDouble = true; continue; }
      if (c == '\\') { i++; if (i < input.length) current.write(input[i]); continue; }

      // Redirect operators
      if (c == '>' || c == '<' || c == '&') {
        if (current.isNotEmpty) { tokens.add(current.toString()); current.clear(); }
        // Check for >>, <<, <>, &>, >&, 2>&1, <<<
        if (c == '>' && i + 1 < input.length && input[i + 1] == '>') {
          tokens.add('>>'); i++;
        } else if (c == '<' && i + 1 < input.length && input[i + 1] == '<') {
          if (i + 2 < input.length && input[i + 2] == '<') {
            tokens.add('<<<'); i += 2;
          } else {
            tokens.add('<<'); i++;
          }
        } else if (c == '<' && i + 1 < input.length && input[i + 1] == '>') {
          tokens.add('<>'); i++;
        } else if (c == '&' && i + 1 < input.length && input[i + 1] == '>') {
          tokens.add('&>'); i++;
        } else if (c == '>' && i + 1 < input.length && input[i + 1] == '&') {
          tokens.add('>&'); i++;
        } else {
          // single operator - but check for fd prefix like "2>"
          tokens.add(c == '&' ? '&' : c == '>' ? '>' : '<');
        }
        continue;
      }

      if (c == ' ' || c == '\t') {
        if (current.isNotEmpty) { tokens.add(current.toString()); current.clear(); }
      } else {
        current.write(c);
      }
    }

    if (inSingle || inDouble) return null; // unclosed quote
    if (current.isNotEmpty) tokens.add(current.toString());
    return tokens;
  }

  Future<ShellResult> _executeWithRedirects(_ParsedCommand parsed) async {
    // Execute the base command
    final baseResult = await _executeSegment(parsed.command);
    if (baseResult.exitCode != 0) {
      // Return early unless we need to capture error output
      return _applyRedirects(baseResult, parsed.redirects);
    }
    return _applyRedirects(baseResult, parsed.redirects);
  }

  Future<ShellResult> _applyRedirects(
      ShellResult result, List<_Redirect> redirects) async {
    var stdout = result.stdout;
    var stderr = result.stderr;

    for (final r in redirects) {
      if (r.isFdRedirect) {
        // fd-to-fd redirect: 2>&1, 1>&2
        if (r.srcFd == 2 && r.dstFd == 1) {
          // stderr -> stdout: merge stderr into stdout
          stdout = '$stdout\n$stderr';
          stderr = '';
        } else if (r.srcFd == 1 && r.dstFd == 2) {
          // stdout -> stderr: merge stdout into stderr
          stderr = '$stdout\n$stderr';
          stdout = '';
        }
        continue;
      }

      final target = _resolvePath(r.target);
      final abs = _vfsAbsolute(target);

      if (r.isInput) {
        // < file : read file and prepend to stdin (affects next run, not current)
        // For built-in commands that already read their own files, this is a no-op.
        // We could pass it as stdin to external commands, but for built-ins we skip.
        continue;
      }

      if (r.srcFd == -1) {
        // &> or >& : both stdout and stderr to file
        final content = '${stdout.trim()}\n${stderr.trim()}'.trim();
        if (r.isAppend) {
          await _vfs.writeFile(target, '${_existingContent(abs)}\n$content');
        } else {
          await _vfs.writeFile(target, content);
        }
        stdout = '';
        stderr = '';
      } else if (r.srcFd == 1) {
        // stdout to file
        if (r.isAppend) {
          await _vfs.writeFile(target, '${_existingContent(abs)}\n$stdout');
        } else {
          await _vfs.writeFile(target, stdout);
        }
        stdout = '';
      } else if (r.srcFd == 2) {
        // stderr to file
        if (r.isAppend) {
          await _vfs.writeFile(target, '${_existingContent(abs)}\n$stderr');
        } else {
          await _vfs.writeFile(target, stderr);
        }
        stderr = '';
      }
    }

    return ShellResult(
      exitCode: result.exitCode,
      stdout: stdout,
      stderr: stderr,
    );
  }

  String _existingContent(String abs) {
    try {
      return File(abs).readAsStringSync();
    } catch (_) {
      return '';
    }
  }

  // ===========================================================================
  // CD HANDLING
  // ===========================================================================

  Future<ShellResult> _handleCd(String cmd) async {
    // Extract the directory argument (after 'cd' + whitespace)
    final rest = cmd.substring(2).trimLeft();

    // Find the dir argument boundary — stop at &&, ||, ;, |, >
    final dirEnd = _findOperandEnd(rest);
    String? dir;
    String? trailing;

    if (dirEnd < rest.length) {
      final raw = rest.substring(0, dirEnd).trim();
      dir = raw.isEmpty ? null : raw;
      trailing = rest.substring(dirEnd).trim();
    } else {
      dir = rest.isEmpty ? null : rest;
    }

    final cdResult = _changeDir(dir);

    if (!cdResult.success || trailing == null || trailing.isEmpty) {
      return cdResult;
    }

    // Chain the trailing command
    final chainResult = await execute(trailing);

    return ShellResult(
      exitCode: cdResult.success
          ? chainResult.exitCode
          : cdResult.exitCode,
      stdout: cdResult.stdout + chainResult.stdout,
      stderr: cdResult.stderr + chainResult.stderr,
    );
  }

  /// Find the end of a command operand (before &&, ||, ;, |, >, <, &).
  int _findOperandEnd(String s) {
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
        if (c == '\\') { i++; continue; }
        continue;
      }
      if (c == '\'') { inSingle = true; continue; }
      if (c == '"') { inDouble = true; continue; }
      if (c == '\\') { i++; continue; }

      if (c == ';' || c == '|' || c == '>' || c == '<') return i;
      if (c == '&') return i;
    }
    return s.length;
  }

  // ===========================================================================
  // CD implementation
  // ===========================================================================

  String _vfsAbsolute(String vfsPath) {
    final parts = vfsPath.split('/').where((s) => s.isNotEmpty).toList();
    final clean = parts.join('/');
    return p.join(_vfs.rootPath, clean);
  }

  ShellResult _changeDir(String? rawDir) {
    String target;
    if (rawDir == null || rawDir.isEmpty || rawDir == '~') {
      target = _env['HOME'] ?? '/';
    } else if (rawDir == '-') {
      target = _previousCwd;
    } else {
      // Expand vars and tilde in the path
      final expanded = _expandVars(rawDir);
      target = _expandTilde(expanded);
      target = p.normalize(target.startsWith('/') ? target : p.join(_cwd, target));
      if (!target.startsWith('/')) target = '/$target';
    }

    final abs = _vfsAbsolute(target);
    final type = FileSystemEntity.typeSync(abs);
    if (type == FileSystemEntityType.notFound) {
      return ShellResult(
        exitCode: 1,
        stdout: '',
        stderr: 'cd: $rawDir: No such directory',
      );
    }
    if (type != FileSystemEntityType.directory) {
      return ShellResult(
        exitCode: 1,
        stdout: '',
        stderr: 'cd: $rawDir: Not a directory',
      );
    }

    _previousCwd = _cwd;
    _cwd = target;
    _env['PWD'] = _cwd;
    _env['OLDPWD'] = _previousCwd;
    return const ShellResult(exitCode: 0, stdout: '', stderr: '');
  }

  // ===========================================================================
  // DELEGATION TO REAL SHELL
  // ===========================================================================

  Future<ShellResult> _runInShell(String command) async {
    final result = await _toolExec.runShellCommand(
      command,
      workingDirectory: _cwd,
      extraEnv: {
        ..._env,
        'PWD': _cwd,
        'OLDPWD': _previousCwd,
      },
    );
    return ShellResult(
      exitCode: result.exitCode,
      stdout: result.stdout,
      stderr: result.stderr,
    );
  }

  // ===========================================================================
  // BUILT-IN EXECUTION
  // ===========================================================================

  Future<ShellResult> _executeBuiltin(String cmd, String firstWord) async {
    // Tokenize the command respecting quotes
    final rawTokens = _tokenize(cmd);
    if (rawTokens.isEmpty) {
      return const ShellResult(exitCode: 0, stdout: '', stderr: '');
    }

    // Expand each token: brace → tilde → vars → globs
    final expanded = <String>[];
    for (var i = 1; i < rawTokens.length; i++) {
      final token = rawTokens[i];
      // Brace expansion produces multiple tokens per one input token
      final braced = _expandBraces(token);
      for (final bt in braced) {
        final withTilde = _expandTilde(bt);
        final withVars = _expandVars(withTilde);
        // Glob expansion may produce multiple tokens
        final globbed = _expandGlob(withVars);
        expanded.addAll(globbed);
      }
    }

    final handler = _builtins[firstWord]!;
    return handler(expanded);
  }

  // ===========================================================================
  // TOKENIZER
  // ===========================================================================

  List<String> _tokenize(String input) {
    final tokens = <String>[];
    final current = StringBuffer();
    var inSingle = false;
    var inDouble = false;

    for (var i = 0; i < input.length; i++) {
      final c = input[i];

      if (inSingle) {
        if (c == '\'') {
          inSingle = false;
        } else {
          current.write(c);
        }
        continue;
      }

      if (inDouble) {
        if (c == '"') {
          inDouble = false;
        } else if (c == '\\') {
          i++;
          if (i < input.length) current.write(input[i]);
        } else {
          current.write(c);
        }
        continue;
      }

      if (c == '\'') {
        inSingle = true;
      } else if (c == '"') {
        inDouble = true;
      } else if (c == '\\') {
        i++;
        if (i < input.length) current.write(input[i]);
      } else if (c == ' ' || c == '\t') {
        if (current.isNotEmpty) {
          tokens.add(current.toString());
          current.clear();
        }
      } else {
        current.write(c);
      }
    }

    if (current.isNotEmpty) tokens.add(current.toString());
    return tokens;
  }

  // ===========================================================================
  // VARIABLE EXPANSION
  // ===========================================================================

  String _expandVars(String s) {
    final result = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (s[i] == '\'') {
        // Single-quoted strings: no expansion
        final end = s.indexOf('\'', i + 1);
        if (end == -1) { result.write(s.substring(i)); break; }
        result.write(s.substring(i, end + 1));
        i = end;
        continue;
      }

      if (s[i] == '\\') {
        i++;
        if (i < s.length) result.write(s[i]);
        continue;
      }

      if (s[i] != r'$') {
        result.write(s[i]);
        continue;
      }

      // $ followed by something
      i++;
      if (i >= s.length) {
        result.write(r'$');
        break;
      }

      // $$
      if (s[i] == r'$') {
        result.write('0');
        continue;
      }

      // $?
      if (s[i] == '?') {
        result.write(_lastExitCode);
        continue;
      }

      // $0
      if (s[i] == '0') {
        result.write('kino');
        continue;
      }

      // $*
      if (s[i] == '*') {
        result.write('');
        continue;
      }

      // $(( — arithmetic expansion
      if (s[i] == '(' && i + 1 < s.length && s[i + 1] == '(') {
        final end = _findMatchingClose(s, i + 2, ')', ')');
        if (end == -1) { result.write(r'$(('); i++; continue; }
        final expr = s.substring(i + 2, end);
        final value = _evalArithmetic(expr);
        result.write(value);
        i = end + 1;
        continue;
      }

      // ${
      if (s[i] == '{') {
        final resultStr = _expandBraceVar(s, i + 1);
        if (resultStr == null) {
          // Not a valid ${} — emit literally
          result.write(r'$');
          i--;
          continue;
        }
        final consumed = _lastBraceVarConsumed;
        result.write(resultStr);
        i = i + consumed;
        continue;
      }

      // $VARNAME — consume alphanumeric/underscore chars
      if (_isVarChar(s[i], first: true)) {
        final start = i;
        while (i < s.length && _isVarChar(s[i], first: false)) { i++; }
        final varName = s.substring(start, i);
        result.write(_lookupVar(varName));
        i--;
      } else {
        // Not a variable: emit $ literally
        result.write(r'$');
        result.write(s[i]);
      }
    }

    return result.toString();
  }

  // Tracks the last consumed length inside ${} so _expandVars knows how far to skip
  int _lastBraceVarConsumed = 0;

  /// Parse and expand `${...}` including all string operations.
  /// Returns null if parsing fails.
  /// Sets [_lastBraceVarConsumed] to the number of chars consumed from the `{`.
  String? _expandBraceVar(String s, int start) {
    // Find the matching closing brace, handling nested ${}
    final end = _findMatchingClose(s, start, '}', '{');
    if (end == -1) return null;

    final contents = s.substring(start, end);
    _lastBraceVarConsumed = end - start + 1; // include both { and }

    if (contents.isEmpty) return null;

    // ${#var} — string length
    if (contents.startsWith('#')) {
      final varName = _extractVarName(contents.substring(1));
      final val = _lookupVar(varName);
      return val.length.toString();
    }

    // ${!var} — indirect expansion (not common, skip for now)
    if (contents.startsWith('!')) {
      final inner = _extractVarName(contents.substring(1));
      final innerVal = _lookupVar(inner);
      return _lookupVar(innerVal);
    }

    // Check for parameter expansion operators
    // Pattern: varname op word
    // Operators: :- := :+ :?  # ## % %% / // ^ ^^ , ,, :offset :offset:length

    // Find var name end — the first occurrence of one of the special operators
    // That isn't part of the var name itself
    final opMatch = RegExp(r'^([_a-zA-Z][_a-zA-Z0-9]*)([:#%^,/!?].*)$').firstMatch(contents);
    if (opMatch == null) {
      // Simple variable expansion: ${var}
      final varName = contents.trim();
      if (!_isSimpleVarName(varName)) return null;
      return _lookupVar(varName);
    }

    final varName = opMatch.group(1)!;
    final rest = opMatch.group(2)!;
    final varValue = _lookupVar(varName);

    // ${var:-word} — use default if unset/null
    // ${var:=word} — assign default if unset/null
    // ${var:+word} — use alternate if set
    // ${var:?word} — error if unset/null
    if (rest.startsWith(':-')) {
      final word = rest.substring(2);
      if (varValue.isEmpty) return _expandVarsIn(word);
      return varValue;
    }
    if (rest.startsWith(':=')) {
      final word = rest.substring(2);
      if (varValue.isEmpty) {
        final expanded = _expandVarsIn(word);
        _env[varName] = expanded;
        return expanded;
      }
      return varValue;
    }
    if (rest.startsWith(':+')) {
      final word = rest.substring(2);
      if (varValue.isNotEmpty) return _expandVarsIn(word);
      return '';
    }
    if (rest.startsWith(':?')) {
      final word = rest.substring(2);
      if (varValue.isEmpty) {
        final msg = word.isEmpty ? 'parameter $varName is not set' : word;
        _lastError = msg;
        return '';
      }
      return varValue;
    }

    // ${var#pattern} — remove shortest prefix
    // ${var##pattern} — remove longest prefix
    if (rest.startsWith('##')) {
      final pattern = rest.substring(2);
      return _removeLongestPrefix(varValue, pattern);
    }
    if (rest.startsWith('#')) {
      final pattern = rest.substring(1);
      return _removeShortestPrefix(varValue, pattern);
    }

    // ${var%pattern} — remove shortest suffix
    // ${var%%pattern} — remove longest suffix
    if (rest.startsWith('%%')) {
      final pattern = rest.substring(2);
      return _removeLongestSuffix(varValue, pattern);
    }
    if (rest.startsWith('%')) {
      final pattern = rest.substring(1);
      return _removeShortestSuffix(varValue, pattern);
    }

    // ${var/pattern/replacement} — replace first
    // ${var//pattern/replacement} — replace all
    if (rest.startsWith('//')) {
      final slashPos = rest.indexOf('/', 2);
      if (slashPos == -1) return varValue;
      final pattern = rest.substring(2, slashPos);
      final replacement = rest.substring(slashPos + 1);
      return varValue.replaceAll(_globToRegexStr(pattern), replacement);
    }
    if (rest.startsWith('/')) {
      final slashPos = rest.indexOf('/', 1);
      if (slashPos == -1) return varValue;
      final pattern = rest.substring(1, slashPos);
      final replacement = rest.substring(slashPos + 1);
      return varValue.replaceFirstMapped(
          RegExp(_globToRegexStr(pattern)), (_) => replacement);
    }

    // ${var^pattern} — uppercase first matching
    // ${var^^pattern} — uppercase all matching
    // ${var,pattern}  — lowercase first matching
    // ${var,,pattern} — lowercase all matching
    if (rest.startsWith('^^')) {
      final pattern = rest.substring(2);
      if (pattern.isEmpty) return varValue.toUpperCase();
      return varValue.splitMapJoin(RegExp(_globToRegexStr(pattern)),
          onMatch: (m) => m.group(0)!.toUpperCase(),
          onNonMatch: (s) => s);
    }
    if (rest.startsWith('^')) {
      final pattern = rest.substring(1);
      if (pattern.isEmpty) {
        if (varValue.isEmpty) return varValue;
        return varValue[0].toUpperCase() + varValue.substring(1);
      }
      return varValue.splitMapJoin(RegExp(_globToRegexStr(pattern)),
          onMatch: (m) => m.group(0)!.toUpperCase(),
          onNonMatch: (s) => s);
    }
    if (rest.startsWith(',,')) {
      final pattern = rest.substring(2);
      if (pattern.isEmpty) return varValue.toLowerCase();
      return varValue.splitMapJoin(RegExp(_globToRegexStr(pattern)),
          onMatch: (m) => m.group(0)!.toLowerCase(),
          onNonMatch: (s) => s);
    }
    if (rest.startsWith(',')) {
      final pattern = rest.substring(1);
      if (pattern.isEmpty) {
        if (varValue.isEmpty) return varValue;
        return varValue[0].toLowerCase() + varValue.substring(1);
      }
      return varValue.splitMapJoin(RegExp(_globToRegexStr(pattern)),
          onMatch: (m) => m.group(0)!.toLowerCase(),
          onNonMatch: (s) => s);
    }

    // ${var:offset} or ${var:offset:length} — substring
    if (rest.startsWith(':')) {
      final parts = rest.substring(1).split(':');
      if (parts.isEmpty) return varValue;
      final offset = int.tryParse(parts[0].trim()) ?? 0;
      if (parts.length >= 2) {
        final length = int.tryParse(parts[1].trim());
        if (length != null) {
          final safeOffset = offset < 0 ? varValue.length + offset : offset;
          if (safeOffset < 0 || safeOffset >= varValue.length) return '';
          return varValue.substring(safeOffset, min(safeOffset + length, varValue.length));
        }
      }
      final safeOffset = offset < 0 ? varValue.length + offset : offset;
      if (safeOffset < 0 || safeOffset >= varValue.length) return '';
      return varValue.substring(safeOffset);
    }

    // Fallback: plain variable
    return _lookupVar(varName);
  }

  String _expandVarsIn(String s) {
    return _expandVars(s);
  }

  bool _isSimpleVarName(String s) {
    if (s.isEmpty) return false;
    if (!_isVarChar(s[0], first: true)) return false;
    for (var i = 1; i < s.length; i++) {
      if (!_isVarChar(s[i], first: false)) return false;
    }
    return true;
  }

  String _extractVarName(String s) {
    final trimmed = s.trim();
    final match = RegExp(r'^[_a-zA-Z][_a-zA-Z0-9]*').firstMatch(trimmed);
    if (match == null) return '';
    return match.group(0)!;
  }

  String _removeShortestPrefix(String value, String pattern) {
    final regex = RegExp('^${_globToRegexStr(pattern)}');
    final match = regex.firstMatch(value);
    if (match == null) return value;
    return value.substring(match.end);
  }

  String _removeLongestPrefix(String value, String pattern) {
    final regex = RegExp(_globToRegexStr(pattern));
    var best = value;
    for (var i = 0; i <= value.length; i++) {
      final sub = value.substring(i);
      if (regex.hasMatch(sub)) {
        best = sub;
        break;
      }
    }
    return best;
  }

  String _removeShortestSuffix(String value, String pattern) {
    final regex = RegExp('${_globToRegexStr(pattern)}\$');
    final match = regex.firstMatch(value);
    if (match == null) return value;
    return value.substring(0, match.start);
  }

  String _removeLongestSuffix(String value, String pattern) {
    final regex = RegExp(_globToRegexStr(pattern));
    var best = value;
    for (var i = value.length; i >= 0; i--) {
      final sub = value.substring(0, i);
      if (regex.hasMatch(sub)) return sub;
    }
    return best;
  }

  // ===========================================================================
  // ARITHMETIC EXPANSION $((expression))
  // ===========================================================================

  String _evalArithmetic(String expr) {
    try {
      final result = _evalExpr(expr.trim());
      return result.toString();
    } catch (_) {
      return '0';
    }
  }

  int _evalExpr(String expr) {
    expr = expr.trim();
    if (expr.isEmpty) return 0;

    // Evaluate simple integer expressions with + - * / % ( ) and variable refs
    // First, expand any variable references
    expr = expr.replaceAllMapped(RegExp(r'[_a-zA-Z][_a-zA-Z0-9]*'), (m) {
      final val = _lookupVar(m.group(0)!);
      if (val.isEmpty) return '0';
      return val;
    });

    // Use a simple recursive descent parser
    return _parseArith(expr);
  }

  int _parseArith(String expr) {
    final trimmed = expr.trim();
    if (trimmed.isEmpty) return 0;

    // Handle parenthesized sub-expressions
    if (trimmed.startsWith('(')) {
      final close = _findMatchingParen(trimmed, 0);
      if (close == -1) return 0;
      final inner = _parseArith(trimmed.substring(1, close));
      final rest = trimmed.substring(close + 1).trim();
      if (rest.isEmpty) return inner;
      return _applyOp(inner, rest);
    }

    // Find the last operator (not inside parens) for left-to-right associativity
    var depth = 0;
    var lastOp = -1;
    var lastOpType = '';
    for (var i = trimmed.length - 1; i >= 0; i--) {
      if (trimmed[i] == ')') { depth++; continue; }
      if (trimmed[i] == '(') { depth--; continue; }
      if (depth > 0) continue;
      // Check for binary operators (lowest precedence first)
      if (trimmed[i] == '+' && (i == 0 || trimmed[i - 1] != '*')) { lastOp = i; lastOpType = '+'; break; }
      if (trimmed[i] == '-') { lastOp = i; lastOpType = '-'; break; }
    }
    if (lastOp == -1) {
      // No + or - outside parens; find * / %
      for (var i = trimmed.length - 1; i >= 0; i--) {
        if (trimmed[i] == ')') { depth++; continue; }
        if (trimmed[i] == '(') { depth--; continue; }
        if (depth > 0) continue;
        if (trimmed[i] == '*') { lastOp = i; lastOpType = '*'; break; }
        if (trimmed[i] == '/') { lastOp = i; lastOpType = '/'; break; }
        if (trimmed[i] == '%') { lastOp = i; lastOpType = '%'; break; }
      }
    }
    if (lastOp == -1) {
      // Leaf: return integer value
      return int.tryParse(trimmed) ?? 0;
    }

    final left = _parseArith(trimmed.substring(0, lastOp));
    final right = _parseArith(trimmed.substring(lastOp + 1));
    switch (lastOpType) {
      case '+': return left + right;
      case '-': return left - right;
      case '*': return left * right;
      case '/': return right == 0 ? 0 : left ~/ right;
      case '%': return right == 0 ? 0 : left % right;
      default: return 0;
    }
  }

  int _applyOp(int left, String rest) {
    rest = rest.trim();
    if (rest.isEmpty) return left;
    return _parseArith('$left $rest');
  }

  int _findMatchingParen(String s, int start) {
    var depth = 0;
    for (var i = start; i < s.length; i++) {
      if (s[i] == '(') depth++;
      if (s[i] == ')') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  int _findMatchingClose(String s, int start, String closeChar, String openChar) {
    var depth = 0;
    for (var i = start; i < s.length; i++) {
      if (s[i] == openChar && openChar != closeChar) { depth++; continue; }
      if (s[i] == closeChar) {
        if (depth == 0) return i;
        depth--;
      }
    }
    return -1;
  }

  /// Convert a glob pattern to a regex pattern string
  String _globToRegexStr(String pattern) {
    final buf = StringBuffer();
    for (var i = 0; i < pattern.length; i++) {
      final c = pattern[i];
      if (c == '*') {
        buf.write('.*');
      } else if (c == '?') {
        buf.write('.');
      } else if (c == '.') {
        buf.write(r'\.');
      } else {
        buf.write(c);
      }
    }
    return buf.toString();
  }

  // ===========================================================================
  // BRACE EXPANSION {a,b,c} {1..5}
  // ===========================================================================

  List<String> _expandBraces(String s) {
    if (!s.contains('{') && !s.contains('}')) return [s];

    final results = <String>[];
    _expandBraceRecursive(s, 0, results);
    if (results.isEmpty) results.add(s);
    return results;
  }

  void _expandBraceRecursive(String s, int start, List<String> out) {
    // Find the first unescaped, unquoted '{' that starts a valid brace expansion
    var i = start;
    var inSingle = false;
    var inDouble = false;

    while (i < s.length) {
      final c = s[i];
      if (c == '\'') { inSingle = !inSingle; i++; continue; }
      if (c == '"') { inDouble = !inDouble; i++; continue; }
      if (c == '\\') { i += 2; continue; }
      if (inSingle || inDouble) { i++; continue; }

      if (c == '{') {
        // Parse the brace group
        final result = _parseBraceGroup(s, i);
        if (result != null) {
          final (prefix, parts, suffix) = result;
          for (final part in parts) {
            final expanded = prefix + part + suffix;
            if (expanded.contains('{')) {
              _expandBraceRecursive(expanded, 0, out);
            } else {
              out.add(expanded);
            }
          }
          return;
        }
        // Not a valid brace expansion, continue scanning
        i++;
        continue;
      }
      i++;
    }

    // No brace expansion found
    out.add(s);
  }

  /// Parse a brace expansion starting at the opening `{`.
  /// Returns (prefix, [parts], suffix) or null if not a valid expansion.
  (String, List<String>, String)? _parseBraceGroup(String s, int start) {
    if (start >= s.length || s[start] != '{') return null;

    final prefix = s.substring(0, start);

    // Check for {x..y} numeric sequence pattern
    final seqMatch = RegExp(r'^\{(-?\d+)\.\.(-?\d+)(?:\.\.(-?\d+))?\}').firstMatch(s.substring(start));
    if (seqMatch != null) {
      final startNum = int.parse(seqMatch.group(1)!);
      final endNum = int.parse(seqMatch.group(2)!);
      final step = seqMatch.group(3) != null ? int.parse(seqMatch.group(3)!).abs() : 1;
      final parts = <String>[];
      if (startNum <= endNum) {
        for (var n = startNum; n <= endNum; n += step) {
          parts.add(n.toString());
        }
      } else {
        for (var n = startNum; n >= endNum; n -= step) {
          parts.add(n.toString());
        }
      }
      final suffix = s.substring(start + seqMatch.group(0)!.length);
      return (prefix, parts, suffix);
    }

    // Check for {a,b,c} list pattern
    // Find the matching closing brace
    final braceContent = _findBraceContent(s, start);
    if (braceContent == null) return null;

    final (content, end) = braceContent;
    final parts = _splitBraceContent(content);
    if (parts.isEmpty) return null;

    final suffix = s.substring(end + 1);
    return (prefix, parts, suffix);
  }

  /// Find the matching closing brace for a brace group, handling nesting.
  (String, int)? _findBraceContent(String s, int start) {
    if (start >= s.length || s[start] != '{') return null;
    var depth = 1;
    var lastComma = -1;
    for (var i = start + 1; i < s.length; i++) {
      if (s[i] == '{') { depth++; continue; }
      if (s[i] == '}') {
        depth--;
        if (depth == 0) {
          if (lastComma >= 0 || _looksLikeSequence(s, start, i)) {
            return (s.substring(start + 1, i), i);
          }
          return null;
        }
      }
      if (s[i] == ',' && depth == 1) {
        lastComma = i;
      }
    }
    return null;
  }

  bool _looksLikeSequence(String s, int braceOpen, int braceClose) {
    final inner = s.substring(braceOpen + 1, braceClose);
    return RegExp(r'^-?\d+\.\.-?\d+(\.\.-?\d+)?$').hasMatch(inner);
  }

  List<String> _splitBraceContent(String content) {
    final parts = <String>[];
    var depth = 0;
    var currentStart = 0;
    for (var i = 0; i < content.length; i++) {
      if (content[i] == '{') { depth++; continue; }
      if (content[i] == '}') { depth--; continue; }
      if (content[i] == ',' && depth == 0) {
        parts.add(content.substring(currentStart, i));
        currentStart = i + 1;
      }
    }
    parts.add(content.substring(currentStart));
    return parts;
  }

  bool _isVarChar(String c, {bool first = false}) {
    if (c == '_') return true;
    if (first) {
      return (c.codeUnitAt(0) >= 65 && c.codeUnitAt(0) <= 90) ||
             (c.codeUnitAt(0) >= 97 && c.codeUnitAt(0) <= 122);
    }
    return (c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57) ||
           (c.codeUnitAt(0) >= 65 && c.codeUnitAt(0) <= 90) ||
           (c.codeUnitAt(0) >= 97 && c.codeUnitAt(0) <= 122) ||
           c == '_';
  }

  String _lookupVar(String name) {
    if (_env.containsKey(name)) return _env[name]!;
    if (name == '?') return _lastExitCode.toString();
    if (name == r'$') return '0';
    return '';
  }

  // ===========================================================================
  // TILDE EXPANSION
  // ===========================================================================

  String _expandTilde(String s) {
    if (s == '~') return _env['HOME'] ?? '/';
    if (s.startsWith('~/')) return (_env['HOME'] ?? '/') + s.substring(1);
    return s;
  }

  // ===========================================================================
  // GLOB EXPANSION
  // ===========================================================================

  List<String> _expandGlob(String token) {
    if (!token.contains('*') && !token.contains('?') && !token.contains('[')) {
      return [token];
    }

    // Split into directory part and pattern
    final dirPart = p.dirname(token);
    final pattern = p.basename(token);
    final resolvedDir = dirPart == '.'
        ? _cwd
        : _resolvePath(dirPart);

    final absDir = _vfsAbsolute(resolvedDir);
    final dir = Directory(absDir);
    if (!dir.existsSync()) return [token];

    final regex = _globToRegex(pattern);
    final matches = <String>[];
    try {
      final entities = dir.listSync();
      for (final e in entities) {
        final name = p.basename(e.path);
        if (regex.hasMatch(name)) {
          final vfsPath = resolvedDir == '/'
              ? '/$name'
              : '$resolvedDir/$name';
          matches.add(vfsPath);
        }
      }
    } catch (_) {}

    matches.sort();

    if (matches.isEmpty) return [token];
    return matches;
  }

  RegExp _globToRegex(String pattern) {
    final sb = StringBuffer('^');
    for (var i = 0; i < pattern.length; i++) {
      final c = pattern[i];
      if (c == '*') {
        sb.write('[^/]*');
      } else if (c == '?') {
        sb.write('[^/]');
      } else if (c == '.') {
        sb.write('\\.');
      } else if (c == '[') {
        // Character class — copy verbatim until ]
        var closed = false;
        for (var j = i + 1; j < pattern.length; j++) {
          if (pattern[j] == ']') {
            sb.write(pattern.substring(i, j + 1));
            i = j;
            closed = true;
            break;
          }
        }
        if (!closed) sb.write(RegExp.escape(c));
      } else {
        sb.write(RegExp.escape(c));
      }
    }
    sb.write(r'$');
    return RegExp(sb.toString());
  }

  // ===========================================================================
  // PATH RESOLUTION
  // ===========================================================================

  String _resolvePath(String path) {
    if (path.isEmpty) return _cwd;
    if (path == '-') return _previousCwd;
    if (path == '~') return _env['HOME'] ?? '/';
    if (path.startsWith('~/')) return p.join(_env['HOME'] ?? '/', path.substring(2));
    if (path.startsWith('/')) return path;

    final resolved = p.normalize(p.join(_cwd, path));
    if (!resolved.startsWith('/')) return '/$resolved';
    return resolved;
  }

  // ===========================================================================
  // BUILT-IN REGISTRY
  // ===========================================================================

  late final Map<String, Future<ShellResult> Function(List<String> args)>
      _builtins = {
    'pwd': _cmdPwd,
    'echo': _cmdEcho,
    'ls': _cmdLs,
    'cat': _cmdCat,
    'mkdir': _cmdMkdir,
    'rm': _cmdRm,
    'cp': _cmdCp,
    'mv': _cmdMv,
    'touch': _cmdTouch,
    'head': _cmdHead,
    'tail': _cmdTail,
    'grep': _cmdGrep,
    'wc': _cmdWc,
    'sort': _cmdSort,
    'printf': _cmdPrintf,
    'true': _cmdTrue,
    'false': _cmdFalse,
    'sleep': _cmdSleep,
    'export': _cmdExport,
    'unset': _cmdUnset,
    'env': _cmdEnv,
    'which': _cmdWhich,
    'type': _cmdType,
    'alias': _cmdAlias,
    'unalias': _cmdUnalias,
    'clear': _cmdClear,
    'help': _cmdHelp,
    'pushd': _cmdPushd,
    'popd': _cmdPopd,
    'dirs': _cmdDirs,
    'source': _cmdSource,
    '.': _cmdSource,
    'set': _cmdSet,
    'exit': _cmdExit,
    'return': _cmdReturn,
    'break': _cmdBreak,
    'continue': _cmdContinue,
    'test': _cmdTest,
    '[': _cmdLeftBracket,
    'declare': _cmdDeclare,
    'local': _cmdLocal,
    'curl': _cmdCurl,
  };

  // ===========================================================================
  // BUILT-IN: pwd
  // ===========================================================================

  Future<ShellResult> _cmdPwd(List<String> args) async {
    String pwd;
    if (args.isNotEmpty && args[0] == '-P') {
      final abs = _vfsAbsolute(_cwd);
      pwd = FileSystemEntity.isLinkSync(abs)
          ? Directory(abs).resolveSymbolicLinksSync()
          : abs;
    } else {
      pwd = _cwd;
    }
    return ShellResult(exitCode: 0, stdout: '$pwd\n', stderr: '');
  }

  // ===========================================================================
  // BUILT-IN: echo
  // ===========================================================================

  Future<ShellResult> _cmdEcho(List<String> args) async {
    var noNewline = false;
    var interpretEscapes = false;
    var i = 0;

    while (i < args.length && args[i].startsWith('-')) {
      if (args[i] == '-n') {
        noNewline = true;
        i++;
      } else if (args[i] == '-e') {
        interpretEscapes = true;
        i++;
      } else if (args[i] == '-E') {
        interpretEscapes = false;
        i++;
      } else {
        break;
      }
    }

    final text = args.sublist(i).join(' ');
    final out = interpretEscapes ? _unescape(text) : text;
    return ShellResult(
      exitCode: 0,
      stdout: out + (noNewline ? '' : '\n'),
      stderr: '',
    );
  }

  String _unescape(String s) {
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (s[i] == '\\' && i + 1 < s.length) {
        i++;
        switch (s[i]) {
          case 'n': b.write('\n');
          case 't': b.write('\t');
          case 'r': b.write('\r');
          case '\\': b.write('\\');
          case '0': b.write('\x00');
          default: b.write(s[i]);
        }
      } else {
        b.write(s[i]);
      }
    }
    return b.toString();
  }

  // ===========================================================================
  // BUILT-IN: ls
  // ===========================================================================

  Future<ShellResult> _cmdLs(List<String> args) async {
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
          exitCode: 1,
          stdout: '',
          stderr: 'ls: invalid option: $arg',
        );
      } else {
        dirs.add(arg);
      }
    }

    if (dirs.isEmpty) dirs.add(_cwd);

    final output = StringBuffer();
    for (var di = 0; di < dirs.length; di++) {
      final target = _resolvePath(dirs[di]);
      final abs = _vfsAbsolute(target);
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

  // ===========================================================================
  // BUILT-IN: cat
  // ===========================================================================

  Future<ShellResult> _cmdCat(List<String> args) async {
    if (args.isEmpty) {
      return const ShellResult(exitCode: 0, stdout: '', stderr: '');
    }

    final output = StringBuffer();
    for (final arg in args) {
      final target = _resolvePath(arg);
      try {
        final content = await _vfs.readFileAsString(target);
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

  // ===========================================================================
  // BUILT-IN: mkdir
  // ===========================================================================

  Future<ShellResult> _cmdMkdir(List<String> args) async {
    var parents = false;
    var dirs = <String>[];

    for (final arg in args) {
      if (arg == '-p') { parents = true; } else if (arg.startsWith('-')) {
        return ShellResult(
          exitCode: 1,
          stdout: '',
          stderr: 'mkdir: invalid option: $arg',
        );
      } else {
        dirs.add(arg);
      }
    }

    if (dirs.isEmpty) {
      return const ShellResult(
        exitCode: 1,
        stdout: '',
        stderr: 'mkdir: missing operand',
      );
    }

    final output = StringBuffer();
    for (final dir in dirs) {
      final target = _resolvePath(dir);
      try {
        if (parents) {
          await Directory(_vfsAbsolute(target)).create(recursive: true);
        } else {
          await _vfs.createDirectory(target);
        }
      } on VfsAlreadyExistsException {
        output.writeln('mkdir: $dir: File exists');
      } catch (e) {
        output.writeln('mkdir: $dir: $e');
      }
    }

    return ShellResult(exitCode: 0, stdout: output.toString(), stderr: '');
  }

  // ===========================================================================
  // BUILT-IN: rm
  // ===========================================================================

  Future<ShellResult> _cmdRm(List<String> args) async {
    var recursive = false;
    var force = false;
    var targets = <String>[];

    for (final arg in args) {
      if (arg == '-rf' || arg == '-fr') { recursive = true; force = true; } else if (arg == '-r' || arg == '-R') { recursive = true; } else if (arg == '-f') { force = true; } else if (arg.startsWith('-')) {
        return ShellResult(
          exitCode: 1,
          stdout: '',
          stderr: 'rm: invalid option: $arg',
        );
      } else {
        targets.add(arg);
      }
    }

    if (targets.isEmpty) {
      return const ShellResult(
        exitCode: 1,
        stdout: '',
        stderr: 'rm: missing operand',
      );
    }

    final output = StringBuffer();
    for (final target in targets) {
      final resolved = _resolvePath(target);
      try {
        final abs = _vfsAbsolute(resolved);
        final type = FileSystemEntity.typeSync(abs);
        if (type == FileSystemEntityType.notFound) {
          if (!force) output.writeln('rm: $target: No such file');
          continue;
        }
        if (type == FileSystemEntityType.directory && !recursive) {
          output.writeln('rm: $target: is a directory');
          continue;
        }
        await _vfs.delete(resolved);
      } catch (e) {
        if (!force) output.writeln('rm: $target: $e');
      }
    }

    return ShellResult(exitCode: 0, stdout: output.toString(), stderr: '');
  }

  // ===========================================================================
  // BUILT-IN: cp
  // ===========================================================================

  Future<ShellResult> _cmdCp(List<String> args) async {
    if (args.length < 2) {
      return const ShellResult(
        exitCode: 1,
        stdout: '',
        stderr: 'cp: missing file operand',
      );
    }

    final src = _resolvePath(args[0]);
    final dest = _resolvePath(args[1]);

    try {
      await _vfs.copy(src, dest);
      return const ShellResult(exitCode: 0, stdout: '', stderr: '');
    } on VfsNotFoundException {
      return ShellResult(
        exitCode: 1,
        stdout: '',
        stderr: 'cp: ${args[0]}: No such file or directory',
      );
    } catch (e) {
      return ShellResult(exitCode: 1, stdout: '', stderr: 'cp: $e');
    }
  }

  // ===========================================================================
  // BUILT-IN: mv
  // ===========================================================================

  Future<ShellResult> _cmdMv(List<String> args) async {
    if (args.length < 2) {
      return const ShellResult(
        exitCode: 1,
        stdout: '',
        stderr: 'mv: missing file operand',
      );
    }

    final src = _resolvePath(args[0]);
    final dest = _resolvePath(args[1]);

    try {
      await _vfs.move(src, dest);
      return const ShellResult(exitCode: 0, stdout: '', stderr: '');
    } on VfsNotFoundException {
      return ShellResult(
        exitCode: 1,
        stdout: '',
        stderr: 'mv: ${args[0]}: No such file or directory',
      );
    } catch (e) {
      return ShellResult(exitCode: 1, stdout: '', stderr: 'mv: $e');
    }
  }

  // ===========================================================================
  // BUILT-IN: touch
  // ===========================================================================

  Future<ShellResult> _cmdTouch(List<String> args) async {
    if (args.isEmpty) {
      return const ShellResult(
        exitCode: 1,
        stdout: '',
        stderr: 'touch: missing file operand',
      );
    }

    for (final arg in args) {
      final target = _resolvePath(arg);
      final file = File(_vfsAbsolute(target));
      if (await file.exists()) {
        await file.setLastModified(DateTime.now());
      } else {
        await file.create(recursive: true);
      }
    }

    return const ShellResult(exitCode: 0, stdout: '', stderr: '');
  }

  // ===========================================================================
  // BUILT-IN: head
  // ===========================================================================

  Future<ShellResult> _cmdHead(List<String> args) async {
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
          exitCode: 1,
          stdout: '',
          stderr: 'head: invalid option: ${args[i]}',
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
      final target = _resolvePath(files[fi]);
      if (files.length > 1) output.writeln('==> ${files[fi]} <==');
      try {
        final content = await _vfs.readFileAsString(target);
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

  // ===========================================================================
  // BUILT-IN: tail
  // ===========================================================================

  Future<ShellResult> _cmdTail(List<String> args) async {
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
          exitCode: 1,
          stdout: '',
          stderr: 'tail: invalid option: ${args[i]}',
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
      final target = _resolvePath(files[fi]);
      if (files.length > 1) output.writeln('==> ${files[fi]} <==');
      try {
        final content = await _vfs.readFileAsString(target);
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

  // ===========================================================================
  // BUILT-IN: grep
  // ===========================================================================

  Future<ShellResult> _cmdGrep(List<String> args) async {
    if (args.isEmpty) {
      return const ShellResult(
        exitCode: 2,
        stdout: '',
        stderr: 'grep: usage: grep [options] pattern [file...]',
      );
    }

    var ignoreCase = false;
    var lineNumbers = false;
    var countOnly = false;
    var invert = false;
    var recursive = false;
    var i = 0;

    while (i < args.length && args[i].startsWith('-')) {
      final opt = args[i];
      if (opt == '-i') { ignoreCase = true; i++; } else if (opt == '-n') { lineNumbers = true; i++; } else if (opt == '-c') { countOnly = true; i++; } else if (opt == '-v') { invert = true; i++; } else if (opt == '-r' || opt == '-R') { recursive = true; i++; } else if (opt == '-iv' || opt == '-vi') { ignoreCase = true; invert = true; i++; } else if (opt == '--') { i++; break; } else {
        return ShellResult(
          exitCode: 2,
          stdout: '',
          stderr: 'grep: invalid option: $opt',
        );
      }
    }

    if (i >= args.length) {
      return const ShellResult(
        exitCode: 2,
        stdout: '',
        stderr: 'grep: missing pattern',
      );
    }

    final pattern = args[i];
    i++;
    final files = args.sublist(i);

    try {
      final regex = RegExp(pattern, caseSensitive: !ignoreCase);
      final output = StringBuffer();
      var matchCount = 0;

      void searchFile(String filePath, String fileName) async {
        try {
          final content = await _vfs.readFileAsString(filePath);
          final lines = content.split('\n');
          for (var li = 0; li < lines.length; li++) {
            final line = lines[li];
            final matches = regex.hasMatch(line);
            final includeLine = invert ? !matches : matches;
            if (includeLine) {
              matchCount++;
              if (!countOnly) {
                if (files.length > 1 || recursive) {
                  output.write('$fileName:');
                }
                if (lineNumbers) output.write('${li + 1}:');
                output.writeln(line);
              }
            }
          }
        } on VfsNotFoundException {
          // skip
        } catch (e) {
          output.writeln('grep: $fileName: $e');
        }
      }

      if (files.isEmpty) {
        // No files — search all files in cwd (basic)
        final abs = _vfsAbsolute(_cwd);
        final dir = Directory(abs);
        if (dir.existsSync()) {
          for (final e in dir.listSync()) {
            if (e is File) {
              final name = p.basename(e.path);
              final vfsPath = _cwd == '/' ? '/$name' : '$_cwd/$name';
              searchFile(vfsPath, name);
            }
          }
        }
      } else {
        for (final file in files) {
          final target = _resolvePath(file);
          final abs = _vfsAbsolute(target);
          final type = FileSystemEntity.typeSync(abs);
          if (type == FileSystemEntityType.directory) {
            // Recursive search
            final dir = Directory(abs);
            try {
              await for (final e in dir.list(recursive: true)) {
                if (e is File) {
                  final rel = p.relative(e.path, from: _vfs.rootPath);
                  final vfsPath = '/$rel';
                  searchFile(vfsPath, rel);
                }
              }
            } catch (_) {}
          } else {
            searchFile(target, file);
          }
        }
      }

      if (countOnly) {
        output.write(matchCount.toString());
        if (files.length > 1 || recursive) output.writeln();
      }

      return ShellResult(
        exitCode: matchCount > 0 ? 0 : 1,
        stdout: output.toString(),
        stderr: '',
      );
    } catch (e) {
      return ShellResult(
        exitCode: 2,
        stdout: '',
        stderr: 'grep: invalid regex: $e',
      );
    }
  }

  // ===========================================================================
  // BUILT-IN: wc
  // ===========================================================================

  Future<ShellResult> _cmdWc(List<String> args) async {
    if (args.isEmpty) {
      return const ShellResult(
        exitCode: 1,
        stdout: '',
        stderr: 'wc: missing file operand',
      );
    }

    var totalLines = 0;
    var totalWords = 0;
    var totalChars = 0;
    final output = StringBuffer();

    for (final arg in args) {
      final target = _resolvePath(arg);
      try {
        final content = await _vfs.readFileAsString(target);
        final lines = content.split('\n');
        final lineCount = content.isEmpty ? 0 : content.endsWith('\n') ? lines.length - 1 : lines.length;
        final wordCount = content.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
        final charCount = content.length;

        totalLines += lineCount;
        totalWords += wordCount;
        totalChars += charCount;

        output.writeln(
            '${lineCount.toString().padLeft(7)}${wordCount.toString().padLeft(7)}${charCount.toString().padLeft(7)} $arg');
      } on VfsNotFoundException {
        output.writeln('wc: $arg: No such file');
      } catch (e) {
        output.writeln('wc: $arg: $e');
      }
    }

    if (args.length > 1) {
      output.writeln(
          '${totalLines.toString().padLeft(7)}${totalWords.toString().padLeft(7)}${totalChars.toString().padLeft(7)} total');
    }

    return ShellResult(exitCode: 0, stdout: output.toString(), stderr: '');
  }

  // ===========================================================================
  // BUILT-IN: sort
  // ===========================================================================

  Future<ShellResult> _cmdSort(List<String> args) async {
    var numeric = false;
    var reverse = false;
    var unique = false;
    var files = <String>[];
    var i = 0;

    while (i < args.length) {
      if (args[i] == '-n') { numeric = true; i++; } else if (args[i] == '-r') { reverse = true; i++; } else if (args[i] == '-u') { unique = true; i++; } else if (args[i].startsWith('-')) {
        return ShellResult(
          exitCode: 1,
          stdout: '',
          stderr: 'sort: invalid option: ${args[i]}',
        );
      } else {
        files.add(args[i]);
        i++;
      }
    }

    if (files.isEmpty) {
      return const ShellResult(
        exitCode: 1,
        stdout: '',
        stderr: 'sort: missing file operand',
      );
    }

    var allLines = <String>[];
    for (final file in files) {
      final target = _resolvePath(file);
      try {
        final content = await _vfs.readFileAsString(target);
        allLines.addAll(content.split('\n'));
      } on VfsNotFoundException {
        return ShellResult(
          exitCode: 1,
          stdout: '',
          stderr: 'sort: $file: No such file',
        );
      }
    }

    if (numeric) {
      allLines.sort((a, b) {
        final an = double.tryParse(a.trim()) ?? double.nan;
        final bn = double.tryParse(b.trim()) ?? double.nan;
        if (an.isNaN && bn.isNaN) return a.compareTo(b);
        if (an.isNaN) return 1;
        if (bn.isNaN) return -1;
        return an.compareTo(bn);
      });
    } else {
      allLines.sort();
    }

    if (reverse) allLines = allLines.reversed.toList();

    final output = StringBuffer();
    final seen = <String>{};
    for (final line in allLines) {
      if (unique) {
        if (seen.contains(line)) continue;
        seen.add(line);
      }
      output.writeln(line);
    }

    return ShellResult(exitCode: 0, stdout: output.toString(), stderr: '');
  }

  // ===========================================================================
  // BUILT-IN: printf
  // ===========================================================================

  Future<ShellResult> _cmdPrintf(List<String> args) async {
    if (args.isEmpty) {
      return const ShellResult(
        exitCode: 1,
        stdout: '',
        stderr: 'printf: usage: printf format [arguments...]',
      );
    }

    final format = args[0];
    final formatArgs = args.sublist(1);
    final output = StringBuffer();
    var argIdx = 0;

    for (var i = 0; i < format.length; i++) {
      if (format[i] == '\\' && i + 1 < format.length) {
        i++;
        switch (format[i]) {
          case 'n': output.write('\n');
          case 't': output.write('\t');
          case 'r': output.write('\r');
          case '\\': output.write('\\');
          case '"': output.write('"');
          case '0':
            // Octal escape
            if (i + 2 < format.length) {
              final octal = format.substring(i + 1, i + 3);
              output.write(String.fromCharCode(int.tryParse(octal, radix: 8) ?? 0));
              i += 2;
            } else {
              output.write('\x00');
            }
          default: output.write(format[i]);
        }
      } else if (format[i] == '%' && i + 1 < format.length) {
        i++;
        final spec = format[i];
        final arg = argIdx < formatArgs.length ? formatArgs[argIdx] : '';
        argIdx++;
        switch (spec) {
          case 's': output.write(arg); break;
          case 'd': output.write(int.tryParse(arg) ?? 0); break;
          case 'f': output.write(double.tryParse(arg)?.toStringAsFixed(6) ?? '0.000000'); break;
          case 'x': output.write((int.tryParse(arg) ?? 0).toRadixString(16)); break;
          case '%': output.write('%'); argIdx--; break;
          default: output.write('%$spec'); argIdx--;
        }
      } else {
        output.write(format[i]);
      }
    }

    return ShellResult(exitCode: 0, stdout: output.toString(), stderr: '');
  }

  // ===========================================================================
  // BUILT-IN: true / false
  // ===========================================================================

  Future<ShellResult> _cmdTrue(List<String> args) async {
    return const ShellResult(exitCode: 0, stdout: '', stderr: '');
  }

  Future<ShellResult> _cmdFalse(List<String> args) async {
    return const ShellResult(exitCode: 1, stdout: '', stderr: '');
  }

  // ===========================================================================
  // BUILT-IN: sleep
  // ===========================================================================

  Future<ShellResult> _cmdSleep(List<String> args) async {
    if (args.isEmpty) {
      return const ShellResult(
        exitCode: 1,
        stdout: '',
        stderr: 'sleep: missing operand',
      );
    }

    final seconds = double.tryParse(args[0]);
    if (seconds == null || seconds < 0) {
      return ShellResult(
        exitCode: 1,
        stdout: '',
        stderr: 'sleep: invalid time interval: ${args[0]}',
      );
    }

    await Future.delayed(Duration(milliseconds: (seconds * 1000).round()));
    return const ShellResult(exitCode: 0, stdout: '', stderr: '');
  }

  // ===========================================================================
  // BUILT-IN: export
  // ===========================================================================

  Future<ShellResult> _cmdExport(List<String> args) async {
    if (args.isEmpty) {
      final output = StringBuffer();
      final sorted = _env.keys.toList()..sort();
      for (final key in sorted) {
        output.writeln('export $key=${_env[key]}');
      }
      return ShellResult(exitCode: 0, stdout: output.toString(), stderr: '');
    }

    for (final arg in args) {
      if (arg.contains('=')) {
        final eq = arg.indexOf('=');
        final name = arg.substring(0, eq);
        var value = arg.substring(eq + 1);
        if ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'"))) {
          value = value.substring(1, value.length - 1);
        }
        _env[name] = value;
      }
    }

    return const ShellResult(exitCode: 0, stdout: '', stderr: '');
  }

  // ===========================================================================
  // BUILT-IN: unset
  // ===========================================================================

  Future<ShellResult> _cmdUnset(List<String> args) async {
    for (final arg in args) {
      _env.remove(arg);
    }
    return const ShellResult(exitCode: 0, stdout: '', stderr: '');
  }

  // ===========================================================================
  // BUILT-IN: env
  // ===========================================================================

  Future<ShellResult> _cmdEnv(List<String> args) async {
    final output = StringBuffer();
    final sorted = _env.keys.toList()..sort();
    for (final key in sorted) {
      output.writeln('$key=${_env[key]}');
    }
    return ShellResult(exitCode: 0, stdout: output.toString(), stderr: '');
  }

  // ===========================================================================
  // BUILT-IN: which
  // ===========================================================================

  Future<ShellResult> _cmdWhich(List<String> args) async {
    if (args.isEmpty) {
      return const ShellResult(exitCode: 1, stdout: '', stderr: '');
    }

    final output = StringBuffer();
    for (final arg in args) {
      if (_builtins.containsKey(arg)) {
        output.writeln('$arg: shell built-in command');
      } else {
        output.writeln('$arg: not found');
      }
    }

    return ShellResult(exitCode: 0, stdout: output.toString(), stderr: '');
  }

  // ===========================================================================
  // BUILT-IN: type
  // ===========================================================================

  Future<ShellResult> _cmdType(List<String> args) async {
    if (args.isEmpty) {
      return const ShellResult(exitCode: 1, stdout: '', stderr: '');
    }

    final output = StringBuffer();
    for (final arg in args) {
      if (_builtins.containsKey(arg)) {
        output.writeln('$arg is a shell builtin');
      } else {
        output.writeln('$arg is not found');
      }
    }

    return ShellResult(exitCode: 0, stdout: output.toString(), stderr: '');
  }

  // ===========================================================================
  // BUILT-IN: alias / unalias
  // ===========================================================================

  Future<ShellResult> _cmdAlias(List<String> args) async {
    if (args.isEmpty) {
      final output = StringBuffer();
      final sorted = _aliases.keys.toList()..sort();
      for (final key in sorted) {
        output.writeln('alias $key=\'${_aliases[key]}\'');
      }
      return ShellResult(exitCode: 0, stdout: output.toString(), stderr: '');
    }

    for (final arg in args) {
      if (arg.contains('=')) {
        final eq = arg.indexOf('=');
        final name = arg.substring(0, eq);
        var value = arg.substring(eq + 1);
        if ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'"))) {
          value = value.substring(1, value.length - 1);
        }
        _aliases[name] = value;
      }
    }

    return const ShellResult(exitCode: 0, stdout: '', stderr: '');
  }

  Future<ShellResult> _cmdUnalias(List<String> args) async {
    if (args.isEmpty) {
      return const ShellResult(
        exitCode: 1,
        stdout: '',
        stderr: 'unalias: usage: unalias name...',
      );
    }

    for (final arg in args) {
      _aliases.remove(arg);
    }

    return const ShellResult(exitCode: 0, stdout: '', stderr: '');
  }

  // ===========================================================================
  // BUILT-IN: clear / help
  // ===========================================================================

  Future<ShellResult> _cmdClear(List<String> args) async {
    return const ShellResult(exitCode: 0, stdout: '', stderr: '');
  }

  Future<ShellResult> _cmdHelp(List<String> args) async {
    return ShellResult(
      exitCode: 0,
      stdout: '''Kino VFS Shell — Built-in commands:
  cd [dir]        Change directory
  pwd             Print working directory
  echo [-nne] ... Print text
  ls [-la] [dir]  List directory
  cat file...     Print file contents
  mkdir [-p] dir  Create directory
  rm [-rf] file   Remove file/directory
  cp src dest     Copy file/directory
  mv src dest     Move/rename file/directory
  touch file...   Create/update file
  head [-n N] f   Show first N lines
  tail [-n N] f   Show last N lines
  grep [opts] p f Search file for pattern (-i, -n, -c, -v, -r)
  wc file...      Line/word/char count
  sort [-nru] f   Sort lines
  printf fmt ...  Formatted printing
  true            Return true (exit 0)
  false           Return false (exit 1)
  sleep N         Sleep N seconds
  export [n=v]    Set environment variable
  unset name      Unset environment variable
  env             Print environment
  which cmd       Show command location
  type cmd        Describe command
  alias [n=v]     Define or list aliases
  unalias name    Remove alias
  pushd [dir]     Push directory onto stack
  popd            Pop directory from stack
  dirs            Show directory stack
  source file     Execute commands from file
  clear           Clear screen
  help            This help

Features: variable expansion (\$VAR, \${VAR}, \$?), glob expansion (*, ?, [...]),
tilde expansion (~), alias expansion, &&/||/; chaining, pipe/redirect delegation.
Non-built-in commands are delegated to /bin/sh.''',
      stderr: '',
    );
  }

  // ===========================================================================
  // BUILT-IN: pushd / popd / dirs
  // ===========================================================================

  Future<ShellResult> _cmdPushd(List<String> args) async {
    if (args.isEmpty) return _cmdDirs(args);

    final target = _resolvePath(args[0]);
    final result = _changeDir(target);
    if (result.success) _dirStack.add(_previousCwd);
    return _cmdDirs(args);
  }

  Future<ShellResult> _cmdPopd(List<String> args) async {
    if (_dirStack.isEmpty) {
      return const ShellResult(
        exitCode: 1,
        stdout: '',
        stderr: 'popd: directory stack empty',
      );
    }

    final target = _dirStack.removeLast();
    final result = _changeDir(target);
    if (result.success) return _cmdDirs(args);
    return result;
  }

  Future<ShellResult> _cmdDirs(List<String> args) async {
    final stack = [_cwd, ..._dirStack.reversed];
    return ShellResult(
      exitCode: 0,
      stdout: '${stack.join(' ')}\n',
      stderr: '',
    );
  }

  // ===========================================================================
  // BUILT-IN: source
  // ===========================================================================

  Future<ShellResult> _cmdSource(List<String> args) async {
    if (args.isEmpty) {
      return const ShellResult(
        exitCode: 1,
        stdout: '',
        stderr: 'source: missing file argument',
      );
    }

    final target = _resolvePath(args[0]);
    try {
      final content = await _vfs.readFileAsString(target);
      final lines = content.split('\n');
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
        final result = await execute(trimmed);
        if (!result.success) return result;
      }
      return const ShellResult(exitCode: 0, stdout: '', stderr: '');
    } on VfsNotFoundException {
      return ShellResult(
        exitCode: 1,
        stdout: '',
        stderr: 'source: ${args[0]}: No such file',
      );
    }
  }

  // ===========================================================================
  // BUILT-IN: set
  // ===========================================================================

  Future<ShellResult> _cmdSet(List<String> args) async {
    // Without arguments, prints all variables and functions
    if (args.isEmpty) {
      final buf = StringBuffer();
      _env.forEach((k, v) => buf.writeln('$k=$v'));
      return ShellResult(exitCode: 0, stdout: buf.toString(), stderr: '');
    }

    // Parse options (simplified — just store flags)
    for (final arg in args) {
      if (arg == '-e' || arg == '-x' || arg == '-u' || arg == '-v') {
        _setFlags[arg] = true;
      } else if (arg.startsWith('+') &&
          (arg == '+e' || arg == '+x' || arg == '+u' || arg == '+v')) {
        _setFlags[arg.replaceFirst('+', '-')] = false;
      } else if (arg == '-o') {
        // ignore next arg, for now
      } else {
        // Positional parameter assignment
        break;
      }
    }
    return const ShellResult(exitCode: 0, stdout: '', stderr: '');
  }

  // ===========================================================================
  // BUILT-IN: exit / return / break / continue
  // ===========================================================================

  Future<ShellResult> _cmdExit(List<String> args) async {
    final code = args.isNotEmpty ? int.tryParse(args[0]) ?? 0 : 0;
    // Signal the shell to stop
    _exitRequested = true;
    return ShellResult(exitCode: code, stdout: '', stderr: '');
  }

  Future<ShellResult> _cmdReturn(List<String> args) async {
    final code = args.isNotEmpty ? int.tryParse(args[0]) ?? 0 : 0;
    return ShellResult(exitCode: code, stdout: '', stderr: '');
  }

  Future<ShellResult> _cmdBreak(List<String> args) async {
    return const ShellResult(exitCode: 0, stdout: '', stderr: '');
  }

  Future<ShellResult> _cmdContinue(List<String> args) async {
    return const ShellResult(exitCode: 0, stdout: '', stderr: '');
  }

  // ===========================================================================
  // BUILT-IN: test / [
  // ===========================================================================

  Future<ShellResult> _cmdTest(List<String> args) async {
    if (args.isEmpty) return _testFalse();

    var i = 0;
    if (args[0] == '!') {
      final innerResult = await _cmdTest(args.sublist(1));
      return innerResult.exitCode == 0 ? _testFalse() : _testTrue();
    }

    // -n STRING: string non-empty
    if (args[i] == '-n') {
      if (args.length < 2) return _testFalse();
      return args[1].isNotEmpty ? _testTrue() : _testFalse();
    }

    // -z STRING: string empty
    if (args[i] == '-z') {
      if (args.length < 2) return _testFalse();
      return args[1].isEmpty ? _testTrue() : _testFalse();
    }

    // -d FILE: exists and is directory
    if (args[i] == '-d') {
      if (args.length < 2) return _testFalse();
      final target = _resolvePath(args[1]);
      final abs = _vfsAbsolute(target);
      return FileSystemEntity.isDirectorySync(abs) ? _testTrue() : _testFalse();
    }

    // -f FILE: exists and is regular file
    if (args[i] == '-f') {
      if (args.length < 2) return _testFalse();
      final target = _resolvePath(args[1]);
      final abs = _vfsAbsolute(target);
      return FileSystemEntity.isFileSync(abs) ? _testTrue() : _testFalse();
    }

    // -e FILE: exists
    if (args[i] == '-e') {
      if (args.length < 2) return _testFalse();
      final target = _resolvePath(args[1]);
      final abs = _vfsAbsolute(target);
      return FileSystemEntity.typeSync(abs) != FileSystemEntityType.notFound
          ? _testTrue()
          : _testFalse();
    }

    // -s FILE: exists and is non-empty
    if (args[i] == '-s') {
      if (args.length < 2) return _testFalse();
      final target = _resolvePath(args[1]);
      final abs = _vfsAbsolute(target);
      try {
        final stat = File(abs).statSync();
        return stat.size > 0 ? _testTrue() : _testFalse();
      } catch (_) {
        return _testFalse();
      }
    }

    // -r FILE: readable
    if (args[i] == '-r') {
      if (args.length < 2) return _testFalse();
      final target = _resolvePath(args[1]);
      final abs = _vfsAbsolute(target);
      final stat = File(abs).statSync();
      return (stat.mode & 0x100) != 0 ? _testTrue() : _testFalse();
    }

    // -w FILE: writable
    if (args[i] == '-w') {
      if (args.length < 2) return _testFalse();
      final target = _resolvePath(args[1]);
      final abs = _vfsAbsolute(target);
      final stat = File(abs).statSync();
      return (stat.mode & 0x80) != 0 ? _testTrue() : _testFalse();
    }

    // -x FILE: executable
    if (args[i] == '-x') {
      if (args.length < 2) return _testFalse();
      final target = _resolvePath(args[1]);
      final abs = _vfsAbsolute(target);
      final stat = File(abs).statSync();
      return (stat.mode & 0x40) != 0 ? _testTrue() : _testFalse();
    }

    // STRING = STRING
    if (i + 2 < args.length && args[i + 1] == '=') {
      return args[i] == args[i + 2] ? _testTrue() : _testFalse();
    }

    // STRING != STRING
    if (i + 2 < args.length && args[i + 1] == '!=') {
      return args[i] != args[i + 2] ? _testTrue() : _testFalse();
    }

    // INTEGER -eq INTEGER (and -ne, -lt, -le, -gt, -ge)
    if (i + 2 < args.length) {
      final cmpOps = {'-eq', '-ne', '-lt', '-le', '-gt', '-ge'};
      if (cmpOps.contains(args[i + 1])) {
        final a = int.tryParse(args[i]);
        final b = int.tryParse(args[i + 2]);
        if (a == null || b == null) return _testFalse();
        bool cmp;
        switch (args[i + 1]) {
          case '-eq': cmp = a == b;
          case '-ne': cmp = a != b;
          case '-lt': cmp = a < b;
          case '-le': cmp = a <= b;
          case '-gt': cmp = a > b;
          case '-ge': cmp = a >= b;
          default: cmp = false;
        }
        return cmp ? _testTrue() : _testFalse();
      }
    }

    // Single string: true if non-empty
    return args[0].isNotEmpty ? _testTrue() : _testFalse();
  }

  Future<ShellResult> _cmdLeftBracket(List<String> args) async {
    // Remove the trailing ']' if present
    if (args.isNotEmpty && args.last == ']') {
      return _cmdTest(args.sublist(0, args.length - 1));
    }
    return _cmdTest(args);
  }

  ShellResult _testTrue() => const ShellResult(exitCode: 0, stdout: '', stderr: '');
  ShellResult _testFalse() => const ShellResult(exitCode: 1, stdout: '', stderr: '');

  // ===========================================================================
  // BUILT-IN: declare / local
  // ===========================================================================

  Future<ShellResult> _cmdDeclare(List<String> args) async {
    if (args.isEmpty) {
      // With no arguments, list all variables (like set)
      final buf = StringBuffer();
      _env.forEach((k, v) => buf.writeln('declare -- $k="$v"'));
      return ShellResult(exitCode: 0, stdout: buf.toString(), stderr: '');
    }

    var i = 0;
    // Parse flags (basic)
    while (i < args.length && args[i].startsWith('-')) {
      if (args[i] == '-p') { i++; continue; } // print attributes
      if (args[i] == '-a') { i++; continue; } // array
      if (args[i] == '-A') { i++; continue; } // associative array
      if (args[i] == '-i') { i++; continue; } // integer
      if (args[i] == '-r') { i++; continue; } // readonly
      if (args[i] == '-x') { i++; continue; } // export
      break;
    }

    // Assign variables: name=value
    for (; i < args.length; i++) {
      final eq = args[i].indexOf('=');
      if (eq > 0) {
        final name = args[i].substring(0, eq);
        final value = args[i].substring(eq + 1);
        _env[name] = value;
      } else if (eq != 0) {
        // Just a name: output its value if -p was given
        if (i > 0 && args[i - 1] == '-p') {
          final val = _lookupVar(args[i]);
          return ShellResult(
            exitCode: 0,
            stdout: 'declare -- ${args[i]}="$val"\n',
            stderr: '',
          );
        }
      }
    }

    return const ShellResult(exitCode: 0, stdout: '', stderr: '');
  }

  Future<ShellResult> _cmdLocal(List<String> args) async {
    // In our shell, 'local' is like 'declare' — assign scoped variables
    // Since we don't truly scope, just delegate to declare
    return _cmdDeclare(args);
  }

  // ===========================================================================
  // BUILT-IN: curl
  // ===========================================================================

  Future<ShellResult> _cmdCurl(List<String> args) async {
    if (args.isEmpty) {
      return const ShellResult(
        exitCode: 1, stdout: '',
        stderr: 'curl: try \'curl --help\' for more information',
      );
    }

    var url = '';
    var method = 'GET';
    final headers = <String, String>{};
    var data = '';
    var outputFile = '';
    var silent = false;
    var verbose = false;
    var includeHeaders = false;
    var followRedirects = false;
    var maxRedirects = 50;
    var timeoutSeconds = 30;

    var i = 0;
    while (i < args.length) {
      final arg = args[i];
      if (!arg.startsWith('-')) {
        url = arg;
        i++;
        continue;
      }

      if (arg == '--') { i++; break; }

      // -X / --request
      if (arg == '-X' || arg == '--request') {
        if (i + 1 >= args.length) return _curlError('$arg requires argument');
        method = args[i + 1].toUpperCase();
        i += 2;
        continue;
      }

      // -d / --data
      if (arg == '-d' || arg == '--data' || arg == '--data-raw') {
        if (i + 1 >= args.length) return _curlError('$arg requires argument');
        if (data.isNotEmpty) data += '&';
        data += args[i + 1];
        i += 2;
        continue;
      }

      // -H / --header
      if (arg == '-H' || arg == '--header') {
        if (i + 1 >= args.length) return _curlError('$arg requires argument');
        final hdr = args[i + 1];
        final colon = hdr.indexOf(':');
        if (colon > 0) {
          headers[hdr.substring(0, colon).trim()] = hdr.substring(colon + 1).trim();
        }
        i += 2;
        continue;
      }

      // -o / --output
      if (arg == '-o' || arg == '--output') {
        if (i + 1 >= args.length) return _curlError('$arg requires argument');
        outputFile = args[i + 1];
        i += 2;
        continue;
      }

      // -s / --silent
      if (arg == '-s' || arg == '--silent') { silent = true; i++; continue; }
      // -v / --verbose
      if (arg == '-v' || arg == '--verbose') { verbose = true; i++; continue; }
      // -i / --include
      if (arg == '-i' || arg == '--include') { includeHeaders = true; i++; continue; }
      // -L / --location
      if (arg == '-L' || arg == '--location') { followRedirects = true; i++; continue; }
      // --max-redirs
      if (arg == '--max-redirs') {
        if (i + 1 >= args.length) return _curlError('$arg requires argument');
        maxRedirects = int.tryParse(args[i + 1]) ?? 50;
        i += 2;
        continue;
      }
      // --connect-timeout
      if (arg == '--connect-timeout') {
        if (i + 1 >= args.length) return _curlError('$arg requires argument');
        timeoutSeconds = int.tryParse(args[i + 1]) ?? 30;
        i += 2;
        continue;
      }
      // -k / --insecure
      if (arg == '-k' || arg == '--insecure') { i++; continue; }

      // -f / --fail
      if (arg == '-f' || arg == '--fail') { i++; continue; }

      // Unknown flag
      return _curlError('curl: unknown option $arg');
    }

    if (url.isEmpty) return _curlError('curl: no URL specified');

    // Auto-set POST if data provided
    if (data.isNotEmpty && method == 'GET') method = 'POST';

    // Ensure URL has scheme
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }

    final parsed = Uri.tryParse(url);
    if (parsed == null) return _curlError('curl: malformed URL: $url');

    final errBuf = StringBuffer();
    if (!silent && verbose) errBuf.writeln('* Host: ${parsed.host}');
    if (!silent && verbose) errBuf.writeln('* Method: $method');
    if (!silent && verbose) errBuf.writeln('* URL: $url');

    try {
      var redirectCount = 0;
      var currentUri = parsed;
      late http.Response response;

      while (true) {
        final client = http.Client();
        try {
          final request = http.Request(method, currentUri);
          request.headers.addAll(headers);
          if (data.isNotEmpty) {
            request.body = data;
            if (!request.headers.containsKey('Content-Type')) {
              request.headers['Content-Type'] = 'application/x-www-form-urlencoded';
            }
          }

          final streamed = await client.send(request).timeout(
            Duration(seconds: timeoutSeconds),
          );
          response = await http.Response.fromStream(streamed);

          if (!silent && verbose) {
            errBuf.writeln('* HTTP ${response.statusCode}');
            for (final entry in response.headers.entries) {
              errBuf.writeln('< ${entry.key}: ${entry.value}');
            }
            errBuf.writeln('* Response body (${response.body.length} bytes)');
          }

          // Follow redirects
          if (followRedirects &&
              redirectCount < maxRedirects &&
              (response.statusCode == 301 ||
               response.statusCode == 302 ||
               response.statusCode == 303 ||
               response.statusCode == 307 ||
               response.statusCode == 308)) {
            final location = response.headers['location'];
            if (location != null && location.isNotEmpty) {
              redirectCount++;
              currentUri = currentUri.resolve(location);
              if (!silent && verbose) {
                errBuf.writeln('* Redirect #$redirectCount to: $currentUri');
              }
              client.close();
              continue;
            }
          }
        } finally {
          client.close();
        }
        break;
      }

      final responseBody = response.body;
      final responseHeaders = response.headers;

      var stdout = '';
      if (includeHeaders) {
        stdout += 'HTTP/${response.statusCode} ${response.reasonPhrase}\n';
        for (final entry in responseHeaders.entries) {
          stdout += '${entry.key}: ${entry.value}\n';
        }
        stdout += '\n';
      }
      stdout += responseBody;

      // Write to output file if requested
      if (outputFile.isNotEmpty) {
        final target = _resolvePath(outputFile);
        try {
          await _vfs.writeFile(target, responseBody);
        } catch (e) {
          return ShellResult(
            exitCode: 1,
            stdout: '',
            stderr: '${errBuf}curl: Failed to write to $outputFile: $e\n',
          );
        }
        if (silent) {
          stdout = '';
        } else if (!includeHeaders) {
          stdout = responseBody.length <= 1024 ? responseBody : '';
          if (responseBody.length > 1024) {
            errBuf.writeln(
              '* Response body written to $outputFile ($responseBody.length bytes)',
            );
          }
        }
      }

      final stderr = errBuf.toString();
      final exitCode = response.statusCode >= 400 ? 1 : 0;

      return ShellResult(exitCode: exitCode, stdout: stdout, stderr: stderr);
    } on SocketException catch (e) {
      return ShellResult(
        exitCode: 6, stdout: '',
        stderr: '${errBuf}curl: Could not resolve host: ${parsed.host} '
            '(${e.message})\n',
      );
    } on HttpException catch (e) {
      return ShellResult(
        exitCode: 7, stdout: '',
        stderr: '${errBuf}curl: Connection failed: ${e.message}\n',
      );
    } on TimeoutException {
      return ShellResult(
        exitCode: 28, stdout: '',
        stderr: '${errBuf}curl: Connection timed out after '
            '${timeoutSeconds}s\n',
      );
    } catch (e) {
      return ShellResult(
        exitCode: 1, stdout: '',
        stderr: '${errBuf}curl: Error: $e\n',
      );
    }
  }

  ShellResult _curlError(String msg) {
    return ShellResult(exitCode: 1, stdout: '', stderr: '$msg\n');
  }

  // ===========================================================================
  // UTILITIES
  // ===========================================================================

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

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)}K';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}M';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}G';
  }
}
