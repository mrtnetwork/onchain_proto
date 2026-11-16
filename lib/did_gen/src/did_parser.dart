import 'did_ast.dart';

/// Parses Candid `.did` type definitions and service method signatures.
class DidParser {
  final String _src;
  int _i = 0;

  DidParser(this._src);

  static DidFile parse(String source) => DidParser(source)._parseFile();

  DidFile _parseFile() {
    final types = <DidTypeDef>[];
    final services = <DidService>[];
    _skip();
    while (!_eof) {
      if (_peekKeyword('type')) {
        types.add(_parseTypeDef());
      } else if (_peekKeyword('service')) {
        services.add(_parseService());
      } else if (_peekKeyword('import')) {
        _skipImport();
      } else {
        if (!_eof) _advance();
        _skip();
      }
    }
    return DidFile(types, services: services);
  }

  DidTypeDef _parseTypeDef() {
    _expectKeyword('type');
    final name = _parseIdent();
    _expect('=');
    final ty = _parseType();
    _optional(';');
    return DidTypeDef(name, ty);
  }

  DidType _parseType() {
    _skip();
    if (_peekKeyword('opt')) {
      _expectKeyword('opt');
      return DidOpt(_parseType());
    }
    if (_peekKeyword('vec')) {
      _expectKeyword('vec');
      return DidVec(_parseType());
    }
    if (_peekKeyword('record')) {
      return _parseRecord();
    }
    if (_peekKeyword('variant')) {
      return _parseVariant();
    }
    if (_peekKeyword('func')) {
      _expectKeyword('func');
      _skipFuncSig();
      return const DidFunc();
    }
    if (_peekKeyword('service')) {
      _expectKeyword('service');
      _skipServiceBodyOrRef();
      return const DidServiceType();
    }
    // blob is sugar for vec nat8 but keep as primitive name
    final prim = _tryPrimitive();
    if (prim != null) return DidPrimitive(prim);

    // named type reference
    final name = _parseIdent();
    return DidNamed(name);
  }

  DidType _parseRecord() {
    _expectKeyword('record');
    _expect('{');
    final fields = <DidField>[];
    var tupleIndex = 0;
    while (!_eof && !_peek('}')) {
      _skip();
      if (_peek('}')) break; // trailing comma/semicolon
      // Tuple-style field: just a type, e.g. record { text; nat }
      // Labeled field: name : type
      if (_isLabeledFieldStart()) {
        final fname = _parseFieldName();
        _expect(':');
        final fty = _parseType();
        fields.add(DidField(fname, fty));
      } else {
        final fty = _parseType();
        fields.add(DidField('$tupleIndex', fty));
        tupleIndex++;
      }
      _optional(';');
      _optional(',');
      _skip();
    }
    _expect('}');
    return DidRecord(fields);
  }

  /// True when the next field is `label : type` (not a bare type).
  bool _isLabeledFieldStart() {
    _skip();
    final save = _i;
    try {
      if (_peek('"')) {
        _parseString();
        _skip();
        return _peek(':');
      }
      if (_digit(_cur)) {
        while (!_eof && _digit(_cur)) {
          _i++;
        }
        _skip();
        return _peek(':');
      }
      // identifier or type keyword — only labeled if followed by ':'
      if (_isIdentStart(_cur)) {
        _parseIdent();
        _skip();
        return _peek(':');
      }
      return false;
    } finally {
      _i = save;
    }
  }

  DidType _parseVariant() {
    _expectKeyword('variant');
    _expect('{');
    final fields = <DidField>[];
    while (!_eof && !_peek('}')) {
      _skip();
      if (_peek('}')) break;
      final fname = _parseFieldName();
      DidType? fty;
      _skip();
      if (_peek(':')) {
        _expect(':');
        fty = _parseType();
      }
      fields.add(DidField(fname, fty));
      _optional(';');
      _optional(',');
      _skip();
    }
    _expect('}');
    return DidVariant(fields);
  }

  String _parseFieldName() {
    _skip();
    if (_peek('"')) {
      return _parseString();
    }
    // numeric label or ident
    if (_digit(_cur)) {
      final start = _i;
      while (!_eof && _digit(_cur)) {
        _i++;
      }
      return _src.substring(start, _i);
    }
    return _parseIdent();
  }

  String? _tryPrimitive() {
    const prims = {
      'nat',
      'int',
      'nat8',
      'nat16',
      'nat32',
      'nat64',
      'int8',
      'int16',
      'int32',
      'int64',
      'float32',
      'float64',
      'bool',
      'text',
      'null',
      'reserved',
      'empty',
      'principal',
      'blob',
    };
    for (final p in prims) {
      if (_peekKeyword(p)) {
        _expectKeyword(p);
        return p;
      }
    }
    return null;
  }

  DidService _parseService() {
    _expectKeyword('service');
    _skip();
    String? name;
    if (!_peek(':') && _isIdentStart(_cur)) {
      name = _parseIdent();
      _skip();
    }
    if (_peek(':')) {
      _i++;
      _skip();
    }
    // optional actor class args ( ... ) -> ServiceType
    if (_peek('(')) {
      _skipBalanced('(', ')');
      _skip();
      if (_peek('-') && _i + 1 < _src.length && _src[_i + 1] == '>') {
        _i += 2;
        _skip();
      }
    }
    final methods = <DidMethod>[];
    if (_peek('{')) {
      _expect('{');
      while (!_eof && !_peek('}')) {
        methods.add(_parseMethod());
        _optional(';');
        _skip();
      }
      _expect('}');
    } else if (_isIdentStart(_cur)) {
      // service ref to another name — no methods here
      _parseIdent();
    }
    _optional(';');
    return DidService(name: name, methods: methods);
  }

  DidMethod _parseMethod() {
    final name = _parseIdent();
    _skip();
    _expect(':');
    _skip();

    // Two forms:
    //   name : (args) -> (rets) query?
    //   name : FuncTypeAlias;     (named func type reference)
    List<DidType> args;
    List<DidType> rets;
    var isQuery = false;
    var isOneway = false;
    var isComposite = false;

    if (_peek('(')) {
      args = _parseTypeList();
      _skip();
      if (_peek('-') && _i + 1 < _src.length && _src[_i + 1] == '>') {
        _i += 2;
        _skip();
        rets = _parseTypeList();
        _skip();
        while (true) {
          if (_peekKeyword('query')) {
            _expectKeyword('query');
            isQuery = true;
          } else if (_peekKeyword('oneway')) {
            _expectKeyword('oneway');
            isOneway = true;
          } else if (_peekKeyword('composite_query')) {
            _expectKeyword('composite_query');
            isComposite = true;
          } else {
            break;
          }
          _skip();
        }
      } else {
        // Unusual: bare (types) without -> — treat as args, empty rets
        rets = const [];
      }
    } else {
      // name : SomeType  where SomeType is often a func type alias
      final ref = _parseType();
      args = [ref];
      rets = const [];
      // Modes may still appear after a func type alias expansion — rare
      _skip();
      while (true) {
        if (_peekKeyword('query')) {
          _expectKeyword('query');
          isQuery = true;
        } else if (_peekKeyword('oneway')) {
          _expectKeyword('oneway');
          isOneway = true;
        } else if (_peekKeyword('composite_query')) {
          _expectKeyword('composite_query');
          isComposite = true;
        } else {
          break;
        }
        _skip();
      }
    }

    return DidMethod(
      name: name,
      args: args,
      rets: rets,
      isQuery: isQuery,
      isOneway: isOneway,
      isCompositeQuery: isComposite,
    );
  }

  /// Parse `(t1, t2, ...)` / `(name : t1, name2 : t2)` / `()` / bare type.
  ///
  /// Candid allows optional argument and result names before each type:
  ///   (name : text, age : nat8) -> (id : nat64)
  List<DidType> _parseTypeList() {
    _skip();
    if (_peek('(')) {
      _expect('(');
      final list = <DidType>[];
      _skip();
      if (!_peek(')')) {
        while (!_eof) {
          _skip();
          // trailing comma: (Type,) or (Type, )
          if (_peek(')')) break;
          // optional `name :` label (ignored for encoding, but must be consumed)
          if (_isLabeledFieldStart()) {
            _parseFieldName();
            _expect(':');
            _skip();
          }
          list.add(_parseType());
          _skip();
          if (_peek(',')) {
            _i++;
            _skip();
            continue;
          }
          break;
        }
      }
      _expect(')');
      return list;
    }
    // bare single type
    return [_parseType()];
  }

  void _skipServiceBodyOrRef() {
    _skip();
    if (_peek('{')) {
      _skipBalanced('{', '}');
    } else if (_isIdentStart(_cur)) {
      _parseIdent();
    }
  }

  void _skipFuncSig() {
    _skip();
    if (_peek('(')) {
      _skipBalanced('(', ')');
      _skip();
      if (_peek('-') && _i + 1 < _src.length && _src[_i + 1] == '>') {
        _i += 2;
        _skip();
        if (_peek('(')) {
          _skipBalanced('(', ')');
        } else {
          _parseType();
        }
      }
      // modes: query, oneway, ...
      while (_peekKeyword('query') ||
          _peekKeyword('oneway') ||
          _peekKeyword('composite_query')) {
        _parseIdent();
        _skip();
      }
    }
  }

  void _skipImport() {
    _expectKeyword('import');
    _skip();
    if (_peek('"')) {
      _parseString();
    }
    _optional(';');
  }

  // ----- lexer helpers -----

  bool get _eof => _i >= _src.length;
  String get _cur => _eof ? '\u0000' : _src[_i];

  void _skip() {
    while (!_eof) {
      final c = _cur;
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
        _i++;
        continue;
      }
      if (c == '/' && _i + 1 < _src.length && _src[_i + 1] == '/') {
        _i += 2;
        while (!_eof && _cur != '\n') {
          _i++;
        }
        continue;
      }
      if (c == '/' && _i + 1 < _src.length && _src[_i + 1] == '*') {
        _i += 2;
        while (!_eof &&
            !(_cur == '*' && _i + 1 < _src.length && _src[_i + 1] == '/')) {
          _i++;
        }
        if (!_eof) {
          _i += 2;
        }
        continue;
      }
      break;
    }
  }

  void _advance() {
    if (!_eof) _i++;
  }

  bool _peek(String s) {
    _skip();
    return _src.startsWith(s, _i);
  }

  bool _peekKeyword(String kw) {
    _skip();
    if (!_src.startsWith(kw, _i)) return false;
    final end = _i + kw.length;
    if (end < _src.length && _isIdentPart(_src[end])) return false;
    return true;
  }

  void _expect(String s) {
    _skip();
    if (!_src.startsWith(s, _i)) {
      throw FormatException('Expected "$s" at $_i, found "${_preview()}"');
    }
    _i += s.length;
  }

  void _expectKeyword(String kw) {
    if (!_peekKeyword(kw)) {
      throw FormatException(
        'Expected keyword $kw at $_i, found "${_preview()}"',
      );
    }
    _i += kw.length;
  }

  void _optional(String s) {
    _skip();
    if (_src.startsWith(s, _i)) _i += s.length;
  }

  String _parseIdent() {
    _skip();
    if (!_isIdentStart(_cur)) {
      throw FormatException(
        'Expected identifier at $_i, found "${_preview()}"',
      );
    }
    final start = _i;
    _i++;
    while (!_eof && _isIdentPart(_cur)) {
      _i++;
    }
    return _src.substring(start, _i);
  }

  String _parseString() {
    _expect('"');
    final buf = StringBuffer();
    while (!_eof && _cur != '"') {
      if (_cur == '\\') {
        _i++;
        if (!_eof) {
          buf.write(_cur);
          _i++;
        }
      } else {
        buf.write(_cur);
        _i++;
      }
    }
    _expect('"');
    return buf.toString();
  }

  void _skipBalanced(String open, String close) {
    _expect(open);
    var depth = 1;
    while (!_eof && depth > 0) {
      if (_cur == open) {
        depth++;
        _i++;
      } else if (_cur == close) {
        depth--;
        _i++;
      } else if (_cur == '"') {
        _parseString();
      } else if (_cur == '/' && _i + 1 < _src.length && _src[_i + 1] == '/') {
        while (!_eof && _cur != '\n') {
          _i++;
        }
      } else {
        _i++;
      }
    }
  }

  String _preview() {
    final end = (_i + 20).clamp(0, _src.length);
    return _src.substring(_i, end).replaceAll('\n', '\\n');
  }

  static bool _digit(String c) =>
      c.compareTo('0') >= 0 && c.compareTo('9') <= 0;
  static bool _isIdentStart(String c) =>
      (c.compareTo('a') >= 0 && c.compareTo('z') <= 0) ||
      (c.compareTo('A') >= 0 && c.compareTo('Z') <= 0) ||
      c == '_';
  static bool _isIdentPart(String c) => _isIdentStart(c) || _digit(c);
}
