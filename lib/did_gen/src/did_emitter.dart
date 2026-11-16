import 'did_ast.dart';

/// Emits Dart [CandidSerializable] models from a parsed [DidFile].
///
/// Anonymous nested variants/records are lifted to named classes.
/// Identical shapes are emitted **once** and reused at every usage site.
class DidEmitter {
  final DidFile file;
  final String namePrefix;
  final List<String> typesImports;

  /// Relative import to shared GeneratorParserUtils, e.g. ../../utils/utils.dart
  final String utilsImport;

  late final Map<String, DidType> _aliases;
  late final Set<String> _typedefNames;

  /// structural shape key → single synthetic class
  final Map<String, _Synthetic> _byShape = {};

  /// `"$parentCn.$fieldName"` → synthetic class name (may share across sites)
  final Map<String, String> _usageToClass = {};

  final Set<String> _reservedNames = {};

  /// Usage key `"Method.arg"` / `"Method.response"` → synthetic class name
  /// (after shape dedup, e.g. GetKnownUtxos.arg → GetBtcAddressArg).
  Map<String, String> get syntheticUsages => Map.unmodifiable(_usageToClass);

  DidEmitter(
    this.file, {
    required this.namePrefix,
    this.typesImports = const [],
    this.utilsImport = '../../utils/utils.dart',
  }) {
    _aliases = {};
    _typedefNames = {};
    for (final def in file.types) {
      if (def.type is! DidRecord && def.type is! DidVariant) {
        _aliases[def.name] = def.type;
        _typedefNames.add(def.name);
        _reservedNames.add(_cn(def.name));
        _reservedNames.add('${_cn(def.name)}Candid');
      } else {
        _reservedNames.add(_cn(def.name));
      }
    }
  }

  String emit() {
    for (final def in file.types) {
      _collect(def.type, parentCn: _cn(def.name));
    }
    // Lift anonymous record/variant used only in service method args/returns
    // so e.g. `(variant { Ok; Err })` becomes `WithdrawErc20Response`.
    for (final svc in file.services) {
      for (final m in svc.methods) {
        final methodCn = '$namePrefix${_pascal(m.name)}';
        for (var i = 0; i < m.args.length; i++) {
          final field = m.args.length == 1 ? 'arg' : 'arg$i';
          _collectField(m.args[i], parentCn: methodCn, fieldName: field);
        }
        for (var i = 0; i < m.rets.length; i++) {
          final field = m.rets.length == 1 ? 'response' : 'response$i';
          _collectField(m.rets[i], parentCn: methodCn, fieldName: field);
        }
      }
    }

    final buf = StringBuffer();
    buf.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
    buf.writeln('// ignore_for_file: prefer_const_constructors, unused_import');
    buf.writeln();
    buf.writeln("import 'package:blockchain_utils/blockchain_utils.dart';");
    for (final imp in typesImports) {
      final path = imp.trim();
      if (path.isEmpty) continue;
      buf.writeln("import '$path';");
    }
    buf.writeln("import '$utilsImport';");
    buf.writeln();

    for (final def in file.types) {
      if (_typedefNames.contains(def.name)) {
        buf.writeln(_emitTypedef(def));
      }
    }
    if (_typedefNames.isNotEmpty) buf.writeln();

    // Unique shapes only
    for (final s in _byShape.values) {
      if (s.type is DidVariant) {
        buf.writeln(
          _emitVariant(s.className, s.origin, s.type as DidVariant, null),
        );
      } else if (s.type is DidRecord) {
        buf.writeln(
          _emitRecord(s.className, s.origin, s.type as DidRecord, null),
        );
      }
      buf.writeln();
    }

    for (final def in file.types) {
      if (_typedefNames.contains(def.name)) continue;
      buf.writeln(_emitDef(def));
      buf.writeln();
    }

    return buf.toString();
  }

  // ---------------------------------------------------------------------------
  // Structural shape key (for dedup)
  // ---------------------------------------------------------------------------

  String _shapeKey(DidType t) {
    return switch (t) {
      DidPrimitive(:final name) => 'P:$name',
      DidOpt(:final inner) => 'O(${_shapeKey(inner)})',
      DidVec(:final inner) => 'V(${_shapeKey(inner)})',
      DidNamed(:final name) => 'N:$name',
      DidRecord(:final fields) =>
        'R{${fields.map((f) => '${f.name}:${_shapeKey(f.type!)}').join(',')}}',
      DidVariant(:final fields) =>
        'U{${fields.map((f) => f.type == null ? '${f.name}:null' : '${f.name}:${_shapeKey(f.type!)}').join(',')}}',
      DidFunc() => 'Func',
      DidServiceType() => 'Service',
    };
  }

  // ---------------------------------------------------------------------------
  // Collect + dedupe anonymous variants / records
  // ---------------------------------------------------------------------------

  void _collect(DidType t, {required String parentCn}) {
    switch (t) {
      case DidRecord(:final fields):
        for (final f in fields) {
          if (f.type != null) {
            _collectField(f.type!, parentCn: parentCn, fieldName: f.name);
          }
        }
      case DidVariant(:final fields):
        for (final f in fields) {
          if (f.type == null) continue;
          final armCn = '$parentCn${_pascal(f.name)}';
          // Do not reserve arm names here — emit allocates uniquely vs typedefs.

          if (f.type is DidRecord) {
            // Embed fields on the arm class — no synthetic record.
            _collect(f.type!, parentCn: armCn);
          } else if (f.type is DidOpt &&
              (f.type as DidOpt).inner is DidRecord) {
            // upgrade : opt record { ... }
            // Arm class holds Payload?; payload is a separate synthetic.
            final payloadName = _allocName(armCn, 'payload');
            final record = (f.type as DidOpt).inner as DidRecord;
            final shape = _shapeKey(record);
            final usageKey = '$parentCn.${f.name}';
            if (_byShape.containsKey(shape)) {
              final existing = _byShape[shape]!;
              _usageToClass[usageKey] = existing.className;
              existing.usages.add(usageKey);
            } else {
              _byShape[shape] = _Synthetic(
                className: payloadName,
                type: record,
                origin: usageKey,
                usages: {usageKey},
              );
              _usageToClass[usageKey] = payloadName;
              _reservedNames.add(payloadName);
              _collect(record, parentCn: payloadName);
            }
          } else {
            _collectField(f.type!, parentCn: parentCn, fieldName: f.name);
          }
        }
      case DidOpt(:final inner):
        if (inner is DidRecord || inner is DidVariant) {
          // opt of anonymous compound at this level — use synthetic named by parent
          // only when we have a field context; bare opt is rare at top-level typedef.
          _collect(inner, parentCn: parentCn);
        } else {
          _collect(inner, parentCn: parentCn);
        }
      case DidVec(:final inner):
        final core = _unwrapContainers(inner);
        if (core is DidRecord || core is DidVariant) {
          // Register once under 'item' when used as typedef element, or rely on
          // _collectField from the parent field for named fields.
          _collectField(core, parentCn: parentCn, fieldName: 'item');
        } else {
          _collect(inner, parentCn: parentCn);
        }
      default:
        break;
    }
  }

  void _collectField(
    DidType t, {
    required String parentCn,
    required String fieldName,
  }) {
    final core = _unwrapContainers(t);
    final usageKey = '$parentCn.$fieldName';

    if (core is DidVariant || core is DidRecord) {
      final shape = _shapeKey(core);

      if (_byShape.containsKey(shape)) {
        // Reuse existing class for this shape
        final existing = _byShape[shape]!;
        _usageToClass[usageKey] = existing.className;
        existing.usages.add(usageKey);
      } else {
        // First time this shape is seen — allocate a name
        final className = _allocName(parentCn, fieldName);
        _byShape[shape] = _Synthetic(
          className: className,
          type: core,
          origin: usageKey,
          usages: {usageKey},
        );
        _usageToClass[usageKey] = className;
        _reservedNames.add(className);
        // Recurse into children with this synthetic as parent
        _collect(core, parentCn: className);
      }
    } else {
      _collect(t, parentCn: parentCn);
    }
  }

  String _allocName(String parentCn, String fieldName) {
    var base = '$parentCn${_pascal(fieldName)}';
    if (!_reservedNames.contains(base)) return base;
    // Collision with top-level or earlier synthetic: disambiguate
    var i = 2;
    while (_reservedNames.contains('$base$i')) {
      i++;
    }
    return '$base$i';
  }

  DidType _unwrapContainers(DidType t) {
    while (true) {
      if (t is DidOpt) {
        t = t.inner;
      } else if (t is DidVec) {
        t = t.inner;
      } else {
        return t;
      }
    }
  }

  String? _syntheticCn(String parentCn, String fieldName) {
    return _usageToClass['$parentCn.$fieldName'];
  }

  bool _isEmptyArmType(DidType? t) {
    if (t is DidPrimitive) {
      return t.name == 'reserved' || t.name == 'null' || t.name == 'empty';
    }
    return false;
  }

  static const _dartBuiltins = {
    'Map',
    'List',
    'Set',
    'String',
    'int',
    'double',
    'bool',
    'Null',
    'Object',
    'dynamic',
    'void',
    'Function',
    'Record',
    'Type',
    'Enum',
    'Future',
    'Stream',
    'Iterator',
    'Iterable',
    'Symbol',
    'Runes',
    'RegExp',
    'DateTime',
    'Uri',
    'Duration',
    'Comparable',
    'Pattern',
    'Error',
    'Exception',
    'num',
    'Never',
    'BigInt',
    'Uint8List',
    'ByteData',
    'Endian',
    'pragma',
  };

  String _cn(String name) {
    final base = _pascal(name);
    final full = '$namePrefix$base';
    // Only append `_` when the *full* identifier is a Dart reserved/builtin
    // (e.g. bare `Map`). Prefixed names like `LEDGERDuration` are fine.
    if (_dartBuiltins.contains(full)) {
      return '${full}_';
    }
    return full;
  }

  // ---------------------------------------------------------------------------
  // Typedef
  // ---------------------------------------------------------------------------

  String _emitTypedef(DidTypeDef def) {
    final cn = _cn(def.name);
    final dart = _dartType(def.type, parentCn: cn, fieldName: def.name);
    final buf = StringBuffer();
    if (def.comment != null && def.comment!.isNotEmpty) {
      buf.writeln('/// ${def.comment}');
    }
    buf.writeln('/// Candid type alias `${def.name}`.');
    buf.writeln('typedef $cn = $dart;');
    // Non-primitive aliases need a CType handle (typedefs cannot have static members).
    if (!_isPurePrimitiveAlias(def.type)) {
      buf.writeln();
      buf.writeln('/// CType for alias `${def.name}`.');
      buf.writeln('abstract final class ${cn}Candid {');
      buf.writeln(
        "  static CType get ctype => ${_ctypeExpr(def.type, parentCn: cn, fieldName: 'item', selfName: '${cn}Candid')};",
      );
      buf.writeln('}');
    }
    return buf.toString();
  }

  bool _isPurePrimitiveAlias(DidType t) {
    var cur = t;
    final seen = <String>{};
    while (true) {
      if (cur is DidNamed) {
        if (seen.contains(cur.name)) return false;
        seen.add(cur.name);
        if (!_aliases.containsKey(cur.name)) return false;
        cur = _aliases[cur.name]!;
        continue;
      }
      if (cur is DidPrimitive) return true;
      return false;
    }
  }

  String _emitDef(DidTypeDef def) {
    final t = def.type;
    if (t is DidRecord) {
      return _emitRecord(_cn(def.name), def.name, t, def.comment);
    }
    if (t is DidVariant) {
      return _emitVariant(_cn(def.name), def.name, t, def.comment);
    }
    return _emitTypedef(def);
  }

  // ===========================================================================
  // Record
  // ===========================================================================

  String _emitRecord(
    String cn,
    String didName,
    DidRecord rec,
    String? comment,
  ) {
    final fields = rec.fields;
    final buf = StringBuffer();

    if (comment != null && comment.isNotEmpty) {
      buf.writeln('/// $comment');
    }
    buf.writeln('/// Candid record `$didName`.');
    buf.writeln('final class $cn with CandidSerializable {');

    for (final f in fields) {
      buf.writeln(
        '  final ${_dartType(f.type!, parentCn: cn, fieldName: f.name)} ${_fieldName(f.name)};',
      );
    }
    buf.writeln();

    if (fields.isEmpty) {
      buf.writeln('  const $cn();');
    } else {
      buf.writeln('  const $cn({');
      for (final f in fields) {
        final req = f.type is DidOpt ? '' : 'required ';
        buf.writeln('    ${req}this.${_fieldName(f.name)},');
      }
      buf.writeln('  });');
    }
    buf.writeln();

    buf.writeln(
      "  static CType get ctype => ${_ctypeExpr(rec, parentCn: cn, selfName: cn)};",
    );
    buf.writeln();
    buf.writeln('  @override');
    buf.writeln('  CType get candidType => ctype;');
    buf.writeln();
    buf.write(_candidValueMap(fields, parentCn: cn));
    buf.writeln();
    buf.write(_toJsonMap(fields, parentCn: cn));
    buf.writeln();

    buf.writeln('  factory $cn.fromCandid(Map<String, dynamic> json) {');
    if (fields.isEmpty) {
      buf.writeln('    return const $cn();');
    } else {
      buf.writeln('    return $cn(');
      for (final f in fields) {
        buf.writeln(
          '      ${_fieldName(f.name)}: ${_fromJson(f.type!, f.name, parentCn: cn)},',
        );
      }
      buf.writeln('    );');
    }
    buf.writeln('  }');
    buf.writeln();

    buf.writeln('  factory $cn.fromBytes(List<int> bytes) {');
    buf.writeln('    final raw = CandidUtils.decodeOneTyped(bytes, ctype);');
    buf.writeln(
      '    return $cn.fromCandid(JsonParser.valueEnsureAsMap<String, dynamic>(raw));',
    );
    buf.writeln('  }');
    buf.writeln('}');
    return buf.toString();
  }

  String _candidValueMap(List<DidField> fields, {required String parentCn}) {
    final buf = StringBuffer();
    buf.writeln('  @override');
    if (fields.isEmpty) {
      buf.writeln('  dynamic get candidValue => <String, dynamic>{};');
      return buf.toString();
    }
    buf.writeln('  dynamic get candidValue => {');
    for (final f in fields) {
      final fn = _fieldName(f.name);
      buf.writeln(
        "    '${f.name}': ${_toCandid(f.type!, fn, parentCn: parentCn, fieldName: f.name)},",
      );
    }
    buf.writeln('  };');
    return buf.toString();
  }

  String _toJsonMap(List<DidField> fields, {required String parentCn}) {
    final buf = StringBuffer();
    if (fields.isEmpty) {
      buf.writeln('  Map<String, dynamic> toJson() => <String, dynamic>{};');
      return buf.toString();
    }
    buf.writeln('  Map<String, dynamic> toJson() => {');
    for (final f in fields) {
      final fn = _fieldName(f.name);
      buf.writeln(
        "    '${f.name}': ${_toJson(f.type!, fn, parentCn: parentCn, fieldName: f.name)},",
      );
    }
    buf.writeln('  };');
    return buf.toString();
  }

  // ===========================================================================
  // Variant
  // ===========================================================================

  String _emitVariant(
    String cn,
    String didName,
    DidVariant vari,
    String? comment,
  ) {
    final buf = StringBuffer();
    if (comment != null && comment.isNotEmpty) {
      buf.writeln('/// $comment');
    }
    buf.writeln('/// Candid variant `$didName`.');
    buf.writeln('sealed class $cn with CandidSerializable {');
    buf.writeln('  const $cn();');
    buf.writeln();
    // Pre-allocate arm class names so typedefs like NestedMetaMap do not collide
    // with arm NestedMeta + map.
    final armNames = <String, String>{};
    for (final f in vari.fields) {
      final preferred = '$cn${_pascal(f.name)}';
      armNames[f.name] = _uniqueClassName(preferred);
    }
    buf.writeln(
      "  static CType get ctype => ${_ctypeExpr(vari, parentCn: cn, selfName: cn)};",
    );
    buf.writeln();
    buf.writeln('  @override');
    buf.writeln('  CType get candidType => ctype;');
    buf.writeln();
    buf.writeln('  Map<String, dynamic> toJson();');
    buf.writeln();

    buf.writeln('  factory $cn.fromCandid(Map<String, dynamic> json) {');
    for (final f in vari.fields) {
      final tag = f.name;
      final arm = armNames[tag]!;
      buf.writeln("    if (json.containsKey('$tag')) {");
      if (f.type == null || _isEmptyArmType(f.type)) {
        buf.writeln('      return const $arm();');
      } else if (f.type is DidRecord) {
        buf.writeln(
          "      return $arm.fromCandid(\n"
          "        JsonParser.valueEnsureAsMap<String, dynamic>(json['$tag']),\n"
          '      );',
        );
      } else if (f.type is DidOpt && (f.type as DidOpt).inner is DidRecord) {
        final payloadCn = _syntheticCn(cn, tag) ?? '${arm}Payload';
        buf.writeln("      final raw = json['$tag'];");
        buf.writeln('      return $arm(');
        buf.writeln('        raw == null');
        buf.writeln('            ? null');
        buf.writeln(
          "            : $payloadCn.fromCandid(\n"
          '                JsonParser.valueEnsureAsMap<String, dynamic>(raw),\n'
          '              ),',
        );
        buf.writeln('      );');
      } else {
        buf.writeln(
          '      return $arm(${_fromJson(f.type!, tag, parentCn: cn)});',
        );
      }
      buf.writeln('    }');
    }
    buf.writeln(
      "    throw ArgumentException.invalidOperationArguments(\n"
      "      '$cn.fromCandid',\n"
      "      reason: 'Unknown $cn arm',\n"
      '    );',
    );
    buf.writeln('  }');
    buf.writeln();

    buf.writeln('  factory $cn.fromBytes(List<int> bytes) {');
    buf.writeln('    final raw = CandidUtils.decodeOneTyped(bytes, ctype);');
    buf.writeln(
      '    return $cn.fromCandid(JsonParser.valueEnsureAsMap<String, dynamic>(raw));',
    );
    buf.writeln('  }');
    buf.writeln('}');
    buf.writeln();

    for (final f in vari.fields) {
      final tag = f.name;
      final arm = armNames[tag]!;

      if (f.type is DidRecord) {
        final rec = f.type as DidRecord;
        buf.writeln('/// Variant arm `$didName.$tag`.');
        buf.writeln('final class $arm extends $cn {');
        for (final rf in rec.fields) {
          buf.writeln(
            '  final ${_dartType(rf.type!, parentCn: arm, fieldName: rf.name)} ${_fieldName(rf.name)};',
          );
        }
        buf.writeln();
        if (rec.fields.isEmpty) {
          buf.writeln('  const $arm();');
        } else {
          buf.writeln('  const $arm({');
          for (final rf in rec.fields) {
            final req = rf.type is DidOpt ? '' : 'required ';
            buf.writeln('    ${req}this.${_fieldName(rf.name)},');
          }
          buf.writeln('  });');
        }
        buf.writeln();
        buf.writeln('  @override');
        buf.writeln('  CType get candidType => $cn.ctype;');
        buf.writeln();
        buf.writeln('  @override');
        buf.writeln("  dynamic get candidValue => Variant('$tag', {");
        for (final rf in rec.fields) {
          final fn = _fieldName(rf.name);
          buf.writeln(
            "    '${rf.name}': ${_toCandid(rf.type!, fn, parentCn: arm, fieldName: rf.name)},",
          );
        }
        buf.writeln('  });');
        buf.writeln();
        buf.writeln('  @override');
        buf.writeln("  Map<String, dynamic> toJson() => {");
        buf.writeln("    '$tag': {");
        for (final rf in rec.fields) {
          final fn = _fieldName(rf.name);
          buf.writeln(
            "      '${rf.name}': ${_toJson(rf.type!, fn, parentCn: arm, fieldName: rf.name)},",
          );
        }
        buf.writeln('    },');
        buf.writeln('  };');
        buf.writeln();
        buf.writeln('  factory $arm.fromCandid(Map<String, dynamic> json) {');
        buf.writeln('    return $arm(');
        for (final rf in rec.fields) {
          buf.writeln(
            '      ${_fieldName(rf.name)}: ${_fromJson(rf.type!, rf.name, parentCn: arm)},',
          );
        }
        buf.writeln('    );');
        buf.writeln('  }');
        buf.writeln('}');
        buf.writeln();
      } else if (f.type == null || _isEmptyArmType(f.type)) {
        buf.writeln('/// Variant arm `$didName.$tag` (nullary).');
        buf.writeln('final class $arm extends $cn {');
        buf.writeln('  const $arm();');
        buf.writeln();
        buf.writeln('  @override');
        buf.writeln('  CType get candidType => $cn.ctype;');
        buf.writeln();
        buf.writeln('  @override');
        buf.writeln(
          "  dynamic get candidValue => const Variant('$tag', null);",
        );
        buf.writeln();
        buf.writeln('  @override');
        buf.writeln("  Map<String, dynamic> toJson() => {'$tag': null};");
        buf.writeln('}');
        buf.writeln();
      } else if (f.type is DidOpt && (f.type as DidOpt).inner is DidRecord) {
        final payloadCn = _syntheticCn(cn, tag) ?? '${arm}Payload';
        buf.writeln('/// Variant arm `$didName.$tag` (`opt record`).');
        buf.writeln('final class $arm extends $cn {');
        buf.writeln('  final $payloadCn? value;');
        buf.writeln('  const $arm([this.value]);');
        buf.writeln();
        buf.writeln('  @override');
        buf.writeln('  CType get candidType => $cn.ctype;');
        buf.writeln();
        buf.writeln('  @override');
        buf.writeln(
          "  dynamic get candidValue => Variant('$tag', value?.candidValue);",
        );
        buf.writeln();
        buf.writeln('  @override');
        buf.writeln(
          "  Map<String, dynamic> toJson() => {'$tag': value?.toJson()};",
        );
        buf.writeln('}');
        buf.writeln();
      } else {
        final dt = _dartType(f.type!, parentCn: cn, fieldName: tag);
        buf.writeln('/// Variant arm `$didName.$tag`.');
        buf.writeln('final class $arm extends $cn {');
        buf.writeln('  final $dt value;');
        buf.writeln('  const $arm(this.value);');
        buf.writeln();
        buf.writeln('  @override');
        buf.writeln('  CType get candidType => $cn.ctype;');
        buf.writeln();
        buf.writeln('  @override');
        buf.writeln(
          "  dynamic get candidValue => Variant('$tag', ${_toCandid(f.type!, 'value', parentCn: cn, fieldName: tag)});",
        );
        buf.writeln();
        buf.writeln('  @override');
        buf.writeln(
          "  Map<String, dynamic> toJson() => {'$tag': ${_toJson(f.type!, 'value', parentCn: cn, fieldName: tag)}};",
        );
        buf.writeln('}');
        buf.writeln();
      }
    }

    return buf.toString();
  }

  // ===========================================================================
  // CType
  // ===========================================================================

  /// Use [LazyField] when the type expression refers to another generated
  /// `.ctype` (named / synthetic / typedef companion) so recursive types
  /// like MetadataMap and Value do not stack-overflow at construction.
  String _fieldCtor(String labelExpr, String ctypeExpr) {
    // Any `.ctype` reference or self `ctype` (static late final) must be lazy.
    if (ctypeExpr.contains('ctype')) {
      return 'LazyField($labelExpr, () => $ctypeExpr)';
    }
    return 'Field($labelExpr, $ctypeExpr)';
  }

  String _ctypeExpr(
    DidType t, {
    required String parentCn,
    String? fieldName,
    Set<String>? expanding,
    String? selfName,
  }) {
    final exp = expanding ?? <String>{};
    return switch (t) {
      DidPrimitive(:final name) => _primCType(name),
      DidOpt(:final inner) =>
        'CType.opt(${_ctypeExpr(inner, parentCn: parentCn, fieldName: fieldName, expanding: exp, selfName: selfName)})',
      DidVec(:final inner) =>
        'CType.vec(${_ctypeExpr(inner, parentCn: parentCn, fieldName: fieldName, expanding: exp, selfName: selfName)})',
      DidNamed(:final name) => () {
        final cn = _cn(name);
        final candidCn = '${cn}Candid';
        // Self-reference: ClassName.ctype (clearer than bare ctype).
        if (selfName != null && (selfName == cn || selfName == candidCn)) {
          return '$selfName.ctype';
        }
        if (_typedefNames.contains(name)) {
          if (!_isPurePrimitiveAlias(_aliases[name]!)) {
            return '$candidCn.ctype';
          }
          if (exp.contains(name)) {
            return '$candidCn.ctype';
          }
          exp.add(name);
          final out = _ctypeExpr(
            _aliases[name]!,
            parentCn: parentCn,
            fieldName: fieldName,
            expanding: exp,
            selfName: selfName,
          );
          exp.remove(name);
          return out;
        }
        return '$cn.ctype';
      }(),
      DidRecord(:final fields) => () {
        if (fieldName != null) {
          final syn = _syntheticCn(parentCn, fieldName);
          if (syn != null) {
            if (selfName != null && selfName == syn) return '$selfName.ctype';
            return '$syn.ctype';
          }
        }
        if (fields.isEmpty) return 'CType.record(const [])';
        final parts = <String>[];
        for (final f in fields) {
          final te = _ctypeExpr(
            f.type!,
            parentCn: parentCn,
            fieldName: f.name,
            expanding: exp,
            selfName: selfName,
          );
          parts.add(_fieldCtor(_labelExpr(f.name), te));
        }
        return 'CType.record([\n    ${parts.join(',\n    ')},\n  ])';
      }(),
      DidVariant(:final fields) => () {
        if (fieldName != null) {
          final syn = _syntheticCn(parentCn, fieldName);
          if (syn != null) {
            if (selfName != null && selfName == syn) return '$selfName.ctype';
            return '$syn.ctype';
          }
        }
        final parts = <String>[];
        for (final f in fields) {
          if (f.type == null) {
            parts.add("Field(${_labelExpr(f.name)}, CType.null_)");
          } else {
            final te = _ctypeExpr(
              f.type!,
              parentCn: parentCn,
              fieldName: f.name,
              expanding: exp,
              selfName: selfName,
            );
            parts.add(_fieldCtor(_labelExpr(f.name), te));
          }
        }
        return 'CType.variant([\n    ${parts.join(',\n    ')},\n  ])';
      }(),
      DidFunc() => 'CType.func(const FunctionType([], [], []))',
      DidServiceType() => 'CType.service(const [])',
    };
  }

  String _primCType(String name) => switch (name) {
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
  };

  // ===========================================================================
  // Dart types
  // ===========================================================================

  DidType _resolve(DidType t) {
    if (t is DidNamed && _aliases.containsKey(t.name)) {
      return _resolve(_aliases[t.name]!);
    }
    return t;
  }

  bool _isBytesInner(DidType inner) {
    final r = _resolve(inner);
    return r is DidPrimitive && (r.name == 'nat8' || r.name == 'blob');
  }

  String _dartType(
    DidType t, {
    required String parentCn,
    required String fieldName,
  }) {
    return switch (t) {
      DidPrimitive(:final name) => _primDart(name),
      DidOpt(:final inner) => () {
        final base = _dartType(inner, parentCn: parentCn, fieldName: fieldName);
        // Dart has no nested nullability; keep a single `?` even for `opt opt T`.
        return base.endsWith('?') ? base : '$base?';
      }(),
      DidVec(:final inner) => () {
        if (_isBytesInner(inner)) return 'List<int>';
        // One List level per DidVec — never collapse nested vec/opt.
        return 'List<${_dartType(inner, parentCn: parentCn, fieldName: fieldName)}>';
      }(),
      DidNamed(:final name) => _cn(name),
      DidRecord() || DidVariant() =>
        _syntheticCn(parentCn, fieldName) ??
            _syntheticCn(parentCn, 'item') ??
            'Map<String, dynamic>',
      DidFunc() => 'FuncRef',
      DidServiceType() => 'ServiceRef',
    };
  }

  String _primDart(String name) => switch (name) {
    'nat' || 'int' || 'nat64' || 'int64' => 'BigInt',
    'nat8' || 'nat16' || 'nat32' || 'int8' || 'int16' || 'int32' => 'int',
    'float32' || 'float64' => 'double',
    'bool' => 'bool',
    'text' => 'String',
    'principal' => 'IcpPrincipalAddress',
    'blob' => 'List<int>',
    _ => 'dynamic',
  };

  // ===========================================================================
  // candidValue
  // ===========================================================================

  String _toCandid(
    DidType t,
    String expr, {
    required String parentCn,
    required String fieldName,
  }) {
    // Expand typedefs first so vec/record rules apply.
    if (t is DidNamed && _typedefNames.contains(t.name)) {
      return _toCandid(
        _aliases[t.name]!,
        expr,
        parentCn: _cn(t.name),
        fieldName: 'item',
      );
    }

    if (t is DidOpt) {
      final innerMapped = _toCandid(
        t.inner,
        expr,
        parentCn: parentCn,
        fieldName: fieldName,
      );
      if (innerMapped == expr) {
        return expr; // primitives / already plain
      }
      // expr.candidValue → expr?.candidValue
      if (innerMapped == '$expr.candidValue') {
        return '$expr?.candidValue';
      }
      // expr.map((e) => ...) → expr?.map((e) => ...)
      if (innerMapped.startsWith('$expr.')) {
        return '$expr?.${innerMapped.substring(expr.length + 1)}';
      }
      // Fallback: treat as optional of mapped value
      return innerMapped;
    }

    if (t is DidNamed) {
      return '$expr.candidValue';
    }

    if (t is DidVec) {
      final inner = t.inner;
      if (_isBytesInner(inner)) {
        return expr;
      }
      // Unique loop variable so nested vec does not shadow.
      final iv = expr == 'el' ? 'e1' : (expr == 'e1' ? 'e2' : 'el');
      final elem = _toCandid(
        inner,
        iv,
        parentCn: parentCn,
        fieldName: fieldName,
      );
      if (elem == iv) {
        return expr;
      }
      return '$expr.map(($iv) => $elem).toList()';
    }

    if (t is DidVariant || t is DidRecord) {
      return '$expr.candidValue';
    }
    return expr;
  }

  /// JSON form of a field value (nested models use [toJson]).
  String _toJson(
    DidType t,
    String expr, {
    required String parentCn,
    required String fieldName,
  }) {
    if (t is DidNamed && _typedefNames.contains(t.name)) {
      return _toJson(
        _aliases[t.name]!,
        expr,
        parentCn: _cn(t.name),
        fieldName: 'item',
      );
    }

    if (t is DidOpt) {
      final innerMapped = _toJson(
        t.inner,
        expr,
        parentCn: parentCn,
        fieldName: fieldName,
      );
      if (innerMapped == expr) {
        return expr;
      }
      if (innerMapped == '$expr.toJson()') {
        return '$expr?.toJson()';
      }
      if (innerMapped.startsWith('$expr.')) {
        return '$expr?.${innerMapped.substring(expr.length + 1)}';
      }
      return innerMapped;
    }

    if (t is DidNamed) {
      // Named record/variant class or principal-like — prefer toJson when class.
      final matches = file.types.where((d) => d.name == t.name);
      final def = matches.isEmpty ? null : matches.first;
      if (def != null && (def.type is DidRecord || def.type is DidVariant)) {
        return '$expr.toJson()';
      }
      if (def == null) {
        // synthetic / external class
        return '$expr.toJson()';
      }
      // typedef expanded above; pure alias left as-is
      return expr;
    }

    if (t is DidVec) {
      final inner = t.inner;
      if (_isBytesInner(inner)) {
        return expr;
      }
      final iv = expr == 'el' ? 'e1' : (expr == 'e1' ? 'e2' : 'el');
      final elem = _toJson(inner, iv, parentCn: parentCn, fieldName: fieldName);
      if (elem == iv) {
        return expr;
      }
      return '$expr.map(($iv) => $elem).toList()';
    }

    if (t is DidVariant || t is DidRecord) {
      return '$expr.toJson()';
    }

    // principal primitive
    if (t is DidPrimitive && t.name == 'principal') {
      return '$expr.address';
    }

    return expr;
  }

  // ===========================================================================
  // JsonParser fromCandid
  // ===========================================================================

  String _fromJson(DidType t, String key, {required String parentCn}) {
    return switch (t) {
      DidOpt(:final inner) => _fromJsonNullable(inner, key, parentCn: parentCn),
      DidPrimitive(:final name) => _primFromJson(name, key, nullable: false),
      DidNamed(:final name) => _namedFromJson(
        name,
        key,
        nullable: false,
        parentCn: parentCn,
      ),
      DidVec(:final inner) => _fromJsonVec(
        inner,
        key,
        nullable: false,
        parentCn: parentCn,
      ),
      DidVariant() || DidRecord() => () {
        final syn = _syntheticCn(parentCn, key);
        if (syn == null) return "json['$key']";
        return "json.valueTo<$syn, Map>(\n"
            "        key: '$key',\n"
            "        parse: (e) => $syn.fromCandid(\n"
            '          JsonParser.valueEnsureAsMap<String, dynamic>(e),\n'
            '        ),\n'
            '      )';
      }(),
      _ => "json['$key']",
    };
  }

  String _fromJsonNullable(
    DidType inner,
    String key, {
    required String parentCn,
  }) {
    return switch (inner) {
      DidPrimitive(:final name) => _primFromJson(name, key, nullable: true),
      DidNamed(:final name) => _namedFromJson(
        name,
        key,
        nullable: true,
        parentCn: parentCn,
      ),
      DidVec(:final inner) => _fromJsonVec(
        inner,
        key,
        nullable: true,
        parentCn: parentCn,
      ),
      DidVariant() || DidRecord() => () {
        final syn = _syntheticCn(parentCn, key);
        if (syn == null) return "json['$key']";
        return "json.valueTo<$syn?, Map>(\n"
            "        key: '$key',\n"
            "        parse: (e) => $syn.fromCandid(\n"
            '          JsonParser.valueEnsureAsMap<String, dynamic>(e),\n'
            '        ),\n'
            '      )';
      }(),
      _ => "json['$key']",
    };
  }

  String _namedFromJson(
    String name,
    String key, {
    required bool nullable,
    required String parentCn,
  }) {
    if (_typedefNames.contains(name)) {
      final underlying = _aliases[name]!;
      // Use the typedef's own name as parent so vec/record synthetics resolve
      // (e.g. MetadataMap → List<MetadataMapItem>).
      final typedefParent = _cn(name);
      if (nullable) {
        final core = underlying is DidOpt ? underlying.inner : underlying;
        return _fromJsonNullable(core, key, parentCn: typedefParent);
      }
      return _fromJson(underlying, key, parentCn: typedefParent);
    }
    final cn = _cn(name);
    if (nullable) {
      return "json.valueTo<$cn?, Map>(\n"
          "        key: '$key',\n"
          "        parse: (e) => $cn.fromCandid(\n"
          '          JsonParser.valueEnsureAsMap<String, dynamic>(e),\n'
          '        ),\n'
          '      )';
    }
    return "json.valueTo<$cn, Map>(\n"
        "        key: '$key',\n"
        "        parse: (e) => $cn.fromCandid(\n"
        '          JsonParser.valueEnsureAsMap<String, dynamic>(e),\n'
        '        ),\n'
        '      )';
  }

  String _fromJsonVec(
    DidType inner,
    String key, {
    required bool nullable,
    required String parentCn,
  }) {
    if (_isBytesInner(inner)) {
      if (nullable) {
        return "json.valueAsBytes<List<int>?>('$key', encoding: StringEncoding.base64)";
      }
      return "json.valueAsBytes<List<int>>('$key', encoding: StringEncoding.base64)";
    }

    final elemDart = _dartType(inner, parentCn: parentCn, fieldName: key);
    final ty = nullable ? 'List<$elemDart>?' : 'List<$elemDart>';
    final parseElem = _listElementFromJson(
      inner,
      'x',
      parentCn: parentCn,
      fieldName: key,
    );

    return "json.valueTo<$ty, List>(\n"
        "        key: '$key',\n"
        "        parse: (e) => e.map<$elemDart>((x) => $parseElem).toList(),\n"
        '      )';
  }

  /// Expression that converts a single dynamic list element [xExpr] into the
  /// Dart type for [inner] (handles nested vec, records, variants, named types).
  String _listElementFromJson(
    DidType inner,
    String xExpr, {
    required String parentCn,
    required String fieldName,
  }) {
    // Expand typedefs
    if (inner is DidNamed && _typedefNames.contains(inner.name)) {
      return _listElementFromJson(
        _aliases[inner.name]!,
        xExpr,
        parentCn: _cn(inner.name),
        fieldName: 'item',
      );
    }

    if (inner is DidOpt) {
      // Element itself optional — rare in candid lists
      final nonNull = _listElementFromJson(
        inner.inner,
        xExpr,
        parentCn: parentCn,
        fieldName: fieldName,
      );
      return '$xExpr == null ? null : $nonNull';
    }

    if (inner is DidVec) {
      if (_isBytesInner(inner.inner)) {
        return '$xExpr is List<int> ? List<int>.from($xExpr) : List<int>.from($xExpr as List)';
      }
      final elemDart = _dartType(
        inner.inner,
        parentCn: parentCn,
        fieldName: fieldName,
      );
      final parseInner = _listElementFromJson(
        inner.inner,
        'y',
        parentCn: parentCn,
        fieldName: fieldName,
      );
      return '($xExpr as List).map<$elemDart>((y) => $parseInner).toList()';
    }

    if (inner is DidRecord || inner is DidVariant) {
      final syn =
          _syntheticCn(parentCn, fieldName) ?? _syntheticCn(parentCn, 'item');
      if (syn != null) {
        return '$syn.fromCandid(JsonParser.valueEnsureAsMap<String, dynamic>($xExpr))';
      }
      return 'Map<String, dynamic>.from($xExpr as Map)';
    }

    if (inner is DidNamed) {
      final cn = _cn(inner.name);
      // Variant and record named types: always fromCandid with map
      return '$cn.fromCandid(JsonParser.valueEnsureAsMap<String, dynamic>($xExpr))';
    }

    if (inner is DidPrimitive) {
      return switch (inner.name) {
        'nat' ||
        'int' ||
        'nat64' ||
        'int64' => 'JsonParser.valueAsBigInt<BigInt>($xExpr)',
        'nat8' ||
        'nat16' ||
        'nat32' ||
        'int8' ||
        'int16' ||
        'int32' => 'JsonParser.valueAsInt<int>($xExpr)',
        'bool' => 'JsonParser.valueAsBool<bool>($xExpr)',
        'text' => 'JsonParser.valueAsString<String>($xExpr)',
        'principal' => 'GeneratorParserUtils.principalFromCandid($xExpr)',
        'blob' =>
          'JsonParser.valueAsBytes<List<int>>($xExpr, encoding: StringEncoding.base64)',
        'float32' || 'float64' => 'JsonParser.valueAsDouble<double>($xExpr)',
        _ => xExpr,
      };
    }

    return xExpr;
  }

  String _primFromJson(String name, String key, {required bool nullable}) {
    return switch (name) {
      'nat' || 'int' || 'nat64' || 'int64' =>
        nullable
            ? "json.valueAsBigInt<BigInt?>('$key')"
            : "json.valueAsBigInt<BigInt>('$key')",
      'nat8' || 'nat16' || 'nat32' || 'int8' || 'int16' || 'int32' =>
        nullable
            ? "json.valueAsInt<int?>('$key')"
            : "json.valueAsInt<int>('$key')",
      'bool' =>
        nullable
            ? "json.valueAsBool<bool?>('$key')"
            : "json.valueAsBool<bool>('$key')",
      'text' =>
        nullable
            ? "json.valueAsString<String?>('$key')"
            : "json.valueAsString<String>('$key')",
      'principal' =>
        nullable
            ? "json.valueTo<IcpPrincipalAddress?, dynamic>(\n"
                  "        key: '$key',\n"
                  "        parse: (e) => GeneratorParserUtils.principalFromCandid(e),\n"
                  '      )'
            : "json.valueTo<IcpPrincipalAddress, dynamic>(\n"
                  "        key: '$key',\n"
                  "        parse: (e) => GeneratorParserUtils.principalFromCandid(e),\n"
                  '      )',
      'blob' =>
        nullable
            ? "json.valueAsBytes<List<int>?>('$key', encoding: StringEncoding.base64)"
            : "json.valueAsBytes<List<int>>('$key', encoding: StringEncoding.base64)",
      'float32' || 'float64' =>
        nullable
            ? "json.valueAsDouble<double?>('$key')"
            : "json.valueAsDouble<double>('$key')",
      _ => "json['$key']",
    };
  }

  // ===========================================================================
  // naming
  // ===========================================================================

  /// Tuple fields `record { text; Value }` use numeric ids 0,1,… not idlHash("0").
  String _labelExpr(String name) {
    if (RegExp(r'^\d+$').hasMatch(name)) {
      return 'Label.id($name)';
    }
    return "Label.named('$name')";
  }

  String _fieldName(String name) {
    if (RegExp(r'^\d+$').hasMatch(name)) return 'field$name';
    final parts = name
        .split(RegExp(r'[^0-9A-Za-z]+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return name;
    var s = parts.first[0].toLowerCase() + parts.first.substring(1);
    for (var i = 1; i < parts.length; i++) {
      final p = parts[i];
      s += p[0].toUpperCase() + p.substring(1);
    }
    const reserved = {
      'class',
      'in',
      'is',
      'new',
      'var',
      'void',
      'default',
      'switch',
    };
    if (reserved.contains(s)) return '${s}Value';
    return s;
  }

  /// Avoid clashing with typedefs / other classes (e.g. NestedMetaMap arm vs typedef).
  String _uniqueClassName(String preferred) {
    if (!_reservedNames.contains(preferred)) {
      _reservedNames.add(preferred);
      return preferred;
    }
    var i = 2;
    while (_reservedNames.contains('$preferred$i')) {
      i++;
    }
    final name = '$preferred$i';
    _reservedNames.add(name);
    return name;
  }

  String _pascal(String name) {
    final parts = name
        .split(RegExp(r'[^0-9A-Za-z]+'))
        .where((p) => p.isNotEmpty);
    return parts.map((p) => p[0].toUpperCase() + p.substring(1)).join();
  }
}

class _Synthetic {
  final String className;
  final DidType type;
  final String origin;
  final Set<String> usages;
  _Synthetic({
    required this.className,
    required this.type,
    required this.origin,
    required this.usages,
  });
}
