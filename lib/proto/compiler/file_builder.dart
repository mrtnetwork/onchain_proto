import 'dart:io';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:onchain_proto/proto/compiler/compiler.dart';
import 'package:onchain_proto/proto/compiler/dart_converter.dart';
import 'package:onchain_proto/proto/types/types.dart';

class ProtoPackageWriter {
  final String outputRoot;
  final String packageRoot;
  final List<ProtoWriteSkipFile> skipFiles;
  final Map<String, ProtoPackagePathOverride> _overridePaths;
  final List<SkipMessages> skipMessages;
  factory ProtoPackageWriter({
    required String outputRoot,
    required String packageRoot,
    List<SkipMessages> skipMessages = const [],
    List<ProtoWriteSkipFile> skipFiles = const [],
    List<ProtoPackagePathOverride> overrides = const [],
  }) {
    Map<String, ProtoPackagePathOverride> overridePaths = {};
    for (final i in overrides) {
      for (final p in i.packages) {
        overridePaths[p] = i;
      }
    }
    return ProtoPackageWriter._(
      outputRoot: outputRoot,
      packageRoot: packageRoot,
      overridePaths: overridePaths,
      skipFiles: skipFiles,
      skipMessages: skipMessages,
    );
  }
  ProtoPackageWriter._({
    required this.outputRoot,
    required this.packageRoot,
    this.skipFiles = const [],
    this._overridePaths = const {},
    this.skipMessages = const [],
  });

  ProtoWriteSkipFile? _getSkipFile(ProtoFile file) {
    if (skipFiles.isEmpty) return null;
    return skipFiles.firstWhereNullable((e) => e.protoPath == file.protoPath);
  }

  String _normalizePackage(String packageName) {
    return packageName.replaceAll('.', '/');
  }

  String _getPackageRoot(String packageName) {
    return _overridePaths[packageName]?.packageRoot ?? packageRoot;
  }

  String _getOutputRoot(String packageName) {
    return _overridePaths[packageName]?.outputRoot ?? outputRoot;
  }

  String packageLibraryUri(String packageName) {
    return '${_getPackageRoot(packageName)}/${_normalizePackage(packageName)}/models.dart';
  }

  String messageLibraryUri({
    required String packageName,
    required String fileName,
  }) {
    return '${_getPackageRoot(packageName)}/${_normalizePackage(packageName)}/src/$fileName';
  }

  String packageLibraryPath(String packageName) {
    return '${_getOutputRoot(packageName)}/${_normalizePackage(packageName)}/models.dart';
  }

  String packageSourceDirectory(String packageName) {
    return '${_getOutputRoot(packageName)}/${_normalizePackage(packageName)}/src';
  }

  GeneratedProtoPackage createPackage({
    required List<ProtoFile> files,
    required String package,
  }) {
    assert(files.isNotEmpty);
    assert(files.every((e) => e.package == package));

    final usedNames = <String>{};

    final generatedFiles = files
        .where((e) => e.hasEnums() || e.hasMessage())
        .map((file) => _createOutputFile(file, usedNames))
        .toList();

    return GeneratedProtoPackage(files: generatedFiles, package: package);
  }

  GeneratedProtoFile _createOutputFile(
    ProtoFile protoFile,
    Set<String> usedNames,
  ) {
    final skip = _getSkipFile(protoFile);
    final sourceDir = packageSourceDirectory(protoFile.package);

    final baseName = protoFile.name;

    var fileName = '$baseName.dart';
    var index = 1;

    while (!usedNames.add(fileName)) {
      fileName = '${baseName}_$index.dart';
      index++;
    }

    return GeneratedProtoFile(
      outputPath: '$sourceDir/$fileName',
      importPath:
          skip?.importUri ??
          messageLibraryUri(packageName: protoFile.package, fileName: fileName),
      file: protoFile,
    );
  }

  ProtoWriteFileResult? writeMessageFile({
    required GeneratedProtoFile file,
    required ProtoCompiler builder,
    bool writeToFile = true,
    bool onlyRefrences = false,
  }) {
    final result = file.file.toDartProtoMessages(
      builder,
      onlyRefrences: onlyRefrences,
    );
    if (result == null) return null;
    final skip = _getSkipFile(file.file);
    if (skip != null) {
      return ProtoWriteFileResult(
        fileData: result,
        importPath: skip.importUri,
        srcPath: skip.allowInSrc
            ? 'src/${file.outputPath.split("/").last}'
            : null,
      );
    }
    final output = File(file.outputPath);
    if (writeToFile && result.write) {
      output.createSync(recursive: true);
      output.writeAsStringSync(result.generatedData);
    }

    return ProtoWriteFileResult(
      fileData: result,
      importPath: file.importPath,
      srcPath: result.write ? 'src/${output.uri.pathSegments.last}' : null,
    );
  }

  ProtoWritePackageResult? writePackage({
    required GeneratedProtoPackage package,
    required ProtoCompiler builder,
    bool onlyRefrences = false,
    bool writeToFile = true,
  }) {
    if (package.files.isEmpty) {
      return null;
    }
    assert(package.files.isNotEmpty);

    final exports = package.files
        .map(
          (file) => writeMessageFile(
            file: file,
            builder: builder,
            onlyRefrences: onlyRefrences,
            writeToFile: writeToFile,
          ),
        )
        .whereType<ProtoWriteFileResult>()
        .toList();
    if (exports.isEmpty) return null;
    if (writeToFile) {
      final library = File(packageLibraryPath(package.package))
        ..createSync(recursive: true);

      library.writeAsStringSync(
        exports
            .where((e) => e.srcPath != null)
            .map((e) => "export '${e.srcPath}';")
            .join('\n'),
      );
    }
    return ProtoWritePackageResult(
      files: exports,
      package: package.package,
      srcUrl: packageLibraryUri(package.package),
    );
  }
}
