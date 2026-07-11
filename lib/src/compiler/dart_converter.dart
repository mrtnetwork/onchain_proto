import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:onchain_proto/src/compiler/type_location.dart';
import 'package:onchain_proto/src/compiler/type_mapper.dart';
import 'package:onchain_proto/src/compiler/compiler.dart';
import 'package:onchain_proto/src/utils/utils.dart';
import 'package:onchain_proto/src/types/types.dart';

extension ProtoFileToDartProtoMessages on ProtoFile {
  ProtoConvertFileResult? toDartProtoMessages(
    ProtoCompiler resolver, {
    String? header,
    bool onlyRefrences = false,
  }) {
    if (onlyRefrences && !resolver.fileHasRefrence(this)) {
      return null;
    }
    final builder = resolver.builder;
    final buf = StringBuffer();
    if (header != null) {
      buf.writeln(header);
      buf.writeln();
    }
    final Set<ProtoTypeLocation> refrences = {};
    Set<String> imports = {...builder.defaultImports(this)};
    for (final i in imports) {
      buf.writeln("import '$i';");
    }
    final fileRefrences = refrenceMessages();
    Set<String> refrencesImport = {};
    for (final i in fileRefrences) {
      final import = OnChainProtoUtils.resolveTypeLocation(
        message: i,
        resolver: resolver,
        f: this,
      );
      if (import == null) continue;
      if (onlyRefrences && !resolver.refrenceExists(i)) {
        continue;
      }
      refrencesImport.add(import.importDirective());
      refrences.add(import);
    }

    for (final i in refrencesImport) {
      buf.writeln("import $i;");
    }
    buf.writeln();

    for (final e in enums) {
      final compile = e.toDartProtoEnum(resolver: resolver, onlyRefrences: onlyRefrences);
      if (compile == null) continue;
      buf.writeln(compile);
      buf.writeln();
    }
    List<ProtoConvertMessageResult> classNames = [];

    for (final m in messages) {
      final compile = m.toDartProtoMessage(
        resolver: resolver,
        syntax: syntax,
        importRefrences: refrences,
        onlyRefrences: onlyRefrences,
      );
      if (compile == null) continue;
      buf.writeln(compile.data);
      classNames.add(compile);
      buf.writeln();
    }

    return ProtoConvertFileResult(classInfo: classNames, generatedData: buf.toString());
  }
}

extension ProtoEnumToDartProtoEnum on ProtoEnum {
  /// Generates a Dart `enum` carrying `value` (proto wire int), `protoName`
  /// (original SCREAMING_SNAKE_CASE identifier), plus lookups:
  ///  - `fromValue(int)`      - matches `.value` only, throws if absent.
  ///  - `from(Object? value)` - matches `.value`, `.name`, or `.protoName`,
  ///    so it accepts whatever shape the caller has on hand (wire int,
  ///    Dart enum name, or the original proto string).
  String? toDartProtoEnum({required ProtoCompiler resolver, bool onlyRefrences = false}) {
    if (onlyRefrences && !resolver.enumHasRefrences(this)) {
      return null;
    }
    final dartName = OnChainProtoUtils.className(
      fullTypeName(),
      prefix: resolver.classNamePrefix,
    );
    final buf = StringBuffer();

    if (comments.isNotEmpty) {
      final c = OnChainProtoUtils.comment(comments);
      if (c != null) {
        buf.writeln(c);
      }
    }
    buf.writeln('enum $dartName implements ProtoEnumVariant {');

    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      final isLast = i == values.length - 1;
      if (v.comments.isNotEmpty) {
        final c = OnChainProtoUtils.comment(v.comments, indent: '  ');
        if (c != null) {
          buf.writeln('  $c');
        }
      }
      final dartValueName = OnChainProtoUtils.enumValueName(v.name);
      buf.writeln("  $dartValueName(${v.value}, '${v.name}')${isLast ? ';' : ','}");
    }
    // throw ItemNotFoundException(name: )

    buf.writeln();
    buf.writeln('  const $dartName(this.value, this.protoName);');
    buf.writeln();
    buf.writeln('  /// The original proto wire value for this enum constant.');
    buf.writeln('  @override');
    buf.writeln('  final int value;');
    buf.writeln();
    buf.writeln('  /// The original proto identifier, e.g. "VOTE_OPTION_UNSPECIFIED".');
    buf.writeln('  @override');
    buf.writeln('  final String protoName;');
    buf.writeln();
    buf.writeln('  /// Looks up a value by its proto wire int. Throws if not found.');
    buf.writeln('  static $dartName fromValue(int? value) {');
    buf.writeln('    return $dartName.values.firstWhere(');
    buf.writeln('      (e) => e.value == value,');
    buf.writeln(
      '      orElse: () => throw ItemNotFoundException(name:"$dartName", value: value)',
    );
    buf.writeln('    );');
    buf.writeln('  }');
    buf.writeln();
    buf.writeln('  /// Looks up a value by wire int, Dart enum name, or original proto');
    buf.writeln('  /// name (whichever [value] happens to be). Throws if not found.');
    buf.writeln('  static $dartName from(Object? value) {');
    buf.writeln('    return $dartName.values.firstWhere(');
    buf.writeln(
      '      (e) => e.value == value || e.name == value || e.protoName == value,',
    );
    buf.writeln(
      '      orElse: () => throw ItemNotFoundException(name:"$dartName", value: value)',
    );
    buf.writeln('    );');
    buf.writeln('  }');
    buf.writeln('}');

    return buf.toString();
  }
}

extension ProtoMessageToDartProtoMessage on ProtoMessage {
  ProtoConvertMessageResult? toDartProtoMessage({
    required ProtoSyntax syntax,
    required ProtoCompiler resolver,
    required Set<ProtoTypeLocation> importRefrences,
    bool onlyRefrences = false,
  }) {
    if (onlyRefrences && !resolver.messageHasRefrence(this)) {
      return null;
    }
    final dartName = OnChainProtoUtils.className(
      fullTypeName(),
      prefix: resolver.classNamePrefix,
    );
    final buf = StringBuffer();

    if (comments.isNotEmpty) {
      final c = OnChainProtoUtils.comment(comments);
      if (c != null) buf.writeln(c);
    }
    final mixins = resolver.builder.mixinsFor(this, resolver, importRefrences);
    buf.write('class $dartName extends ${resolver.builder.messageBaseClassName}');

    if (mixins.isNotEmpty) {
      buf.write(' with ${mixins.join(', ')}');
    }

    buf.writeln(' {');

    // ---- fields ----
    for (final f in fields) {
      String dartType = ProtoRuntimeTypeMapper.dartFieldType(
        type: f.type,
        optional: f.optional,
        resolver: resolver,
        importRefrences: importRefrences,
        required: f.required,
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
    if (fields.isEmpty) {
      buf.writeln('  const $dartName();');
    } else {
      buf.writeln('  const $dartName({');
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

        if (isNullable) {
          buf.writeln('    this.$dartFieldName,');
        } else if (defaultExpr != null) {
          buf.writeln('    this.$dartFieldName = $defaultExpr,');
        } else {
          buf.writeln('    required this.$dartFieldName,');
        }
      }
      buf.writeln('  });');
    }
    buf.writeln();
    final config = resolver.builder.buildConfigMembers(this, resolver, syntax);
    buf.writeln(config);
    final toJson = resolver.builder.buildToJson(this, resolver);
    if (toJson != null) {
      buf.writeln(toJson);
    }
    final fromJson = resolver.builder.buildFromJson(
      this,
      resolver,
      dartName,
      importRefrences,
    );
    if (fromJson != null) {
      buf.writeln(fromJson);
    }
    final deserialize = resolver.builder.buildDeserialize(
      this,
      resolver,
      dartName,
      importRefrences,
    );
    if (deserialize != null) {
      buf.writeln(deserialize);
    }
    final data = resolver.builder.buildExtraMembers(this, resolver, importRefrences);
    if (data != null) {
      buf.writeln(data);
    }
    buf.writeln('}');

    return ProtoConvertMessageResult(
      data: buf.toString(),
      className: dartName,
      message: this,
    );
  }
}

/// Renders [ProtoOption] lists/values as Dart source literals, used for
/// both message-level `options:` and field-level `options:` in
/// `protoConfigStatic()`.
abstract final class ProtoOptionRenderer {
  static String renderList(List<ProtoOption> options) {
    if (options.isEmpty) return 'const []';
    final items = options.map((e) => e.stringify()).join(', ');
    return '[$items]';
  }
}
