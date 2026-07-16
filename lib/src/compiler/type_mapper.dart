import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:onchain_proto/src/compiler/compiler.dart';
import 'package:onchain_proto/src/compiler/dart_converter.dart';
import 'package:onchain_proto/src/exception/exception.dart';
import 'package:onchain_proto/src/types/types.dart';
import 'package:onchain_proto/src/utils/utils.dart';

import 'type_location.dart';

abstract final class ProtoRuntimeTypeMapper {
  static String dartFieldType({
    required ProtoType type,

    required bool optional,
    required bool required,
    required ProtoCompiler resolver,
    required Set<ProtoTypeLocation> importRefrences,
  }) {
    final base = bareDartType(
      type: type,
      resolver: resolver,
      importRefrences: importRefrences,
    );
    if (isNullable(type: type, optional: optional, required: required) &&
        !base.endsWith('?')) {
      return '$base?';
    }
    return base;
  }

  static String bareDartType({
    required ProtoType type,
    required ProtoCompiler resolver,
    required Set<ProtoTypeLocation> importRefrences,
  }) {
    switch (type) {
      case ProtoScalar(type: final st):
        return _dartScalarType(st);
      case ProtoMessageRefrence(:final fullTypeName):
        return importRefrences.qualifyType(
          OnChainProtoUtils.className(
            fullTypeName(),
            prefix: resolver.classNamePrefix,
          ),
          type,
        );
      case ProtoRepeated(inner: final inner):
        return 'List<${bareDartType(type: inner, importRefrences: importRefrences, resolver: resolver)}>';
      case ProtoMap(key: final k, value: final v):
        return 'Map<${bareDartType(type: k, resolver: resolver, importRefrences: importRefrences)}, ${bareDartType(type: v, importRefrences: importRefrences, resolver: resolver)}>';
    }
  }

  static bool isNullable({
    required ProtoType type,
    required bool optional,
    required bool required,
  }) {
    if (required || type is ProtoRepeated || type is ProtoMap) return false;
    if (optional) return true;
    if (type is ProtoMessageRefrence) return true;
    if (type case ProtoScalar()) {
      return true;
    }
    return false;
  }

  static String? defaultValueExpr({
    required ProtoType type,
    required bool optional,
    required bool required,
    required ProtoCompiler resolver,
  }) {
    if (isNullable(type: type, optional: optional, required: required))
      return null;
    switch (type) {
      case ProtoRepeated():
        return 'const []';
      case ProtoMap():
        return 'const {}';
      case ProtoScalar(type: final st):
        return _dartScalarDefault(st);
      case ProtoMessageRefrence():
        return null;
    }
  }

  static String _dartScalarType(ProtoScalarType st) {
    switch (st) {
      case ProtoScalarType.double_:
      case ProtoScalarType.float_:
        return 'double';
      case ProtoScalarType.int32:
      case ProtoScalarType.sint32:
      case ProtoScalarType.sfixed32:
      case ProtoScalarType.uint32:
      case ProtoScalarType.fixed32:
        return 'int';
      case ProtoScalarType.int64:
      case ProtoScalarType.uint64:
      case ProtoScalarType.sint64:
      case ProtoScalarType.fixed64:
      case ProtoScalarType.sfixed64:
        return 'BigInt';
      case ProtoScalarType.bool_:
        return 'bool';
      case ProtoScalarType.string_:
        return 'String';
      case ProtoScalarType.bytes:
        return 'List<int>';
    }
  }

  static String? _dartScalarDefault(ProtoScalarType st) {
    switch (st) {
      case ProtoScalarType.double_:
      case ProtoScalarType.float_:
        return '0.0';
      case ProtoScalarType.int32:
      case ProtoScalarType.sint32:
      case ProtoScalarType.sfixed32:
      case ProtoScalarType.uint32:
      case ProtoScalarType.fixed32:
        return '0';
      case ProtoScalarType.bool_:
        return 'false';
      default:
        return null;
    }
  }

  static String _wireFieldType(ProtoScalarType st) {
    switch (st) {
      case ProtoScalarType.double_:
        return 'ProtoFieldType.double';
      case ProtoScalarType.float_:
        return 'ProtoFieldType.float';
      case ProtoScalarType.int32:
        return 'ProtoFieldType.int32';
      case ProtoScalarType.int64:
        return 'ProtoFieldType.int64';
      case ProtoScalarType.uint32:
        return 'ProtoFieldType.uint32';
      case ProtoScalarType.uint64:
        return 'ProtoFieldType.uint64';
      case ProtoScalarType.sint32:
        return 'ProtoFieldType.sint32';
      case ProtoScalarType.sint64:
        return 'ProtoFieldType.sint64';
      case ProtoScalarType.fixed32:
        return 'ProtoFieldType.fixed32';
      case ProtoScalarType.fixed64:
        return 'ProtoFieldType.fixed64';
      case ProtoScalarType.sfixed32:
        return 'ProtoFieldType.sFixed32';
      case ProtoScalarType.sfixed64:
        return 'ProtoFieldType.sFixed64';
      case ProtoScalarType.bool_:
        return 'ProtoFieldType.bool';
      case ProtoScalarType.string_:
        return 'ProtoFieldType.string';
      case ProtoScalarType.bytes:
        return 'ProtoFieldType.bytes';
    }
  }

  /// Resolves a bare (non-repeated, non-map) ProtoType to its
  /// ProtoFieldType, used both for the top-level fieldType of a plain
  /// field and for repeatedType/mapKeyType/mapValueType.
  static String _wireFieldTypeForBare(
    ProtoType type, {
    required ProtoCompiler resolver,
  }) {
    switch (type) {
      case ProtoScalar(type: final st):
        return _wireFieldType(st);
      case ProtoMessageRefrence():
        return resolver.isEnum(type)
            ? 'ProtoFieldType.enumType'
            : 'ProtoFieldType.message';
      case ProtoRepeated():
      case ProtoMap():
        throw OnChainProtoException(
          'repeated/map cannot be nested directly inside repeated/map in proto3',
        );
    }
  }

  static String fieldConfigExpr(
    ProtoField f, {
    required ProtoCompiler resolver,
  }) {
    final tag = f.tag;
    final opts = ProtoOptionRenderer.renderList(
      resolver.builder.filterFieldOptions(f),
    );
    final optsArg = f.options.isEmpty ? '' : ', options: $opts';
    final optionalFlag = f.optional ? ', hasOptionalFlags: true' : '';
    final type = f.type;
    switch (type) {
      case ProtoScalar(type: final st):
        return _scalarFactoryCall(st, tag, optsArg, optionalFlag);
      case ProtoMessageRefrence():
        if (resolver.isEnum(type)) {
          return 'ProtoFieldConfig.enumType($tag$optsArg$optionalFlag)';
        }
        return 'ProtoFieldConfig.message($tag$optsArg$optionalFlag)';
      case ProtoRepeated(inner: final inner):
        final elementType = _wireFieldTypeForBare(inner, resolver: resolver);
        return 'ProtoFieldConfig.repeated(\n'
            '          fieldNumber: $tag,\n'
            '          elementType: $elementType,\n'
            '${f.options.isEmpty ? '' : '          options: $opts,\n'}'
            '        )';
      case ProtoMap(key: final k, value: final v):
        final keyType = _wireFieldTypeForBare(k, resolver: resolver);
        final valueType = _wireFieldTypeForBare(v, resolver: resolver);
        return 'ProtoFieldConfig.map(\n'
            '          fieldNumber: $tag,\n'
            '          keyType: $keyType,\n'
            '          valueType: $valueType,\n'
            '${f.options.isEmpty ? '' : '          options: $opts,\n'}'
            '        )';
    }
  }

  static String _scalarFactoryCall(
    ProtoScalarType st,
    int tag,
    String optsArg,
    String optionlFlags,
  ) {
    switch (st) {
      case ProtoScalarType.double_:
        return 'ProtoFieldConfig.double($tag$optsArg$optionlFlags)';
      case ProtoScalarType.float_:
        return 'ProtoFieldConfig.float($tag$optsArg$optionlFlags)';
      case ProtoScalarType.int32:
        return 'ProtoFieldConfig.int32($tag$optsArg$optionlFlags)';
      case ProtoScalarType.int64:
        return 'ProtoFieldConfig.int64($tag$optsArg$optionlFlags)';
      case ProtoScalarType.uint32:
        return 'ProtoFieldConfig.uint32($tag$optsArg$optionlFlags)';
      case ProtoScalarType.uint64:
        return 'ProtoFieldConfig.uint64($tag$optsArg$optionlFlags)';
      case ProtoScalarType.sint32:
        return 'ProtoFieldConfig.sint32($tag$optsArg$optionlFlags)';
      case ProtoScalarType.sint64:
        return 'ProtoFieldConfig.sint64($tag$optsArg$optionlFlags)';
      case ProtoScalarType.fixed32:
        return 'ProtoFieldConfig.fixed32($tag$optsArg$optionlFlags)';
      case ProtoScalarType.fixed64:
        return 'ProtoFieldConfig.fixed64($tag$optsArg$optionlFlags)';
      case ProtoScalarType.sfixed32:
        return 'ProtoFieldConfig.sFixed32($tag$optsArg$optionlFlags)';
      case ProtoScalarType.sfixed64:
        return 'ProtoFieldConfig.sFixed64($tag$optsArg$optionlFlags)';
      case ProtoScalarType.bool_:
        return 'ProtoFieldConfig.bool($tag$optsArg$optionlFlags)';
      case ProtoScalarType.string_:
        return 'ProtoFieldConfig.string($tag$optsArg$optionlFlags)';
      case ProtoScalarType.bytes:
        return 'ProtoFieldConfig.bytes($tag$optsArg$optionlFlags)';
    }
  }

  static String toJsonValueExpr({
    required ProtoType type,
    required String accessor,
    required bool optional,
    required ProtoCompiler resolver,
    required bool required,
    required StringEncoding? bytesEncoding,
    required List<ProtoOption> options,
    String? toJsonParams,
    bool isElement = false,
  }) {
    // Repeated/map elements are never individually null in proto3 - only
    // the top-level field's own optionality/bare-message-ref rule applies.
    final nullable = isElement
        ? false
        : isNullable(type: type, required: required, optional: optional);
    switch (type) {
      case ProtoScalar(type: final st):
        return _scalarToJsonExpr(
          st: st,
          accessor: accessor,
          nullable: nullable,
          bytesEncoding: bytesEncoding,
        );
      case ProtoMessageRefrence(
        :final isGoogleTimestamp,
        :final isGoogleDuration,
      ):
        if (resolver.isEnum(type)) {
          // Canonical protobuf JSON encodes enums as their original proto
          // identifier string, not the wire int - matches the `from()`
          // lookup added to the generated enum.
          return nullable ? '$accessor?.protoName' : '$accessor.protoName';
        }
        bool isGoogle = isGoogleTimestamp();
        bool isDuration = isGoogleDuration();
        if (isGoogle) {
          return nullable ? '$accessor?.toRfc3339()' : '$accessor.toRfc3339()';
        }
        if (isDuration) {
          final stdDuration = OnChainProtoUtils.hasStdduration(options);
          return nullable
              ? '$accessor?.encodeString(asNanos:$stdDuration)'
              : '$accessor.encodeString(asNanos:$stdDuration)';
        }
        if (toJsonParams != null) {
          return nullable
              ? '$accessor?.toJson($toJsonParams)'
              : '$accessor.toJson($toJsonParams)';
        }
        return nullable ? '$accessor?.toJson()' : '$accessor.toJson()';
      case ProtoRepeated(inner: final inner):
        final innerExpr = toJsonValueExpr(
          type: inner,
          accessor: 'e',
          resolver: resolver,
          bytesEncoding: bytesEncoding,
          required: true,
          toJsonParams: toJsonParams,
          options: options,
          optional: false,
          isElement: true,
        );
        return '$accessor.map((e) => $innerExpr).toList()';
      case ProtoMap(value: final v, :final key):
        if (key is! ProtoScalar) {
          throw OnChainProtoException(
            "toJson only support for premitive and message types.",
          );
        }
        final valueExpr = toJsonValueExpr(
          type: v,
          accessor: 'v',
          resolver: resolver,
          options: options,
          isElement: true,
          bytesEncoding: bytesEncoding,
          required: true,
          optional: false,
          toJsonParams: toJsonParams,
        );
        if (valueExpr == 'v') {
          return accessor;
        }
        return '$accessor.map((k, v) => MapEntry(k, $valueExpr))';
    }
  }

  static String _scalarToJsonExpr({
    required ProtoScalarType st,
    required String accessor,
    required bool nullable,
    required StringEncoding? bytesEncoding,
  }) {
    switch (st) {
      case ProtoScalarType.int64:
      case ProtoScalarType.uint64:
      case ProtoScalarType.sint64:
      case ProtoScalarType.fixed64:
      case ProtoScalarType.sfixed64:
        if (nullable) {
          return '$accessor?.toString()';
        }
        return '$accessor.toString()';
      case ProtoScalarType.bytes:
        if (bytesEncoding == null) return accessor;
        if (nullable) {
          return 'switch ($accessor) {List<int> bytes =>StringUtils.decode(bytes, encoding: StringEncoding.${bytesEncoding.name}),_=>null}';
        }
        return 'StringUtils.decode($accessor, encoding: StringEncoding.${bytesEncoding.name})';
      default:
        return accessor;
    }
  }

  static String fromJsonValueExpr({
    required ProtoField f,
    required Set<ProtoTypeLocation> importRefrences,
    required ProtoCompiler resolver,
    required bool camelCase,
    required StringEncoding? bytesEncoding,
    required bool acceptCamelCase,
    required bool defaultOnMissing,
  }) {
    final key = f.name;
    final effectiveOptional = isNullable(
      type: f.type,
      optional: f.optional,
      required: f.required,
    );
    return _fromJsonForType(
      type: f.type,
      keyOrAccessor: key,
      optional: effectiveOptional,
      resolver: resolver,
      isTopLevelKey: true,
      importRefrences: importRefrences,
      camelCase: camelCase,
      bytesEncoding: bytesEncoding,
      acceptCamelCase: acceptCamelCase,
      defaultOnMissing: defaultOnMissing,
    );
  }

  static String _fromJsonForType({
    required ProtoType type,
    required String keyOrAccessor,
    bool optional = false,
    required ProtoCompiler resolver,
    required bool isTopLevelKey,
    required Set<ProtoTypeLocation> importRefrences,
    required bool camelCase,
    required StringEncoding? bytesEncoding,
    required bool acceptCamelCase,
    required bool defaultOnMissing,
  }) {
    if (camelCase && isTopLevelKey) {
      keyOrAccessor = OnChainProtoUtils.snakeToCamel(
        keyOrAccessor,
        capitalizeFirst: false,
      );
    }
    switch (type) {
      case ProtoScalar(type: final st):
        return isTopLevelKey
            ? _scalarFromJsonTopLevel(
                st,
                keyOrAccessor,
                optional: optional,
                bytesEncoding: bytesEncoding,
                acceptCamelCase: acceptCamelCase,
                defaultOnMissing: defaultOnMissing,
              )
            : _scalarFromJsonRaw(st, keyOrAccessor);

      case ProtoMessageRefrence(
        :final fullTypeName,
        :final isGoogleTimestamp,
        :final isGoogleDuration,
      ):
        String className = OnChainProtoUtils.className(
          fullTypeName(),
          prefix: resolver.classNamePrefix,
        );
        className = importRefrences.qualifyType(className, type);
        if (resolver.isEnum(type)) {
          // Enums round-trip through their original proto identifier
          // string in JSON, so fromJson uses `.from(v)` (accepts the
          // string, the wire int, or the Dart name) rather than
          // `.fromValue(v)` (int-only).
          if (isTopLevelKey) {
            final typeArgs = '$className${optional ? '?' : ''}, Object?';
            final onError = '';
            return "json.valueTo<$typeArgs>(\n"
                "        key: '$keyOrAccessor',$onError\n"
                '        parse: (v) => $className.from(v),\n'
                '      )';
          }
          return 'JsonParser.valueTo<$className, Object>(\n'
              '          value: $keyOrAccessor,\n'
              '          parse: (v) => $className.from(v),\n'
              '        )';
        }
        final bool googleTimestamp = isGoogleTimestamp();
        final bool isDuration = isGoogleDuration();
        String jsonFormat = switch (googleTimestamp || isDuration) {
          false => "Map<String, dynamic>",
          true => "String",
        };
        final constructor = switch (googleTimestamp || isDuration) {
          false => "fromJson(v)",
          true => switch (isDuration) {
            false => "fromRfc3339(v)",
            true => "fromString(v)",
          },
        };
        // message: nested object, parsed via the nested class's fromJson.
        if (isTopLevelKey) {
          final typeArgs = '$className${optional ? '?' : ''}, $jsonFormat';
          final onError = '';
          return "json.valueTo<$typeArgs>(\n"
              "        key: '$keyOrAccessor',$onError\n"
              '        parse: (v) => $className.$constructor,\n'
              '${acceptCamelCase ? "acceptCamelCase: true,\n" : ""}        '
              '      )';
        }
        return 'JsonParser.valueTo<$className, $jsonFormat>(\n'
            '          value: $keyOrAccessor,\n'
            '          parse: (v) => $className.$constructor,\n'
            '        )';

      case ProtoRepeated(inner: final inner):
        final rawList = isTopLevelKey
            ? "json.valueEnsureAsList<dynamic>('$keyOrAccessor'${acceptCamelCase ? ", acceptCamelCase: true" : ""})"
            : keyOrAccessor;
        final elementExpr = _fromJsonForType(
          type: inner,
          keyOrAccessor: 'e',
          resolver: resolver,
          isTopLevelKey: false,
          importRefrences: importRefrences,
          camelCase: camelCase,
          bytesEncoding: bytesEncoding,
          acceptCamelCase: acceptCamelCase,
          defaultOnMissing: defaultOnMissing,
        );
        return '($rawList).map((e) => $elementExpr).toList()';

      case ProtoMap(key: final k, value: final v):
        final rawMap = isTopLevelKey
            ? "json.valueAsMap<Map<dynamic, dynamic>>('$keyOrAccessor'${acceptCamelCase ? ", acceptCamelCase: true" : ""})"
            : keyOrAccessor;
        final keyExpr = _fromJsonForType(
          type: k,
          keyOrAccessor: 'k',
          resolver: resolver,
          isTopLevelKey: false,
          camelCase: camelCase,
          importRefrences: importRefrences,
          bytesEncoding: bytesEncoding,
          acceptCamelCase: acceptCamelCase,
          defaultOnMissing: defaultOnMissing,
        );
        final valueExpr = _fromJsonForType(
          type: v,
          keyOrAccessor: 'v',
          resolver: resolver,
          isTopLevelKey: false,
          camelCase: camelCase,
          importRefrences: importRefrences,
          bytesEncoding: bytesEncoding,
          acceptCamelCase: acceptCamelCase,
          defaultOnMissing: defaultOnMissing,
        );
        return '($rawMap).map((k, v) => MapEntry($keyExpr, $valueExpr))';
    }
  }

  static String _scalarFromJsonTopLevel(
    ProtoScalarType st,
    String key, {
    required bool optional,
    required StringEncoding? bytesEncoding,
    required bool acceptCamelCase,
    required bool defaultOnMissing,
  }) {
    final q = "'$key'";
    final acceptCammelCaseParams = acceptCamelCase
        ? ", acceptCamelCase: true"
        : "";
    final bool allowMissingParam = (!optional && defaultOnMissing);
    switch (st) {
      case ProtoScalarType.double_:
      case ProtoScalarType.float_:
        String onMissing = allowMissingParam ? ", onMissing:() => 0.0" : "";
        return "json.valueAsDouble<double${optional ? '?' : ''}>($q$acceptCammelCaseParams$onMissing)";
      case ProtoScalarType.int32:
      case ProtoScalarType.sint32:
      case ProtoScalarType.sfixed32:
      case ProtoScalarType.uint32:
      case ProtoScalarType.fixed32:
        String onMissing = allowMissingParam ? ", onMissing:() => 0" : "";
        return "json.valueAsInt<int${optional ? '?' : ''}>($q$acceptCammelCaseParams$onMissing)";
      case ProtoScalarType.int64:
      case ProtoScalarType.uint64:
      case ProtoScalarType.sint64:
      case ProtoScalarType.fixed64:
      case ProtoScalarType.sfixed64:
        String onMissing = allowMissingParam
            ? ", onMissing:() => BigInt.zero"
            : "";
        return "json.valueAsBigInt<BigInt${optional ? '?' : ''}>($q$acceptCammelCaseParams$onMissing)";
      case ProtoScalarType.bool_:
        String onMissing = allowMissingParam ? ", onMissing:() => false" : "";
        return "json.valueAsBool<bool${optional ? '?' : ''}>($q$acceptCammelCaseParams$onMissing)";
      case ProtoScalarType.string_:
        String onMissing = allowMissingParam ? ', onMissing:() => ""' : "";
        return "json.valueAsString<String${optional ? '?' : ''}>($q$acceptCammelCaseParams$onMissing)";
      case ProtoScalarType.bytes:
        String onMissing = allowMissingParam ? ", onMissing:() => []" : "";
        String encodingParams = bytesEncoding != null
            ? ",encoding: StringEncoding.${bytesEncoding.name}"
            : '';
        return "json.valueAsBytes<List<int>${optional ? '?' : ''}>($q$acceptCammelCaseParams$encodingParams$onMissing)";
    }
  }

  static String _scalarFromJsonRaw(ProtoScalarType st, String accessor) {
    switch (st) {
      case ProtoScalarType.double_:
      case ProtoScalarType.float_:
        return 'JsonParser.valueAsDouble<double>($accessor)';
      case ProtoScalarType.int32:
      case ProtoScalarType.sint32:
      case ProtoScalarType.sfixed32:
      case ProtoScalarType.uint32:
      case ProtoScalarType.fixed32:
        return 'JsonParser.valueAsInt<int>($accessor)';
      case ProtoScalarType.int64:
      case ProtoScalarType.uint64:
      case ProtoScalarType.sint64:
      case ProtoScalarType.fixed64:
      case ProtoScalarType.sfixed64:
        return 'JsonParser.valueAsBigInt<BigInt>($accessor)';
      case ProtoScalarType.bool_:
        return 'JsonParser.valueAsBool<bool>($accessor)';
      case ProtoScalarType.string_:
        return 'JsonParser.valueAsString<String>($accessor)';
      case ProtoScalarType.bytes:
        return 'JsonParser.valueAsBytes<List<int>>($accessor,encoding:StringEncoding.base64)';
    }
  }

  static String deserializeValueExpr({
    required ProtoField f,
    required ProtoCompiler resolver,
    required Set<ProtoTypeLocation> importRefrences,
  }) {
    final effectiveOptional = isNullable(
      type: f.type,
      optional: f.optional,
      required: f.required,
    );
    return _deserializeForType(
      type: f.type,
      tag: f.tag,
      optional: effectiveOptional,
      resolver: resolver,
      importRefrences: importRefrences,
    );
  }

  static String _deserializeForType({
    required ProtoType type,
    required int tag,
    required bool optional,
    required ProtoCompiler resolver,
    required Set<ProtoTypeLocation> importRefrences,
  }) {
    switch (type) {
      case ProtoScalar(type: final st):
        return _scalarDeserializeExpr(st, tag, optional: optional);

      case ProtoMessageRefrence(:final fullTypeName):
        final className = importRefrences.qualifyType(
          OnChainProtoUtils.className(
            fullTypeName(),
            prefix: resolver.classNamePrefix,
          ),
          type,
        );
        if (resolver.isEnum(type)) {
          // getEnum needs the full list of enum variants to match the
          // wire int against (it doesn't know about your generated enum
          // type on its own).
          final t = optional ? '$className?' : className;
          return 'decode.getEnum<$t>($tag, $className.values)';
        }
        // messageTo hands you the raw sub-message bytes and lets you
        // supply your own converter; it also auto-passes null through
        // when T is nullable, matching bare message fields exactly.
        final t = optional ? '$className?' : className;
        return 'decode.messageTo<$t>($tag, (b) => $className.deserialize(b))';

      case ProtoRepeated(inner: final inner):
        return _deserializeRepeated(
          inner: inner,
          importRefrences: importRefrences,
          tag: tag,
          resolver: resolver,
        );

      case ProtoMap(key: final k, value: final v):
        return _deserializeMap(
          keyType: k,
          valueType: v,
          tag: tag,
          resolver: resolver,
          importRefrences: importRefrences,
        );
    }
  }

  static String _deserializeRepeated({
    required ProtoType inner,
    required int tag,
    required ProtoCompiler resolver,
    required Set<ProtoTypeLocation> importRefrences,
  }) {
    switch (inner) {
      case ProtoScalar(type: ProtoScalarType.bytes):
        // repeated bytes: each element is itself a length-delimited blob,
        // same shape as repeated message - use getListOfBytes directly.
        return 'decode.getListOfBytes($tag)';
      case ProtoScalar(type: final st):
        final dartType = _dartScalarType(st);
        return 'decode.getListOrEmpty<$dartType>($tag)';
      case ProtoMessageRefrence(:final fullTypeName):
        final className = importRefrences.qualifyType(
          OnChainProtoUtils.className(
            fullTypeName(),
            prefix: resolver.classNamePrefix,
          ),
          inner,
        );
        if (resolver.isEnum(inner)) {
          return 'decode.getReapeatedEnum<$className>($tag, $className.values)';
        }
        // ASSUMPTION (see file header): repeated message fields decode as
        // a list of raw sub-message byte-blobs under one field number.
        return 'decode.getListOfBytes($tag).map((b) => $className.deserialize(b)).toList()';
      case ProtoRepeated():
      case ProtoMap():
        throw OnChainProtoException(
          'repeated/map cannot be nested directly inside repeated in proto3',
        );
    }
  }

  static String _deserializeMap({
    required ProtoType keyType,
    required ProtoType valueType,
    required int tag,
    required Set<ProtoTypeLocation> importRefrences,
    required ProtoCompiler resolver,
  }) {
    switch ((keyType, valueType)) {
      case (ProtoScalar(type: final key), ProtoScalar(type: final value)):
        final keyDart = _dartScalarType(key);
        final valueDartType = _dartScalarType(value);
        return 'decode.getMap<$keyDart, $valueDartType>($tag)';
      case (
        ProtoScalar(type: final key),
        ProtoMessageRefrence(:final fullTypeName),
      ):
        final keyDart = _dartScalarType(key);
        final className = importRefrences.qualifyType(
          OnChainProtoUtils.className(
            OnChainProtoUtils.lastSegment(fullTypeName()),
            prefix: resolver.classNamePrefix,
          ),
          valueType,
        );
        return 'decode.getMapField<$keyDart, $className>('
            "        fieldNumber: $tag,\n"
            '        keyMapper: (v) => JsonParser.valueAs<$keyDart>(v),\n'
            '        valueMapper: (v) => $className.deserialize(JsonParser.valueAsBytes<List<int>>(v)))\n';
      case (
        ProtoMessageRefrence(:final fullTypeName),
        ProtoScalar(:final type),
      ):
        final keyDart = _dartScalarType(type);
        final className = importRefrences.qualifyType(
          OnChainProtoUtils.className(
            OnChainProtoUtils.lastSegment(fullTypeName()),
            prefix: resolver.classNamePrefix,
          ),
          keyType,
        );
        return 'decode.getMapField<$className, $keyDart>('
            "        fieldNumber: $tag,\n"
            '        valueMapper: (v) => JsonParser.valueAs<$keyDart>(v),\n'
            '        keyMapper: (v) => $className.deserialize(JsonParser.valueAsBytes<List<int>>(v)))\n';
      case (
        ProtoMessageRefrence(:final fullTypeName),
        ProtoMessageRefrence(fullTypeName: var valueName),
      ):
        final keyClassName = importRefrences.qualifyType(
          OnChainProtoUtils.className(
            OnChainProtoUtils.lastSegment(fullTypeName()),
            prefix: resolver.classNamePrefix,
          ),
          keyType,
        );
        final valueClassName = importRefrences.qualifyType(
          OnChainProtoUtils.className(
            OnChainProtoUtils.lastSegment(valueName()),
            prefix: resolver.classNamePrefix,
          ),
          valueType,
        );
        return 'decode.getMapField<$keyClassName, $valueClassName>('
            "        fieldNumber: $tag,\n"
            '        valueMapper: (v) => $valueClassName.deserialize(JsonParser.valueAsBytes<List<int>>(v)),\n'
            '        keyMapper: (v) => $keyClassName.deserialize(JsonParser.valueAsBytes<List<int>>(v)))\n';
      default:
        assert(false, "unsupported map types");
        return '/* TODO: map with message/enum value at tag $tag is not '
            'auto-generated - getMap only supports scalar values; '
            'fill this in by hand using decode.getListOrNull<MapEntry>($tag) */ '
            'const {}';
    }
  }

  static String _scalarDeserializeExpr(
    ProtoScalarType st,
    int tag, {
    required bool optional,
  }) {
    final opt = optional ? '?' : '';
    switch (st) {
      case ProtoScalarType.double_:
      case ProtoScalarType.float_:
        return 'decode.getDouble<double$opt>($tag)';
      case ProtoScalarType.int32:
      case ProtoScalarType.sint32:
      case ProtoScalarType.sfixed32:
      case ProtoScalarType.uint32:
      case ProtoScalarType.fixed32:
        return 'decode.getInt<int$opt>($tag)';
      case ProtoScalarType.int64:
      case ProtoScalarType.uint64:
      case ProtoScalarType.sint64:
      case ProtoScalarType.fixed64:
      case ProtoScalarType.sfixed64:
        return 'decode.getBigInt<BigInt$opt>($tag)';
      case ProtoScalarType.bool_:
        return 'decode.getBool<bool$opt>($tag)';
      case ProtoScalarType.string_:
        return 'decode.getString<String$opt>($tag)';
      case ProtoScalarType.bytes:
        return 'decode.getBytes<List<int>$opt>($tag)';
    }
  }
}
