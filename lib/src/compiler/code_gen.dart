import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:onchain_proto/src/compiler/dart_converter.dart';
import 'package:onchain_proto/src/compiler/compiler.dart';
import 'package:onchain_proto/src/compiler/type_mapper.dart';
import 'package:onchain_proto/src/types/types.dart';
import 'package:onchain_proto/src/utils/utils.dart';

abstract class ProtoCodegenTarget {
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
    StringEncoding? bytesEncoding,
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

    StringEncoding? bytesEncoding,
    bool camelCase = false,
  });

  /// Generates the `deserialize(List<int> bytes)` factory body, or `null`
  /// to omit it (e.g. for service-only messages that have no wire form
  /// of their own).
  String? buildDeserialize(
    ProtoMessage message,
    ProtoCompiler resolver,
    String className,
    Set<ProtoTypeLocation> importRefrences, {
    StringEncoding? bytesEncoding,
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
  );
}

class DefaultProtoCodegenTarget implements ProtoCodegenTarget {
  const DefaultProtoCodegenTarget();

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
    StringEncoding? bytesEncoding,
    bool camelCase = false,
  }) {
    final buf = StringBuffer();
    buf.writeln('  @override');
    buf.writeln('  Map<String, dynamic> toJson() {');
    buf.writeln('    return {');
    for (final f in message.fields) {
      final dartFieldName = OnChainProtoUtils.fieldName(f.name);
      buf.writeln(
        "      '${camelCase ? OnChainProtoUtils.snakeToCamel(f.name, capitalizeFirst: false) : f.name}': ${ProtoRuntimeTypeMapper.toJsonValueExpr(type: f.type, accessor: dartFieldName, optional: f.optional, resolver: resolver, required: f.required, bytesEncoding: bytesEncoding, options: f.options)},",
      );
    }
    buf.writeln('    };');
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

    StringEncoding? bytesEncoding,
    bool camelCase = false,
    StringBuffer? buf,
  }) {
    buf ??= StringBuffer();

    buf.writeln('  factory $className.fromJson(Map<String, dynamic> json) {');
    buf.writeln('    return $className(');
    for (final f in message.fields) {
      final dartFieldName = OnChainProtoUtils.fieldName(f.name);
      final fieldData = ProtoRuntimeTypeMapper.fromJsonValueExpr(
        f: f,
        resolver: resolver,
        importRefrences: importRefrences,
        camelCase: camelCase,
        bytesEncoding: bytesEncoding,
        acceptCamelCase: true,
        defaultOnMissing: true,
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
                  assert(message.services.isEmpty, "hash service!");
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
    StringEncoding? bytesEncoding,
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
}

class CosmosProtoCodegenTarget extends DefaultProtoCodegenTarget {
  @override
  String get messageBaseClassName => "CosmosProtoMessage";
  static const List<String> alwaysIncludedPackagePrefixes = [
    "injective.crypto",
    "cosmos.evm.crypto",
    "cosmos.crypto",
    "cosmos.tx",
    "ethermint.crypto",
    "injective.crypto.v1beta1.ethsecp256k1",
    "stratos.crypto.v1.ethsecp256k1",
    "initia.crypto.v1beta1.ethsecp256k1",
  ];
  static const List<String> suppressedOptionPrefixes = [
    "gogoproto",
    "cosmos_proto.scalar",
    "cosmos_proto.method_added_in",
    "cosmos_proto.implements_interface",
    "cosmos_proto.accepts_interface",
    "cosmos_proto.accepts_interface",
    "cosmos_proto.message_added_in",
  ];

  static const List<String> knownQueryServices = [
    "Query",
    "ABCIListenerService",
    "Service",
    "ReflectionService",
    "QueryService",
  ];
  static const List<String> knownTxServices = [
    "Msg",
    "ABCI",
    "MsgCreator",
    "SQSIngester",
    "Stream",
    "LocalhostBifrost",
  ];

  static const queryMixinName = "ICosmosProtoQueryMessage";
  static const serviceMixinName = "ICosmosProtoServiceMessage";
  static const aminoMixinName = "ICosmosProtoAminoMessage";
  static const aminoOptionKey = "amino.name";

  const CosmosProtoCodegenTarget();

  @override
  List<ProtoOption> filterFieldOptions(ProtoField field) {
    return field.options
        .where(
          (e) => !(suppressedOptionPrefixes.any((f) => e.name.startsWith(f))),
        )
        .toList();
  }

  @override
  List<ProtoOption> filterMessageOptions(
    ProtoMessage message,
    List<ServiceMessageOption> services,
  ) {
    final List<ProtoOption> options = [
      ...message.options,
      ...services.expand((e) => e.rpc.options),
    ];
    return options
        .where(
          (e) => !(suppressedOptionPrefixes.any((f) => e.name.startsWith(f))),
        )
        .toList();
  }

  @override
  List<String> defaultImports(ProtoFile file) {
    return [
      ...super.defaultImports(file),
      "package:cosmos_sdk/proto_messages/types.dart",
      "package:cosmos_sdk/sdk/serialization/serialization.dart",
    ];
  }

  @override
  List<String> mixinsFor(
    ProtoMessage message,
    ProtoCompiler resolver,
    Set<ProtoTypeLocation> importRefrences,
  ) {
    if (message.services.isEmpty) return [];
    List<String> mixins = [];
    bool hasQuery = false;
    bool hasTx = false;
    for (final i in message.services) {
      if (!hasQuery && knownQueryServices.contains(i.serviceName)) {
        mixins.add(
          '$queryMixinName<${ProtoRuntimeTypeMapper.bareDartType(type: i.type, importRefrences: importRefrences, resolver: resolver)}>',
        );
        hasQuery = true;
        continue;
      }
      if (!hasTx && knownTxServices.contains(i.serviceName)) {
        mixins.add(
          '$serviceMixinName<${ProtoRuntimeTypeMapper.bareDartType(type: i.type, importRefrences: importRefrences, resolver: resolver)}>',
        );
        hasTx = true;
      }
    }
    if (message.hasOption(aminoOptionKey)) {
      mixins.add(aminoMixinName);
    }

    return mixins;
  }

  @override
  String buildExtraMembers(
    ProtoMessage message,
    ProtoCompiler resolver,
    Set<ProtoTypeLocation> importRefrences,
  ) {
    // Deliberately built from the proto package + declaration name only
    // (never OnChainProtoUtils.className / classNamePrefix), so this stays a
    // stable cross-run identifier even when classNamePrefix changes what
    // the generated Dart class itself is called.
    final name = OnChainProtoUtils.snakeToCamel(
      "${message.package}.${message.fullName()}".replaceAll(".", "_"),
      capitalizeFirst: false,
    );
    final buf = StringBuffer();
    buf.writeln('  @override');
    buf.writeln(
      'DefaultCosmosProtoTypeUrl get declarationId => DefaultCosmosProtoTypeUrl.$name;',
    );

    final queryService = message.services.firstWhereNullable(
      (e) => knownQueryServices.contains(e.serviceName),
    );
    if (queryService != null) {
      final query = queryService.type;
      buf.writeln('  @override');
      buf.writeln(
        '  ${ProtoRuntimeTypeMapper.bareDartType(type: query, importRefrences: importRefrences, resolver: resolver)} onQueryResponse(List<int> bytes) {',
      );
      buf.writeln(
        "    return ${ProtoRuntimeTypeMapper.bareDartType(type: query, importRefrences: importRefrences, resolver: resolver)}.deserialize(bytes);",
      );
      buf.writeln('  }');
      buf.writeln('  @override');
      buf.writeln(
        '  ${ProtoRuntimeTypeMapper.bareDartType(type: query, importRefrences: importRefrences, resolver: resolver)} onQueryResponseJson(Map<String, dynamic> json) {',
      );
      buf.writeln(
        "     return ${ProtoRuntimeTypeMapper.bareDartType(type: query, importRefrences: importRefrences, resolver: resolver)}.fromJson(json);",
      );
      buf.writeln('  }');
    }
    final txService = message.services.firstWhereNullable(
      (e) => knownTxServices.contains(e.serviceName),
    );
    if (txService != null) {
      final request = txService.type;
      buf.writeln('  @override');
      buf.writeln(
        '  ${ProtoRuntimeTypeMapper.bareDartType(type: request, importRefrences: importRefrences, resolver: resolver)} onServiceResponse(List<int> bytes) {',
      );
      buf.writeln(
        "     return ${ProtoRuntimeTypeMapper.bareDartType(type: request, importRefrences: importRefrences, resolver: resolver)}.deserialize(bytes);",
      );
      buf.writeln('  }');
      buf.writeln('  @override');
      buf.writeln(
        '  ${ProtoRuntimeTypeMapper.bareDartType(type: request, importRefrences: importRefrences, resolver: resolver)} onServiceResponseJson(Map<String, dynamic> json) {',
      );
      buf.writeln(
        "      return ${ProtoRuntimeTypeMapper.bareDartType(type: request, importRefrences: importRefrences, resolver: resolver)}.fromJson(json);",
      );
      buf.writeln('  }');
    }

    return buf.toString();
  }

  @override
  List<ProtoService> filterServices(List<ProtoService> services) {
    return services
        .where(
          (e) =>
              knownQueryServices.contains(e.name) ||
              knownTxServices.contains(e.name),
        )
        .toList();
  }

  @override
  String? buildToJson(
    ProtoMessage message,
    ProtoCompiler resolver, {
    StringEncoding? bytesEncoding,
    bool camelCase = false,
  }) {
    return super.buildToJson(
      message,
      resolver,
      bytesEncoding: bytesEncoding ?? StringEncoding.base64,
      camelCase: camelCase,
    );
  }

  @override
  String? buildFromJson(
    ProtoMessage message,
    ProtoCompiler resolver,
    String className,
    Set<ProtoTypeLocation> importRefrences, {
    StringEncoding? bytesEncoding,
    bool camelCase = false,
    StringBuffer? buf,
  }) {
    // StringBuffer? buf;
    if (OnChainProtoUtils.isGoogleTimestamp(message.package, message.name)) {
      buf ??= StringBuffer();
      buf.writeln('  factory $className.fromRfc3339(String timestamp) {');
      buf.writeln(
        '    final data = ProtoUtils.timestampFromRfc3339(timestamp);',
      );
      buf.writeln(
        '    return $className(seconds: BigInt.from(data.seconds), nanos: data.nanos);',
      );
      buf.writeln('  }');
      buf.writeln();
      buf.writeln('  String toRfc3339()');
      buf.writeln('  {');
      buf.writeln(
        '  return ProtoUtils.timestampToRfc3339(seconds?.toIntOrThrow??0  ,nanos??0);',
      );
      buf.writeln('  }');
    }
    if (OnChainProtoUtils.isGoogleDuration(message.package, message.name)) {
      buf ??= StringBuffer();
      buf.writeln('  factory $className.fromString(String duration) {');
      buf.writeln(
        '    final data = ProtoUtils.googleDurationFromJson(duration);',
      );
      buf.writeln(
        '    return $className(seconds: data.seconds, nanos: data.nanos);',
      );
      buf.writeln('  }');
      buf.writeln();
      buf.writeln('  String encodeString({bool asNanos = true})');
      buf.writeln('  {');
      buf.writeln(
        '  return ProtoUtils.googleDurationToJson(seconds??BigInt.zero  ,nanos??0, asNanos:asNanos);',
      );
      buf.writeln('  }');
    }

    return super.buildFromJson(
      message,
      resolver,
      className,
      importRefrences,
      bytesEncoding: bytesEncoding ?? StringEncoding.base64,
      camelCase: camelCase,
      buf: buf,
    );
  }

  @override
  ({
    List<ProtoMessageRefrence> references,
    List<ProtoDeclaration> declarations,
  })?
  computeReferenceClosure(
    Map<String, GeneratedProtoPackage> generatedPackages,
  ) {
    List<ProtoMessageRefrence> references = [];
    List<ProtoDeclaration> declarations = [];
    List<ProtoMessageRefrence> collectTransitiveReferences(
      ProtoMessageRefrence reference,
    ) {
      final package = generatedPackages[reference.package]!;
      List<ProtoMessageRefrence> nestedReferences = [];
      ProtoDeclaration? declaration;
      for (final i in package.files) {
        declaration ??= i.file.messages.firstWhereNullable(
          (e) => e.isEqualTo(reference),
        );
        declaration ??= i.file.enums.firstWhereNullable(
          (e) => e.isEqualTo(reference),
        );
        if (declaration != null) break;
      }
      if (declarations.contains(declaration)) return [];
      assert(declaration != null);
      if (declaration == null) return nestedReferences;
      declarations.add(declaration);
      final r = declaration.refTypes();
      for (final i in r) {
        nestedReferences.addAll(collectTransitiveReferences(i));
      }
      return nestedReferences;
    }

    // Seed the closure: messages that already carry a service (RPC
    // request/response types are always relevant) plus everything in a
    // target's always-included packages (e.g. crypto key types that get
    // referenced only via `Any`, so no ordinary field reference would
    // otherwise pull them in).
    List<ProtoMessageRefrence> seedReferences = [];
    for (final i in generatedPackages.values) {
      for (final f in i.files) {
        final bool alwaysIncluded = alwaysIncludedPackagePrefixes.any(
          (e) => f.file.package.startsWith(e),
        );
        for (final m in f.file.messages) {
          if (m.services.isNotEmpty || alwaysIncluded) {
            seedReferences.addAll(m.refTypes());
            declarations.add(m);
          }
        }
      }
    }

    references = List.from(seedReferences, growable: true);
    for (final i in seedReferences) {
      references.addAll(collectTransitiveReferences(i));
    }
    return (references: references, declarations: declarations);
  }
}

class ZcashProtoCodegenTarget extends DefaultProtoCodegenTarget {
  @override
  String get messageBaseClassName => "ZcashProtoMessage";
  static const queryMixinName = "IZcashProtoQueryMessage";
  static const List<String> knownQueryServices = ["CompactTxStreamer"];
  final List<String> imports;
  const ZcashProtoCodegenTarget({
    this.imports = const [
      "package:zcash_dart/src/provider/walletd/proto_messages/types.dart",
      "package:zcash_dart/src/serialization/protobuf/protobuf.dart",
    ],
  });

  @override
  List<ProtoOption> filterFieldOptions(ProtoField field) {
    return field.options;
  }

  @override
  List<ProtoOption> filterMessageOptions(
    ProtoMessage message,
    List<ServiceMessageOption> services,
  ) {
    return message.options;
  }

  @override
  List<String> defaultImports(ProtoFile file) {
    return [...super.defaultImports(file), ...imports];
  }

  @override
  List<String> mixinsFor(
    ProtoMessage message,
    ProtoCompiler resolver,
    Set<ProtoTypeLocation> importRefrences,
  ) {
    if (message.services.isEmpty) return [];
    List<String> mixins = [];
    for (final i in message.services) {
      if (knownQueryServices.contains(i.serviceName)) {
        mixins.add(
          '$queryMixinName<${ProtoRuntimeTypeMapper.bareDartType(type: i.type, importRefrences: importRefrences, resolver: resolver)}>',
        );
        break;
      }
    }
    return mixins;
  }

  @override
  String buildExtraMembers(
    ProtoMessage message,
    ProtoCompiler resolver,
    Set<ProtoTypeLocation> importRefrences,
  ) {
    // Same rationale as CosmosProtoCodegenTarget.buildExtraMembers: keep
    // this tied to proto-space names, not the (possibly prefixed) Dart
    // class name.
    final name = OnChainProtoUtils.snakeToCamel(
      "${message.package}.${message.fullName()}".replaceAll(".", "_"),
      capitalizeFirst: false,
    );
    final buf = StringBuffer();
    buf.writeln('  @override');
    buf.writeln(
      'DefaultZcashProtoTypeUrl get declarationId => DefaultZcashProtoTypeUrl.$name;',
    );

    final queryService = message.services.firstWhereNullable(
      (e) => knownQueryServices.contains(e.serviceName),
    );
    if (queryService != null) {
      final query = queryService.type;
      buf.writeln('  @override');
      buf.writeln(
        '  ${ProtoRuntimeTypeMapper.bareDartType(type: query, importRefrences: importRefrences, resolver: resolver)} onQueryResponse(List<int> bytes) {',
      );
      buf.writeln(
        "    return ${ProtoRuntimeTypeMapper.bareDartType(type: query, importRefrences: importRefrences, resolver: resolver)}.deserialize(bytes);",
      );
      buf.writeln('  }');
    }
    return buf.toString();
  }

  @override
  List<ProtoService> filterServices(List<ProtoService> services) {
    return services.where((e) => knownQueryServices.contains(e.name)).toList();
  }

  @override
  String? buildToJson(
    ProtoMessage message,
    ProtoCompiler resolver, {
    StringEncoding? bytesEncoding,
    bool camelCase = false,
  }) {
    return null;
  }

  @override
  String? buildFromJson(
    ProtoMessage message,
    ProtoCompiler resolver,
    String className,
    Set<ProtoTypeLocation> importRefrences, {
    StringEncoding? bytesEncoding,
    bool camelCase = false,
    StringBuffer? buf,
  }) {
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
            final message = ProtoMessage(
              name: rpc.name,
              comments: "",
              options: [],
              fields: [
                ProtoField(
                  name: rpc.name,
                  tag: 0,
                  type: rpc.request,
                  options: [],
                  comments: rpc.comments,
                ),
              ],
              package: proto.package,
              services: [
                ServiceMessageOption(
                  rpc: rpc,
                  type: rpc.response,
                  serviceName: service.name,
                ),
              ],
            );
            final sourceFile = resolved[rpc.request.package]!
                .firstWhereNullable((file) {
                  return file.messages.any((m) => m.isEqualTo(rpc.request));
                });
            if (sourceFile == null) {
              continue;
            }
            replace(
              sourceFile,
              sourceFile.copyWith(messages: [...sourceFile.messages, message]),
            );
          }
        }
      }
    }

    return resolved.values.expand((e) => e).toList();
  }

  @override
  String? buildDeserialize(
    ProtoMessage message,
    ProtoCompiler resolver,
    String className,
    Set<ProtoTypeLocation> importRefrences, {
    StringEncoding? bytesEncoding,
    bool camelCase = false,
  }) {
    if (message.services.isEmpty) {
      return super.buildDeserialize(
        message,
        resolver,
        className,
        importRefrences,
        bytesEncoding: bytesEncoding,
        camelCase: camelCase,
      );
    }
    return null;
  }

  @override
  String buildConfigMembers(
    ProtoMessage message,
    ProtoCompiler resolver,
    ProtoSyntax syntax,
  ) {
    if (message.services.isEmpty) {
      return super.buildConfigMembers(message, resolver, syntax);
    }
    final buf = StringBuffer();
    final field = message.fields.first;
    buf.writeln('  @override');
    buf.writeln(
      '  ProtoMessageConfig protoConfig() =>${OnChainProtoUtils.fieldName(field.name)}?.protoConfig() ?? ProtoMessageConfig();',
    );
    buf.writeln();

    assert(message.fields.length == 1, "unexpected service");

    buf.writeln('  @override');
    buf.writeln(
      '  List<Object?> get protoValues => ${OnChainProtoUtils.fieldName(field.name)}?.protoValues??[];',
    );
    return buf.toString();
  }
}
