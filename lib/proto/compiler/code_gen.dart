import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:onchain_proto/proto/compiler/dart_converter.dart';
import 'package:onchain_proto/proto/compiler/compiler.dart';
import 'package:onchain_proto/proto/compiler/type_mapper.dart';
import 'package:onchain_proto/proto/types/types.dart';
import 'package:onchain_proto/proto/utils/utils.dart';

abstract class ProtoCodegenTarget {
  void init(ProtoCompiler resolver);

  /// The Dart class every generated message class `extends` (e.g.
  /// `IProtoMessage`, `CosmosProtoMessage`, `ZcashProtoMessage`).
  String get messageBaseClassName;

  /// Import directives every generated file for this target should carry,
  /// regardless of what any single message needs.
  List<String> defaultImports(ProtoFile file);

  /// Filters which proto options end up rendered into a message's
  /// `protoConfigStatic()` (e.g. to drop target-internal annotations like
  /// `gogoproto.*` that have no meaning once compiled to Dart).
  List<ProtoOption> filterMessageOptions(
    ProtoMessage message,
    List<ServiceMessageOption> services,
  );

  /// Same as [filterMessageOptions], but for a single field's options.
  List<ProtoOption> filterFieldOptions(ProtoField field);

  /// Generates the `toJson()` method body, or `null` to omit it entirely.
  String? buildToJson(
    ProtoMessage message,
    ProtoCompiler resolver, {
    String configGetter,
    bool allowNullValue = true,
  });

  /// Extra `with` mixin type expressions to add to a generated message
  /// class, e.g. query/tx-service marker mixins keyed off [message]'s
  /// attached [ProtoMessage.services].
  List<String> mixinsFor(
    ProtoMessage message,
    ProtoCompiler resolver,
    Set<ProtoTypeLocation> importRefrences,
  );

  /// Any additional members to append to the end of a generated message
  /// class body beyond fields/constructor/config/json/deserialize (e.g. a
  /// `declarationId` getter, or `onQueryResponse`/`onServiceResponse`
  /// overrides for service-backed messages). Return `null` for none.
  String? buildExtraMembers(
    ProtoMessage message,
    ProtoCompiler resolver,
    Set<ProtoTypeLocation> importRefrences,
  );

  /// Narrows a file's declared services down to the ones this target
  /// actually cares about generating support for.
  List<ProtoService> filterServices(List<ProtoService> services);

  /// Generates the `fromJson(...)` factory body, or `null` to omit it.
  String? buildFromJson(
    ProtoMessage message,
    ProtoCompiler resolver,
    String className,
    Set<ProtoTypeLocation> importRefrences, {
    bool camelCase = false,
    bool defaultOnMissing = true,
    String configGetter =
        "ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig",
  });

  /// Generates the `deserialize(List<int> bytes)` factory body, or `null`
  /// to omit it (e.g. for service-only messages that have no wire form
  /// of their own).
  String? buildDeserialize(
    ProtoMessage message,
    ProtoCompiler resolver,
    String className,
    Set<ProtoTypeLocation> importRefrences, {
    bool camelCase = false,
  });

  /// Computes the transitive closure of proto declarations (messages
  /// and/or enums) that must be emitted in "references-only" output mode,
  /// starting from whatever a target considers "always relevant" (e.g.
  /// messages with attached services, or messages in a target's own
  /// always-included packages), and following every field/service type
  /// reference outward from there. Returns `null` for targets that don't
  /// support references-only mode (e.g. [DefaultProtoCodegenTarget]).
  ({
    List<ProtoMessageRefrence> references,
    List<ProtoDeclaration> declarations,
  })?
  computeReferenceClosure(Map<String, GeneratedProtoPackage> generatedPackages);

  /// Rewrites each package's files so that an RPC request message carries
  /// a [ServiceMessageOption] pointing at its response type, letting the
  /// generator later emit response-handling members for it.
  List<ProtoFile> attachServiceMetadata(Map<String, List<ProtoFile>> packages);

  /// Generates the `protoConfig()`/`protoConfigStatic()` and `protoValues`
  /// members that describe a message's wire layout to the runtime codec.
  String buildConfigMembers(
    ProtoMessage message,
    ProtoCompiler resolver,
    ProtoSyntax syntax,
    Set<ProtoTypeLocation> importRefrences,
  );

  List<ProtoMessageRefrence> refrenceMessages(
    ProtoCompiler resolver,
    ProtoFile file,
  );

  String? buildEnumFunctions(
    ProtoCompiler resolver,
    String className,
    ProtoEnum enum_,
    ProtoSyntax syntax,
  );
  String buildMessageBodyAndConstructor({
    required ProtoMessage message,
    required ProtoCompiler resolver,
    required Set<ProtoTypeLocation> importRefrences,
    StringBuffer? buf,
  });
}

class DefaultProtoCodegenTarget implements ProtoCodegenTarget {
  const DefaultProtoCodegenTarget();
  @override
  void init(ProtoCompiler resolver) {}

  @override
  List<ProtoOption> filterFieldOptions(ProtoField field) {
    return field.options;
  }

  @override
  List<ProtoOption> filterMessageOptions(
    ProtoMessage message,
    List<ServiceMessageOption> services,
  ) {
    return [...message.options, ...services.expand((e) => e.rpc.options)];
  }

  @override
  String? buildToJson(
    ProtoMessage message,
    ProtoCompiler resolver, {
    bool camelCase = false,
    bool allowNullValue = true,
    String configGetter =
        "ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig",
  }) {
    final buf = StringBuffer();
    buf.writeln('  @override');
    buf.writeln('  Map<String, dynamic> toJson({$configGetter}) {');
    buf.writeln('    return {');
    for (final f in message.fields) {
      final dartFieldName = OnChainProtoUtils.fieldName(f.name);
      buf.writeln(
        "      '${camelCase ? OnChainProtoUtils.snakeToCamel(f.name, capitalizeFirst: false) : f.name}': ${ProtoRuntimeTypeMapper.toJsonValueExpr(type: f.type, accessor: dartFieldName, optional: f.optional, resolver: resolver, required: f.required, options: f.options)},",
      );
    }

    buf.writeln(
      '    }${(allowNullValue || message.fields.isEmpty) ? '' : '.notNullValue'};',
    );
    buf.writeln('  }');
    buf.writeln();
    return buf.toString();
  }

  @override
  List<String> defaultImports(ProtoFile file) {
    return ['package:blockchain_utils/blockchain_utils.dart'];
  }

  @override
  List<String> mixinsFor(
    ProtoMessage message,
    ProtoCompiler resolver,
    Set<ProtoTypeLocation> importRefrences,
  ) {
    return [];
  }

  @override
  String buildMessageBodyAndConstructor({
    required ProtoMessage message,
    required ProtoCompiler resolver,
    required Set<ProtoTypeLocation> importRefrences,
    StringBuffer? buf,
    Map<ProtoField, String?> extraFields = const {},
  }) {
    final fields = [...extraFields.keys, ...message.fields];
    final dartName = OnChainProtoUtils.className(
      message.fullTypeName(),
      prefix: resolver.classNamePrefix,
    );
    buf ??= StringBuffer();

    for (final f in fields) {
      String dartType = ProtoRuntimeTypeMapper.dartFieldType(
        type: f.type,
        optional: f.optional,
        resolver: resolver,
        importRefrences: importRefrences,
        required: f.required,
        withClassPrefix: !extraFields.containsKey(f),
      );
      // dartType = importRefrences.maybeRefrence(dartType, f.type);
      final dartFieldName = OnChainProtoUtils.fieldName(f.name);
      if (f.comments.isNotEmpty) {
        final c = OnChainProtoUtils.comment(f.comments, indent: '  ');
        if (c != null) buf.writeln('  $c');
      }
      buf.writeln('  final $dartType $dartFieldName;');
      buf.writeln();
    }
    // ---- constructor ----
    // Bytes fields are stored as `BuBytes` but accept `List<int>` parameters
    // mapped via `.asImmutableBytes`, so call sites are unaffected. The
    // conversion is not const, hence any message with a bytes field gets a
    // non-const constructor.
    final hasBytesField = fields.any(
      (f) => ProtoRuntimeTypeMapper.isBytesType(f.type),
    );
    if (fields.isEmpty && extraFields.isEmpty) {
      buf.writeln('  const $dartName();');
    } else if (!hasBytesField) {
      buf.writeln('  const $dartName({');
      // for (final i in extraFields.entries) {
      //   final dartFieldName = OnChainProtoUtils.fieldName(i.key);
      //   final v = i.value;
      //   if (v == null) {
      //     buf.writeln('    this.$dartFieldName,');
      //   } else {
      //     buf.writeln('     this.$dartFieldName = $v,');
      //   }
      // }
      for (final f in fields) {
        final dartFieldName = OnChainProtoUtils.fieldName(f.name);
        final isNullable = ProtoRuntimeTypeMapper.isNullable(
          type: f.type,
          optional: f.optional,
          required: f.required,
          // f.required
        );
        final defaultExpr = ProtoRuntimeTypeMapper.defaultValueExpr(
          type: f.type,
          optional: f.optional,
          resolver: resolver,
          required: f.required,
        );
        if (extraFields.hasValue(f)) {
          buf.writeln('     this.$dartFieldName = ${extraFields[f]},');
        } else if (isNullable) {
          buf.writeln('    this.$dartFieldName,');
        } else if (defaultExpr != null) {
          buf.writeln('    this.$dartFieldName = $defaultExpr,');
        } else {
          buf.writeln('    required this.$dartFieldName,');
        }
      }
      buf.writeln('  });');
    } else {
      // Messages with bytes fields: params stay `List<int>`-shaped, stored
      // fields are `BuBytes` mapped via `.asImmutableBytes`. Non-const.
      final inits = <String>[];
      buf.writeln('  $dartName({');
      for (final f in fields) {
        final dartFieldName = OnChainProtoUtils.fieldName(f.name);
        final isNullable = ProtoRuntimeTypeMapper.isNullable(
          type: f.type,
          optional: f.optional,
          required: f.required,
        );
        final defaultExpr = ProtoRuntimeTypeMapper.defaultValueExpr(
          type: f.type,
          optional: f.optional,
          resolver: resolver,
          required: f.required,
        );
        final isBytes = ProtoRuntimeTypeMapper.isBytesType(f.type);
        if (extraFields.hasValue(f) && !isBytes) {
          buf.writeln('     this.$dartFieldName = ${extraFields[f]},');
          continue;
        }
        if (!isBytes) {
          if (extraFields.hasValue(f)) {
            buf.writeln('     this.$dartFieldName = ${extraFields[f]},');
          } else if (isNullable) {
            buf.writeln('    this.$dartFieldName,');
          } else if (defaultExpr != null) {
            buf.writeln('    this.$dartFieldName = $defaultExpr,');
          } else {
            buf.writeln('    required this.$dartFieldName,');
          }
          continue;
        }
        final paramType = ProtoRuntimeTypeMapper.ctorParamType(
          type: f.type,
          optional: f.optional,
          required: f.required,
          resolver: resolver,
          importRefrences: importRefrences,
        );
        // Strip a `?` for the `required` non-nullable-bytes form; the
        // initializer converts to the non-nullable `BuBytes` field.
        final paramBase = paramType.endsWith('?')
            ? paramType.substring(0, paramType.length - 1)
            : paramType;
        if (isNullable) {
          buf.writeln('    $paramType $dartFieldName,');
          // Nullable bytes are always a singular scalar (repeated/map are
          // never nullable), so a null-aware call is exact.
          inits.add('    $dartFieldName = $dartFieldName?.asImmutableBytes,');
        } else if (defaultExpr != null) {
          buf.writeln('    $paramBase $dartFieldName = $defaultExpr,');
          inits.add(
            '    $dartFieldName = ${ProtoRuntimeTypeMapper.bytesInitExpr(f.type, dartFieldName)},',
          );
        } else {
          buf.writeln('    required $paramBase $dartFieldName,');
          inits.add(
            '    $dartFieldName = ${ProtoRuntimeTypeMapper.bytesInitExpr(f.type, dartFieldName)},',
          );
        }
      }
      if (inits.isEmpty) {
        buf.writeln('  });');
      } else {
        buf.writeln('  }) : ');
        for (var i = 0; i < inits.length; i++) {
          final last = i == inits.length - 1;
          var line = inits[i].trim();
          if (line.endsWith(',')) line = line.substring(0, line.length - 1);
          buf.writeln('    $line${last ? ';' : ','}');
        }
      }
    }
    return buf.toString();
  }

  @override
  String? buildExtraMembers(
    ProtoMessage message,
    ProtoCompiler resolver,
    Set<ProtoTypeLocation> importRefrences,
  ) => null;

  @override
  String? buildFromJson(
    ProtoMessage message,
    ProtoCompiler resolver,
    String className,
    Set<ProtoTypeLocation> importRefrences, {
    bool camelCase = false,
    bool defaultOnMissing = true,
    StringBuffer? buf,
    String configGetter =
        "ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig",
  }) {
    buf ??= StringBuffer();

    buf.writeln(
      '  factory $className.fromJson(Map<String, dynamic> json, {$configGetter}) {',
    );
    buf.writeln('    return $className(');
    for (final f in message.fields) {
      final dartFieldName = OnChainProtoUtils.fieldName(f.name);
      final fieldData = ProtoRuntimeTypeMapper.fromJsonValueExpr(
        f: f,
        resolver: resolver,
        importRefrences: importRefrences,
        camelCase: camelCase,
        defaultOnMissing: defaultOnMissing,
      );
      buf.writeln('      $dartFieldName: $fieldData,');
    }
    buf.writeln('    );');
    buf.writeln('  }');
    return buf.toString();
  }

  @override
  List<ProtoService> filterServices(List<ProtoService> services) {
    return services;
  }

  @override
  String get messageBaseClassName => "IProtoMessage";

  @override
  ({
    List<ProtoDeclaration> declarations,
    List<ProtoMessageRefrence> references,
  })?
  computeReferenceClosure(
    Map<String, GeneratedProtoPackage> generatedPackages,
  ) {
    return null;
  }

  @override
  List<ProtoFile> attachServiceMetadata(Map<String, List<ProtoFile>> packages) {
    final resolved = packages.clone();

    void replace(ProtoFile oldFile, ProtoFile newFile) {
      final files = resolved[oldFile.package]!;
      final index = files.indexWhere((e) => identical(e, oldFile));
      files[index] = newFile;
    }

    for (final package in packages.values) {
      for (final proto in package) {
        final services = filterServices(proto.services);
        for (final service in services) {
          for (final rpc in service.rpcs) {
            assert(
              resolved.containsKey(rpc.request.package),
              "unknwon package ${rpc.request.package}",
            );
            final sourceFile = resolved[rpc.request.package]!
                .firstWhereNullable((file) {
                  return file.messages.any((m) => m.isEqualTo(rpc.request));
                });
            if (sourceFile == null) {
              continue;
            }
            final option = ServiceMessageOption(
              rpc: rpc,
              type: rpc.response,
              serviceName: service.name,
            );

            replace(
              sourceFile,
              sourceFile.copyWith(
                messages: sourceFile.messages.map((message) {
                  if (!message.isEqualTo(rpc.request)) {
                    return message;
                  }
                  return message.copyWith(
                    services: [...message.services, option],
                  );
                }).toList(),
              ),
            );
          }
        }
      }
    }

    return resolved.values.expand((e) => e).toList();
  }

  @override
  String buildConfigMembers(
    ProtoMessage message,
    ProtoCompiler resolver,
    ProtoSyntax syntax,
    Set<ProtoTypeLocation> importRefrences,
  ) {
    final buf = StringBuffer();
    List<ProtoOption> messageOptions = filterMessageOptions(
      message,
      message.services,
    );
    buf.writeln('  @override');
    buf.writeln('  ProtoMessageConfig protoConfig() => protoConfigStatic();');
    buf.writeln();
    buf.writeln('  static ProtoMessageConfig protoConfigStatic() {');
    buf.writeln('    return ProtoMessageConfig(');
    buf.writeln('      syntax: ProtoSyntax.${syntax.name},');
    buf.writeln(
      '      options: ${ProtoOptionRenderer.renderList(messageOptions)},',
    );
    buf.writeln('      fields: [');
    for (final f in message.fields) {
      buf.writeln(
        '        ${ProtoRuntimeTypeMapper.fieldConfigExpr(f, resolver: resolver)},',
      );
    }
    buf.writeln('      ],');
    buf.writeln('    );');
    buf.writeln('  }');
    buf.writeln();

    buf.writeln('  @override');
    buf.writeln('  List<Object?> get protoValues => [');
    for (final f in message.fields) {
      buf.writeln('        ${OnChainProtoUtils.fieldName(f.name)},');
    }
    buf.writeln('      ];');
    buf.writeln();
    return buf.toString();
  }

  @override
  String? buildDeserialize(
    ProtoMessage message,
    ProtoCompiler resolver,
    String className,
    Set<ProtoTypeLocation> importRefrences, {
    bool camelCase = false,
  }) {
    final buf = StringBuffer();
    buf.writeln('  factory $className.deserialize(List<int> bytes) {');
    if (message.fields.isNotEmpty) {
      buf.writeln(
        '    final decode = ${resolver.builder.messageBaseClassName}.decode(bytes, protoConfigStatic());',
      );
    }

    buf.writeln('    return $className(');
    for (final f in message.fields) {
      final dartFieldName = OnChainProtoUtils.fieldName(f.name);
      buf.writeln(
        '      $dartFieldName: ${ProtoRuntimeTypeMapper.deserializeValueExpr(f: f, importRefrences: importRefrences, resolver: resolver)},',
      );
    }
    buf.writeln('    );');
    buf.writeln('  }');
    return buf.toString();
  }

  @override
  List<ProtoMessageRefrence> refrenceMessages(
    ProtoCompiler resolver,
    ProtoFile file,
  ) {
    return [];
  }

  @override
  String? buildEnumFunctions(
    ProtoCompiler resolver,
    String className,
    ProtoEnum enum_,
    ProtoSyntax syntax,
  ) {
    final buf = StringBuffer();
    buf.writeln('  /// The original proto wire value for this enum constant.');
    buf.writeln('  @override');
    buf.writeln('  final int value;');
    buf.writeln();
    buf.writeln(
      '  /// The original proto identifier, e.g. "VOTE_OPTION_UNSPECIFIED".',
    );
    buf.writeln('  @override');
    buf.writeln('  final String protoName;');
    buf.writeln();
    buf.writeln(
      '  /// Looks up a value by its proto wire int. Throws if not found.',
    );
    buf.writeln('  static $className fromValue(int? value) {');
    if (syntax.isV3) buf.writeln('    value ??=0;');
    buf.writeln('    return $className.values.firstWhere(');
    buf.writeln('      (e) => e.value == value,');
    buf.writeln(
      '      orElse: () => throw ItemNotFoundException(name:"$className", value: value)',
    );
    buf.writeln('    );');
    buf.writeln('  }');
    buf.writeln();
    buf.writeln(
      '  /// Looks up a value by wire int, Dart enum name, or original proto',
    );
    buf.writeln(
      '  /// name (whichever [value] happens to be). Throws if not found.',
    );
    buf.writeln('  static $className from(Object? value) {');
    if (syntax.isV3) buf.writeln('    value ??=0;');
    buf.writeln('    return $className.values.firstWhere(');
    buf.writeln(
      '      (e) => e.value == value || e.name == value || e.protoName == value,',
    );
    buf.writeln(
      '      orElse: () => throw ItemNotFoundException(name:"$className", value: value)',
    );
    buf.writeln('    );');
    buf.writeln('  }');
    return buf.toString();
  }
}
