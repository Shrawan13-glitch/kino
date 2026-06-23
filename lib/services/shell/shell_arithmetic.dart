import 'shell_state.dart';

enum _ArithTokType { num, var_, op, assign, eof }

class _ArithToken {
  final String value;
  final _ArithTokType type;
  final int radix;
  _ArithToken(this.value, this.type, {this.radix = 10});
}

class ShellArithmetic {
  final ShellState state;

  ShellArithmetic(this.state);

  int _pos = 0;
  List<_ArithToken> _tokens = [];

  int eval(String expr) {
    try {
      final trimmed = expr.trim();
      if (trimmed.isEmpty) return 0;
      return _parse(trimmed);
    } catch (_) {
      return 0;
    }
  }

  int _parse(String s) {
    _tokens = _tokenize(s);
    _pos = 0;
    return _parseComma();
  }

  List<_ArithToken> _tokenize(String s) {
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
        if (i + 2 < s.length) {
          final three = s.substring(i, i + 3);
          if (multiOps.contains(three)) {
            tokens.add(_ArithToken(three,
                assignOps.contains(three) ? _ArithTokType.assign : _ArithTokType.op));
            i += 3;
            continue;
          }
        }
        if (multiOps.contains(two)) {
          tokens.add(_ArithToken(two,
              assignOps.contains(two) ? _ArithTokType.assign : _ArithTokType.op));
          i += 2;
          continue;
        }
      }

      if ('+-*/%&|^~!<>=()?,:'.contains(s[i])) {
        final ch = s[i];
        tokens.add(_ArithToken(ch,
            ch == '=' ? _ArithTokType.assign : _ArithTokType.op));
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

      if (s[i] == '_' || (s[i].codeUnitAt(0) >= 65 && s[i].codeUnitAt(0) <= 90) ||
          (s[i].codeUnitAt(0) >= 97 && s[i].codeUnitAt(0) <= 122)) {
        final start = i;
        while (i < s.length && (s[i] == '_' ||
            (s[i].codeUnitAt(0) >= 48 && s[i].codeUnitAt(0) <= 57) ||
            (s[i].codeUnitAt(0) >= 65 && s[i].codeUnitAt(0) <= 90) ||
            (s[i].codeUnitAt(0) >= 97 && s[i].codeUnitAt(0) <= 122))) { i++; }
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

  _ArithToken _peek() =>
      _pos < _tokens.length ? _tokens[_pos] : _ArithToken('', _ArithTokType.eof);

  _ArithToken _advance() => _tokens[_pos++];

  bool _match(String v) {
    if (_peek().value == v) {
      _advance();
      return true;
    }
    return false;
  }

  void _expect(String v) {
    if (_peek().value != v) throw Exception('Expected $v in arithmetic');
    _advance();
  }

  int _parseComma() {
    var left = _parseAssign();
    while (_match(',')) {
      left = _parseAssign();
    }
    return left;
  }

  int _parseAssign() {
    if (_peek().type == _ArithTokType.var_) {
      final savedPos = _pos;
      final varToken = _advance();
      if (_peek().type == _ArithTokType.assign) {
        final op = _advance().value;
        final right = _parseAssign();
        final name = varToken.value;
        final val = right;
        switch (op) {
          case '=':
            state.env[name] = val.toString();
          case '+=':
            state.env[name] = (state.getArithVar(name) + val).toString();
          case '-=':
            state.env[name] = (state.getArithVar(name) - val).toString();
          case '*=':
            state.env[name] = (state.getArithVar(name) * val).toString();
          case '/=':
            state.env[name] = (val == 0 ? 0 : state.getArithVar(name) ~/ val).toString();
          case '%=':
            state.env[name] = (val == 0 ? 0 : state.getArithVar(name) % val).toString();
          case '<<=':
            state.env[name] = (state.getArithVar(name) << val).toString();
          case '>>=':
            state.env[name] = (state.getArithVar(name) >> val).toString();
          case '&=':
            state.env[name] = (state.getArithVar(name) & val).toString();
          case '^=':
            state.env[name] = (state.getArithVar(name) ^ val).toString();
          case '|=':
            state.env[name] = (state.getArithVar(name) | val).toString();
        }
        return val;
      }
      _pos = savedPos;
    }
    return _parseTernary();
  }

  int _parseTernary() {
    var left = _parseLor();
    if (_match('?')) {
      final trueVal = _parseTernary();
      _expect(':');
      final falseVal = _parseTernary();
      return left != 0 ? trueVal : falseVal;
    }
    return left;
  }

  int _parseLor() {
    var left = _parseLand();
    while (_match('||')) {
      final right = _parseLand();
      left = (left != 0 || right != 0) ? 1 : 0;
    }
    return left;
  }

  int _parseLand() {
    var left = _parseBor();
    while (_match('&&')) {
      final right = _parseBor();
      left = (left != 0 && right != 0) ? 1 : 0;
    }
    return left;
  }

  int _parseBor() {
    var left = _parseXor();
    while (_match('|')) {
      final right = _parseXor();
      left = left | right;
    }
    return left;
  }

  int _parseXor() {
    var left = _parseBand();
    while (_match('^')) {
      final right = _parseBand();
      left = left ^ right;
    }
    return left;
  }

  int _parseBand() {
    var left = _parseEq();
    while (_match('&')) {
      final right = _parseEq();
      left = left & right;
    }
    return left;
  }

  int _parseEq() {
    var left = _parseRel();
    while (true) {
      if (_match('==')) {
        final r = _parseRel();
        left = left == r ? 1 : 0;
      } else if (_match('!=')) {
        final r = _parseRel();
        left = left != r ? 1 : 0;
      } else {
        break;
      }
    }
    return left;
  }

  int _parseRel() {
    var left = _parseShift();
    while (true) {
      if (_match('<=')) {
        final r = _parseShift();
        left = left <= r ? 1 : 0;
      } else if (_match('>=')) {
        final r = _parseShift();
        left = left >= r ? 1 : 0;
      } else if (_match('<')) {
        final r = _parseShift();
        left = left < r ? 1 : 0;
      } else if (_match('>')) {
        final r = _parseShift();
        left = left > r ? 1 : 0;
      } else {
        break;
      }
    }
    return left;
  }

  int _parseShift() {
    var left = _parseAdd();
    while (true) {
      if (_match('<<')) {
        final r = _parseAdd();
        left = left << r;
      } else if (_match('>>')) {
        final r = _parseAdd();
        left = left >> r;
      } else {
        break;
      }
    }
    return left;
  }

  int _parseAdd() {
    var left = _parseMul();
    while (true) {
      if (_match('+')) {
        final r = _parseMul();
        left = left + r;
      } else if (_match('-')) {
        final r = _parseMul();
        left = left - r;
      } else {
        break;
      }
    }
    return left;
  }

  int _parseMul() {
    var left = _parsePower();
    while (true) {
      if (_match('*')) {
        final r = _parsePower();
        left = left * r;
      } else if (_match('/')) {
        final r = _parsePower();
        if (r == 0) throw Exception('division by zero');
        left = left ~/ r;
      } else if (_match('%')) {
        final r = _parsePower();
        if (r == 0) throw Exception('division by zero');
        left = left % r;
      } else {
        break;
      }
    }
    return left;
  }

  int _parsePower() {
    var left = _parseUnary();
    if (_match('**')) {
      final right = _parsePower();
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

  int _parseUnary() {
    if (_match('+')) return _parsePostfix();
    if (_match('-')) return -_parsePostfix();
    if (_match('!')) return _parsePostfix() == 0 ? 1 : 0;
    if (_match('~')) return ~_parsePostfix();
    if (_match('++')) {
      final token = _advance();
      if (token.type == _ArithTokType.var_) {
        final val = state.getArithVar(token.value) + 1;
        state.setArithVar(token.value, val);
        return val;
      }
      return _parsePostfix();
    }
    if (_match('--')) {
      final token = _advance();
      if (token.type == _ArithTokType.var_) {
        final val = state.getArithVar(token.value) - 1;
        state.setArithVar(token.value, val);
        return val;
      }
      return _parsePostfix();
    }
    return _parsePostfix();
  }

  int _parsePostfix() {
    if (_peek().type == _ArithTokType.num) {
      final token = _advance();
      return int.parse(token.value, radix: token.radix);
    }
    if (_peek().type == _ArithTokType.var_) {
      final token = _advance();
      if (_peek().value == '++') {
        _advance();
        final val = state.getArithVar(token.value);
        state.setArithVar(token.value, val + 1);
        return val;
      }
      if (_peek().value == '--') {
        _advance();
        final val = state.getArithVar(token.value);
        state.setArithVar(token.value, val - 1);
        return val;
      }
      return state.getArithVar(token.value);
    }
    if (_peek().value == '(') {
      _advance();
      final val = _parseComma();
      _expect(')');
      return val;
    }
    return 0;
  }
}
