import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:onchain_proto/proto/compiler/compiler.dart';
import 'package:onchain_proto/proto/exception/exception.dart';
import 'package:onchain_proto/proto/types/types.dart';
import 'tokenize.dart';

class ProtoParseException extends OnChainProtoException {
  final int line;
  final Map<String, dynamic>? details;

  const ProtoParseException(super.message, this.line, {this.details});

  @override
  String toString() =>
      'ProtoParseException at line $line: $message, details: $details';
}

class ProtoFileParser {
  final ProtoCompiler resolver;
  final String packageName;
  final ProtoFile file;
  final List<String> types;
  final List<ProtoDeclaration> declarations;

  ProtoFileParser._({
    required this.resolver,
    required this.packageName,
    required this.file,
    required List<String> types,
    required List<ProtoDeclaration> declarations,
  }) : types = types.immutable,
       declarations = declarations.immutable;
  factory ProtoFileParser({
    required String source,
    required ProtoCompiler resolver,
    required String path,
    required String name,
  }) {
    _ProtoFileParser instance = _ProtoFileParser(
      resolver: resolver,
      source: source,
    );
    final file = instance.parseFile(path: path, name: name);

    List<ProtoDeclaration> allDeclarations = [];
    void collectDeclarations(
      List<ProtoMessage> messages,
      List<ProtoEnum> enums,
    ) {
      allDeclarations.addAll(messages);
      allDeclarations.addAll(enums);
    }

    collectDeclarations(file.messages, file.enums);

    return ProtoFileParser._(
      resolver: resolver,
      packageName: instance.packageName,
      file: file,
      types: [
        ...file.messages.map((e) => e.fullName()), // use fullName not just name
        ...file.enums.map((e) => e.fullName()),
      ],
      declarations: allDeclarations,
    );
  }
  ProtoFile finalize() {
    return file.resolveRefrences((e, parent) {
      final result = resolver.resolveTypeRefrence(
        origin: packageName,
        typeName: e.typeName,
        enclosingMessage: parent,
      );
      return result;
    });
  }
}

class _ProtoFileParser {
  // final ProtoCompiler resolver;
  final String packageName;
  final List<ProtoToken> _tokens;
  int _i = 0;

  final List<String> _pendingComments = [];

  final List<ProtoEnum> _nestedEnums = [];

  final List<ProtoExtend> _extends = [];
  _ProtoFileParser._({
    required this.packageName,
    required List<ProtoToken> tokens,
  }) : _tokens = tokens.immutable;

  factory _ProtoFileParser({
    required String source,
    required ProtoCompiler resolver,
  }) {
    final tokens = ProtoTokenizer(source).tokenize();
    _ProtoFileParser instance = _ProtoFileParser._(
      packageName: "",
      tokens: tokens,
    );
    return _ProtoFileParser._(
      packageName: instance._getPackageName(),
      tokens: tokens,
    );
  }

  ProtoToken get _cur {
    return _tokens[_i];
  }

  bool get _atEnd => _cur.type == ProtoTokenType.eof;

  /// Advances past comment tokens, stashing their text into
  /// [_pendingComments], until a "real" token is reached.
  void _skipCommentsCollecting() {
    while (!_atEnd &&
        (_cur.type == ProtoTokenType.lineComment ||
            _cur.type == ProtoTokenType.blockComment)) {
      _pendingComments.add(_cleanComment(_cur.text));
      _i++;
    }
  }

  String _cleanComment(String raw) {
    if (raw.startsWith('//')) {
      return raw.substring(2).trim();
    }
    if (raw.startsWith('/*')) {
      var s = raw;
      s = s.substring(2);
      if (s.endsWith('*/')) s = s.substring(0, s.length - 2);
      return s.trim();
    }
    return raw.trim();
  }

  /// Pulls and clears the pending comments, joined by newlines.
  String _takeComments() {
    final text = _pendingComments.join('\n');
    _pendingComments.clear();
    return text;
  }

  ProtoToken _advance() {
    final t = _cur;
    _i++;
    _skipCommentsCollecting();
    return t;
  }

  ProtoToken _expect(String text) {
    _skipCommentsCollecting();
    if (_cur.text != text) {
      throw ProtoParseException(
        'expected "$text" but found "${_cur.text}"',
        _cur.line,
      );
    }
    return _advance();
  }

  ProtoToken _expectType(ProtoTokenType type) {
    _skipCommentsCollecting();
    if (_cur.type != type) {
      throw ProtoParseException(
        'expected token type $type but found ${_cur.type} ("${_cur.text}")',
        _cur.line,
      );
    }
    return _advance();
  }

  bool _check(String text) {
    _skipCommentsCollecting();
    return _cur.text == text;
  }

  bool _matchConsume(String text) {
    if (_check(text)) {
      _advance();
      return true;
    }
    return false;
  }

  /// Reads a dotted identifier path like `google.protobuf.Any` or
  /// `gogoproto.nullable` as a single string, consuming identifier/'.'
  /// tokens. Leading '.' (fully-qualified type names) is preserved.
  String _readDottedPath() {
    final sb = StringBuffer();
    if (_check('.')) {
      sb.write('.');
      _advance();
    }
    sb.write(_expectType(ProtoTokenType.identifier).text);
    while (_check('.')) {
      _advance();
      sb.write('.');
      sb.write(_expectType(ProtoTokenType.identifier).text);
    }
    return sb.toString();
  }

  ProtoFile parseFile({required String path, required String name}) {
    _skipCommentsCollecting();

    ProtoSyntax? syntax = ProtoSyntax.v3;
    String? package;
    final imports = <String>[];
    final options = <ProtoOption>[];
    final enums = <ProtoEnum>[];
    List<ProtoMessage> messages = [];
    final services = <ProtoService>[];

    while (!_atEnd) {
      _skipCommentsCollecting();
      if (_atEnd) break;

      final keyword = _cur.text;
      switch (keyword) {
        case 'syntax':
          syntax = ProtoSyntax.fromSyntax(_parseSyntax());
          break;
        case 'package':
          package = _parsePackage();
          break;
        case 'extend':
          // Nested message: parse and stash for the caller to hoist.
          _extends.add(_parseExtend());
          break;
        case 'import':
          imports.add(_parseImport());
          break;
        case 'option':
          options.add(_parseFileOption());
          break;
        case 'enum':
          enums.add(_parseEnum());
          break;
        case 'message':
          final parse = _parseMessage();
          messages.addAll(parse.getMessages());
          enums.addAll(parse.getEums());
          break;
        case 'service':
          services.add(_parseService());
          break;
        case ';':
          _advance(); // stray semicolon
          break;
        default:
          throw ProtoParseException(
            'unexpected top-level token "$keyword"',
            _cur.line,
          );
      }
    }
    if (package == null) {
      throw ProtoParseException("Missing package name.", _cur.line);
    }
    if (syntax == null) {
      throw ProtoParseException("Unknown file syntax..", _cur.line);
    }

    // print("enims ${messages.map((e) => e.fullTypeName()).toList()}");

    return ProtoFile(
      syntax: syntax,
      package: package,
      imports: imports,
      options: options,
      enums: enums,
      messages: messages,
      services: services,
      extends_: _extends,
      name: name,
      protoPath: path,
    );
  }

  String _getPackageName() {
    _skipCommentsCollecting();
    while (!_atEnd) {
      _skipCommentsCollecting();
      if (_atEnd) break;

      final keyword = _cur.text;
      switch (keyword) {
        case 'package':
          return _parsePackage();
        default:
          break;
      }
      _advance();
    }
    throw ProtoParseException("Missing package name.", _cur.line);
  }

  String _parseSyntax() {
    _expect('syntax');
    _expect('=');
    final s = _expectType(ProtoTokenType.string).text;
    _expect(';');
    return _unquote(s);
  }

  String _parsePackage() {
    _expect('package');
    final path = _readDottedPath();
    _expect(';');
    return path;
  }

  String _parseImport() {
    _expect('import');
    // optional 'public' or 'weak' modifier
    if (_check('public') || _check('weak')) _advance();
    final s = _expectType(ProtoTokenType.string).text;
    _expect(';');
    return _unquote(s);
  }

  /// Top-level `option name = value;`
  ProtoOption _parseFileOption() {
    _expect('option');
    final name = _readOptionName();
    _expect('=');
    final value = _readFileOptionValue();
    _expect(';');
    return ProtoOption.parse(name: name, value: value);
  }

  String _readOptionName() {
    if (_matchConsume('(')) {
      final name = _readDottedPath();
      _expect(')');
      // Handle trailing path after a parenthesized extension, e.g.
      // (foo.bar).baz - rare in these files, but safe to support.
      final sb = StringBuffer(name);
      while (_check('.')) {
        _advance();
        sb.write('.');
        sb.write(_expectType(ProtoTokenType.identifier).text);
      }
      return sb.toString();
    }
    return _readDottedPath();
  }

  /// Reads a scalar option value: string, number, bool identifier, plain
  /// identifier (e.g. enum-like option values), or a `{ ... }` aggregate
  /// (returned as a raw string of its contents since ProtoOption.value is
  /// `Object?` and we don't have a dedicated map type for it).
  Object? _readOptionValue() {
    _skipCommentsCollecting();
    if (_cur.type == ProtoTokenType.string) {
      String result = "";
      while (_cur.type == ProtoTokenType.string) {
        result += _unquote(_advance().text);
      }
      return result;
    }
    if (_cur.type == ProtoTokenType.number) {
      return _parseNumberToken(_advance().text);
    }
    if (_check('true')) {
      _advance();
      return true;
    }
    if (_check('false')) {
      _advance();
      return false;
    }
    if (_check('{')) {
      return _readAggregateOptionValue();
    }
    // Plain identifier value (e.g. an enum constant used as an option value).
    return _readDottedPath();
  }

  /// Converts a NUMBER token's raw text into an [int] or [double]. Handles
  /// hex literals (`0x7FFFFFFF`, as seen in proto2 files like
  /// descriptor.proto's `EDITION_MAX = 0x7FFFFFFF;`) as a special case
  /// BEFORE the float-vs-int heuristic below: a hex literal can legally
  /// contain the letter `e` as one of its digits (e.g. `0xeF12`), which
  /// would otherwise be misdetected as a float exponent and crash on
  /// `double.parse` (hex syntax isn't valid float syntax).
  Object _parseNumberToken(String text) {
    if (text.startsWith('0x') || text.startsWith('0X')) {
      return int.parse(text);
    }
    if (text.contains('.') || text.contains('e') || text.contains('E')) {
      return double.parse(text);
    }
    return int.parse(text);
  }

  /// Reads a scalar FILE/message-level option value: same shapes as
  /// [_readOptionValue], but a string value may be split across several
  /// ADJACENT string literals (proto's implicit string concatenation,
  /// commonly used to wrap long values like URL templates onto multiple
  /// lines), e.g.:
  ///   option (google.api.http).get = "/cosmos/.../interfaces/"
  ///                                  "{interface_name}/implementations";
  /// which must be read as a single concatenated string, not just the
  /// first literal followed by a parse error on the second.
  Object? _readFileOptionValue() {
    _skipCommentsCollecting();
    if (_cur.type == ProtoTokenType.string) {
      String result = "";
      while (_cur.type == ProtoTokenType.string) {
        result += _unquote(_advance().text);
      }
      return result;
    }
    if (_cur.type == ProtoTokenType.number) {
      return _parseNumberToken(_advance().text);
    }
    if (_check('true')) {
      _advance();
      return true;
    }
    if (_check('false')) {
      _advance();
      return false;
    }
    if (_check('{')) {
      return _readAggregateOptionValue();
    }
    // Plain identifier value (e.g. an enum constant used as an option value).
    return _readDottedPath();
  }

  Map<String, Object?> _readAggregateOptionValue() {
    _expect('{');

    final result = <String, Object?>{};

    while (!_check('}')) {
      _skipCommentsCollecting();

      final key = _readOptionName();
      _expect(':');

      Object? value;

      if (_check('{')) {
        value = _readAggregateOptionValue();
      } else {
        value = _readOptionValue();
      }

      result[key] = value;

      // optional separators
      _matchConsume(',');
      _matchConsume(';');
    }

    _expect('}');

    return result;
  }

  String _unquote(String raw) {
    if (raw.length >= 2) {
      return raw.substring(1, raw.length - 1);
    }
    return raw;
  }

  /// Parses the `[ (a) = 1, (b) = "x" ]` field-option suffix, if present.
  /// Also accepts a bare `[declaration = {...}]`-style proto2 `extensions`
  /// option block (same bracket syntax, just with aggregate values), so
  /// this is reused for both regular field options and `extensions N [..]`.
  List<ProtoOption> _parseFieldOptionsOpt() {
    final opts = <ProtoOption>[];
    if (!_check('[')) return opts;
    _advance(); // [
    while (!_check(']')) {
      final name = _readOptionName();
      _expect('=');
      final value = _readOptionValue();
      opts.add(ProtoOption.parse(name: name, value: value));
      if (!_matchConsume(',')) break;
    }
    _expect(']');
    return opts;
  }

  ProtoEnum _parseEnum() {
    final comments = _takeComments();
    _expect('enum');
    final name = _expectType(ProtoTokenType.identifier).text;
    _expect('{');

    final options = <ProtoOption>[];
    final values = <ProtoEnumValue>[];

    while (!_check('}')) {
      _skipCommentsCollecting();
      if (_check('}')) break;

      if (_check('option')) {
        options.add(_parseFileOption());
        continue;
      }
      if (_check('reserved')) {
        _skipReserved();
        continue;
      }
      if (_matchConsume(';')) continue;

      values.add(_parseEnumValue());
    }
    _expect('}');

    return ProtoEnum(
      name: name,
      comments: comments,
      options: options,
      values: values,
      package: packageName,
    );
  }

  ProtoEnumValue _parseEnumValue() {
    final comments = _takeComments();
    final name = _expectType(ProtoTokenType.identifier).text;
    _expect('=');
    final numText = _expectType(ProtoTokenType.number).text;
    final value = int.parse(numText);
    final options = _parseFieldOptionsOpt();
    _expect(';');
    return ProtoEnumValue(
      name: name,
      value: value,
      comments: comments,
      options: options,
    );
  }

  void _skipReserved() {
    _expect('reserved');
    while (!_check(';')) {
      _advance();
    }
    _expect(';');
  }

  /// Skips a proto2-style `extensions 100 to 200 [declaration = {...}];` or
  /// `extensions 536000000 [declaration = {...}];` declaration. This
  /// generator has no model slot for extension RANGES (as opposed to
  /// `extend` blocks, which ARE modeled via [ProtoExtend]) - they don't
  /// describe a field on the message itself, just a number range reserved
  /// for others to extend into, so there is nothing useful to carry into
  /// [ProtoMessage]. Parsed and discarded so it doesn't trip up the
  /// message-body loop or get misread as a field declaration.
  void _skipExtensions() {
    _expect('extensions');
    while (!_check(';')) {
      if (_check('[')) {
        // reuse the field-options bracket reader for `[declaration = {...}]`
        _parseFieldOptionsOpt();
        continue;
      }
      _advance();
    }
    _expect(';');
  }

  ParsedProtobufMessage _withParent(
    ParsedProtobufMessage parsed,
    ProtoMessage parent,
  ) {
    final message = parsed.message.copyWith(parent: parent);
    final enums = parsed.enums.map((e) => e.copyWith(parent: message)).toList();
    return ParsedProtobufMessage(
      message: message,
      enums: enums,
      nestedMessages: parsed.nestedMessages
          .map((e) => _withParent(e, message))
          .toList(),
    );
  }

  // ProtoEnum _enumWithParent(ProtoEnum parsed, ProtoMessage parent) {
  //   final message = parsed.copyWith(parent: parent);

  //   return ParsedProtobufMessage(
  //     message: message,
  //     enums: parsed.enums.map((e) => e.copyWith(parent: message)).toList(),
  //     nestedMessages: parsed.nestedMessages
  //         .map((e) => _withParent(e, message))
  //         .toList(),
  //   );
  // }

  ParsedProtobufMessage _parseMessage() {
    final comments = _takeComments();
    _expect('message');
    final name = _expectType(ProtoTokenType.identifier).text;
    _expect('{');

    final options = <ProtoOption>[];
    final fields = <ProtoField>[];
    List<ParsedProtobufMessage> messages = [];
    List<ProtoEnum> enums = [];
    // Nested messages/enums aren't represented separately in your model
    // (ProtoMessage has no `nested` list), so per proto convention we lift
    // them to top-level-style declarations the caller can flatten in; see
    // note below `parseFile` usage. Here we just parse and discard the
    // structural placement but still return them via a side list the
    // caller can merge - see `parseWithNested` if you need that.
    while (!_check('}')) {
      _skipCommentsCollecting();
      if (_check('}')) break;

      switch (_cur.text) {
        case 'option':
          options.add(_parseFileOption());
          break;
        case 'reserved':
          _skipReserved();
          break;
        case 'extensions':
          _skipExtensions();
          break;
        case 'extend':
          _extends.add(_parseExtend());
          break;
        case ';':
          _advance();
          break;
        case 'message':
          final parse = _parseMessage();
          messages.add(parse);
          break;
        case 'enum':
          final nested = _parseEnum();
          enums.add(nested);
          break;
        case 'oneof':
          fields.addAll(_parseOneof());
          break;
        case 'map':
          fields.add(_parseField());
          break;
        default:
          fields.add(_parseField());
      }
    }
    _expect('}');
    final msg = ProtoMessage(
      name: name,
      comments: comments,
      options: options,
      fields: fields,
      package: packageName,

      services: [],
    );
    return ParsedProtobufMessage(
      message: msg,
      enums: enums.map((e) => e.copyWith(parent: msg)).toList(),
      nestedMessages: messages.map((e) => _withParent(e, msg)).toList(),
    );
  }

  ProtoExtend _parseExtend() {
    final comments = _takeComments();
    _expect('extend');
    final type = _parseFieldType();
    _expect('{');

    final options = <ProtoOption>[];
    final fields = <ProtoField>[];
    while (!_check('}')) {
      _skipCommentsCollecting();
      if (_check('}')) break;

      switch (_cur.text) {
        case 'option':
          options.add(_parseFileOption());
          break;
        case 'reserved':
          _skipReserved();
          break;
        case 'extensions':
          _skipExtensions();
          break;
        case ';':
          _advance();
          break;
        case 'message':
          // _nestedMessages.add(_parseMessage());
          break;
        case 'enum':
          _nestedEnums.add(_parseEnum());
          break;
        case 'oneof':
          fields.addAll(_parseOneof());
          break;
        case 'map':
          fields.add(_parseField());
          break;
        default:
          fields.add(_parseField());
      }
    }
    _expect('}');

    return ProtoExtend(
      type: type,
      comments: comments,
      options: options,
      fields: fields,
    );
  }

  List<ProtoField> _parseOneof() {
    _expect('oneof');
    _expectType(
      ProtoTokenType.identifier,
    ); // oneof group name (not modeled - flattened)
    _expect('{');
    final fields = <ProtoField>[];
    while (!_check('}')) {
      _skipCommentsCollecting();
      if (_check('}')) break;
      if (_matchConsume(';')) continue;
      fields.add(_parseField());
    }
    _expect('}');
    return fields;
  }

  ProtoField _parseField() {
    final comments = _takeComments();

    bool repeated = false;
    bool optional = false;
    bool required = false;

    if (_matchConsume('repeated')) {
      repeated = true;
    } else if (_matchConsume('optional')) {
      optional = true;
    } else if (_matchConsume('required')) {
      // proto2-only modifier (e.g. descriptor.proto's
      // UninterpretedOption.NamePart). Must be consumed here the same way
      // `optional` is, or it gets misread as the field's TYPE name, which
      // shifts every following token left by one and produces a
      // confusing "expected '=' but found <field name>" error further on.
      required = true;
    }

    ProtoType type;
    if (_check('map')) {
      type = _parseMapType();
    } else {
      type = _parseFieldType();
    }
    if (repeated) {
      type = ProtoRepeated(type);
    }

    final name = _expectType(ProtoTokenType.identifier).text;
    _expect('=');
    final tag = int.parse(_expectType(ProtoTokenType.number).text);
    final options = _parseFieldOptionsOpt();
    _expect(';');

    return ProtoField(
      name: name,
      tag: tag,
      type: type,
      options: options,
      comments: comments,
      optional: optional,
      required: required,
    );
  }

  ProtoMap _parseMapType() {
    _expect('map');
    _expect('<');
    final key = _parseFieldType();
    _expect(',');
    final value = _parseFieldType();
    _expect('>');
    return ProtoMap(key: key, value: value);
  }

  static const _scalarNames = {
    'double': ProtoScalarType.double_,
    'float': ProtoScalarType.float_,
    'int32': ProtoScalarType.int32,
    'int64': ProtoScalarType.int64,
    'uint32': ProtoScalarType.uint32,
    'uint64': ProtoScalarType.uint64,
    'sint32': ProtoScalarType.sint32,
    'sint64': ProtoScalarType.sint64,
    'fixed32': ProtoScalarType.fixed32,
    'fixed64': ProtoScalarType.fixed64,
    'sfixed32': ProtoScalarType.sfixed32,
    'sfixed64': ProtoScalarType.sfixed64,
    'bool': ProtoScalarType.bool_,
    'string': ProtoScalarType.string_,
    'bytes': ProtoScalarType.bytes,
  };

  ProtoType _parseFieldType() {
    final path = _readDottedPath();
    final scalar = _scalarNames[path];
    if (scalar != null) {
      return ProtoScalar(scalar);
    }
    return ProtoMessageRefrence.unresolved(path);
  }

  // ---- service -----------------------------------------------------------

  ProtoService _parseService() {
    final comments = _takeComments();
    _expect('service');
    final name = _expectType(ProtoTokenType.identifier).text;
    _expect('{');

    final options = <ProtoOption>[];
    final rpcs = <ProtoRpc>[];

    while (!_check('}')) {
      _skipCommentsCollecting();
      if (_check('}')) break;
      if (_check('option')) {
        options.add(_parseFileOption());
        continue;
      }
      if (_matchConsume(';')) continue;
      rpcs.add(_parseRpc());
    }
    _expect('}');

    return ProtoService(
      name: name,
      comments: comments,
      options: options,
      rpcs: rpcs,
    );
  }

  ProtoRpc _parseRpc() {
    final comments = _takeComments();
    _expect('rpc');
    final name = _expectType(ProtoTokenType.identifier).text;
    _expect('(');
    final clientStreaming = _matchConsume('stream');
    final requestName = _readDottedPath();
    _expect(')');
    _expect('returns');
    _expect('(');
    final serverStreaming = _matchConsume('stream');
    final responseName = _readDottedPath();
    _expect(')');

    final options = <ProtoOption>[];
    if (_matchConsume('{')) {
      while (!_check('}')) {
        _skipCommentsCollecting();
        if (_check('}')) break;
        if (_check('option')) {
          options.add(_parseFileOption());
          continue;
        }
        if (_matchConsume(';')) continue;
        // Unknown rpc-body construct; skip the token defensively.
        _advance();
      }
      _expect('}');
      _matchConsume(';');
    } else {
      _expect(';');
    }

    return ProtoRpc(
      name: name,
      request: ProtoMessageRefrence.unresolved(requestName),
      response: ProtoMessageRefrence.unresolved(responseName),
      clientStreaming: clientStreaming,
      serverStreaming: serverStreaming,
      comments: comments,
      options: options,
    );
  }
}
