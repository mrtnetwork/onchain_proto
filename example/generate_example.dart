// Example: generate Dart models from the bundled OpenAPI + Candid specs.
//
// Run from the package root:
//
//   dart run example/generate_example.dart
//
// Outputs (types only, no client wrappers):
//   example/generated/<stem>/types.dart
import 'package:onchain_proto/open_api/openapi_generator.dart' show generate;
import 'package:onchain_proto/did_gen/did.dart' show generateCandid;

class _Spec {
  final String stem;
  final String file;
  final String prefix;
  const _Spec(this.stem, this.file, this.prefix);
}

const _specs = [
  _Spec('changenow', 'changenow_openapi.json', 'ChangeNow'),
  _Spec('inch', 'inch_openapi.json', 'Inch'),
  _Spec('jupiter', 'jup_openapi.json', 'Jupiter'),
];

void main(List<String> argv) {
  final only = argv.isEmpty ? null : argv.toSet();
  var failed = 0;

  for (final s in _specs) {
    if (only != null && !only.contains(s.stem)) continue;
    try {
      generate([
        'example/specs/openapi/${s.file}',
        '-o',
        'example/generated/${s.stem}/types.dart',
        '--prefix',
        s.prefix,
      ]);
      print('OK ${s.stem}');
    } catch (e) {
      failed++;
      print('FAIL ${s.stem}: $e');
    }
  }

  // Candid (.did) example: types only for two small ICP specs.
  try {
    generateCandid([
      'example/specs/did',
      '--out-dir',
      'example/generated/did',
      '--service-query-class',
      'IQueryService',
      '--service-update-class',
      'IUpdateService',
      '--types-only',
    ]);
    print('OK did');
  } catch (e) {
    failed++;
    print('FAIL did: $e');
  }

  if (failed > 0) {
    print('$failed spec(s) failed to generate');
  }
}
