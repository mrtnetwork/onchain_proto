enum ProtoTokenType {
  identifier,
  number,
  string,
  symbol,
  lineComment,
  blockComment,
  eof,
}

class ProtoToken {
  final ProtoTokenType type;
  final String text;
  final int line;

  const ProtoToken(this.type, this.text, this.line);

  @override
  String toString() =>
      '${type.name}(${text.length > 30 ? '${text.substring(0, 30)}...' : text}) @line $line';
}

class ProtoTokenizer {
  final String src;
  int _pos = 0;
  int _line = 1;

  ProtoTokenizer(this.src);

  static const _symbols = {
    '{',
    '}',
    '(',
    ')',
    '[',
    ']',
    ';',
    ',',
    '=',
    '<',
    '>',
    '.',
    ':',
  };

  List<ProtoToken> tokenize() {
    final tokens = <ProtoToken>[];
    while (true) {
      final t = _next();
      tokens.add(t);
      if (t.type == ProtoTokenType.eof) break;
    }
    return tokens;
  }

  ProtoToken _next() {
    _skipWhitespace();
    if (_pos >= src.length) {
      return ProtoToken(ProtoTokenType.eof, '', _line);
    }

    final startLine = _line;
    final c = src[_pos];

    // Line comment.
    if (c == '/' && _pos + 1 < src.length && src[_pos + 1] == '/') {
      final start = _pos;
      while (_pos < src.length && src[_pos] != '\n') {
        _pos++;
      }
      return ProtoToken(
        ProtoTokenType.lineComment,
        src.substring(start, _pos),
        startLine,
      );
    }

    // Block comment.
    if (c == '/' && _pos + 1 < src.length && src[_pos + 1] == '*') {
      final start = _pos;
      _pos += 2;
      while (_pos + 1 < src.length &&
          !(src[_pos] == '*' && src[_pos + 1] == '/')) {
        if (src[_pos] == '\n') _line++;
        _pos++;
      }
      _pos = (_pos + 2 <= src.length) ? _pos + 2 : src.length;
      return ProtoToken(
        ProtoTokenType.blockComment,
        src.substring(start, _pos),
        startLine,
      );
    }

    if (c == '"' || c == "'") {
      final quote = c;
      final start = _pos;
      _pos++;
      while (_pos < src.length && src[_pos] != quote) {
        if (src[_pos] == '\\') _pos++;
        _pos++;
      }
      _pos++;
      return ProtoToken(
        ProtoTokenType.string,
        src.substring(start, _pos),
        startLine,
      );
    }

    // Hex integer literal: 0x... / 0X... (e.g. `EDITION_MAX = 0x7FFFFFFF;`
    // in proto2 files). Must be checked BEFORE the general decimal/float
    // number rule below, since a plain "starts with a digit" check would
    // otherwise consume just the leading "0" and then tokenize "x7FFFFFFF"
    // as a separate identifier - which is exactly the bug that produced
    // "expected ';' but found 'x7FFFFFFF'" on a hex enum value.
    if (c == '0' &&
        _pos + 1 < src.length &&
        (src[_pos + 1] == 'x' || src[_pos + 1] == 'X')) {
      final start = _pos;
      _pos += 2; // consume "0x"/"0X"
      while (_pos < src.length && _isHexDigit(src[_pos])) {
        _pos++;
      }
      return ProtoToken(
        ProtoTokenType.number,
        src.substring(start, _pos),
        startLine,
      );
    }

    // Number (handles -, ., digits, and 0x/0X hex literals; good enough for
    // field numbers / enum values / floats / proto2-style hex constants
    // like `EDITION_MAX = 0x7FFFFFFF;`).
    if (_isDigit(c) ||
        (c == '-' && _pos + 1 < src.length && _isDigit(src[_pos + 1]))) {
      final start = _pos;
      if (c == '-') _pos++;

      // Hex literal: 0x... / 0X... - must be checked before the generic
      // decimal/float loop below, since a bare "0" followed by "x" would
      // otherwise be tokenized as the number "0" and leave "x7FFFFFFF" to
      // be misread as a separate identifier token.
      final isHexPrefix =
          _pos + 1 < src.length &&
          src[_pos] == '0' &&
          (src[_pos + 1] == 'x' || src[_pos + 1] == 'X');
      if (isHexPrefix) {
        _pos += 2; // consume "0x"/"0X"
        while (_pos < src.length && _isHexDigit(src[_pos])) {
          _pos++;
        }
        return ProtoToken(
          ProtoTokenType.number,
          src.substring(start, _pos),
          startLine,
        );
      }

      while (_pos < src.length &&
          (_isDigit(src[_pos]) ||
              src[_pos] == '.' ||
              src[_pos] == 'e' ||
              src[_pos] == 'E' ||
              src[_pos] == '+' ||
              src[_pos] == '-')) {
        _pos++;
      }
      return ProtoToken(
        ProtoTokenType.number,
        src.substring(start, _pos),
        startLine,
      );
    }

    // Identifier (letters, digits, underscore). Proto identifiers can't start with a digit
    // (handled above) but can contain dots when read as a whole path - we tokenize dots
    // separately as symbols and let the parser glue them back together, since that's
    // simpler and handles options like (gogoproto.nullable) uniformly.
    if (_isIdentStart(c)) {
      final start = _pos;
      while (_pos < src.length && _isIdentPart(src[_pos])) {
        _pos++;
      }
      return ProtoToken(
        ProtoTokenType.identifier,
        src.substring(start, _pos),
        startLine,
      );
    }

    // Symbols.
    if (_symbols.contains(c)) {
      _pos++;
      return ProtoToken(ProtoTokenType.symbol, c, startLine);
    }

    // Unknown char - skip it defensively rather than throwing, so odd formatting
    // doesn't crash the whole parse.
    _pos++;
    return _next();
  }

  void _skipWhitespace() {
    while (_pos < src.length) {
      final c = src[_pos];
      if (c == '\n') {
        _line++;
        _pos++;
      } else if (c == ' ' || c == '\t' || c == '\r') {
        _pos++;
      } else {
        break;
      }
    }
  }

  bool _isDigit(String c) => c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;

  bool _isHexDigit(String c) {
    final u = c.codeUnitAt(0);
    return (u >= 48 && u <= 57) || // 0-9
        (u >= 65 && u <= 70) || // A-F
        (u >= 97 && u <= 102); // a-f
  }

  bool _isIdentStart(String c) {
    final u = c.codeUnitAt(0);
    return (u >= 65 && u <= 90) || (u >= 97 && u <= 122) || c == '_';
  }

  bool _isIdentPart(String c) {
    final u = c.codeUnitAt(0);
    return _isIdentStart(c) || (u >= 48 && u <= 57);
  }
}
