import 'package:onchain_proto/src/compiler/file_builder.dart';
import 'package:onchain_proto/src/compiler/code_gen.dart';
import 'package:onchain_proto/src/exception/exception.dart';
import 'package:onchain_proto/src/types/types.dart';
import 'package:onchain_proto/src/utils/utils.dart';
import 'type_resolver.dart';

class ProtoCompiler extends TypeResolver {
  ProtoCompiler({
    required this.writer,
    this.builder = const CosmosProtoCodegenTarget(),
    this.classNamePrefix = '',
  });

  factory ProtoCompiler.fromDirectory({
    required String sourceDirectory,
    required ProtoPackageWriter writer,
    ProtoCodegenTarget builder = const CosmosProtoCodegenTarget(),
    Map<String, ProtoPackageWriter> packageWriters = const {},
    String classNamePrefix = '',
  }) {
    final compiler = ProtoCompiler(
      writer: writer,
      builder: builder,
      classNamePrefix: classNamePrefix,
    );

    compiler.addSourceFiles(
      OnChainProtoUtils.findProtoFiles(
        directory: sourceDirectory,
        resolver: compiler,
      ),
    );

    return compiler;
  }

  final ProtoCodegenTarget builder;

  final ProtoPackageWriter writer;

  /// Prepended to every generated Dart class/enum name (e.g. `Cosmos` ->
  /// `CosmosMsgSend`, `CosmosSendEnabled`). Purely cosmetic on the Dart
  /// side: it never affects `typeUrl`, `declarationId`, or any other value
  /// derived from the original proto package/type name, so wire
  /// compatibility and generated-vs-previously-generated type identity are
  /// unaffected by turning this on, off, or changing it.
  final String classNamePrefix;

  final Map<String, List<ProtoSourceFile>> sourceFiles = {};

  final Map<String, GeneratedProtoPackage> generatedPackages = {};

  final Map<String, Set<String>> enumsByPackage = {};
  bool _onlyRefrences = false;

  @override
  Set<String> get allPackageNames => sourceFiles.keys.toSet();

  void addSourceFile(ProtoSourceFile file) {
    sourceFiles.putIfAbsent(file.packageName, () => []).add(file);
  }

  void addSourceFiles(Iterable<ProtoSourceFile> files) {
    for (final file in files) {
      addSourceFile(file);
    }
  }

  List<ProtoMessageRefrence> _refrences = [];
  List<ProtoDeclaration> _messages = [];

  bool messageHasRefrence(ProtoMessage message) {
    return _messages.contains(message) ||
        _refrences.any((e) => message.isEqualTo(e));
  }

  bool refrenceExists(ProtoMessageRefrence refrence) {
    return _messages.any((e) => e.isEqualTo(refrence)) ||
        _refrences.contains(refrence);
  }

  bool enumHasRefrences(ProtoEnum message) {
    return _messages.contains(message) ||
        _refrences.any((e) => message.isEqualTo(e));
  }

  bool fileHasRefrence(ProtoFile file) {
    return file.messages.any(messageHasRefrence) ||
        file.enums.any(enumHasRefrences);
  }

  void compile({bool onlyRefrences = false}) {
    final packages = sourceFiles.map(
      (key, value) => MapEntry(key, value.map((e) => e.toFile()).toList()),
    );
    final resolved = builder.attachServiceMetadata(packages);
    _indexPackages(resolved);
    _refrences = [];
    _messages = [];
    _onlyRefrences = onlyRefrences;
    if (onlyRefrences) {
      final closure = builder.computeReferenceClosure(generatedPackages);
      _refrences = closure?.references ?? [];
      _messages = closure?.declarations ?? [];
    }
  }

  void _indexPackages(List<ProtoFile> files) {
    generatedPackages.clear();
    final grouped = <String, List<ProtoFile>>{};

    for (final file in files) {
      grouped.putIfAbsent(file.package, () => []).add(file);

      enumsByPackage.putIfAbsent(file.package, () => {});

      for (final e in file.enums) {
        enumsByPackage[file.package]!.add(e.fullTypeName());
      }
    }

    for (final entry in grouped.entries) {
      final output = writer.createPackage(
        files: entry.value,
        package: entry.key,
      );

      generatedPackages[entry.key] = output;
    }
  }

  GeneratedProtoPackage generatedPackage(String packageName) {
    final package = generatedPackages[packageName];

    if (package == null) {
      throw OnChainProtoException("Unknown package '$packageName'.");
    }

    return package;
  }

  List<ProtoSourceFile>? tryGetsSourcFiles(String packageName) {
    final package = sourceFiles[packageName];

    return package;
  }

  List<ProtoSourceFile> sourcFiles(String packageName) {
    final package = tryGetsSourcFiles(packageName);
    if (package == null) {
      throw OnChainProtoException("Unknown package '$packageName'.");
    }

    return package;
  }

  ProtoWritePackageResult? _writePackage(
    String packageName, {
    bool onlyRefrences = false,
  }) {
    final output = generatedPackage(packageName);

    return writer.writePackage(
      package: output,
      builder: this,
      onlyRefrences: onlyRefrences,
    );
  }

  List<ProtoWritePackageResult> writeAll() {
    List<ProtoWritePackageResult> result = [];
    for (final package in generatedPackages.keys) {
      final write = _writePackage(package, onlyRefrences: _onlyRefrences);
      if (write == null) continue;
      result.add(write);
    }
    return result;
  }

  @override
  bool isPackage(String packageName) {
    return sourceFiles.containsKey(packageName);
  }

  bool isEnum(ProtoMessageRefrence reference) {
    return enumsByPackage[reference.package]?.contains(
          reference.fullTypeName(),
        ) ??
        false;
  }

  @override
  Set<String> types(String fullPackagePath) {
    final source = tryGetsSourcFiles(fullPackagePath);
    final types = source?.expand((e) => e.parser.types).toSet();
    return types ?? {};
  }

  @override
  List<ProtoDeclaration> getPackageDeclaration(String fullPackagePath) {
    final source = tryGetsSourcFiles(fullPackagePath);
    final types = source?.expand((e) => e.parser.declarations).toList();
    return types ?? [];
  }
}
