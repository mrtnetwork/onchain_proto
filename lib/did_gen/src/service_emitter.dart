import 'did_ast.dart';

/// Emits query/update message classes from [DidService]s.
///
/// Naming: every class is prefixed with [namePrefix] (from .did file name / --did-name),
/// e.g. ICRC7Transfer, ICRC7QueryMessage, ICRC7UpdateMessage.
class ServiceEmitter {
  final DidFile file;

  /// Prefix for all generated type + message class names (from file name / --did-name).
  final String namePrefix;
  final String queryBaseClass;
  final String updateBaseClass;
  final List<String> servicesImports;

  /// From [DidEmitter.syntheticUsages]: `"GetKnownUtxos.arg"` → `"GetBtcAddressArg"`.
  final Map<String, String> syntheticUsages;
  final String utilsImport;

  ServiceEmitter(
    this.file, {
    required this.namePrefix,
    this.queryBaseClass = 'IQueryService',
    this.updateBaseClass = 'IUpdateService',
    this.servicesImports = const [],
    this.syntheticUsages = const {},
    this.utilsImport = '../../utils/utils.dart',
  });

  String _cn(String name) {
    final base = _pascal(name);
    return '$namePrefix$base';
  }

  String get _queryMessageClass => '${namePrefix}QueryMessage';
  String get _updateMessageClass => '${namePrefix}UpdateMessage';

  String _headerImports() {
    final buf = StringBuffer();
    buf.writeln("import 'package:blockchain_utils/blockchain_utils.dart';");
    for (final imp in servicesImports) {
      final p = imp.trim();
      if (p.isEmpty) continue;
      buf.writeln("import '$p';");
    }
    buf.writeln("import 'types.dart';");
    buf.writeln("import '$utilsImport';");
    return buf.toString();
  }

  String emitServiceBases(String serviceName, {required bool forQuery}) {
    final buf = StringBuffer();
    if (forQuery) {
      final qName = _queryMessageClass;
      buf.writeln('/// Query messages for service `$serviceName`.');
      buf.writeln(
        'abstract class $qName<RESULT> extends $queryBaseClass<RESULT> {',
      );
      buf.writeln('  const $qName();');
      buf.writeln('}');
      buf.writeln();
    } else {
      final uName = _updateMessageClass;
      buf.writeln('/// Update messages for service `$serviceName`.');
      buf.writeln(
        'abstract class $uName<RESULT> extends $updateBaseClass<RESULT> {',
      );
      buf.writeln('  const $uName();');
      buf.writeln('}');
      buf.writeln();
    }
    return buf.toString();
  }

  String emitQueries() {
    final methods = file.services
        .expand((s) => s.methods)
        .where((m) => m.isQuery || m.isCompositeQuery)
        .toList();
    if (methods.isEmpty) return '';

    final buf = StringBuffer();
    buf.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
    buf.writeln('// ignore_for_file: prefer_const_constructors');
    buf.writeln();
    buf.write(_headerImports());
    buf.writeln();
    buf.write(emitServiceBases(_serviceLabel(), forQuery: true));
    for (final m in methods) {
      buf.writeln(_emitMethod(m, isQuery: true));
      buf.writeln();
    }
    buf.writeln(_bytesHelper);
    return buf.toString();
  }

  String emitUpdates() {
    final methods = file.services
        .expand((s) => s.methods)
        .where((m) => m.isUpdate || m.isOneway)
        .toList();
    if (methods.isEmpty) return '';

    final buf = StringBuffer();
    buf.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
    buf.writeln('// ignore_for_file: prefer_const_constructors');
    buf.writeln();
    buf.write(_headerImports());
    buf.writeln();
    buf.write(emitServiceBases(_serviceLabel(), forQuery: false));
    for (final m in methods) {
      buf.writeln(_emitMethod(m, isQuery: false));
      buf.writeln();
    }
    buf.writeln(_bytesHelper);
    return buf.toString();
  }

  String _serviceLabel() {
    if (file.services.isNotEmpty &&
        file.services.first.name != null &&
        file.services.first.name!.isNotEmpty) {
      return file.services.first.name!;
    }
    return namePrefix;
  }

  static const String _bytesHelper = '';

  String _emitMethod(DidMethod m, {required bool isQuery}) {
    final base = isQuery ? _queryMessageClass : _updateMessageClass;
    final className = _methodClassName(m.name, isQuery: isQuery);
    final resultType = _resultDartType(m.rets, methodName: m.name);

    final buf = StringBuffer();
    buf.writeln('class $className extends $base<$resultType> {');

    if (m.args.isEmpty) {
      buf.writeln('  const $className();');
    } else if (m.args.length == 1) {
      final argT = _typeToDart(m.args.first, methodName: m.name, role: 'arg');
      buf.writeln('  final $argT args;');
      buf.writeln('  const $className(this.args);');
    } else {
      for (var i = 0; i < m.args.length; i++) {
        final argT = _typeToDart(m.args[i], methodName: m.name, role: 'arg$i');
        buf.writeln('  final $argT arg$i;');
      }
      buf.writeln('  const $className({');
      for (var i = 0; i < m.args.length; i++) {
        buf.writeln('    required this.arg$i,');
      }
      buf.writeln('  });');
    }
    buf.writeln();

    buf.writeln('  @override');
    buf.writeln("  String get methodName => '${m.name}';");
    buf.writeln();

    buf.writeln('  @override');
    buf.writeln('  List<int> toCandidBytes() {');
    if (m.args.isEmpty) {
      buf.writeln(
        '    return CandidUtils.encode(const <CType>[], const <dynamic>[]);',
      );
    } else if (m.args.length == 1) {
      buf.writeln(
        '    return ${_encodeArg('args', m.args.first, methodName: m.name)};',
      );
    } else {
      final types = [
        for (var i = 0; i < m.args.length; i++)
          _ctypeRef(m.args[i], methodName: m.name, role: 'arg$i'),
      ].join(', ');
      final vals = [
        for (var i = 0; i < m.args.length; i++) _valueRef('arg$i', m.args[i]),
      ].join(', ');
      buf.writeln('    return CandidUtils.encode([$types], [$vals]);');
    }
    buf.writeln('  }');
    buf.writeln();

    buf.writeln('  @override');
    buf.writeln('  $resultType onResponse(List<int> bytes) {');
    if (m.rets.isEmpty) {
      buf.writeln('    // unit ()');
      buf.writeln('    return null;');
    } else if (m.rets.length == 1) {
      buf.write(_decodeRetBody(m.rets.first, methodName: m.name));
    } else {
      final ctypes = [
        for (var i = 0; i < m.rets.length; i++)
          _ctypeRef(m.rets[i], methodName: m.name, role: 'response$i'),
      ].join(', ');
      buf.writeln('    return CandidUtils.decode(bytes, [$ctypes]);');
    }
    buf.writeln('  }');
    buf.writeln('}');

    return buf.toString();
  }

  /// Query: `{prefix}Query{Method}` — Update: `{prefix}Update{Method}`
  /// so message classes never collide with type names of the same method result.
  String _methodClassName(String methodName, {required bool isQuery}) {
    final kind = isQuery ? 'Query' : 'Update';
    return '$namePrefix$kind${_pascal(methodName)}';
  }

  /// Preferred synthetic name for anonymous method return/arg types.
  String _preferredAnon(String methodName, {required String role}) {
    final base = '$namePrefix${_pascal(methodName)}';
    if (role == 'response') return '${base}Response';
    if (role.startsWith('response')) {
      return '$base${_pascal(role)}';
    }
    if (role == 'arg') return '${base}Arg';
    return '$base${_pascal(role)}';
  }

  /// Resolve anonymous method type to the class actually emitted (shape-deduped).
  String _anonCn(String methodName, {required String role}) {
    final key = '$namePrefix${_pascal(methodName)}.$role';
    final hit = syntheticUsages[key];
    if (hit != null) return hit;
    return _preferredAnon(methodName, role: role);
  }

  String _resultDartType(List<DidType> rets, {required String methodName}) {
    if (rets.isEmpty) return 'Null';
    if (rets.length == 1) {
      return _typeToDart(rets.first, methodName: methodName, role: 'response');
    }
    return 'List<dynamic>';
  }

  bool _isNamedRecordOrVariant(DidNamed t) {
    final matches = file.types.where((d) => d.name == t.name);
    if (matches.isEmpty) return true;
    final def = matches.first;
    return def.type is DidRecord || def.type is DidVariant;
  }

  DidType? _aliasBody(String name) {
    final matches = file.types.where((d) => d.name == name);
    if (matches.isEmpty) return null;
    final def = matches.first;
    if (def.type is DidRecord || def.type is DidVariant) return null;
    return def.type;
  }

  bool _isPurePrimitiveAlias(DidType t) {
    var cur = t;
    final seen = <String>{};
    while (true) {
      if (cur is DidNamed) {
        if (seen.contains(cur.name)) return false;
        seen.add(cur.name);
        final body = _aliasBody(cur.name);
        if (body == null) return false;
        cur = body;
        continue;
      }
      if (cur is DidPrimitive) return true;
      return false;
    }
  }

  /// Follow typedef aliases to the underlying type (stops at record/variant class).
  DidType _resolve(DidType t) {
    final seen = <String>{};
    var cur = t;
    while (cur is DidNamed) {
      final name = cur.name;
      if (seen.contains(name)) break;
      seen.add(name);
      final body = _aliasBody(name);
      if (body == null) break; // record/variant class or unknown
      cur = body;
    }
    return cur;
  }

  DidType _unwrapContainers(DidType t) {
    var cur = t;
    while (true) {
      if (cur is DidOpt) {
        cur = cur.inner;
      } else if (cur is DidVec) {
        cur = cur.inner;
      } else {
        return cur;
      }
    }
  }

  /// Element class for `type Alias = vec …` matching DidEmitter naming.
  String? _vecElementClass(String aliasName, DidType inner) {
    final core = _resolve(_unwrapContainers(inner));
    if (core is DidNamed && _isNamedClass(core)) {
      return _cn(core.name);
    }
    if (core is DidNamed) {
      // typedef-to-typedef element; still a named dart type
      return _cn(core.name);
    }
    if (core is DidRecord || core is DidVariant) {
      final aliasCn = _cn(aliasName);
      final key = '$aliasCn.item';
      final hit = syntheticUsages[key];
      if (hit != null) return hit;
      // DidEmitter default: parentCn + Item
      return '${aliasCn}Item';
    }
    return null;
  }

  String _typeToDart(
    DidType t, {
    required String methodName,
    required String role,
  }) {
    // Keep DID type names (classes and typedef aliases).
    if (t is DidNamed) {
      return _cn(t.name);
    }
    return switch (t) {
      DidPrimitive(:final name) => _primDart(name),
      DidOpt(:final inner) =>
        '${_typeToDart(inner, methodName: methodName, role: role)}?',
      DidVec(:final inner) =>
        (inner is DidPrimitive &&
                (inner.name == 'nat8' || inner.name == 'blob'))
            ? 'List<int>'
            : 'List<${_typeToDart(inner, methodName: methodName, role: role)}>',
      DidRecord() || DidVariant() => _anonCn(methodName, role: role),
      DidFunc() => 'FuncRef',
      DidServiceType() => 'ServiceRef',
      _ => 'dynamic',
    };
  }

  String _primDart(String name) => switch (name) {
    'nat' || 'int' || 'nat64' || 'int64' => 'BigInt',
    'nat8' || 'nat16' || 'nat32' || 'int8' || 'int16' || 'int32' => 'int',
    'float32' || 'float64' => 'double',
    'bool' => 'bool',
    'text' => 'String',
    'null' => 'Null',
    'principal' => 'IcpPrincipalAddress',
    'blob' => 'List<int>',
    'reserved' || 'empty' => 'Null',
    _ => 'dynamic',
  };

  bool _isNamedClass(DidType t) {
    if (t is! DidNamed) return false;
    return _isNamedRecordOrVariant(t);
  }

  String _encodeArg(String expr, DidType t, {required String methodName}) {
    // Named record/variant class
    if (t is DidNamed && _isNamedClass(t)) {
      return '$expr.toCandidBytes()';
    }
    // Anonymous record/variant (or synthetic MethodArg)
    final r = _resolve(t);
    if (r is DidRecord || r is DidVariant) {
      return '$expr.toCandidBytes()';
    }
    return 'CandidUtils.encodeOneTyped(${_ctypeRef(t, methodName: methodName, role: 'arg')}, ${_valueRef(expr, t)})';
  }

  String _valueRef(String expr, DidType t) {
    if (t is DidNamed && _isNamedClass(t)) return '$expr.candidValue';
    final r = _resolve(t);
    if (r is DidRecord || r is DidVariant) {
      if (t is DidNamed && _isNamedClass(t)) return '$expr.candidValue';
      if (t is! DidNamed) return '$expr.candidValue';
    }
    // vec containing class/record values: encode their candid maps, not
    // the objects themselves (encoding class instances directly fails).
    if (r is DidVec && _vecElementNeedsCandidValue(r.inner)) {
      return '$expr.map((e) => ${_encodeElementValue('e', r.inner)}).toList()';
    }
    return expr;
  }

  bool _vecElementNeedsCandidValue(DidType t) {
    final r = _resolve(t);
    if (r is DidNamed && _isNamedClass(r)) return true;
    if (r is DidRecord || r is DidVariant) return true;
    if (r is DidOpt) return _vecElementNeedsCandidValue(r.inner);
    if (r is DidVec) return _vecElementNeedsCandidValue(r.inner);
    return false;
  }

  String _encodeElementValue(String e, DidType t) {
    final r = _resolve(t);
    if (r is DidOpt) {
      return '$e == null ? null : ${_encodeElementValue(e, r.inner)}';
    }
    if (r is DidVec) {
      return '($e as List).map((x) => ${_encodeElementValue('x', r.inner)}).toList()';
    }
    if (r is DidNamed && _isNamedClass(r)) return '$e.candidValue';
    if (r is DidRecord || r is DidVariant) return '$e.candidValue';
    return e;
  }

  String _ctypeRef(
    DidType t, {
    required String methodName,
    required String role,
  }) {
    if (t is DidNamed) {
      if (_isNamedClass(t)) return '${_cn(t.name)}.ctype';
      final body = _aliasBody(t.name);
      if (body != null) {
        if (_isPurePrimitiveAlias(body)) {
          return _ctypeExprSimple(body);
        }
        // Compound typedef → companion class
        return '${_cn(t.name)}Candid.ctype';
      }
      return '${_cn(t.name)}.ctype';
    }
    final r = _resolve(t);
    if (r is DidRecord || r is DidVariant) {
      return '${_anonCn(methodName, role: role)}.ctype';
    }
    return _ctypeExprSimple(t);
  }

  /// Expression decoding one already-candid-decoded element [e] of did
  /// type [t] into its Dart form.
  ///
  /// `decodeOneTyped` returns dynamic values (`List<dynamic>` for vec) —
  /// a direct `as List<T>` cast throws, so lists are normalized with
  /// `valueAsList` by the caller and converted element-wise here.
  /// [depth] namespaces nested map variables (`e`, `e1`, `e2`, …).
  /// [parentAlias] is the unprefixed typedef name used to resolve
  /// anonymous nested record synthetics (`<Alias>Item`).
  String _decodeElementExpr(
    DidType t,
    String e, {
    required String methodName,
    required int depth,
    String? parentAlias,
  }) {
    final r = _resolve(t);
    if (r is DidOpt) {
      final inner = _decodeElementExpr(
        r.inner,
        e,
        methodName: methodName,
        depth: depth,
        parentAlias: parentAlias,
      );
      return '$e == null ? null : $inner';
    }
    if (r is DidVec) {
      final core = _resolve(r.inner);
      if (core is DidPrimitive &&
          (core.name == 'nat8' || core.name == 'blob')) {
        return 'List<int>.from($e as List)';
      }
      final x = 'e${depth + 1}';
      final inner = _decodeElementExpr(
        r.inner,
        x,
        methodName: methodName,
        depth: depth + 1,
        parentAlias: parentAlias,
      );
      return '($e as List).map(($x) => $inner).toList()';
    }
    if (r is DidNamed && _isNamedClass(r)) {
      return '${_cn(r.name)}.fromCandid($e)';
    }
    if (r is DidRecord || r is DidVariant) {
      final cn = parentAlias != null
          ? (_vecElementClass(parentAlias, t) ?? '${_cn(parentAlias)}Item')
          : _anonCn(methodName, role: 'response');
      return '$cn.fromCandid($e)';
    }
    if (r is DidPrimitive) {
      return switch (r.name) {
        'nat' ||
        'int' ||
        'nat64' ||
        'int64' => 'JsonParser.valueAsBigInt<BigInt>($e)',
        'nat8' ||
        'nat16' ||
        'nat32' ||
        'int8' ||
        'int16' ||
        'int32' => 'JsonParser.valueAsInt<int>($e)',
        'bool' => 'JsonParser.valueAsBool<bool>($e)',
        'text' => 'JsonParser.valueAsString<String>($e)',
        'principal' => 'GeneratorParserUtils.principalFromCandid($e)',
        'blob' => 'List<int>.from($e as List)',
        'float32' || 'float64' => 'JsonParser.valueAsDouble<double>($e)',
        _ => e,
      };
    }
    return e;
  }

  /// Ctype expression for a decode call, mirroring [_decodeElementExpr]:
  /// anonymous records/variants resolve to their lifted synthetic class
  /// (instead of the `CType.null_` placeholder [_ctypeExprSimple] emits),
  /// so the ctype matches the classes the decoded values are converted
  /// into. [parentAlias] is the unprefixed typedef name for typedef bodies.
  String _ctypeForDecode(
    DidType t, {
    required String methodName,
    String role = 'response',
    String? parentAlias,
  }) {
    final r = _resolve(t);
    if (r is DidOpt) {
      return 'CType.opt(${_ctypeForDecode(r.inner, methodName: methodName, role: role, parentAlias: parentAlias)})';
    }
    if (r is DidVec) {
      return 'CType.vec(${_ctypeForDecode(r.inner, methodName: methodName, role: role, parentAlias: parentAlias)})';
    }
    if (r is DidNamed && _isNamedClass(r)) {
      return '${_cn(r.name)}.ctype';
    }
    if (r is DidRecord || r is DidVariant) {
      final cn = parentAlias != null
          ? (_vecElementClass(parentAlias, t) ?? '${_cn(parentAlias)}Item')
          : _anonCn(methodName, role: role);
      return '$cn.ctype';
    }
    return _ctypeExprSimple(r);
  }

  /// Body of onResponse (indented with 4 spaces).
  String _decodeRetBody(DidType t, {required String methodName}) {
    final buf = StringBuffer();

    // Named DID type (class or typedef) — never invent MethodResponse.
    if (t is DidNamed) {
      if (_isNamedClass(t)) {
        buf.writeln('    return ${_cn(t.name)}.fromBytes(bytes);');
        return buf.toString();
      }
      final body = _aliasBody(t.name);
      if (body != null) {
        return _decodeTypedef(t.name, body, methodName: methodName);
      }
      // Unknown named — try fromBytes
      buf.writeln('    return ${_cn(t.name)}.fromBytes(bytes);');
      return buf.toString();
    }

    final r = _resolve(t);

    // Anonymous record/variant → synthetic MethodResponse
    if (r is DidRecord || r is DidVariant) {
      final cn = _anonCn(methodName, role: 'response');
      buf.writeln('    return $cn.fromBytes(bytes);');
      return buf.toString();
    }

    // vec of named class / anonymous
    if (r is DidVec) {
      final inner = _resolve(r.inner);
      if (inner is DidNamed && _isNamedClass(inner)) {
        final cn = _cn(inner.name);
        buf.writeln(
          '    final decode = CandidUtils.decodeOneTyped(bytes, CType.vec($cn.ctype));',
        );
        buf.writeln(
          '    return JsonParser.valueEnsureAsList<Map<String, dynamic>>(decode)',
        );
        buf.writeln('        .map((e) => $cn.fromCandid(e))');
        buf.writeln('        .toList();');
        return buf.toString();
      }
      if (inner is DidRecord || inner is DidVariant) {
        final cn = _anonCn(methodName, role: 'response');
        buf.writeln(
          '    final decode = CandidUtils.decodeOneTyped(bytes, CType.vec($cn.ctype));',
        );
        buf.writeln(
          '    return JsonParser.valueEnsureAsList<Map<String, dynamic>>(decode)',
        );
        buf.writeln('        .map((e) => $cn.fromCandid(e))');
        buf.writeln('        .toList();');
        return buf.toString();
      }
      // vec of primitives / typedef scalars / nested containers:
      // decodeOneTyped returns List<dynamic> — a direct `as List<T>` cast
      // throws, so normalize with valueAsList and convert each element.
      buf.writeln('    final result = JsonParser.valueAsList<List>(');
      buf.writeln(
        '      CandidUtils.decodeOneTyped(bytes, ${_ctypeForDecode(r, methodName: methodName)}),',
      );
      buf.writeln('    );');
      buf.writeln(
        '    return result.map((e) => ${_decodeElementExpr(r.inner, 'e', methodName: methodName, depth: 0)}).toList();',
      );
      return buf.toString();
    }

    // opt of named class
    if (r is DidOpt) {
      final inner = _resolve(r.inner);
      if (inner is DidNamed && _isNamedClass(inner)) {
        final cn = _cn(inner.name);
        buf.writeln(
          '    final decode = CandidUtils.decodeOneTyped(bytes, CType.opt($cn.ctype));',
        );
        buf.writeln('    if (decode == null) return null;');
        buf.writeln(
          '    return $cn.fromCandid(JsonParser.valueEnsureAsMap<String, dynamic>(decode));',
        );
        return buf.toString();
      }
      if (inner is DidRecord || inner is DidVariant) {
        final cn = _anonCn(methodName, role: 'response');
        buf.writeln(
          '    final decode = CandidUtils.decodeOneTyped(bytes, CType.opt($cn.ctype));',
        );
        buf.writeln('    if (decode == null) return null;');
        buf.writeln(
          '    return $cn.fromCandid(JsonParser.valueEnsureAsMap<String, dynamic>(decode));',
        );
        return buf.toString();
      }
      // opt of scalars: decode returns the scalar or null — `as` is fine.
      // opt of records/containers: null-check, then convert element-wise.
      final optInner = _resolve(r.inner);
      if (optInner is DidPrimitive) {
        buf.writeln(
          '    return CandidUtils.decodeOneTyped(bytes, ${_ctypeExprSimple(r)}) as ${_typeToDart(r, methodName: methodName, role: 'response')};',
        );
        return buf.toString();
      }
      buf.writeln(
        '    final decode = CandidUtils.decodeOneTyped(bytes, ${_ctypeForDecode(r, methodName: methodName)});',
      );
      buf.writeln('    if (decode == null) return null;');
      buf.writeln(
        '    return ${_decodeElementExpr(r.inner, 'decode', methodName: methodName, depth: 0)};',
      );
      return buf.toString();
    }

    // principal
    if (r is DidPrimitive && r.name == 'principal') {
      buf.writeln(
        '    final raw = CandidUtils.decodeOneTyped(bytes, CType.principal);',
      );
      buf.writeln('    return GeneratorParserUtils.principalFromCandid(raw);');
      return buf.toString();
    }

    // primitives / remaining
    buf.writeln(
      '    return CandidUtils.decodeOneTyped(bytes, ${_ctypeExprSimple(r)}) as ${_typeToDart(r, methodName: methodName, role: 'response')};',
    );
    return buf.toString();
  }

  /// Decode a named typedef (`type Allowances = vec record {…}`).
  String _decodeTypedef(
    String aliasName,
    DidType body, {
    required String methodName,
  }) {
    final buf = StringBuffer();
    final aliasCn = _cn(aliasName);
    final r = _resolve(body);

    if (r is DidVec) {
      // Direct class/record elements only — nested containers (opt/vec)
      // need per-element null/list handling, handled below.
      final directInner = _resolve(r.inner);
      final isDirectClass =
          (directInner is DidNamed && _isNamedClass(directInner)) ||
          directInner is DidRecord ||
          directInner is DidVariant;
      final elem = isDirectClass ? _vecElementClass(aliasName, r.inner) : null;
      if (elem != null) {
        final ctypeExpr = _isPurePrimitiveAlias(body)
            ? _ctypeExprSimple(body)
            : '${aliasCn}Candid.ctype';
        buf.writeln(
          '    final decode = CandidUtils.decodeOneTyped(bytes, $ctypeExpr);',
        );
        buf.writeln(
          '    return JsonParser.valueEnsureAsList<Map<String, dynamic>>(decode)',
        );
        buf.writeln('        .map((e) => $elem.fromCandid(e))');
        buf.writeln('        .toList();');
        return buf.toString();
      }
      // vec of primitives / blobs / nested containers: decodeOneTyped
      // returns List<dynamic> — a direct `as` cast throws, so normalize
      // with valueAsList and convert each element.
      final useCtype = _isPurePrimitiveAlias(body)
          ? _ctypeExprSimple(body)
          : '${aliasCn}Candid.ctype';
      buf.writeln('    final result = JsonParser.valueAsList<List>(');
      buf.writeln('      CandidUtils.decodeOneTyped(bytes, $useCtype),');
      buf.writeln('    );');
      buf.writeln(
        '    return result.map((e) => ${_decodeElementExpr(r.inner, 'e', methodName: methodName, depth: 0, parentAlias: aliasName)}).toList();',
      );
      return buf.toString();
    }

    if (r is DidOpt) {
      final inner = _resolve(r.inner);
      if (inner is DidNamed && _isNamedClass(inner)) {
        final cn = _cn(inner.name);
        buf.writeln(
          '    final decode = CandidUtils.decodeOneTyped(bytes, ${aliasCn}Candid.ctype);',
        );
        buf.writeln('    if (decode == null) return null;');
        buf.writeln(
          '    return $cn.fromCandid(JsonParser.valueEnsureAsMap<String, dynamic>(decode));',
        );
        return buf.toString();
      }
      // opt of scalars: decode returns the scalar or null.
      final optInner = _resolve(r.inner);
      if (optInner is DidPrimitive) {
        buf.writeln(
          '    return CandidUtils.decodeOneTyped(bytes, ${aliasCn}Candid.ctype) as $aliasCn;',
        );
        return buf.toString();
      }
      // opt of records/containers: null-check, then convert element-wise.
      buf.writeln(
        '    final decode = CandidUtils.decodeOneTyped(bytes, ${aliasCn}Candid.ctype);',
      );
      buf.writeln('    if (decode == null) return null;');
      buf.writeln(
        '    return ${_decodeElementExpr(r.inner, 'decode', methodName: methodName, depth: 0, parentAlias: aliasName)};',
      );
      return buf.toString();
    }

    if (r is DidPrimitive) {
      if (r.name == 'principal') {
        buf.writeln(
          '    final raw = CandidUtils.decodeOneTyped(bytes, CType.principal);',
        );
        buf.writeln(
          '    return GeneratorParserUtils.principalFromCandid(raw);',
        );
        return buf.toString();
      }
      buf.writeln(
        '    return CandidUtils.decodeOneTyped(bytes, ${_ctypeExprSimple(r)}) as $aliasCn;',
      );
      return buf.toString();
    }

    // Fallback
    if (_isPurePrimitiveAlias(body)) {
      buf.writeln(
        '    return CandidUtils.decodeOneTyped(bytes, ${_ctypeExprSimple(body)}) as $aliasCn;',
      );
    } else {
      buf.writeln(
        '    return CandidUtils.decodeOneTyped(bytes, ${aliasCn}Candid.ctype) as $aliasCn;',
      );
    }
    return buf.toString();
  }

  String _ctypeExprSimple(DidType t) {
    return switch (t) {
      DidPrimitive(:final name) => switch (name) {
        'nat' => 'CType.nat',
        'int' => 'CType.int_',
        'nat8' => 'CType.nat8',
        'nat16' => 'CType.nat16',
        'nat32' => 'CType.nat32',
        'nat64' => 'CType.nat64',
        'int8' => 'CType.int8',
        'int16' => 'CType.int16',
        'int32' => 'CType.int32',
        'int64' => 'CType.int64',
        'float32' => 'CType.float32',
        'float64' => 'CType.float64',
        'bool' => 'CType.bool_',
        'text' => 'CType.text',
        'null' => 'CType.null_',
        'reserved' => 'CType.reserved',
        'empty' => 'CType.empty',
        'principal' => 'CType.principal',
        'blob' => 'CType.vec(CType.nat8)',
        _ => 'CType.null_',
      },
      DidOpt(:final inner) => 'CType.opt(${_ctypeExprSimple(inner)})',
      DidVec(:final inner) => 'CType.vec(${_ctypeExprSimple(inner)})',
      DidNamed(:final name) => () {
        if (_isNamedRecordOrVariant(DidNamed(name))) {
          return '${_cn(name)}.ctype';
        }
        final body = _aliasBody(name);
        if (body != null) {
          if (_isPurePrimitiveAlias(body)) {
            return _ctypeExprSimple(body);
          }
          return '${_cn(name)}Candid.ctype';
        }
        return '${_cn(name)}.ctype';
      }(),
      DidRecord() || DidVariant() =>
        // Must be routed via _ctypeRef / synthetic class.
        'CType.null_',
      _ => 'CType.null_',
    };
  }

  String _pascal(String name) {
    final parts = name
        .split(RegExp(r'[^0-9A-Za-z]+'))
        .where((p) => p.isNotEmpty);
    return parts.map((p) => p[0].toUpperCase() + p.substring(1)).join();
  }
}
