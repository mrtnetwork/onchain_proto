import 'dart:io';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:onchain_proto/proto/compiler/compiler.dart';
import 'package:onchain_proto/proto/exception/exception.dart';
import 'package:onchain_proto/proto/parser/proto_parser.dart';
import 'package:onchain_proto/proto/types/types.dart';

class OnChainProtoUtils {
  static ProtoSourceFile readProtoFile({
    required String filePath,
    required ProtoCompiler resolver,
  }) {
    final source = File(filePath).readAsStringSync();
    final name = filePath.split("/").last.split(".").first;
    final parser = ProtoFileParser(
      source: source,
      resolver: resolver,
      path: filePath,
      name: StringUtils.camelToSnake(name),
    );
    return ProtoSourceFile(
      parser: parser,
      path: filePath,
      packageName: parser.packageName,
    );
  }

  static List<ProtoSourceFile> findProtoFiles({
    required String directory,
    required ProtoCompiler resolver,
  }) {
    final data = Directory(directory).listSync();
    List<ProtoSourceFile> files = [];
    for (final i in data) {
      if (i is Directory) {
        files.addAll(findProtoFiles(directory: i.path, resolver: resolver));
      } else {
        if (!i.path.endsWith(".proto")) {
          continue;
        }
        final packageName = readProtoFile(filePath: i.path, resolver: resolver);

        files.add(packageName);
      }
    }
    return files;
  }

  static ProtoTypeLocation? resolveTypeLocation({
    required ProtoMessageRefrence message,
    required ProtoCompiler resolver,
    required ProtoFile f,
    // void Function()
  }) {
    final typeName = message.fullTypeName();
    final external = message.package == f.package ? null : message.package;
    final files = switch (external) {
      null => resolver.generatedPackage(f.package),
      String package => resolver.generatedPackage(package),
    };
    final file = files.files.firstWhere(
      (e) {
        final types = e.file.typesName();
        return types.contains(typeName);
      },
      orElse: () => throw OnChainProtoException(
        "Type not find $message $typeName /  ${files.files.expand((e) => e.file.typesName().toList()).toList()}",
      ),
    );
    final skip = resolver.isSkipedMessage(message);
    if (skip != null) {
      return ProtoTypeLocation(
        name: typeName,
        importPath: skip.importPath,
        packageName: external ?? f.package,
      );
    }
    if (identical(file.file, f)) return null;

    return ProtoTypeLocation(
      name: typeName,
      importPath: file.importPath,
      packageName: external ?? f.package,
    );
  }

  static const googleProtobufPackage = "google.protobuf";
  static const googleProtobufTimestampType = "Timestamp";
  static const googleProtobufDuration = "Duration";
  static const goProtoStdDuration = "gogoproto.stdduration";
  static bool isGoogleTimestamp(String package, String type) {
    return package == googleProtobufPackage &&
        type == googleProtobufTimestampType;
  }

  static bool isGoogleDuration(String package, String type) {
    return package == googleProtobufPackage && type == googleProtobufDuration;
  }

  static bool hasStdduration(List<ProtoOption> options) {
    return options.any((e) => e.name == goProtoStdDuration);
  }

  static const _dartReservedWords = {
    'abstract',
    'as',
    'assert',
    'async',
    'await',
    'break',
    'case',
    'catch',
    'class',
    'const',
    'continue',
    'covariant',
    'default',
    'deferred',
    'do',
    'dynamic',
    'else',
    'enum',
    'export',
    'extends',
    'extension',
    'external',
    'factory',
    'false',
    'final',
    'finally',
    'for',
    'Function',
    'get',
    'hide',
    'if',
    'implements',
    'import',
    'in',
    'interface',
    'is',
    'late',
    'library',
    'mixin',
    'new',
    'null',
    'on',
    'operator',
    'part',
    'required',
    'rethrow',
    'return',
    'set',
    'show',
    'static',
    'super',
    'switch',
    'sync',
    'this',
    'throw',
    'true',
    'try',
    'typedef',
    'var',
    'void',
    'while',
    'with',
    'yield',

    ///
    'int',
  };

  /// `spend_limit` -> `spendLimit`; escapes Dart keywords with a trailing
  /// underscore (`class` -> `class_`) so the field name always compiles.
  static String fieldName(String protoName) {
    final camel = snakeToCamel(protoName, capitalizeFirst: false);
    return _dartReservedWords.contains(camel) ? '${camel}_' : camel;
  }

  /// `BasicAllowance` stays `BasicAllowance`; `basic_allowance` (unlikely
  /// for message names, but handled) -> `BasicAllowance`. Dots from
  /// fully-qualified refs should already be stripped via [lastSegment]
  /// before calling this.
  ///
  /// [prefix], when non-empty, is prepended verbatim to the generated
  /// name (e.g. prefix `Cosmos` + proto name `MsgSend` -> `CosmosMsgSend`).
  /// This only affects the *Dart* class/enum identifier - it must never
  /// leak into anything derived from the original proto name (typeUrl,
  /// declarationId, wire-format lookups, etc.), since those are contracts
  /// with the outside world and have to stay stable regardless of how the
  /// generator happens to name the local Dart type.
  static String className(String protoName, {String prefix = ''}) {
    final cleaned = protoName.replaceAll('.', '_');
    final base = snakeToCamel(cleaned, capitalizeFirst: true);
    return prefix.isEmpty ? base : '$prefix$base';
  }

  /// `MY_ENUM_VALUE_UNSPECIFIED` -> `myEnumValueUnspecified`.
  static String enumValueName(String protoName) {
    final camel = snakeToCamel(protoName, capitalizeFirst: false);
    return _dartReservedWords.contains(camel) ? '${camel}_' : camel;
  }

  /// `google.protobuf.Any` -> `Any`. Used so message-ref fields reference
  /// the local Dart class name rather than the fully-qualified proto path
  /// (the generator emits one flat set of classes per file, mirroring how
  /// the parser already flattens nested types - see proto_parser.dart).
  static String lastSegment(String dottedName) {
    final parts = dottedName.split('.');
    return parts.isEmpty ? dottedName : parts.last;
  }

  static String snakeToCamel(String input, {required bool capitalizeFirst}) {
    if (input.isEmpty) return input;
    final parts = input
        .split(RegExp(r'[_\-]+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return input;

    final buf = StringBuffer();
    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      final shouldCapitalize = capitalizeFirst || i > 0;
      buf.write(_capitalizeWord(part, capitalize: shouldCapitalize));
    }
    return buf.toString();
  }

  static String _capitalizeWord(String word, {required bool capitalize}) {
    if (word.isEmpty) return word;

    // Proto enum values are conventionally SCREAMING_SNAKE_CASE, so a
    // word like "UNSPECIFIED" arrives here fully uppercase. If we only
    // touched the first letter (as you'd do for a word that's *already*
    // mixed-case, e.g. preserving a genuine acronym), every snake_case
    // segment after the first would stay shouting - "UNSPECIFIED" not
    // "Unspecified" - which breaks camelCase entirely.
    //
    // Heuristic: if the word is all-uppercase (and more than one letter,
    // so single-letter words/initials aren't affected), lowercase the
    // tail before re-capitalizing the first letter. Otherwise (already
    // mixed-case, e.g. a deliberate acronym like "ID" mid-word in a
    // genuinely camelCase source), leave the tail untouched.
    final isShouting = word.length > 1 && word == word.toUpperCase();
    final tail = isShouting
        ? word.substring(1).toLowerCase()
        : word.substring(1);

    final first = capitalize ? word[0].toUpperCase() : word[0].toLowerCase();
    return '$first$tail';
  }

  // /// Wraps multi-line proto comments as a Dart doc comment (`///` per line).
  // static String? comment(String comments, {String indent = ''}) {
  //   final lines = comments.split('\n').where((e) => !e.contains("TODO"));
  //   if (lines.isEmpty) return null;
  //   return lines.map((l) => '$indent/// $l'.trimRight()).join('\n');
  // }

  /// Wraps multi-line proto comments as a Dart doc comment (`///` per line).
  static String? comment(String comments, {String indent = ''}) {
    final lines = comments.split('\n').where((e) => !e.contains("TODO"));
    if (lines.isEmpty) return null;
    return lines
        .map((l) => '$indent/// ${_escapeDocComment(l)}'.trimRight())
        .join('\n');
  }

  static String _escapeDocComment(String line) {
    return line
        .replaceAll('&', '&amp;') // must come first
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }
}
