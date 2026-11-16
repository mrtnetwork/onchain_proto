/// Pure-Dart Candid `.did` → types + service method generator.
///
///   dart run tool/did_gen/generate.dart interfaces/ --out-dir lib/services \
///     --did-name="ICRC-7:ICRC7,icp_ledger:IcpLedger" \
///     --types-import "package:candid_test/candid_test.dart" \
///     --services-import "package:candid_test/candid_test.dart"
library;

import 'dart:io';

import 'did_emitter.dart';
import 'did_parser.dart';
import 'service_emitter.dart';

List<String> _splitImports(String? raw) {
  if (raw == null || raw.trim().isEmpty) return [];
  return raw
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

/// Parse `--did-name="ICRC-7:ICRC19,foo:Bar"` → `{ 'ICRC-7': 'ICRC19', 'foo': 'Bar' }`.
Map<String, String> _parseDidNames(String? raw) {
  final map = <String, String>{};
  if (raw == null || raw.trim().isEmpty) return map;
  for (final part in raw.split(',')) {
    final p = part.trim();
    if (p.isEmpty) continue;
    final idx = p.indexOf(':');
    if (idx <= 0 || idx >= p.length - 1) {
      stderr.writeln('Invalid --did-name entry (want stem:Prefix): $p');
      exit(64);
    }
    final stem = p.substring(0, idx).trim();
    final prefix = p.substring(idx + 1).trim();
    map[stem] = prefix;
  }
  return map;
}

/// Default prefix from file stem: `ICRC-7` → `ICRC7`, `icp_ledger` → `IcpLedger`.
String _prefixFromStem(String stem) {
  // Keep runs of alphanumerics; capitalize each run.
  final parts = stem
      .split(RegExp(r'[^0-9A-Za-z]+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return 'Did';
  // All-lowercase single token → full uppercase (ic → IC).
  if (parts.length == 1 && parts[0] == parts[0].toLowerCase()) {
    return parts[0].toUpperCase();
  }
  return parts.map((p) {
    if (p == p.toUpperCase() && p.length > 1) return p; // keep ICRC
    return p[0].toUpperCase() + p.substring(1);
  }).join();
}

/// Folder / library file name from prefix: `ICRC7` → `icrc7`.
String _folderName(String prefix) {
  return prefix.toLowerCase();
}

String _emitGeneratorUtils(List<String> typesImports) {
  final buf = StringBuffer();
  buf.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
  buf.writeln();
  buf.writeln("import 'package:blockchain_utils/blockchain_utils.dart';");
  for (final imp in typesImports) {
    final path = imp.trim();
    if (path.isEmpty) continue;
    buf.writeln("import '$path';");
  }
  buf.writeln();
  buf.writeln(
    '/// Shared helpers for generated Candid types (principal parse, etc.).',
  );
  buf.writeln('abstract final class GeneratorParserUtils {');
  buf.writeln(
    '  /// Convert a decoded Candid principal value to [IcpPrincipalAddress].',
  );
  buf.writeln('  static IcpPrincipalAddress principalFromCandid(dynamic e) {');
  buf.writeln('    if (e is IcpPrincipalAddress) return e;');
  buf.writeln('    if (e is String) return IcpPrincipalAddress(e);');
  buf.writeln(
    '    if (e is List<int>) return IcpPrincipalAddress.fromBytes(e);',
  );
  buf.writeln('    try {');
  buf.writeln('      final b = (e as dynamic).bytes;');
  buf.writeln(
    '      if (b is List<int>) return IcpPrincipalAddress.fromBytes(b);',
  );
  buf.writeln('    } catch (_) {}');
  buf.writeln('    throw ArgumentException.invalidOperationArguments(');
  buf.writeln("      'GeneratorParserUtils.principalFromCandid',");
  buf.writeln("      reason: 'Expected principal, got \${e.runtimeType}',");
  buf.writeln('    );');
  buf.writeln('  }');
  buf.writeln('}');
  return buf.toString();
}

void generateCandid(List<String> args) {
  if (args.isEmpty || args.contains('-h') || args.contains('--help')) {
    stderr.writeln('''
Generate Candid types and service method classes from .did files.

  dart run tool/did_gen/generate.dart <input.did|dir> [options]

Options:
  -o, --output FILE              Write types only into one Dart file
  --out-dir DIR                  Write per-did packages under DIR
  --did-name MAP                 Comma-separated stem:Prefix overrides
                                 e.g. --did-name="ICRC-7:ICRC7,ledger:IcpLedger"
                                 Default prefix is derived from the .did file name
                                 (ICRC-7.did → ICRC7, icp_ledger.did → IcpLedger)
  --service-query-class NAME     Base class for queries (default: IQueryService)
  --service-update-class NAME    Base class for updates (default: IUpdateService)
  --types-import IMPORTS         Comma-separated imports for types.dart
  --services-import IMPORTS      Comma-separated imports for queries/updates
                                 (also accepts --queries-import as alias)
  --types-only                   Skip service method generation
  -h, --help                     Show this help

Output layout (per .did file):
  <out-dir>/<prefix_lower>/
    <prefix_lower>.dart          // export 'src/types.dart'; ...
    src/types.dart
    src/queries.dart             // if any query methods
    src/updates.dart             // if any update methods

All generated classes are prefixed with the did name prefix, e.g. ICRC7Account,
ICRC7QueryMessage, ICRC7Transfer.
''');
    exit(args.isEmpty ? 64 : 0);
  }

  String? outputFile;
  String? outDir;
  var queryBase = 'IQueryService';
  var updateBase = 'IUpdateService';
  var typesOnly = false;
  String? typesImportRaw;
  String? servicesImportRaw;
  String? didNameRaw;
  final inputs = <String>[];

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '-o' || a == '--output') {
      outputFile = args[++i];
    } else if (a == '--out-dir') {
      outDir = args[++i];
    } else if (a == '--did-name') {
      didNameRaw = args[++i];
    } else if (a == '--class-prefix' || a == '--service-prefix') {
      stderr.writeln(
        'Removed option $a — use --did-name="stem:Prefix" (or file-name default).',
      );
      exit(64);
    } else if (a == '--service-query-class') {
      queryBase = args[++i];
    } else if (a == '--service-update-class') {
      updateBase = args[++i];
    } else if (a == '--types-import') {
      typesImportRaw = args[++i];
    } else if (a == '--services-import' || a == '--queries-import') {
      servicesImportRaw = args[++i];
    } else if (a == '--types-only') {
      typesOnly = true;
    } else if (!a.startsWith('-')) {
      inputs.add(a);
    }
  }

  final typesImports = _splitImports(typesImportRaw);
  final servicesImports = _splitImports(servicesImportRaw);
  final didNames = _parseDidNames(didNameRaw);

  if (inputs.isEmpty) {
    stderr.writeln('No input .did file or directory given.');
    exit(64);
  }

  final didFiles = <File>[];
  for (final path in inputs) {
    final entity = FileSystemEntity.typeSync(path);
    if (entity == FileSystemEntityType.directory) {
      didFiles.addAll(
        Directory(path)
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.did')),
      );
    } else if (entity == FileSystemEntityType.file) {
      didFiles.add(File(path));
    } else {
      stderr.writeln('Not found: $path');
      exit(66);
    }
  }

  if (didFiles.isEmpty) {
    stderr.writeln('No .did files found.');
    exit(66);
  }

  if (outDir != null) {
    final root = Directory(outDir);
    root.createSync(recursive: true);

    // Single shared utils for the whole generate run.
    final utilsDir = Directory('${root.path}/utils');
    utilsDir.createSync(recursive: true);
    final utilsFile = File('${utilsDir.path}/utils.dart');
    utilsFile.writeAsStringSync(_emitGeneratorUtils(typesImports));
    stdout.writeln('Wrote ${utilsFile.path}');
    // From <pkg>/src/*.dart → ../../utils/utils.dart
    const utilsImport = '../../utils/utils.dart';

    for (final f in didFiles) {
      final stem = f.uri.pathSegments.last.replaceAll('.did', '');
      final namePrefix = didNames[stem] ?? _prefixFromStem(stem);
      final folder = _folderName(namePrefix);
      final source = f.readAsStringSync();
      final ast = DidParser.parse(source);

      final packageDir = Directory('${root.path}/$folder');
      final srcDir = Directory('${packageDir.path}/src');
      srcDir.createSync(recursive: true);

      final de = DidEmitter(
        ast,
        namePrefix: namePrefix,
        typesImports: typesImports,
        utilsImport: utilsImport,
      );
      final typesCode = de.emit();
      final typesFile = File('${srcDir.path}/types.dart');
      typesFile.writeAsStringSync(typesCode);
      stdout.writeln('Wrote ${typesFile.path}');

      var wroteQueries = false;
      var wroteUpdates = false;

      if (!typesOnly) {
        final se = ServiceEmitter(
          ast,
          namePrefix: namePrefix,
          queryBaseClass: queryBase,
          updateBaseClass: updateBase,
          servicesImports: servicesImports,
          syntheticUsages: de.syntheticUsages,
          utilsImport: utilsImport,
        );

        final queries = se.emitQueries();
        if (queries.trim().isNotEmpty) {
          final qFile = File('${srcDir.path}/queries.dart');
          qFile.writeAsStringSync(queries);
          stdout.writeln('Wrote ${qFile.path}');
          wroteQueries = true;
        }

        final updates = se.emitUpdates();
        if (updates.trim().isNotEmpty) {
          final uFile = File('${srcDir.path}/updates.dart');
          uFile.writeAsStringSync(updates);
          stdout.writeln('Wrote ${uFile.path}');
          wroteUpdates = true;
        }
      }

      // Barrel export
      final barrel = StringBuffer();
      barrel.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
      barrel.writeln("export 'src/types.dart';");
      if (wroteQueries) barrel.writeln("export 'src/queries.dart';");
      if (wroteUpdates) barrel.writeln("export 'src/updates.dart';");
      final barrelFile = File('${packageDir.path}/$folder.dart');
      barrelFile.writeAsStringSync(barrel.toString());
      stdout.writeln('Wrote ${barrelFile.path} (prefix=$namePrefix)');
    }
  } else {
    final buf = StringBuffer();
    var first = true;
    for (final f in didFiles) {
      final stem = f.uri.pathSegments.last.replaceAll('.did', '');
      final namePrefix = didNames[stem] ?? _prefixFromStem(stem);
      final code = DidEmitter(
        DidParser.parse(f.readAsStringSync()),
        namePrefix: namePrefix,
        typesImports: typesImports,
      ).emit();
      if (first) {
        buf.write(code);
        first = false;
      } else {
        final lines = code.split('\n');
        final start = lines.indexWhere(
          (l) =>
              l.startsWith('final class') ||
              l.startsWith('sealed class') ||
              l.startsWith('typedef') ||
              l.startsWith('///'),
        );
        buf.writeln();
        buf.write(lines.skip(start < 0 ? 0 : start).join('\n'));
      }
    }
    final outPath = outputFile ?? 'generated_candid_types.dart';
    File(outPath).writeAsStringSync(buf.toString());
    stdout.writeln('Wrote $outPath (${didFiles.length} did file(s))');
  }
}
