import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:onchain_proto/src/compiler/compiler.dart';
import 'package:onchain_proto/src/parser/proto_parser.dart';
import 'package:onchain_proto/src/utils/utils.dart';

class ParsedProtobufMessage {
  final List<ParsedProtobufMessage> nestedMessages;
  final ProtoMessage message;
  final List<ProtoEnum> enums;
  const ParsedProtobufMessage({
    required this.nestedMessages,
    required this.message,
    required this.enums,
  });
  List<ProtoEnum> getEums() {
    return [...enums, ...nestedMessages.expand((e) => e.enums)];
  }

  List<ProtoMessage> getMessages() {
    return [message, ...nestedMessages.expand((e) => e.getMessages())];
  }
}

class ProtoWriteSkipFile {
  final String protoPath;
  final String importUri;
  final bool allowInSrc;
  const ProtoWriteSkipFile({
    required this.protoPath,
    required this.importUri,
    required this.allowInSrc,
  });
}

class ProtoPackagePathOverride {
  final String outputRoot;
  final String packageRoot;
  final List<String> packages;
  const ProtoPackagePathOverride({
    required this.outputRoot,
    required this.packages,
    required this.packageRoot,
  });
}

class ProtoSourceFile {
  final String path;
  final String packageName;
  final ProtoFileParser parser;
  const ProtoSourceFile({
    required this.parser,
    required this.path,
    required this.packageName,
  });

  ProtoFile toFile() {
    return parser.finalize();
  }
}

class GeneratedProtoFile {
  final String outputPath;
  final String importPath;
  final ProtoFile file;
  const GeneratedProtoFile({
    required this.outputPath,
    required this.file,
    required this.importPath,
  });
}

class GeneratedProtoPackage {
  final String package;
  final List<GeneratedProtoFile> files;
  GeneratedProtoPackage({required this.files, required this.package});
}

class ProtoConvertFileResult {
  final String generatedData;
  final List<ProtoConvertMessageResult> classInfo;
  const ProtoConvertFileResult({
    required this.classInfo,
    required this.generatedData,
  });
}

class ProtoConvertMessageResult {
  final String data;
  final String className;
  final ProtoMessage message;

  const ProtoConvertMessageResult({
    required this.data,
    required this.className,
    required this.message,
  });

  String get package => message.package;

  /// Built only from the original proto package + declaration name -
  /// never from the generated Dart [className]. This is deliberate: a
  /// `classNamePrefix` (see [ProtoCompiler.classNamePrefix]) is free to
  /// change what the generated Dart type is called without changing what
  /// goes on the wire / in on-chain type registries, so typeUrl must stay
  /// derived from proto-space names only.
  String get typeUrl => "/$package.${message.fullName()}";
}

class ProtoWriteFileResult {
  final ProtoConvertFileResult fileData;
  final String importPath;
  final String? srcPath;
  const ProtoWriteFileResult({
    required this.fileData,
    required this.importPath,
    required this.srcPath,
  });
}

class ProtoWritePackageResult {
  final List<ProtoWriteFileResult> files;
  final String package;
  final String srcUrl;
  const ProtoWritePackageResult({
    required this.files,
    required this.package,
    required this.srcUrl,
  });
}

enum ProtoScalarType {
  double_,
  float_,
  int32,
  int64,
  uint32,
  uint64,
  sint32,
  sint64,
  fixed32,
  fixed64,
  sfixed32,
  sfixed64,
  bool_,
  string_,
  bytes,
}

sealed class ProtoType {
  const ProtoType();
  Map<String, dynamic> toJson();

  List<ProtoMessageRefrence> refTypes();

  ProtoType resolveRefrences(
    ProtoMessageRefrence Function(ProtoMessageRefrence) fn,
  );
}

class ProtoScalar extends ProtoType with Equality {
  final ProtoScalarType type;

  const ProtoScalar(this.type);

  ProtoScalar copyWith({ProtoScalarType? type}) {
    return ProtoScalar(type ?? this.type);
  }

  @override
  List<dynamic> get variables => [type];

  @override
  String toString() => "ProtoScalar(${type.name})";

  @override
  Map<String, dynamic> toJson() {
    return {"type": type.name};
  }

  @override
  List<ProtoMessageRefrence> refTypes() {
    return [];
  }

  @override
  ProtoType resolveRefrences(
    ProtoMessageRefrence Function(ProtoMessageRefrence) fn,
  ) {
    return this;
  }
}

class ProtoMessageRefrence extends ProtoType with Equality {
  final String typeName;
  final String package;
  final String? nestedName;
  final bool resolved;
  const ProtoMessageRefrence({
    required String fullName,
    required this.typeName,
    required this.package,
    required this.nestedName,
    this.resolved = true,
  });
  factory ProtoMessageRefrence.unresolved(String typeName) {
    return ProtoMessageRefrence(
      fullName: typeName,
      typeName: typeName,
      package: "",
      nestedName: null,
      resolved: false,
    );
  }
  @override
  Map<String, dynamic> toJson() {
    return {"typeName": typeName, "package": package, "nestedName": nestedName};
  }

  @override
  String toString() {
    return "ProtoMessageRefrence(${toJson()})";
  }

  @override
  List<ProtoMessageRefrence> refTypes() {
    return [this];
  }

  @override
  List<dynamic> get variables => [typeName, package];

  String fullTypeName() {
    assert(resolved, "unresolved.");
    final nestedName = this.nestedName;
    if (nestedName != null) {
      assert(nestedName.contains("."), "unexpected nested name.  $nestedName");
      return nestedName.split(".").join("");
    }
    return typeName;
  }

  @override
  ProtoMessageRefrence resolveRefrences(
    ProtoMessageRefrence Function(ProtoMessageRefrence) fn,
  ) {
    return fn(this);
  }

  bool isGoogleTimestamp() =>
      OnChainProtoUtils.isGoogleTimestamp(package, typeName);
  bool isGoogleDuration() =>
      OnChainProtoUtils.isGoogleDuration(package, typeName);
}

class ProtoMap extends ProtoType with Equality {
  final ProtoType key;
  final ProtoType value;

  const ProtoMap({required this.key, required this.value});

  ProtoMap copyWith({ProtoType? key, ProtoType? value}) {
    return ProtoMap(key: key ?? this.key, value: value ?? this.value);
  }

  @override
  List<dynamic> get variables => [key, value];

  @override
  Map<String, dynamic> toJson() {
    return {"key": key.toJson(), "value": value.toJson()};
  }

  @override
  List<ProtoMessageRefrence> refTypes() {
    return [...key.refTypes(), ...value.refTypes()];
  }

  @override
  String toString() {
    return "ProtoMap($key, $value)";
  }

  @override
  ProtoType resolveRefrences(
    ProtoMessageRefrence Function(ProtoMessageRefrence) fn,
  ) {
    ProtoType key = this.key;
    ProtoType value = this.value;
    if (key case ProtoMessageRefrence()) {
      key = fn(key);
    }
    if (value case ProtoMessageRefrence()) {
      value = fn(value);
    }
    return ProtoMap(key: key, value: value);
  }
}

class ProtoRepeated extends ProtoType with Equality {
  final ProtoType inner;

  const ProtoRepeated(this.inner);

  ProtoRepeated copyWith({ProtoType? inner}) {
    return ProtoRepeated(inner ?? this.inner);
  }

  @override
  List<ProtoMessageRefrence> refTypes() {
    return inner.refTypes();
  }

  @override
  List<dynamic> get variables => [inner];

  @override
  Map<String, dynamic> toJson() {
    return {"inner": inner.toJson()};
  }

  @override
  String toString() {
    return "ProtoRepeated($inner)";
  }

  @override
  ProtoType resolveRefrences(
    ProtoMessageRefrence Function(ProtoMessageRefrence) fn,
  ) {
    ProtoType inner = this.inner;
    if (inner case ProtoMessageRefrence()) {
      inner = fn(inner);
    }
    return ProtoRepeated(inner);
  }
}

class ProtoField with Equality {
  final String name;
  final int tag;
  final ProtoType type;
  final List<ProtoOption> options;
  final String comments;
  final bool optional;
  final bool required;
  const ProtoField({
    required this.name,
    required this.tag,
    required this.type,
    required this.options,
    required this.comments,
    this.optional = false,
    this.required = false,
  });

  ProtoField copyWith({
    String? name,
    int? tag,
    ProtoType? type,
    List<ProtoOption>? options,
    String? comments,
    bool? optional,
    bool? required,
  }) {
    return ProtoField(
      name: name ?? this.name,
      tag: tag ?? this.tag,
      type: type ?? this.type,
      options: options ?? this.options,
      comments: comments ?? this.comments,
      optional: optional ?? this.optional,
      required: required ?? this.required,
    );
  }

  @override
  List<dynamic> get variables => [name, tag, type, options, comments, optional];
  Map<String, dynamic> toJson() {
    return {
      "name": name,
      "tag": tag,
      "type": type.toJson(),
      "required": required,
    };
  }

  ProtoField resolveRefrences(
    ProtoMessageRefrence Function(ProtoMessageRefrence) fn,
  ) {
    return copyWith(type: type.resolveRefrences(fn));
  }

  @override
  String toString() => "ProtoField($name)";
}

sealed class ProtoDeclaration with Equality {
  final String name;
  final String package;

  /// The parent of this this mean this decelarion is nested
  /// also ProtoMessage and protoEnim is type of ProtoDeclaration
  final ProtoMessage? parent;

  const ProtoDeclaration({
    required this.name,
    required this.package,
    required this.parent,
  });
  String fullName() {
    final parentName = parent?.fullName();
    if (parentName != null) {
      return "$parentName.$name";
    }
    return name;
  }

  String fullTypeName() {
    return fullName().split(".").join();
  }

  bool isEqualTo(ProtoMessageRefrence type) {
    if (type.package != package) return false;
    final nestedName = type.nestedName;
    if (nestedName != null) return nestedName == fullName();
    return name == type.typeName;
  }

  bool isFrom(String package) => this.package == package;

  List<ProtoMessageRefrence> refTypes();

  @override
  String toString() {
    return "ProtoDeclaration(${fullName()})";
  }

  @override
  List<dynamic> get variables => [name, package, parent];
}

class ProtoEnum extends ProtoDeclaration {
  final String comments;
  final List<ProtoOption> options;
  final List<ProtoEnumValue> values;

  const ProtoEnum({
    required super.name,
    required super.package,
    required this.comments,
    required this.options,
    required this.values,
    super.parent,
  });

  ProtoEnum copyWith({
    String? name,
    String? package,
    String? comments,
    List<ProtoOption>? options,
    List<ProtoEnumValue>? values,
    ProtoMessage? parent,
  }) {
    return ProtoEnum(
      name: name ?? this.name,
      comments: comments ?? this.comments,
      options: options ?? this.options,
      values: values ?? this.values,
      package: package ?? this.package,
      parent: parent ?? this.parent,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "name": name,
      "comments": comments,
      "options": options.map((e) => e.toJson()).toList(),
      "values": values.map((e) => e.toJson()).toList(),
    };
  }

  @override
  List<ProtoMessageRefrence> refTypes() {
    return [];
  }
}

class ProtoEnumValue with Equality {
  final String name;
  final int value;
  final String comments;
  final List<ProtoOption> options;

  const ProtoEnumValue({
    required this.name,
    required this.value,
    required this.comments,
    required this.options,
  });

  ProtoEnumValue copyWith({
    String? name,
    int? value,
    String? comments,
    List<ProtoOption>? options,
  }) {
    return ProtoEnumValue(
      name: name ?? this.name,
      value: value ?? this.value,
      comments: comments ?? this.comments,
      options: options ?? this.options,
    );
  }

  @override
  List<dynamic> get variables => [name, value, comments, options];

  Map<String, dynamic> toJson() {
    return {
      "name": name,
      "value": value,
      "comments": comments,
      "options": options.map((e) => e.toJson()).toList(),
    };
  }
}

class ProtoMessage extends ProtoDeclaration {
  final String comments;
  final List<ProtoOption> options;
  final List<ProtoField> fields;
  final List<ServiceMessageOption> services;

  const ProtoMessage({
    required super.name,
    required this.comments,
    required this.options,
    required this.fields,
    super.parent,
    required super.package,
    required this.services,
  });

  ProtoMessage copyWith({
    String? name,
    String? comments,
    ProtoMessage? parent,
    List<ProtoOption>? options,
    List<ProtoField>? fields,
    String? package,
    List<ServiceMessageOption>? services,
  }) {
    return ProtoMessage(
      name: name ?? this.name,
      comments: comments ?? this.comments,
      options: options ?? this.options,
      fields: fields ?? this.fields,
      services: services ?? this.services,
      parent: parent ?? this.parent,
      package: package ?? this.package,
    );
  }

  @override
  String toString() => "ProtoMessage({name: $name, fields: $fields})";

  Map<String, dynamic> toJson() {
    return {
      "name": name,
      "comments": comments,
      "options": options.map((e) => e.toJson()).toList(),
      "fields": fields.map((e) => e.toJson()).toList(),
    };
  }

  @override
  List<ProtoMessageRefrence> refTypes() {
    final List<ProtoType> types = [
      ...fields.map((e) => e.type),
      ...services.map((e) => e.type),
    ];
    return types.expand((e) => e.refTypes()).toList();
  }

  ProtoMessage resolveRefrences(
    ProtoMessageRefrence Function(
      ProtoMessageRefrence,
      ProtoDeclaration? parent,
    )
    fn,
  ) {
    return copyWith(
      // Pass `this` (the message itself) as the enclosing context,
      // not `this.parent`. The resolver needs to know we are INSIDE
      // this message when resolving its fields.
      fields: fields
          .map((e) => e.resolveRefrences((p0) => fn(p0, this)))
          .toList(),
      services: services
          .map((e) => e.resolveRefrences((p0) => fn(p0, this)))
          .toList(),
    );
  }

  bool hasOption(String key) {
    return options.any((e) => e.name == key);
  }

  List<ProtoOption> getAllOptions() => [
    ...options,
    ...fields.expand((e) => e.options),
  ];
}

/// A proto2 `extend TargetType { ... }` block: declares additional fields
/// for `TargetType` (which is defined elsewhere - often in a different
/// file/package entirely, e.g. plugins extending
/// `google.protobuf.FileOptions`) from outside that type's own
/// declaration. Not valid in proto3, but needed to parse proto2 files such
/// as descriptor.proto and files that extend its options messages.
class ProtoExtend with Equality {
  /// The type being extended, e.g. `google.protobuf.FileOptions`.
  final ProtoType type;

  final String comments;

  final List<ProtoOption> options;

  /// The extension fields declared inside this block.
  final List<ProtoField> fields;

  const ProtoExtend({
    required this.type,
    required this.comments,
    required this.options,
    required this.fields,
  });

  @override
  List<dynamic> get variables => [type, comments, options, fields];
  Map<String, dynamic> toJson() {
    return {
      "type": type.toJson(),
      "comments": comments,
      "options": options.map((e) => e.toJson()).toList(),
      "fields": fields.map((e) => e.toJson()).toList(),
    };
  }
}

class ProtoService with Equality {
  final String name;
  final String comments;
  final List<ProtoOption> options;
  final List<ProtoRpc> rpcs;

  const ProtoService({
    required this.name,
    required this.comments,
    required this.options,
    required this.rpcs,
  });

  ProtoService resolveRefrences(
    ProtoMessageRefrence Function(ProtoMessageRefrence) fn,
  ) {
    return copyWith(rpcs: rpcs.map((e) => e.resolveRefrences(fn)).toList());
  }

  ProtoService copyWith({
    String? name,
    String? comments,
    List<ProtoOption>? options,
    List<ProtoRpc>? rpcs,
  }) {
    return ProtoService(
      name: name ?? this.name,
      comments: comments ?? this.comments,
      options: options ?? this.options,
      rpcs: rpcs ?? this.rpcs,
    );
  }

  @override
  List<dynamic> get variables => [name, comments, options, rpcs];

  Map<String, dynamic> toJson() {
    return {
      "name": name,
      "comments": comments,
      "options": options.map((e) => e.toJson()).toList(),
      "rpcs": rpcs.map((e) => e.toJson()).toList(),
    };
  }
}

class ProtoRpc with Equality {
  final String name;
  final ProtoMessageRefrence request;
  final ProtoMessageRefrence response;
  final bool clientStreaming;
  final bool serverStreaming;
  final String comments;
  final List<ProtoOption> options;

  const ProtoRpc({
    required this.name,
    required this.request,
    required this.response,
    required this.clientStreaming,
    required this.serverStreaming,
    required this.comments,
    required this.options,
  });
  ProtoRpc resolveRefrences(
    ProtoMessageRefrence Function(ProtoMessageRefrence) fn,
  ) {
    return copyWith(
      request: request.resolveRefrences(fn),
      response: response.resolveRefrences(fn),
    );
  }

  ProtoRpc copyWith({
    String? name,
    ProtoMessageRefrence? request,
    ProtoMessageRefrence? response,
    bool? clientStreaming,
    bool? serverStreaming,
    String? comments,
    List<ProtoOption>? options,
  }) {
    return ProtoRpc(
      name: name ?? this.name,
      request: request ?? this.request,
      response: response ?? this.response,
      clientStreaming: clientStreaming ?? this.clientStreaming,
      serverStreaming: serverStreaming ?? this.serverStreaming,
      comments: comments ?? this.comments,
      options: options ?? this.options,
    );
  }

  @override
  List<dynamic> get variables => [
    name,
    request,
    response,
    clientStreaming,
    serverStreaming,
    comments,
    options,
  ];

  Map<String, dynamic> toJson() {
    return {
      "name": name,
      "comments": comments,
      "options": options.map((e) => e.toJson()).toList(),
      "request": request.toJson(),
      "response": response.toJson(),
      "clientStreaming": clientStreaming,
      "serverStreaming": serverStreaming,
    };
  }
}

class ProtoFile with Equality {
  final ProtoSyntax syntax;
  final String package;
  final String name;
  final String protoPath;
  final List<String> imports;
  final List<ProtoOption> options;
  final List<ProtoEnum> enums;
  final List<ProtoMessage> messages;
  final List<ProtoService> services;
  final List<ProtoExtend> extends_;

  bool hasEnums() => enums.isNotEmpty;
  bool hasMessage() => messages.isNotEmpty;

  factory ProtoFile.unknown() {
    return ProtoFile(
      syntax: ProtoSyntax.v3,
      package: "",
      imports: [],
      options: [],
      enums: [],
      messages: [],
      services: [],
      extends_: [],
      protoPath: "",
      name: "",
    );
  }

  const ProtoFile({
    required this.syntax,
    required this.package,
    required this.imports,
    required this.options,
    required this.enums,
    required this.messages,
    required this.services,
    required this.extends_,
    required this.name,
    required this.protoPath,
  });

  ProtoFile copyWith({
    ProtoSyntax? syntax,
    String? package,
    List<String>? imports,
    List<ProtoOption>? options,
    List<ProtoEnum>? enums,
    List<ProtoMessage>? messages,
    List<ProtoService>? services,
    List<ProtoExtend>? extends_,
    String? name,
    String? protoPath,
  }) {
    return ProtoFile(
      syntax: syntax ?? this.syntax,
      package: package ?? this.package,
      imports: imports ?? this.imports,
      options: options ?? this.options,
      enums: enums ?? this.enums,
      messages: messages ?? this.messages,
      services: services ?? this.services,
      extends_: extends_ ?? this.extends_,
      name: name ?? this.name,
      protoPath: protoPath ?? this.protoPath,
    );
  }

  @override
  List<dynamic> get variables => [
    syntax,
    package,
    imports,
    options,
    enums,
    messages,
    services,
  ];

  Map<String, dynamic> toJson() {
    return {
      "syntax": syntax,
      "package": package,
      "imports": imports,
      "options": options.map((e) => e.toJson()).toList(),
      "enums": enums.map((e) => e.toJson()).toList(),
      "messages": messages.map((e) => e.toJson()).toList(),
      "services": services.map((e) => e.toJson()).toList(),
      "extends": extends_.map((e) => e.toJson()).toList(),
    };
  }

  List<ProtoMessageRefrence> refrenceMessages() {
    return messages.expand((e) => e.refTypes()).toList();
  }

  List<String> typesName() {
    return [
      ...messages.map((e) => e.fullTypeName()),
      ...enums.map((e) => e.fullTypeName()),
    ];
  }

  ProtoFile resolveRefrences(
    ProtoMessageRefrence Function(
      ProtoMessageRefrence,
      ProtoDeclaration? parent,
    )
    fn,
  ) {
    return copyWith(
      messages: messages.map((e) => e.resolveRefrences(fn)).toList(),
      services: services
          .map((e) => e.resolveRefrences((p0) => fn(p0, null)))
          .toList(),
    );
  }
}

class ServiceMessageOption {
  final String serviceName;
  final ProtoRpc rpc;
  final ProtoMessageRefrence type;
  const ServiceMessageOption({
    required this.rpc,
    required this.type,
    required this.serviceName,
  });

  String fullName() => "$serviceName/${rpc.name}";

  Map<String, dynamic> toJson() {
    return {"rpc": rpc.toJson(), "type": type.toJson()};
  }

  ServiceMessageOption copyWith({
    ProtoRpc? rpc,
    ProtoMessageRefrence? type,
    String? serviceName,
  }) {
    return ServiceMessageOption(
      rpc: rpc ?? this.rpc,
      type: type ?? this.type,
      serviceName: serviceName ?? this.serviceName,
    );
  }

  ServiceMessageOption resolveRefrences(
    ProtoMessageRefrence Function(ProtoMessageRefrence) fn,
  ) {
    return copyWith(rpc: rpc, type: fn(type));
  }
}

class ProtoTypeLocation extends Equality {
  final String name;

  final String alias;

  final String importPath;

  final String packageName;

  ProtoTypeLocation({
    required this.name,
    required this.importPath,
    required this.packageName,
    String? alias,
  }) : alias =
           alias ??
           '${packageName.replaceAll(".", "_")}_${importPath.split('/').last.split('.').first}'
               .toLowerCase();

  @override
  List<Object?> get variables => [name, packageName];

  @override
  String toString() {
    return 'ProtoTypeLocation($name, $packageName)';
  }
}
