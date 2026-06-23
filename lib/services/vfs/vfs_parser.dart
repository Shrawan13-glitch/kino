import 'vfs_ast.dart';

enum TokKind {
  word,
  reserved,
  pipe,
  pipeAnd,
  and,
  or,
  semicolon,
  doubleSemicolon,
  background,
  redirectIn,
  redirectOut,
  redirectAppend,
  redirectHereDoc,
  redirectHereStr,
  redirectBoth,
  redirectFd,
  leftParen,
  rightParen,
  leftBrace,
  rightBrace,
  dParen,
  dParenClose,
  procSubstIn,
  procSubstOut,
  eof,
}

class Token {
  final TokKind kind;
  final String value;
  final int pos;
  Token(this.kind, this.value, this.pos);
}

class _Lexer {
  final String _input;
  int _pos = 0;
  final List<Token> _tokens = [];

  _Lexer(this._input);

  List<Token> tokenize() {
    _tokens.clear();
    while (_pos < _input.length) {
      final c = _input[_pos];

      if (c == ' ' || c == '\t' || c == '\n') {
        _pos++;
        continue;
      }

      if (c == '#' && (_pos == 0 || _input[_pos - 1] == '\n' || _input[_pos - 1] == ' ' || _input[_pos - 1] == '\t' || _input[_pos - 1] == ';' || _input[_pos - 1] == '|' || _input[_pos - 1] == '&')) {
        while (_pos < _input.length && _input[_pos] != '\n') { _pos++; }
        continue;
      }

      // Process substitution: <(
      if (c == '<' && _pos + 1 < _input.length && _input[_pos + 1] == '(') {
        _add(TokKind.procSubstIn, '<(');
        _pos += 2;
        continue;
      }

      // Process substitution: >(
      if (c == '>' && _pos + 1 < _input.length && _input[_pos + 1] == '(') {
        _add(TokKind.procSubstOut, '>(');
        _pos += 2;
        continue;
      }

      if (c == '|') {
        if (_pos + 1 < _input.length && _input[_pos + 1] == '|') {
          _add(TokKind.or, '||');
          _pos += 2;
        } else if (_pos + 1 < _input.length && _input[_pos + 1] == '&') {
          _add(TokKind.pipeAnd, '|&');
          _pos += 2;
        } else {
          _add(TokKind.pipe, '|');
          _pos++;
        }
        continue;
      }

      if (c == '&') {
        if (_pos + 1 < _input.length && _input[_pos + 1] == '&') {
          _add(TokKind.and, '&&');
          _pos += 2;
        } else {
          _add(TokKind.background, '&');
          _pos++;
        }
        continue;
      }

      if (c == ';') {
        if (_pos + 1 < _input.length && _input[_pos + 1] == ';') {
          _add(TokKind.doubleSemicolon, ';;');
          _pos += 2;
        } else {
          _add(TokKind.semicolon, ';');
          _pos++;
        }
        continue;
      }

      // Redirections
      if (c == '>') {
        if (_pos + 1 < _input.length && _input[_pos + 1] == '>') {
          _add(TokKind.redirectAppend, '>>');
          _pos += 2;
        } else if (_pos + 1 < _input.length && _input[_pos + 1] == '&') {
          _add(TokKind.redirectFd, '>&');
          _pos += 2;
        } else if (_pos + 1 < _input.length && _input[_pos + 1] == '|') {
          _add(TokKind.redirectBoth, '>|');
          _pos += 2;
        } else {
          _add(TokKind.redirectOut, '>');
          _pos++;
        }
        continue;
      }

      if (c == '<') {
        if (_pos + 1 < _input.length && _input[_pos + 1] == '<') {
          if (_pos + 2 < _input.length && _input[_pos + 2] == '<') {
            _add(TokKind.redirectHereStr, '<<<');
            _pos += 3;
          } else {
            _add(TokKind.redirectHereDoc, '<<');
            _pos += 2;
          }
        } else if (_pos + 1 < _input.length && _input[_pos + 1] == '>') {
          _add(TokKind.redirectBoth, '<>');
          _pos += 2;
        } else if (_pos + 1 < _input.length && _input[_pos + 1] == '&') {
          _add(TokKind.redirectFd, '<&');
          _pos += 2;
        } else {
          _add(TokKind.redirectIn, '<');
          _pos++;
        }
        continue;
      }

      // Double parentheses (( and ))
      if (c == '(' && _pos + 1 < _input.length && _input[_pos + 1] == '(') {
        _add(TokKind.dParen, '((');
        _pos += 2;
        continue;
      }
      if (c == ')' && _pos + 1 < _input.length && _input[_pos + 1] == ')') {
        _add(TokKind.dParenClose, '))');
        _pos += 2;
        continue;
      }

      if (c == '(') { _add(TokKind.leftParen, '('); _pos++; continue; }
      if (c == ')') { _add(TokKind.rightParen, ')'); _pos++; continue; }
      if (c == '{') { _add(TokKind.leftBrace, '{'); _pos++; continue; }
      if (c == '}') { _add(TokKind.rightBrace, '}'); _pos++; continue; }

      final word = _readWord();
      if (word != null) {
        _add(TokKind.word, word);
        continue;
      }

      _pos++;
    }

    _add(TokKind.eof, '');
    return _tokens;
  }

  void _add(TokKind kind, String value) {
    _tokens.add(Token(kind, value, _pos));
  }

  String? _readWord() {
    final buf = StringBuffer();
    var started = false;

    while (_pos < _input.length) {
      final c = _input[_pos];

      if (c == '\'') {
        started = true;
        _pos++;
        while (_pos < _input.length && _input[_pos] != '\'') {
          buf.write(_input[_pos]);
          _pos++;
        }
        if (_pos < _input.length) _pos++;
        continue;
      }

      if (c == '"') {
        started = true;
        _pos++;
        while (_pos < _input.length && _input[_pos] != '"') {
          if (_input[_pos] == '\\' && _pos + 1 < _input.length) {
            _pos++;
            buf.write(_input[_pos]);
          } else {
            buf.write(_input[_pos]);
          }
          _pos++;
        }
        if (_pos < _input.length) _pos++;
        continue;
      }

      if (c == '\\') {
        started = true;
        _pos++;
        if (_pos < _input.length) {
          buf.write(_input[_pos]);
          _pos++;
        }
        continue;
      }

      if (c == ' ' || c == '\t' || c == '\n') break;
      if ('|&;<>(){}' == c) break;

      buf.write(c);
      _pos++;
      started = true;
    }

    if (!started) return null;
    return buf.toString();
  }
}

class ShellParser {
  final List<Token> _tokens;
  int _pos = 0;

  ShellParser._(this._tokens);

  static ShellParser? tryParse(String input) {
    final lexer = _Lexer(input);
    final tokens = lexer.tokenize();
    if (tokens.isEmpty || (tokens.length == 1 && tokens[0].kind == TokKind.eof)) {
      return null;
    }
    return ShellParser._(tokens);
  }

  Token get _current => _pos < _tokens.length ? _tokens[_pos] : _tokens.last;
  Token _advance() => _tokens[_pos++];
  bool get _isEof => _current.kind == TokKind.eof;

  bool _match(TokKind kind) {
    if (_current.kind == kind) {
      _advance();
      return true;
    }
    return false;
  }

  Token _expect(TokKind kind, [String? msg]) {
    if (_current.kind == kind) return _advance();
    throw Exception(msg ?? 'Expected ${kind.name}, got ${_current.value} at pos ${_current.pos}');
  }

  // =========================================================================
  // Main entry point
  // =========================================================================

  AstNode parse() {
    final stmts = <AstNode>[];
    while (!_isEof) {
      final stmt = _parseCompleteCommand();
      if (stmt != null) stmts.add(stmt);
      _match(TokKind.semicolon);
      _match(TokKind.doubleSemicolon);
    }
    if (stmts.isEmpty) throw Exception('empty program');
    if (stmts.length == 1) return stmts.first;
    return SeqNode(stmts);
  }

  // =========================================================================
  // complete_command = list [ separator ]
  // =========================================================================

  AstNode? _parseCompleteCommand() {
    if (_isEof) return null;

    // Detect C-style for ((;;))
    if (_current.kind == TokKind.word && _current.value == 'for' && _pos + 1 < _tokens.length &&
        _tokens[_pos + 1].kind == TokKind.dParen) {
      return _parseCFor();
    }

    // Detect ((…)) arithmetic command
    if (_current.kind == TokKind.dParen) {
      return _parseArithmeticCommand();
    }

    final list = _parseList();
    return list;
  }

  // =========================================================================
  // list = and_or ( separator and_or )*
  // =========================================================================

  AstNode _parseList() {
    var left = _parseAndOr();

    while (_match(TokKind.semicolon) || _match(TokKind.doubleSemicolon) || _match(TokKind.background)) {
      if (_isEof || _current.kind == TokKind.rightParen || _current.kind == TokKind.rightBrace) break;
      if (_current.kind == TokKind.word && (_current.value == 'then' || _current.value == 'else' || _current.value == 'elif' || _current.value == 'fi' || _current.value == 'do' || _current.value == 'done' || _current.value == 'esac')) break;
      final right = _parseAndOr();
      left = SeqNode([left, right]);
    }

    return left;
  }

  // =========================================================================
  // and_or = pipeline ( ( && || ) pipeline )*
  // =========================================================================

  AstNode _parseAndOr() {
    var left = _parsePipeline();

    while (_current.kind == TokKind.and || _current.kind == TokKind.or) {
      final op = _current.kind == TokKind.and ? AndOrOp.and : AndOrOp.or;
      _advance();
      final right = _parsePipeline();
      left = AndOrNode(left, op, right);
    }

    return left;
  }

  // =========================================================================
  // pipeline = [ ! ] command ( | command )*
  // =========================================================================

  AstNode _parsePipeline() {
    if (_isEof) return SeqNode([]);
    if (_current.kind == TokKind.semicolon || _current.kind == TokKind.doubleSemicolon || _current.kind == TokKind.background) return SeqNode([]);
    if (_current.kind == TokKind.rightParen || _current.kind == TokKind.rightBrace) return SeqNode([]);
    if (_current.kind == TokKind.word && (_current.value == 'then' || _current.value == 'else' || _current.value == 'elif' || _current.value == 'fi' || _current.value == 'do' || _current.value == 'done' || _current.value == 'in' || _current.value == 'esac')) return SeqNode([]);

    var invert = false;
    if (_current.kind == TokKind.word && _current.value == '!') {
      invert = true;
      _advance();
    }

    var left = _parseCommand() ?? SeqNode([]);

    if (_current.kind == TokKind.pipe || _current.kind == TokKind.pipeAnd) {
      final cmds = <AstNode>[left];
      while (_current.kind == TokKind.pipe || _current.kind == TokKind.pipeAnd) {
        _advance();
        final cmd = _parseCommand();
        if (cmd == null) break;
        cmds.add(cmd);
      }
      if (cmds.length > 1) {
        left = PipelineNode(cmds);
      }
    }

    if (invert) {
      left = IfNode(left, SeqNode([]), elseBody: SeqNode([]));
    }

    return left;
  }

  // =========================================================================
  // command = simple_command | compound_command | function_definition
  // =========================================================================

  AstNode? _parseCommand() {
    if (_isEof) return null;

    if (_current.kind == TokKind.word && _pos + 2 < _tokens.length &&
        _tokens[_pos + 1].kind == TokKind.leftParen &&
        _tokens[_pos + 2].kind == TokKind.rightParen) {
      return _parseFunctionDef();
    }

    if (_current.kind == TokKind.word && _current.value == 'function') {
      return _parseFunctionDef();
    }

    if (_current.kind == TokKind.leftBrace) return _parseBlock();
    if (_current.kind == TokKind.leftParen) return _parseSubshell();

    if (_current.kind == TokKind.word) {
      final word = _current.value;
      if (word == 'if') return _parseIf();
      if (word == 'while') return _parseWhile();
      if (word == 'until') return _parseUntil();
      if (word == 'for') return _parseFor();
      if (word == 'case') return _parseCase();
      if (word == 'select') return _parseSelect();
      if (word == 'coproc') return _parseCoproc();
      if (word == '{') { _advance(); return _parseBlock(); }
      if (word == 'break') return _parseBreak();
      if (word == 'continue') return _parseContinue();
      if (word == 'return') return _parseReturn();
      if (word == 'exit') return _parseExit();
    }

    return _parseSimpleCommand();
  }

  // =========================================================================
  // Simple Command
  // =========================================================================

  AstNode? _parseSimpleCommand() {
    final words = <String>[];
    final redirects = <RedirectNode>[];
    var background = false;

    while (!_isEof) {
      if (_isRedirect(_current.kind)) {
        final redir = _parseRedirect();
        if (redir != null) redirects.add(redir);
        continue;
      }

      if (_current.kind == TokKind.word &&
          RegExp(r'^\d+$').hasMatch(_current.value) &&
          _pos + 1 < _tokens.length &&
          _isRedirect(_tokens[_pos + 1].kind)) {
        final fd = int.parse(_current.value);
        _advance();
        final redir = _parseRedirectWithFd(fd);
        if (redir != null) redirects.add(redir);
        continue;
      }

      // Process substitution as argument: <(cmd) or >(cmd)
      if (_current.kind == TokKind.procSubstIn || _current.kind == TokKind.procSubstOut) {
        final subst = _parseProcessSubstitution();
        words.add(subst);
        continue;
      }

      if (_current.kind == TokKind.word) {
        words.add(_advance().value);
        continue;
      }

      break;
    }

    if (words.isEmpty && redirects.isEmpty) return null;

    if (words.length == 1 && words[0] == 'break') return BreakNode(1);
    if (words.isNotEmpty && words[0] == 'break') {
      final count = int.tryParse(words[1]) ?? 1;
      return BreakNode(count);
    }
    if (words.length == 1 && words[0] == 'continue') return ContinueNode(1);
    if (words.isNotEmpty && words[0] == 'continue') {
      final count = int.tryParse(words[1]) ?? 1;
      return ContinueNode(count);
    }
    if (words.length == 1 && words[0] == 'return') {
      return ReturnNode(0);
    }
    if (words.isNotEmpty && words[0] == 'return') {
      return ReturnNode(int.tryParse(words[1]) ?? 0);
    }
    if (words.length == 1 && words[0] == 'exit') {
      return ExitNode(0);
    }
    if (words.isNotEmpty && words[0] == 'exit') {
      return ExitNode(int.tryParse(words[1]) ?? 0);
    }

    // Check for variable assignments at the beginning
    if (words.isNotEmpty && _isAssignment(words[0])) {
      final eq = words[0].indexOf('=');
      final name = words[0].substring(0, eq);
      var value = words[0].substring(eq + 1);

      if (value.startsWith('(') && value.endsWith(')')) {
        final inner = value.substring(1, value.length - 1);
        final arrValues = _splitArrayValues(inner);
        if (words.length == 1) {
          return ArrayAssignmentNode(name, arrValues);
        }
        _envPrefixes[name] = value;
        words.removeAt(0);
      } else {
        if (words.length == 1) {
          return AssignmentNode(name, value);
        }
        _envPrefixes[name] = value;
        words.removeAt(0);
      }
      while (words.isNotEmpty && _isAssignment(words[0])) {
        final aEq = words[0].indexOf('=');
        final aName = words[0].substring(0, aEq);
        final aValue = words[0].substring(aEq + 1);
        _envPrefixes[aName] = aValue;
        words.removeAt(0);
      }
    }

    if (words.isEmpty && redirects.isNotEmpty) {
      return SimpleCmdNode(words: [], redirects: redirects);
    }

    return SimpleCmdNode(words: words, redirects: redirects, background: background);
  }

  // =========================================================================
  // Process substitution
  // =========================================================================

  /// Parses <(cmd) or >(cmd), captures the inner command string,
  /// and returns a synthetic word that the executor will recognize.
  String _parseProcessSubstitution() {
    final token = _advance();
    final isInput = token.kind == TokKind.procSubstIn;
    final prefix = isInput ? '<(' : '>(';

    // Collect tokens until matching ) at depth 0
    var depth = 1;
    final innerBuf = StringBuffer();
    while (!_isEof && depth > 0) {
      if (_current.kind == TokKind.leftParen) {
        depth++;
        innerBuf.write(_current.value);
        _advance();
      } else if (_current.kind == TokKind.rightParen) {
        depth--;
        if (depth > 0) {
          innerBuf.write(_current.value);
          _advance();
        }
      } else {
        innerBuf.write(_current.value);
        _advance();
        // Add space between tokens for proper reconstruction
        if (_current.kind != TokKind.rightParen && _current.kind != TokKind.leftParen && _current.kind != TokKind.eof) {
          // emit separator via value
        }
      }
    }

    // Encode as a special marker the executor will handle
    final inner = innerBuf.toString().trim();
    return '$prefix$inner)';
  }

  final Map<String, String> _envPrefixes = {};

  bool _isRedirect(TokKind kind) {
    return kind == TokKind.redirectIn ||
           kind == TokKind.redirectOut ||
           kind == TokKind.redirectAppend ||
           kind == TokKind.redirectHereDoc ||
           kind == TokKind.redirectHereStr ||
           kind == TokKind.redirectBoth ||
           kind == TokKind.redirectFd;
  }

  RedirectNode? _parseRedirect() {
    final kind = _current.kind;
    final op = _advance().value;
    return _parseRedirectTarget(kind, op, 1);
  }

  RedirectNode? _parseRedirectWithFd(int fd) {
    if (_isEof) return null;
    final kind = _current.kind;
    final op = _advance().value;
    return _parseRedirectTarget(kind, op, fd);
  }

  RedirectNode? _parseRedirectTarget(TokKind kind, String op, int defaultFd) {
    int fd;
    switch (kind) {
      case TokKind.redirectIn:
        fd = 0;
      case TokKind.redirectOut:
        fd = 1;
      case TokKind.redirectAppend:
        fd = 1;
      case TokKind.redirectHereDoc:
        fd = 0;
      case TokKind.redirectHereStr:
        fd = 0;
      case TokKind.redirectBoth:
        fd = -1;
      case TokKind.redirectFd:
        fd = -1;
      default:
        return null;
    }

    if (op == '>&' || op == '<&') {
      String target;
      if (_current.kind == TokKind.word) {
        target = _advance().value;
      } else {
        return null;
      }
      return _makeFdRedirect(op, target, defaultFd);
    }

    if (op == '&>') {
      fd = -1;
      final target = _current.kind == TokKind.word ? _advance().value : '';
      if (target.isEmpty) return null;
      return RedirectNode(-1, '&>', target);
    }

    if (op == '>|') {
      final target = _current.kind == TokKind.word ? _advance().value : '';
      if (target.isEmpty) return null;
      return RedirectNode(1, '>|', target);
    }

    if (op == '<>') {
      final target = _current.kind == TokKind.word ? _advance().value : '';
      if (target.isEmpty) return null;
      return RedirectNode(0, '<>', target);
    }

    if (op == '<<') {
      final delimiter = _current.kind == TokKind.word ? _advance().value : '';
      if (delimiter.isEmpty) return null;
      return RedirectNode(0, '<<', delimiter);
    }

    if (op == '<<<') {
      final content = _current.kind == TokKind.word ? _advance().value : '';
      if (content.isEmpty) return null;
      final redir = RedirectNode(0, '<<<', content);
      return redir;
    }

    final target = _current.kind == TokKind.word ? _advance().value : '';
    if (target.isEmpty) return null;

    return RedirectNode(fd, op, target);
  }

  RedirectNode _makeFdRedirect(String op, String target, int defaultFd) {
    if (target.startsWith('&')) {
      final dst = int.tryParse(target.substring(1));
      if (dst != null) {
        return RedirectNode(defaultFd, op, target);
      }
    }
    return RedirectNode(defaultFd, op, target);
  }

  bool _isAssignment(String s) {
    if (s.isEmpty) return false;
    if (!RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*=').hasMatch(s)) return false;
    return true;
  }

  List<String> _splitArrayValues(String s) {
    final parts = <String>[];
    var i = 0;
    while (i < s.length) {
      final c = s[i];
      if (c == ' ' || c == '\t') { i++; continue; }
      if (c == '\'') {
        i++;
        final start = i;
        while (i < s.length && s[i] != '\'') { i++; }
        parts.add(s.substring(start, i));
        if (i < s.length) i++;
      } else if (c == '"') {
        i++;
        final start = i;
        while (i < s.length && s[i] != '"') { i++; }
        parts.add(s.substring(start, i));
        if (i < s.length) i++;
      } else {
        final start = i;
        while (i < s.length && s[i] != ' ' && s[i] != '\t') { i++; }
        parts.add(s.substring(start, i));
      }
    }
    return parts;
  }

  // =========================================================================
  // (( … )) arithmetic command
  // =========================================================================

  AstNode _parseArithmeticCommand() {
    _advance(); // skip ((
    final buf = StringBuffer();
    while (!_isEof && _current.kind != TokKind.dParenClose) {
      buf.write(_current.value);
      _advance();
    }
    _expect(TokKind.dParenClose);
    // Evaluate as a simple command via let-style evaluation
    final expr = buf.toString().trim();
    if (expr.isEmpty) return SimpleCmdNode(words: ['true'], redirects: []);
    return SimpleCmdNode(words: ['let', expr], redirects: []);
  }

  // =========================================================================
  // C-style for (( init ; condition ; increment )) do body done
  // =========================================================================

  AstNode _parseCFor() {
    _advance(); // skip 'for'
    _expect(TokKind.dParen, "expected '((' after for");

    // Read init expression
    final init = _readArithExpr([TokKind.semicolon]);
    _match(TokKind.semicolon);

    // Read condition expression
    final condition = _readArithExpr([TokKind.semicolon]);
    _match(TokKind.semicolon);

    // Read increment expression
    final increment = _readArithExpr([TokKind.dParenClose]);
    _expect(TokKind.dParenClose, "expected '))' in for expression");

    _expectKeyword('do');
    final body = _parseList();
    _expectKeyword('done');

    return CForNode(
      init: init.isNotEmpty ? init : null,
      condition: condition.isNotEmpty ? condition : null,
      increment: increment.isNotEmpty ? increment : null,
      body: body,
    );
  }

  String _readArithExpr(List<TokKind> terminators) {
    final buf = StringBuffer();
    while (!_isEof && !terminators.contains(_current.kind)) {
      if (_current.kind == TokKind.dParenClose) break;
      buf.write(_current.value);
      _advance();
    }
    return buf.toString().trim();
  }

  // =========================================================================
  // select name [in word*] do list done
  // =========================================================================

  AstNode _parseSelect() {
    _advance(); // skip 'select'
    if (_current.kind != TokKind.word) throw Exception('expected variable name after select');
    final varName = _advance().value;

    final words = <String>[];
    if (_current.kind == TokKind.word && _current.value == 'in') {
      _advance();
      while (_current.kind == TokKind.word && _current.value != 'do') {
        words.add(_advance().value);
      }
    }

    _expectKeyword('do');
    final body = _parseList();
    _expectKeyword('done');

    return SelectNode(varName, words, body);
  }

  // =========================================================================
  // coproc [name] compound-command
  // =========================================================================

  AstNode _parseCoproc() {
    _advance(); // skip 'coproc'

    String? name;
    // If next token is a word that's not a compound command keyword, it's the name
    if (_current.kind == TokKind.word &&
        _current.value != '{' &&
        _current.value != '(' &&
        _current.value != 'if' &&
        _current.value != 'while' &&
        _current.value != 'until' &&
        _current.value != 'for' &&
        _current.value != 'select' &&
        _current.value != 'case') {
      name = _advance().value;
    }

    final body = _parseCommand();
    if (body == null) throw Exception('expected command after coproc');
    return CoprocNode(name: name ?? 'COPROC', body: body);
  }

  // =========================================================================
  // if_clause = if list then list [elif list then list]* [else list] fi
  // =========================================================================

  AstNode _parseIf() {
    _advance();
    final cond = _parseList();
    _expectKeyword('then');
    final thenBody = _parseList();

    final elifs = <ElifPair>[];
    while (_current.kind == TokKind.word && _current.value == 'elif') {
      _advance();
      final elifCond = _parseList();
      _expectKeyword('then');
      final elifBody = _parseList();
      elifs.add(ElifPair(elifCond, elifBody));
    }

    AstNode? elseBody;
    if (_current.kind == TokKind.word && _current.value == 'else') {
      _advance();
      elseBody = _parseList();
    }

    _expectKeyword('fi');
    return IfNode(cond, thenBody, elifs: elifs, elseBody: elseBody);
  }

  // =========================================================================
  // while_clause = while list do list done
  // =========================================================================

  AstNode _parseWhile() {
    _advance();
    final cond = _parseList();
    _expectKeyword('do');
    final body = _parseList();
    _expectKeyword('done');
    return WhileNode(cond, body);
  }

  // =========================================================================
  // until_clause = until list do list done
  // =========================================================================

  AstNode _parseUntil() {
    _advance();
    final cond = _parseList();
    _expectKeyword('do');
    final body = _parseList();
    _expectKeyword('done');
    return UntilNode(cond, body);
  }

  // =========================================================================
  // for_clause = for name [in word*] do list done
  // =========================================================================

  AstNode _parseFor() {
    _advance();
    if (_current.kind != TokKind.word) throw Exception('expected variable name after for');
    final varName = _advance().value;

    final words = <String>[];
    if (_current.kind == TokKind.word && _current.value == 'in') {
      _advance();
      while (_current.kind == TokKind.word && _current.value != 'do') {
        words.add(_advance().value);
      }
    }

    _expectKeyword('do');
    final body = _parseList();
    _expectKeyword('done');
    return ForNode(varName, words: words, body: body);
  }

  // =========================================================================
  // case_clause = case word in case_item* esac
  // =========================================================================

  AstNode _parseCase() {
    _advance();
    if (_current.kind != TokKind.word) throw Exception('expected word after case');
    final word = _advance().value;

    _expectKeyword('in');

    final items = <CaseItemNode>[];
    while (!_isEof && !(_current.kind == TokKind.word && _current.value == 'esac')) {
      final patterns = <String>[];
      if (_current.kind == TokKind.word && (_current.value == '(' || _current.value == ')')) break;
      patterns.add(_advance().value);
      while (_current.kind == TokKind.pipe) {
        _advance();
        if (_current.kind == TokKind.word) {
          patterns.add(_advance().value);
        }
      }
      if (_current.kind == TokKind.rightParen || (_current.kind == TokKind.word && _current.value == ')')) {
        _advance();
      }

      final bodyStmts = <AstNode>[];
      while (!_isEof && !(_current.kind == TokKind.doubleSemicolon || (_current.kind == TokKind.word && _current.value == 'esac'))) {
        if (_current.kind == TokKind.semicolon) {
          _advance();
          continue;
        }
        final stmt = _parseCompleteCommand();
        if (stmt != null) bodyStmts.add(stmt);
      }
      if (_current.kind == TokKind.doubleSemicolon) _advance();

      AstNode body = bodyStmts.isEmpty ? SeqNode([]) : bodyStmts.length == 1 ? bodyStmts.first : SeqNode(bodyStmts);
      items.add(CaseItemNode(patterns, body));
    }

    _expectKeyword('esac');
    return CaseNode(word, items);
  }

  // =========================================================================
  // function_definition = name ( ) compound_command
  //                    | function name compound_command
  // =========================================================================

  AstNode _parseFunctionDef() {
    String name;

    if (_current.kind == TokKind.word && _current.value == 'function') {
      _advance();
      if (_current.kind != TokKind.word) throw Exception('expected function name');
      name = _advance().value;
      if (_current.kind == TokKind.leftParen) {
        _advance();
        if (_current.kind == TokKind.rightParen) _advance();
      }
    } else {
      name = _advance().value;
      _advance();
      _advance();
    }

    AstNode body;
    if (_current.kind == TokKind.leftBrace) {
      body = _parseBlock();
    } else if (_current.kind == TokKind.leftParen) {
      body = _parseSubshell();
    } else if (_current.kind == TokKind.word && (_current.value == 'if' || _current.value == 'for' || _current.value == 'while' || _current.value == 'until' || _current.value == 'case')) {
      body = _parseCommand()!;
    } else {
      body = _parseSimpleCommand()!;
    }

    return FunctionDefNode(name, body);
  }

  // =========================================================================
  // block = { list }
  // =========================================================================

  AstNode _parseBlock() {
    _advance();
    final body = _parseList();
    if (_current.kind == TokKind.rightBrace) {
      _advance();
    } else if (_current.kind == TokKind.word && _current.value == '}') {
      _advance();
    }
    return BlockNode(body);
  }

  // =========================================================================
  // subshell = ( list )
  // =========================================================================

  AstNode _parseSubshell() {
    _advance();
    final body = _parseList();
    _expect(TokKind.rightParen);
    return SubshellNode(body);
  }

  // =========================================================================
  // break / continue / return / exit
  // =========================================================================

  AstNode _parseBreak() {
    _advance();
    var count = 1;
    if (_current.kind == TokKind.word && RegExp(r'^\d+$').hasMatch(_current.value)) {
      count = int.parse(_advance().value);
    }
    return BreakNode(count);
  }

  AstNode _parseContinue() {
    _advance();
    var count = 1;
    if (_current.kind == TokKind.word && RegExp(r'^\d+$').hasMatch(_current.value)) {
      count = int.parse(_advance().value);
    }
    return ContinueNode(count);
  }

  AstNode _parseReturn() {
    _advance();
    var code = 0;
    if (_current.kind == TokKind.word && RegExp(r'^\d+$').hasMatch(_current.value)) {
      code = int.parse(_advance().value);
    }
    return ReturnNode(code);
  }

  AstNode _parseExit() {
    _advance();
    var code = 0;
    if (_current.kind == TokKind.word && RegExp(r'^\d+$').hasMatch(_current.value)) {
      code = int.parse(_advance().value);
    }
    return ExitNode(code);
  }

  void _expectKeyword(String kw) {
    if (_current.kind == TokKind.word && _current.value == kw) {
      _advance();
      return;
    }
    throw Exception('expected keyword "$kw" at pos ${_current.pos}, got "${_current.value}"');
  }
}
