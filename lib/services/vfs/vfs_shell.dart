import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:collection';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../tool_execution.dart';
import 'vfs_service.dart';
import 'vfs_exception.dart';
import 'vfs_ast.dart';
import 'vfs_parser.dart';

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

class _BashRematch {
  List<String> matches = [];
  @override
  String toString() => matches.isEmpty ? '' : matches.join(' ');
}

class _Job {
  final int id;
  final String command;
  final Process process;
  String status; // 'running', 'stopped', 'done'
  int exitCode;

  _Job(this.id, this.command, this.process, this.status) : exitCode = -1;
}

enum _ArithTokType { num, var_, op, assign, eof }

class _ArithToken {
  final String value;
  final _ArithTokType type;
  final int radix;
  _ArithToken(this.value, this.type, {this.radix = 10});
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
  String _lastError = '';
  final Map<String, bool> _setFlags = {};

  final Map<String, String> _env = {
    'HOME': '/',
    'SHELL': '/bin/sh',
    'USER': 'kino',
    'TERM': 'xterm-256color',
    'PS1': r'\u@\h:\w\$ ',
    'PS2': '> ',
    'PS4': '+ ',
  };

  final Map<String, String> _aliases = {};

  // --- arrays and functions ---
  final Map<String, List<String>> _arrays = {};
  final Map<String, AstNode> _functions = {};
  final List<String> _history = [];
  final int _historyMax = 1000;

  // --- shell options (shopt) ---
  final Map<String, bool> _shopt = {
    'dotglob': false,
    'extglob': false,
    'nullglob': false,
    'failglob': false,
    'globstar': false,
    'nocaseglob': false,
    'histexpand': false,
    'cdable_vars': false,
    'cdspell': false,
    'checkwinsize': false,
    'cmdhist': true,
    'expand_aliases': true,
    'gnu_errfmt': false,
    'histappend': true,
    'hostcomplete': true,
    'huponexit': false,
    'interactive_comments': true,
    'lithist': false,
    'localvars': true,
    'mailwarn': false,
    'no_empty_cmd_completion': false,
    'norc': false,
    'restricted_shell': false,
    'shift_verbose': false,
    'sourcepath': true,
    'xpg_echo': false,
    'nocasematch': false,
    'pipefail': false,
    'autocd': false,
    'checkhash': false,
    'checkjobs': false,
    'direxpand': false,
    'dirspell': false,
    'execfail': false,
    'extdebug': false,
    'extquote': true,
    'force_fignore': true,
    'globskipdots': true,
    'histreedit': false,
    'histverify': false,
    'inherit_errexit': false,
    'lastpipe': false,
    'login_shell': false,
    'noexpand_translation': false,
    'patsub_replacement': false,
    'progcomp': true,
    'progcomp_alias': false,
    'promptvars': true,
    'syslog_history': false,
  };

  // --- execution context for AST evaluation ---
  int _breakDepth = 0;
  int _continueDepth = 0;
  bool _returnFromFunction = false;
  bool _exitRequested = false;

  final Map<String, Map<String, String>> _assocArrays = {};
  int _nextJobId = 1;
  String? _globIgnore;
  final Map<String, List<String>> _completions = {};
  final Map<int, _Job> _jobs = {};
  final _BashRematch _bashRematch = _BashRematch();
  List<String> _positionalParams = [];
  int _lastBgPid = 0;
  int _getoptsIndex = 0;
  int _getoptsPos = 0;

  final Stopwatch _shellTimer = Stopwatch()..start();

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
    // Expand PS1 prompt escapes if this looks like a prompt display
    if (_env.containsKey('PS1') && command.isEmpty) {
      return ShellResult(exitCode: 0, stdout: _expandPrompt(_env['PS1']!), stderr: '');
    }
    final trimmed = command.trim();
    if (trimmed.isEmpty) {
      return const ShellResult(exitCode: 0, stdout: '', stderr: '');
    }

    _history.add(trimmed);
    if (_history.length > _historyMax) {
      _history.removeRange(0, _history.length - _historyMax);
    }
    _underscore = trimmed.split(RegExp(r'\s+')).lastOrNull ?? '';

    try {
      // Check for control flow keywords or reserved words
      if (_containsControlFlow(trimmed)) {
        String input = _expandAliases(trimmed);
        try {
          final parser = ShellParser.tryParse(input);
          if (parser != null) {
            final ast = parser.parse();
            final result = await _executeAst(ast);
            _lastExitCode = result.exitCode;
            _pipeStatusString = _lastExitCode.toString();
            if (_exitRequested) _exitRequested = false;
            return result;
          }
        } catch (_) {
          // Parsing failed — fall through to system shell below
        }
        // Parser couldn't handle it; run full command through system shell
        final result = await _runInShell(input);
        _lastExitCode = result.exitCode;
        _pipeStatusString = _lastExitCode.toString();
        return result;
      }

      // Existing path for simple commands
      String input = _expandAliases(trimmed);
      final segments = _splitCompound(input);
      final result = await _executeChain(segments, 0);
      _pipeStatusString = _lastExitCode.toString();
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
    } finally {
      if (_traps.containsKey('EXIT')) {
        await _executeTrap('EXIT');
      }
    }
  }

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
    if (RegExp(r'\b(if|for|while|until|case|function|then|else|elif|fi|do|done|esac|select)\b').hasMatch(cmd)) {
      return true;
    }
    return false;
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

    if (_functions.containsKey(firstWord)) {
      final ast = _functions[firstWord]!;
      final funcResult = await _executeAstInner(ast);
      _returnFromFunction = false;
      return funcResult;
    }

    return _runInShell(cmd);
  }

  /// Execute a command that has already been tokenized (by the shell parser).
  /// Expands each word (variables, tilde, globs) and dispatches to builtins,
  /// functions, or the real shell.
  Future<ShellResult> _executePreTokenized(List<String> words) async {
    // Expand variables in all words (the parser already handled quote stripping)
    final expanded = <String>[];
    for (var i = 0; i < words.length; i++) {
      var w = words[i];
      w = _expandVars(w);
      w = _expandTilde(w);
      expanded.add(w);
    }

    if (expanded.isEmpty) return _okResult;
    final cmd = expanded[0];
    final args = expanded.sublist(1);

    // Check for 'cd' specially (it needs cwd tracking)
    if (cmd == 'cd' && expanded.length <= 2) {
      return _handleCd('cd ${args.isNotEmpty ? args[0] : ''}');
    }

    if (_builtins.containsKey(cmd)) {
      // Apply brace + glob expansion to args
      final finalArgs = <String>[];
      for (final arg in args) {
        for (final braced in _expandBraces(arg)) {
          final globbed = _expandGlob(braced);
          finalArgs.addAll(globbed);
        }
      }
      _underscore = finalArgs.isNotEmpty ? finalArgs.last : cmd;
      return _builtins[cmd]!(finalArgs);
    }

    if (_functions.containsKey(cmd)) {
      final ast = _functions[cmd]!;
      // Save positional params
      final savedParams = List<String>.from(_positionalParams);
      // Set positional params to the function arguments
      _positionalParams = args;
      _env['@'] = args.join(' ');
      _env['#'] = _positionalParams.length.toString();
      final funcResult = await _executeAstInner(ast);
      _returnFromFunction = false;
      // Restore positional params
      _positionalParams = savedParams;
      _env['@'] = savedParams.join(' ');
      _env['#'] = savedParams.length.toString();
      return funcResult;
    }

    // Fallback: delegate to real shell
    final fullCmd = expanded.join(' ');
    return _runInShell(fullCmd);
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
  /// pipes (|), backgrounding (&), heredocs (<<), and subcommands ($( ) ``).
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

      // Here-document: << (but not <<< which is a here-string)
      if (c == '<' && i + 1 < cmd.length && cmd[i + 1] == '<') {
        if (i + 2 < cmd.length && cmd[i + 2] == '<') {
          // <<< is a here-string, we handle that natively
          i += 2;
          continue;
        }
        return true; // << heredoc -> delegate to real shell
      }
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
  // AST EXECUTOR
  // ===========================================================================

  Future<ShellResult> _executeAst(AstNode node) async {
    try {
      return _executeAstInner(node);
    } catch (e) {
      return ShellResult(
        exitCode: -1,
        stdout: '',
        stderr: 'Shell error: $e',
      );
    }
  }

  Future<ShellResult> _executeAstInner(AstNode node) async {
    switch (node) {
      case ProgramNode n:
        ShellResult last = const ShellResult(exitCode: 0, stdout: '', stderr: '');
        for (final stmt in n.statements) {
          last = await _executeAstInner(stmt);
          if (_returnFromFunction || _exitRequested) break;
        }
        return last;

      case SeqNode n:
        ShellResult last = const ShellResult(exitCode: 0, stdout: '', stderr: '');
        for (final stmt in n.nodes) {
          last = await _executeAstInner(stmt);
          if (_returnFromFunction || _exitRequested) break;
        }
        return last;

      case AndOrNode n:
        final left = await _executeAstInner(n.left);
        if (n.op == AndOrOp.and) {
          if (left.exitCode == 0) return await _executeAstInner(n.right);
          return left;
        } else {
          if (left.exitCode != 0) return await _executeAstInner(n.right);
          return left;
        }

      case PipelineNode n:
        if (n.commands.isEmpty) return _okResult;
        if (n.commands.length == 1) return await _executeAstInner(n.commands.first);
        final cmdStrs = <String>[];
        for (final cmd in n.commands) {
          if (cmd is SimpleCmdNode) {
            cmdStrs.add(cmd.words.join(' '));
          } else {
            return _runInShell(n.commands.map((c) => _astToString(c)).join(' | '));
          }
        }
        final result = await _runInShell(cmdStrs.join(' | '));
        if (_shopt['pipefail'] == true && result.exitCode != 0) {
          return result;
        }
        return result;

      case BackgroundNode n:
        final cmdStr = _astToString(n.command);
        final jobId = _nextJobId++;
        final proc = await Process.start('/bin/sh', ['-c', cmdStr],
            workingDirectory: _cwd,
            environment: Map<String, String>.from(_env));
        _jobs[jobId] = _Job(jobId, cmdStr, proc, 'running');
        _lastBgPid = proc.pid;
        unawaited(proc.exitCode.then((code) {
          if (_jobs.containsKey(jobId)) {
            _jobs[jobId]!.status = 'done';
            _jobs[jobId]!.exitCode = code;
          }
        }));
        _writeToStdout('[$jobId] $jobId\n');
        return _okResult;

      case SimpleCmdNode n:
        if (n.words.isEmpty) {
          if (n.redirects.isNotEmpty) {
            return _executeRedirectsOnly(n.redirects);
          }
          return _okResult;
        }
        return _executePreTokenized(n.words);

      case IfNode n:
        final condResult = await _executeAstInner(n.condition);
        if (condResult.exitCode == 0) {
          return await _executeAstInner(n.thenBody);
        }
        for (final elif in n.elifs) {
          final elifResult = await _executeAstInner(elif.condition);
          if (elifResult.exitCode == 0) {
            return await _executeAstInner(elif.body);
          }
        }
        if (n.elseBody != null) {
          return await _executeAstInner(n.elseBody!);
        }
        return _okResult;

      case WhileNode n:
        while (true) {
          final condResult = await _executeAstInner(n.condition);
          if (condResult.exitCode != 0) break;
          if (_breakDepth > 0) { _breakDepth--; break; }
          if (_continueDepth > 0) { _continueDepth = 0; continue; }
          if (_returnFromFunction || _exitRequested) break;
          await _executeAstInner(n.body);
          if (_breakDepth > 0) { _breakDepth--; break; }
          if (_continueDepth > 0) { _continueDepth = 0; continue; }
        }
        return _okResult;

      case UntilNode n:
        while (true) {
          final condResult = await _executeAstInner(n.condition);
          if (condResult.exitCode == 0) break;
          if (_breakDepth > 0) { _breakDepth--; break; }
          if (_continueDepth > 0) { _continueDepth = 0; continue; }
          if (_returnFromFunction || _exitRequested) break;
          await _executeAstInner(n.body);
          if (_breakDepth > 0) { _breakDepth--; break; }
          if (_continueDepth > 0) { _continueDepth = 0; continue; }
        }
        return _okResult;

      case ForNode n:
        final words = n.words.isNotEmpty ? n.words : _env['@']?.split(' ') ?? [];
        for (final word in words) {
          _env[n.variable] = word;
          if (_returnFromFunction || _exitRequested) break;
          await _executeAstInner(n.body);
          if (_breakDepth > 0) { _breakDepth--; break; }
          if (_continueDepth > 0) { _continueDepth = 0; continue; }
        }
        return _okResult;

      case CaseNode n:
        for (final item in n.items) {
          for (final pattern in item.patterns) {
            if (_matchCasePattern(n.word, pattern)) {
              return await _executeAstInner(item.body);
            }
          }
        }
        return _okResult;

      case FunctionDefNode n:
        _functions[n.name] = n.body;
        return _okResult;

      case BlockNode n:
        return await _executeAstInner(n.body);

      case SubshellNode n:
        return _runInShell(n.toString());

      case AssignmentNode n:
        _env[n.name] = n.value;
        return _okResult;

      case ArrayAssignmentNode n:
        _arrays[n.name] = n.values;
        return _okResult;

      case BreakNode n:
        _breakDepth = n.count;
        return _okResult;

      case ContinueNode n:
        _continueDepth = n.count;
        return _okResult;

      case ReturnNode n:
        _returnFromFunction = true;
        return ShellResult(exitCode: n.code, stdout: '', stderr: '');

      case ExitNode n:
        _exitRequested = true;
        return ShellResult(exitCode: n.code, stdout: '', stderr: '');

      case CForNode n:
        // Save any variables that init might set
        if (n.init != null && n.init!.contains('=')) {
          final parts = n.init!.split('=');
          if (parts.length >= 2) {
            _env[parts[0].trim()] = parts.sublist(1).join('=');
          }
        }
        bool evalCond(String? cond) {
          if (cond == null || cond.isEmpty) return true;
          final val = _evalArithmetic(cond);
          return val != 0;
        }
        while (evalCond(n.condition)) {
          if (_breakDepth > 0) { _breakDepth--; break; }
          if (_continueDepth > 0) { _continueDepth = 0; break; }
          if (_returnFromFunction || _exitRequested) break;
          await _executeAstInner(n.body);
          if (_breakDepth > 0) { _breakDepth--; break; }
          if (_continueDepth > 0) { _continueDepth = 0; break; }
          if (n.increment != null && n.increment!.isNotEmpty) {
            _evalArithmetic(n.increment!);
          }
        }
        return _okResult;

      case SelectNode n:
        final items = n.words.isNotEmpty
            ? n.words
            : (_env['@']?.split(' ') ?? []);
        if (items.isEmpty) return _okResult;
        while (true) {
          for (var idx = 0; idx < items.length; idx++) {
            _writeToStdout('${idx + 1}) ${items[idx]}\n');
          }
          _writeToStdout('#? ');
          final line = stdin.readLineSync();
          if (line == null) break;
          if (line.isEmpty) continue;
          final choice = int.tryParse(line);
          if (choice != null && choice >= 1 && choice <= items.length) {
            _env[n.variable] = items[choice - 1];
            _env['REPLY'] = line;
          } else {
            _env['REPLY'] = line;
            _env[n.variable] = '';
          }
          await _executeAstInner(n.body);
          if (_breakDepth > 0) { _breakDepth--; break; }
          if (_returnFromFunction || _exitRequested) break;
        }
        return _okResult;

      case CoprocNode n:
        final cmdStr = _astToString(n.body);
        final proc = await Process.start('/bin/sh', ['-c', cmdStr],
            workingDirectory: _cwd,
            environment: Map<String, String>.from(_env));
        _env['${n.name}_PID'] = proc.pid.toString();
        unawaited(proc.exitCode.then((_) {}));
        return _okResult;
    }
  }

  void _writeToStdout(String s) {
    stdout.write(s);
  }

  String _astToString(AstNode node) {
    final buf = StringBuffer();
    _astToStringBuf(node, buf);
    return buf.toString();
  }

  void _astToStringBuf(AstNode node, StringBuffer buf) {
    switch (node) {
      case SimpleCmdNode n:
        for (var i = 0; i < n.words.length; i++) {
          if (i > 0) buf.write(' ');
          buf.write(n.words[i]);
        }
      case ProgramNode n:
        for (var i = 0; i < n.statements.length; i++) {
          if (i > 0) buf.write('; ');
          _astToStringBuf(n.statements[i], buf);
        }
      case SeqNode n:
        for (var i = 0; i < n.nodes.length; i++) {
          if (i > 0) buf.write('; ');
          _astToStringBuf(n.nodes[i], buf);
        }
      case BlockNode n:
        buf.write('{ ');
        _astToStringBuf(n.body, buf);
        buf.write('; }');
      case SubshellNode n:
        buf.write('( ');
        _astToStringBuf(n.body, buf);
        buf.write(' )');
      case IfNode n:
        buf.write('if '); _astToStringBuf(n.condition, buf);
        buf.write('; then '); _astToStringBuf(n.thenBody, buf);
        for (final elif in n.elifs) {
          buf.write('; elif '); _astToStringBuf(elif.condition, buf);
          buf.write('; then '); _astToStringBuf(elif.body, buf);
        }
        if (n.elseBody != null) { buf.write('; else '); _astToStringBuf(n.elseBody!, buf); }
        buf.write('; fi');
      case ForNode n:
        buf.write('for ${n.variable} in ${n.words.join(" ")}; do ');
        _astToStringBuf(n.body, buf);
        buf.write('; done');
      case WhileNode n:
        buf.write('while '); _astToStringBuf(n.condition, buf);
        buf.write('; do '); _astToStringBuf(n.body, buf);
        buf.write('; done');
      case UntilNode n:
        buf.write('until '); _astToStringBuf(n.condition, buf);
        buf.write('; do '); _astToStringBuf(n.body, buf);
        buf.write('; done');
      case CaseNode n:
        buf.write('case ${n.word} in ');
        for (final item in n.items) {
          buf.write('${item.patterns.join("|")}) ');
          _astToStringBuf(item.body, buf);
          buf.write(' ;; ');
        }
        buf.write('esac');
      case FunctionDefNode n:
        buf.write('${n.name} () { ');
        _astToStringBuf(n.body, buf);
        buf.write('; }');
      default:
        buf.write(node.toString());
    }
  }

  ShellResult get _okResult =>
      const ShellResult(exitCode: 0, stdout: '', stderr: '');

  Future<ShellResult> _executeRedirectsOnly(List<RedirectNode> redirects) async {
    var stdout = '';
    var stderr = '';
    for (final r in redirects) {
      final target = _resolvePath(r.target);
      final abs = _vfsAbsolute(target);
      if (r.srcFd == -1 || r.op == '&>') {
        final content = '${stdout.trim()}\n${stderr.trim()}'.trim();
        await _vfs.writeFile(target, content);
        stdout = '';
        stderr = '';
      } else if (r.isOutput) {
        if (r.isAppend) {
          final existing = _existingContent(abs);
          stdout = existing.isNotEmpty ? '$existing\n$stdout' : stdout;
        }
        await _vfs.writeFile(target, stdout);
        stdout = '';
      } else if (r.isInput && r.isHereStr) {
        stdout = r.target;
      }
    }
    return ShellResult(exitCode: 0, stdout: stdout, stderr: stderr);
  }

  bool _matchCasePattern(String word, String pattern) {
    if (pattern == '*') return true;
    if (pattern == word) return true;
    try {
      final caseSensitive = _shopt['nocasematch'] != true;
      final regex = RegExp('^${_globToRegexStr(pattern)}\$', caseSensitive: caseSensitive);
      return regex.hasMatch(word);
    } catch (_) {
      return word == pattern;
    }
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

      // $!
      if (s[i] == '!') {
        result.write(_lastBgPid);
        continue;
      }

      // $0 — shell name
      if (s[i] == '0') {
        result.write('kino');
        continue;
      }

      // $#
      if (s[i] == '#') {
        result.write(_positionalParams.length);
        continue;
      }

      // $@
      if (s[i] == '@') {
        result.write(_positionalParams.join(' '));
        continue;
      }

      // $*
      if (s[i] == '*') {
        result.write(_positionalParams.join(' '));
        continue;
      }

      // $1-$9 — positional params
      if (s[i].codeUnitAt(0) >= 49 && s[i].codeUnitAt(0) <= 57) {
        final idx = int.parse(s[i]) - 1;
        result.write(idx < _positionalParams.length ? _positionalParams[idx] : '');
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
    // ${#arr[@]} or ${#arr[*]} — array element count
    if (contents.startsWith('#')) {
      final rest = contents.substring(1);
      // Check for array length: ${#arr[@]} or ${#arr[*]}
      if (rest.endsWith('[@]') || rest.endsWith('[*]')) {
        final arrName = rest.substring(0, rest.length - 3);
        if (_assocArrays.containsKey(arrName)) {
          return _assocArrays[arrName]!.length.toString();
        }
        if (_arrays.containsKey(arrName)) {
          return _arrays[arrName]!.length.toString();
        }
        return '0';
      }
      final varName = _extractVarName(rest);
      final val = _lookupVar(varName);
      return val.length.toString();
    }

    // Check for array key lookup: ${arr[key]}
    final bracketOpen = contents.indexOf('[');
    if (bracketOpen > 0 && contents.endsWith(']')) {
      final arrName = contents.substring(0, bracketOpen);
      final key = contents.substring(bracketOpen + 1, contents.length - 1);
      if (_assocArrays.containsKey(arrName)) {
        return _assocArrays[arrName]![key] ?? '';
      }
      if (_arrays.containsKey(arrName)) {
        final idx = int.tryParse(key);
        if (idx != null && idx >= 0 && idx < _arrays[arrName]!.length) {
          return _arrays[arrName]![idx];
        }
        return '';
      }
      return '';
    }

    // ${!var} — indirect expansion
    // ${!prefix*} — expand to variable names matching prefix
    // ${!name[@]} — expand to keys/indices of array
    if (contents.startsWith('!')) {
      final inner = contents.substring(1);
      // ${!name[@]} or ${!name[*]} — list array keys
      if (inner.endsWith('[@]') || inner.endsWith('[*]')) {
        final arrName = inner.substring(0, inner.length - 3);
        if (_assocArrays.containsKey(arrName)) {
          return _assocArrays[arrName]!.keys.join(' ');
        }
        if (_arrays.containsKey(arrName)) {
          return List.generate(_arrays[arrName]!.length, (i) => i.toString()).join(' ');
        }
        return '';
      }
      // ${!prefix*} or ${!prefix@} — variable names matching prefix
      if (!_isSimpleVarName(inner)) {
        final prefix = inner;
        final matching = <String>[];
        for (final key in _env.keys) {
          if (key.startsWith(prefix)) matching.add(key);
        }
        for (final key in _arrays.keys) {
          if (key.startsWith(prefix)) matching.add(key);
        }
        for (final key in _assocArrays.keys) {
          if (key.startsWith(prefix)) matching.add(key);
        }
        matching.sort();
        return matching.join(' ');
      }
      final innerVal = _lookupVar(inner);
      return _lookupVar(innerVal);
    }

    // Array slicing: ${arr[@]:offset:length} or ${arr[*]:offset:length}
    final sliceMatch = RegExp(r'^([_a-zA-Z][_a-zA-Z0-9]*)\[@\]:(\d+)(?::(\d+))?$').firstMatch(contents);
    if (sliceMatch != null) {
      final arrName = sliceMatch.group(1)!;
      final offset = int.parse(sliceMatch.group(2)!);
      final length = sliceMatch.group(3) != null ? int.parse(sliceMatch.group(3)!) : null;
      if (_arrays.containsKey(arrName)) {
        final arr = _arrays[arrName]!;
        if (offset >= arr.length) return '';
        final slice = length != null
            ? arr.sublist(offset, (offset + length).clamp(0, arr.length))
            : arr.sublist(offset);
        return slice.join(' ');
      }
      if (_assocArrays.containsKey(arrName)) {
        final entries = _assocArrays[arrName]!.entries.toList();
        if (offset >= entries.length) return '';
        final slice = length != null
            ? entries.sublist(offset, (offset + length).clamp(0, entries.length))
            : entries.sublist(offset);
        return slice.map((e) => e.value).join(' ');
      }
    }
    final sliceStarMatch = RegExp(r'^([_a-zA-Z][_a-zA-Z0-9]*)\[\*\]:(\d+)(?::(\d+))?$').firstMatch(contents);
    if (sliceStarMatch != null) {
      final arrName = sliceStarMatch.group(1)!;
      final offset = int.parse(sliceStarMatch.group(2)!);
      final length = sliceStarMatch.group(3) != null ? int.parse(sliceStarMatch.group(3)!) : null;
      if (_arrays.containsKey(arrName)) {
        final arr = _arrays[arrName]!;
        if (offset >= arr.length) return '';
        final slice = length != null
            ? arr.sublist(offset, (offset + length).clamp(0, arr.length))
            : arr.sublist(offset);
        return slice.join(' ');
      }
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
    final regex = RegExp('^${_globToRegexStr(pattern)}\$');
    for (var i = 1; i <= value.length; i++) {
      if (regex.hasMatch(value.substring(0, i))) return value.substring(i);
    }
    return value;
  }

  String _removeLongestPrefix(String value, String pattern) {
    final regex = RegExp('^${_globToRegexStr(pattern)}\$');
    for (var i = value.length; i >= 0; i--) {
      if (regex.hasMatch(value.substring(0, i))) return value.substring(i);
    }
    return value;
  }

  String _removeShortestSuffix(String value, String pattern) {
    final regex = RegExp('^${_globToRegexStr(pattern)}\$');
    for (var i = value.length; i >= 0; i--) {
      if (regex.hasMatch(value.substring(i))) return value.substring(0, i);
    }
    return value;
  }

  String _removeLongestSuffix(String value, String pattern) {
    final regex = RegExp('^${_globToRegexStr(pattern)}\$');
    for (var i = 0; i <= value.length; i++) {
      if (regex.hasMatch(value.substring(i))) return value.substring(0, i);
    }
    return value;
  }

  // ===========================================================================
  // ARITHMETIC EXPANSION $((expression))
  // ===========================================================================
  //
  // Full recursive-descent parser with correct operator precedence:
  //
  //   1  ,        (comma)
  //   2  =  *=  /=  %=  +=  -=  <<=  >>=  &=  ^=  |=
  //   3  ? :      (ternary)
  //   4  ||       (logical OR)
  //   5  &&       (logical AND)
  //   6  |        (bitwise OR)
  //   7  ^        (bitwise XOR)
  //   8  &        (bitwise AND)
  //   9  ==  !=   (equality)
  //   10  <  <=  >  >=  (relational)
  //   11  <<  >>  (shift)
  //   12  +  -    (addition/subtraction)
  //   13  *  /  % (multiplication/division/modulo)
  //   14  **      (exponentiation, right-associative)
  //   15  !  ~  ++prefix  --prefix  unary+  unary-
  //   16  ++postfix  --postfix
  //   17  ( )     (grouping)

  int _evalArithmetic(String expr) {
    try {
      final trimmed = expr.trim();
      if (trimmed.isEmpty) return 0;
      return _parseArithExpr(trimmed);
    } catch (_) {
      return 0;
    }
  }

  int _parseArithExpr(String s) {
    final tokens = _tokenizeArith(s);
    _arithPos = 0;
    _arithTokensList = tokens;
    return _parseArithComma();
  }

  int _arithPos = 0;
  List<_ArithToken> _arithTokensList = [];

  List<_ArithToken> _tokenizeArith(String s) {
    final tokens = <_ArithToken>[];
    var i = 0;
    const multiOps = [
      '**', '<<=', '>>=', '<<', '>>', '==', '!=', '<=', '>=',
      '&&', '||', '++', '--', '+=', '-=', '*=', '/=', '%=', '&=', '^=', '|=',
    ];
    const assignOps = {
      '=', '+=', '-=', '*=', '/=', '%=', '<<=', '>>=', '&=', '^=', '|=',
    };

    while (i < s.length) {
      if (s[i] == ' ' || s[i] == '\t') { i++; continue; }

      if (i + 1 < s.length) {
        final two = s.substring(i, i + 2);
        String? match;
        if (i + 2 < s.length) {
          final three = s.substring(i, i + 3);
          if (multiOps.contains(three)) match = three;
        }
        match ??= multiOps.contains(two) ? two : null;
        if (match != null) {
          tokens.add(_ArithToken(match,
              assignOps.contains(match) ? _ArithTokType.assign : _ArithTokType.op));
          i += match.length;
          continue;
        }
      }

      if ('+-*/%&|^~!<>=()?,:'.contains(s[i])) {
        final ch = s[i];
        if (ch == '=') {
          tokens.add(_ArithToken('=', _ArithTokType.assign));
        } else {
          tokens.add(_ArithToken(ch, _ArithTokType.op));
        }
        i++;
        continue;
      }

      if (_isDigit(s[i])) {
        final start = i;
        while (i < s.length && _isDigit(s[i])) { i++; }
        String numStr = s.substring(start, i);
        int radix = 10;
        if (numStr == '0' && i < s.length && (s[i] == 'x' || s[i] == 'X')) {
          i++;
          final hexStart = i;
          while (i < s.length && _isHexDigit(s[i])) { i++; }
          numStr = s.substring(hexStart, i);
          radix = 16;
          if (numStr.isEmpty) numStr = '0';
        }
        tokens.add(_ArithToken(numStr, _ArithTokType.num, radix: radix));
        continue;
      }

      if (_isVarChar(s[i], first: true)) {
        final start = i;
        while (i < s.length && _isVarChar(s[i])) { i++; }
        tokens.add(_ArithToken(s.substring(start, i), _ArithTokType.var_));
        continue;
      }

      i++;
    }
    return tokens;
  }

  bool _isDigit(String c) {
    if (c.isEmpty) return false;
    final code = c.codeUnitAt(0);
    return code >= 48 && code <= 57;
  }

  bool _isHexDigit(String c) =>
      (c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57) ||
      (c.codeUnitAt(0) >= 65 && c.codeUnitAt(0) <= 70) ||
      (c.codeUnitAt(0) >= 97 && c.codeUnitAt(0) <= 102);

  _ArithToken _arithPeek() =>
      _arithPos < _arithTokensList.length
          ? _arithTokensList[_arithPos]
          : _ArithToken('', _ArithTokType.eof);

  _ArithToken _arithAdvance() => _arithTokensList[_arithPos++];

  bool _arithMatch(String v) {
    if (_arithPeek().value == v) {
      _arithAdvance();
      return true;
    }
    return false;
  }

  int _parseArithComma() {
    var left = _parseArithAssign();
    while (_arithPeek().value == ',') {
      _arithAdvance();
      left = _parseArithAssign();
    }
    return left;
  }

  int _parseArithAssign() {
    if (_arithPeek().type == _ArithTokType.var_) {
      final savedPos = _arithPos;
      final varToken = _arithAdvance();
      if (_arithPeek().type == _ArithTokType.assign) {
        final op = _arithAdvance().value;
        final right = _parseArithAssign();
        final name = varToken.value;
        final val = right;
        switch (op) {
          case '=':
            _env[name] = val.toString();
          case '+=':
            _env[name] = (_getArithVar(name) + val).toString();
          case '-=':
            _env[name] = (_getArithVar(name) - val).toString();
          case '*=':
            _env[name] = (_getArithVar(name) * val).toString();
          case '/=':
            _env[name] = (val == 0 ? 0 : _getArithVar(name) ~/ val).toString();
          case '%=':
            _env[name] = (val == 0 ? 0 : _getArithVar(name) % val).toString();
          case '<<=':
            _env[name] = (_getArithVar(name) << val).toString();
          case '>>=':
            _env[name] = (_getArithVar(name) >> val).toString();
          case '&=':
            _env[name] = (_getArithVar(name) & val).toString();
          case '^=':
            _env[name] = (_getArithVar(name) ^ val).toString();
          case '|=':
            _env[name] = (_getArithVar(name) | val).toString();
        }
        return val;
      }
      _arithPos = savedPos;
    }
    return _parseArithTernary();
  }

  int _parseArithTernary() {
    var left = _parseArithLor();
    if (_arithMatch('?')) {
      final trueVal = _parseArithTernary();
      _arithExpect(':');
      final falseVal = _parseArithTernary();
      return left != 0 ? trueVal : falseVal;
    }
    return left;
  }

  int _parseArithLor() {
    var left = _parseArithLand();
    while (_arithMatch('||')) {
      final right = _parseArithLand();
      left = (left != 0 || right != 0) ? 1 : 0;
    }
    return left;
  }

  int _parseArithLand() {
    var left = _parseArithBor();
    while (_arithMatch('&&')) {
      final right = _parseArithBor();
      left = (left != 0 && right != 0) ? 1 : 0;
    }
    return left;
  }

  int _parseArithBor() {
    var left = _parseArithXor();
    while (_arithMatch('|')) {
      final right = _parseArithXor();
      left = left | right;
    }
    return left;
  }

  int _parseArithXor() {
    var left = _parseArithBand();
    while (_arithMatch('^')) {
      final right = _parseArithBand();
      left = left ^ right;
    }
    return left;
  }

  int _parseArithBand() {
    var left = _parseArithEq();
    while (_arithMatch('&')) {
      final right = _parseArithEq();
      left = left & right;
    }
    return left;
  }

  int _parseArithEq() {
    var left = _parseArithRel();
    while (true) {
      if (_arithMatch('==')) {
        final r = _parseArithRel();
        left = left == r ? 1 : 0;
      } else if (_arithMatch('!=')) {
        final r = _parseArithRel();
        left = left != r ? 1 : 0;
      } else {
        break;
      }
    }
    return left;
  }

  int _parseArithRel() {
    var left = _parseArithShift();
    while (true) {
      if (_arithMatch('<=')) {
        final r = _parseArithShift();
        left = left <= r ? 1 : 0;
      } else if (_arithMatch('>=')) {
        final r = _parseArithShift();
        left = left >= r ? 1 : 0;
      } else if (_arithMatch('<')) {
        final r = _parseArithShift();
        left = left < r ? 1 : 0;
      } else if (_arithMatch('>')) {
        final r = _parseArithShift();
        left = left > r ? 1 : 0;
      } else {
        break;
      }
    }
    return left;
  }

  int _parseArithShift() {
    var left = _parseArithAdd();
    while (true) {
      if (_arithMatch('<<')) {
        final r = _parseArithAdd();
        left = left << r;
      } else if (_arithMatch('>>')) {
        final r = _parseArithAdd();
        left = left >> r;
      } else {
        break;
      }
    }
    return left;
  }

  int _parseArithAdd() {
    var left = _parseArithMul();
    while (true) {
      if (_arithMatch('+')) {
        final r = _parseArithMul();
        left = left + r;
      } else if (_arithMatch('-')) {
        final r = _parseArithMul();
        left = left - r;
      } else {
        break;
      }
    }
    return left;
  }

  int _parseArithMul() {
    var left = _parseArithPower();
    while (true) {
      if (_arithMatch('*')) {
        final r = _parseArithPower();
        left = left * r;
      } else if (_arithMatch('/')) {
        final r = _parseArithPower();
        if (r == 0) throw Exception('division by zero');
        left = left ~/ r;
      } else if (_arithMatch('%')) {
        final r = _parseArithPower();
        if (r == 0) throw Exception('division by zero');
        left = left % r;
      } else {
        break;
      }
    }
    return left;
  }

  int _parseArithPower() {
    var left = _parseArithUnary();
    if (_arithMatch('**')) {
      final right = _parseArithPower();
      return _intPow(left, right);
    }
    return left;
  }

  int _intPow(int base, int exp) {
    if (exp < 0) return 0;
    var result = 1;
    var b = base;
    var e = exp;
    while (e > 0) {
      if (e.isOdd) result *= b;
      e >>= 1;
      b *= b;
    }
    return result;
  }

  int _parseArithUnary() {
    if (_arithMatch('+')) return _parseArithPostfix();
    if (_arithMatch('-')) return -_parseArithPostfix();
    if (_arithMatch('!')) return _parseArithPostfix() == 0 ? 1 : 0;
    if (_arithMatch('~')) return ~_parseArithPostfix();
    if (_arithMatch('++')) {
      final token = _arithAdvance();
      if (token.type == _ArithTokType.var_) {
        final val = _getArithVar(token.value) + 1;
        _setArithVar(token.value, val);
        return val;
      }
      return _parseArithPostfix();
    }
    if (_arithMatch('--')) {
      final token = _arithAdvance();
      if (token.type == _ArithTokType.var_) {
        final val = _getArithVar(token.value) - 1;
        _setArithVar(token.value, val);
        return val;
      }
      return _parseArithPostfix();
    }
    return _parseArithPostfix();
  }

  int _parseArithPostfix() {
    if (_arithPeek().type == _ArithTokType.num) {
      final token = _arithAdvance();
      return int.parse(token.value, radix: token.radix);
    }
    if (_arithPeek().type == _ArithTokType.var_) {
      final token = _arithAdvance();
      if (_arithPeek().value == '++') {
        _arithAdvance();
        final val = _getArithVar(token.value);
        _setArithVar(token.value, val + 1);
        return val;
      }
      if (_arithPeek().value == '--') {
        _arithAdvance();
        final val = _getArithVar(token.value);
        _setArithVar(token.value, val - 1);
        return val;
      }
      return _getArithVar(token.value);
    }
    if (_arithPeek().value == '(') {
      _arithAdvance();
      final val = _parseArithComma();
      _arithExpect(')');
      return val;
    }
    return 0;
  }

  int _getArithVar(String name) {
    final val = _lookupVar(name);
    if (val.isNotEmpty) {
      final parsed = int.tryParse(val);
      if (parsed != null) return parsed;
    }
    if (_arrays.containsKey(name) && _arrays[name]!.isNotEmpty) {
      final parsed = int.tryParse(_arrays[name]!.last);
      if (parsed != null) return parsed;
    }
    return 0;
  }

  void _setArithVar(String name, int val) {
    _env[name] = val.toString();
  }

  void _arithExpect(String v) {
    if (_arithPeek().value != v) throw Exception('Expected $v in arithmetic');
    _arithAdvance();
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
    if (name == r'$') return _pid.toString();
    if (name == '!') return _lastBgPid.toString();
    if (name == '0') return 'kino';
    if (name == '#') return _positionalParams.length.toString();
    if (name == '@') return _positionalParams.join(' ');
    if (name == '*') return _positionalParams.join(' ');
    if (name.length == 1 && name.codeUnitAt(0) >= 49 && name.codeUnitAt(0) <= 57) {
      final idx = int.parse(name) - 1;
      return idx < _positionalParams.length ? _positionalParams[idx] : '';
    }
    if (name == 'RANDOM') return _random.nextInt(32768).toString();
    if (name == 'LINENO') return '0';
    if (name == 'SECONDS') return _shellTimer.elapsed.inSeconds.toString();
    if (name == 'EPOCHREALTIME') return (DateTime.now().microsecondsSinceEpoch / 1000000).toStringAsFixed(6);
    if (name == 'EPOCHSECONDS') return (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    if (name == 'HOSTNAME') {
      try { return Platform.localHostname; } catch (_) { return 'localhost'; }
    }
    if (name == 'OSTYPE') {
      if (Platform.isAndroid) return 'linux-android';
      if (Platform.isLinux) return 'linux-gnu';
      if (Platform.isMacOS) return 'darwin';
      if (Platform.isWindows) return 'windows';
      return 'unknown';
    }
    if (name == 'BASHPID') return _pid.toString();
    if (name == '_') return _underscore;
    if (name == '-') return _currentFlags();
    if (name == 'PIPESTATUS') return _pipeStatusString;
    if (name == 'BASH_VERSION') return '5.2.26(1)-kino';
    if (name == 'BASH_VERSINFO') return '5';
    if (name == 'MACHTYPE') {
      if (Platform.isAndroid) return 'aarch64-unknown-linux-android';
      return Platform.localHostname.contains('arm') ? 'aarch64-unknown-linux-gnu' : 'x86_64-unknown-linux-gnu';
    }
    if (name == 'BASH_SUBSHELL') return '0';
    if (name == 'BASH_REMATCH') return _bashRematch.toString();
    if (name == 'GLOBIGNORE') return _globIgnore ?? '';
    if (_arrays.containsKey(name)) {
      final arr = _arrays[name]!;
      return arr.isNotEmpty ? arr.join(' ') : '';
    }
    if (_assocArrays.containsKey(name)) {
      final arr = _assocArrays[name]!;
      return arr.values.isNotEmpty ? arr.values.join(' ') : '';
    }
    return '';
  }

  int get _pid => 1;

  String _currentFlags() {
    var flags = '';
    if (_setFlags['-e'] == true) flags += 'e';
    if (_setFlags['-x'] == true) flags += 'x';
    if (_setFlags['-u'] == true) flags += 'u';
    if (_setFlags['-v'] == true) flags += 'v';
    return flags.isEmpty ? 'hB' : '${flags}hB';
  }

  String _expandPrompt(String ps) {
    return ps
        .replaceAll(r'\h', _getHostname())
        .replaceAll(r'\H', _getHostname())
        .replaceAll(r'\u', _env['USER'] ?? 'kino')
        .replaceAll(r'\w', _cwd)
        .replaceAll(r'\W', p.basename(_cwd))
        .replaceAll(r'\d', _dateFormat())
        .replaceAll(r'\t', _timeFormat('HH:mm:ss'))
        .replaceAll(r'\@', _timeFormat('hh:mm am'))
        .replaceAll(r'\A', _timeFormat('HH:mm'))
        .replaceAll(r'\s', 'kino')
        .replaceAll(r'\v', '1.0')
        .replaceAll(r'\V', '1.0.0')
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\r', '\r')
        .replaceAll(r'\e', '\x1b')
        .replaceAll(r'\\', '\\')
        .replaceAll(r'\$', _env['USER'] == 'root' ? '#' : r'$')
        .replaceAll(r'\!', (_history.length + 1).toString())
        .replaceAll(r'\#', (_history.length + 1).toString());
  }

  String _getHostname() {
    try { return Platform.localHostname; } catch (_) { return 'localhost'; }
  }

  String _dateFormat() {
    final now = DateTime.now();
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${days[now.weekday % 7]} ${months[now.month - 1]} ${now.day.toString().padLeft(2, ' ')}';
  }

  String _timeFormat(String fmt) {
    final now = DateTime.now();
    return fmt
        .replaceAll('HH', now.hour.toString().padLeft(2, '0'))
        .replaceAll('mm', now.minute.toString().padLeft(2, '0'))
        .replaceAll('ss', now.second.toString().padLeft(2, '0'))
        .replaceAll('hh', (now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour)).toString().padLeft(2, '0'))
        .replaceAll('am', now.hour < 12 ? 'am' : 'pm');
  }

  String _pipeStatusString = '0';
  String _underscore = '';
  final _random = Random();

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
    final hasGlob = token.contains('*') || token.contains('?') || token.contains('[');
    final hasExtGlob = _shopt['extglob'] == true &&
        RegExp(r'[@*+?!]\(.*\)').hasMatch(token);

    if (!hasGlob && !hasExtGlob) return [token];

    // Split into directory part and pattern
    final dirPart = p.dirname(token);
    final pattern = p.basename(token);
    final resolvedDir = dirPart == '.'
        ? _cwd
        : _resolvePath(dirPart);

    final absDir = _vfsAbsolute(resolvedDir);
    final dir = Directory(absDir);
    if (!dir.existsSync()) {
      if (_shopt['nullglob'] == true) return [];
      if (_shopt['failglob'] == true) {
        // Will be handled by caller
      }
      return [token];
    }

    final regex = _globToRegex(pattern);
    final matches = <String>[];
    try {
      final entities = dir.listSync();
      for (final e in entities) {
        final name = p.basename(e.path);
        if (_shopt['dotglob'] != true && name.startsWith('.')) continue;
        if (regex.hasMatch(name)) {
          final vfsPath = resolvedDir == '/'
              ? '/$name'
              : '$resolvedDir/$name';
          matches.add(vfsPath);
        }
      }
    } catch (_) {}

    matches.sort();

    // Apply GLOBIGNORE filtering
    if (_globIgnore != null && _globIgnore!.isNotEmpty && matches.isNotEmpty) {
      final ignorePatterns = _globIgnore!.split(':');
      matches.removeWhere((path) {
        for (final pattern in ignorePatterns) {
          if (pattern.isEmpty) continue;
          try {
            if (RegExp('^${_globToRegexStr(pattern)}\$').hasMatch(p.basename(path))) return true;
          } catch (_) {}
        }
        return false;
      });
    }

    if (matches.isEmpty) {
      if (_shopt['nullglob'] == true) return [];
      if (_shopt['failglob'] == true) {
        _lastError = 'glob: no matches for: $token';
        _lastExitCode = 1;
      }
      return [token];
    }
    return matches;
  }

  RegExp _globToRegex(String pattern) {
    // Handle extended glob patterns if enabled
    if (_shopt['extglob'] == true) {
      pattern = _expandExtGlob(pattern);
    }

    final sb = StringBuffer('^');
    for (var i = 0; i < pattern.length; i++) {
      final c = pattern[i];
      if (c == '*' && i + 1 < pattern.length && pattern[i + 1] == '*') {
        if (_shopt['globstar'] == true) {
          sb.write('.*');
          i++;
        } else {
          sb.write('[^/]*');
        }
      } else if (c == '*') {
        sb.write('[^/]*');
      } else if (c == '?') {
        sb.write('[^/]');
      } else if (c == '.') {
        sb.write('\\.');
      } else if (c == '[') {
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
      } else if (c == '@' || c == '*' || c == '+' || c == '?' || c == '!') {
        // Extended glob prefixes will be handled by _expandExtGlob
        sb.write(RegExp.escape(c));
      } else {
        sb.write(RegExp.escape(c));
      }
    }
    sb.write(r'$');
    return RegExp(sb.toString(), caseSensitive: _shopt['nocaseglob'] != true);
  }

  /// Convert ksh-style extended glob patterns to regex.
  /// Patterns: @(pattern) (exactly one), *(pattern) (zero or more),
  /// +(pattern) (one or more), ?(pattern) (zero or one),
  /// !(pattern) (anything except)
  String _expandExtGlob(String pattern) {
    var result = pattern;
    // ?(pattern) -> zero or one
    result = result.replaceAllMapped(
      RegExp(r'\(\?([^()]+)\)'),
      (m) => '(${m.group(1)})?',
    );
    // +(pattern) -> one or more
    result = result.replaceAllMapped(
      RegExp(r'\(\+([^()]+)\)'),
      (m) => '(${m.group(1)})+',
    );
    // @(pattern) -> exactly one (just the content)
    result = result.replaceAllMapped(
      RegExp(r'\(@([^()]+)\)'),
      (m) => '(${m.group(1)})',
    );
    // !(pattern) -> not-match (neg lookahead)
    result = result.replaceAllMapped(
      RegExp(r'\(!([^()]+)\)'),
      (m) => '(?!${m.group(1)}).*',
    );
    // *(pattern) -> zero or more
    result = result.replaceAllMapped(
      RegExp(r'\(\*([^()]+)\)'),
      (m) => '(${m.group(1)})*',
    );
    return result;
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
    '[[': _cmdDoubleBracket,
    'declare': _cmdDeclare,
    'local': _cmdLocal,
    'curl': _cmdCurl,
    'read': _cmdRead,
    'eval': _cmdEval,
    'exec': _cmdExec,
    'shift': _cmdShift,
    'let': _cmdLet,
    'readarray': _cmdReadarray,
    'mapfile': _cmdReadarray,
    'trap': _cmdTrap,
    'kill': _cmdKill,
    'wait': _cmdWait,
    'jobs': _cmdJobs,
    'bg': _cmdBg,
    'fg': _cmdFg,
    'disown': _cmdDisown,
    'history': _cmdHistory,
    'shopt': _cmdShopt,
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
    'readonly': _cmdReadonly,
    'getopts': _cmdGetopts,
    'date': _cmdDate,
    'basename': _cmdBasename,
    'dirname': _cmdDirname,
    'realpath': _cmdRealpath,
    'uniq': _cmdUniq,
    'select': _cmdSelect,
    ':': _cmdColon,
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
      return ShellResult(exitCode: 1, stdout: '', stderr: 'printf: usage: printf format [arguments]\n');
    }
    final format = args[0];
    final fmtArgs = args.sublist(1);

    var argIdx = 0;
    var fmt = format;

    // Handle \e (escape) sequences in the format string
    fmt = fmt
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\t', '\t')
        .replaceAll(r'\r', '\r')
        .replaceAll(r'\b', '\x08')
        .replaceAll(r'\f', '\x0c')
        .replaceAll(r'\v', '\x0b')
        .replaceAll(r'\a', '\x07')
        .replaceAll(r'\\', '\\')
        .replaceAll(r'\e', '\x1b')
        .replaceAll(r'\0', '\x00');

    final output2 = StringBuffer();
    var i = 0;
    while (i < fmt.length) {
      if (fmt[i] == '%' && i + 1 < fmt.length) {
        i++;
        // Parse format specifier
        var flags = '';
        while (i < fmt.length && '-+0 #,'.contains(fmt[i])) {
          flags += fmt[i];
          i++;
        }
        // Parse width
        String? width;
        if (i < fmt.length && fmt[i] == '*') {
          width = argIdx < fmtArgs.length ? fmtArgs[argIdx++] : '';
          i++;
        } else {
          final wStart = i;
          while (i < fmt.length && fmt[i].codeUnitAt(0) >= 48 && fmt[i].codeUnitAt(0) <= 57) { i++; }
          if (i > wStart) width = fmt.substring(wStart, i);
        }
        // Parse precision
        String? precision;
        if (i < fmt.length && fmt[i] == '.') {
          i++;
          if (i < fmt.length && fmt[i] == '*') {
            precision = argIdx < fmtArgs.length ? fmtArgs[argIdx++] : '';
            i++;
          } else {
            final pStart = i;
            while (i < fmt.length && fmt[i].codeUnitAt(0) >= 48 && fmt[i].codeUnitAt(0) <= 57) { i++; }
            if (i > pStart) precision = fmt.substring(pStart, i);
          }
        }
        if (i >= fmt.length) break;
        final spec = fmt[i];
        i++;

        String arg;
        if (spec == '%') {
          arg = '%';
        } else {
          arg = argIdx < fmtArgs.length ? fmtArgs[argIdx++] : '';
        }

        String formatted;
        switch (spec) {
          case 's':
            formatted = arg;
          case 'd':
          case 'i':
            final n = int.tryParse(arg) ?? 0;
            formatted = n.toString();
          case 'u':
            final n = int.tryParse(arg) ?? 0;
            formatted = (n < 0 ? 0 : n).toString();
          case 'o':
            final n = int.tryParse(arg) ?? 0;
            formatted = n.toRadixString(8);
          case 'x':
            final n = int.tryParse(arg) ?? 0;
            formatted = n.toRadixString(16);
          case 'X':
            final n = int.tryParse(arg) ?? 0;
            formatted = n.toRadixString(16).toUpperCase();
          case 'f':
            final n = double.tryParse(arg) ?? 0.0;
            final prec = precision != null ? int.parse(precision) : 6;
            formatted = n.toStringAsFixed(prec);
          case 'e':
            final n = double.tryParse(arg) ?? 0.0;
            final prec = precision != null ? int.parse(precision) : 6;
            formatted = n.toStringAsExponential(prec);
          case 'E':
            final n = double.tryParse(arg) ?? 0.0;
            final prec = precision != null ? int.parse(precision) : 6;
            formatted = n.toStringAsExponential(prec).toUpperCase();
          case 'g':
          case 'G':
            final n = double.tryParse(arg) ?? 0.0;
            final prec = precision != null ? int.parse(precision) : 6;
            formatted = n.toStringAsPrecision(prec);
            if (spec == 'G') formatted = formatted.toUpperCase();
          case 'a':
          case 'A':
            final n = double.tryParse(arg) ?? 0.0;
            final hex = n.toInt().toRadixString(16);
            formatted = spec == 'A' ? '0X${hex.toUpperCase()}' : '0x$hex';
          case 'n':
            formatted = output2.length.toString();
          case 'q':
            // Quote the string for shell reuse
            formatted = _quoteForShell(arg);
          case 'b':
            // Process escape sequences
            formatted = arg
                .replaceAll(r'\n', '\n')
                .replaceAll(r'\t', '\t')
                .replaceAll(r'\r', '\r')
                .replaceAll(r'\b', '\x08')
                .replaceAll(r'\f', '\x0c')
                .replaceAll(r'\v', '\x0b')
                .replaceAll(r'\a', '\x07')
                .replaceAll(r'\\', '\\')
                .replaceAll(r'\0', '\x00')
                .replaceAllMapped(RegExp(r'\\([0-7]{1,3})'), (m) => String.fromCharCode(int.parse(m[1]!, radix: 8)))
                .replaceAllMapped(RegExp(r'\\x([0-9a-fA-F]{1,2})'), (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)));
          default:
            formatted = '%$spec$arg';
        }

        // Apply width
        if (width != null) {
          final w = int.tryParse(width) ?? 0;
          if (w.abs() > formatted.length) {
            final padding = w.abs() - formatted.length;
            final padChar = flags.contains('0') && !flags.contains('-') ? '0' : ' ';
            if (flags.contains('-')) {
              formatted = formatted + (padChar * padding);
            } else {
              formatted = (padChar * padding) + formatted;
            }
          }
        }

        // Apply flags
        if (flags.contains('+') && !formatted.startsWith('-') && spec != 's' && spec != '%') {
          formatted = '+$formatted';
        }
        if (flags.contains(' ') && !formatted.startsWith('-') && !formatted.startsWith('+') && spec != 's' && spec != '%') {
          formatted = ' $formatted';
        }

        output2.write(formatted);
      } else {
        output2.write(fmt[i]);
        i++;
      }
    }

    return ShellResult(exitCode: 0, stdout: output2.toString(), stderr: '');
  }

  String _quoteForShell(String s) {
    if (s.isEmpty) return "''";
    if (RegExp(r'^[a-zA-Z0-9_./-]+$').hasMatch(s)) return s;
    return "'${s.replaceAll("'", "'\\''")}'";
  }

  // ===========================================================================
  // BUILT-IN: true / false
  // ===========================================================================

  Future<ShellResult> _cmdColon(List<String> args) async => _okResult;

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
      } else if (_functions.containsKey(arg)) {
        output.writeln('$arg: shell function');
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
    var allFlag = false;
    var i = 0;
    while (i < args.length && args[i].startsWith('-')) {
      if (args[i] == '-a') { allFlag = true; i++; }
      else { i++; }
    }

    if (i >= args.length) {
      return ShellResult(exitCode: 1, stdout: '', stderr: 'type: usage: type [-a] name [name...]\n');
    }

    final buf = StringBuffer();
    for (var j = i; j < args.length; j++) {
      final name = args[j];
      var found = false;

      if (_builtins.containsKey(name)) {
        buf.writeln('$name is a shell builtin');
        found = true;
        if (!allFlag) continue;
      }

      if (_functions.containsKey(name)) {
        buf.writeln('$name is a function');
        found = true;
        if (!allFlag) continue;
      }

      if (_aliases.containsKey(name)) {
        buf.writeln('$name is aliased to `${_aliases[name]}`');
        found = true;
        if (!allFlag) continue;
      }

      // Check PATH
      final pathDirs = (_env['PATH'] ?? '/bin:/usr/bin').split(':');
      for (final dir in pathDirs) {
        final fullPath = p.join(dir, name);
        try {
          if (FileSystemEntity.isFileSync(fullPath)) {
            buf.writeln('$name is $fullPath');
            found = true;
            if (!allFlag) break;
          }
        } catch (_) {}
      }

      if (!found) {
        buf.writeln('type: $name: not found');
      }
    }
    return ShellResult(exitCode: 0, stdout: buf.toString(), stderr: '');
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
    if (args.isNotEmpty) {
      final topic = args[0];
      if (_builtins.containsKey(topic)) {
        return ShellResult(
          exitCode: 0,
          stdout: '$topic: shell built-in command\n',
          stderr: '',
        );
      }
      return ShellResult(
        exitCode: 1,
        stdout: '',
        stderr: 'help: no help topics match "$topic". Try `help` or `man`.\n',
      );
    }
    return ShellResult(
      exitCode: 0,
      stdout: 'GNU bash, version 5.2.26(1)-kino (VFS shell)\n'
             'These shell commands are defined internally:\n\n'
             '  . : [ [[ alias bg bind break builtin caller cd command\n'
             '  compgen complete continue declare dirs disown echo enable\n'
             '  eval exec exit export false fg fc getopts hash help history\n'
             '  jobs kill let local logout mapfile popd printf pushd pwd\n'
             '  read readarray readonly return set shift shopt source\n'
             '  suspend test times trap true type ulimit umask unalias\n'
             '  unset wait\n',
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
    if (args.isEmpty) {
      final buf = StringBuffer();
      _env.forEach((k, v) => buf.writeln('$k=$v'));
      _arrays.forEach((k, v) => buf.writeln('$k=(${v.join(' ')})'));
      _functions.forEach((k, v) => buf.writeln('$k () { ... }'));
      return ShellResult(exitCode: 0, stdout: buf.toString(), stderr: '');
    }

    var i = 0;
    while (i < args.length && (args[i].startsWith('-') || args[i].startsWith('+'))) {
      final arg = args[i];
      final isSet = arg.startsWith('-');

      if (arg == '-o' && i + 1 < args.length) {
        i++;
        final opt = args[i];
        _setFlags['-o $opt'] = true;
        i++;
        continue;
      }
      if (arg == '+o' && i + 1 < args.length) {
        i++;
        final opt = args[i];
        _setFlags['-o $opt'] = false;
        i++;
        continue;
      }

      if (arg == '-o') {
        _setFlags['-o'] = true;
        i++;
        continue;
      }

      for (var j = 1; j < arg.length; j++) {
        switch (arg[j]) {
          case 'e': _setFlags['-e'] = isSet; break;
          case 'x': _setFlags['-x'] = isSet; break;
          case 'u': _setFlags['-u'] = isSet; break;
          case 'v': _setFlags['-v'] = isSet; break;
          case 'C': _setFlags['-C'] = isSet; break;  // noclobber
          case 'B': _setFlags['-B'] = isSet; break;  // brace expansion
          case 'f': _setFlags['-f'] = isSet; break;  // disable glob
          case 'm': _setFlags['-m'] = isSet; break;  // monitor (job control)
          case 'a': _setFlags['-a'] = isSet; break;  // allexport
          case 'b': _setFlags['-b'] = isSet; break;  // notify
          case 'h': _setFlags['-h'] = isSet; break;  // hashall
          case 'k': _setFlags['-k'] = isSet; break;  // keyword
          case 'n': _setFlags['-n'] = isSet; break;  // noexec
          case 't': _setFlags['-t'] = isSet; break;  // onecmd
        }
      }
      i++;
    }

    if (i < args.length && args[i] == '--') {
      i++;
      _positionalParams = args.sublist(i);
      _env['@'] = _positionalParams.join(' ');
      _env['#'] = _positionalParams.length.toString();
      i = args.length;
    } else if (i < args.length) {
      _env['@'] = args.sublist(i).join(' ');
    }

    return _okResult;
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
    final count = args.isNotEmpty ? int.tryParse(args[0]) ?? 1 : 1;
    _breakDepth = count;
    return const ShellResult(exitCode: 0, stdout: '', stderr: '');
  }

  Future<ShellResult> _cmdContinue(List<String> args) async {
    final count = args.isNotEmpty ? int.tryParse(args[0]) ?? 1 : 1;
    _continueDepth = count;
    return const ShellResult(exitCode: 0, stdout: '', stderr: '');
  }

  // ===========================================================================
  // BUILT-IN: test / [ / [[
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

    // -nt FILE: newer than
    if (args[i] == '-nt' && i + 2 < args.length) {
      try {
        final a = _resolvePath(args[i + 1]);
        final b = _resolvePath(args[i + 2]);
        final statA = await _vfs.stat(a);
        final statB = await _vfs.stat(b);
        return statA.modifiedAt.isAfter(statB.modifiedAt) ? _testTrue() : _testFalse();
      } catch (_) {
        return _testFalse();
      }
    }

    // -ot FILE: older than
    if (args[i] == '-ot' && i + 2 < args.length) {
      try {
        final a = _resolvePath(args[i + 1]);
        final b = _resolvePath(args[i + 2]);
        final statA = await _vfs.stat(a);
        final statB = await _vfs.stat(b);
        return statA.modifiedAt.isBefore(statB.modifiedAt) ? _testTrue() : _testFalse();
      } catch (_) {
        return _testFalse();
      }
    }

    // -ef FILE: same file (same device/inode)
    if (args[i] == '-ef' && i + 2 < args.length) {
      final a = _vfsAbsolute(_resolvePath(args[i + 1]));
      final b = _vfsAbsolute(_resolvePath(args[i + 2]));
      return a == b ? _testTrue() : _testFalse();
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

    // STRING < STRING (lexicographic)
    if (i + 2 < args.length && args[i + 1] == '<') {
      return args[i].compareTo(args[i + 2]) < 0 ? _testTrue() : _testFalse();
    }

    // STRING > STRING (lexicographic)
    if (i + 2 < args.length && args[i + 1] == '>') {
      return args[i].compareTo(args[i + 2]) > 0 ? _testTrue() : _testFalse();
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
    if (args.isNotEmpty && args.last == ']') {
      return _cmdTest(args.sublist(0, args.length - 1));
    }
    return _cmdTest(args);
  }

  Future<ShellResult> _cmdDoubleBracket(List<String> args) async {
    // Handle [[ expr ]] — strip outer [[ ]]
    if (args.isEmpty) return _testFalse();
    // Remove trailing ]] if present
    var inner = args;
    if (inner.last == ']]') {
      inner = inner.sublist(0, inner.length - 1);
    }
    if (inner.isEmpty) return _testFalse();
    if (inner.first == '[[') {
      inner = inner.sublist(1);
    }
    if (inner.isEmpty) return _testFalse();
    return _evalBracketExpr(inner, 0);
  }

  Future<ShellResult> _evalBracketExpr(List<String> args, int start) async {
    // Handle parenthesized sub-expressions
    if (args[start] == '(') {
      // Find matching )
      var depth = 1;
      var end = start + 1;
      while (end < args.length && depth > 0) {
        if (args[end] == '(') { depth++; }
        else if (args[end] == ')') { depth--; }
        if (depth > 0) end++;
      }
      final innerResult = await _evalBracketExpr(args, start + 1);
      // After the ), check for operators
      var result = innerResult.exitCode == 0;
      var i = end + 1;
      while (i < args.length) {
        if (args[i] == '&&') {
          i++;
          final right = await _evalBracketExpr(args, i);
          result = result && right.exitCode == 0;
          break;
        } else if (args[i] == '||') {
          i++;
          final right = await _evalBracketExpr(args, i);
          result = result || right.exitCode == 0;
          break;
        }
        break;
      }
      return ShellResult(exitCode: result ? 0 : 1, stdout: '', stderr: '');
    }
    // Delegate to _cmdTest for simple expressions
    final result = await _cmdTest(args.sublist(start));
    return result;
  }

  ShellResult _testTrue() => const ShellResult(exitCode: 0, stdout: '', stderr: '');
  ShellResult _testFalse() => const ShellResult(exitCode: 1, stdout: '', stderr: '');

  // ===========================================================================
  // BUILT-IN: read
  // ===========================================================================

  Future<ShellResult> _cmdRead(List<String> args) async {
    var prompt = '';
    // ignore: unused_local_variable
    var timeoutSec = -1;
    var nchars = -1;
    var delimiter = 10; // \n
    var silent = false;
    // ignore: unused_local_variable
    var rawMode = false;
    int? fd;

    var i = 0;
    while (i < args.length && args[i].startsWith('-')) {
      if (args[i] == '-p' && i + 1 < args.length) { prompt = args[i + 1]; i += 2; }
      else if (args[i] == '-t' && i + 1 < args.length) { timeoutSec = int.tryParse(args[i + 1]) ?? -1; i += 2; }
      else if (args[i] == '-n' && i + 1 < args.length) { nchars = int.tryParse(args[i + 1]) ?? -1; i += 2; }
      else if (args[i] == '-d' && i + 1 < args.length) { delimiter = args[i + 1].codeUnitAt(0); i += 2; }
      else if (args[i] == '-s') { silent = true; i++; }
      else if (args[i] == '-r') { rawMode = true; i++; }
      else if (args[i] == '-u' && i + 1 < args.length) { fd = int.tryParse(args[i + 1]); i += 2; }
      else { i++; }
    }

    final varNames = args.sublist(i);
    if (varNames.isEmpty) {
      return _cmdRead(['-p', prompt, 'REPLY']);
    }

    if (prompt.isNotEmpty) {
      if (!silent) stdout.write(prompt);
    }

    String? line;
    try {
      if (fd != null) {
        // Read from file descriptor — not fully supported
        return ShellResult(exitCode: 1, stdout: '', stderr: 'read: -u not fully supported\n');
      }
      if (silent) {
        // Read without echo
        final charCodes = <int>[];
        while (true) {
          final byte = stdin.readByteSync();
          if (byte == 3) return ShellResult(exitCode: 1, stdout: '', stderr: ''); // Ctrl-C
          if (byte == delimiter || byte == 10) break;
          charCodes.add(byte);
        }
        line = String.fromCharCodes(charCodes);
        // Write newline since echo was suppressed
        stdout.writeln();
      } else if (nchars > 0) {
        final charCodes = <int>[];
        for (var j = 0; j < nchars; j++) {
          final byte = stdin.readByteSync();
          if (byte == delimiter || byte == 10) break;
          if (byte == 3) return ShellResult(exitCode: 1, stdout: '', stderr: '');
          charCodes.add(byte);
        }
        line = String.fromCharCodes(charCodes);
      } else {
        line = stdin.readLineSync();
      }
    } catch (e) {
      // Fallback
      try {
        line = stdin.readLineSync();
      } catch (_) {
        return ShellResult(exitCode: 1, stdout: '', stderr: 'read: error reading input\n');
      }
    }

    if (line == null) {
      return ShellResult(exitCode: 1, stdout: '', stderr: '');
    }

    if (varNames.length == 1) {
      _env[varNames[0]] = line;
    } else {
      final parts = line.split(RegExp(r'[\s\t]+'));
      for (var j = 0; j < varNames.length; j++) {
        if (j < parts.length) {
          _env[varNames[j]] = parts[j];
        } else {
          _env[varNames[j]] = '';
        }
      }
    }
    return _okResult;
  }

  // ===========================================================================
  // BUILT-IN: eval
  // ===========================================================================

  Future<ShellResult> _cmdEval(List<String> args) async {
    if (args.isEmpty) return _okResult;
    final cmd = args.join(' ');
    return execute(cmd);
  }

  // ===========================================================================
  // BUILT-IN: exec
  // ===========================================================================

  Future<ShellResult> _cmdExec(List<String> args) async {
    if (args.isEmpty) {
      return ShellResult(exitCode: 0, stdout: '', stderr: '');
    }
    // Parse redirects in args
    final cmdArgs = <String>[];
    for (var i = 0; i < args.length; i++) {
      if (args[i] == '>' && i + 1 < args.length) {
        i++;
        continue;
      } else if (args[i] == '>>' && i + 1 < args.length) {
        i++;
        continue;
      } else if (args[i] == '2>' && i + 1 < args.length) {
        i++;
        continue;
      } else if (args[i] == '&>' && i + 1 < args.length) {
        i++;
        continue;
      } else if (args[i] == '<' && i + 1 < args.length) {
        i++;
        continue;
      } else if (RegExp(r'^\d+>').hasMatch(args[i]) && i + 1 < args.length) {
        i++;
        continue;
      } else {
        cmdArgs.add(args[i]);
      }
    }
    if (cmdArgs.isEmpty) return _okResult;
    // Execute the command replacing the shell
    return _runInShell(cmdArgs.join(' '));
  }

  // ===========================================================================
  // BUILT-IN: shift
  // ===========================================================================

  Future<ShellResult> _cmdShift(List<String> args) async {
    var n = 1;
    if (args.isNotEmpty) {
      n = int.tryParse(args[0]) ?? 1;
    }
    if (n > _positionalParams.length) {
      return ShellResult(
        exitCode: 1,
        stdout: '',
        stderr: 'shift: shift count out of range',
      );
    }
    _positionalParams = _positionalParams.sublist(n);
    _env['@'] = _positionalParams.join(' ');
    _env['#'] = _positionalParams.length.toString();
    return _okResult;
  }

  // ===========================================================================
  // BUILT-IN: let
  // ===========================================================================

  Future<ShellResult> _cmdLet(List<String> args) async {
    if (args.isEmpty) {
      return const ShellResult(
        exitCode: 1,
        stdout: '',
        stderr: 'let: usage: let expression [expression ...]',
      );
    }
    for (final arg in args) {
      final eq = arg.indexOf('=');
      if (eq > 0) {
        final name = arg.substring(0, eq);
        final expr = arg.substring(eq + 1);
        final value = _evalArithmetic(expr);
        _env[name] = value.toString();
      }
    }
    return _okResult;
  }

  // ===========================================================================
  // BUILT-IN: readarray / mapfile
  // ===========================================================================

  Future<ShellResult> _cmdReadarray(List<String> args) async {
    var arrayName = 'MAPFILE';
    var maxLines = -1;
    var skipLines = 0;
    var i = 0;

    while (i < args.length && args[i].startsWith('-')) {
      if (args[i] == '-t') { i++; continue; }
      if (args[i] == '-d' && i + 1 < args.length) { i += 2; continue; }
      if (args[i] == '-n' && i + 1 < args.length) { maxLines = int.tryParse(args[i + 1]) ?? -1; i += 2; continue; }
      if (args[i] == '-u' && i + 1 < args.length) { i += 2; continue; }
      if (args[i] == '-s' && i + 1 < args.length) { skipLines = int.tryParse(args[i + 1]) ?? 0; i += 2; continue; }
      if (args[i] == '-C' && i + 1 < args.length) { i += 2; continue; }
      if (args[i] == '-c' && i + 1 < args.length) { i += 2; continue; }
      break;
    }
    if (i < args.length) arrayName = args[i];

    try {
      final lines = <String>[];
      var count = 0;
      while (maxLines < 0 || count < maxLines) {
        final line = stdin.readLineSync();
        if (line == null) break;
        if (skipLines > 0) { skipLines--; continue; }
        lines.add(line);
        count++;
      }
      _arrays[arrayName] = lines;
      _env[arrayName] = lines.join(' ');
      return _okResult;
    } catch (_) {
      _arrays[arrayName] = [];
      return _okResult;
    }
  }

  // ===========================================================================
  // BUILT-IN: trap
  // ===========================================================================

  final Map<String, String> _traps = {};

  static const _signalNames = {
    0: 'EXIT', 1: 'SIGHUP', 2: 'SIGINT', 3: 'SIGQUIT', 4: 'SIGILL',
    5: 'SIGTRAP', 6: 'SIGABRT', 7: 'SIGBUS', 8: 'SIGFPE', 9: 'SIGKILL',
    10: 'SIGUSR1', 11: 'SIGSEGV', 12: 'SIGUSR2', 13: 'SIGPIPE', 14: 'SIGALRM',
    15: 'SIGTERM', 16: 'SIGSTKFLT', 17: 'SIGCHLD', 18: 'SIGCONT', 19: 'SIGSTOP',
    20: 'SIGTSTP', 21: 'SIGTTIN', 22: 'SIGTTOU',
  };

  Future<void> _executeTrap(String signal) async {
    if (_traps.containsKey(signal)) {
      final cmd = _traps[signal]!;
      await execute(cmd);
    }
  }

  Future<ShellResult> _cmdTrap(List<String> args) async {
    if (args.isEmpty) {
      final buf = StringBuffer();
      _traps.forEach((sig, cmd) => buf.writeln('trap -- $cmd $sig'));
      return ShellResult(exitCode: 0, stdout: buf.toString(), stderr: '');
    }
    if (args.length == 1) {
      // trap SIGSPEC — show current trap
      final cmd = _traps[args[0]];
      if (cmd != null) {
        return ShellResult(exitCode: 0, stdout: 'trap -- $cmd ${args[0]}\n', stderr: '');
      }
      return _okResult;
    }
    // trap [-lp] [arg] [sigspec]
    var signals = <String>[];
    var command = '';
    if (args[0] == '-l') {
      final buf = StringBuffer();
      final sorted = _signalNames.keys.toList()..sort();
      for (final num in sorted) {
        buf.writeln('${num.toString().padLeft(2)}) ${_signalNames[num]}');
      }
      return ShellResult(exitCode: 0, stdout: buf.toString(), stderr: '');
    }
    if (args[0] == '-p') {
      final buf = StringBuffer();
      _traps.forEach((sig, cmd) => buf.writeln('trap -- $cmd $sig'));
      return ShellResult(exitCode: 0, stdout: buf.toString(), stderr: '');
    }
    command = args[0];
    for (var j = 1; j < args.length; j++) {
      signals.add(args[j]);
    }
    // Convert signal numbers to names
    for (var j = 0; j < signals.length; j++) {
      final sigNum = int.tryParse(signals[j]);
      if (sigNum != null && _signalNames.containsKey(sigNum)) {
        signals[j] = _signalNames[sigNum]!;
      }
    }
    if (command == '-' || command.isEmpty) {
      for (final sig in signals) { _traps.remove(sig); }
    } else {
      for (final sig in signals) { _traps[sig] = command; }
    }
    return _okResult;
  }

  // ===========================================================================
  // BUILT-IN: kill
  // ===========================================================================

  Future<ShellResult> _cmdKill(List<String> args) async {
    if (args.isEmpty) {
      return ShellResult(
        exitCode: 1, stdout: '',
        stderr: 'kill: usage: kill [-s sigspec | -signum] pid...',
      );
    }
    var pids = <String>[];
    var i = 0;
    if (args[0] == '-l') {
      return ShellResult(
        exitCode: 0,
        stdout: ' 1) SIGHUP  2) SIGINT  3) SIGQUIT  4) SIGILL  5) SIGTRAP\n'
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
    for (; i < args.length; i++) { pids.add(args[i]); }
    if (pids.isEmpty) {
      return ShellResult(exitCode: 1, stdout: '', stderr: 'kill: usage: kill pid...');
    }
    for (final pid in pids) {
      try {
        Process.killPid(int.parse(pid));
      } catch (_) {
        // ignore if process doesn't exist
      }
    }
    return _okResult;
  }

  // ===========================================================================
  // BUILT-IN: wait
  // ===========================================================================

  Future<ShellResult> _cmdWait(List<String> args) async {
    if (args.isEmpty) {
      // Wait for all background jobs
      for (final job in _jobs.values.toList()) {
        final code = await job.process.exitCode;
        job.status = 'done';
        job.exitCode = code;
      }
      return _okResult;
    }
    for (final arg in args) {
      final jobId = int.tryParse(arg.replaceAll(RegExp(r'[%\[\]]'), ''));
      if (jobId != null && _jobs.containsKey(jobId)) {
        final job = _jobs[jobId]!;
        final code = await job.process.exitCode;
        job.status = 'done';
        job.exitCode = code;
        _jobs.remove(jobId);
      }
      final pid = int.tryParse(arg);
      if (pid != null) {
        try {
          Process.killPid(pid);
        } catch (_) {}
      }
    }
    return _okResult;
  }

  // ===========================================================================
  // BUILT-IN: jobs / bg / fg / disown
  // ===========================================================================

  Future<ShellResult> _cmdJobs(List<String> args) async {
    if (_jobs.isEmpty) {
      return const ShellResult(exitCode: 0, stdout: '', stderr: '');
    }
    final buf = StringBuffer();
    final sorted = _jobs.keys.toList()..sort();
    for (final id in sorted) {
      final job = _jobs[id]!;
      buf.writeln('[${job.id}]  ${job.status.padRight(8)}${job.command}');
    }
    return ShellResult(exitCode: 0, stdout: buf.toString(), stderr: '');
  }

  Future<ShellResult> _cmdBg(List<String> args) async {
    int? jobId;
    if (args.isNotEmpty) {
      jobId = int.tryParse(args[0].replaceAll(RegExp(r'[%\[\]]'), ''));
    }
    if (jobId == null) {
      if (_jobs.isEmpty) return ShellResult(exitCode: 1, stdout: '', stderr: 'bg: no current job\n');
      jobId = _jobs.keys.last;
    }
    final job = _jobs[jobId];
    if (job == null) {
      return ShellResult(exitCode: 1, stdout: '', stderr: 'bg: $jobId: no such job\n');
    }
    job.status = 'running';
    unawaited(job.process.exitCode.then((code) {
      if (_jobs.containsKey(jobId)) {
        _jobs[jobId]!.status = 'done';
        _jobs[jobId]!.exitCode = code;
      }
    }));
    _writeToStdout('[${job.id}] $jobId\n');
    return _okResult;
  }

  Future<ShellResult> _cmdFg(List<String> args) async {
    int? jobId;
    if (args.isNotEmpty) {
      jobId = int.tryParse(args[0].replaceAll(RegExp(r'[%\[\]]'), ''));
    }
    if (jobId == null) {
      if (_jobs.isEmpty) return ShellResult(exitCode: 1, stdout: '', stderr: 'fg: no current job\n');
      jobId = _jobs.keys.last;
    }
    final job = _jobs[jobId];
    if (job == null) {
      return ShellResult(exitCode: 1, stdout: '', stderr: 'fg: $jobId: no such job\n');
    }
    _writeToStdout('${job.command}\n');
    final code = await job.process.exitCode;
    _jobs.remove(jobId);
    return ShellResult(exitCode: code, stdout: '', stderr: '');
  }

  Future<ShellResult> _cmdDisown(List<String> args) async {
    if (args.isEmpty) {
      if (_jobs.isEmpty) return _okResult;
      final lastId = _jobs.keys.last;
      _jobs.remove(lastId);
      return _okResult;
    }
    for (final arg in args) {
      final jobId = int.tryParse(arg.replaceAll(RegExp(r'[%\[\]]'), ''));
      if (jobId != null) _jobs.remove(jobId);
    }
    return _okResult;
  }

  // ===========================================================================
  // BUILT-IN: history
  // ===========================================================================

  Future<ShellResult> _cmdHistory(List<String> args) async {
    if (args.isNotEmpty && args[0] == '-c') {
      _history.clear();
      return _okResult;
    }
    if (args.isNotEmpty && args[0] == '-d' && args.length > 1) {
      final idx = int.tryParse(args[1]);
      if (idx != null && idx > 0 && idx <= _history.length) {
        _history.removeAt(idx - 1);
      }
      return _okResult;
    }
    final buf = StringBuffer();
    for (var i = 0; i < _history.length; i++) {
      buf.writeln('${(i + 1).toString().padLeft(5)}  ${_history[i]}');
    }
    return ShellResult(exitCode: 0, stdout: buf.toString(), stderr: '');
  }

  // ===========================================================================
  // BUILT-IN: shopt
  // ===========================================================================

  Future<ShellResult> _cmdShopt(List<String> args) async {
    if (args.isEmpty) {
      final buf = StringBuffer();
      final sorted = _shopt.keys.toList()..sort();
      for (final key in sorted) {
        final val = _shopt[key]! ? 'on' : 'off';
        buf.writeln('$key\t$val');
      }
      return ShellResult(exitCode: 0, stdout: buf.toString(), stderr: '');
    }

    if (args[0] == '-s' && args.length > 1) {
      for (var i = 1; i < args.length; i++) {
        _shopt[args[i]] = true;
      }
      return _okResult;
    }

    if (args[0] == '-u' && args.length > 1) {
      for (var i = 1; i < args.length; i++) {
        _shopt[args[i]] = false;
      }
      return _okResult;
    }

    if (args[0] == '-p') {
      final buf = StringBuffer();
      final sorted = _shopt.keys.toList()..sort();
      for (final key in sorted) {
        buf.writeln('shopt -${_shopt[key]! ? 's' : 'u'} $key');
      }
      return ShellResult(exitCode: 0, stdout: buf.toString(), stderr: '');
    }

    // Query individual options
    final buf = StringBuffer();
    for (final arg in args) {
      if (_shopt.containsKey(arg)) {
        buf.writeln('$arg\t${_shopt[arg]! ? 'on' : 'off'}');
      }
    }
    return ShellResult(exitCode: 0, stdout: buf.toString(), stderr: '');
  }

  // ===========================================================================
  // BUILT-IN: command / builtin
  // ===========================================================================

  Future<ShellResult> _cmdCommand(List<String> args) async {
    if (args.isEmpty) {
      return const ShellResult(
        exitCode: 1, stdout: '', stderr: 'command: usage: command [-vV] cmd [args...]',
      );
    }
    var verboseFlag = false;
    var vFlag = false;
    var i = 0;
    while (i < args.length && args[i].startsWith('-')) {
      if (args[i] == '-v') { vFlag = true; i++; }
      else if (args[i] == '-V') { verboseFlag = true; i++; }
      else { break; }
    }
    if (i >= args.length) {
      return ShellResult(exitCode: 1, stdout: '', stderr: 'command: missing command name');
    }
    if (vFlag) {
      final cmdName = args[i];
      if (_builtins.containsKey(cmdName)) {
        return ShellResult(exitCode: 0, stdout: '$cmdName\n', stderr: '');
      }
      return ShellResult(exitCode: 1, stdout: '', stderr: '');
    }
    if (verboseFlag) {
      final cmdName = args[i];
      if (_builtins.containsKey(cmdName)) {
        return ShellResult(exitCode: 0, stdout: '$cmdName is a shell builtin\n', stderr: '');
      }
      return ShellResult(exitCode: 1, stdout: '', stderr: '');
    }
    final cmd = args.sublist(i).join(' ');
    return _runInShell(cmd);
  }

  Future<ShellResult> _cmdBuiltin(List<String> args) async {
    if (args.isEmpty) {
      return const ShellResult(
        exitCode: 1, stdout: '', stderr: 'builtin: usage: builtin [shell-builtin [args]]',
      );
    }
    final builtinName = args[0];
    final handler = _builtins[builtinName];
    if (handler == null) {
      return ShellResult(
        exitCode: 1, stdout: '', stderr: 'builtin: $builtinName: not a shell builtin',
      );
    }
    return handler(args.sublist(1));
  }

  // ===========================================================================
  // BUILT-IN: hash
  // ===========================================================================

  final Map<String, String> _hashTable = {};

  Future<ShellResult> _cmdHash(List<String> args) async {
    if (args.isEmpty) {
      if (_hashTable.isEmpty) {
        return ShellResult(exitCode: 0, stdout: 'hash: hash table empty\n', stderr: '');
      }
      final buf = StringBuffer();
      _hashTable.forEach((cmd, path) {
        buf.writeln('$cmd=$path');
      });
      return ShellResult(exitCode: 0, stdout: buf.toString(), stderr: '');
    }
    if (args[0] == '-r') {
      _hashTable.clear();
      return _okResult;
    }
    // Look up or store commands
    for (final cmd in args) {
      if (_hashTable.containsKey(cmd)) {
        // Already hashed — do nothing
      } else if (_builtins.containsKey(cmd)) {
        // Builtins are already resolved
      } else {
        // Try to find in PATH
        final pathDirs = (_env['PATH'] ?? '/bin:/usr/bin').split(':');
        for (final dir in pathDirs) {
          final fullPath = p.join(dir, cmd);
          try {
            if (FileSystemEntity.isFileSync(fullPath)) {
              _hashTable[cmd] = fullPath;
              break;
            }
          } catch (_) {}
        }
      }
    }
    return _okResult;
  }

  // ===========================================================================
  // BUILT-IN: fc
  // ===========================================================================

  Future<ShellResult> _cmdFc(List<String> args) async {
    // fc -l [range] : list history
    // fc -s [pattern] : re-execute command
    // fc [first] [last] : edit and re-execute (not supported)
    var listMode = false;
    var i = 0;
    while (i < args.length && args[i].startsWith('-')) {
      if (args[i] == '-l') { listMode = true; i++; }
      else if (args[i] == '-s') { i++; }
      else if (args[i] == '-e' && i + 1 < args.length) { i += 2; }
      else { i++; }
    }

    if (listMode) {
      final buf = StringBuffer();
      final start = _history.length > 16 ? _history.length - 16 : 0;
      for (var j = start; j < _history.length; j++) {
        buf.writeln('${j + 1}\t${_history[j]}');
      }
      return ShellResult(exitCode: 0, stdout: buf.toString(), stderr: '');
    }

    // Execute last command
    if (_history.isNotEmpty) {
      final lastCmd = _history.last;
      return execute(lastCmd);
    }
    return _okResult;
  }

  // ===========================================================================
  // BUILT-IN: ulimit
  // ===========================================================================

  Future<ShellResult> _cmdUlimit(List<String> args) async {
    var i = 0;
    while (i < args.length && args[i].startsWith('-')) {
      i++;
    }
    if (i < args.length) {}
    return ShellResult(exitCode: 0, stdout: 'unlimited\n', stderr: '');
  }

  // ===========================================================================
  // BUILT-IN: umask
  // ===========================================================================

  Future<ShellResult> _cmdUmask(List<String> args) async {
    if (args.isNotEmpty && RegExp(r'^[0-7]{1,4}$').hasMatch(args[0])) {
      // Accept but don't enforce mask setting
      return _okResult;
    }
    // Print current umask
    return ShellResult(exitCode: 0, stdout: '0022\n', stderr: '');
  }

  // ===========================================================================
  // BUILT-IN: logout / suspend / times / caller / bind / complete / compgen / enable / readonly / getopts
  // ===========================================================================

  Future<ShellResult> _cmdLogout(List<String> args) async {
    _exitRequested = true;
    return const ShellResult(exitCode: 0, stdout: '', stderr: '');
  }

  Future<ShellResult> _cmdSuspend(List<String> args) async {
    return const ShellResult(
      exitCode: 1, stdout: '', stderr: 'suspend: cannot suspend (VFS shell)',
    );
  }

  Future<ShellResult> _cmdTimes(List<String> args) async {
    // Report accumulated user and system time for the shell
    final elapsed = _shellTimer.elapsed;
    final minutes = elapsed.inMinutes;
    final seconds = elapsed.inSeconds % 60;
    final millis = (elapsed.inMilliseconds % 1000) ~/ 100;
    return ShellResult(
      exitCode: 0,
      stdout: '${minutes}m$seconds.${millis}s ${minutes}m$seconds.${millis}s\n',
      stderr: '',
    );
  }

  Future<ShellResult> _cmdCaller(List<String> args) async {
    return const ShellResult(exitCode: 0, stdout: '0\n', stderr: '');
  }

  Future<ShellResult> _cmdBind(List<String> args) async {
    if (args.isEmpty) {
      return const ShellResult(exitCode: 0, stdout: '', stderr: '');
    }
    if (args.length >= 2 && args[0] == '-x') {
      // Bind a key sequence to a shell command (simplified — store in keybindings)
      return _okResult;
    }
    return _okResult;
  }

  Future<ShellResult> _cmdComplete(List<String> args) async {
    if (args.isEmpty) {
      if (_completions.isEmpty) return _okResult;
      final buf = StringBuffer();
      _completions.forEach((cmd, words) {
        buf.writeln('complete $cmd');
      });
      return ShellResult(exitCode: 0, stdout: buf.toString(), stderr: '');
    }
    if (args[0] == '-r' && args.length > 1) {
      _completions.remove(args[1]);
      return _okResult;
    }
    if (args[0] == '-p' && args.length > 1) {
      // Print completion for specific command
      if (_completions.containsKey(args[1])) {
        return ShellResult(exitCode: 0, stdout: 'complete ${args[1]}\n', stderr: '');
      }
      return ShellResult(exitCode: 1, stdout: '', stderr: '');
    }

    var wordList = <String>[];
    var i = 0;
    while (i < args.length && args[i].startsWith('-')) {
      if (args[i] == '-W' && i + 1 < args.length) {
        wordList = args[i + 1].split(RegExp(r'\s+'));
        i += 2;
      } else if (args[i] == '-A' && i + 1 < args.length) {
        i += 2;
      } else if (args[i] == '-C' && i + 1 < args.length) {
        i += 2;
      } else if (args[i] == '-F' && i + 1 < args.length) {
        i += 2;
      } else if (args[i] == '-G' && i + 1 < args.length) {
        i += 2;
      } else if (args[i] == '-X' && i + 1 < args.length) {
        i += 2;
      } else if (args[i] == '-P' && i + 1 < args.length) {
        i += 2;
      } else if (args[i] == '-S' && i + 1 < args.length) {
        i += 2;
      } else if (args[i] == '-o' && i + 1 < args.length) {
        i += 2;
      } else if (args[i] == '-D') {
        i++;
      } else if (args[i] == '-E') {
        i++;
      } else { i++; }
    }
    if (i < args.length) {
      _completions[args[i]] = wordList;
    }
    return _okResult;
  }

  Future<ShellResult> _cmdCompgen(List<String> args) async {
    var action = 'file';
    var wordList = <String>[];
    var i = 0;
    while (i < args.length && args[i].startsWith('-')) {
      if (args[i] == '-W' && i + 1 < args.length) {
        wordList = args[i + 1].split(RegExp(r'\s+'));
        i += 2;
      } else if (args[i] == '-A' && i + 1 < args.length) {
        action = args[i + 1];
        i += 2;
      } else if (args[i] == '-G' && i + 1 < args.length) {
        i += 2;
      } else if (args[i] == '-X' && i + 1 < args.length) {
        i += 2;
      } else if (args[i] == '-F' && i + 1 < args.length) {
        i += 2;
      } else if (args[i] == '-C' && i + 1 < args.length) {
        i += 2;
      } else if (args[i] == '-P' && i + 1 < args.length) {
        i += 2;
      } else if (args[i] == '-S' && i + 1 < args.length) {
        i += 2;
      } else { i++; }
    }

    final buf = StringBuffer();

    if (wordList.isNotEmpty) {
      for (final word in wordList) {
        buf.writeln(word);
      }
      return ShellResult(exitCode: 0, stdout: buf.toString(), stderr: '');
    }

    if (action == 'file' || action == 'directory') {
      // List files in cwd
      try {
        final entries = await _vfs.list(_cwd);
        for (final entry in entries) {
          final name = entry.name;
          if (action == 'directory') {
            if (entry.isDirectory) buf.writeln(name);
          } else {
            buf.writeln(name);
          }
        }
      } catch (_) {}
    }

    if (action == 'builtin') {
      for (final builtin in _builtins.keys) {
        buf.writeln(builtin);
      }
    }

    if (action == 'function') {
      for (final fn in _functions.keys) {
        buf.writeln(fn);
      }
    }

    if (action == 'command' || action == 'file') {
      final pathDirs = (_env['PATH'] ?? '/bin:/usr/bin').split(':');
      final seen = <String>{};
      for (final dir in pathDirs) {
        try {
          final entries = Directory(dir).listSync();
          for (final entry in entries) {
            final name = p.basename(entry.path);
            if (seen.add(name)) buf.writeln(name);
          }
        } catch (_) {}
      }
    }

    return ShellResult(exitCode: 0, stdout: buf.toString(), stderr: '');
  }

  Future<ShellResult> _cmdEnable(List<String> args) async {
    return const ShellResult(
      exitCode: 0, stdout: '', stderr: 'enable: not supported in VFS shell',
    );
  }

  Future<ShellResult> _cmdReadonly(List<String> args) async {
    if (args.isEmpty) {
      final buf = StringBuffer();
      // readonly without args lists readonly vars — we don't track readonly state
      return ShellResult(exitCode: 0, stdout: buf.toString(), stderr: '');
    }
    for (final arg in args) {
      final eq = arg.indexOf('=');
      if (eq > 0) {
        _env[arg.substring(0, eq)] = arg.substring(eq + 1);
      }
    }
    return _okResult;
  }



  Future<ShellResult> _cmdSelect(List<String> args) async {
    // select name [in word ...]; do body; done
    // When used as a builtin (fallback from AST parsing), this is a simplified version.
    // The AST executor handles the full version via SelectNode.
    if (args.isEmpty) {
      return const ShellResult(
        exitCode: 1, stdout: '', stderr: 'select: usage: select name [in words ...]; do commands; done',
      );
    }
    final varName = args[0];
    final items = args.length > 1 ? args.sublist(1) : (_env['@']?.split(' ') ?? []);
    if (items.isEmpty) return _okResult;
    while (true) {
      for (var idx = 0; idx < items.length; idx++) {
        _writeToStdout('${idx + 1}) ${items[idx]}\n');
      }
      _writeToStdout('#? ');
      final line = stdin.readLineSync();
      if (line == null) break;
      if (line.isEmpty) continue;
      final choice = int.tryParse(line);
      if (choice != null && choice >= 1 && choice <= items.length) {
        _env[varName] = items[choice - 1];
        _env['REPLY'] = line;
      } else {
        _env['REPLY'] = line;
        _env[varName] = '';
      }
      // In the non-AST path, select acts as a simple menu without body execution
    }
    return _okResult;
  }

  Future<ShellResult> _cmdGetopts(List<String> args) async {
    // getopts optstring name [args...]
    if (args.length < 2) {
      return ShellResult(exitCode: 1, stdout: '', stderr: 'getopts: usage: getopts optstring name [args]\n');
    }
    final optstring = args[0];
    final varName = args[1];
    final userArgs = args.sublist(2);

    // Determine the list of arguments to parse
    final argsToParse = userArgs.isNotEmpty ? userArgs : _positionalParams;

    // Simple state tracking
    var optIndex = _getoptsIndex;
    if (optIndex >= argsToParse.length) {
      _env[varName] = '?';
      _getoptsIndex = 0;
      return ShellResult(exitCode: 1, stdout: '', stderr: '');
    }

    final current = argsToParse[optIndex];
    if (!current.startsWith('-') || current == '-') {
      _env[varName] = '?';
      _getoptsIndex = 0;
      return ShellResult(exitCode: 1, stdout: '', stderr: '');
    }

    if (current == '--') {
      _getoptsIndex++;
      _env[varName] = '?';
      return ShellResult(exitCode: 1, stdout: '', stderr: '');
    }

    // Parse the option character
    var optChar = '';
    var optArg = '';

    // Get current position in the option string
    var pos = _getoptsPos;
    if (pos == 0) pos = 1; // skip '-'

    if (pos < current.length) {
      optChar = current[pos];
      pos++;

      // Check if this option expects an argument
      final optIdx = optstring.indexOf(optChar);
      if (optIdx >= 0 && optIdx + 1 < optstring.length && optstring[optIdx + 1] == ':') {
        // Option requires an argument
        if (pos < current.length) {
          // Argument is in the same string: -oarg
          optArg = current.substring(pos);
          pos = current.length;
        } else if (optIndex + 1 < argsToParse.length) {
          // Argument is the next word
          optArg = argsToParse[optIndex + 1];
          optIndex++;
          pos = 0;
        } else {
          // Missing argument
          _env[varName] = ':';
          _getoptsIndex = optIndex + 1;
          _getoptsPos = 0;
          _env['OPTARG'] = optChar;
          return ShellResult(exitCode: 1, stdout: '', stderr: '');
        }
      }

      _env[varName] = optChar;
      _env['OPTARG'] = optArg;
      _getoptsPos = pos < current.length ? pos : 0;
      _getoptsIndex = _getoptsPos == 0 ? optIndex + 1 : optIndex;
      return _okResult;
    }

    _getoptsIndex++;
    _getoptsPos = 0;
    _env[varName] = '?';
    return ShellResult(exitCode: 1, stdout: '', stderr: '');
  }

  // ===========================================================================
  // BUILT-IN: date
  // ===========================================================================

  Future<ShellResult> _cmdDate(List<String> args) async {
    if (args.isEmpty) {
      return ShellResult(exitCode: 0, stdout: '${DateTime.now()}\n', stderr: '');
    }
    if (args[0] == '-u' || args[0] == '--utc' || args[0] == '--universal') {
      return ShellResult(exitCode: 0, stdout: '${DateTime.now().toUtc()}\n', stderr: '');
    }
    if (args[0] == '-I' || args[0] == '--iso-8601') {
      final now = DateTime.now();
      return ShellResult(
        exitCode: 0,
        stdout: '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}\n',
        stderr: '',
      );
    }
    if (args[0] == '-r' && args.length > 1) {
      // date -r <file> — show last modified time of file
      final target = _resolvePath(args[1]);
      try {
        final abs = _vfsAbsolute(target);
        final stat = File(abs).statSync();
        return ShellResult(exitCode: 0, stdout: '${stat.modified}\n', stderr: '');
      } catch (e) {
        return ShellResult(exitCode: 1, stdout: '', stderr: 'date: $e\n');
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
      return ShellResult(exitCode: 0, stdout: 'Thu Jan  1 00:00:00 UTC 1970\n', stderr: '');
    }
    if (args.length >= 2 && args[0] == '-d' && args[1].startsWith('@')) {
      final secs = int.tryParse(args[1].substring(1));
      if (secs != null) {
        final dt = DateTime.fromMillisecondsSinceEpoch(secs * 1000, isUtc: true);
        return ShellResult(exitCode: 0, stdout: '$dt\n', stderr: '');
      }
    }
    if (args[0] == '+%Y') {
      return ShellResult(exitCode: 0, stdout: '${DateTime.now().year}\n', stderr: '');
    }
    return ShellResult(exitCode: 0, stdout: '${DateTime.now()}\n', stderr: '');
  }

  // ===========================================================================
  // BUILT-IN: basename
  // ===========================================================================

  Future<ShellResult> _cmdBasename(List<String> args) async {
    if (args.isEmpty) {
      return const ShellResult(
        exitCode: 1, stdout: '', stderr: 'basename: missing operand',
      );
    }
    var path = args[0];
    var suffix = args.length > 2 ? args[2] : (args.length > 1 && !args[1].startsWith('-') ? args[1] : '');
    final name = p.basename(path);
    if (suffix.isNotEmpty && name.endsWith(suffix)) {
      return ShellResult(exitCode: 0, stdout: '${name.substring(0, name.length - suffix.length)}\n', stderr: '');
    }
    return ShellResult(exitCode: 0, stdout: '$name\n', stderr: '');
  }

  // ===========================================================================
  // BUILT-IN: dirname
  // ===========================================================================

  Future<ShellResult> _cmdDirname(List<String> args) async {
    if (args.isEmpty) {
      return const ShellResult(
        exitCode: 1, stdout: '', stderr: 'dirname: missing operand',
      );
    }
    final dir = p.dirname(args[0]);
    return ShellResult(exitCode: 0, stdout: '${dir.isEmpty ? '.' : dir}\n', stderr: '');
  }

  // ===========================================================================
  // BUILT-IN: realpath / readlink
  // ===========================================================================

  Future<ShellResult> _cmdRealpath(List<String> args) async {
    if (args.isEmpty) {
      return const ShellResult(
        exitCode: 1, stdout: '', stderr: 'realpath: missing operand',
      );
    }
    try {
      final resolved = _resolvePath(args[0]);
      final abs = _vfsAbsolute(resolved);
      return ShellResult(exitCode: 0, stdout: '$abs\n', stderr: '');
    } catch (e) {
      return ShellResult(exitCode: 1, stdout: '', stderr: 'realpath: $e\n');
    }
  }

  // ===========================================================================
  // BUILT-IN: uniq
  // ===========================================================================

  Future<ShellResult> _cmdUniq(List<String> args) async {
    var file = '';
    var i = 0;
    while (i < args.length && args[i].startsWith('-')) {
      i++;
    }
    if (i < args.length) file = args[i];

    if (file.isEmpty) {
      return const ShellResult(
        exitCode: 1, stdout: '', stderr: 'uniq: missing file operand',
      );
    }

    try {
      final target = _resolvePath(file);
      final content = await _vfs.readFileAsString(target);
      final lines = content.split('\n');
      final output = StringBuffer();
      String? last;
      for (final line in lines) {
        if (line != last) {
          output.writeln(line);
          last = line;
        }
      }
      return ShellResult(exitCode: 0, stdout: output.toString(), stderr: '');
    } catch (e) {
      return ShellResult(exitCode: 1, stdout: '', stderr: 'uniq: $e\n');
    }
  }

  // ===========================================================================
  // BUILT-IN: declare / local
  // ===========================================================================

  Future<ShellResult> _cmdDeclare(List<String> args) async {
    if (args.isEmpty) {
      final buf = StringBuffer();
      _env.forEach((k, v) => buf.writeln('declare -- $k="$v"'));
      _arrays.forEach((k, v) {
        buf.writeln('declare -a $k=(${v.map((s) => '"$s"').join(' ')})');
      });
      _assocArrays.forEach((k, v) {
        buf.writeln('declare -A $k=(${v.entries.map((e) => '["${e.key}"]="${e.value}"').join(' ')})');
      });
      return ShellResult(exitCode: 0, stdout: buf.toString(), stderr: '');
    }

    var isArray = false;
    var isAssoc = false;
    var i = 0;
    while (i < args.length && args[i].startsWith('-')) {
      if (args[i] == '-p') { i++; continue; }
      if (args[i] == '-a') { isArray = true; i++; continue; }
      if (args[i] == '-A') { isAssoc = true; i++; continue; }
      if (args[i] == '-i') { i++; continue; }
      if (args[i] == '-r') { i++; continue; }
      if (args[i] == '-x') { i++; continue; }
      break;
    }

    for (; i < args.length; i++) {
      final eq = args[i].indexOf('=');
      if (eq > 0) {
        final name = args[i].substring(0, eq);
        var rawValue = args[i].substring(eq + 1);

        if (rawValue.startsWith('(') && rawValue.endsWith(')')) {
          final inner = rawValue.substring(1, rawValue.length - 1);
          if (isAssoc || RegExp(r'\[.*\]=').hasMatch(inner)) {
            final assocMap = <String, String>{};
            var j = 0;
            while (j < inner.length) {
              if (inner[j] == ' ' || inner[j] == '\t') { j++; continue; }
              if (inner[j] == '[') {
                j++;
                final keyStart = j;
                while (j < inner.length && inner[j] != ']') { j++; }
                final key = inner.substring(keyStart, j);
                j++; // skip ]
                if (j < inner.length && inner[j] == '=') j++;
                // Read value (quoted or unquoted)
                if (j < inner.length && (inner[j] == '"' || inner[j] == '\'')) {
                  final quote = inner[j];
                  j++;
                  final valStart = j;
                  while (j < inner.length && inner[j] != quote) { j++; }
                  assocMap[key] = inner.substring(valStart, j);
                  j++;
                } else {
                  final valStart = j;
                  while (j < inner.length && inner[j] != ' ' && inner[j] != '\t') { j++; }
                  assocMap[key] = inner.substring(valStart, j);
                }
              } else {
                j++;
              }
            }
            _assocArrays[name] = assocMap;
            _env[name] = assocMap.values.join(' ');
          } else {
            final values = _splitArrayValuesSimple(inner);
            _arrays[name] = values;
            _env[name] = values.join(' ');
          }
        } else {
          if (isArray) {
            _arrays[name] = [rawValue];
          } else if (isAssoc) {
            _assocArrays[name] = {};
          }
          _env[name] = rawValue;
        }
      } else if (eq != 0) {
        final val = _lookupVar(args[i]);
        final isArr = _arrays.containsKey(args[i]);
        final isAss = _assocArrays.containsKey(args[i]);
        if (isArr) {
          return ShellResult(
            exitCode: 0,
            stdout: 'declare -a ${args[i]}=(${_arrays[args[i]]!.map((s) => '"$s"').join(' ')})\n',
            stderr: '',
          );
        }
        if (isAss) {
          return ShellResult(
            exitCode: 0,
            stdout: 'declare -A ${args[i]}=(${_assocArrays[args[i]]!.entries.map((e) => '["${e.key}"]="${e.value}"').join(' ')})\n',
            stderr: '',
          );
        }
        return ShellResult(
          exitCode: 0,
          stdout: 'declare -- ${args[i]}="$val"\n',
          stderr: '',
        );
      }
    }

    return _okResult;
  }

  List<String> _splitArrayValuesSimple(String s) {
    final parts = <String>[];
    var inSingle = false;
    var inDouble = false;
    var current = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (inSingle) {
        if (c == '\'') { inSingle = false; }
        else { current.write(c); }
        continue;
      }
      if (inDouble) {
        if (c == '"') { inDouble = false; }
        else if (c == '\\' && i + 1 < s.length) { i++; current.write(s[i]); }
        else { current.write(c); }
        continue;
      }
      if (c == '\'') { inSingle = true; continue; }
      if (c == '"') { inDouble = true; continue; }
      if (c == ' ' || c == '\t') {
        if (current.isNotEmpty) { parts.add(current.toString()); current.clear(); }
      } else {
        current.write(c);
      }
    }
    if (current.isNotEmpty) parts.add(current.toString());
    return parts;
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
