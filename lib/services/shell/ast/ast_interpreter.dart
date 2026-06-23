import 'dart:async';
import 'dart:io' show stdout, stdin, Process, File;

import '../../vfs/vfs_ast.dart';
import '../shell_builtin.dart';
import '../shell_result.dart';
import '../shell_state.dart';

typedef ExecuteWords = Future<ShellResult> Function(List<String> words);
typedef ExecuteString = Future<ShellResult> Function(String cmd);

class AstInterpreter {
  final ShellContext ctx;
  final ExecuteWords executeWords;
  final ExecuteString executeString;

  AstInterpreter({
    required this.ctx,
    required this.executeWords,
    required this.executeString,
  });

  Future<ShellResult> interpret(AstNode node) {
    return _executeAstInner(node);
  }

  Future<ShellResult> _executeAstInner(AstNode node) async {
    switch (node) {
      case ProgramNode n:
        ShellResult last = ShellResult.ok;
        for (final stmt in n.statements) {
          last = await _executeAstInner(stmt);
          if (ctx.state.returnFromFunction || ctx.state.exitRequested) break;
        }
        return last;

      case SeqNode n:
        ShellResult last = ShellResult.ok;
        for (final stmt in n.nodes) {
          last = await _executeAstInner(stmt);
          if (ctx.state.returnFromFunction || ctx.state.exitRequested) break;
        }
        return last;

      case AndOrNode n:
        final left = await _executeAstInner(n.left);
        if (n.op == AndOrOp.and) {
          if (left.exitCode == 0) return _executeAstInner(n.right);
          return left;
        } else {
          if (left.exitCode != 0) return _executeAstInner(n.right);
          return left;
        }

      case PipelineNode n:
        if (n.commands.isEmpty) return ShellResult.ok;
        if (n.commands.length == 1) {
          return _executeAstInner(n.commands.first);
        }
        final cmdStrs = <String>[];
        for (final cmd in n.commands) {
          if (cmd is SimpleCmdNode) {
            cmdStrs.add(cmd.words.join(' '));
          } else {
            return executeString(
              n.commands.map((c) => _astToString(c)).join(' | '),
            );
          }
        }
        final result = await executeString(cmdStrs.join(' | '));
        if (ctx.state.shopt['pipefail'] == true && result.exitCode != 0) {
          return result;
        }
        return result;

      case BackgroundNode n:
        final cmdStr = _astToString(n.command);
        final jobId = ctx.state.nextJobId++;
        final proc = await Process.start(
          '/bin/sh', ['-c', cmdStr],
          workingDirectory: ctx.state.cwd,
          environment: Map<String, String>.from(ctx.state.env),
        );
        ctx.state.jobs[jobId] = Job(jobId, cmdStr, proc, 'running');
        ctx.state.lastBgPid = proc.pid;
        unawaited(proc.exitCode.then((code) {
          if (ctx.state.jobs.containsKey(jobId)) {
            ctx.state.jobs[jobId]!.status = 'done';
            ctx.state.jobs[jobId]!.exitCode = code;
          }
        }));
        stdout.write('[$jobId] $jobId\n');
        return ShellResult.ok;

      case SimpleCmdNode n:
        if (n.words.isEmpty) {
          if (n.redirects.isNotEmpty) {
            return _executeRedirectsOnly(n.redirects);
          }
          return ShellResult.ok;
        }
        return _executePreTokenized(n.words);

      case IfNode n:
        final condResult = await _executeAstInner(n.condition);
        if (condResult.exitCode == 0) {
          return _executeAstInner(n.thenBody);
        }
        for (final elif in n.elifs) {
          final elifResult = await _executeAstInner(elif.condition);
          if (elifResult.exitCode == 0) {
            return _executeAstInner(elif.body);
          }
        }
        if (n.elseBody != null) {
          return _executeAstInner(n.elseBody!);
        }
        return ShellResult.ok;

      case WhileNode n:
        while (true) {
          final condResult = await _executeAstInner(n.condition);
          if (condResult.exitCode != 0) break;
          if (ctx.state.breakDepth > 0) { ctx.state.breakDepth--; break; }
          if (ctx.state.continueDepth > 0) { ctx.state.continueDepth = 0; continue; }
          if (ctx.state.returnFromFunction || ctx.state.exitRequested) break;
          await _executeAstInner(n.body);
          if (ctx.state.breakDepth > 0) { ctx.state.breakDepth--; break; }
          if (ctx.state.continueDepth > 0) { ctx.state.continueDepth = 0; continue; }
        }
        return ShellResult.ok;

      case UntilNode n:
        while (true) {
          final condResult = await _executeAstInner(n.condition);
          if (condResult.exitCode == 0) break;
          if (ctx.state.breakDepth > 0) { ctx.state.breakDepth--; break; }
          if (ctx.state.continueDepth > 0) { ctx.state.continueDepth = 0; continue; }
          if (ctx.state.returnFromFunction || ctx.state.exitRequested) break;
          await _executeAstInner(n.body);
          if (ctx.state.breakDepth > 0) { ctx.state.breakDepth--; break; }
          if (ctx.state.continueDepth > 0) { ctx.state.continueDepth = 0; continue; }
        }
        return ShellResult.ok;

      case ForNode n:
        final words = n.words.isNotEmpty
            ? n.words
            : (ctx.state.lookupVar('@').split(' ')..removeWhere((s) => s.isEmpty));
        for (final word in words) {
          ctx.state.env[n.variable] = word;
          if (ctx.state.returnFromFunction || ctx.state.exitRequested) break;
          await _executeAstInner(n.body);
          if (ctx.state.breakDepth > 0) { ctx.state.breakDepth--; break; }
          if (ctx.state.continueDepth > 0) { ctx.state.continueDepth = 0; continue; }
        }
        return ShellResult.ok;

      case CaseNode n:
        for (final item in n.items) {
          for (final pattern in item.patterns) {
            if (_matchCasePattern(n.word, pattern)) {
              return _executeAstInner(item.body);
            }
          }
        }
        return ShellResult.ok;

      case FunctionDefNode n:
        ctx.state.functions[n.name] = n.body;
        return ShellResult.ok;

      case BlockNode n:
        return _executeAstInner(n.body);

      case SubshellNode n:
        return executeString(_astToString(n));

      case AssignmentNode n:
        ctx.state.env[n.name] = n.value;
        return ShellResult.ok;

      case ArrayAssignmentNode n:
        ctx.state.arrays[n.name] = n.values;
        return ShellResult.ok;

      case BreakNode n:
        ctx.state.breakDepth = n.count;
        return ShellResult.ok;

      case ContinueNode n:
        ctx.state.continueDepth = n.count;
        return ShellResult.ok;

      case ReturnNode n:
        ctx.state.returnFromFunction = true;
        return ShellResult(exitCode: n.code, stdout: '', stderr: '');

      case ExitNode n:
        ctx.state.exitRequested = true;
        return ShellResult(exitCode: n.code, stdout: '', stderr: '');

      case CForNode n:
        if (n.init != null && n.init!.contains('=')) {
          final parts = n.init!.split('=');
          if (parts.length >= 2) {
            ctx.state.env[parts[0].trim()] = parts.sublist(1).join('=');
          }
        }
        bool evalCond(String? cond) {
          if (cond == null || cond.isEmpty) return true;
          final val = ctx.arithmetic.eval(cond);
          return val != 0;
        }
        while (evalCond(n.condition)) {
          if (ctx.state.breakDepth > 0) { ctx.state.breakDepth--; break; }
          if (ctx.state.continueDepth > 0) { ctx.state.continueDepth = 0; break; }
          if (ctx.state.returnFromFunction || ctx.state.exitRequested) break;
          await _executeAstInner(n.body);
          if (ctx.state.breakDepth > 0) { ctx.state.breakDepth--; break; }
          if (ctx.state.continueDepth > 0) { ctx.state.continueDepth = 0; break; }
          if (n.increment != null && n.increment!.isNotEmpty) {
            ctx.arithmetic.eval(n.increment!);
          }
        }
        return ShellResult.ok;

      case SelectNode n:
        final items = n.words.isNotEmpty
            ? n.words
            : (ctx.state.lookupVar('@').split(' ')..removeWhere((s) => s.isEmpty));
        if (items.isEmpty) return ShellResult.ok;
        while (true) {
          for (var idx = 0; idx < items.length; idx++) {
            stdout.write('${idx + 1}) ${items[idx]}\n');
          }
          stdout.write('#? ');
          final line = stdin.readLineSync();
          if (line == null) break;
          if (line.isEmpty) continue;
          final choice = int.tryParse(line);
          if (choice != null && choice >= 1 && choice <= items.length) {
            ctx.state.env[n.variable] = items[choice - 1];
            ctx.state.env['REPLY'] = line;
          } else {
            ctx.state.env['REPLY'] = line;
            ctx.state.env[n.variable] = '';
          }
          await _executeAstInner(n.body);
          if (ctx.state.breakDepth > 0) { ctx.state.breakDepth--; break; }
          if (ctx.state.returnFromFunction || ctx.state.exitRequested) break;
        }
        return ShellResult.ok;

      case CoprocNode n:
        final cmdStr = _astToString(n.body);
        final proc = await Process.start(
          '/bin/sh', ['-c', cmdStr],
          workingDirectory: ctx.state.cwd,
          environment: Map<String, String>.from(ctx.state.env),
        );
        ctx.state.env['${n.name}_PID'] = proc.pid.toString();
        unawaited(proc.exitCode.then((_) {}));
        return ShellResult.ok;
    }
  }

  Future<ShellResult> _executePreTokenized(List<String> words) async {
    final expanded = <String>[];
    for (var i = 0; i < words.length; i++) {
      var w = words[i];
      w = ctx.expander.expandVars(w);
      w = ctx.expander.expandTilde(w);
      expanded.add(w);
    }

    if (expanded.isEmpty) return ShellResult.ok;
    final cmd = expanded[0];
    final args = expanded.sublist(1);

    // Apply brace + glob expansion to args
    final finalArgs = <String>[];
    for (final arg in args) {
      for (final braced in ctx.expander.expandBraces(arg)) {
        final globbed = ctx.expander.expandGlob(braced);
        finalArgs.addAll(globbed);
      }
    }
    ctx.state.underscore = finalArgs.isNotEmpty ? finalArgs.last : cmd;

    if (ctx.builtins.containsKey(cmd)) {
      return ctx.builtins.call(cmd, ctx, finalArgs);
    }

    if (ctx.state.functions.containsKey(cmd)) {
      final ast = ctx.state.functions[cmd]!;
      final savedParams = List<String>.from(ctx.state.positionalParams);
      ctx.state.positionalParams = finalArgs;
      ctx.state.env['@'] = finalArgs.join(' ');
      ctx.state.env['#'] = ctx.state.positionalParams.length.toString();
      final funcResult = await _executeAstInner(ast);
      ctx.state.returnFromFunction = false;
      ctx.state.positionalParams = savedParams;
      ctx.state.env['@'] = savedParams.join(' ');
      ctx.state.env['#'] = savedParams.length.toString();
      return funcResult;
    }

    return executeString(expanded.join(' '));
  }

  Future<ShellResult> _executeRedirectsOnly(List<RedirectNode> redirects) async {
    var stdout = '';
    var stderr = '';
    for (final r in redirects) {
      final target = ctx.expander.resolvePath(r.target);
      final abs = ctx.vfsAbsolute(target);
      if (r.srcFd == -1 || r.op == '&>') {
        final content = '${stdout.trim()}\n${stderr.trim()}'.trim();
        await ctx.vfs.writeFile(target, content);
        stdout = '';
        stderr = '';
      } else if (r.isOutput) {
        if (r.isAppend) {
          final existing = _existingContent(abs);
          stdout = existing.isNotEmpty ? '$existing\n$stdout' : stdout;
        }
        await ctx.vfs.writeFile(target, stdout);
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
      final caseSensitive = ctx.state.shopt['nocasematch'] != true;
      final regex = RegExp('^${_globToRegexStr(pattern)}\$',
          caseSensitive: caseSensitive);
      return regex.hasMatch(word);
    } catch (_) {
      return word == pattern;
    }
  }

  String _globToRegexStr(String pattern) {
    final buf = StringBuffer();
    var i = 0;
    while (i < pattern.length) {
      final c = pattern[i];
      if (c == '*') {
        buf.write('.*');
      } else if (c == '?') {
        buf.write('.');
      } else if (c == '.') {
        buf.write('\\.');
      } else if (c == '[') {
        buf.write('[');
        i++;
        if (i < pattern.length && pattern[i] == '!') {
          buf.write('^');
          i++;
        } else if (i < pattern.length && pattern[i] == '^') {
          buf.write('^');
          i++;
        }
        while (i < pattern.length && pattern[i] != ']') {
          if (pattern[i] == '\\' && i + 1 < pattern.length) {
            buf.write('\\${pattern[i + 1]}');
            i += 2;
          } else {
            buf.write(pattern[i]);
            i++;
          }
        }
        if (i < pattern.length && pattern[i] == ']') buf.write(']');
      } else if (c == '\\' && i + 1 < pattern.length) {
        buf.write(RegExp.escape(pattern[i + 1]));
        i++;
      } else {
        buf.write(RegExp.escape(c));
      }
      i++;
    }
    return buf.toString();
  }

  String _existingContent(String abs) {
    try {
      return File(abs).readAsStringSync();
    } catch (_) {
      return '';
    }
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
}
