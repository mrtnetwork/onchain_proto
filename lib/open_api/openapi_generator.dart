// onchain_proto unified OpenAPI (3.x) + OpenRPC (1.x) JSON -> Dart generator.
//
// Conventions:
//   - string / oneOf / anyOf "enums" of primitive constants -> real `enum`
//   - oneOf/anyOf of objects/tagged variants -> sealed class hierarchies
//   - object schemas -> immutable classes
//   - primitive aliases -> typedefs
//   - fromJson uses blockchain_utils ExtJSONHelper:
//       package:blockchain_utils/utils/json/extension/json.dart
// OpenRPC documents are normalized via `openrpcToOpenapi` first, then go
// through the same OpenAPI pipeline (one request-wrapper class per method).
//
// Usage:
//   dart run package:onchain_proto/open_api/openapi_generator.dart openapi.json -o generated/models.dart

import 'dart:convert';
import 'dart:io';

// ---------------------------------------------------------------------------
// Naming helpers
// ---------------------------------------------------------------------------

const Set<String> dartReserved = {
  'abstract',
  'as',
  'assert',
  'async',
  'await',
  'base',
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
  'sealed',
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
  'when',
  'with',
  'while',
  'yield',
};

const Set<String> dartBuiltins = {
  'int',
  'double',
  'num',
  'bool',
  'String',
  'List',
  'Map',
  'Set',
  'Object',
  'Null',
  'dynamic',
};

const Set<String> enumReservedMembers = {
  'values',
  'index',
  'name',
  'hashCode',
  'runtimeType',
  'toString',
  'noSuchMethod',
};

/// lowerCamelCase (or UpperCamelCase if [capitalizeFirst]) version of
/// [name], splitting on any run of non-alphanumeric characters. If [name]
/// already has no separators (looks like it's already Camel/PascalCase),
/// just fixes the leading-case instead of re-splitting it.
String snakeToCamel(String name, {bool capitalizeFirst = false}) {
  final parts = name
      .split(RegExp(r'[^0-9A-Za-z]+'))
      .where((p) => p.isNotEmpty)
      .toList();

  if (parts.isEmpty) return 'value';

  String camel;

  if (capitalizeFirst) {
    camel = parts.map((p) => p[0].toUpperCase() + p.substring(1)).join();
  } else {
    camel = parts.first[0].toLowerCase() + parts.first.substring(1);

    camel += parts
        .skip(1)
        .map((p) => p[0].toUpperCase() + p.substring(1))
        .join();
  }

  if (dartReserved.contains(camel) || dartBuiltins.contains(camel)) {
    camel = '${camel}_';
  }

  if (RegExp(r'^[0-9]').hasMatch(camel)) {
    camel = 'n$camel';
  }

  return camel;
}
// String snakeToCamel(String name, {bool capitalizeFirst = false}) {
//   final parts =
//       name.split(RegExp(r'[^0-9A-Za-z]+')).where((p) => p.isNotEmpty).toList();
//   if (parts.isEmpty) return 'value';
//   String camel;
//   if (capitalizeFirst) {
//     camel =
//         parts
//             .map((p) => p.substring(0, 1).toUpperCase() + p.substring(1))
//             .join();
//   } else {
//     final first = parts.first;
//     camel =
//         first.substring(0, 1).toLowerCase() +
//         first.substring(1) +
//         parts
//             .skip(1)
//             .map((p) => p.substring(0, 1).toUpperCase() + p.substring(1))
//             .join();
//   }
//   if (!name.contains('_') && !name.contains('-') && !name.contains(' ')) {
//     if (name.isNotEmpty) {
//       camel =
//           capitalizeFirst
//               ? name.substring(0, 1).toUpperCase() + name.substring(1)
//               : name.substring(0, 1).toLowerCase() + name.substring(1);
//     }
//   }
//   if (dartReserved.contains(camel) || dartBuiltins.contains(camel)) {
//     camel = '${camel}_';
//   }
//   if (camel.isNotEmpty && RegExp(r'^[0-9]').hasMatch(camel)) {
//     camel = 'n$camel';
//   }
//   return camel;
// }

/// PascalCase class name: splits on non-alphanumeric runs and
/// PascalCase-normalizes each piece (ALL-CAPS -> Titlecase, lowercase ->
/// capitalized, already-mixed-case left alone), so
/// "JsonRpcRequest_for_EXPERIMENTAL_receipt" becomes
/// "JsonRpcRequestForExperimentalReceipt" instead of keeping stray
/// underscores/shouting fragments.
String sanitizeClassName(String name) {
  final parts = name
      .split(RegExp(r'[^0-9A-Za-z]+'))
      .where((p) => p.isNotEmpty)
      .toList();
  String cleaned;
  if (parts.isEmpty) {
    cleaned = 'Generated';
  } else {
    final pieces = <String>[];
    for (final p in parts) {
      if (p == p.toUpperCase() && p.length > 1) {
        pieces.add(p.substring(0, 1) + p.substring(1).toLowerCase());
      } else if (RegExp(r'^[a-z0-9]').hasMatch(p)) {
        pieces.add(p.substring(0, 1).toUpperCase() + p.substring(1));
      } else {
        pieces.add(p);
      }
    }
    cleaned = pieces.join();
  }
  if (cleaned.isEmpty) cleaned = 'Generated';
  if (RegExp(r'^[0-9]').hasMatch(cleaned)) cleaned = 'N$cleaned';
  if (cleaned.isNotEmpty && RegExp(r'^[a-z]').hasMatch(cleaned)) {
    cleaned = cleaned.substring(0, 1).toUpperCase() + cleaned.substring(1);
  }
  if (dartReserved.contains(cleaned) || dartBuiltins.contains(cleaned)) {
    // Trailing underscore breaks the UpperCamelCase lint; use a Value suffix.
    cleaned = '${cleaned}Value';
  }
  return cleaned;
}

String sanitizeFieldName(String name) =>
    snakeToCamel(name, capitalizeFirst: false);

/// SCREAMING_SNAKE/kebab tag -> PascalCase suffix appended to [parent] to
/// name a union variant class.
String variantClassName(String parent, String tag) {
  var tagPart = sanitizeClassName(snakeToCamel(tag, capitalizeFirst: true));
  if (tagPart == tagPart.toUpperCase() && tagPart.length > 1) {
    tagPart = tagPart.substring(0, 1) + tagPart.substring(1).toLowerCase();
    tagPart = sanitizeClassName(tagPart);
  }
  return '$parent$tagPart';
}

String indentText(String text, [int spaces = 2]) {
  final pad = ' ' * spaces;
  return text.split('\n').map((l) => l.isEmpty ? l : '$pad$l').join('\n');
}

String refName(String ref) => ref.split('/').last;

/// Normalizes a JSON Schema `type` keyword to a single scalar type name.
///
/// OpenAPI 3.0 uses `"type": "string"` plus a separate `"nullable": true`
/// flag. OpenAPI 3.1 / JSON Schema instead allows `"type": ["string", "null"]`.
/// This collapses the array form down to the single non-null type so the
/// rest of the generator (which only ever compares against a bare string)
/// keeps working for both styles. Returns null if `type` is absent, or if
/// it's an array of only `"null"`.
String? primaryType(dynamic schemaType) {
  if (schemaType is String) return schemaType;
  if (schemaType is List) {
    final nonNull = schemaType.whereType<String>().where((t) => t != 'null');
    if (nonNull.isEmpty) return null;
    return nonNull.first;
  }
  return null;
}

/// True if a JSON Schema `type` keyword (string or array form) includes `null`.
bool typeIncludesNull(dynamic schemaType) {
  if (schemaType is String) return schemaType == 'null';
  if (schemaType is List) return schemaType.contains('null');
  return false;
}

bool isNullSchema(dynamic schema) {
  if (schema == null) return true;
  if (schema is! Map) return false;
  if (schema['type'] == 'null') return true;
  final enumVal = schema['enum'];
  if (enumVal is List && enumVal.length == 1 && enumVal[0] == null) return true;
  return false;
}

/// True if [v] looks like a Tezos protocol id (Base58 Proto… / Ps… / Pt…).
bool looksLikeProtocolId(dynamic v) {
  if (v is! String || v.isEmpty) return false;
  return RegExp(r'^P(roto|[st])[1-9A-HJ-NP-Za-km-z]+').hasMatch(v);
}

bool isUnitNullEnum(dynamic schema) {
  if (schema is! Map) return false;
  final enumVal = schema['enum'];
  final isNullEnum =
      enumVal is List && enumVal.length == 1 && enumVal[0] == null;
  if (isNullEnum) return true;
  if (schema['nullable'] == true && isNullEnum) return true;
  return false;
}

String jsonLiteral(dynamic v) => jsonEncode(v);

String escapeDartString(String s) =>
    s.replaceAll('\\', '\\\\').replaceAll("'", "\\'");

// ---------------------------------------------------------------------------
// Data classes
// ---------------------------------------------------------------------------

/// Resolved Dart type info for a schema (or property).
class TypeRef {
  String dartType;
  // kind: primitive | typedef | class | sealed | list | map | dynamic
  String kind;
  bool isNullable;
  TypeRef? item; // for list
  TypeRef? value; // for map
  // fromJsonMode: map | dynamic | string | int | num | double | bool |
  // bigint | bytes | list
  String fromJsonMode;

  /// When a typedef aliases a class/sealed type, [dartType] is the typedef
  /// name (used for field declarations) while [parseType] is the concrete
  /// name that actually has `.fromJson` / can be constructed.
  String? parseType;

  TypeRef(
    this.dartType, {
    this.kind = 'class',
    this.isNullable = false,
    this.item,
    this.value,
    this.fromJsonMode = 'map',
    this.parseType,
  });

  /// Name to use when calling `.fromJson` / constructing this type.
  String get effectiveParseType => parseType ?? dartType;

  bool get isDynamic => dartType == "dynamic";
  bool get isNullType => dartType == "Null";
}

class FieldInfo {
  String jsonKey;
  String dartName;
  TypeRef typeRef;
  bool optional;
  String description;
  // True when the source schema gave us nothing to go on at all (no
  // type/$ref/enum/oneOf/anyOf/allOf) — i.e. `dynamic` here isn't a
  // deliberate "anything goes" schema, it's us giving up.
  bool isAmbiguous;

  FieldInfo({
    required this.jsonKey,
    required this.dartName,
    required this.typeRef,
    required this.optional,
    this.description = '',
    this.isAmbiguous = false,
  });
}

class VariantInfo {
  String tag; // discriminator key or synthetic name
  String className;
  String kind; // string_const | tagged_object | object | primitive | ref
  dynamic constValue;
  // for tagged_object: the property key holding payload
  String? payloadKey;
  Map<String, dynamic>? payloadSchema;
  // for object: full schema
  Map<String, dynamic>? objectSchema;
  // for primitive
  String? primitiveType;
  // for ref
  String? refType;
  // for ref: classification (kind) of the referenced schema itself
  String? refKind;
  String? title;
  // for "object" variants: a property name/value that reliably
  // distinguishes this variant from sibling variants.
  String? discriminatorKey;
  dynamic discriminatorValue;

  /// AND-combined literal matches when a single key is not unique across
  /// siblings (e.g. kind=staking + category=delegator_numerator).
  List<MapEntry<String, dynamic>>? discriminatorLiterals;

  /// Required property names from the object schema (for match ranking).
  List<String> requiredKeys = const [];

  /// Property names present on this variant but not on any sibling object
  /// variant — used when primary discriminators collide.
  List<String> exclusiveKeys = const [];
  // Presence-based discriminator when variants share required keys but
  // differ by an optional (or nested) property. [presencePath] is a list of
  // steps from the root map: plain property names, or `[]` meaning "first
  // element of the array at the previous step". Example:
  //   ['contents', '[]', 'metadata'] → contents[0].metadata
  // [presencePositive] true → key must be present; false → must be absent.
  List<String>? presencePath;
  bool presencePositive = true;
  // set instead when this variant shares the exact same required fields
  // with one or more siblings and no distinguishing literal value could be
  // found — genuinely structurally ambiguous.
  List<String>? ambiguousWith;

  /// Anchored pattern-prefix pins (`pattern: "^ed25519:"` → startsWith
  /// "ed25519:") used as a last-resort tiebreaker when siblings share the
  /// same required keys and the same (or no) literal pins. Entries are
  /// (property, literal prefix) pairs AND-combined in match guards.
  List<MapEntry<String, String>>? patternGuards;

  VariantInfo({
    required this.tag,
    required this.className,
    required this.kind,
    this.constValue,
    this.payloadKey,
    this.payloadSchema,
    this.objectSchema,
    this.primitiveType,
    this.refType,
    this.refKind,
    this.title,
    this.discriminatorKey,
    this.discriminatorValue,
    this.discriminatorLiterals,
    this.requiredKeys = const [],
    this.exclusiveKeys = const [],
    this.presencePath,
    this.presencePositive = true,
    this.ambiguousWith,
    this.patternGuards,
  });
}

class BodyPlan {
  String kind; // none | plain | json_rpc
  String? jsonRpcMethod;
  TypeRef? paramTypeRef;

  BodyPlan({required this.kind, this.jsonRpcMethod, this.paramTypeRef});
}

class ClientParamInfo {
  String dartName;
  String jsonName;
  TypeRef typeRef;
  bool required;
  String location; // "path" | "query"
  /// Optional default for constructor (from openapi base_path.default_args).
  String? defaultValue;

  ClientParamInfo({
    required this.dartName,
    required this.jsonName,
    required this.typeRef,
    required this.required,
    required this.location,
    this.defaultValue,
  });
}

// ---------------------------------------------------------------------------
// Small dynamic-JSON helpers (jsonDecode gives Map<String, dynamic> with
// dynamic values; nested objects are also Map<String, dynamic>, nested
// arrays are List<dynamic> — these helpers just do safe casts/dispatch).
// ---------------------------------------------------------------------------

Map<String, dynamic> asMap(dynamic v) {
  if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
  return <String, dynamic>{};
}

Map<String, dynamic>? asMapOrNull(dynamic v) {
  if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
  return null;
}

List<dynamic> asList(dynamic v) => v is List ? v : <dynamic>[];

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------

class OpenApiToDart {
  final Map<String, dynamic> openapi;
  final String packageImport;
  final RegExp? excludeRe;

  /// Optional prefix prepended to every generated model type name
  /// (e.g. `Algo` → `AlgoAccount`). Empty/null = no prefix.
  final String classPrefix;

  /// Optional prefix for generated client request-wrapper class names.
  /// When null/empty, falls back to the base [clientClass] name.
  final String clientPrefix;

  late final Map<String, dynamic> schemas;
  final Map<String, String> generated = {}; // class/typedef name -> source
  final Set<String> emitted = {};
  final Set<String> inProgress = {};
  int _inlineCounter = 0;
  final Map<String, String> kindOf = {}; // schema name -> classification
  final Set<String> sealedNames = {};
  final Set<String> typedefNames = {};
  final Set<String> classNames = {};
  final Map<String, String> typedefTarget = {};
  // structural dedupe cache: (kind, canonical-schema-json) -> TypeRef
  final Map<String, TypeRef> _inlineCache = {};
  // generated sealed-union name -> the (possibly already-merged) raw
  // oneOf/anyOf schema currently backing it. Lets a later near-duplicate
  // union that wants the same name widen this one instead of minting a
  // second, confusingly-numbered sealed class. See _tryMergeUnionSchemas.
  final Map<String, Map<String, dynamic>> _unionMergedSchema = {};
  // original schema name -> ["GET /path (request|response)", ...]
  final Map<String, List<String>> endpointUsage = {};

  final Set<String> nullableTypedefs = {};

  /// From openapi root `base_path`:
  /// ```json
  /// "base_path": { "path": "/{block_id}/", "default_args": ["head"] }
  /// ```
  /// Prefixed onto every operation path; placeholders become String fields
  /// on every client request class (with constructor defaults when given).
  String? _basePathTemplate;
  List<String> _basePathDefaults = const [];

  /// Transport path of the generic JSON-RPC operation skipped in
  /// `--client-json-rpc` mode (e.g. `/api/v2/jsonRPC`), reused as the
  /// `path` of every generated jsonRPC class. Null when the spec declares
  /// no such operation.
  String? jsonRpcTransportPath;

  /// toJson config: `{Type config = Type.defaultConfig}`. Defaults to the
  /// [JsonifyConfig] contract with [DefaultJsonifyConfig.defaultConfig];
  /// `--json-config Name:URI` switches to a custom config (imported from
  /// URI, must implement JsonifyConfig and expose a static const
  /// `defaultConfig`).
  String jsonConfigType;
  String jsonConfigDefault;
  String? jsonConfigImport;

  /// `{Type config = Type.defaultConfig}` parameter fragment for every
  /// generated `toJson`.
  String get _toJsonParams => '{$jsonConfigType config = $jsonConfigDefault}';

  /// Client emitter knobs (all default to the historical output shape):
  ///
  /// - [clientPathMember]: getter name for the endpoint URL (`path`).
  ///   Non-default names emit a non-nullable getter (a custom member name
  ///   implies a strict base contract; the URL itself is always static).
  /// - [clientPathParams]: `inline` substitutes `{x}` into the URL;
  ///   `list` keeps the `{x}` template and emits
  ///   `List<String> get pathParameters`.
  /// - [clientBodyGetter]: emit `Map? get body` instead of
  ///   `dynamic body({... config ...})`.
  /// - [clientMethodMember]: getter name for the JSON-RPC operation name
  ///   (`jsonRpcMethd`, only for json_rpc body plans).
  /// - [clientJsonRpc]: emit JSON-RPC-shaped clients (`jsonRpcMethod` +
  ///   config-driven `body()` + `onResponse` — `jsonRpcMethod` only on
  ///   JSON-RPC-style requests; the hand-written `buildRequest` owns
  ///   transport, e.g. ton_dart's `TonCenterPostRequest`).
  /// - [clientResultMap]: per-operation RESULT type overrides
  ///   (`{lookupKey: DartType}`); lookup tries operationId, then
  ///   `"METHOD path"`, then (jsonRpc mode) the bare method name.
  String clientPathMember;
  String clientPathParams;
  bool clientBodyGetter;
  String clientMethodMember;
  bool clientJsonRpc;
  Map<String, String> clientResultMap;
  Set<String> clientExclude;
  bool clientConstCtors;
  String? clientParent;
  String? clientDetails;
  // Base class for operations WITH a body member (`--client-post-base`,
  // e.g. a POST base with `body` support). Defaults to [clientClass].
  // Lets one generation run cover GETs (base) and POSTs (post base), e.g.
  // ton_dart's TonApiRequest / TonApiPostRequest split.
  String? clientPostBase;

  /// Set while [generateClientRequests] runs when some request's RESULT type
  /// collides with its own wrapper name (addressed as `models.X`): the
  /// client file header must then also import the models file as `models`.
  /// Reset at the start of every [generateClientRequests] run.
  bool clientNeedsModelsImport = false;

  OpenApiToDart(
    this.openapi, {
    this.packageImport =
        'package:blockchain_utils/utils/json/extension/json.dart',
    String? excludePattern,
    String? classPrefix,
    String? clientPrefix,
    this.jsonConfigType = 'JsonifyConfig',
    this.jsonConfigDefault = 'DefaultJsonifyConfig.defaultConfig',
    this.jsonConfigImport,
    this.clientPathMember = 'path',
    this.clientPathParams = 'inline',
    this.clientBodyGetter = false,
    this.clientMethodMember = 'jsonRpcMethd',
    this.clientJsonRpc = false,
    this.clientResultMap = const {},
    this.clientExclude = const {},
    this.clientParent,
    this.clientDetails,
    this.clientConstCtors = true,
    this.clientPostBase,
  }) : excludeRe = excludePattern != null ? RegExp(excludePattern) : null,
       classPrefix = (classPrefix ?? '').trim(),
       clientPrefix = (clientPrefix ?? '').trim() {
    final components = asMap(openapi['components']);
    final componentSchemas = asMap(components['schemas']);
    schemas = componentSchemas.isNotEmpty
        ? componentSchemas
        : asMap(openapi['definitions']);
    _parseBasePath();
    _buildEndpointUsage();
  }

  void _parseBasePath() {
    final bp = asMapOrNull(openapi['base_path']);
    if (bp == null) return;
    final p = bp['path'];
    if (p is! String || p.isEmpty) return;
    _basePathTemplate = p;
    final defaults = bp['default_args'];
    if (defaults is List) {
      _basePathDefaults = [for (final d in defaults) d?.toString() ?? ''];
    }
  }

  /// Path placeholders in order, e.g. `/{block_id}/` → `['block_id']`.
  List<String> _basePathPlaceholderNames() {
    final tmpl = _basePathTemplate;
    if (tmpl == null) return const [];
    return [
      for (final m in RegExp(r'\{([^{}]+)\}').allMatches(tmpl)) m.group(1)!,
    ];
  }

  /// Client params for base_path placeholders (String, optional default).
  List<ClientParamInfo> _basePathParams() {
    final names = _basePathPlaceholderNames();
    final out = <ClientParamInfo>[];
    for (var i = 0; i < names.length; i++) {
      final jsonName = names[i];
      final def =
          i < _basePathDefaults.length && _basePathDefaults[i].isNotEmpty
          ? _basePathDefaults[i]
          : null;
      out.add(
        ClientParamInfo(
          dartName: sanitizeFieldName(jsonName),
          jsonName: jsonName,
          typeRef: TypeRef('String', kind: 'primitive', fromJsonMode: 'string'),
          // Has a default → not required in the ctor sense.
          required: def == null,
          location: 'path',
          defaultValue: def,
        ),
      );
    }
    return out;
  }

  /// Join base_path template with an operation path, normalizing slashes.
  String _applyBasePath(String operationPath) {
    final base = _basePathTemplate;
    if (base == null || base.isEmpty) return operationPath;
    var left = base;
    var right = operationPath;
    if (left.endsWith('/') && right.startsWith('/')) {
      right = right.substring(1);
    } else if (!left.endsWith('/') &&
        !right.startsWith('/') &&
        right.isNotEmpty) {
      left = '$left/';
    }
    final joined = '$left$right';
    // collapse accidental // (but keep leading /)
    return joined.replaceAll(RegExp(r'(?<!:)/{2,}'), '/');
  }

  /// Schema / inline type name with optional [classPrefix] applied.
  String _dartName(String name) {
    final base = sanitizeClassName(name);
    if (classPrefix.isEmpty) return base;
    final pref = sanitizeClassName(classPrefix);
    if (base.startsWith(pref)) return base;
    return '$pref$base';
  }

  /// Path/operationId → PascalCase token used for response/body/params type
  /// hints and client request class suffixes, e.g. `/v2/teal/disassemble`
  /// → `V2TealDisassemble`.
  String _pathTypeBase(
    String path,
    String method,
    Map<String, dynamic> operation, {
    bool stripApiPrefix = false,
  }) {
    final opId = operation['operationId'];
    if (opId is String && opId.isNotEmpty) {
      var id = opId;
      if (stripApiPrefix) {
        // `api_v3_get_account_states` mirrors the `/api/v3/` URL prefix, not
        // a real name part — drop it for concise client class names.
        id = id.replaceFirst(RegExp(r'^api(_v[0-9]+)?_'), '');
        if (id.isEmpty) id = opId;
      }
      return sanitizeClassName(id);
    }
    final raw = path
        .replaceAll(RegExp(r'[{}]'), '')
        .replaceAll(RegExp(r'^/+|/+$'), '');
    return sanitizeClassName(raw.isEmpty ? 'Root' : raw);
  }

  bool _isExcluded(String name) =>
      excludeRe != null && excludeRe!.hasMatch(name);

  void _buildEndpointUsage() {
    final paths = asMap(openapi['paths']);
    const httpMethods = {
      'get',
      'post',
      'put',
      'patch',
      'delete',
      'options',
      'head',
    };
    for (final pathEntry in paths.entries) {
      final path = pathEntry.key;
      final pathItem = asMapOrNull(pathEntry.value);
      if (pathItem == null) continue;
      for (final opEntry in pathItem.entries) {
        final method = opEntry.key;
        if (!httpMethods.contains(method.toLowerCase())) continue;
        final op = asMapOrNull(opEntry.value);
        if (op == null) continue;
        final verb = method.toUpperCase();
        final rb = asMapOrNull(op['requestBody']);
        if (rb != null) {
          for (final content in asMap(rb['content']).values) {
            final c = asMapOrNull(content);
            if (c != null) {
              _recordEndpointUsage(c['schema'], path, verb, 'request');
            }
          }
        }
        final responses = asMap(op['responses']);
        for (final resp in responses.values) {
          final r = asMapOrNull(resp);
          if (r == null) continue;
          for (final content in asMap(r['content']).values) {
            final c = asMapOrNull(content);
            if (c != null) {
              _recordEndpointUsage(c['schema'], path, verb, 'response');
            }
          }
        }
      }
    }
  }

  void _recordEndpointUsage(
    dynamic schema,
    String path,
    String verb,
    String kind,
  ) {
    final s = asMapOrNull(schema);
    if (s == null) return;
    final ref = s['\$ref'];
    if (ref is! String) return;
    final name = refName(ref);
    final label = '$verb $path ($kind)';
    final bucket = endpointUsage.putIfAbsent(name, () => <String>[]);
    if (!bucket.contains(label)) bucket.add(label);
  }

  // ---- public API ----

  /// Ensure every component schema is generated, in sorted order, so model
  /// classes exist under their canonical names before client request
  /// generation runs (client response/body hints then reuse those classes
  /// instead of minting client-driven inline duplicates).
  void ensureAllSchemas() {
    for (final name in schemas.keys.toList()..sort()) {
      _ensureSchema(name);
    }
  }

  String generateAll() {
    for (final entry in schemas.entries) {
      kindOf[entry.key] = _classify(entry.value);
    }
    final names = schemas.keys.toList()..sort();
    for (final name in names) {
      _ensureSchema(name);
    }

    final infoMap = asMap(openapi['info']);
    final parts = <String>[
      '// GENERATED CODE - DO NOT MODIFY BY HAND',
      "// Source: OpenAPI ${openapi['openapi'] ?? openapi['swagger'] ?? ''}",
      "// ${infoMap['title'] ?? ''} ${infoMap['version'] ?? ''}".trimRight(),
      '//',
      '// toJson contract (config-driven): every `toJson` takes an optional',
      '// `$jsonConfigType` (`config`, default `$jsonConfigDefault`) and',
      '// returns the result through `config.encodeMap`, so `toJson` never',
      '// returns null — it always yields a Map.',
      '// BigInt / null handling is delegated to the config: `encodeBigint`',
      '// encodes BigInt values and `encodeMap` post-processes the map.',
      '// Make sure the configured output is `jsonEncode`-compatible: raw',
      '// BigInt values are rejected by `jsonEncode`, so either keep the',
      '// default string encoding or handle BigInt in your own encoder.',
      '',
      "import '$packageImport';",
      if (jsonConfigImport != null && jsonConfigImport != packageImport)
        "import '$jsonConfigImport';",
      '',
    ];

    final typedefs = <MapEntry<String, String>>[];
    final sealed = <MapEntry<String, String>>[];
    final classes = <MapEntry<String, String>>[];
    for (final entry in generated.entries) {
      if (typedefNames.contains(entry.key)) {
        typedefs.add(entry);
      } else if (sealedNames.contains(entry.key)) {
        sealed.add(entry);
      } else {
        classes.add(entry);
      }
    }
    // Component (spec `components/schemas`) types first — in schema-sorted
    // order — then client/inline-derived types. Types output must read as
    // the model's own declarations first, not the client wrappers' inline
    // response helpers.
    final compOrder = <String, int>{};
    var compIdx = 0;
    for (final n in schemas.keys.toList()..sort()) {
      compOrder[_dartName(n)] = compIdx++;
    }
    int emitOrder(MapEntry<String, String> e) => compOrder[e.key] ?? (1 << 30);
    for (final bucket in [typedefs, sealed, classes]) {
      bucket.sort((a, b) {
        final c = emitOrder(a).compareTo(emitOrder(b));
        return c != 0 ? c : a.key.compareTo(b.key);
      });
    }
    for (final b in typedefs) {
      parts.add(b.value);
      parts.add('');
    }
    for (final b in sealed) {
      parts.add(b.value);
      parts.add('');
    }
    for (final b in classes) {
      parts.add(b.value);
      parts.add('');
    }
    return '${parts.join('\n').trimRight()}\n';
  }

  List<File> generateSplit(Directory outDir) {
    outDir.createSync(recursive: true);
    final names = schemas.keys.toList()..sort();
    for (final name in names) {
      _ensureSchema(name);
    }
    final written = <File>[];
    final barrel = <String>['// GENERATED CODE - DO NOT MODIFY BY HAND', ''];
    final sortedGenerated = generated.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final entry in sortedGenerated) {
      var fileStem = entry.key
          .replaceAllMapped(RegExp(r'(?<!^)(?=[A-Z])'), (m) => '_')
          .toLowerCase();
      fileStem = fileStem.replaceAll(RegExp(r'[^a-z0-9_]+'), '_');
      final path = File('${outDir.path}/$fileStem.dart');
      final content =
          '// GENERATED CODE - DO NOT MODIFY BY HAND\n'
          "import '$packageImport';\n\n"
          '${entry.value.trimRight()}\n';
      path.writeAsStringSync(content);
      written.add(path);
      barrel.add("export '$fileStem.dart';");
    }
    final barrelPath = File('${outDir.path}/models.dart');
    barrelPath.writeAsStringSync('${barrel.join('\n')}\n');
    written.add(barrelPath);
    return written;
  }

  // ---- classification ----

  String _classify(dynamic schemaAny) {
    final schema = asMapOrNull(schemaAny);
    if (schema == null) return 'unknown';
    if (isUnitNullEnum(schema)) return 'null_unit';
    final enumVal = schema['enum'];
    final t = primaryType(schema['type']);
    if (enumVal is List &&
        (t == null || t == 'string' || t == 'integer' || t == 'number')) {
      // Any enum (string/int/mixed) becomes a real Dart `enum`.
      return 'string_enum';
    }
    if (schema.containsKey('oneOf') || schema.containsKey('anyOf')) {
      return 'union';
    }
    if (schema.containsKey('allOf')) {
      final pureRef = _allOfSingleRef(schema);
      if (pureRef != null) return 'ref_alias';
      final merged = _mergeAllOf(schema);
      if (merged['enum'] != null) return 'string_enum';
      final mergedType = primaryType(merged['type']);
      if ((mergedType == 'string' ||
              mergedType == 'integer' ||
              mergedType == 'number' ||
              mergedType == 'boolean') &&
          merged['properties'] == null) {
        return 'alias';
      }
      if (merged['properties'] != null || mergedType == 'object') {
        return 'object';
      }
      if (mergedType == 'array') return 'alias_array';
      return 'object';
    }
    if (t == 'array') return 'alias_array';
    if (t == 'string' || t == 'integer' || t == 'number' || t == 'boolean') {
      return 'alias';
    }
    if (t == 'object' || schema.containsKey('properties')) return 'object';
    if (schema.containsKey('\$ref')) return 'ref';
    return 'unknown';
  }

  /// If [schema] is essentially a $ref wrapper via allOf, return target name.
  String? _allOfSingleRef(Map<String, dynamic> schema) {
    final parts = asList(schema['allOf']);
    final refs = <String>[];
    var extras = false;
    for (final pAny in parts) {
      final p = asMapOrNull(pAny);
      if (p == null) {
        extras = true;
        continue;
      }
      final keys = p.keys.toSet();
      if (keys.difference({'\$ref', 'description', 'title'}).isEmpty &&
          p.containsKey('\$ref')) {
        refs.add(refName(p['\$ref'] as String));
      } else if (p.containsKey('allOf') && _allOfSingleRef(p) != null) {
        refs.add(_allOfSingleRef(p)!);
      } else {
        extras = true;
      }
    }
    if (refs.length == 1 && !extras) return refs.first;
    return null;
  }

  /// Shallow-merge allOf parts + sibling keys into one object schema.
  Map<String, dynamic> _mergeAllOf(Map<String, dynamic> schema) {
    final parts = asList(schema['allOf']);
    final merged = <String, dynamic>{
      for (final e in schema.entries)
        if (e.key != 'allOf') e.key: e.value,
    };
    final props = <String, dynamic>{...asMap(merged['properties'])};
    final required = <String>[...asList(merged['required']).cast<String>()];
    // A field-specific annotation sibling (an allOf part that is NOT
    // itself a bare $ref, e.g. `allOf: [{$ref: EntityId},
    // {description: "The account this account stakes to"}]`) should win
    // over the description/title inherited from the $ref'd part's target
    // schema — otherwise the generic ref-level text (e.g. EntityId's
    // "Network entity ID...") silently overwrites the more useful
    // per-field text just because the $ref part happens to be processed
    // first below.
    String? siblingDescription;
    String? siblingTitle;
    for (final partAny in parts) {
      final isRefPart = asMapOrNull(partAny)?.containsKey('\$ref') == true;
      var part = asMapOrNull(_resolve(partAny));
      if (part == null) continue;
      if (part.containsKey('allOf')) {
        part = _mergeAllOf(part);
      }
      if (part.containsKey('properties')) {
        props.addAll(asMap(part['properties']));
      }
      for (final r in asList(part['required'])) {
        if (r is String && !required.contains(r)) required.add(r);
      }
      if (!isRefPart) {
        if (part['description'] is String) {
          siblingDescription = part['description'] as String;
        }
        if (part['title'] is String) siblingTitle = part['title'] as String;
      }
      for (final e in part.entries) {
        if (e.key == 'properties' || e.key == 'required' || e.key == 'allOf') {
          continue;
        }
        if (!merged.containsKey(e.key)) merged[e.key] = e.value;
      }
    }
    if (siblingDescription != null) merged['description'] = siblingDescription;
    if (siblingTitle != null) merged['title'] = siblingTitle;
    if (props.isNotEmpty) merged['properties'] = props;
    if (required.isNotEmpty) merged['required'] = required;
    if (!merged.containsKey('type') && props.isNotEmpty) {
      merged['type'] = 'object';
    }
    return merged;
  }

  dynamic _resolve(dynamic schemaAny) {
    final schema = asMapOrNull(schemaAny);
    if (schema == null) return schemaAny;
    final ref = schema['\$ref'];
    if (ref is String) {
      final name = refName(ref);
      final target = schemas[name];
      if (target == null) return schema;
      final resolved = <String, dynamic>{...asMap(target)};
      for (final k in ['description', 'nullable', 'title']) {
        if (schema.containsKey(k) && !resolved.containsKey(k)) {
          resolved[k] = schema[k];
        }
      }
      return resolved;
    }
    return schema;
  }

  /// `$ref`) override the shared definition.
  Map<String, dynamic>? _resolveParameter(dynamic pAny) {
    final p = asMapOrNull(pAny);
    if (p == null) return null;
    final ref = p['\$ref'];
    if (ref is! String) return p;
    final name = refName(ref);
    final components = asMap(openapi['components']);
    final params = asMap(components['parameters']);
    var target = asMapOrNull(params[name]);
    // Swagger 2.0 global parameters live at the document root.
    target ??= asMapOrNull(asMap(openapi['parameters'])[name]);
    if (target == null) return p;
    final resolved = <String, dynamic>{...target};
    for (final e in p.entries) {
      if (e.key != '\$ref') resolved[e.key] = e.value;
    }
    return resolved;
  }

  List<Map<String, dynamic>> _mergedParameters(
    Map<String, dynamic> pathItem,
    Map<String, dynamic> operation,
  ) {
    final merged = <String, Map<String, dynamic>>{};
    for (final pAny in asList(pathItem['parameters'])) {
      final p = _resolveParameter(pAny);
      if (p != null && p['name'] != null && p['in'] != null) {
        merged['${p['name']}|${p['in']}'] = p;
      }
    }
    for (final pAny in asList(operation['parameters'])) {
      final p = _resolveParameter(pAny);
      if (p != null && p['name'] != null && p['in'] != null) {
        merged['${p['name']}|${p['in']}'] = p;
      }
    }
    return merged.values.toList();
  }

  /// Path-item-level `parameters` apply to every

  /// Resolve refs and allOf into a concrete schema dict.
  Map<String, dynamic> _unwrap(dynamic schemaAny) {
    final schema = asMapOrNull(schemaAny);
    if (schema == null) return {};
    if (schema.containsKey('\$ref') && schema.length == 1) {
      return _unwrap(_resolve(schema));
    }
    if (schema.containsKey('allOf')) {
      return _mergeAllOf(schema);
    }
    if (schema.containsKey('\$ref')) {
      final base = asMapOrNull(_resolve(schema));
      if (base != null && base.containsKey('allOf')) {
        return _mergeAllOf(base);
      }
      return base ?? {};
    }
    return schema;
  }

  // ---- ensure / emit ----

  void _ensureSchema(String name) {
    if (emitted.contains(name) || inProgress.contains(name)) return;
    if (!schemas.containsKey(name)) return;
    if (_isExcluded(name)) {
      // Excluded (e.g. --exclude-pattern matched a client-request envelope
      // schema): emit nothing for it. Any $ref pointing here is handled
      // separately in _typeRef, which falls back to Map<String, dynamic>
      // instead of a class reference.
      emitted.add(name);
      kindOf[name] = 'excluded';
      return;
    }
    inProgress.add(name);
    final schema = asMap(schemas[name]);
    final kind = kindOf[name] ?? _classify(schema);
    kindOf[name] = kind;
    final dartName = _dartName(name);

    if (kind == 'null_unit') {
      typedefNames.add(dartName);
      generated[dartName] =
          '/// OpenAPI unit/null schema `$name`.\ntypedef $dartName = Null;';
    } else if (kind == 'alias') {
      final target = _primitiveDartType(schema);
      final isNullableAlias =
          schema['nullable'] == true || typeIncludesNull(schema['type']);
      // Primitive aliases are NOT emitted as typedefs — use sites inline the
      // primitive directly. Bookkeeping stays so $refs resolve the same way.
      typedefTarget[dartName] = target; // stays clean, e.g. "String"
      if (isNullableAlias) nullableTypedefs.add(dartName);
    } else if (kind == 'ref_alias') {
      final target = _allOfSingleRef(schema) ?? '';
      _ensureSchema(target);
      final tDart = _dartName(target);
      final ultimate = _resolveTypedefTarget(tDart);
      typedefTarget[dartName] = ultimate;
      if (_isPrimitiveName(ultimate)) {
        // Inlined primitive — no typedef emitted (bookkeeping above keeps
        // $ref resolution working).
        inProgress.remove(name);
        emitted.add(name);
        return;
      }
      typedefNames.add(dartName);
      final desc = _doc(schema);
      generated[dartName] = '${desc}typedef $dartName = $tDart;';
    } else if (kind == 'alias_array') {
      final items = asMap(schema['items']);
      final itemT = _typeRef(items, hintName: '${dartName}Item');
      final itemTypeStr = (itemT.isNullable && itemT.dartType != 'dynamic')
          ? '${itemT.dartType}?'
          : itemT.dartType;
      typedefNames.add(dartName);
      typedefTarget[dartName] = 'List<$itemTypeStr>';
      final desc = _doc(schema);
      generated[dartName] = '${desc}typedef $dartName = List<$itemTypeStr>;';
    } else if (kind == 'string_enum') {
      sealedNames.add(dartName);
      generated[dartName] = _genStringEnum(dartName, schema, name);
    } else if (kind == 'union') {
      // oneOf: [ { $ref: unistring } ] → typedef to Unistring (no useless
      // sealed wrapper + try/catch fromJson).
      final variants = asList(schema['oneOf'] ?? schema['anyOf'] ?? const []);
      final nonNull = variants
          .where((v) => !isNullSchema(_resolve(v)))
          .toList();
      if (_isInt64AsStringUnion(schema)) {
        // int64-as-string pair (integer branch + digit-string branch) is a
        // single BigInt value, not a real sum type — never a sealed class.
        // No typedef emitted (primitives inline); bookkeeping stays for
        // $ref resolution and nullability.
        typedefTarget[dartName] = 'BigInt';
        kindOf[name] = 'alias';
        sealedNames.remove(dartName);
        final nullSuffix = variants.length > nonNull.length ? '?' : '';
        if (nullSuffix == '?') nullableTypedefs.add(dartName);
      } else if (nonNull.length == 1) {
        final inner = _typeRef(nonNull[0], hintName: dartName);
        final target = inner.dartType;
        if (target == dartName) {
          // Single inline object/union variant was already emitted under our
          // own name (e.g. oneOf with a single inline object schema) — keep
          // that declaration instead of overwriting it with a
          // self-referential typedef.
          if (inner.kind == 'sealed') {
            kindOf[name] = 'union';
            sealedNames.add(dartName);
          } else {
            kindOf[name] = 'object';
            classNames.add(dartName);
          }
        } else {
          final ultimate = _resolveTypedefTarget(target);
          typedefTarget[dartName] = ultimate;
          kindOf[name] = 'alias';
          sealedNames.remove(dartName);
          final nullSuffix =
              (inner.isNullable || variants.length > nonNull.length) ? '?' : '';
          if (nullSuffix == '?') nullableTypedefs.add(dartName);
          if (_isPrimitiveName(ultimate)) {
            // Inlined primitive — no typedef emitted.
            inProgress.remove(name);
            emitted.add(name);
            return;
          }
          typedefNames.add(dartName);
          final desc = _doc(schema);
          generated[dartName] =
              '${desc}typedef $dartName = $target$nullSuffix;';
        }
      } else {
        sealedNames.add(dartName);
        generated[dartName] = _genUnion(dartName, schema, name);
      }
    } else if (kind == 'object') {
      classNames.add(dartName);
      generated[dartName] = _genObject(dartName, schema, name);
    } else if (kind == 'ref') {
      final target = refName(schema['\$ref'] as String);
      _ensureSchema(target);
      final tDart = _dartName(target);
      final ultimate = _resolveTypedefTarget(tDart);
      typedefTarget[dartName] = ultimate;
      if (_isPrimitiveName(ultimate)) {
        // Inlined primitive — no typedef emitted.
        inProgress.remove(name);
        emitted.add(name);
        return;
      }
      typedefNames.add(dartName);
      generated[dartName] = 'typedef $dartName = $tDart;';
    } else {
      if (schema.containsKey('properties') ||
          primaryType(schema['type']) == 'object') {
        classNames.add(dartName);
        generated[dartName] = _genObject(dartName, schema, name);
      } else {
        typedefNames.add(dartName);
        typedefTarget[dartName] = 'Map<String, dynamic>';
        kindOf[name] = 'alias';
        generated[dartName] =
            '/// Free-form JSON object (OpenAPI schema `$name` had no type).\n'
            'typedef $dartName = Map<String, dynamic>;';
      }
    }

    inProgress.remove(name);
    emitted.add(name);
  }

  String _doc(Map<String, dynamic> schema) {
    final desc = (schema['description'] as String? ?? '').trim();
    if (desc.isEmpty) return '';
    final lines = desc.split('\n');
    if (lines.length == 1) return '/// ${lines[0]}\n';
    return '/// ${lines.join('\n/// ')}\n';
  }

  /// Same as [_doc], plus (if this schema is used directly as a request
  /// body or response body somewhere in `paths`) a trailing comment listing
  /// the HTTP method + path it belongs to.
  String _docWithEndpoints(Map<String, dynamic> schema, String originalName) {
    final doc = _doc(schema);
    final endpoints = endpointUsage[originalName];
    if (endpoints == null || endpoints.isEmpty) return doc;
    final lines = doc.isEmpty
        ? <String>[]
        : doc.replaceAll(RegExp(r'\n$'), '').split('\n');
    if (lines.isNotEmpty) lines.add('///');
    for (final e in endpoints) {
      lines.add('/// $e');
    }
    return '${lines.join('\n')}\n';
  }

  // ---- type mapping ----

  String _primitiveDartType(Map<String, dynamic> schema) {
    final t = primaryType(schema['type']);
    final fmt = schema['format'];
    if (t == 'string') {
      return 'String'; // covers bytes/byte/binary formats too
    }
    if (t == 'boolean') return 'bool';
    if (t == 'integer') {
      if (fmt is String) {
        // Accepts both signed (int64) and unsigned (uint64) widths by
        // normalizing "uint64" -> "int64" first. NOTE: a naive
        // `"uint64".replaceFirst("int", '')` yields "u64" (unparsable), which
        // is why every uintXX width used to silently fall through to int.
        // Widths > 53 bits exceed the JSON-safe integer range, so they map
        // to BigInt (Dart int is signed 64-bit and cannot hold uint64 max).
        // Bare "int"/"uint" (no width, e.g. small counts) stays int.
        final normalized = fmt.startsWith('uint') ? fmt.substring(1) : fmt;
        if (normalized.startsWith('int')) {
          final bit = int.tryParse(normalized.replaceFirst('int', ''));
          if (bit != null && bit > 53) {
            return 'BigInt';
          }
        }
      }

      return 'int';
    }
    if (t == 'number') {
      if (fmt == 'double' || fmt == 'float') return 'double';
      return 'num';
    }
    return 'dynamic';
  }

  /// True when [schema] is an int64-as-string union: oneOf/anyOf of exactly
  /// one integer branch and one string branch (plus an optional null
  /// branch) — the java-tron `x-tron-int64-as-string` shape. Both branches
  /// always represent the same 64-bit integer, which may arrive either as a
  /// JSON number or as a digit string, so these map directly to [BigInt]
  /// instead of a two-variant sealed class.
  bool _isInt64AsStringUnion(Map<String, dynamic> schema) {
    final variants = asList(schema['oneOf'] ?? schema['anyOf']);
    if (variants.isEmpty) return false;
    final nonNull = variants.where((v) => !isNullSchema(_resolve(v))).toList();
    if (nonNull.length != 2) return false;
    var sawInt = false;
    var sawString = false;
    for (final v in nonNull) {
      // A `$ref` branch names a *different* type (e.g. BlockId = height OR
      // hash) — it is never "the same int64 written as a string", so only
      // inline branches qualify. (Check the raw branch: resolving first
      // would hide the $ref and misread `{type: string}` targets.)
      final raw = asMapOrNull(v);
      if (raw == null || raw.containsKey('\$ref')) return false;
      final r = asMapOrNull(_resolve(v));
      if (r == null) return false;
      // Branches must be plain scalar schemas — no nested unions /
      // objects / enums, which would mean the branches carry different types.
      if (r.containsKey('properties') ||
          r.containsKey('oneOf') ||
          r.containsKey('anyOf') ||
          r.containsKey('allOf') ||
          r.containsKey('enum')) {
        return false;
      }
      final t = primaryType(r['type']);
      if (t == 'integer') {
        // Small widths (int32 and below) never need a string encoding for
        // precision — every value survives JSON numbers exactly — so
        // `oneOf(string, int32)` (e.g. a method name OR numeric ID) is a
        // real sum type, not an int64-as-string pair. Only 64-bit (or
        // widthless) integers collapse to BigInt.
        final fmt = r['format'];
        if (fmt is String) {
          final norm = fmt.startsWith('uint') ? fmt.substring(1) : fmt;
          if (norm.startsWith('int')) {
            final bits = int.tryParse(norm.substring(3));
            if (bits != null && bits <= 53) return false;
          }
        }
        sawInt = true;
      } else if (t == 'string') {
        sawString = true;
      } else {
        return false;
      }
    }
    return sawInt && sawString;
  }

  /// [TypeRef] for an int64-as-string union: plain `BigInt`. Parsing goes
  /// through `valueAsBigInt`, which already accepts both JSON numbers and
  /// digit strings, and serializes back via `.toString()`-safe paths.
  TypeRef _int64AsStringTypeRef(Map<String, dynamic> schema, bool nullable) {
    final variants = asList(schema['oneOf'] ?? schema['anyOf']);
    final hasNull = variants.any((v) => isNullSchema(_resolve(v)));
    return TypeRef(
      'BigInt',
      kind: 'primitive',
      isNullable: nullable || hasNull,
      fromJsonMode: 'bigint',
    );
  }

  TypeRef _typeRef(dynamic schemaAny, {String hintName = 'Inline'}) {
    if (schemaAny == null || isNullSchema(schemaAny)) {
      return TypeRef(
        'dynamic',
        kind: 'dynamic',
        isNullable: true,
        fromJsonMode: 'dynamic',
      );
    }
    final schema = asMapOrNull(schemaAny);
    if (schema == null) {
      return TypeRef('dynamic', kind: 'dynamic', fromJsonMode: 'dynamic');
    }

    // // final nullable = schema['nullable'] == true;
    final nullable =
        schema['nullable'] == true || typeIncludesNull(schema['type']);

    // $ref
    final ref = schema['\$ref'];
    if (ref is String) {
      final name = refName(ref);
      if (_isExcluded(name)) {
        // Referenced schema was excluded (e.g. client-request envelope) —
        // fall back to a raw map so this still compiles.
        return TypeRef(
          'Map<String, dynamic>',
          kind: 'map',
          isNullable: nullable,
          fromJsonMode: 'map',
        );
      }
      _ensureSchema(name);
      final dart = _dartName(name);
      final kind = kindOf[name] ?? 'object';
      // OpenAPI 3.1 allows the *target* schema itself to be nullable via
      // `"type": ["object","null"]` (or `"nullable": true`). A bare `$ref`
      // does not carry that flag on the referencing node, so inherit it
      // from the resolved target schema.
      final targetSchema = asMap(schemas[name]);
      final targetNullable =
          targetSchema['nullable'] == true ||
          typeIncludesNull(targetSchema['type']);
      final effectiveNullable =
          nullable || targetNullable || nullableTypedefs.contains(dart);
      if (kind == 'null_unit') {
        return TypeRef(
          'Null',
          kind: 'typedef',
          isNullable: true,
          fromJsonMode: 'dynamic',
        );
      }
      if (kind == 'alias_array') {
        // Preserve list structure so fromJson can parse nested items;
        // field type stays the typedef name (e.g. `typedef Foo = List<Bar>`).
        final schemaForArray = asMap(schemas[name]);
        final items = asMap(schemaForArray['items']);
        final item = _typeRef(items, hintName: '${dart}Item');
        return TypeRef(
          dart,
          kind: 'list',
          isNullable: effectiveNullable,
          item: item,
          fromJsonMode: 'list',
        );
      }
      if (kind == 'alias' || kind == 'ref' || kind == 'ref_alias') {
        final target = typedefTarget[dart] ?? dart;
        final ultimate = _resolveTypedefTarget(target);
        // Primitive aliases are inlined (no typedef is emitted for them),
        // so resolve straight to the primitive here.
        if (_isPrimitiveName(ultimate)) {
          return TypeRef(
            ultimate,
            kind: 'primitive',
            isNullable: effectiveNullable,
            fromJsonMode: _modeForPrimitiveName(ultimate),
          );
        }
        final mode = _modeForPrimitiveName(target);
        // If the ultimate target is a class/sealed (ref_alias chain to an
        // object/union/enum), treat as that kind so fromJson/toJson work,
        // while keeping the typedef name as the declared dartType.
        if (classNames.contains(target) || sealedNames.contains(target)) {
          final isSealed = sealedNames.contains(target);
          return TypeRef(
            dart,
            kind: isSealed ? 'sealed' : 'class',
            isNullable: effectiveNullable,
            fromJsonMode: isSealed ? 'dynamic' : 'map',
            parseType: target,
          );
        }
        // Primitive (or list-of-primitive) alias — keep as typedef.
        return TypeRef(
          dart,
          kind: 'typedef',
          isNullable: effectiveNullable,
          fromJsonMode: mode,
        );
      }
      if (kind == 'string_enum' || kind == 'union') {
        return TypeRef(
          dart,
          kind: 'sealed',
          isNullable: effectiveNullable,
          fromJsonMode: 'dynamic',
        );
      }
      return TypeRef(
        dart,
        kind: 'class',
        isNullable: effectiveNullable,
        fromJsonMode: 'map',
      );
    }

    // allOf
    if (schema.containsKey('allOf')) {
      final merged = _mergeAllOf(schema);
      final parts = asList(schema['allOf']);
      if (parts.length == 1) {
        final p0 = asMapOrNull(parts[0]);
        if (p0 != null && p0.containsKey('\$ref')) {
          return _typeRef(p0, hintName: hintName);
        }
      }
      // `nullable` above only reflects the *outer* wrapper node (the
      // `{"allOf": [...]}` object itself almost never carries its own
      // `type`/`nullable`) — the actual nullability normally lives on one
      // of the merged parts, e.g. an allOf branch that's just a $ref to a
      // schema declared `"type": ["string", "null"]`. `_mergeAllOf`
      // already folds that part's `type` into `merged`, so re-derive
      // nullability from `merged` (falling back to the outer flag) rather
      // than trusting the stale outer-only `nullable`.
      final mergedNullable =
          nullable ||
          merged['nullable'] == true ||
          typeIncludesNull(merged['type']);
      if (merged['enum'] != null) {
        return _inlineStringEnum(merged, hintName, mergedNullable);
      }
      if (merged['properties'] != null ||
          primaryType(merged['type']) == 'object') {
        return _inlineObject(merged, hintName, mergedNullable);
      }
      final mt = primaryType(merged['type']);
      if (mt == 'string' ||
          mt == 'integer' ||
          mt == 'number' ||
          mt == 'boolean') {
        final prim = _primitiveDartType(merged);
        return TypeRef(
          prim,
          kind: 'primitive',
          isNullable: mergedNullable,
          fromJsonMode: _modeForPrimitiveName(prim),
        );
      }
      return _typeRef(merged, hintName: hintName);
    }

    // oneOf / anyOf
    if (schema.containsKey('oneOf') || schema.containsKey('anyOf')) {
      // int64-as-string pair (integer branch + digit-string branch) is a
      // single BigInt value, not a real sum type — never a sealed class.
      if (_isInt64AsStringUnion(schema)) {
        return _int64AsStringTypeRef(schema, nullable);
      }
      final variants = asList(schema['oneOf'] ?? schema['anyOf'] ?? const []);
      final nonNull = variants
          .where((v) => !isNullSchema(_resolve(v)))
          .toList();
      // Single non-null branch: unwrap to that type (optional nullability if
      // null was a sibling). Avoids useless sealed wrappers like
      // ResponseX with only a Unistring variant for oneOf: [{$ref: unistring}].
      if (nonNull.length == 1) {
        final inner = _typeRef(nonNull[0], hintName: hintName);
        if (variants.length > nonNull.length || nullable) {
          inner.isNullable = true;
        }
        return inner;
      }
      return _inlineUnion(schema, hintName, nullable);
    }

    // enum — Tezos (and similar) OpenAPI often closes `protocol` to a single
    // hash like ProtoGenesis… / PsUshuai… even though the wire value varies
    // by chain. Prefer Protocol_hash when available so runtime parses.
    if (schema.containsKey('enum')) {
      final vals = schema['enum'];
      if (vals is List &&
          vals.isNotEmpty &&
          vals.every(looksLikeProtocolId) &&
          schemas.containsKey('Protocol_hash')) {
        _ensureSchema('Protocol_hash');
        final dart = _dartName('Protocol_hash');
        final kind = kindOf['Protocol_hash'] ?? 'union';
        return TypeRef(
          dart,
          kind: kind == 'object'
              ? 'class'
              : (kind == 'string_enum' ? 'sealed' : 'sealed'),
          isNullable: nullable,
          fromJsonMode: kind == 'object' ? 'map' : 'dynamic',
        );
      }
      return _inlineStringEnum(schema, hintName, nullable);
    }

    final t = primaryType(schema['type']);

    if (t == 'array') {
      final items = asMap(schema['items']);
      final item = _typeRef(items, hintName: '${hintName}Item');
      final itemTypeStr = (item.isNullable && item.dartType != 'dynamic')
          ? '${item.dartType}?'
          : item.dartType;
      return TypeRef(
        'List<$itemTypeStr>',
        kind: 'list',
        isNullable: nullable,
        item: item,
        fromJsonMode: 'list',
      );
    }

    if (t == 'object' || schema.containsKey('properties')) {
      final propsVal = schema['properties'];
      final propsFalsy =
          propsVal == null || (propsVal is Map && propsVal.isEmpty);
      if (schema.containsKey('additionalProperties') && propsFalsy) {
        final ap = schema['additionalProperties'];
        if (ap == true) {
          return TypeRef(
            'Map<String, dynamic>',
            kind: 'map',
            isNullable: nullable,
            fromJsonMode: 'map',
          );
        }
        if (ap is Map) {
          final val = _typeRef(ap, hintName: '${hintName}Value');
          return TypeRef(
            'Map<String, ${val.dartType}>',
            kind: 'map',
            isNullable: nullable,
            value: val,
            fromJsonMode: 'map',
          );
        }
      }
      if (schema['properties'] != null) {
        return _inlineObject(schema, hintName, nullable);
      }
      return TypeRef(
        'Map<String, dynamic>',
        kind: 'map',
        isNullable: nullable,
        fromJsonMode: 'map',
      );
    }

    if (t == 'string' || t == 'integer' || t == 'number' || t == 'boolean') {
      final prim = _primitiveDartType(schema);
      return TypeRef(
        prim,
        kind: 'primitive',
        isNullable: nullable,
        fromJsonMode: _modeForPrimitiveName(prim),
      );
    }

    // free form
    return TypeRef(
      'dynamic',
      kind: 'dynamic',
      isNullable: nullable,
      fromJsonMode: 'dynamic',
    );
  }

  String _modeForPrimitiveName(String dart) {
    if (dart == 'String') return 'string';
    if (dart == 'int') return 'int';
    if (dart == 'double') return 'double';
    if (dart == 'num') return 'num';
    if (dart == 'bool') return 'bool';
    if (dart == 'BigInt') return 'bigint';
    if (dart.startsWith('List<int>')) return 'bytes';
    if (dart.startsWith('List<')) return 'list';
    if (dart.startsWith('Map<')) return 'map';
    return 'dynamic';
  }

  /// Serializes a BigInt-holding expression [expr] for toJson output via
  /// the configured `encodeBigint` (accepts nullable values, so no `?.`
  /// dance is needed).
  String _bigIntToJson(String expr) => 'config.encodeBigint($expr)';

  /// True for plain Dart primitives (after typedef resolution). Primitive
  /// aliases (`typedef ShardId = int`) are inlined at use sites instead of
  /// emitted — only List/Map/class/enum/union typedefs are generated.
  bool _isPrimitiveName(String dartType) {
    const prims = {'String', 'int', 'BigInt', 'bool', 'double', 'num'};
    return prims.contains(dartType);
  }

  /// Follows the typedef chain for [dartType] (e.g. PeerId -> PublicKey ->
  /// String, or BlockId -> BigInt) and returns the ultimate target, or
  /// [dartType] itself when it is not a typedef.
  String _resolveTypedefTarget(String dartType) {
    var cur = dartType;
    final seen = <String>{};
    while (typedefTarget.containsKey(cur) && seen.add(cur)) {
      cur = typedefTarget[cur]!;
    }
    return cur;
  }

  /// True when [dartName] collides with any top-level schema's generated
  /// Dart name (e.g. wrapper `NearRpcShardLayoutV0` vs component
  /// `ShardLayoutV0` with the same prefix). Compares prefixed forms —
  /// checking `schemas.containsKey(dartName)` directly never matches
  /// because schema keys are raw (`ShardLayoutV0`) while [dartName] is
  /// already prefixed.
  bool _collidesWithSchema(String dartName) {
    for (final k in schemas.keys) {
      if (_dartName(k) == dartName) return true;
    }
    return false;
  }

  String _inlineName(String hint) {
    _inlineCounter++;
    var base = _dartName(hint);
    var name = base;
    while (generated.containsKey(name) ||
        emitted.contains(name) ||
        _collidesWithSchema(name) ||
        classNames.contains(name) ||
        sealedNames.contains(name) ||
        typedefNames.contains(name)) {
      name = '$base$_inlineCounter';
      _inlineCounter++;
    }
    return name;
  }

  /// Structural fingerprint of a schema, ignoring cosmetic fields. Two
  /// inline schemas with the same shape (same properties/types/enum
  /// values) but different descriptions/titles should reuse a single
  /// generated Dart type instead of each minting its own.
  String _canonicalKey(dynamic schemaAny) {
    dynamic clean(dynamic obj) {
      if (obj is Map) {
        final entries =
            obj.entries
                .where(
                  (e) => !{
                    'description',
                    'title',
                    'example',
                    'examples',
                    'summary',
                  }.contains(e.key),
                )
                .toList()
              ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
        return {for (final e in entries) e.key.toString(): clean(e.value)};
      }
      if (obj is List) return obj.map(clean).toList();
      return obj;
    }

    try {
      return jsonEncode(clean(schemaAny));
    } catch (_) {
      return schemaAny.toString();
    }
  }

  TypeRef _inlineStringEnum(
    Map<String, dynamic> schema,
    String hintName,
    bool nullable,
  ) {
    final cacheKey = 'string_enum:${_canonicalKey(schema)}';
    final cached = _inlineCache[cacheKey];
    if (cached != null) {
      return TypeRef(
        cached.dartType,
        kind: cached.kind,
        isNullable: nullable,
        item: cached.item,
        value: cached.value,
        fromJsonMode: cached.fromJsonMode,
        parseType: cached.parseType,
      );
    }
    final name = _inlineName(hintName);
    sealedNames.add(name);
    generated[name] = _genStringEnum(name, schema, name);
    emitted.add(name);
    final tr = TypeRef(
      name,
      kind: 'sealed',
      isNullable: nullable,
      fromJsonMode: 'dynamic',
    );
    _inlineCache[cacheKey] = tr;
    return tr;
  }

  TypeRef _inlineObject(
    Map<String, dynamic> schema,
    String hintName,
    bool nullable,
  ) {
    final cacheKey = 'object:${_canonicalKey(schema)}';
    final cached = _inlineCache[cacheKey];
    if (cached != null) {
      return TypeRef(
        cached.dartType,
        kind: cached.kind,
        isNullable: nullable,
        item: cached.item,
        value: cached.value,
        fromJsonMode: cached.fromJsonMode,
        parseType: cached.parseType,
      );
    }
    final name = _inlineName(hintName);
    classNames.add(name);
    generated[name] = _genObject(name, schema, name);
    emitted.add(name);
    final tr = TypeRef(
      name,
      kind: 'class',
      isNullable: nullable,
      fromJsonMode: 'map',
    );
    _inlineCache[cacheKey] = tr;
    return tr;
  }

  TypeRef _inlineUnion(
    Map<String, dynamic> schema,
    String hintName,
    bool nullable,
  ) {
    // int64-as-string pair: single BigInt, never a sealed class.
    if (_isInt64AsStringUnion(schema)) {
      return _int64AsStringTypeRef(schema, nullable);
    }
    final cacheKey = 'union:${_canonicalKey(schema)}';
    final cached = _inlineCache[cacheKey];
    if (cached != null) {
      return TypeRef(
        cached.dartType,
        kind: cached.kind,
        isNullable: nullable,
        item: cached.item,
        value: cached.value,
        fromJsonMode: cached.fromJsonMode,
        parseType: cached.parseType,
      );
    }

    // Not byte-identical to anything seen before, per _canonicalKey. But
    // if the sanitized name we're about to mint is ALREADY a generated
    // union (i.e. some earlier, structurally-similar-but-not-identical
    // oneOf/anyOf schema wanted this same name), try to widen that
    // existing sealed class to cover this schema's variants too, instead
    // of minting a second sealed class with a meaningless numeric suffix
    // that nothing in the generated code relates back to the first.
    final baseName = _dartName(hintName);
    final existingRaw = _unionMergedSchema[baseName];
    if (existingRaw != null && sealedNames.contains(baseName)) {
      final merged = _tryMergeUnionSchemas(existingRaw, schema);
      if (merged != null) {
        generated[baseName] = _genUnion(baseName, merged, baseName);
        _unionMergedSchema[baseName] = merged;
        final tr = TypeRef(
          baseName,
          kind: 'sealed',
          isNullable: nullable,
          fromJsonMode: 'dynamic',
        );
        _inlineCache[cacheKey] = tr;
        return tr;
      }
      // Genuinely incompatible (different shared siblings/type) — fall
      // through to the old behavior of minting a separate, numbered class
      // rather than risk silently merging something that isn't the same
      // type.
    }

    final name = _inlineName(hintName);
    sealedNames.add(name);
    generated[name] = _genUnion(name, schema, name);
    emitted.add(name);
    if (!_unionMergedSchema.containsKey(name)) {
      _unionMergedSchema[name] = schema;
    }
    final tr = TypeRef(
      name,
      kind: 'sealed',
      isNullable: nullable,
      fromJsonMode: 'dynamic',
    );
    _inlineCache[cacheKey] = tr;
    return tr;
  }

  /// Attempts to widen [existing] (a union schema already generated under
  /// some name) to also cover [incoming]'s variants, when the two are
  /// conceptually "the same union" but arrived with slightly different
  /// oneOf/anyOf variant lists — e.g. the same field re-declared across
  /// near-duplicate schemas (different protocol/API versions, spec authors
  /// mixing `-`/`_`/`.` in an otherwise-identical field name, etc.) where
  /// [_canonicalKey] no longer considers them byte-identical.
  ///
  /// Returns the merged schema (existing variants ++ any genuinely new
  /// ones from incoming, deduped by each variant's own canonical shape) on
  /// success. Returns null when [existing] and [incoming] disagree on
  /// anything besides which variants they list — e.g. different shared
  /// sibling `properties`/`type` — since merging those could silently
  /// produce incorrect code; the caller falls back to generating a
  /// separate class in that case.
  Map<String, dynamic>? _tryMergeUnionSchemas(
    Map<String, dynamic> existing,
    Map<String, dynamic> incoming,
  ) {
    final existingIsUnion =
        existing.containsKey('oneOf') || existing.containsKey('anyOf');
    final incomingIsUnion =
        incoming.containsKey('oneOf') || incoming.containsKey('anyOf');
    if (!existingIsUnion || !incomingIsUnion) return null;

    Map<String, dynamic> withoutVariants(Map<String, dynamic> s) {
      final m = Map<String, dynamic>.from(s);
      m.remove('oneOf');
      m.remove('anyOf');
      // Cosmetic-only, already ignored elsewhere by _canonicalKey, but
      // strip explicitly too so this comparison only reflects
      // behaviorally-relevant siblings (shared properties/type/etc.).
      m.remove('description');
      m.remove('title');
      return m;
    }

    if (_canonicalKey(withoutVariants(existing)) !=
        _canonicalKey(withoutVariants(incoming))) {
      return null;
    }

    final existingVariants = asList(
      existing['oneOf'] ?? existing['anyOf'] ?? const [],
    );
    final incomingVariants = asList(
      incoming['oneOf'] ?? incoming['anyOf'] ?? const [],
    );

    // The sibling check above is vacuously true whenever both schemas are
    // bare `{oneOf: [...]}` with no other keys — which is the common case
    // — so on its own it can't tell "the same union, evolved" apart from
    // "two unrelated unions that happen to want the same generated name."
    // Require the variant sets to actually overlap substantially before
    // treating them as the same type; two schemas that share zero (or
    // almost zero) variants are not near-duplicates, no matter how
    // similar their surrounding schema looks, and merging them would
    // silently produce a class that's wrong for both call sites.
    final existingKeys = existingVariants.map(_canonicalKey).toSet();
    final incomingKeys = incomingVariants.map(_canonicalKey).toSet();
    final sharedCount = existingKeys.intersection(incomingKeys).length;
    final smallerSize = existingKeys.length < incomingKeys.length
        ? existingKeys.length
        : incomingKeys.length;
    if (smallerSize == 0 || sharedCount / smallerSize < 0.5) {
      return null;
    }

    final seen = <String>{...existingKeys};
    final mergedVariants = [...existingVariants];
    for (final v in incomingVariants) {
      if (seen.add(_canonicalKey(v))) mergedVariants.add(v);
    }

    if (mergedVariants.length == existingVariants.length) {
      // Same effective variant set (just arrived via a different route,
      // or in a different order) — nothing to widen.
      return existing;
    }

    final merged = Map<String, dynamic>.from(existing);
    merged.remove('anyOf');
    merged['oneOf'] = mergedVariants;
    return merged;
  }

  // ---- codegen: real Dart `enum` for pure primitive-constant unions ----

  /// Normalizes an enum wire value before lowerCamelCase conversion.
  ///
  /// Specs (like java-tron's) often use SCREAMING_SNAKE_CASE wire values
  /// (`BANDWIDTH`, `OUT_OF_ENERGY`). Without normalization those have no
  /// word separators *after* lowercasing the first letter only, producing
  /// non-standard members like `bANDWIDTH` / `oUTOFENERGY`. When the token
  /// contains no lowercase letters at all, lowercase the whole token first
  /// so `BANDWIDTH` → `bandwidth` and `TRON_POWER` → `tronPower`.
  /// Mixed/pascal-case values (`Normal`, `AssetIssue`) pass through
  /// untouched.
  String _normalizeEnumToken(String value) {
    if (value.isNotEmpty && !RegExp(r'[a-z]').hasMatch(value)) {
      return value.toLowerCase();
    }
    return value;
  }

  /// Dart-safe, unique enum member identifier for a raw JSON literal
  /// (string/int/float/bool). Strings get the usual lowerCamelCase
  /// treatment; non-strings get a synthetic `nXxx` name since Dart
  /// identifiers can't be bare numbers. An explicit spec [label]
  /// (`x-enum-varnames` / `x-enumNames`) wins over the derived name.
  String _enumMemberName(dynamic value, Set<String> used, [String? label]) {
    String base;
    if (label != null && label.trim().isNotEmpty) {
      base = snakeToCamel(
        _normalizeEnumToken(label.trim()),
        capitalizeFirst: false,
      );
      if (base.isEmpty) base = 'value';
    } else if (value is bool) {
      base = value ? 'true_' : 'false_';
    } else if (value is String) {
      base = snakeToCamel(_normalizeEnumToken(value), capitalizeFirst: false);
    } else if (value is num) {
      base = 'n${value.toString().replaceAll('-', 'Neg').replaceAll('.', '_')}';
    } else {
      base = snakeToCamel(
        _normalizeEnumToken(value.toString()),
        capitalizeFirst: false,
      );
    }
    if (base.isEmpty || !RegExp(r'^[A-Za-z_]').hasMatch(base)) {
      base = 'v$base';
    }
    if (dartReserved.contains(base) || enumReservedMembers.contains(base)) {
      base = '${base}_';
    }
    var name = base;
    var i = 2;
    while (used.contains(name)) {
      name = '$base$i';
      i++;
    }
    used.add(name);
    return name;
  }

  /// Author-declared enum member labels (`x-enum-varnames`, fallback
  /// `x-enumNames`), used only when they align 1:1 with the enum values
  /// (same order). Otherwise empty (derived names apply).
  List<String> _enumVarLabels(Map<String, dynamic> schema, int count) {
    for (final key in ['x-enum-varnames', 'x-enumNames']) {
      final raw = asList(schema[key]).whereType<String>().toList();
      if (raw.length == count && raw.every((s) => s.trim().isNotEmpty)) {
        return raw;
      }
    }
    return const [];
  }

  String _genStringEnum(
    String dartName,
    Map<String, dynamic> schema,
    String original,
  ) {
    var values = asList(schema['enum']).where((v) => v != null).toList();
    // Labels gathered alongside values when enums arrive via oneOf/anyOf
    // branches (each branch may carry its own x-enum-varnames).
    var branchLabels = <String>[];
    if (values.isEmpty &&
        (schema.containsKey('oneOf') || schema.containsKey('anyOf'))) {
      for (final vAny in asList(
        schema['oneOf'] ?? schema['anyOf'] ?? const [],
      )) {
        final v = asMapOrNull(_resolve(vAny));
        if (v != null && v['enum'] != null) {
          final branchVals = asList(v['enum']).where((x) => x != null).toList();
          values.addAll(branchVals);
          final branchNames = _enumVarLabels(v, branchVals.length);
          branchLabels.addAll(
            branchNames.isEmpty
                ? List<String>.filled(branchVals.length, '')
                : branchNames,
          );
        }
      }
    }
    // de-dupe preserve order (labels travel with their values; branch
    // labels only apply when nothing was de-duplicated away).
    final seen = <dynamic>{};
    final uniq = <dynamic>[];
    var labelsKept = branchLabels.length == values.length;
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (!seen.contains(v)) {
        seen.add(v);
        uniq.add(v);
      } else {
        labelsKept = false;
      }
    }
    values = uniq;
    if (!labelsKept) branchLabels = <String>[];

    if (values.isEmpty) {
      // A real Dart `enum` needs >=1 member, so an empty enum schema
      // (should be vanishingly rare) can't become one — keep the old
      // throwing-stub shape, flagged for attention.
      return '${_doc(schema)}'
          '/// TODO: schema `$original` declares an enum with no usable '
          "values — can't generate a real Dart enum (needs at least one "
          'member). Left as a throwing stub; check the source schema.\n'
          'sealed class $dartName {\n'
          '  const $dartName();\n'
          '  factory $dartName.fromJson(dynamic json) =>\n'
          "      throw ArgumentException.invalidOperationArguments('$dartName', reason: 'Empty enum $dartName');\n"
          '  dynamic toJson($_toJsonParams);\n'
          '}';
    }

    final isString = values.every((v) => v is String);

    final usedNames = <String>{};
    // Branch-gathered labels win when present (already aligned post-dedupe),
    // else the schema's own x-enum-varnames.
    final labels = branchLabels.length == values.length
        ? branchLabels
        : _enumVarLabels(schema, values.length);
    final members = <MapEntry<String, dynamic>>[
      for (var i = 0; i < values.length; i++)
        MapEntry(
          _enumMemberName(
            values[i],
            usedNames,
            i < labels.length && labels[i].isNotEmpty ? labels[i] : null,
          ),
          values[i],
        ),
    ];

    final bool isInt = values.every((v) => v is int);
    final bool isBool = values.every((v) => v is bool);
    final bool isNum = values.every((v) => v is num);
    final String valueType;
    if (isString) {
      valueType = 'String';
    } else if (isBool) {
      valueType = 'bool';
    } else if (isInt) {
      valueType = 'int';
    } else if (isNum) {
      valueType = 'num';
    } else {
      valueType = 'Object';
    }

    final lines = <String>[];
    lines.add(_docWithEndpoints(schema, original).trimRight());
    lines.add('enum $dartName {');
    for (var i = 0; i < members.length; i++) {
      final member = members[i].key;
      final v = members[i].value;
      final suffix = i == members.length - 1 ? ';' : ',';
      final lit = jsonLiteral(v);
      lines.add('  $member($lit)$suffix');
    }
    lines.add('');
    lines.add('  final $valueType value;');
    lines.add('  const $dartName(this.value);');
    lines.add('');
    lines.add('  static $dartName fromJson(dynamic json) {');
    if (isString) {
      lines.add('    final value = json is String ? json : json?.toString();');
    } else {
      lines.add('    final value = json;');
    }
    lines.add('    return values.firstWhere(');
    lines.add('      (e) => e.value == value,');
    lines.add(
      "      orElse: () => throw ItemNotFoundException(name: '$dartName'),",
    );
    lines.add('    );');
    lines.add('  }');
    lines.add('');
    lines.add('  $valueType toJson($_toJsonParams) => value;');
    lines.add('}');
    return lines.join('\n');
  }

  // ---- codegen: union (oneOf/anyOf) as sealed class ----

  /// (isLiteral, value) for a property schema that pins a single constant
  /// value via `enum: [x]` or `const: x` — i.e. a Rust-serde style
  /// internally-tagged "this is variant X" marker field.
  MapEntry<bool, dynamic> _literalValue(dynamic propSchemaAny) {
    final propSchema = asMapOrNull(propSchemaAny);
    if (propSchema == null) return const MapEntry(false, null);
    if (propSchema.containsKey('const')) {
      return MapEntry(true, propSchema['const']);
    }
    final vals = propSchema['enum'];
    if (vals is List && vals.length == 1) {
      return MapEntry(true, vals[0]);
    }
    return const MapEntry(false, null);
  }

  /// Literal prefix anchored at a regex start (`^ed25519:` → `ed25519:`),
  /// or `''` when [pattern] is not start-anchored or has no usable literal
  /// head. Backslash escapes (`\:`) contribute their literal char. Only
  /// used to tell apart tied siblings pinning *different* patterns on the
  /// same property — never executed as a regex, so no compile risk.
  String _regexLiteralPrefix(String pattern) {
    if (!pattern.startsWith('^')) return '';
    final buf = StringBuffer();
    var i = 1;
    while (i < pattern.length) {
      final c = pattern[i];
      if (c == '\\' && i + 1 < pattern.length) {
        buf.write(pattern[i + 1]);
        i += 2;
        continue;
      }
      if (r'.^$*+?()[]{}|'.contains(c)) break;
      buf.write(c);
      i++;
    }
    return buf.toString();
  }

  /// `{prop: literalPrefix}` for required props of [props] pinning distinct
  /// anchored patterns (`pattern: "^p256:"`). Only pins with a head of at
  /// least 2 literal chars qualify — shorter heads are too weak to branch on.
  Map<String, String> _patternPins(
    Map<String, dynamic> props,
    Set<String> required,
  ) {
    final out = <String, String>{};
    for (final e in props.entries) {
      final key = e.key.toString();
      if (!required.contains(key)) continue;
      final ps = asMapOrNull(e.value);
      final pat = ps?['pattern'];
      if (pat is! String) continue;
      final prefix = _regexLiteralPrefix(pat);
      if (prefix.length >= 2) out[key] = prefix;
    }
    return out;
  }

  /// `map['k']` starts with [prefix] (null-safe: absent/wrong-typed values
  /// simply don't match instead of throwing).
  String _patternCondition(String key, String prefix) {
    final k = escapeDartString(key);
    final p = escapeDartString(prefix);
    return "(map['$k']?.toString().startsWith('$p') ?? false)";
  }

  /// Property accessor for pattern/literal inspection of a variant: inline
  /// `object` variants contribute their own schema; `$ref` variants
  /// contribute their target's schema.
  Map<String, dynamic> _variantMatchProperties(VariantInfo v) {
    if (v.kind == 'object' && v.objectSchema != null) {
      return asMap(v.objectSchema!['properties']);
    }
    return asMap(_refTargetSchema(v)['properties']);
  }

  /// Last-resort tiebreaker for a group sharing identical match guards:
  /// when every member pins a *different* anchored pattern on the same
  /// required key, assign startsWith guards. Returns true on success.
  bool _assignPatternGuards(List<VariantInfo> group) {
    if (group.length < 2) return false;
    final pinsByVariant = <VariantInfo, Map<String, String>>{};
    for (final v in group) {
      pinsByVariant[v] = _patternPins(
        _variantMatchProperties(v),
        v.requiredKeys.toSet(),
      );
    }
    final allKeys = <String>{};
    for (final pins in pinsByVariant.values) {
      allKeys.addAll(pins.keys);
    }
    for (final key in [...allKeys]..sort()) {
      if (!pinsByVariant.values.every((pins) => pins.containsKey(key))) {
        continue;
      }
      final prefixes = [for (final v in group) pinsByVariant[v]![key]!];
      if (prefixes.toSet().length != prefixes.length) continue;
      for (var i = 0; i < group.length; i++) {
        group[i].patternGuards = [MapEntry(key, prefixes[i])];
      }
      return true;
    }
    return false;
  }

  /// Applies an explicit OpenAPI `discriminator` (`{propertyName, mapping}`)
  /// declared alongside oneOf/anyOf. The mapping pins exact wire values to
  /// `$ref` variants (`"msg.dataText" -> MsgDataText`), which is authoritative
  /// over any inferred literal/presence matching. Variants not covered by the
  /// mapping keep inferred matching. Called before [_assignDiscriminators];
  /// inference skips explicitly-pinned variants.
  void _applyExplicitDiscriminator(
    Map<String, dynamic> schema,
    List<VariantInfo> variants,
  ) {
    final disc = asMapOrNull(schema['discriminator']);
    if (disc == null) return;
    final prop = disc['propertyName'];
    if (prop is! String || prop.isEmpty) return;
    final mapping = asMapOrNull(disc['mapping']);
    if (mapping == null || mapping.isEmpty) return;
    // Invert: component schema name -> discriminator wire value. Entries
    // whose value is not a schema $ref cannot name a variant — skip them.
    final byRef = <String, String>{};
    for (final e in mapping.entries) {
      final v = e.value;
      if (v is String && v.contains('/')) {
        byRef.putIfAbsent(refName(v), () => e.key.toString());
      }
    }
    if (byRef.isEmpty) return;
    for (final v in variants) {
      if (v.discriminatorKey != null) continue;
      if (v.kind != 'ref' || v.refType == null) continue;
      final comp = _componentNameForDartType(v.refType!);
      if (comp == null) continue;
      final value = byRef[comp];
      if (value == null) continue;
      v.discriminatorKey = prop;
      v.discriminatorValue = value;
    }
  }

  /// Struct-style ("object") union variants are normally matched by which
  /// required keys are present. That breaks when two variants require the
  /// exact same keys — the `hasValue` check is then identical for both, so
  /// the first is always picked and the second is unreachable dead code.
  ///
  /// For each such colliding group, look for a property that pins a single
  /// literal value (`enum: [x]`/`const: x`) and is present with a
  /// *different* literal value on every member of the group. If found,
  /// switch on that value instead of key presence. If not, mark the
  /// variants so the caller can emit a [TODO] instead of silently generating
  /// unreachable code.
  void _assignDiscriminators(List<VariantInfo> variants) {
    final groups = <String, List<VariantInfo>>{};
    for (final v in variants) {
      if (v.kind != 'object' || v.objectSchema == null) continue;
      final props = asMap(v.objectSchema!['properties']);
      final req =
          (asList(v.objectSchema!['required']).isNotEmpty
                ? asList(v.objectSchema!['required']).cast<String>()
                : props.keys.toList())
            ..sort();
      final sig = req.join('\u0001');
      groups.putIfAbsent(sig, () => []).add(v);
    }

    int cmpKey(String k) =>
        (k == 'request_type' ||
            k == 'type' ||
            k == 'kind' ||
            k == 'name' ||
            k == 'tag')
        ? 0
        : 1;
    List<String> sortKeys(Iterable<String> keys) {
      final list = keys.toList();
      list.sort((a, b) {
        final c = cmpKey(a).compareTo(cmpKey(b));
        return c != 0 ? c : a.compareTo(b);
      });
      return list;
    }

    for (final group in groups.values) {
      // Explicit spec discriminators (see _applyExplicitDiscriminator)
      // outrank every inferred strategy for the whole group.
      if (group.any((v) => v.discriminatorKey != null)) continue;
      if (group.length == 1) {
        final v = group[0];
        // Explicit spec discriminators (see _applyExplicitDiscriminator)
        // outrank inferred literal pins.
        if (v.discriminatorKey != null) continue;
        final props = asMap(v.objectSchema!['properties']);
        for (final key in sortKeys(props.keys)) {
          final lit = _literalValue(props[key]);
          if (lit.key) {
            v.discriminatorKey = key;
            v.discriminatorValue = lit.value;
            break;
          }
        }
        continue;
      }

      Set<String>? candidateKeys;
      for (final v in group) {
        final props = asMap(v.objectSchema!['properties']);
        final literalKeys = <String>{
          for (final e in props.entries)
            if (_literalValue(e.value).key) e.key,
        };
        candidateKeys = candidateKeys == null
            ? literalKeys
            : candidateKeys.intersection(literalKeys);
      }
      candidateKeys ??= {};

      var resolved = false;
      for (final key in sortKeys(candidateKeys)) {
        final values = <dynamic>[];
        for (final v in group) {
          final props = asMap(v.objectSchema!['properties']);
          values.add(_literalValue(props[key]).value);
        }
        final distinct = values.map((x) => x.toString()).toSet();
        if (distinct.length == values.length) {
          for (var i = 0; i < group.length; i++) {
            group[i].discriminatorKey = key;
            group[i].discriminatorValue = values[i];
          }
          resolved = true;
          break;
        }
      }

      if (!resolved) {
        // Fall back: exclusive optional properties, then deep array/object
        // item key differences (generic — e.g. Tezos run_operation
        // Operation_with_metadata vs without: contents[].metadata).
        resolved = _assignPresenceDiscriminators(group);
      }

      if (!resolved) {
        // Last resort: anchored pattern prefixes on the same required key
        // (e.g. webauthn `public_key` matching `^ed25519:` vs `^p256:`).
        resolved = _assignPatternGuards(group);
      }

      if (!resolved) {
        final names = group.map((v) => v.className).toList();
        for (final v in group) {
          v.ambiguousWith = names.where((n) => n != v.className).toList();
        }
      }
    }
  }

  /// Collect property names declared on [schema] (resolved $ref / allOf /
  /// oneOf variants). For oneOf/anyOf, returns the **union** of property
  /// names across variants (keys that *may* appear).
  /// Property names on [schema]. For oneOf/anyOf, [intersect] true returns
  /// keys common to **every** variant (strong discriminators); false returns
  /// the union (keys that may appear on some variants).
  Set<String> _schemaPropertyNames(
    dynamic schemaAny, {
    int depth = 0,
    bool intersect = false,
  }) {
    if (depth > 8 || schemaAny == null) return {};
    if (schemaAny is! Map) return {};
    var schema = Map<String, dynamic>.from(
      schemaAny.map((k, v) => MapEntry(k.toString(), v)),
    );
    final refKey = r'$' + 'ref';
    if (schema.containsKey(refKey)) {
      final name = refName(schema[refKey] as String);
      final target = asMapOrNull(schemas[name]);
      if (target == null) return {};
      return _schemaPropertyNames(
        target,
        depth: depth + 1,
        intersect: intersect,
      );
    }
    if (schema.containsKey('allOf')) {
      final out = <String>{};
      for (final part in asList(schema['allOf'])) {
        out.addAll(
          _schemaPropertyNames(part, depth: depth + 1, intersect: intersect),
        );
      }
      return out;
    }
    if (schema.containsKey('oneOf') || schema.containsKey('anyOf')) {
      final parts = asList(schema['oneOf'] ?? schema['anyOf']);
      if (parts.isEmpty) return {};
      Set<String>? acc;
      for (final part in parts) {
        final keys = _schemaPropertyNames(
          part,
          depth: depth + 1,
          intersect: intersect,
        );
        if (acc == null) {
          acc = keys;
        } else if (intersect) {
          acc = acc.intersection(keys);
        } else {
          acc = acc.union(keys);
        }
      }
      return acc ?? {};
    }
    return asMap(schema['properties']).keys.map((k) => k.toString()).toSet();
  }

  /// Item schema of an array property, or null.
  Map<String, dynamic>? _arrayItemsSchema(dynamic propSchemaAny) {
    final prop = asMapOrNull(propSchemaAny);
    if (prop == null) return null;
    final refKey = r'$' + 'ref';
    if (prop.containsKey(refKey)) {
      final name = refName(prop[refKey] as String);
      return _arrayItemsSchema(schemas[name]);
    }
    if (primaryType(prop['type']) == 'array') {
      return asMapOrNull(prop['items']) ?? {};
    }
    return null;
  }

  /// Try to distinguish [group] variants by property presence (top-level
  /// exclusive keys, then keys unique to array-item / nested object schemas).
  /// Returns true if every variant got a presencePath.
  bool _assignPresenceDiscriminators(List<VariantInfo> group) {
    if (group.length < 2) return false;

    // --- top-level exclusive property keys ---
    final propSets = <VariantInfo, Set<String>>{
      for (final v in group)
        v: asMap(
          v.objectSchema!['properties'],
        ).keys.map((k) => k.toString()).toSet(),
    };
    final allKeys = <String>{};
    for (final s in propSets.values) {
      allKeys.addAll(s);
    }
    // Keys that appear in exactly one variant's property set.
    final exclusive = <String, VariantInfo>{};
    for (final key in allKeys) {
      final owners = [
        for (final e in propSets.entries)
          if (e.value.contains(key)) e.key,
      ];
      if (owners.length == 1) exclusive[key] = owners.first;
    }
    if (exclusive.isNotEmpty && exclusive.length >= group.length - 1) {
      // Prefer keys owned by a single variant; check positive presence for
      // the owner. Variants with no exclusive key match by process of
      // elimination (no presencePath — matched last via required keys only).
      for (final e in exclusive.entries) {
        e.value.presencePath = [e.key];
        e.value.presencePositive = true;
      }
      // If every variant has at least one exclusive key OR only one lacks
      // one, we can order matches: exclusive-positive first.
      final covered = exclusive.values.toSet();
      if (covered.length == group.length ||
          covered.length == group.length - 1) {
        return true;
      }
    }

    // --- shared array properties: exclusive keys on item schemas ---
    final sharedArrayKeys = <String>{};
    if (group.isNotEmpty) {
      sharedArrayKeys.addAll(propSets[group.first]!);
      for (final v in group.skip(1)) {
        sharedArrayKeys.retainAll(propSets[v]!);
      }
    }
    for (final arrayKey in sharedArrayKeys) {
      final itemKeySets = <VariantInfo, Set<String>>{};
      var allArray = true;
      for (final v in group) {
        final prop = asMap(v.objectSchema!['properties'])[arrayKey];
        final items = _arrayItemsSchema(prop);
        if (items == null) {
          allArray = false;
          break;
        }
        // Intersection = keys present on every item variant (reliable).
        itemKeySets[v] = _schemaPropertyNames(items, intersect: true);
      }
      if (!allArray) continue;

      final itemAll = <String>{};
      for (final s in itemKeySets.values) {
        itemAll.addAll(s);
      }
      // Also need union of other variants to exclude shared keys.
      final itemUnions = <VariantInfo, Set<String>>{
        for (final v in group)
          v: _schemaPropertyNames(
            _arrayItemsSchema(asMap(v.objectSchema!['properties'])[arrayKey]) ??
                {},
            intersect: false,
          ),
      };
      final itemExclusive = <String, VariantInfo>{};
      for (final key in itemAll) {
        // Owner: key is in this variant's intersection and not in any
        // other variant's union (never appears on siblings).
        final owners = <VariantInfo>[];
        for (final e in itemKeySets.entries) {
          if (!e.value.contains(key)) continue;
          final appearsOnSibling = group.any(
            (o) => o != e.key && (itemUnions[o]?.contains(key) ?? false),
          );
          if (!appearsOnSibling) owners.add(e.key);
        }
        if (owners.length == 1) itemExclusive[key] = owners.first;
      }
      if (itemExclusive.isEmpty) continue;

      // Assign presence paths contents/[]/metadata style.
      for (final e in itemExclusive.entries) {
        e.value.presencePath = [arrayKey, '[]', e.key];
        e.value.presencePositive = true;
      }
      final covered = itemExclusive.values.toSet();
      if (covered.length == group.length ||
          covered.length == group.length - 1) {
        return true;
      }
    }

    // --- shared object properties: exclusive nested keys ---
    for (final objKey in sharedArrayKeys) {
      // reuse shared keys that are objects (not arrays)
      final nestedSets = <VariantInfo, Set<String>>{};
      var allObj = true;
      for (final v in group) {
        final prop = asMap(v.objectSchema!['properties'])[objKey];
        final items = _arrayItemsSchema(prop);
        if (items != null) {
          allObj = false;
          break; // array handled above
        }
        final propSchema = asMapOrNull(prop);
        if (propSchema == null) {
          allObj = false;
          break;
        }
        // object-like?
        final names = _schemaPropertyNames(propSchema);
        if (names.isEmpty && primaryType(propSchema['type']) != 'object') {
          allObj = false;
          break;
        }
        nestedSets[v] = names;
      }
      if (!allObj || nestedSets.length != group.length) continue;

      final nestedAll = <String>{};
      for (final s in nestedSets.values) {
        nestedAll.addAll(s);
      }
      final nestedExclusive = <String, VariantInfo>{};
      for (final key in nestedAll) {
        final owners = [
          for (final e in nestedSets.entries)
            if (e.value.contains(key)) e.key,
        ];
        if (owners.length == 1) nestedExclusive[key] = owners.first;
      }
      if (nestedExclusive.isEmpty) continue;
      for (final e in nestedExclusive.entries) {
        e.value.presencePath = [objKey, e.key];
        e.value.presencePositive = true;
      }
      final covered = nestedExclusive.values.toSet();
      if (covered.length == group.length ||
          covered.length == group.length - 1) {
        return true;
      }
    }

    return group.every((v) => v.presencePath != null);
  }

  /// Build a Dart boolean expression over `map` for [v.presencePath].
  String _presenceCheckExpr(VariantInfo v) {
    final path = v.presencePath!;
    // Walk path producing an expression. Start from map.
    // '[]' means: value is non-empty List and first element is Map → continue
    // from that map.
    final parts = <String>[];
    var current = 'map';
    var i = 0;
    while (i < path.length) {
      final step = path[i];
      if (step == '[]') {
        // previous current must be list-ish
        parts.add('$current is List');
        parts.add('($current as List).isNotEmpty');
        parts.add('($current as List).first is Map');
        current = 'Map<String, dynamic>.from(($current as List).first as Map)';
        i++;
        continue;
      }
      if (i == path.length - 1) {
        // final key presence
        final key = escapeDartString(step);
        if (v.presencePositive) {
          if (current == 'map') {
            parts.add("map.hasValue('$key')");
          } else {
            parts.add("($current).containsKey('$key')");
          }
        } else {
          if (current == 'map') {
            parts.add("!map.hasValue('$key')");
          } else {
            parts.add("!($current).containsKey('$key')");
          }
        }
        i++;
        break;
      }
      // intermediate property: must exist AND be a Map to descend into.
      // Without the `is Map` check a non-Map intermediate (e.g. a String)
      // would throw NoSuchMethodError on `containsKey` instead of cleanly
      // falling through to sibling variants.
      final key = escapeDartString(step);
      if (current == 'map') {
        parts.add("map.hasValue('$key')");
        current = "map['$key']";
      } else {
        parts.add("($current).containsKey('$key')");
        current = "($current)['$key']";
      }
      parts.add('$current is Map');
      current = '($current as Map)';
      i++;
    }
    return parts.join(' && ');
  }

  /// `map['k'] == value` (AND-combined when [discriminatorLiterals] is set,
  /// plus anchored pattern-prefix pins when [patternGuards] is set).
  String _discriminatorIfCondition(VariantInfo v) {
    final parts = <String>[];
    if (v.patternGuards != null) {
      for (final e in v.patternGuards!) {
        parts.add(_patternCondition(e.key, e.value));
      }
    }
    if (v.discriminatorLiterals != null &&
        v.discriminatorLiterals!.isNotEmpty) {
      parts.add(
        v.discriminatorLiterals!
            .map(
              (e) =>
                  "map['${escapeDartString(e.key)}'] == ${jsonLiteral(e.value)}",
            )
            .join(' && '),
      );
    } else if (v.discriminatorKey != null) {
      parts.add(
        "map['${escapeDartString(v.discriminatorKey!)}'] == "
        '${jsonLiteral(v.discriminatorValue)}',
      );
    }
    return parts.join(' && ');
  }

  void _refineCollidingDiscriminators(List<VariantInfo> variants) {
    final objects = variants
        .where((v) => v.kind == 'object' && v.objectSchema != null)
        .toList();
    final byPrimary = <String, List<VariantInfo>>{};
    for (final v in objects) {
      if (v.discriminatorKey == null) continue;
      final sig =
          '${v.discriminatorKey}\u0001${jsonLiteral(v.discriminatorValue)}';
      byPrimary.putIfAbsent(sig, () => []).add(v);
    }

    for (final group in byPrimary.values) {
      if (group.length < 2) continue;

      final litMaps = <VariantInfo, Map<String, dynamic>>{};
      for (final v in group) {
        final props = asMap(v.objectSchema!['properties']);
        final m = <String, dynamic>{};
        for (final e in props.entries) {
          final lit = _literalValue(e.value);
          if (lit.key) m[e.key] = lit.value;
        }
        litMaps[v] = m;
      }

      final allKeys = <String>{};
      for (final m in litMaps.values) {
        allKeys.addAll(m.keys);
      }
      final distinguishing = <String>[];
      for (final key in allKeys) {
        if (!litMaps.values.every((m) => m.containsKey(key))) continue;
        final vals = [for (final v in group) litMaps[v]![key]];
        final distinct = vals.map((x) => jsonLiteral(x)).toSet();
        if (distinct.length == vals.length) distinguishing.add(key);
      }
      if (distinguishing.isEmpty) continue;

      distinguishing.sort((a, b) {
        int rank(String k) {
          if (k == group.first.discriminatorKey) return 0;
          if (k == 'category' || k == 'type' || k == 'name' || k == 'tag') {
            return 1;
          }
          return 2;
        }

        final c = rank(a).compareTo(rank(b));
        return c != 0 ? c : a.compareTo(b);
      });

      final extra = distinguishing
          .where((k) => k != group.first.discriminatorKey)
          .toList();
      if (extra.isEmpty) continue;
      final useKeys = <String>[
        if (group.first.discriminatorKey != null) group.first.discriminatorKey!,
        extra.first,
      ];

      for (final v in group) {
        final m = litMaps[v]!;
        v.discriminatorLiterals = [
          for (final k in useKeys)
            if (m.containsKey(k)) MapEntry(k, m[k]),
        ];
      }
    }
  }

  /// Minimal shape describing a union variant for identical-twin dedupe:
  /// same kind + same canonical shape means the same match guard and the
  /// same parse, so later twins are unreachable dead code.
  dynamic _variantDedupeShape(VariantInfo v) {
    switch (v.kind) {
      case 'object':
        return v.objectSchema;
      case 'tagged_object':
        return {'tag': v.payloadKey, 'schema': v.payloadSchema};
      case 'ref':
        return {'ref': v.refType, 'kind': v.refKind};
      case 'primitive':
        return {'prim': v.primitiveType};
      case 'string_const':
        return {'const': v.constValue};
      default:
        return {'tag': v.tag, 'kind': v.kind};
    }
  }

  String _genUnion(
    String dartName,
    Map<String, dynamic> schema,
    String original,
  ) {
    final variantsRaw = asList(schema['oneOf'] ?? schema['anyOf'] ?? const []);
    final variants = <VariantInfo>[];
    final usedNames = <String>{};

    for (var i = 0; i < variantsRaw.length; i++) {
      final v = _parseVariant(dartName, variantsRaw[i], i, usedNames);
      if (v != null) {
        variants.add(v);
        usedNames.add(v.className);
      }
    }

    // Drop structurally-identical variants (same kind + same canonical
    // shape — descriptions/titles ignored, e.g. Tezos specs repeating one
    // event object 4x): only the first stays reachable, the rest would be
    // dead `if` branches. The collapse is recorded on the parent doc below,
    // so it stays visible instead of silent.
    final absorbed = <String, List<String>>{};
    {
      final seen = <String, String>{};
      variants.removeWhere((v) {
        final key = '${v.kind}\u0001${_canonicalKey(_variantDedupeShape(v))}';
        final prev = seen[key];
        if (prev == null) {
          seen[key] = v.className;
          return false;
        }
        absorbed.putIfAbsent(prev, () => []).add(v.className);
        return true;
      });
    }

    _applyExplicitDiscriminator(schema, variants);
    _assignDiscriminators(variants);
    _refineCollidingDiscriminators(variants);
    _finalizeVariantMatches(variants);

    // Special case: all variants are single-string enums -> pure string sealed
    if (variants.isNotEmpty &&
        variants.every((v) => v.kind == 'string_const')) {
      final fake = <String, dynamic>{
        if (schema['description'] != null) 'description': schema['description'],
        'enum': variants.map((v) => v.constValue).toList(),
        'type': 'string',
      };
      return _genStringEnum(dartName, fake, original);
    }

    final lines = <String>[];
    var doc = _docWithEndpoints(schema, original);

    // Some schemas declare `properties`/`required` as *siblings* of
    // oneOf/anyOf (e.g. NEAR's RpcQueryResponse: block_hash/block_height
    // are common to every variant). Every variant must carry these too —
    // but only when every variant is guaranteed to parse from a Map (ref
    // to an object-shaped schema, a struct variant, or a tagged-object
    // variant); mixing shared object-level properties with a bare
    // primitive/string-constant variant is contradictory, so that
    // combination falls back to the old shared-less behavior with a [TODO]
    // instead of generating broken code.
    var sharedFields = _objectFields(schema, dartName);
    final supportsShared = variants.every((v) {
      if (v.kind == 'object' || v.kind == 'tagged_object') return true;
      if (v.kind == 'ref') return v.refKind == 'object';
      return false;
    });
    if (sharedFields.isNotEmpty && !supportsShared) {
      final todo =
          '/// TODO: this union also declares shared `properties` '
          '(${sharedFields.map((f) => f.jsonKey).join(', ')}) alongside its '
          'oneOf/anyOf variants, but at least one variant is a bare '
          'primitive/string-constant or a non-object \$ref — mixing those '
          "with shared object-level properties isn't supported, so the "
          'shared fields are NOT included below. Handle them manually if '
          'you need them.\n';
      doc = doc.isNotEmpty ? '$doc$todo' : todo;
      sharedFields = [];
    }

    lines.add(doc.trimRight());
    if (absorbed.isNotEmpty) {
      for (final e in absorbed.entries) {
        lines.add(
          '/// NOTE: structurally-identical oneOf/anyOf branch(es) '
          '${e.value.join(', ')} parse as ${e.key}; no separate class generated.',
        );
      }
    }
    lines.add('sealed class $dartName {');
    for (final f in sharedFields) {
      final nullSuffix = _fieldTypeSuffix(f);
      lines.addAll(_fieldDocLines(f));
      lines.add('  final ${f.typeRef.dartType}$nullSuffix ${f.dartName};');
    }
    if (sharedFields.isEmpty) {
      lines.add('  const $dartName();');
    } else {
      lines.add('');
      lines.add('  const $dartName({');
      for (final f in sharedFields) {
        lines.add(
          f.optional
              ? '    this.${f.dartName},'
              : '    required this.${f.dartName},',
        );
      }
      lines.add('  });');
    }
    lines.add('');
    lines.add('  factory $dartName.fromJson(dynamic json) {');
    lines.addAll(_unionFromJsonBody(dartName, variants, sharedFields));
    lines.add('  }');
    lines.add('');
    lines.add('  dynamic toJson($_toJsonParams);');
    lines.add('}');
    lines.add('');

    for (final v in variants) {
      lines.add(_genVariantClass(dartName, v, sharedFields));
      lines.add('');
    }

    return lines.join('\n').trimRight();
  }

  String _uniqueVariantName(String base, Set<String> used) {
    var name = base;
    var i = 2;
    while (used.contains(name) ||
        generated.containsKey(name) ||
        emitted.contains(name) ||
        _collidesWithSchema(name) ||
        classNames.contains(name) ||
        sealedNames.contains(name) ||
        typedefNames.contains(name)) {
      name = '$base$i';
      i++;
    }
    return name;
  }

  VariantInfo? _parseVariant(
    String parent,
    dynamic rawAny,
    int index,
    Set<String> used,
  ) {
    final schemaResolved = rawAny is Map ? _resolve(rawAny) : rawAny;
    var schema = asMapOrNull(schemaResolved);
    if (schema == null) return null;
    if (isNullSchema(schema) || isUnitNullEnum(schema)) return null;

    final raw = asMapOrNull(rawAny);
    final title = (schema['title'] ?? raw?['title']) as String?;

    // string const enum: { "enum": ["FullAccess"], "type": "string" }
    if (schema.containsKey('enum') &&
        (schema['type'] == null || primaryType(schema['type']) == 'string')) {
      final vals = asList(schema['enum']).where((x) => x != null).toList();
      if (vals.length == 1 && vals[0] is String) {
        final tag = vals[0] as String;
        final cls = _uniqueVariantName(variantClassName(parent, tag), used);
        return VariantInfo(
          tag: tag,
          className: cls,
          kind: 'string_const',
          constValue: tag,
          title: title,
        );
      }
    }

    // pure $ref
    if (raw != null &&
        raw.containsKey('\$ref') &&
        raw.keys.toSet().difference({
          '\$ref',
          'description',
          'title',
          'nullable',
        }).isEmpty) {
      final rname = refName(raw['\$ref'] as String);
      _ensureSchema(rname);
      final dart = _dartName(rname);
      final kind = kindOf[rname] ?? 'object';
      if (kind == 'null_unit') {
        final cls = _uniqueVariantName(variantClassName(parent, rname), used);
        return VariantInfo(
          tag: rname,
          className: cls,
          kind: 'primitive',
          primitiveType: 'Null',
          title: title ?? rname,
        );
      }
      if (kind == 'alias' || kind == 'ref' || kind == 'ref_alias') {
        final cls = _uniqueVariantName(variantClassName(parent, rname), used);
        // Primitive aliases are inlined (no typedef emitted) — resolve to
        // the primitive so dispatch (`json is num`, `BigInt.parse`, ...)
        // keys off the real wire type.
        final resolved = _resolveTypedefTarget(dart);
        return VariantInfo(
          tag: rname,
          className: cls,
          kind: 'primitive',
          primitiveType: _isPrimitiveName(resolved) ? resolved : dart,
          title: title ?? rname,
        );
      }
      if (kind == 'alias_array') {
        final cls = _uniqueVariantName(variantClassName(parent, rname), used);
        return VariantInfo(
          tag: rname,
          className: cls,
          kind: 'ref',
          refType: dart,
          refKind: 'alias_array',
          title: title ?? rname,
        );
      }
      final cls = _uniqueVariantName(variantClassName(parent, rname), used);
      return VariantInfo(
        tag: rname,
        className: cls,
        kind: 'ref',
        refType: dart,
        refKind: kind,
        title: title ?? rname,
      );
    }

    // allOf merge
    if (schema.containsKey('allOf')) {
      schema = _mergeAllOf(schema);
    }

    // tagged single-key object: { "FunctionCall": <schema> }
    // Only PascalCase keys (JSON-RPC / ADT style). Do NOT treat
    // { "status": "skipped" } or { "kind": "..." } as tagged — those are
    // ordinary struct variants with a literal discriminator field.
    final props = asMap(schema['properties']);
    final required = asList(schema['required']).cast<String>();
    if ((primaryType(schema['type']) == 'object' || props.isNotEmpty) &&
        props.length == 1) {
      final key = props.keys.first;
      if (RegExp(r'^[A-Z]').hasMatch(key)) {
        final cls = _uniqueVariantName(variantClassName(parent, key), used);
        return VariantInfo(
          tag: key,
          className: cls,
          kind: 'tagged_object',
          payloadKey: key,
          payloadSchema: asMapOrNull(props[key]) ?? {},
          title: title ?? key,
        );
      }
    }

    // object with multiple fields (struct variant)
    if (props.isNotEmpty || primaryType(schema['type']) == 'object') {
      final rt = asMapOrNull(props['request_type']);
      String tag;
      if (rt != null &&
          rt['enum'] is List &&
          (rt['enum'] as List).length == 1) {
        tag = (rt['enum'] as List)[0].toString();
      } else if (title != null) {
        tag = title;
      } else {
        tag = required.isNotEmpty ? required.join('_') : 'variant$index';
      }
      final cls = _uniqueVariantName(
        variantClassName(parent, snakeToCamel(tag, capitalizeFirst: true)),
        used,
      );
      // NOTE: keep the spec's `required` as-is. When the schema declares
      // no `required`, requiredKeys stays empty (keyless variant) instead
      // of being synthesized as "all properties". Synthesizing all-props
      // forces Phase-4 to emit `hasValue(a) && hasValue(b) && ...`, which
      // is unreachable for real payloads carrying only a subset — while
      // the generated class itself accepts any subset (all nullable).
      // Keyless variants are matched via exclusive-key `||` / fallback
      // in Phase-4 instead.
      final reqKeys = asList(
        schema['required'],
      ).map((e) => e.toString()).toList();
      return VariantInfo(
        tag: tag,
        className: cls,
        kind: 'object',
        objectSchema: schema,
        title: title ?? tag,
        requiredKeys: reqKeys,
      );
    }
    // nested union: this variant's own schema is itself oneOf/anyOf (no
    // $ref, no properties at this level) — generate it as its own inline
    // sealed class and wrap it, the same way a $ref to a top-level union
    // variant is already handled.
    if (schema.containsKey('oneOf') || schema.containsKey('anyOf')) {
      final tag = title ?? 'variant$index';
      final cls = _uniqueVariantName(variantClassName(parent, tag), used);
      final hint = '${cls}Value';
      final inner = _inlineUnion(schema, hint, false);
      // An int64-as-string pair collapses to a plain BigInt (no sealed
      // class) — model it as a primitive variant so fromJson passes the
      // value through instead of calling a non-existent `.fromJson`.
      if (inner.kind == 'primitive' || inner.kind == 'typedef') {
        return VariantInfo(
          tag: tag,
          className: cls,
          kind: 'primitive',
          primitiveType: inner.dartType,
          title: title ?? tag,
        );
      }
      // Keep schema so we can promote shared inner discriminators (e.g. all
      // Applied/* branches share status:"applied") onto this wrapper.
      return VariantInfo(
        tag: tag,
        className: cls,
        kind: 'ref',
        refType: inner.dartType,
        refKind: 'union',
        title: title ?? tag,
        objectSchema: schema,
      );
    }
    // primitive
    final t = primaryType(schema['type']);
    if (t == 'string' || t == 'integer' || t == 'number' || t == 'boolean') {
      final prim = _primitiveDartType(schema);
      final tag = title ?? (t ?? 'prim$index');
      final cls = _uniqueVariantName(
        variantClassName(parent, snakeToCamel(tag, capitalizeFirst: true)),
        used,
      );
      return VariantInfo(
        tag: tag,
        className: cls,
        kind: 'primitive',
        primitiveType: prim,
        title: title,
      );
    }

    // array — resolve item type so fromJson can map elements via .fromJson
    if (t == 'array') {
      final tag = title ?? 'list$index';
      final cls = _uniqueVariantName(
        variantClassName(parent, snakeToCamel(tag, capitalizeFirst: true)),
        used,
      );
      final tr = _typeRef(schema, hintName: cls);
      return VariantInfo(
        tag: tag,
        className: cls,
        kind: 'primitive',
        primitiveType: tr.dartType,
        title: title,
      );
    }

    // fallback
    final tag = title ?? 'variant$index';
    final cls = _uniqueVariantName(
      variantClassName(parent, snakeToCamel(tag, capitalizeFirst: true)),
      used,
    );
    return VariantInfo(
      tag: tag,
      className: cls,
      kind: 'primitive',
      primitiveType: 'dynamic',
      title: title,
    );
  }

  String _aliasArrayFromJsonExpr(String typedefName, String listExpr) {
    // Callers invoke this inside `if (<listExpr> is List)`, so when the
    // expression is a plain promotable variable (e.g. `json`) an extra
    // `as List` cast trips the `unnecessary_cast` lint — use it directly.
    final listVal = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(listExpr)
        ? listExpr
        : '($listExpr as List)';
    String? schemaName;
    for (final e in schemas.entries) {
      if (_dartName(e.key) == typedefName) {
        schemaName = e.key;
        break;
      }
    }
    if (schemaName == null) {
      return 'List<dynamic>.from($listExpr) as $typedefName';
    }
    final schema = asMap(schemas[schemaName]);
    final items = asMap(schema['items']);
    // Inline oneOf/anyOf/allOf items (e.g. nanotez = array of oneOf[bignum])
    if (items.containsKey('oneOf') ||
        items.containsKey('anyOf') ||
        items.containsKey('allOf')) {
      final itemTr = _typeRef(items, hintName: '${typedefName}Item');
      final parse = itemTr.effectiveParseType;
      if (itemTr.kind == 'class' ||
          itemTr.kind == 'sealed' ||
          itemTr.kind == 'string_enum' ||
          itemTr.kind == 'union') {
        return '$listVal.map((e) => $parse.fromJson(e)).toList()';
      }
      return '$listVal.map((e) => $parse.fromJson(e)).toList() as $typedefName';
    }
    if (primaryType(items['type']) == 'array') {
      final inner = asMap(items['items']);
      final innerRef = inner['\$ref'];
      if (innerRef is String) {
        final iname = refName(innerRef);
        _ensureSchema(iname);
        final idart = _dartName(iname);
        final ikind = kindOf[iname] ?? 'object';
        if (ikind == 'object' || ikind == 'union' || ikind == 'string_enum') {
          return '$listVal.map((e) => (e as List).map((x) => $idart.fromJson(x)).toList()).toList()';
        }
        return '$listVal.map((e) => List<dynamic>.from(e as List)).toList() as $typedefName';
      }
      return '$listVal.map((e) => List<dynamic>.from(e as List)).toList() as $typedefName';
    }
    final ref = items['\$ref'];
    if (ref is String) {
      final iname = refName(ref);
      _ensureSchema(iname);
      final idart = _dartName(iname);
      final ikind = kindOf[iname] ?? 'object';
      if (ikind == 'object' || ikind == 'union' || ikind == 'string_enum') {
        return '$listVal.map((e) => $idart.fromJson(e)).toList()';
      }
      // Primitive aliases are inlined (no typedef emitted) — cast to the
      // resolved primitive instead of the dangling typedef name.
      final resolved = _resolveTypedefTarget(idart);
      if (_isPrimitiveName(resolved)) {
        return '$listVal.cast<$resolved>().toList()';
      }
      return '$listVal.cast<$idart>().toList()';
    }
    final t = primaryType(items['type']);
    if (t == 'string') {
      return '$listVal.cast<String>().toList()';
    }
    if (t == 'integer') {
      return '$listVal.map((e) => (e as num).toInt()).toList()';
    }
    if (t == 'number') {
      return '$listVal.cast<num>().toList()';
    }
    if (t == 'boolean') {
      return '$listVal.cast<bool>().toList()';
    }
    return 'List<dynamic>.from($listExpr) as $typedefName';
  }

  /// Promote shared discriminators from nested oneOf wrappers, compute
  /// exclusive keys, and ensure requiredKeys is populated for objects.
  void _finalizeVariantMatches(List<VariantInfo> variants) {
    // Populate requiredKeys from objectSchema when missing.
    // Keep keyless variants keyless: an object schema with no `required`
    // must NOT synthesize requiredKeys=all properties (that produces an
    // unreachable `&&`-over-all-props guard for payloads with subsets).
    for (final v in variants) {
      if (v.objectSchema == null) continue;
      if (v.requiredKeys.isEmpty && v.kind == 'object') {
        final req = asList(v.objectSchema!['required']);
        v.requiredKeys = req.map((e) => e.toString()).toList();
      }
      // Nested union wrapper (Applied / Backtracked): if every concrete
      // object branch shares the same literal for a key (status/kind),
      // promote it onto the wrapper so the parent can branch without try/catch.
      if (v.kind == 'ref' &&
          v.refKind == 'union' &&
          v.discriminatorKey == null &&
          (v.objectSchema!.containsKey('oneOf') ||
              v.objectSchema!.containsKey('anyOf'))) {
        final branches = asList(
          v.objectSchema!['oneOf'] ?? v.objectSchema!['anyOf'],
        );
        final litMaps = <Map<String, dynamic>>[];
        for (final b in branches) {
          final schema = asMapOrNull(_resolve(b));
          if (schema == null) continue;
          final props = asMap(schema['properties']);
          if (props.isEmpty &&
              (schema.containsKey('oneOf') || schema.containsKey('anyOf'))) {
            // one more level (rare)
            continue;
          }
          final m = <String, dynamic>{};
          for (final e in props.entries) {
            final lit = _literalValue(e.value);
            if (lit.key) m[e.key] = lit.value;
          }
          if (m.isNotEmpty) litMaps.add(m);
        }
        if (litMaps.isNotEmpty) {
          final commonKeys = litMaps.first.keys.toSet();
          for (final m in litMaps.skip(1)) {
            commonKeys.retainAll(m.keys);
          }
          for (final key in [
            'status',
            'kind',
            'request_type',
            'type',
            'name',
            'tag',
            ...commonKeys,
          ]) {
            if (!commonKeys.contains(key)) continue;
            final vals = litMaps.map((m) => jsonLiteral(m[key])).toSet();
            if (vals.length == 1) {
              v.discriminatorKey = key;
              v.discriminatorValue = litMaps.first[key];
              break;
            }
          }
        }
      }
    }

    // Exclusive property keys among object siblings.
    final objects = variants
        .where((v) => v.kind == 'object' && v.objectSchema != null)
        .toList();
    if (objects.length >= 2) {
      final propSets = <VariantInfo, Set<String>>{
        for (final v in objects)
          v: asMap(
            v.objectSchema!['properties'],
          ).keys.map((k) => k.toString()).toSet(),
      };
      for (final v in objects) {
        final others = <String>{};
        for (final o in objects) {
          if (identical(o, v)) continue;
          others.addAll(propSets[o]!);
        }
        v.exclusiveKeys = propSets[v]!.difference(others).toList()..sort();
      }
    }

    // When several objects share the same discriminator value, append
    // required-only keys (and exclusive keys) into discriminatorLiterals
    // / match metadata via exclusive presence.
    final byDisc = <String, List<VariantInfo>>{};
    for (final v in objects) {
      if (v.discriminatorKey == null) continue;
      final sig =
          '${v.discriminatorKey}\u0001${jsonLiteral(v.discriminatorValue)}';
      byDisc.putIfAbsent(sig, () => []).add(v);
    }
    for (final group in byDisc.values) {
      if (group.length < 2) continue;
      // Prefer more required keys first at emission; also build
      // discriminatorLiterals = primary + exclusive presence is handled
      // in _objectMatchCondition.
      // Ensure each has requiredKeys sorted by length for ranking later.
      for (final v in group) {
        if (v.discriminatorLiterals == null ||
            v.discriminatorLiterals!.isEmpty) {
          v.discriminatorLiterals = [
            MapEntry(v.discriminatorKey!, v.discriminatorValue),
          ];
        }
      }
    }

    _promoteRefLiterals(variants);
    _refineRefDiscriminators(variants);
  }

  /// Backfills `requiredKeys` for `$ref`-to-object variants and promotes a
  /// single-literal pin from the target (e.g. `standard: enum [nep413]`) to
  /// a discriminator on the wrapper. Without this, same-required-key
  /// siblings with different literal values emit identical `hasValue`
  /// guards where only the first branch is reachable.
  void _promoteRefLiterals(List<VariantInfo> variants) {
    for (final v in variants) {
      if (v.kind != 'ref' ||
          (v.refKind ?? 'object') != 'object' ||
          v.refType == null) {
        continue;
      }
      if (v.requiredKeys.isEmpty) {
        v.requiredKeys = _refVariantRequiredKeys(v);
      }
      if (v.discriminatorKey != null) continue;
      final target = _refTargetSchema(v);
      if (target.isEmpty) continue;
      final props = asMap(target['properties']);
      final req = v.requiredKeys.toSet();
      // Only required-key pins discriminate reliably (an optional pin may
      // simply be absent from the payload).
      final ordered = props.keys.map((k) => k.toString()).toList()
        ..sort(_preferDiscriminatorKey);
      for (final key in ordered) {
        if (!req.contains(key)) continue;
        final lit = _literalValue(props[key]);
        if (lit.key) {
          v.discriminatorKey = key;
          v.discriminatorValue = lit.value;
          break;
        }
      }
    }
  }

  /// Resolves same-literal collisions between `$ref` siblings (mirrors
  /// [_refineCollidingDiscriminators] for inline objects): appends a second
  /// distinguishing literal when one exists, else descends one level into
  /// `$ref`-typed required properties (nested presence paths), else marks
  /// the group genuinely ambiguous.
  void _refineRefDiscriminators(List<VariantInfo> variants) {
    final byDisc = <String, List<VariantInfo>>{};
    for (final v in variants) {
      if (v.kind != 'ref' ||
          (v.refKind ?? 'object') != 'object' ||
          v.discriminatorKey == null) {
        continue;
      }
      final sig =
          '${v.discriminatorKey}\u0001${jsonLiteral(v.discriminatorValue)}';
      byDisc.putIfAbsent(sig, () => []).add(v);
    }
    for (final group in byDisc.values) {
      if (group.length < 2) continue;
      if (_assignRefSecondaryLiteral(group)) continue;
      if (_assignNestedRefDiscriminators(group)) continue;
      if (_assignPatternGuards(group)) continue;
      final names = group.map((v) => v.className).toList();
      for (final v in group) {
        v.ambiguousWith = names.where((n) => n != v.className).toList();
      }
    }
    // Nested descent also applies to same-required-key ties with NO
    // literals at all (e.g. Stellar vs XRPL transactions sharing every
    // top-level required key but differing in a nested `data` object).
    final byReq = <String, List<VariantInfo>>{};
    for (final v in variants) {
      if (v.kind != 'ref' ||
          (v.refKind ?? 'object') != 'object' ||
          v.discriminatorKey != null ||
          v.requiredKeys.isEmpty) {
        continue;
      }
      final sig = [...v.requiredKeys]..sort();
      byReq.putIfAbsent(sig.join('\u0001'), () => []).add(v);
    }
    for (final group in byReq.values) {
      if (group.length < 2) continue;
      if (_assignNestedRefDiscriminators(group)) continue;
      if (_assignPatternGuards(group)) continue;
      final names = group.map((v) => v.className).toList();
      for (final v in group) {
        v.ambiguousWith ??= names.where((n) => n != v.className).toList();
      }
    }
  }

  /// Appends a second distinguishing required literal to every member of a
  /// same-primary-literal `$ref` group. Returns true on success.
  bool _assignRefSecondaryLiteral(List<VariantInfo> group) {
    final litMaps = <VariantInfo, Map<String, dynamic>>{};
    for (final v in group) {
      final m = <String, dynamic>{};
      final req = v.requiredKeys.toSet();
      for (final e in _refTargetLiterals(v).entries) {
        if (req.contains(e.key)) m[e.key] = e.value;
      }
      litMaps[v] = m;
    }
    final allKeys = <String>{};
    for (final m in litMaps.values) {
      allKeys.addAll(m.keys);
    }
    final distinguishing = <String>[];
    for (final key in allKeys) {
      if (!litMaps.values.every((m) => m.containsKey(key))) continue;
      final vals = [for (final v in group) litMaps[v]![key]];
      final distinct = vals.map((x) => jsonLiteral(x)).toSet();
      if (distinct.length == vals.length) distinguishing.add(key);
    }
    if (distinguishing.isEmpty) return false;
    distinguishing.sort(_preferDiscriminatorKey);
    final extra = distinguishing
        .where((k) => k != group.first.discriminatorKey)
        .toList();
    if (extra.isEmpty) return false;
    final useKeys = <String>[group.first.discriminatorKey!, extra.first];
    for (final v in group) {
      final m = litMaps[v]!;
      v.discriminatorLiterals = [
        for (final k in useKeys)
          if (m.containsKey(k)) MapEntry(k, m[k]),
      ];
    }
    return true;
  }

  /// One-level nested disambiguation for tied `$ref` siblings: when members
  /// require the same top-level properties, descend into a `$ref`-typed
  /// property and compare the nested targets' required keys. A nested key
  /// required in exactly one member identifies it via a `[prop, key]`
  /// presence path. Members whose nested target is unresolvable (free-form
  /// catch-alls like JsonNode) simply keep their top-level guard as a
  /// sound fallback — they are tried after the precise nested guards.
  /// Returns true when at least one member gained a presence path.
  bool _assignNestedRefDiscriminators(List<VariantInfo> group) {
    if (group.length < 2) return false;
    // Candidate props: union of members' required keys (a member whose
    // nested target is unresolvable owns nothing for that prop).
    final candidates = <String>{};
    for (final v in group) {
      candidates.addAll(v.requiredKeys);
    }
    for (final prop in [...candidates]..sort()) {
      final nestedReq = <VariantInfo, List<String>?>{};
      final nestedProps = <VariantInfo, Set<String>?>{};
      for (final v in group) {
        if (!v.requiredKeys.contains(prop)) {
          nestedReq[v] = null;
          nestedProps[v] = null;
          continue;
        }
        final nested = _refNestedObjectSchema(v, prop);
        nestedReq[v] = nested == null
            ? null
            : asList(nested['required']).map((e) => e.toString()).toList();
        nestedProps[v] = nested == null
            ? null
            : asMap(nested['properties']).keys.map((k) => k.toString()).toSet();
      }
      final allNested = <String>{};
      for (final keys in nestedReq.values) {
        if (keys != null) allNested.addAll(keys);
      }
      var assigned = false;
      for (final key in [...allNested]..sort()) {
        final owners = [
          for (final e in nestedReq.entries)
            if (e.value != null && e.value!.contains(key)) e.key,
        ];
        // The key must be required in exactly one member AND absent
        // (even optionally) from every other member's nested target —
        // otherwise a payload could legitimately carry it elsewhere.
        if (owners.length != 1) continue;
        final elsewhere = group.any(
          (o) =>
              !identical(o, owners.first) &&
              (nestedProps[o]?.contains(key) ?? false),
        );
        if (elsewhere) continue;
        if (owners.first.presencePath == null) {
          owners.first.presencePath = [prop, key];
          owners.first.presencePositive = true;
          assigned = true;
        }
      }
      if (assigned) return true;
    }
    return false;
  }

  /// Full boolean condition for matching an object (or promoted ref) variant.
  String _objectMatchCondition(VariantInfo v) {
    final parts = <String>[];
    if (v.discriminatorLiterals != null &&
        v.discriminatorLiterals!.isNotEmpty) {
      for (final e in v.discriminatorLiterals!) {
        parts.add(
          "map['${escapeDartString(e.key)}'] == ${jsonLiteral(e.value)}",
        );
      }
    } else if (v.discriminatorKey != null) {
      parts.add(
        "map['${escapeDartString(v.discriminatorKey!)}'] == "
        '${jsonLiteral(v.discriminatorValue)}',
      );
    }
    // Anchored pattern-prefix pins (last-resort tiebreaker). Null-safe:
    // absent/wrong-typed values simply don't match.
    final patternKeys = <String>{};
    if (v.patternGuards != null) {
      for (final e in v.patternGuards!) {
        parts.add(_patternCondition(e.key, e.value));
        patternKeys.add(e.key);
      }
    }
    // Extra required keys not already constrained by discriminators or
    // pattern pins (a startsWith check subsumes presence).
    final discKeys = <String>{
      if (v.discriminatorKey != null) v.discriminatorKey!,
      if (v.discriminatorLiterals != null)
        ...v.discriminatorLiterals!.map((e) => e.key),
    };
    final extraReq = v.requiredKeys
        .where((k) => !discKeys.contains(k) && !patternKeys.contains(k))
        .toList();
    // When siblings share the same primary discriminator, require the
    // *extra* required keys so the more-specific variant wins first.
    for (final k in extraReq) {
      parts.add("map.hasValue('${escapeDartString(k)}')");
    }
    return parts.isEmpty ? 'true' : parts.join(' && ');
  }

  int _variantMatchScore(VariantInfo v) {
    // Higher = checked first.
    var score = 0;
    if (v.discriminatorLiterals != null) {
      score += 100 * v.discriminatorLiterals!.length;
    } else if (v.discriminatorKey != null) {
      score += 100;
    }
    if (v.patternGuards != null && v.patternGuards!.isNotEmpty) {
      score += 100;
    }
    if (v.presencePath != null) score += 80;
    // Extra required keys (beyond discriminator) make a variant more specific.
    final discKeys = <String>{
      if (v.discriminatorKey != null) v.discriminatorKey!,
      if (v.discriminatorLiterals != null)
        ...v.discriminatorLiterals!.map((e) => e.key),
    };
    final extraReq = v.requiredKeys.where((k) => !discKeys.contains(k)).length;
    score += 30 * extraReq;
    score += 20 * v.exclusiveKeys.length;
    if (v.kind == 'object') score += 2;
    if (v.kind == 'ref' && v.refKind == 'union') score += 1;
    return score;
  }

  /// True if [v] can represent an arbitrary JSON string (not a fixed const).
  bool _variantAcceptsFreeString(VariantInfo v) {
    if (v.kind == 'primitive') {
      final p = v.primitiveType ?? '';
      final underlying = typedefTarget[p] ?? p;
      return underlying == 'String' || p == 'String';
    }
    if (v.kind == 'ref' && v.refType != null) {
      final name = v.refType!;
      // Unistring and Protocol_hash-style sealed aliases accept plain strings.
      if (name == 'Unistring' ||
          name.endsWith('Unistring') ||
          name == 'ProtocolHash' ||
          sealedNames.contains(name) ||
          classNames.contains(name)) {
        return true;
      }
      if (v.refKind == 'union' ||
          v.refKind == 'string_enum' ||
          v.refKind == 'alias' ||
          v.refKind == 'ref_alias') {
        return true;
      }
    }
    return false;
  }

  /// Prefer title "named" / unistring-ish refs when choosing a free-string sink.
  VariantInfo? _firstFreeStringVariant(List<VariantInfo> variants) {
    final candidates = variants.where(_variantAcceptsFreeString).toList();
    if (candidates.isEmpty) return null;
    for (final v in candidates) {
      final t = (v.title ?? v.tag).toLowerCase();
      if (t == 'named' || t.contains('unistring') || t == 'string') {
        return v;
      }
    }
    for (final v in candidates) {
      if (v.refType == 'Unistring' ||
          (v.refType?.endsWith('Unistring') ?? false)) {
        return v;
      }
    }
    return candidates.first;
  }

  String _freeStringConstructExpr(VariantInfo v, String jsonVar) {
    if (v.kind == 'primitive') {
      return '${v.className}($jsonVar)';
    }
    if (v.kind == 'ref' && v.refType != null) {
      return '${v.className}(${v.refType}.fromJson($jsonVar))';
    }
    return '${v.className}.fromJson($jsonVar)';
  }

  /// Original component schema name backing the Dart type [dartName], or
  /// null when [dartName] is an inline (non-component) generated type.
  String? _componentNameForDartType(String dartName) {
    for (final e in schemas.entries) {
      if (_dartName(e.key) == dartName) return e.key;
    }
    return null;
  }

  /// Required property names of the object schema behind a `$ref` union
  /// variant's target type. Empty when the target is not object-shaped
  /// (nested union / enum / alias / map-catchall / unknown).
  ///
  /// Used to match `$ref`-to-object branches structurally
  /// (`map.hasValue('Error')`) instead of speculative try/catch — which
  /// selects the *wrong* class whenever an all-optional branch parses
  /// without throwing (e.g. `Account` swallowing a `JavaTronError` map).
  List<String> _refVariantRequiredKeys(VariantInfo v) {
    if (v.kind != 'ref' || v.refType == null) return const [];
    if ((v.refKind ?? 'object') != 'object') return const [];
    final schemaName = _componentNameForDartType(v.refType!);
    if (schemaName == null) return const [];
    final target = _unwrap(asMap(schemas[schemaName]));
    if (target.containsKey('oneOf') || target.containsKey('anyOf')) {
      return const [];
    }
    final props = asMap(target['properties']);
    if (props.isEmpty) return const []; // map-catchall / empty object
    return asList(target['required']).map((e) => e.toString()).toList();
  }

  /// Unwrapped object schema behind a `$ref`-to-object union variant's
  /// target type, or `{}` when the target is not a plain object schema
  /// (nested union / enum / alias / unknown / inline type).
  Map<String, dynamic> _refTargetSchema(VariantInfo v) {
    if (v.kind != 'ref' || v.refType == null) return {};
    if ((v.refKind ?? 'object') != 'object') return {};
    final schemaName = _componentNameForDartType(v.refType!);
    if (schemaName == null) return {};
    final target = _unwrap(asMap(schemas[schemaName]));
    if (target.containsKey('oneOf') || target.containsKey('anyOf')) return {};
    if (asMap(target['properties']).isEmpty) return {};
    return target;
  }

  /// Single-literal pins (`const: x` / `enum: [x]`) on a `$ref` variant
  /// target's properties: `{propName: literal}`. Used to promote target
  /// literals (e.g. `standard: enum [nep413]`) onto the wrapper as
  /// discriminators.
  Map<String, dynamic> _refTargetLiterals(VariantInfo v) {
    final target = _refTargetSchema(v);
    if (target.isEmpty) return {};
    final out = <String, dynamic>{};
    for (final e in asMap(target['properties']).entries) {
      final lit = _literalValue(e.value);
      if (lit.key) out[e.key.toString()] = lit.value;
    }
    return out;
  }

  /// Rank order for discriminator literal keys: tag-like keys first (same
  /// bias as the inline-object path), then alphabetical for stability.
  int _preferDiscriminatorKey(String a, String b) {
    int rank(String k) {
      if (k == 'request_type' ||
          k == 'type' ||
          k == 'kind' ||
          k == 'name' ||
          k == 'tag' ||
          k == 'status' ||
          k == 'standard') {
        return 0;
      }
      return 1;
    }

    final c = rank(a).compareTo(rank(b));
    return c != 0 ? c : a.compareTo(b);
  }

  /// Resolved object schema of a required property [prop] on a `$ref`
  /// variant's target (following a single `$ref`/allOf hop), or null when
  /// the property is not object-shaped. Used for one-level nested
  /// disambiguation of shape-identical `$ref` siblings.
  Map<String, dynamic>? _refNestedObjectSchema(VariantInfo v, String prop) {
    final target = _refTargetSchema(v);
    if (target.isEmpty) return null;
    final ps = asMapOrNull(asMap(target['properties'])[prop]);
    if (ps == null) return null;
    Map<String, dynamic>? node = ps;
    for (var i = 0; i < 3 && node != null; i++) {
      if (node.containsKey('\$ref')) {
        node = asMapOrNull(schemas[refName(node['\$ref'] as String)]);
        continue;
      }
      if (node.containsKey('allOf')) node = _mergeAllOf(node);
      break;
    }
    if (node == null) return null;
    if (node.containsKey('oneOf') || node.containsKey('anyOf')) return null;
    if (asMap(node['properties']).isEmpty) return null;
    if (primaryType(node['type']) != null &&
        primaryType(node['type']) != 'object') {
      return null;
    }
    return node;
  }

  /// Property names declared on a `$ref` variant's target object schema
  /// (resolving allOf parts one level). Used for presence-based matching
  /// of branches that declare no required fields.
  Set<String> _refVariantPropertyKeys(VariantInfo v) {
    if (v.kind != 'ref' || v.refType == null) return const {};
    if ((v.refKind ?? 'object') != 'object') return const {};
    final schemaName = _componentNameForDartType(v.refType!);
    if (schemaName == null) return const {};
    return _objectPropertyKeyUnion(asMap(schemas[schemaName]));
  }

  /// Property keys that may appear on any map-shaped union variant:
  /// inline `object` variants contribute their own `properties`, `$ref`
  /// variants contribute their target's property union. Used to compute
  /// exclusive presence keys for keyless (no-`required`) variants across
  /// object/ref boundaries — e.g. broadcasthex `result/code/...` vs
  /// JavaTronError `Error`.
  Set<String> _mapVariantPropertyKeys(VariantInfo v) {
    if (v.kind == 'object' && v.objectSchema != null) {
      return asMap(
        v.objectSchema!['properties'],
      ).keys.map((k) => k.toString()).toSet();
    }
    if (v.kind == 'ref') return _refVariantPropertyKeys(v);
    return const {};
  }

  /// Union of property names across an object schema, resolving allOf
  /// (including single-level `$ref` parts).
  Set<String> _objectPropertyKeyUnion(
    Map<String, dynamic> schema, [
    int depth = 0,
  ]) {
    if (depth > 6) return const {};
    final out = <String>{
      ...asMap(schema['properties']).keys.map((k) => k.toString()),
    };
    for (final part in asList(schema['allOf'])) {
      final p = asMapOrNull(part);
      if (p == null) continue;
      if (p.containsKey('\$ref')) {
        final target = asMapOrNull(schemas[refName(p['\$ref'] as String)]);
        if (target != null) {
          out.addAll(_objectPropertyKeyUnion(target, depth + 1));
        }
      } else {
        out.addAll(asMap(p['properties']).keys.map((k) => k.toString()));
      }
    }
    return out;
  }

  List<String> _unionFromJsonBody(
    String dartName,
    List<VariantInfo> variants,
    List<FieldInfo> sharedFields,
  ) {
    final lines = <String>[];

    if (sharedFields.isEmpty) {
      // string constants first
      final stringConsts = variants
          .where((v) => v.kind == 'string_const')
          .toList();
      if (stringConsts.isNotEmpty) {
        // Prefer a sibling that can accept arbitrary strings (e.g. Tezos
        // entrypoint "named" → Unistring) so unknown values like "GG" parse
        // instead of throwing at the switch default.
        final freeString = _firstFreeStringVariant(variants);
        lines.add('    if (json is String) {');
        lines.add('      return switch (json) {');
        for (final v in stringConsts) {
          lines.add(
            "        '${escapeDartString(v.constValue.toString())}' => const ${v.className}(),",
          );
        }
        if (freeString != null) {
          final expr = _freeStringConstructExpr(freeString, 'json');
          lines.add('        _ => $expr,');
        } else {
          lines.add(
            "        _ => throw ArgumentException.invalidOperationArguments('$dartName', reason:'Unknown $dartName: \$json'),",
          );
        }
        lines.add('      };');
        lines.add('    }');
      }

      // primitive variants (int/string without const)
      final prims = variants.where((v) => v.kind == 'primitive').toList();
      for (final v in prims) {
        final ptype = v.primitiveType ?? 'dynamic';
        final underlying = typedefTarget[ptype] ?? ptype;
        if (underlying == 'int' || ptype == 'int') {
          lines.add(
            '    if (json is num) return ${v.className}(json.toInt());',
          );
        } else if (underlying == 'BigInt' || ptype == 'BigInt') {
          // int64 / format:int64 → BigInt. Accept JSON numbers and (when
          // this is the only numeric-like branch) digit strings.
          // NOTE: `json` is promoted to num by the `is` check, so
          // `json.toInt()` (not `BigInt.from(json)`, which rejects doubles).
          lines.add(
            '    if (json is num) return ${v.className}(BigInt.from(json.toInt()));',
          );
          // Only claim digit-strings when no sibling String primitive exists,
          // otherwise the String variant must win for plain strings.
          final hasStringPrim = prims.any((o) {
            if (identical(o, v)) return false;
            final ot = o.primitiveType ?? 'dynamic';
            final ou = typedefTarget[ot] ?? ot;
            return ou == 'String' || ot == 'String';
          });
          if (!hasStringPrim) {
            lines.add(
              '    if (json is String) return ${v.className}(BigInt.parse(json));',
            );
          }
        } else if (underlying == 'String' || ptype == 'String') {
          lines.add('    if (json is String) return ${v.className}(json);');
        } else if (underlying == 'bool' || ptype == 'bool') {
          lines.add('    if (json is bool) return ${v.className}(json);');
        } else if (underlying == 'double' ||
            underlying == 'num' ||
            ptype == 'double' ||
            ptype == 'num') {
          lines.add('    if (json is num) return ${v.className}(json);');
        } else if (underlying.startsWith('List') || ptype.startsWith('List')) {
          // List<SomeClass> / List<SomeSealed> -> map via .fromJson
          final listMatch = RegExp(r'^List<(.+)>$').firstMatch(ptype);
          final itemType = listMatch?.group(1);
          if (itemType != null &&
              itemType != 'dynamic' &&
              !itemType.startsWith('List<') &&
              RegExp(r'^[A-Z]').hasMatch(itemType) &&
              !{
                'String',
                'int',
                'bool',
                'num',
                'double',
                'Object',
              }.contains(itemType)) {
            lines.add(
              '    if (json is List) return ${v.className}('
              'json.map((e) => $itemType.fromJson(e)).toList());',
            );
          } else if (itemType != null && itemType.startsWith('List<')) {
            // List<List<T>> — fall back to cast (rare in Tezos schemas)
            lines.add(
              '    if (json is List) return ${v.className}('
              'List<dynamic>.from(json) as $ptype);',
            );
          } else {
            lines.add(
              '    if (json is List) return ${v.className}('
              'List<dynamic>.from(json) as $ptype);',
            );
          }
        } else if (RegExp(r'^[A-Z]').hasMatch(ptype) &&
            [
              'String',
              'int',
              'bool',
              'num',
              'double',
              'BigInt',
            ].contains(underlying)) {
          if (underlying == 'int') {
            lines.add(
              '    if (json is num) return ${v.className}(json.toInt());',
            );
          } else if (underlying == 'BigInt') {
            lines.add(
              '    if (json is num) return ${v.className}(BigInt.from(json.toInt()));',
            );
            final hasStringPrim = prims.any((o) {
              if (identical(o, v)) return false;
              final ot = o.primitiveType ?? 'dynamic';
              final ou = typedefTarget[ot] ?? ot;
              return ou == 'String' || ot == 'String';
            });
            if (!hasStringPrim) {
              lines.add(
                '    if (json is String) return ${v.className}(BigInt.parse(json));',
              );
            }
          } else if (underlying == 'String') {
            lines.add('    if (json is String) return ${v.className}(json);');
          } else if (underlying == 'bool') {
            lines.add('    if (json is bool) return ${v.className}(json);');
          } else {
            lines.add('    if (json is num) return ${v.className}(json);');
          }
        }
      }

      // map-based variants — structural matches only (no try/catch fallthrough).
      final mapVariants = variants.where((v) {
        if (v.kind == 'tagged_object' || v.kind == 'object') return true;
        if (v.kind == 'ref') {
          final rk = v.refKind ?? 'object';
          return rk == 'object' || rk == 'union' || rk == 'string_enum';
        }
        return false;
      }).toList();
      if (mapVariants.isNotEmpty) {
        mapVariants.sort(
          (a, b) => _variantMatchScore(b).compareTo(_variantMatchScore(a)),
        );
        lines.add('    if (json is Map) {');
        lines.add(
          '      final map = json is Map<String, dynamic>'
          ' ? json : Map<String, dynamic>.from(json);',
        );
        // ---- Phase 1: tagged objects ----
        for (final v in mapVariants) {
          if (v.kind == 'tagged_object' && v.payloadKey != null) {
            final key = v.payloadKey!;
            lines.add("      if (map.hasValue('${escapeDartString(key)}')) {");
            lines.addAll(
              indentText(_taggedPayloadConstruct(v, ''), 8).split('\n'),
            );
            lines.add('      }');
          }
        }

        // ---- Phase 2: specific object matches (exclusive / extra required) ----
        for (final v in mapVariants) {
          if (v.kind != 'object' || v.objectSchema == null) continue;
          if (v.discriminatorKey == null &&
              (v.discriminatorLiterals == null ||
                  v.discriminatorLiterals!.isEmpty) &&
              v.presencePath == null &&
              (v.patternGuards == null || v.patternGuards!.isEmpty)) {
            continue; // handled in phase 4
          }
          if (v.presencePath != null) {
            lines.add('      if (${_presenceCheckExpr(v)}) {');
            lines.add('        return ${v.className}.fromJson(map);');
            lines.add('      }');
            continue;
          }
          // Anchored pattern pins are self-sufficient (subsumes presence of
          // the pinned key); bypass the sibling-sharing logic below.
          if (v.patternGuards != null && v.patternGuards!.isNotEmpty) {
            final cond = _objectMatchCondition(v);
            lines.add('      if ($cond) {');
            lines.add('        return ${v.className}.fromJson(map);');
            lines.add('      }');
            continue;
          }
          final cond = _objectMatchCondition(v);
          final siblings = v.discriminatorKey == null
              ? const <VariantInfo>[]
              : mapVariants.where((o) {
                  if (o.kind != 'object') return false;
                  return o.discriminatorKey == v.discriminatorKey &&
                      jsonLiteral(o.discriminatorValue) ==
                          jsonLiteral(v.discriminatorValue);
                }).toList();
          final siblingsShare = siblings.length >= 2;
          final discKeys = <String>{
            if (v.discriminatorKey != null) v.discriminatorKey!,
            if (v.discriminatorLiterals != null)
              ...v.discriminatorLiterals!.map((e) => e.key),
          };
          final extraReq = v.requiredKeys
              .where((k) => !discKeys.contains(k))
              .toList();

          if (siblingsShare) {
            if (v.exclusiveKeys.isNotEmpty) {
              final ex = v.exclusiveKeys
                  .map((k) => "map.hasValue('${escapeDartString(k)}')")
                  .join(' || ');
              lines.add('      if ($cond && ($ex)) {');
              lines.add('        return ${v.className}.fromJson(map);');
              lines.add('      }');
            }
            if (extraReq.isNotEmpty) {
              lines.add('      if ($cond) {');
              lines.add('        return ${v.className}.fromJson(map);');
              lines.add('      }');
            }
            // plain fallback deferred to phase 3
          } else {
            lines.add('      if ($cond) {');
            lines.add('        return ${v.className}.fromJson(map);');
            lines.add('      }');
          }
        }

        // ---- Phase 3: plain disc fallbacks (least specific sibling) ----
        for (final v in mapVariants) {
          if (v.kind != 'object' || v.objectSchema == null) continue;
          if (v.discriminatorKey == null &&
              (v.discriminatorLiterals == null ||
                  v.discriminatorLiterals!.isEmpty)) {
            continue;
          }
          final siblings = v.discriminatorKey == null
              ? const <VariantInfo>[]
              : mapVariants.where((o) {
                  if (o.kind != 'object') return false;
                  return o.discriminatorKey == v.discriminatorKey &&
                      jsonLiteral(o.discriminatorValue) ==
                          jsonLiteral(v.discriminatorValue);
                }).toList();
          if (siblings.length < 2) continue;
          final discKeys = <String>{
            if (v.discriminatorKey != null) v.discriminatorKey!,
            if (v.discriminatorLiterals != null)
              ...v.discriminatorLiterals!.map((e) => e.key),
          };
          final extraReq = v.requiredKeys
              .where((k) => !discKeys.contains(k))
              .toList();
          final minReq = siblings
              .map((o) => o.requiredKeys.length)
              .reduce((a, b) => a < b ? a : b);
          if (v.requiredKeys.length != minReq || extraReq.isNotEmpty) continue;
          final plain =
              v.discriminatorLiterals != null &&
                  v.discriminatorLiterals!.isNotEmpty
              ? v.discriminatorLiterals!
                    .map(
                      (e) =>
                          "map['${escapeDartString(e.key)}'] == ${jsonLiteral(e.value)}",
                    )
                    .join(' && ')
              : "map['${escapeDartString(v.discriminatorKey!)}'] == "
                    '${jsonLiteral(v.discriminatorValue)}';
          lines.add('      if ($plain) {');
          lines.add('        return ${v.className}.fromJson(map);');
          lines.add('      }');
        }

        // ---- Phase 5a: $ref-to-object wrappers, matched structurally ----
        // Never speculative try/catch here: an all-optional branch (e.g.
        // Account) parses *any* map without throwing, so try/catch order
        // would silently select the wrong class (e.g. an error payload
        // decoded as Account instead of JavaTronError). Branches whose
        // target declares required keys get explicit `hasValue` checks
        // (most keys first); a single remaining keyless branch becomes the
        // unconditional fallback.
        final refObjects = mapVariants
            .where(
              (v) =>
                  v.kind == 'ref' &&
                  v.refType != null &&
                  (v.refKind ?? 'object') == 'object',
            )
            .toList();
        final refWithKeys = <VariantInfo>[];
        final refKeyless = <VariantInfo>[];
        for (final v in refObjects) {
          // Nested presence (one-level descent into a $ref-typed required
          // property) is the most specific ref match and REPLACES the plain
          // discriminator guard: a payload missing the nested key must fall
          // through to siblings, not throw inside this variant's fromJson.
          if (v.presencePath != null) {
            lines.add('      if (${_presenceCheckExpr(v)}) {');
            lines.add(
              '        return ${v.className}(${v.refType}.fromJson(map));',
            );
            lines.add('      }');
          } else if (v.discriminatorKey != null ||
              (v.discriminatorLiterals?.isNotEmpty ?? false) ||
              (v.patternGuards?.isNotEmpty ?? false)) {
            lines.add('      if (${_objectMatchCondition(v)}) {');
            lines.add(
              '        return ${v.className}(${v.refType}.fromJson(map));',
            );
            lines.add('      }');
          } else if (_refVariantRequiredKeys(v).isNotEmpty) {
            refWithKeys.add(v);
          } else {
            refKeyless.add(v);
          }
        }
        // Most required keys first, so e.g. JavaTronError (`Error`) wins
        // over siblings requiring fewer keys.
        refWithKeys.sort(
          (a, b) => _refVariantRequiredKeys(
            b,
          ).length.compareTo(_refVariantRequiredKeys(a).length),
        );
        for (final v in refWithKeys) {
          final cond = _refVariantRequiredKeys(
            v,
          ).map((k) => "map.hasValue('${escapeDartString(k)}')").join(' && ');
          lines.add('      if ($cond) {');
          lines.add(
            '        return ${v.className}(${v.refType}.fromJson(map));',
          );
          lines.add('      }');
        }

        // Presence-based matching for branches whose targets declare no
        // required fields (e.g. Tron contract types): a property key
        // present on exactly one sibling's target schema identifies that
        // branch. Siblings with no exclusive key at all stay genuinely
        // ambiguous and keep the ordered try/catch fallback below.
        final propSets = <VariantInfo, Set<String>>{
          for (final v in refKeyless) v: _refVariantPropertyKeys(v),
        };
        final keyOwners = <String, List<VariantInfo>>{};
        for (final e in propSets.entries) {
          for (final k in e.value) {
            keyOwners.putIfAbsent(k, () => []).add(e.key);
          }
        }
        final refExclusive = <VariantInfo>[];
        final refAmbiguous = <VariantInfo>[];
        for (final v in refKeyless) {
          final excl =
              propSets[v]!.where((k) => keyOwners[k]!.length == 1).toList()
                ..sort();
          if (excl.isNotEmpty) {
            v.exclusiveKeys = excl;
            refExclusive.add(v);
          } else {
            refAmbiguous.add(v);
          }
        }
        for (final v in refExclusive) {
          final cond = v.exclusiveKeys
              .map((k) => "map.hasValue('${escapeDartString(k)}')")
              .join(' || ');
          lines.add('      if ($cond) {');
          lines.add(
            '        return ${v.className}(${v.refType}.fromJson(map));',
          );
          lines.add('      }');
        }
        // ---- Phase 5b: $ref wrappers to nested unions / string enums ----
        // These genuinely accept the raw value and validate inside their
        // own fromJson, so try/catch remains the correct dispatch here.
        for (final v in mapVariants) {
          if (v.kind != 'ref' || v.refType == null) continue;
          final rkind = v.refKind ?? 'object';
          if (rkind != 'union' && rkind != 'string_enum') continue;
          if (v.discriminatorKey != null ||
              (v.discriminatorLiterals?.isNotEmpty ?? false)) {
            lines.add('      if (${_objectMatchCondition(v)}) {');
            lines.add(
              '        return ${v.className}(${v.refType}.fromJson(map));',
            );
            lines.add('      }');
          } else {
            lines.add('      try {');
            lines.add(
              '        return ${v.className}(${v.refType}.fromJson(map));',
            );
            lines.add('      } catch (_) {}');
          }
        }
        // ---- Phase 4: objects with no discriminator (required-key match) ----
        // Unconditional tails (variants matching any map) are deferred to
        // the very end so the keyless-$ref fallback below keeps its
        // original priority over them.
        //
        // Keyless inline objects (no `required` in spec) MUST NOT use
        // `&&`-over-all-props: their class accepts any subset (all
        // nullable), so requiring all keys makes them unreachable (e.g.
        // broadcasthex success {result,txid} vs business-error
        // {result,code,message}). Instead match on exclusive presence
        // (`||` over keys no sibling has); variants with no exclusive
        // key become tail fallbacks.
        final phase4Tails = <VariantInfo>[];
        // Property sets of every map-shaped sibling (inline objects plus
        // $ref-to-object targets) for cross-kind exclusivity.
        final allPropSets = <VariantInfo, Set<String>>{
          for (final v in mapVariants)
            if (v.kind == 'object' || v.kind == 'ref')
              v: _mapVariantPropertyKeys(v),
        };
        final allKeyOwners = <String, List<VariantInfo>>{};
        for (final e in allPropSets.entries) {
          for (final k in e.value) {
            allKeyOwners.putIfAbsent(k, () => []).add(e.key);
          }
        }
        final keylessOrGuards = <VariantInfo>[];
        for (final v in mapVariants) {
          if (v.kind != 'object' || v.objectSchema == null) continue;
          if (v.discriminatorKey != null ||
              (v.discriminatorLiterals?.isNotEmpty ?? false) ||
              v.presencePath != null ||
              (v.patternGuards?.isNotEmpty ?? false)) {
            continue;
          }
          final req = v.requiredKeys;
          if (req.isEmpty) {
            final own = allPropSets[v] ?? const <String>{};
            final exclusive =
                own.where((k) => allKeyOwners[k]!.length == 1).toList()..sort();
            if (exclusive.isEmpty) {
              phase4Tails.add(v);
            } else {
              v.exclusiveKeys = exclusive;
              keylessOrGuards.add(v);
            }
            continue;
          }
          if (v.ambiguousWith != null) {
            lines.add(
              '      // TODO: ${v.className} cannot be reliably distinguished from '
              "${v.ambiguousWith!.join(', ')}.",
            );
          }
          final props = asMap(v.objectSchema!['properties']);
          final parts = <String>[];
          for (final k in req) {
            final lit = _literalValue(props[k]);
            if (lit.key) {
              parts.add(
                "map['${escapeDartString(k)}'] == ${jsonLiteral(lit.value)}",
              );
            } else {
              parts.add("map.hasValue('${escapeDartString(k)}')");
            }
          }
          final c = parts.join(' && ');
          lines.add('      if ($c) {');
          lines.add('        return ${v.className}.fromJson(map);');
          lines.add('      }');
        }
        // Most exclusive keys first so the more specific keyless variant
        // wins when a payload carries keys from several of them.
        keylessOrGuards.sort(
          (a, b) => b.exclusiveKeys.length.compareTo(a.exclusiveKeys.length),
        );
        for (final v in keylessOrGuards) {
          if (v.ambiguousWith != null) {
            lines.add(
              '      // TODO: ${v.className} cannot be reliably distinguished from '
              "${v.ambiguousWith!.join(', ')}.",
            );
          }
          final c = v.exclusiveKeys
              .map((k) => "map.hasValue('${escapeDartString(k)}')")
              .join(' || ');
          lines.add('      if ($c) {');
          lines.add('        return ${v.className}.fromJson(map);');
          lines.add('      }');
        }

        // ---- Phase 5c: ambiguous $ref fallback ----
        // Only branches with neither required keys nor an exclusive
        // presence key reach here (e.g. contracts sharing identical
        // property sets). Emit all-own-keys-present guards, most keys
        // first, so a more specific branch (Transfer{owner,to,amount})
        // wins over a subset branch (CancelAllUnfreeze{owner}) whose
        // all-optional parse would otherwise swallow the map without
        // throwing. Ordered try/catch stays as the final safety net so
        // payloads with absent optional fields still parse.
        final ambiguousOrdered = [...refAmbiguous];
        ambiguousOrdered.sort(
          (a, b) => _refVariantPropertyKeys(
            b,
          ).length.compareTo(_refVariantPropertyKeys(a).length),
        );
        if (refAmbiguous.length > 1) {
          for (final v in ambiguousOrdered) {
            final keys = _refVariantPropertyKeys(v);
            if (keys.isEmpty) continue; // pure catchall: net below
            final cond = (keys.toList()..sort())
                .map((k) => "map.hasValue('${escapeDartString(k)}')")
                .join(' && ');
            lines.add('      if ($cond) {');
            lines.add(
              '        return ${v.className}(${v.refType}.fromJson(map));',
            );
            lines.add('      }');
          }
        }
        if (refAmbiguous.length == 1 && phase4Tails.isEmpty) {
          final v = refAmbiguous.single;
          lines.add('      return ${v.className}(${v.refType}.fromJson(map));');
        } else {
          for (final v in ambiguousOrdered) {
            lines.add('      try {');
            lines.add(
              '        return ${v.className}(${v.refType}.fromJson(map));',
            );
            lines.add('      } catch (_) {}');
          }
        }
        for (final v in phase4Tails) {
          if (v.ambiguousWith != null) {
            lines.add(
              '      // TODO: ${v.className} cannot be reliably distinguished from '
              "${v.ambiguousWith!.join(', ')}.",
            );
          }
          lines.add('      return ${v.className}.fromJson(map);');
        }

        lines.add('    }');
      }

      for (final v in variants) {
        if (v.kind == 'ref' &&
            v.refType != null &&
            v.refKind == 'alias_array') {
          final parseExpr = _aliasArrayFromJsonExpr(v.refType!, 'json');
          lines.add('    if (json is List) {');
          lines.add('      return ${v.className}($parseExpr);');
          lines.add('    }');
        }
      }

      // ref variants that can plausibly accept non-map JSON (e.g. sealed
      // unions over primitives, or bare string/int enums). Object-kind
      // refs are skipped here — their fromJson only ever accepts a Map,
      // and every one of them was already exhaustively tried inside the
      // `if (json is Map)` block above, so retrying them unconditionally
      // (even when `json` isn't a Map at all) would be pure dead code.
      for (final v in variants) {
        if (v.kind == 'ref' &&
            v.refType != null &&
            v.refKind != 'object' &&
            v.refKind != 'alias_array') {
          lines.add('    try {');
          lines.add(
            '      return ${v.className}(${v.refType}.fromJson(json));',
          );
          lines.add('    } catch (_) {}');
        }
      }

      lines.add(
        "    throw ArgumentException.invalidOperationArguments('$dartName', reason:'Cannot parse $dartName from \$json');",
      );
      return lines;
    }

    // Every variant also carries `sharedFields` — properties declared as
    // siblings of oneOf/anyOf on this same schema. Those only make sense
    // when `json` is an object, so require that up front, then extract
    // each shared field's value exactly once and forward it into whichever
    // variant matches.
    lines.add('    if (json is! Map) {');
    lines.add(
      "      throw ArgumentException.invalidOperationArguments('$dartName', reason:'Cannot parse $dartName from \$json');",
    );
    lines.add('    }');
    lines.add(
      '    final map = json is Map<String, dynamic> ? json : Map<String, dynamic>.from(json);',
    );
    // Only `ref` and `tagged_object` variants consume the parent's extracted
    // locals (via sharedArgs). Inline `object` variants re-parse shared fields
    // from the full map in their own fromJson, so when every variant is an
    // inline object the locals would be dead code (unused_local_variable).
    final needsSharedLocals = variants.any(
      (v) =>
          (v.kind == 'tagged_object' && v.payloadKey != null) ||
          (v.kind == 'ref' && v.refType != null),
    );
    if (needsSharedLocals) {
      for (final f in sharedFields) {
        final expr = f.typeRef.dartType == 'Null'
            ? 'null'
            : _mapValueExpr('map', f.jsonKey, f.typeRef, required: !f.optional);
        // Explicit local type so generic helpers like valueAsString/valueAsInt
        // infer a non-nullable T for required fields. Without it `final x = ...`
        // infers a nullable type and passing it to the required ctor param fails.
        final declType = f.typeRef.dartType == 'Null'
            ? 'Null'
            : '${f.typeRef.dartType}${_fieldTypeSuffix(f)}';
        lines.add('    final $declType ${f.dartName} = $expr;');
      }
    }
    final sharedArgs = sharedFields
        .map((f) => ', ${f.dartName}: ${f.dartName}')
        .join();

    // Presence sets across every map-shaped sibling (inline objects + $ref
    // targets) so keyless $ref branches can match on keys no sibling has —
    // same cross-kind exclusivity as the non-shared path (Phase 5a).
    final sharedAllPropSets = <VariantInfo, Set<String>>{
      for (final v in variants)
        if (v.kind == 'object' || v.kind == 'ref')
          v: _mapVariantPropertyKeys(v),
    };
    final sharedKeyOwners = <String, List<VariantInfo>>{};
    for (final e in sharedAllPropSets.entries) {
      for (final k in e.value) {
        sharedKeyOwners.putIfAbsent(k, () => []).add(e.key);
      }
    }
    // $ref branches with no structural guard at all (keyless target, no
    // exclusive key) stay as ordered try/catch — but deferred until after
    // every precise guard so an all-optional branch can't swallow payloads
    // meant for a sibling with required keys.
    final deferredRefFallbacks = <VariantInfo>[];
    var sawUnconditionalTail = false;

    // Emission order: tagged payload keys (most specific) first, then
    // `$ref` branches sorted by guard specificity (nested presence >
    // discriminator > required keys > exclusive keys), then inline objects.
    // A loose guard must never shadow a precise one from a different
    // variant — specificity-first keeps dispatch deterministic.
    final sharedRefs = variants
        .where((v) => v.kind == 'ref' && v.refType != null)
        .toList();
    int refSpecificity(VariantInfo v) {
      if (v.presencePath != null) return 4;
      if (v.discriminatorKey != null ||
          (v.discriminatorLiterals?.isNotEmpty ?? false)) {
        return 3;
      }
      if (_refVariantRequiredKeys(v).isNotEmpty) return 2;
      final own = sharedAllPropSets[v] ?? const <String>{};
      if (own.any((k) => sharedKeyOwners[k]!.length == 1)) return 1;
      return 0;
    }

    final sharedOrdered = <VariantInfo>[
      for (final v in variants)
        if (v.kind == 'tagged_object') v,
      for (final v in variants)
        if (v.kind == 'object') v,
    ];
    final sortedRefs = [...sharedRefs]
      ..sort((a, b) {
        final c = refSpecificity(b).compareTo(refSpecificity(a));
        if (c != 0) return c;
        return variants.indexOf(a).compareTo(variants.indexOf(b));
      });
    // Refs slot between tagged and objects: more specific than the loose
    // keyless-object `||` guards below, less specific than tagged keys.
    final taggedCount = variants.where((v) => v.kind == 'tagged_object').length;
    sharedOrdered.insertAll(taggedCount, sortedRefs);

    for (final v in sharedOrdered) {
      if (v.kind == 'tagged_object' && v.payloadKey != null) {
        final key = v.payloadKey!;
        lines.add("    if (map.hasValue('${escapeDartString(key)}')) {");
        lines.addAll(
          indentText(_taggedPayloadConstruct(v, sharedArgs), 6).split('\n'),
        );
        lines.add('    }');
      } else if (v.kind == 'object' && v.objectSchema != null) {
        // The variant's own .fromJson(map) re-parses the shared fields
        // from the same (full, unfiltered) map itself — see
        // _genObjectVariant — so no sharedArgs needed at the call site.
        final props = asMap(v.objectSchema!['properties']);
        if (v.patternGuards != null && v.patternGuards!.isNotEmpty) {
          lines.add('    if (${_objectMatchCondition(v)}) {');
          lines.add('      return ${v.className}.fromJson(map);');
          lines.add('    }');
        } else if (v.discriminatorKey != null ||
            (v.discriminatorLiterals != null &&
                v.discriminatorLiterals!.isNotEmpty)) {
          lines.add('    if (${_discriminatorIfCondition(v)}) {');
          lines.add('      return ${v.className}.fromJson(map);');
          lines.add('    }');
        } else if (v.presencePath != null) {
          lines.add('    if (${_presenceCheckExpr(v)}) {');
          lines.add('      return ${v.className}.fromJson(map);');
          lines.add('    }');
        } else {
          // Keyless variants (no `required`): match on ANY own key
          // (`||`), not ALL (`&&`) — the class accepts subsets.
          final req = asList(v.objectSchema!['required']).cast<String>();
          final ownKeys = props.keys.toList();
          if (v.ambiguousWith != null) {
            lines.add(
              '    // TODO: ${v.className} cannot be reliably distinguished from '
              "${v.ambiguousWith!.join(', ')} — they share the same required fields "
              '(${req.join(', ')}) and no differing literal/tag value was found anywhere '
              'in their schemas. Whichever variant is checked first below always wins; if '
              "that's wrong, fix this by hand (e.g. branch on a nested field's value).",
            );
          }
          if (req.isNotEmpty) {
            final cond = req
                .map((k) => "map.hasValue('${escapeDartString(k)}')")
                .join(' && ');
            lines.add('    if ($cond) {');
            lines.add('      return ${v.className}.fromJson(map);');
            lines.add('    }');
          } else if (ownKeys.isNotEmpty) {
            final cond = ownKeys
                .map((k) => "map.hasValue('${escapeDartString(k.toString())}')")
                .join(' || ');
            lines.add('    if ($cond) {');
            lines.add('      return ${v.className}.fromJson(map);');
            lines.add('    }');
          } else {
            lines.add('    return ${v.className}.fromJson(map);');
            sawUnconditionalTail = true;
          }
        }
      } else if (v.kind == 'ref' && v.refType != null) {
        // Structural matching instead of speculative try/catch: an
        // all-optional $ref target parses *any* map without throwing, so
        // try/catch order would silently select the wrong class. Nested
        // presence replaces the discriminator guard (a payload missing the
        // nested key must fall through to siblings, not throw here).
        if (v.presencePath != null) {
          lines.add('    if (${_presenceCheckExpr(v)}) {');
          lines.add(
            '      return ${v.className}(${v.refType}.fromJson(map)$sharedArgs);',
          );
          lines.add('    }');
        } else if (v.discriminatorKey != null ||
            (v.discriminatorLiterals?.isNotEmpty ?? false) ||
            (v.patternGuards?.isNotEmpty ?? false)) {
          lines.add('    if (${_objectMatchCondition(v)}) {');
          lines.add(
            '      return ${v.className}(${v.refType}.fromJson(map)$sharedArgs);',
          );
          lines.add('    }');
        } else {
          final req = _refVariantRequiredKeys(v);
          if (req.isNotEmpty) {
            final cond = req
                .map((k) => "map.hasValue('${escapeDartString(k)}')")
                .join(' && ');
            lines.add('    if ($cond) {');
            lines.add(
              '      return ${v.className}(${v.refType}.fromJson(map)$sharedArgs);',
            );
            lines.add('    }');
          } else {
            final own = sharedAllPropSets[v] ?? const <String>{};
            final excl =
                own.where((k) => sharedKeyOwners[k]!.length == 1).toList()
                  ..sort();
            if (excl.isNotEmpty) {
              final cond = excl
                  .map((k) => "map.hasValue('${escapeDartString(k)}')")
                  .join(' || ');
              lines.add('    if ($cond) {');
              lines.add(
                '      return ${v.className}(${v.refType}.fromJson(map)$sharedArgs);',
              );
              lines.add('    }');
            } else {
              deferredRefFallbacks.add(v);
            }
          }
        }
      }
    }

    // Ambiguous $ref fallbacks: keyless target with no exclusive key, so no
    // structural guard exists — keep ordered try/catch as the last resort
    // before the final throw (skipped when an unconditional tail above
    // already returns for every remaining payload).
    if (!sawUnconditionalTail) {
      for (final v in deferredRefFallbacks) {
        lines.add('    try {');
        lines.add(
          '      return ${v.className}(${v.refType}.fromJson(map)$sharedArgs);',
        );
        lines.add('    } catch (_) {}');
      }
    }

    lines.add(
      "    throw ArgumentException.invalidOperationArguments('$dartName', reason:'Cannot parse $dartName from \$json');",
    );
    return lines;
  }

  String _taggedPayloadConstruct(VariantInfo v, String sharedArgs) {
    final key = v.payloadKey!;
    final ps = v.payloadSchema ?? {};
    final psUnwrapped = _unwrap(ps);

    // payload is empty object / no props / empty schema -> unit variant
    final isUnitPayload =
        ps.isEmpty ||
        (primaryType(ps['type']) == 'object' &&
            (ps['properties'] == null ||
                (ps['properties'] is Map &&
                    (ps['properties'] as Map).isEmpty)) &&
            !ps.containsKey('\$ref') &&
            !ps.containsKey('allOf') &&
            !ps.containsKey('oneOf') &&
            !ps.containsKey('anyOf') &&
            !ps.containsKey('additionalProperties'));
    if (isUnitPayload) {
      if (sharedArgs.isEmpty) {
        return 'return const ${v.className}();';
      }
      return 'return ${v.className}(${sharedArgs.substring(2)});';
    }

    // payload is $ref
    if (ps.containsKey('\$ref')) {
      final rawName = refName(ps['\$ref'] as String);
      _ensureSchema(rawName);
      final rname = _dartName(rawName);
      final kind = kindOf[rawName] ?? 'object';

      if (kind == 'alias' ||
          kind == 'ref' ||
          kind == 'ref_alias' ||
          kind == 'alias_array') {
        final target = typedefTarget[rname] ?? 'String';
        final mode = _modeForPrimitiveName(target);
        final expr = _mapValueExpr(
          'map',
          key,
          TypeRef(rname, kind: 'typedef', fromJsonMode: mode),
          required: true,
        );
        return 'return ${v.className}($expr$sharedArgs);';
      }

      if (kind == 'string_enum' || kind == 'union') {
        return "return ${v.className}($rname.fromJson(map['${escapeDartString(key)}'])$sharedArgs);";
      }

      // object class
      return "return ${v.className}($rname.fromJson(map.valueEnsureAsMap<String, dynamic>("
          "'${escapeDartString(key)}'))$sharedArgs);";
    }

    // payload is inline object with properties
    if ((ps['properties'] != null) || (psUnwrapped['properties'] != null)) {
      return 'return ${v.className}.fromPayload(map.valueEnsureAsMap<String, dynamic>('
          "'${escapeDartString(key)}')$sharedArgs);";
    }

    // payload is primitive
    final t = primaryType(ps['type']);
    if (t == 'string' || t == 'integer' || t == 'number' || t == 'boolean') {
      final tr = _typeRef(ps, hintName: '${v.className}Payload');
      final expr = _mapValueExpr('map', key, tr, required: true);
      return 'return ${v.className}($expr$sharedArgs);';
    }

    // payload is array
    if (t == 'array') {
      final tr = _typeRef(ps, hintName: '${v.className}Payload');
      final expr = _mapValueExpr('map', key, tr, required: true);
      return 'return ${v.className}($expr$sharedArgs);';
    }

    // Remaining schemas: oneOf/anyOf unions, allOf, nullable wrappers,
    // additionalProperties maps, etc. _typeRef already classifies these
    // correctly when generating the variant class field type — mirror that
    // here so fromJson calls .fromJson instead of passing raw JSON.
    if (ps.isNotEmpty) {
      final tr = _typeRef(ps, hintName: '${v.className}Payload');
      final expr = _mapValueExpr('map', key, tr, required: true);
      return 'return ${v.className}($expr$sharedArgs);';
    }

    // True unknown / empty payload — last resort
    return '// TODO: payload schema for tag \'${escapeDartString(key)}\' could not be '
        'classified; passing the raw JSON value through unchanged — verify '
        'manually.\n'
        "return ${v.className}(map['${escapeDartString(key)}']$sharedArgs);";
  }

  String _genVariantClass(
    String parent,
    VariantInfo v,
    List<FieldInfo> sharedFields,
  ) {
    final lines = <String>[];
    final sharedCtorLines = [
      for (final f in sharedFields)
        f.optional
            ? '    super.${f.dartName},'
            : '    required super.${f.dartName},',
    ];
    final sharedToJsonLines = [
      for (final f in sharedFields) _tojsonEntryLine(f, _fieldToJsonExpr(f)),
    ];

    if (v.kind == 'string_const') {
      // Note: string_const variants can only appear here when sharedFields
      // is empty (see the supportsShared check in _genUnion) — a bare
      // string-constant JSON value can't also carry object-level shared
      // properties, so this shape never mixes with sharedFields.
      lines.add('class ${v.className} extends $parent {');
      lines.add('  const ${v.className}();');
      lines.add('');
      lines.add('  @override');
      lines.add(
        "  String toJson($_toJsonParams) => '${escapeDartString(v.constValue.toString())}';",
      );
      lines.add('}');
      return lines.join('\n');
    }

    if (v.kind == 'primitive') {
      // Same note as string_const above — primitive variants never coexist
      // with sharedFields.
      final t = v.primitiveType ?? 'dynamic';
      lines.add('class ${v.className} extends $parent {');
      lines.add('  final $t value;');
      lines.add('  const ${v.className}(this.value);');
      lines.add('');
      lines.add('  @override');
      // BigInt is not JSON-encodable; emit decimal string (int64 wire form).
      final primToJson = (t == 'BigInt' || (typedefTarget[t] ?? t) == 'BigInt')
          ? _bigIntToJson('value')
          : _listOrPrimitiveToJsonExpr('value', t);
      lines.add('  dynamic toJson($_toJsonParams) => $primToJson;');
      lines.add('}');
      return lines.join('\n');
    }

    if (v.kind == 'ref') {
      final t = v.refType ?? 'dynamic';
      final rkind = v.refKind ?? 'object';
      lines.add('class ${v.className} extends $parent {');
      lines.add('  final $t value;');
      if (sharedFields.isEmpty) {
        lines.add('  const ${v.className}(this.value);');
      } else {
        lines.add('  const ${v.className}(');
        lines.add('    this.value, {');
        lines.addAll(sharedCtorLines);
        lines.add('  });');
      }
      lines.add('');
      lines.add('  @override');
      final String valueExpr;
      if (rkind == 'string_enum' || rkind == 'union' || rkind == 'object') {
        valueExpr = 'value.toJson(config: config)';
      } else if (rkind == 'alias_array' || rkind == 'list') {
        valueExpr = _listOrPrimitiveToJsonExpr('value', t);
      } else {
        valueExpr = _listOrPrimitiveToJsonExpr('value', t);
      }
      if (sharedFields.isEmpty) {
        lines.add('  dynamic toJson($_toJsonParams) => $valueExpr;');
      } else {
        // supportsShared guarantees rkind == 'object' here, so valueExpr
        // is always a Map<String, dynamic> and safe to spread (no cast:
        // object classes already declare `Map<String, dynamic> toJson()`).
        lines.add(
          '  Map<String, dynamic> toJson($_toJsonParams) =>\n'
          '      config.encodeMap(<String, dynamic>{',
        );
        lines.add('    ...$valueExpr,');
        lines.addAll(sharedToJsonLines);
        lines.add('      });');
      }
      lines.add('}');
      return lines.join('\n');
    }

    if (v.kind == 'tagged_object') {
      return _genTaggedVariant(parent, v, sharedFields);
    }

    if (v.kind == 'object') {
      return _genObjectVariant(parent, v, sharedFields);
    }

    lines.add(
      '/// TODO: could not classify this union variant (tag: '
      "'${v.tag}'); generated as an empty stub — verify manually and fill "
      'in real fields/parsing if this variant carries data.',
    );
    lines.add('class ${v.className} extends $parent {');
    lines.add('  const ${v.className}();');
    lines.add('  @override');
    lines.add('  dynamic toJson($_toJsonParams) => null;');
    lines.add('}');
    return lines.join('\n');
  }

  String _genTaggedVariant(
    String parent,
    VariantInfo v,
    List<FieldInfo> sharedFields,
  ) {
    final key = v.payloadKey ?? v.tag;
    final ps = v.payloadSchema ?? {};
    final lines = <String>[];
    final sharedCtorLines = [
      for (final f in sharedFields)
        f.optional
            ? '    super.${f.dartName},'
            : '    required super.${f.dartName},',
    ];
    final sharedToJsonLines = [
      for (final f in sharedFields) _tojsonEntryLine(f, _fieldToJsonExpr(f)),
    ];

    // unit
    final isUnit =
        (primaryType(ps['type']) == 'object' &&
            ps['properties'] == null &&
            !ps.containsKey('\$ref')) ||
        ps.isEmpty;
    if (isUnit &&
        !ps.containsKey('\$ref') &&
        !ps.containsKey('properties') &&
        !ps.containsKey('allOf')) {
      lines.add('class ${v.className} extends $parent {');
      if (sharedFields.isEmpty) {
        lines.add('  const ${v.className}();');
      } else {
        lines.add('  const ${v.className}({');
        lines.addAll(sharedCtorLines);
        lines.add('  });');
      }
      lines.add('');
      lines.add('  @override');
      lines.add(
        '  Map<String, dynamic> toJson($_toJsonParams) =>\n'
        '      config.encodeMap(<String, dynamic>{',
      );
      lines.add("    '${escapeDartString(key)}': {},");
      lines.addAll(sharedToJsonLines);
      lines.add('      });');
      lines.add('}');
      return lines.join('\n');
    }

    // $ref payload -> single field
    if (ps.containsKey('\$ref')) {
      final rawName = refName(ps['\$ref'] as String);
      _ensureSchema(rawName);
      final rname = _dartName(rawName);
      final kind = kindOf[rawName] ?? 'object';
      final fieldName = sanitizeFieldName(key);
      // Primitive aliases are inlined (no typedef emitted) — declare the
      // primitive directly instead of the dangling typedef name.
      final resolved = _resolveTypedefTarget(rname);
      final t = _isPrimitiveName(resolved) ? resolved : rname;
      // A payload tag literally named `config` would shadow the
      // `toJson({config})` parameter — read it explicitly as `this.config`.
      final fieldRead = fieldName == 'config' ? 'this.$fieldName' : fieldName;
      String toJsonVal;
      if (kind == 'alias' ||
          kind == 'alias_array' ||
          kind == 'ref' ||
          kind == 'ref_alias') {
        toJsonVal = fieldRead;
      } else {
        toJsonVal = '$fieldRead.toJson(config: config)';
      }
      lines.add('class ${v.className} extends $parent {');
      lines.add('  final $t $fieldName;');
      if (sharedFields.isEmpty) {
        lines.add('  const ${v.className}(this.$fieldName);');
      } else {
        lines.add('  const ${v.className}(');
        lines.add('    this.$fieldName, {');
        lines.addAll(sharedCtorLines);
        lines.add('  });');
      }
      lines.add('');
      lines.add('  @override');
      lines.add(
        '  Map<String, dynamic> toJson($_toJsonParams) =>\n'
        '      config.encodeMap(<String, dynamic>{',
      );
      lines.add("    '${escapeDartString(key)}': $toJsonVal,");
      lines.addAll(sharedToJsonLines);
      lines.add('      });');
      lines.add('}');
      return lines.join('\n');
    }

    // inline object payload -> fields + fromPayload
    if (ps['properties'] != null || ps.containsKey('allOf')) {
      final schema = _unwrap(ps);
      final fields = _objectFields(schema, v.className);
      lines.add('class ${v.className} extends $parent {');
      for (final f in fields) {
        final nullSuffix = _fieldTypeSuffix(f);
        lines.addAll(_fieldDocLines(f));
        lines.add('  final ${f.typeRef.dartType}$nullSuffix ${f.dartName};');
      }
      lines.add('');
      final hasTaggedCtorArgs = fields.isNotEmpty || sharedFields.isNotEmpty;
      if (!hasTaggedCtorArgs) {
        lines.add('  const ${v.className}();');
      } else {
        lines.add('  const ${v.className}({');
        for (final f in fields) {
          lines.add(
            f.optional
                ? '    this.${f.dartName},'
                : '    required this.${f.dartName},',
          );
        }
        lines.addAll(sharedCtorLines);
        lines.add('  });');
      }
      lines.add('');
      if (sharedFields.isEmpty) {
        lines.add(
          '  factory ${v.className}.fromPayload(Map<String, dynamic> json) {',
        );
      } else {
        lines.add(
          '  factory ${v.className}.fromPayload(Map<String, dynamic> json, {',
        );
        for (final f in sharedFields) {
          final suffix = _fieldTypeSuffix(f);
          lines.add('    required ${f.typeRef.dartType}$suffix ${f.dartName},');
        }
        lines.add('  }) {');
      }
      lines.add('    return ${v.className}(');
      for (final f in fields) {
        lines.add('      ${f.dartName}: ${_fieldFromJsonExpr(f)},');
      }
      for (final f in sharedFields) {
        lines.add('      ${f.dartName}: ${f.dartName},');
      }
      lines.add('    );');
      lines.add('  }');
      lines.add('');
      lines.add('  @override');
      lines.add(
        '  Map<String, dynamic> toJson($_toJsonParams) =>\n'
        '      config.encodeMap(<String, dynamic>{',
      );
      lines.add("    '${escapeDartString(key)}': {");
      for (final f in fields) {
        final tj = _fieldToJsonExpr(f);
        lines.add(_tojsonEntryLine(f, tj, indentSpaces: '      '));
      }
      lines.add('    },');
      lines.addAll(sharedToJsonLines);
      lines.add('      });');
      lines.add('}');
      return lines.join('\n');
    }

    // primitive / dynamic payload
    final tr = ps.isNotEmpty
        ? _typeRef(ps, hintName: '${v.className}Payload')
        : TypeRef('dynamic', fromJsonMode: 'dynamic');
    const fieldName = 'value';
    lines.add('class ${v.className} extends $parent {');
    lines.add('  final ${tr.dartType} $fieldName;');
    if (sharedFields.isEmpty) {
      lines.add('  const ${v.className}(this.$fieldName);');
    } else {
      lines.add('  const ${v.className}(');
      lines.add('    this.$fieldName, {');
      lines.addAll(sharedCtorLines);
      lines.add('  });');
    }
    lines.add('');
    lines.add('  @override');
    final toJ = _valueToJson(fieldName, tr, false);
    lines.add(
      '  Map<String, dynamic> toJson($_toJsonParams) =>\n'
      '      config.encodeMap(<String, dynamic>{',
    );
    lines.add("    '${escapeDartString(key)}': $toJ,");
    lines.addAll(sharedToJsonLines);
    lines.add('      });');
    lines.add('}');
    return lines.join('\n');
  }

  String _genObjectVariant(
    String parent,
    VariantInfo v,
    List<FieldInfo> sharedFields,
  ) {
    final schema = v.objectSchema ?? {};
    final fields = _objectFields(schema, v.className);

    if (fields.isEmpty &&
        schema.containsKey('additionalProperties') &&
        sharedFields.isEmpty) {
      final ap = schema['additionalProperties'];
      TypeRef valTr;
      if (ap == true) {
        valTr = TypeRef('dynamic', kind: 'dynamic', fromJsonMode: 'dynamic');
      } else if (ap is Map) {
        valTr = _typeRef(ap, hintName: '${v.className}Value');
      } else {
        valTr = TypeRef('dynamic', kind: 'dynamic', fromJsonMode: 'dynamic');
      }
      final valT = valTr.dartType;
      final fromExpr = _rawValueExpr('v', valTr);
      final toExpr = (valTr.kind == 'class' || valTr.kind == 'sealed')
          ? 'v.toJson(config: config)'
          : 'v';
      return 'class ${v.className} extends $parent {\n'
          '  final Map<String, $valT> values;\n'
          '  const ${v.className}(this.values);\n\n'
          '  factory ${v.className}.fromJson(Map<String, dynamic> json) =>\n'
          '      ${v.className}(json.map((k, v) => MapEntry(k, $fromExpr)));\n\n'
          '  @override\n'
          '  Map<String, dynamic> toJson($_toJsonParams) =>\n'
          '      config.encodeMap(values.map((k, v) => MapEntry(k, $toExpr)));\n'
          '}';
    }

    final lines = <String>[];
    lines.add('class ${v.className} extends $parent {');
    for (final f in fields) {
      final nullSuffix = _fieldTypeSuffix(f);
      lines.addAll(_fieldDocLines(f));
      lines.add('  final ${f.typeRef.dartType}$nullSuffix ${f.dartName};');
    }
    lines.add('');
    final hasCtorArgs = fields.isNotEmpty || sharedFields.isNotEmpty;
    if (!hasCtorArgs) {
      lines.add('  const ${v.className}();');
    } else {
      lines.add('  const ${v.className}({');
      for (final f in fields) {
        lines.add(
          f.optional
              ? '    this.${f.dartName},'
              : '    required this.${f.dartName},',
        );
      }
      for (final f in sharedFields) {
        lines.add(
          f.optional
              ? '    super.${f.dartName},'
              : '    required super.${f.dartName},',
        );
      }
      lines.add('  });');
    }
    lines.add('');
    lines.add('  factory ${v.className}.fromJson(Map<String, dynamic> json) {');
    if (!hasCtorArgs) {
      lines.add('    return const ${v.className}();');
    } else {
      lines.add('    return ${v.className}(');
      for (final f in fields) {
        lines.add('      ${f.dartName}: ${_fieldFromJsonExpr(f)},');
      }
      // Every variant's full field set is flat/merged on the wire, so a
      // struct variant's own .fromJson(map) can just re-parse the shared
      // fields from the same map it already has — no need for the caller to
      // supply them separately.
      for (final f in sharedFields) {
        lines.add('      ${f.dartName}: ${_fieldFromJsonExpr(f)},');
      }
      lines.add('    );');
    }
    lines.add('  }');
    lines.add('');
    lines.add('  @override');
    lines.add(
      '  Map<String, dynamic> toJson($_toJsonParams) =>\n'
      '      config.encodeMap(<String, dynamic>{',
    );
    for (final f in fields) {
      final tj = _fieldToJsonExpr(f);
      lines.add(_tojsonEntryLine(f, tj));
    }
    for (final f in sharedFields) {
      lines.add(_tojsonEntryLine(f, _fieldToJsonExpr(f)));
    }
    lines.add('      });');
    lines.add('}');
    return lines.join('\n');
  }

  // ---- codegen: object class ----

  /// True when a schema gives no usable type information at all (no
  /// type/$ref/enum/oneOf/anyOf/allOf/properties) — e.g. `{}` or just a
  /// bare `"description"` — as opposed to a deliberate "anything goes"
  /// schema that at least says `type: object` or similar.
  bool _isSchemaAmbiguous(dynamic schemaAny) {
    final schema = asMapOrNull(schemaAny);
    if (schema == null) return true;
    return !(schema['type'] != null ||
        schema.containsKey('\$ref') ||
        schema.containsKey('enum') ||
        schema.containsKey('oneOf') ||
        schema.containsKey('anyOf') ||
        schema.containsKey('allOf') ||
        schema['properties'] != null ||
        schema.containsKey('additionalProperties'));
  }

  /// The '?' suffix for a field's Dart type declaration. Suppressed for the
  /// synthetic `Null` type (used for unit/always-null schemas) since
  /// `Null?` is redundant, and for `dynamic` since `dynamic` is already
  /// nullable (`dynamic?` trips unnecessary_question_mark).
  String _fieldTypeSuffix(FieldInfo f) {
    if (nullableTypedefs.contains(f.typeRef.dartType)) {
      return '';
    }
    if (f.typeRef.dartType == 'Null') return '';
    if (f.typeRef.dartType == 'dynamic') return '';
    return f.optional ? '?' : '';
  }

  List<String> _fieldDocLines(FieldInfo f, {String indentSpaces = '  '}) {
    final lines = <String>[];
    if (f.isAmbiguous) {
      lines.add(
        '$indentSpaces/// TODO: the schema for `${f.jsonKey}` (or its '
        'array items) gave no usable type information (no type/\$ref/'
        'enum/oneOf/anyOf/allOf); generated as `${f.typeRef.dartType}` — '
        'check the OpenAPI spec and fix this field manually.',
      );
    }
    if (f.description.isNotEmpty) {
      lines.add('$indentSpaces/// ${f.description.split('\n').first}');
    }
    return lines;
  }

  /// A single `'key': value,` toJson entry. Always unconditional — even
  /// for optional/nullable fields — so the key is always present in the
  /// output (with a null value when the field itself is null), instead of
  /// silently disappearing.
  String _tojsonEntryLine(
    FieldInfo f,
    String tj, {
    String indentSpaces = '    ',
  }) {
    return "$indentSpaces'${f.jsonKey}': $tj,";
  }

  List<FieldInfo> _objectFields(
    Map<String, dynamic> schemaAny,
    String parentName,
  ) {
    final schema = _unwrap(schemaAny);
    final props = asMap(schema['properties']);
    final required = asList(schema['required']).cast<String>().toSet();
    final fields = <FieldInfo>[];
    for (final entry in props.entries) {
      final key = entry.key;
      final prop = asMapOrNull(entry.value) ?? {};
      final tr = _typeRef(
        prop,
        hintName: '$parentName${snakeToCamel(key, capitalizeFirst: true)}',
      );
      var optional =
          !required.contains(key) ||
          tr.isNullable ||
          (prop['nullable'] == true);
      if (prop['nullable'] == true || typeIncludesNull(prop['type'])) {
        tr.isNullable = true;
        optional = true;
      }
      bool ambiguous;
      if (tr.kind == 'dynamic') {
        ambiguous = _isSchemaAmbiguous(prop);
      } else if (tr.kind == 'list' &&
          tr.item != null &&
          tr.item!.kind == 'dynamic') {
        ambiguous = _isSchemaAmbiguous(prop['items']);
      } else {
        ambiguous = false;
      }
      fields.add(
        FieldInfo(
          jsonKey: key,
          dartName: sanitizeFieldName(key),
          typeRef: tr,
          optional: optional,
          description: (prop['description'] as String? ?? '').trim(),
          isAmbiguous: ambiguous,
        ),
      );
    }
    return fields;
  }

  String _genObject(
    String dartName,
    Map<String, dynamic> schemaAny,
    String original,
  ) {
    final schema = _unwrap(schemaAny);
    final fields = _objectFields(schema, dartName);

    // free map object
    if (fields.isEmpty && schema.containsKey('additionalProperties')) {
      final ap = schema['additionalProperties'];
      TypeRef valTr;
      if (ap == true) {
        valTr = TypeRef('dynamic', kind: 'dynamic', fromJsonMode: 'dynamic');
      } else if (ap is Map) {
        valTr = _typeRef(ap, hintName: '${dartName}Value');
      } else {
        valTr = TypeRef('dynamic', kind: 'dynamic', fromJsonMode: 'dynamic');
      }
      final valT = valTr.dartType;
      final fromExpr = _rawValueExpr('v', valTr);
      final toExpr = (valTr.kind == 'class' || valTr.kind == 'sealed')
          ? 'v.toJson(config: config)'
          : 'v';
      return '${_docWithEndpoints(schema, original)}'
          'class $dartName {\n'
          '  final Map<String, $valT> values;\n'
          '  const $dartName(this.values);\n\n'
          '  factory $dartName.fromJson(Map<String, dynamic> json) =>\n'
          '      $dartName(json.map((k, v) => MapEntry(k, $fromExpr)));\n\n'
          '  Map<String, dynamic> toJson($_toJsonParams) =>\n'
          '      config.encodeMap(values.map((k, v) => MapEntry(k, $toExpr)));\n'
          '}';
    }

    final lines = <String>[];
    var doc = _docWithEndpoints(schema, original);
    if (fields.isNotEmpty &&
        schema['additionalProperties'] != null &&
        schema['additionalProperties'] != false) {
      const todo =
          '/// TODO: this schema also declares `additionalProperties` '
          'alongside its named properties — that combination isn\'t '
          'modeled, so any extra/unknown keys are silently ignored by '
          'fromJson/toJson. Handle them manually if you need them.\n';
      doc = doc.isNotEmpty ? '$doc$todo' : todo;
    }
    lines.add(doc.trimRight());
    lines.add('class $dartName {');
    for (final f in fields) {
      final nullSuffix = _fieldTypeSuffix(f);
      lines.addAll(_fieldDocLines(f));
      lines.add('  final ${f.typeRef.dartType}$nullSuffix ${f.dartName};');
    }
    lines.add('');
    if (fields.isEmpty) {
      lines.add('  const $dartName();');
    } else {
      lines.add('  const $dartName({');
      for (final f in fields) {
        lines.add(
          f.optional
              ? '    this.${f.dartName},'
              : '    required this.${f.dartName},',
        );
      }
      lines.add('  });');
    }
    lines.add('');
    lines.add('  factory $dartName.fromJson(Map<String, dynamic> json) {');
    if (fields.isEmpty) {
      lines.add('    return const $dartName();');
    } else {
      lines.add('    return $dartName(');
      for (final f in fields) {
        lines.add('      ${f.dartName}: ${_fieldFromJsonExpr(f)},');
      }
      lines.add('    );');
    }
    lines.add('  }');
    lines.add('');
    lines.add(
      '  Map<String, dynamic> toJson($_toJsonParams) =>\n'
      '      config.encodeMap(<String, dynamic>{',
    );
    for (final f in fields) {
      final tj = _fieldToJsonExpr(f);
      lines.add(_tojsonEntryLine(f, tj));
    }
    lines.add('      });');
    lines.add('}');
    return lines.join('\n');
  }

  // ---- fromJson / toJson expressions ----

  String _fieldFromJsonExpr(FieldInfo f) {
    if (f.typeRef.dartType == 'Null') return 'null';
    return _mapValueExpr('json', f.jsonKey, f.typeRef, required: !f.optional);
  }

  /// Convert a single already-extracted raw JSON value (`var`) into `tr`'s
  /// Dart type. Used per-entry when building Map<'String, V> / List<'V> so
  /// that e.g. a class/sealed value type actually calls `.fromJson()`, and
  /// a primitive value type actually coerces via JsonParser, instead of an
  /// invalid `as ClassName` cast or a blind passthrough.
  String _rawValueExpr(String varName, TypeRef tr) {
    final mode = tr.fromJsonMode;
    final dart = tr.dartType;
    final parse = tr.effectiveParseType;
    final ultimate = typedefTarget[dart] ?? dart;
    // Map<String, V> with a concrete value type converts each entry (e.g.
    // Map<String, String> must not pass through Map<String, dynamic>.from,
    // which mistypes List<Map<String, String>> fields). Only free-form maps
    // keep the blind .from passthrough.
    if (tr.kind == 'map' &&
        tr.value != null &&
        tr.value!.kind != 'dynamic' &&
        tr.value!.dartType != 'dynamic') {
      final valueExpr = _rawValueExpr('v', tr.value!);
      return '($varName as Map).map((k, v) => MapEntry(k as String, $valueExpr))';
    }
    // typedef X = Map<String, dynamic> (or any Map) — no .fromJson
    if (ultimate == 'Map<String, dynamic>' ||
        ultimate.startsWith('Map<') ||
        dart == 'Map<String, dynamic>' ||
        dart.startsWith('Map<')) {
      return 'Map<String, dynamic>.from($varName as Map)';
    }
    if (tr.kind == 'class') {
      return '$parse.fromJson($varName as Map<String, dynamic>)';
    }
    if (tr.kind == 'sealed') {
      return '$parse.fromJson($varName)';
    }
    if (mode == 'string') {
      return '($varName is num ? $varName.toString() : JsonParser.valueAsString<String>($varName))';
    }
    if (mode == 'int') return 'JsonParser.valueAsInt<int>($varName)';
    if (mode == 'num') return 'JsonParser.valueAsNum<num>($varName)';
    if (mode == 'double') return 'JsonParser.valueAsDouble<double>($varName)';
    if (mode == 'bool') return 'JsonParser.valueAsBool<bool>($varName)';
    if (mode == 'bigint') return 'JsonParser.valueAsBigInt<BigInt>($varName)';
    if (mode == 'bytes') return 'JsonParser.valueAsBytes<List<int>>($varName)';
    if (tr.kind == 'list' && tr.item != null) {
      if (tr.item!.isNullable && tr.item!.kind != 'dynamic') {
        final itemExpr = _rawValueExpr('e', tr.item!);
        return '($varName as List).map((e) => e == null ? null : $itemExpr).toList()';
      }
      final itemExpr = _rawValueExpr('e', tr.item!);
      return '($varName as List).map((e) => $itemExpr).toList()';
    }
    if (tr.kind == 'map') {
      return 'Map<String, dynamic>.from($varName as Map)';
    }
    // dynamic / unresolved typedef fallback
    if (dart == 'dynamic') return varName;
    return '$varName as $dart';
  }

  String _mapValueExpr(
    String mapVar,
    String key,
    TypeRef tr, {
    required bool required,
  }) {
    final k = escapeDartString(key);
    final mode = tr.fromJsonMode;
    final dart = tr.dartType;
    final nullable = tr.isNullable || !required;
    final nullT = nullable ? '?' : '';

    // OpenAPI marks Tezos bignum/int64 as strings; nodes often emit JSON numbers.
    // Explicit generics (<String> vs <String?> etc.) so the type doesn't rely
    // on call-site inference — required fields must parse as non-nullable even
    // when the expression is first assigned to a `final` local without context.
    if (mode == 'string') {
      final t = nullable ? 'String?' : 'String';
      return "($mapVar['$k'] is num ? $mapVar['$k'].toString() : $mapVar.valueAsString<$t>('$k'))";
    }
    if (mode == 'int') {
      final t = nullable ? 'int?' : 'int';
      return "$mapVar.valueAsInt<$t>('$k')";
    }
    if (mode == 'num') {
      final t = nullable ? 'num?' : 'num';
      return "$mapVar.valueAsNum<$t>('$k')";
    }
    if (mode == 'double') {
      final t = nullable ? 'double?' : 'double';
      return "$mapVar.valueAsDouble<$t>('$k')";
    }
    if (mode == 'bool') {
      final t = nullable ? 'bool?' : 'bool';
      return "$mapVar.valueAsBool<$t>('$k')";
    }
    if (mode == 'bigint') {
      final t = nullable ? 'BigInt?' : 'BigInt';
      return "$mapVar.valueAsBigInt<$t>('$k')";
    }
    if (mode == 'bytes') {
      final t = nullable ? 'List<int>?' : 'List<int>';
      return "$mapVar.valueAsBytes<$t>('$k')";
    }

    if (mode == 'list' || tr.kind == 'list') {
      final item = tr.item;
      if (item == null) {
        return "$mapVar.valueAsList<List$nullT>('$k')";
      }
      if (item.isNullable && item.kind != 'dynamic') {
        // JsonParser's valueAsList<List<T>> family has no notion of a
        // nullable item type, so build the list manually with an explicit
        // null check per element instead.
        final elemExpr = _rawValueExpr('e', item);
        final base =
            "$mapVar.valueEnsureAsList<dynamic>('$k')"
            '.map((e) => e == null ? null : $elemExpr).toList()';
        if (!required) {
          return "$mapVar.hasValue('$k') ? $base : null";
        }
        return base;
      }
      if ((item.kind == 'primitive' || item.kind == 'typedef') &&
          [
            'string',
            'int',
            'num',
            'double',
            'bool',
            'bigint',
            'dynamic',
          ].contains(item.fromJsonMode)) {
        return "$mapVar.valueAsList<List<${item.dartType}>$nullT>('$k')";
      }
      if (item.fromJsonMode == 'map' || item.kind == 'class') {
        final parse = item.effectiveParseType;
        final itemUltimate = typedefTarget[item.dartType] ?? item.dartType;
        final isMapAlias =
            itemUltimate == 'Map<String, dynamic>' ||
            itemUltimate.startsWith('Map<') ||
            item.dartType == 'Map<String, dynamic>';
        // True maps (kind == 'map') convert each entry via _rawValueExpr
        // (concrete value types) or keep the blind .from passthrough
        // (free-form Map<String, dynamic>). Classes use .fromJson.
        final mapFn = item.kind == 'map'
            ? '(e) => ${_rawValueExpr('e', item)}'
            : (isMapAlias
                  ? '(e) => Map<String, dynamic>.from(e as Map)'
                  : '(e) => $parse.fromJson(e)');
        final base =
            "$mapVar.valueEnsureAsList<Map<String, dynamic>>('$k')"
            '.map($mapFn).toList()';
        if (!required) {
          return "$mapVar.hasValue('$k') ? $base : null";
        }
        return base;
      }
      if (item.kind == 'sealed') {
        final parse = item.effectiveParseType;
        final base =
            "$mapVar.valueEnsureAsList<dynamic>('$k')"
            '.map((e) => $parse.fromJson(e)).toList()';
        if (!required) {
          return "$mapVar.hasValue('$k') ? "
              "$mapVar.valueEnsureAsList<dynamic>('$k')"
              '.map((e) => $parse.fromJson(e)).toList() : null';
        }
        return base;
      }
      if (item.kind == 'list') {
        final elemExpr = _rawValueExpr('e', item);
        final base =
            "$mapVar.valueEnsureAsList<dynamic>('$k')"
            '.map((e) => $elemExpr).toList()';
        if (!required) {
          return "$mapVar.hasValue('$k') ? $base : null";
        }
        return base;
      }
      if (item.kind == 'dynamic') {
        return "$mapVar.valueAsList<List<dynamic>$nullT>('$k')";
      }
      return "$mapVar.valueAsList<List<${item.dartType}>$nullT>('$k')";
    }

    // typedef X = Map<String, dynamic>
    final ultimate = typedefTarget[dart] ?? dart;
    if (tr.kind == 'typedef' &&
        (ultimate == 'Map<String, dynamic>' || ultimate.startsWith('Map<'))) {
      if (!required) {
        return "$mapVar.hasValue('$k') ? "
            "Map<String, dynamic>.from($mapVar['$k'] as Map) : null";
      }
      return "Map<String, dynamic>.from($mapVar['$k'] as Map)";
    }

    // IMPORTANT: sealed/class refs must be matched *before* the generic map
    // branch below. Object refs and sealed refs both carry
    // from_json_mode == "map"/"dynamic" (that just means "expects a
    // Map/raw JSON on the wire"), which would otherwise make them fall
    // into the plain `valueAsMap<Map<String, dynamic>>(...)` branch instead
    // of calling the nested type's own fromJson.
    if (tr.kind == 'sealed') {
      final parse = tr.effectiveParseType;
      // Sealed unions/enums accept any wire shape (string/map/list), so the
      // raw value passes through as Object into the nested fromJson — same
      // valueTo convention as the class branch below. NOTE: VV must stay
      // *non-nullable* Object (not Object?): with a nullable VV, valueTo
      // calls parse(null) for absent keys and the nested fromJson(null)
      // throws, instead of yielding null like `hasValue ? ... : null` did.
      if (!required) {
        return '$mapVar.valueTo<'
            '$dart?, Object>('
            "key: '$k', parse: (e) => $parse.fromJson(JsonParser.valueAs(e)))";
      }
      return '$mapVar.valueTo<'
          '$dart, Object>('
          "key: '$k', parse: (e) => $parse.fromJson(JsonParser.valueAs(e)))";
    }

    if (tr.kind == 'class') {
      final parse = tr.effectiveParseType;
      if (!required) {
        return '$mapVar.valueTo<'
            '$dart?, Map<String, dynamic>>('
            "key: '$k', parse: (v) => $parse.fromJson(v))";
      }
      return '$mapVar.valueTo<'
          '$dart, Map<String, dynamic>>('
          "key: '$k', parse: (v) => $parse.fromJson(v))";
    }

    // Only true free-form maps (kind == "map", e.g. additionalProperties)
    // land here — never object/sealed refs, since those are handled above.
    if (tr.kind == 'map') {
      final value = tr.value;
      if (value == null || value.kind == 'dynamic') {
        return "$mapVar.valueAsMap<Map<String, dynamic>$nullT>('$k')";
      }
      final valueExpr = _rawValueExpr('v', value);
      final base =
          "$mapVar.valueEnsureAsMap<String, dynamic>('$k')"
          '.map((k, v) => MapEntry(k, $valueExpr))';
      if (!required) {
        return "$mapVar.hasValue('$k') ? $base : null";
      }
      return base;
    }

    if (mode == 'dynamic' || tr.kind == 'dynamic') {
      return "$mapVar['$k']";
    }

    // typedef primitives already handled via mode; remaining typedef
    // class-like fallback
    if (tr.kind == 'typedef') {
      if (['string', 'int', 'num', 'bool', 'double', 'bigint'].contains(mode)) {
        return _mapValueExpr(
          mapVar,
          key,
          TypeRef(
            dart,
            kind: 'primitive',
            isNullable: nullable,
            fromJsonMode: mode,
          ),
          required: required,
        );
      }
      return "$mapVar['$k']";
    }

    return "$mapVar['$k']";
  }

  /// Serialize a field of type [typeName] (possibly `List<…>` / nested lists).
  /// Class/sealed elements get `.toJson()`; BigInt becomes a decimal string
  /// (it is not JSON-encodable); other primitives stay as-is.
  String _listOrPrimitiveToJsonExpr(String name, String typeName) {
    final trimmed = typeName.trim();
    // BigInt serializes through the configured encodeBigint. Resolves
    // typedefs (e.g. BlockId -> BigInt) the same way.
    final base = trimmed.endsWith('?')
        ? trimmed.substring(0, trimmed.length - 1).trim()
        : trimmed;
    if (_resolveTypedefTarget(base) == 'BigInt') {
      return _bigIntToJson(name);
    }
    if (trimmed.startsWith('List<') && trimmed.endsWith('>')) {
      final inner = trimmed.substring(5, trimmed.length - 1).trim();
      final innerBase = inner.endsWith('?')
          ? inner.substring(0, inner.length - 1)
          : inner;
      if (innerBase.startsWith('List<')) {
        // List<List<T>> — map outer, then serialize each inner list.
        final innerExpr = _listOrPrimitiveToJsonExpr('e', innerBase);
        if (innerExpr != 'e') {
          return '$name.map((e) => $innerExpr).toList()';
        }
        return name;
      }
      if (_typeNeedsToJson(innerBase)) {
        return '$name.map((e) => e.toJson(config: config)).toList()';
      }
      return name;
    }
    if (_typeNeedsToJson(trimmed)) {
      return '$name.toJson(config: config)';
    }
    return name;
  }

  bool _typeNeedsToJson(String typeName) {
    if (typeName == 'dynamic' ||
        typeName == 'String' ||
        typeName == 'int' ||
        typeName == 'double' ||
        typeName == 'num' ||
        typeName == 'bool' ||
        typeName == 'BigInt' ||
        typeName == 'Null' ||
        typeName.startsWith('Map<')) {
      return false;
    }
    if (classNames.contains(typeName) || sealedNames.contains(typeName)) {
      return true;
    }
    final target = typedefTarget[typeName];
    if (target == null) return false;
    if (target.startsWith('List<')) {
      // typedef X = List<Y>
      final inner = target.substring(5, target.length - 1).trim();
      final base = inner.endsWith('?')
          ? inner.substring(0, inner.length - 1)
          : inner;
      return _typeNeedsToJson(base);
    }
    return classNames.contains(target) || sealedNames.contains(target);
  }

  String _fieldToJsonExpr(FieldInfo f) =>
      _valueToJson(_fieldReadExpr(f), f.typeRef, f.optional);

  /// Field read expression inside `toJson`: a field literally named `config`
  /// would shadow the `toJson({config})` parameter, so it is read explicitly
  /// as `this.config` (the parameter keeps its contract name).
  String _fieldReadExpr(FieldInfo f) =>
      f.dartName == 'config' ? 'this.${f.dartName}' : f.dartName;

  String _valueToJson(String name, TypeRef tr, bool optional) {
    final q = optional ? '?' : '';
    // BigInt goes through the configured encodeBigint. Typedefs resolving
    // to BigInt (e.g. BlockId) are covered too.
    if (_resolveTypedefTarget(tr.dartType) == 'BigInt') {
      return _bigIntToJson(name);
    }
    if (tr.kind == 'list' && tr.item != null) {
      final item = tr.item!;
      if (_resolveTypedefTarget(
            item.dartType.endsWith('?')
                ? item.dartType.substring(0, item.dartType.length - 1)
                : item.dartType,
          ) ==
          'BigInt') {
        // List<uint64> — each element through the configured encodeBigint.
        return '$name$q.map((e) => ${_bigIntToJson('e')}).toList()';
      }
      if (item.kind == 'class' || item.kind == 'sealed') {
        final bang = item.isNullable ? '?' : '';
        return '$name$q.map((e) => e$bang.toJson(config: config)).toList()';
      }
      if (item.kind == 'list' &&
          item.item != null &&
          (item.item!.kind == 'class' || item.item!.kind == 'sealed')) {
        final bang = item.item!.isNullable ? '?' : '';
        return '$name$q.map((e) => e.map((x) => x$bang.toJson(config: config)).toList()).toList()';
      }
      return name;
    }
    if (tr.kind == 'map' && tr.value != null) {
      final value = tr.value!;
      if (value.kind == 'class' || value.kind == 'sealed') {
        return '$name$q.map((k, v) => MapEntry(k, v.toJson(config: config)))';
      }
      return name;
    }
    if (tr.kind == 'class' || tr.kind == 'sealed') {
      return '$name$q.toJson(config: config)';
    }
    return name;
  }

  // // ---- codegen: client request wrapper classes ----

  // /// Path-item-level `parameters` apply to every operation on that path;
  // /// operation-level ones override same name+location.
  // List<Map<String, dynamic>> _mergedParameters(
  //   Map<String, dynamic> pathItem,
  //   Map<String, dynamic> operation,
  // ) {
  //   final merged = <String, Map<String, dynamic>>{};
  //   for (final pAny in asList(pathItem['parameters'])) {
  //     final p = asMapOrNull(pAny);
  //     if (p != null && p['name'] != null && p['in'] != null) {
  //       merged['${p['name']}|${p['in']}'] = p;
  //     }
  //   }
  //   for (final pAny in asList(operation['parameters'])) {
  //     final p = asMapOrNull(pAny);
  //     if (p != null && p['name'] != null && p['in'] != null) {
  //       merged['${p['name']}|${p['in']}'] = p;
  //     }
  //   }
  //   return merged.values.toList();
  // }

  Map<String, dynamic>? _responseSchemaForOperation(
    Map<String, dynamic> operation,
  ) {
    Map<String, dynamic>? swagger2(Map<String, dynamic> resp) {
      // Swagger 2.0: schema sits directly on the response object.
      final s = resp['schema'];
      return s is Map ? asMap(s) : null;
    }

    final responses = asMap(operation['responses']);
    for (final status in ['200', '201', '202', '204']) {
      final resp = asMapOrNull(responses[status]);
      if (resp != null) {
        for (final c in asMap(resp['content']).values) {
          final cm = asMapOrNull(c);
          if (cm != null && cm['schema'] != null) return asMap(cm['schema']);
        }
        final s2 = swagger2(resp);
        if (s2 != null) return s2;
      }
    }
    for (final entry in responses.entries) {
      final resp = asMapOrNull(entry.value);
      if (resp != null && entry.key.toString().startsWith('2')) {
        for (final c in asMap(resp['content']).values) {
          final cm = asMapOrNull(c);
          if (cm != null && cm['schema'] != null) return asMap(cm['schema']);
        }
        final s2 = swagger2(resp);
        if (s2 != null) return s2;
      }
    }
    return null;
  }

  Map<String, dynamic>? _requestBodySchemaForOperation(
    Map<String, dynamic> operation,
  ) {
    final rb = asMapOrNull(operation['requestBody']);
    if (rb != null) {
      for (final c in asMap(rb['content']).values) {
        final cm = asMapOrNull(c);
        if (cm != null && cm['schema'] != null) return asMap(cm['schema']);
      }
      return null;
    }
    // Swagger 2.0: body lives in `parameters` as `{in: body, schema: ...}`.
    for (final pAny in asList(operation['parameters'])) {
      final p = asMapOrNull(_resolveParameter(pAny));
      if (p != null && p['in'] == 'body' && p['schema'] is Map) {
        return asMap(p['schema']);
      }
    }
    return null;
  }

  /// (RESULT dart type, SERVICERESPONSE dart type, onResonse body).
  List<String> _resultAndServiceTypes(
    TypeRef tr, {
    String hintName = 'Response',
  }) {
    // Object classes always deserialize from a JSON object (Map).
    if (tr.kind == 'class') {
      final parse = tr.effectiveParseType;
      return [
        tr.dartType,
        'Map<String, dynamic>',
        'return $parse.fromJson(result);',
      ];
    }
    // Sealed unions (oneOf/anyOf) may be string | map | list | null on the
    // wire (e.g. Unistring, ChainId, Micheline). Service layer must pass the
    // raw decoded JSON as dynamic — never force Map<String, dynamic>.
    if (tr.kind == 'sealed') {
      final parse = tr.effectiveParseType;
      return [tr.dartType, 'dynamic', 'return $parse.fromJson(result);'];
    }
    if (tr.kind == 'list') {
      final item = tr.item;
      if (item != null && (item.kind == 'class' || item.kind == 'sealed')) {
        final parse = item.effectiveParseType;
        final listType = tr.dartType.startsWith('List<')
            ? tr.dartType
            : 'List<${item.dartType}>';
        return [
          listType,
          'List<dynamic>',
          'return result.map((e) => $parse.fromJson(e)).toList();',
        ];
      }
      if (item != null && item.kind == 'list') {
        final nested = item.item;
        if (nested != null &&
            (nested.kind == 'class' || nested.kind == 'sealed')) {
          final parse = nested.effectiveParseType;
          return [
            tr.dartType,
            'List<dynamic>',
            'return result.map((e) => (e as List).map((x) => $parse.fromJson(x)).toList()).toList() as ${tr.dartType};',
          ];
        }
        final innerType = nested?.dartType ?? 'dynamic';
        return [
          tr.dartType,
          'List<dynamic>',
          'return result.map((e) => (e as List).cast<$innerType>().toList()).toList() as ${tr.dartType};',
        ];
      }
      final itemType = item != null ? item.dartType : 'dynamic';
      return [
        tr.dartType,
        'List<dynamic>',
        'return result.cast<$itemType>().toList();',
      ];
    }
    if (tr.kind == 'map') {
      return ['Map<String, dynamic>', 'Map<String, dynamic>', 'return result;'];
    }
    // typedef / primitive / dynamic — pass through (already coerced by client).
    return [tr.dartType, tr.dartType, 'return result;'];
  }

  List<ClientParamInfo> _clientParams(
    List<Map<String, dynamic>> params,
    String path,
  ) {
    final result = <ClientParamInfo>[];
    final seen = <String>{};
    for (final p in params) {
      final loc = p['in'];
      final name = p['name'];
      if ((loc != 'path' && loc != 'query') || name == null) continue;
      final schema = asMapOrNull(p['schema']) ?? {'type': 'string'};
      final tr = _typeRef(schema, hintName: sanitizeClassName(name.toString()));
      final required = (p['required'] == true) || loc == 'path';
      result.add(
        ClientParamInfo(
          dartName: sanitizeFieldName(name.toString()),
          jsonName: name.toString(),
          typeRef: tr,
          required: required,
          location: loc.toString(),
        ),
      );
      if (loc == 'path') seen.add(name.toString());
    }
    // Path templates occasionally have {placeholders} that aren't (also)
    // declared in `parameters` — fall back to a required String for those.
    for (final m in RegExp(r'\{([^{}]+)\}').allMatches(path)) {
      final pname = m.group(1)!;
      if (seen.contains(pname)) continue;
      result.add(
        ClientParamInfo(
          dartName: sanitizeFieldName(pname),
          jsonName: pname,
          typeRef: TypeRef('String', kind: 'primitive', fromJsonMode: 'string'),
          required: true,
          location: 'path',
        ),
      );
    }
    return result;
  }

  BodyPlan _clientBodyPlan(
    Map<String, dynamic> operation, {
    String typeBase = '',
  }) {
    final schema = _requestBodySchemaForOperation(operation);
    if (schema == null) return BodyPlan(kind: 'none');

    final unwrapped = _unwrap(schema);
    final props = asMap(unwrapped['properties']);
    final required = asList(unwrapped['required']).cast<String>().toSet();
    final methodProp = asMapOrNull(props['method']);
    final paramsProp = props['params'];
    if (methodProp != null &&
        paramsProp != null &&
        required.contains('method') &&
        required.contains('params')) {
      final lit = _literalValue(methodProp);
      if (lit.key && lit.value is String) {
        return BodyPlan(
          kind: 'json_rpc',
          jsonRpcMethod: lit.value as String,
          paramTypeRef: _typeRef(
            paramsProp,
            hintName: typeBase.isEmpty ? 'Params' : '${typeBase}Params',
          ),
        );
      }
    }
    // Plain body — the whole schema becomes one constructor field.
    return BodyPlan(
      kind: 'plain',
      paramTypeRef: _typeRef(
        schema,
        hintName: typeBase.isEmpty ? 'Body' : '${typeBase}Body',
      ),
    );
  }

  String _clientPathExpr(
    String path,
    List<ClientParamInfo> params, [
    bool keepTemplate = false,
  ]) {
    final pathParams = {
      for (final p in params.where((p) => p.location == 'path'))
        p.jsonName: p.dartName,
    };
    var rendered = path;

    for (final entry in pathParams.entries) {
      if (keepTemplate) break;
      final p = entry.value.contains(".")
          ? "\${${entry.value}}"
          : "\$${entry.value}";
      rendered = rendered.replaceAll('{${entry.key}}', p);
    }
    final escaped = rendered.replaceAll("'", "\\'");
    return "'$escaped'";
  }

  /// Last URL segment, e.g. `/api/v2/getAddressBalance` → `getAddressBalance`.
  /// Used as the JSON-RPC method name in `--client-json-rpc` mode.
  String _jsonRpcMethodName(String path) {
    final segs = path
        .split('/')
        .where((s) => s.isNotEmpty && !s.startsWith('{'));
    return segs.isEmpty ? '' : segs.last;
  }

  /// `jsonRpcMethod` + config-driven `body()` for `--client-json-rpc` mode.
  /// The base class owns transport (path/verb/encoding); the generated
  /// class only names the RPC method and provides the POST body. Field
  /// serialization mirrors model `toJson` exactly (primitives pass through,
  /// models go through `.toJson(config: config)`, everything wrapped in
  /// `config.encodeMap`) — `body()` never holds a modeled type, only the
  /// flattened primitive map the OpenAPI operation declares.
  void _emitJsonRpcBody(
    List<String> lines,
    String rpcMethod,
    List<ClientParamInfo> params,
  ) {
    lines.add('  @override');
    lines.add(
      "  String? get jsonRpcMethod => '${escapeDartString(rpcMethod)}';",
    );
    lines.add('');
    lines.add('  @override');
    lines.add('  dynamic body($_toJsonParams) =>');
    lines.add('      config.encodeMap(<String, dynamic>{');
    for (final p in params) {
      final read = p.dartName == 'config' ? 'this.${p.dartName}' : p.dartName;
      final nullable = !p.required && p.defaultValue == null;
      lines.add(
        "        '${p.jsonName}': ${_valueToJson(read, p.typeRef, nullable)},",
      );
    }
    lines.add('      });');
    lines.add('');
  }

  /// Query-parameter value: primitives stay primitive in the
  /// `Map<String, dynamic>` (transport stringifies for [Uri]), everything
  /// else serializes via `.toJson()`. Never `.toString()`.
  String _queryValueExpr(ClientParamInfo p) {
    final nullAware = (!p.required && p.defaultValue == null) ? '?' : '';
    // Lists: serialize model elements via toJson, then join. join() itself
    // stringifies primitives, so no toString() here either.
    if (p.typeRef.kind == 'list' && p.typeRef.item != null) {
      final item = p.typeRef.item!;
      var itemBase = item.dartType;
      if (itemBase.endsWith('?')) {
        itemBase = itemBase.substring(0, itemBase.length - 1);
      }
      final resolved = _resolveTypedefTarget(itemBase);
      if (_typeNeedsToJson(itemBase) ||
          _typeNeedsToJson(resolved) ||
          resolved == 'BigInt') {
        final bang = item.isNullable ? '?' : '';
        if (resolved == 'BigInt') {
          return "${p.dartName}$nullAware.map((e) => e$bang.toString()).join(',')";
        }
        return "${p.dartName}$nullAware.map((e) => e$bang.toJson()).join(',')";
      }
      return "${p.dartName}$nullAware.join(',') /* TODO: verify multi-value query param encoding */";
    }
    var base = p.typeRef.dartType;
    if (base.endsWith('?')) base = base.substring(0, base.length - 1);
    final resolved = _resolveTypedefTarget(base);
    // BigInt stays a BigInt in the map (transport stringifies); it is not
    // valid to toString() here per the query contract.
    if (base == 'BigInt' || resolved == 'BigInt') return p.dartName;
    if (_typeNeedsToJson(base) || _typeNeedsToJson(resolved)) {
      return '${p.dartName}$nullAware.toJson()';
    }
    // Primitive (String/int/num/double/bool/Map/dynamic): as-is.
    return p.dartName;
  }

  /// Default-config serializer for the legacy `--client-body-getter` path
  /// (`Map? get body`, used with custom hand bases). The standard
  /// `dynamic body({... config ...})` path instead threads `config` through
  /// via [_valueToJson], exactly like model `toJson`.
  String _bodySerializeExpr(String fieldName, TypeRef tr) {
    if (tr.kind == 'class' || tr.kind == 'sealed') return '$fieldName.toJson()';
    if (tr.kind == 'list' &&
        tr.item != null &&
        (tr.item!.kind == 'class' || tr.item!.kind == 'sealed')) {
      return '$fieldName.map((e) => e.toJson()).toList()';
    }
    if (tr.kind == 'map' &&
        tr.value != null &&
        (tr.value!.kind == 'class' || tr.value!.kind == 'sealed')) {
      return '$fieldName.map((k, v) => MapEntry(k, v.toJson()))';
    }
    return fieldName;
  }

  /// Path relative to the spec-declared base (`base_path.path` or Swagger
  /// 2.0 `basePath`, when it is a plain prefix without placeholders), used
  /// ONLY for client class-name suffixes so `/api/v3/account` yields
  /// `...Account` instead of `...ApiV3Account`. Emitted URLs, type hints
  /// and model names keep the full path (renaming those would desync the
  /// types-only output from client runs sharing it).
  String _stripClientBase(String path) {
    String? base = _basePathTemplate;
    if (base != null && base.contains('{')) base = null;
    base ??= openapi['basePath'] as String?;
    if (base == null || base.isEmpty || base == '/') return path;
    if (path == base) return '/';
    if (path.startsWith('$base/')) return path.substring(base.length);
    return path;
  }

  String _clientClassName(
    String clientClass,
    String method,
    String path,
    Map<String, dynamic> operation,
    Set<String> used, {
    String? nameSuffix,
  }) {
    // Prefer explicit --client-prefix; otherwise fall back to the base
    // client class name so request wrappers stay namespaced.
    final head = clientPrefix.isNotEmpty
        ? sanitizeClassName(clientPrefix)
        : sanitizeClassName(clientClass);
    final suffix =
        nameSuffix ??
        _pathTypeBase(
          _stripClientBase(path),
          method,
          operation,
          stripApiPrefix: true,
        );
    var name = '$head$suffix';
    // If the path base already includes the method (no operationId), avoid
    // doubling the method when we need a disambiguator.
    if (used.contains(name)) {
      final m =
          '${method[0].toUpperCase()}${method.substring(1).toLowerCase()}';
      if (!suffix.startsWith(m)) {
        name = '$head$m$suffix';
      }
    }
    final baseName = name;
    var i = 2;
    while (used.contains(name)) {
      name = '$baseName$i';
      i++;
    }
    used.add(name);
    return name;
  }

  /// [resultType, serviceType, onresBody] for a `--client-result-map`
  /// override type: primitives coerce via JsonParser, collections cast,
  /// everything else parses via `.fromJson`.
  List<String> _overrideResultTypes(String type) {
    final t = type.trim();
    if (t == 'String') {
      return [t, 'dynamic', 'return JsonParser.valueAsString<String>(result);'];
    }
    if (t == 'int') {
      return [t, 'dynamic', 'return JsonParser.valueAsInt<int>(result);'];
    }
    if (t == 'BigInt') {
      return [t, 'dynamic', 'return JsonParser.valueAsBigInt<BigInt>(result);'];
    }
    if (t == 'bool') {
      return [t, 'dynamic', 'return JsonParser.valueAsBool<bool>(result);'];
    }
    if (t == 'double') {
      return [t, 'dynamic', 'return JsonParser.valueAsDouble<double>(result);'];
    }
    if (t == 'num') {
      return [t, 'dynamic', 'return JsonParser.valueAsNum<num>(result);'];
    }
    if (t.startsWith('Map<')) {
      if (t == 'Map<String, dynamic>') {
        // Service already hands us exactly this type — no copy/cast needed.
        return [t, 'Map<String, dynamic>', 'return result;'];
      }
      return [t, 'Map<String, dynamic>', 'return $t.from(result as Map);'];
    }
    if (t.startsWith('List<')) {
      return [t, 'List<dynamic>', 'return $t.from(result);'];
    }
    return [t, 'Map<String, dynamic>', 'return $t.fromJson(result);'];
  }

  /// RESULT type override for an operation from `--client-result-map`.
  /// Lookup order: operationId, then `"METHOD path"`, then (jsonRpc mode)
  /// the bare method name.
  String? _clientResultOverride(
    String method,
    String path,
    Map<String, dynamic> operation,
  ) {
    if (clientResultMap.isEmpty) return null;
    for (final key in _clientOpKeys(method, path, operation)) {
      if (clientResultMap.containsKey(key)) return clientResultMap[key];
    }
    return null;
  }

  /// Lookup keys identifying an operation for `--client-result-map` and
  /// `--client-exclude`: operationId, then `"METHOD path"`, then (jsonRpc
  /// mode) the bare method name.
  List<String> _clientOpKeys(
    String method,
    String path,
    Map<String, dynamic> operation,
  ) {
    final keys = <String>[];
    final opId = operation['operationId'];
    if (opId is String && opId.isNotEmpty) keys.add(opId);
    keys.add('${method.toUpperCase()} $path');
    if (clientJsonRpc) keys.add(_jsonRpcMethodName(path));
    return keys;
  }

  /// True when an operation is skipped from client generation
  /// (`--client-exclude`, comma-separated match against [_clientOpKeys]).
  /// For hand-maintained methods with custom wire logic (BOC deserialization,
  /// non-standard unwraps) that a generated client cannot express.
  bool _isClientExcluded(
    String method,
    String path,
    Map<String, dynamic> operation,
  ) {
    if (clientExclude.isEmpty) return false;
    return _clientOpKeys(method, path, operation).any(clientExclude.contains);
  }

  /// Extra `params()` fields for `--client-json-rpc` mode taken from a POST
  /// requestBody object schema (deduped against query/path params by the
  /// caller via json names).
  List<ClientParamInfo> _jsonRpcBodyParams(
    Map<String, dynamic> operation,
    String typeBase,
  ) {
    final schema = _requestBodySchemaForOperation(operation);
    if (schema == null) return const [];
    final unwrapped = _unwrap(schema);
    final props = asMap(unwrapped['properties']);
    if (props.isEmpty) return const [];
    final required = asList(unwrapped['required']).cast<String>().toSet();
    final out = <ClientParamInfo>[];
    for (final entry in props.entries) {
      final jsonName = entry.key.toString();
      final tr = _typeRef(
        entry.value,
        hintName: '$typeBase${snakeToCamel(jsonName, capitalizeFirst: true)}',
      );
      out.add(
        ClientParamInfo(
          dartName: sanitizeFieldName(jsonName),
          jsonName: jsonName,
          typeRef: tr,
          required: required.contains(jsonName) && !tr.isNullable,
          location: 'body',
        ),
      );
    }
    return out;
  }

  /// Full `params()` field list for `--client-json-rpc` mode: query/path
  /// params plus POST-body object properties not already covered.
  /// (Member-name collisions are handled centrally in [_genClientRequest].)
  List<ClientParamInfo> _jsonRpcParams(
    Map<String, dynamic> operation,
    List<ClientParamInfo> params,
    String typeBase,
  ) {
    final have = {for (final p in params) p.jsonName};
    final out = [...params];
    for (final p in _jsonRpcBodyParams(operation, typeBase)) {
      if (have.add(p.jsonName)) out.add(p);
    }
    return out;
  }

  String _genClientRequest(
    String clientClass,
    String method,
    String path,
    Map<String, dynamic> operation,
    Map<String, dynamic> pathItem,
    Set<String> usedNames,
  ) {
    final name = _clientClassName(
      clientClass,
      method,
      path,
      operation,
      usedNames,
      nameSuffix: clientJsonRpc
          ? sanitizeClassName(_jsonRpcMethodName(path))
          : null,
    );
    // Shared path/operationId token for response/body/params type hints
    // (e.g. V2TealDisassemble → ResponseV2TealDisassemble).
    final typeBase = _pathTypeBase(path, method, operation);

    final responseSchema = _responseSchemaForOperation(operation);
    final docLines = <String>[
      '/// ${method.toUpperCase()} ${_applyBasePath(path)}',
    ];
    String resultType, serviceType, onresBody;
    bool nullable = false;
    bool isDynamic = responseSchema == null;
    if (isDynamic) {
      resultType = 'dynamic';
      serviceType = 'dynamic';
      onresBody = 'return result;';
      docLines.add(
        '/// TODO: no JSON response schema found for this operation; '
        'RESULT/SERVICERESPONSE default to `dynamic` — fill in manually.',
      );
    } else {
      final tr = _typeRef(responseSchema, hintName: 'Response$typeBase');
      final rst = _resultAndServiceTypes(tr, hintName: 'Response$typeBase');
      isDynamic = tr.isDynamic;
      nullable = tr.isNullable;
      resultType = rst[0];
      serviceType = rst[1];
      if (nullable && (!isDynamic && !tr.isNullType)) {
        resultType = "$resultType?";
        if (serviceType != "dynamic") serviceType = "$serviceType?";
      }
      onresBody = rst[2];
    }
    // Per-operation RESULT override (`--client-result-map`): the spec's
    // response schema may be a generic envelope (e.g. TonlibResponse) while
    // the provider unwraps to a method-specific payload.
    final resultOverride = _clientResultOverride(method, path, operation);
    if (resultOverride != null && resultOverride.isNotEmpty) {
      final rst = _overrideResultTypes(resultOverride);
      resultType = rst[0];
      serviceType = rst[1];
      onresBody = rst[2];
      nullable = false;
      isDynamic = false;
    }

    // A RESULT type sharing the wrapper's own name (e.g. the
    // `TonCenterDetectHash` model vs the `TonCenterDetectHash` request)
    // would resolve to the wrapper inside the class body — address the
    // model through a prefixed models import (`models.X`) and mark the
    // client file for it.
    if (resultType == name) {
      resultType = 'models.$name';
      onresBody = onresBody.replaceAll(' $name.', ' models.$name.');
      if (serviceType == name) serviceType = 'models.$serviceType';
      clientNeedsModelsImport = true;
    }

    // Operation path with optional openapi base_path prefix applied.
    final effectivePath = _applyBasePath(path);

    final params = _clientParams(
      _mergedParameters(pathItem, operation),
      effectivePath,
    );
    // base_path placeholders: merge defaults onto params discovered from the
    // effective path template, or insert if missing.
    final baseParams = _basePathParams();
    final baseByName = {for (final p in baseParams) p.jsonName: p};
    for (final p in params) {
      if (p.location != 'path') continue;
      final bp = baseByName[p.jsonName];
      if (bp == null) continue;
      if (bp.defaultValue != null) {
        p.defaultValue = bp.defaultValue;
        p.required = false;
      }
    }
    final existingPathNames = {
      for (final p in params.where((p) => p.location == 'path')) p.jsonName,
    };
    for (final bp in baseParams.reversed) {
      if (existingPathNames.contains(bp.jsonName)) continue;
      params.insert(0, bp);
    }

    final bodyPlan = _clientBodyPlan(operation, typeBase: typeBase);

    // POST-body object properties flatten into scalar fields — never a
    // model-typed `requestBody` field holding e.g. `TonCenterConfigParamRequest`:
    // the generated class carries exactly the properties the OpenAPI
    // operation declares, and `body()` serializes each one like model
    // `toJson` does. (In `--client-json-rpc` mode this flattening already
    // happened inside [_jsonRpcParams]; in REST mode the body-only props are
    // appended below, deduped by wire name so a shared field serves both
    // `queryParameters` and `body()`.)
    final List<ClientParamInfo> flatBodyProps = clientJsonRpc
        ? const <ClientParamInfo>[]
        : _jsonRpcBodyParams(operation, typeBase);

    // jsonRpc mode flattens POST-body object properties into the same field
    // list the body() map uses.
    final List<ClientParamInfo> allParams;
    if (clientJsonRpc) {
      allParams = _jsonRpcParams(operation, params, typeBase);
    } else {
      final have = {for (final p in params) p.jsonName};
      allParams = [
        ...params,
        for (final p in flatBodyProps)
          if (have.add(p.jsonName)) p,
      ];
    }

    // Client field names must not shadow base-class members
    // (jsonRpcMethod, body(), path, headers, ...) or the body()/toJson
    // `config` parameter; collisions get a deterministic `_` suffix, wire
    // jsonName untouched. (`method` stays reserved for stability even though
    // the member is now named `jsonRpcMethod`.)
    const reservedClientFields = {
      'method',
      'jsonRpcMethod',
      'params',
      'body',
      'config',
      'models',
      'path',
      'headers',
      'queryParameters',
      'pathParameters',
      'requestMethod',
      'onResponse',
      'buildRequest',
    };
    for (final p in allParams) {
      if (reservedClientFields.contains(p.dartName)) {
        p.dartName = '${p.dartName}_';
      }
    }

    final lines = <String>[docLines.join('\n')];

    String? bodyFieldName;
    if (clientJsonRpc) {
      // No model-typed body field: POST-body object properties flatten into
      // scalar params (see _jsonRpcParams) to match hand-written request
      // classes (`address`, `seqno`, ... instead of `requestBody`).
      bodyFieldName = null;
    } else if (flatBodyProps.isNotEmpty) {
      // Object-shaped requestBody flattens into scalar fields (see above) —
      // no model-typed field.
      bodyFieldName = null;
    } else if (bodyPlan.kind == 'plain' && bodyPlan.paramTypeRef != null) {
      bodyFieldName = 'requestBody';
    } else if (bodyPlan.kind == 'json_rpc' && bodyPlan.paramTypeRef != null) {
      bodyFieldName = 'params';
    }
    // Operations carrying a body member extend the POST base when one is
    // configured (e.g. TonApiPostRequest with `body` support).
    final effectiveBase =
        (bodyFieldName != null &&
            clientPostBase != null &&
            clientPostBase!.isNotEmpty)
        ? clientPostBase!
        : clientClass;
    lines.add(
      'class $name extends $effectiveBase<$resultType, $serviceType> {',
    );

    for (final p in allParams) {
      // Path params with defaults stay non-nullable String (default in ctor).
      final nullable = (!p.required && p.defaultValue == null) ? '?' : '';
      lines.add('  final ${p.typeRef.dartType}$nullable ${p.dartName};');
    }
    if (bodyFieldName != null) {
      lines.add('  final ${bodyPlan.paramTypeRef!.dartType} $bodyFieldName;');
    }
    lines.add('');

    final hasCtorFields = allParams.isNotEmpty || bodyFieldName != null;
    final cc = clientConstCtors ? 'const ' : '';
    if (hasCtorFields) {
      lines.add('  $cc$name({');
      for (final p in allParams) {
        if (p.defaultValue != null) {
          lines.add(
            "    this.${p.dartName} = '${escapeDartString(p.defaultValue!)}',",
          );
        } else if (p.required) {
          lines.add('    required this.${p.dartName},');
        } else {
          lines.add('    this.${p.dartName},');
        }
      }
      if (bodyFieldName != null) {
        lines.add('    required this.$bodyFieldName,');
      }
      lines.add('  });');
    } else {
      lines.add('  $cc$name();');
    }
    lines.add('');

    if (clientJsonRpc) {
      final transport = jsonRpcTransportPath;
      lines.add('  @override');
      if (transport != null && transport.isNotEmpty) {
        lines.add("  String? get path => '${escapeDartString(transport)}';");
      } else {
        // No transport op declared: satisfy the base contract explicitly.
        lines.add('  String? get path => null;');
      }
      lines.add('');
      // JSON-RPC requests always travel as POST to the transport path.
      lines.add('  @override');
      lines.add('  RequestMethod get requestMethod => RequestMethod.post;');
      lines.add('');
      _emitJsonRpcBody(lines, _jsonRpcMethodName(effectivePath), allParams);
    } else {
      final pathNull = clientPathMember == 'path' ? '?' : '';
      lines.add('  @override');
      lines.add(
        '  String$pathNull get $clientPathMember => ${_clientPathExpr(effectivePath, params, clientPathParams == 'list')};',
      );
      lines.add('');
      if (clientPathParams == 'list') {
        // Path placeholders substitute as strings. String fields pass
        // through; numbers/bools/BigInts stringify (nullable ones fall back
        // to '' — a missing segment 404s anyway); anything else stays bare
        // so a real mismatch surfaces as a compile error, not wrong wire.
        String pathExpr(ClientParamInfo p) {
          final mode = p.typeRef.fromJsonMode;
          if (mode == 'string') return p.dartName;
          if (mode == 'int' ||
              mode == 'num' ||
              mode == 'double' ||
              mode == 'bool' ||
              mode == 'bigint') {
            if (p.typeRef.isNullable || !p.required) {
              return '${p.dartName}?.toString() ?? \'\'';
            }
            return '${p.dartName}.toString()';
          }
          return p.dartName;
        }

        final pathNames = [
          for (final p in params)
            if (p.location == 'path') pathExpr(p),
        ];
        if (pathNames.isNotEmpty) {
          lines.add('  @override');
          lines.add(
            '  List<String> get pathParameters => [${pathNames.join(', ')}];',
          );
          lines.add('');
        }
      }

      lines.add('  @override');
      lines.add(
        '  RequestMethod get requestMethod => RequestMethod.${method.toLowerCase()};',
      );

      final queryParams = params.where((p) => p.location == 'query').toList();
      if (queryParams.isNotEmpty) {
        lines.add('');
        lines.add('  @override');
        lines.add('  Map<String, dynamic> get queryParameters => {');
        for (final p in queryParams) {
          final val = _queryValueExpr(p);
          lines.add("    '${p.jsonName}': $val,");
        }
        lines.add('  };');
      }

      if (bodyPlan.kind == 'json_rpc') {
        lines.add('');
        lines.add('  @override');
        lines.add(
          "  String? get $clientMethodMember => '${escapeDartString(bodyPlan.jsonRpcMethod!)}';",
        );
      }

      if (flatBodyProps.isNotEmpty) {
        // Flattened object body: config-driven map over the body-only props
        // (primitives pass through, models serialize via toJson(config)).
        final mergedByJson = {for (final p in allParams) p.jsonName: p};
        lines.add('');
        lines.add('  @override');
        lines.add('  dynamic body($_toJsonParams) =>');
        lines.add('      config.encodeMap(<String, dynamic>{');
        for (final p in flatBodyProps) {
          final merged = mergedByJson[p.jsonName]!;
          final read = merged.dartName == 'config'
              ? 'this.${merged.dartName}'
              : merged.dartName;
          final nullable = !merged.required && merged.defaultValue == null;
          lines.add(
            "        '${p.jsonName}': "
            '${_valueToJson(read, merged.typeRef, nullable)},',
          );
        }
        lines.add('      });');
      } else if (bodyFieldName != null) {
        lines.add('');
        lines.add('  @override');
        if (clientBodyGetter) {
          final expr = _bodySerializeExpr(
            bodyFieldName,
            bodyPlan.paramTypeRef!,
          );
          lines.add('  Map<String, dynamic>? get body => $expr;');
        } else {
          // Single non-object body (array/primitive): config threads through
          // exactly like model toJson.
          final expr = _valueToJson(
            bodyFieldName,
            bodyPlan.paramTypeRef!,
            false,
          );
          lines.add('  dynamic body($_toJsonParams) => $expr;');
        }
      }

      lines.add('');
    }
    lines.add('  @override');
    lines.add('  $resultType onResponse($serviceType result) {');
    if (nullable && !isDynamic && resultType != serviceType) {
      lines.add('  if(result == null) return null;');
    }
    lines.add('    $onresBody');
    lines.add('  }');
    lines.add('}');
    return lines.join('\n');
  }

  /// Turn an OpenAPI path into a snake_case file stem, dropping path
  /// parameters (`{address}`) and normalizing separators.
  ///
  /// Examples:
  ///   `/swagger.json`                        → `swagger_json`
  ///   `/v2/accounts/{address}`               → `v2_accounts`
  ///   `/v2/accounts/{address}/applications`  → `v2_accounts_applications`
  String pathFileStem(String path) {
    var s = path.replaceAll(RegExp(r'\{[^{}]+\}'), '');
    s = s.replaceAll(RegExp(r'/+'), '/');
    s = s.replaceAll(RegExp(r'^/+|/+$'), '');
    s = s.replaceAll('.', '_');
    s = s.replaceAll('/', '_');
    s = s.replaceAll(RegExp(r'[^a-zA-Z0-9_]+'), '_');
    s = s.replaceAll(RegExp(r'_+'), '_');
    s = s.replaceAll(RegExp(r'^_|_$'), '');
    if (s.isEmpty) s = 'root';
    return s.toLowerCase();
  }

  /// Generate the client base stack for `--client-parent`:
  /// chain root (`<'parent><RESULT, RESPONSE, E extends
  /// BaseServiceRequestParams>`), provider base (`<'clientClass>` with the
  /// transport contract: `path`, `requestMethod`, `queryParameters`,
  /// `headers`, `body()`, `jsonRpcMethod` — plus a `buildRequest` that throws
  /// [UnimplementedError] until hand-written per provider), and request
  /// details (`<details>`).
  ///
  /// Chains with several providers (e.g. TON: TonApi / TonCenterV2 /
  /// TonCenterV3) share one parent while each provider gets its own base
  /// + details pair. The per-method classes need no changes: JSON-RPC-style
  /// requests already provide `path` / `jsonRpcMethod` / `body()` /
  /// `onResponse`, which the hand-written `buildRequest` consumes.
  String generateClientBase(
    String parent,
    String clientClass,
    String detailsClass,
  ) {
    final p = sanitizeClassName(parent);
    final c = sanitizeClassName(clientClass);
    final d = sanitizeClassName(detailsClass);
    return '''
/// Chain-level client root: binds RESULT/RESPONSE to a concrete
/// [BaseServiceRequestParams] implementation [E].
///
/// Chains with several providers share one parent, e.g. TON:
/// `TonApiClient`, `TonCenterV2Client` and `TonCenterV3Client` all extend
/// `TonClient<RESULT, RESPONSE, TonRequestDetails>`.
abstract class $p<RESULT, RESPONSE, E extends BaseServiceRequestParams>
    extends BaseServiceRequest<RESULT, RESPONSE, E> {}

/// Request details for [$c] requests.
class $d extends BaseServiceRequestParams {
  const $d({
    required super.requestID,
    required super.path,
    required super.responseEncoding,
    required super.headers,
    required super.requestMethod,
    super.bodyBytes,
    super.bodyString,
    super.successStatusCodes,
    super.errorStatusCodes,
    super.network,
  });

  @override
  Map<String, dynamic> toJson() => {
    'requestID': requestID,
    'path': path,
    'headers': headers,
    'requestMethod': requestMethod.name,
    'responseEncoding': responseEncoding.name,
    'successStatusCodes': successStatusCodes,
    'errorStatusCodes': errorStatusCodes,
    'bodyBytes': bodyBytes,
    'bodyString': bodyString,
  };

  factory $d.fromJson(Map<String, dynamic> json) {
    T asEnum<T extends Enum>(List<T> values, dynamic raw) {
      return values.firstWhere(
        (e) => e.name == raw?.toString(),
        orElse: () => throw ArgumentError.value(raw, 'unknown enum value'),
      );
    }

    return $d(
      requestID: JsonParser.valueAsInt<int>(json['requestID']),
      path: JsonParser.valueAsString<String?>(json['path']),
      responseEncoding: asEnum(
        ServiceReponseEncoding.values,
        json['responseEncoding'],
      ),
      headers: Map<String, String>.from(json['headers'] as Map? ?? {}),
      requestMethod: asEnum(RequestMethod.values, json['requestMethod']),
      bodyBytes:
          (json['bodyBytes'] as List?)?.map((e) => (e as num).toInt()).toList(),
      bodyString: JsonParser.valueAsString<String?>(json['bodyString']),
      successStatusCodes:
          (json['successStatusCodes'] as List?)
              ?.map((e) => (e as num).toInt())
              .toList(),
      errorStatusCodes:
          (json['errorStatusCodes'] as List?)
              ?.map((e) => (e as num).toInt())
              .toList(),
    );
  }

  @override
  Uri encodeUrl(String url) {
    var uri = url;
    if (uri.endsWith('/')) uri = uri.substring(0, uri.length - 1);
    return Uri.parse('\$uri\${path ?? ''}');
  }

  @override
  SerializationIdentifier get serializationIdentifier {
    final network = this.network;
    if (network == null) {
      throw StateError(
        'CBOR serialization of $d requires a network; '
        'pass `network` explicitly (JSON transport never touches this).',
      );
    }
    return network.identifier;
  }

  @override
  List<CborObject?> get serializationItems => [
    CborMapValue.definite(
      headers.map((k, v) => MapEntry(CborStringValue(k), CborStringValue(v))),
    ),
    requestMethod.value.toCbor(),
    responseEncoding.value.toCbor(),
    CborTagSerializable.listFromDynamic(
      successStatusCodes?.map((e) => CborIntValue(e)).toList() ?? [],
    ),
    CborTagSerializable.listFromDynamic(
      errorStatusCodes?.map((e) => CborIntValue(e)).toList() ?? [],
    ),
    bodyBytes?.toCborBytes(),
    bodyString?.toCbor(),
    path?.toCbor(),
    requestID.toCbor(),
  ];
}

/// Provider base for [$c] requests: transport contract only. Per-method
/// classes provide `path`, `requestMethod`, `queryParameters`, `headers`,
/// a config-driven `body()` — and, for JSON-RPC-style requests only, the
/// RPC operation name via `jsonRpcMethod`; `buildRequest` is intentionally
/// left unimplemented here — each provider hand-writes its own envelope
/// (REST query-string vs JSON-RPC `{method, params, id}` POST, ...).
abstract class $c<RESULT, RESPONSE>
    extends $p<RESULT, RESPONSE, $d> {
  String? get path;
  @override
  RequestMethod get requestMethod => RequestMethod.get;
  Map<String, dynamic> get queryParameters => const {};
  Map<String, String?> get headers => const {};
  dynamic body() => null;
  String? get jsonRpcMethod => null;

  @override
  $d buildRequest(int v) {
    throw UnimplementedError(
      '$c.buildRequest must be implemented by hand for this provider.',
    );
  }
}
''';
  }

  /// Generate one request-wrapper class per HTTP operation in `paths`, each
  /// extending `{clientClass}<RESULT, SERVICERESPONSE>`.
  ///
  /// Returns a map of file-stem → source. When [splitPerPath] is false there
  /// is a single entry with key `''` (caller writes one combined file).
  /// When true, keys are path-derived stems (e.g. `v2_accounts`).
  Map<String, String> generateClientRequests(
    String clientClass, {
    bool splitPerPath = false,
  }) {
    clientNeedsModelsImport = false;
    final paths = asMap(openapi['paths']);
    const httpMethods = {'get', 'post', 'put', 'patch', 'delete'};
    final usedNames = <String>{};
    // stem -> list of class source blocks
    final grouped = <String, List<String>>{};
    // In jsonRpc mode one class is emitted per RPC method (not per HTTP
    // operation): the generic transport op (`.../jsonRPC`) is skipped and
    // GET/POST twins collapse, keeping the variant with the most params.
    final jsonRpcSeen = <String, _JsonRpcOp>{};
    for (final pathEntry in paths.entries) {
      final path = pathEntry.key;
      final pathItem = asMapOrNull(pathEntry.value);
      if (pathItem == null) continue;
      final stem = splitPerPath ? pathFileStem(path) : '';
      for (final opEntry in pathItem.entries) {
        final method = opEntry.key;
        if (!httpMethods.contains(method.toLowerCase())) continue;
        final operation = asMapOrNull(opEntry.value);
        if (operation == null) continue;
        if (_isClientExcluded(method, path, operation)) continue;
        if (clientJsonRpc) {
          final rpcMethod = _jsonRpcMethodName(_applyBasePath(path));
          if (rpcMethod.isEmpty || rpcMethod.toLowerCase() == 'jsonrpc') {
            // Generic transport op: remember its path for the generated
            // classes, then skip it (it is the envelope, not a method).
            jsonRpcTransportPath ??= _applyBasePath(path);
            continue;
          }
          final prev = jsonRpcSeen[rpcMethod];
          final count =
              _mergedParameters(pathItem, operation).length +
              _jsonRpcBodyParams(operation, '').length;
          if (prev == null || count > prev.paramCount) {
            jsonRpcSeen[rpcMethod] = _JsonRpcOp(
              method,
              path,
              operation,
              pathItem,
              stem,
              count,
            );
          }
          continue;
        }
        final block = _genClientRequest(
          clientClass,
          method,
          path,
          operation,
          pathItem,
          usedNames,
        );
        grouped.putIfAbsent(stem, () => <String>[]).add(block);
      }
    }
    if (clientJsonRpc) {
      for (final op in jsonRpcSeen.values) {
        final block = _genClientRequest(
          clientClass,
          op.method,
          op.path,
          op.operation,
          op.pathItem,
          usedNames,
        );
        grouped.putIfAbsent(op.stem, () => <String>[]).add(block);
      }
    }
    return {
      for (final e in grouped.entries)
        e.key: e.value.isEmpty ? '' : '${e.value.join('\n\n')}\n',
    };
  }
}

/// One deferred JSON-RPC operation: the winning HTTP variant per RPC method
/// name (most params) in `--client-json-rpc` mode.
class _JsonRpcOp {
  final String method;
  final String path;
  final Map<String, dynamic> operation;
  final Map<String, dynamic> pathItem;
  final String stem;
  final int paramCount;

  _JsonRpcOp(
    this.method,
    this.path,
    this.operation,
    this.pathItem,
    this.stem,
    this.paramCount,
  );
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

class CliArgs {
  String? input;
  String output = 'generated/openapi_models.dart';
  bool split = false;
  String packageImport = 'package:blockchain_utils/blockchain_utils.dart';
  String? excludePattern;
  String? clientClass;
  String? clientImport;
  String? clientOutput;
  String? classPrefix;
  String? clientPrefix;
  bool splitPerPath = false;
  final List<String> replacePatterns = [];
  // Optional `--json-config Name:import-uri` for config-driven toJson.
  String jsonConfigType = 'JsonifyConfig';
  String jsonConfigDefault = 'DefaultJsonifyConfig.defaultConfig';
  String? jsonConfigImport;
  // Client emitter knobs (see OpenApiToDart fields for semantics).
  String clientPathMember = 'path';
  String clientPathParams = 'inline';
  bool clientBodyGetter = false;
  String clientMethodMember = 'jsonRpcMethd';
  bool clientJsonRpc = false;
  String? clientResultMapPath;
  // Comma-separated `--client-exclude` operation keys (same lookup as
  // result-map) skipped from client generation.
  String? clientExcludeRaw;
  // Override for the models import emitted into client output
  // (`--client-models-import URI`, e.g. a package: URI when the client file
  // lives in a different directory than the models file).
  String? clientModelsImport;
  // Base-stack emission for `--client` (see generateClientBase):
  // `--client-parent` names the chain root
  // (TonClient<RESULT, RESPONSE, E extends BaseServiceRequestParams>),
  // `--client-details` names the request-details class
  // (default: <ClientClass>Details).
  String? clientParent;
  String? clientDetails;
  // Omit `const` on generated client constructors (for bases without a
  // const constructor). Default keeps `const`.
  bool clientConstCtors = true;
  // Base class for operations WITH a body member (`--client-post-base`,
  // e.g. a POST base with `body` support). Defaults to [clientClass].
  // Lets one generation run cover GETs (base) and POSTs (post base), e.g.
  // ton_dart's TonApiRequest / TonApiPostRequest split.
  String? clientPostBase;
}

void _printUsage() {
  stdout.writeln(
    'Convert OpenAPI JSON schemas to Dart '
    '(sealed enums/real enums + blockchain_utils fromJson).',
  );
  stdout.writeln('');
  stdout.writeln('Usage:');
  stdout.writeln('  dart run openapi_to_dart.dart <input.json> [options]');
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln(
    '  -o, --output PATH        Output .dart file (or directory with --split)',
  );
  stdout.writeln(
    '                           default: generated/openapi_models.dart',
  );
  stdout.writeln(
    '  --split                  Write one file per type into the output directory',
  );
  stdout.writeln('  --import IMPORT          Dart import for JSON helpers');
  stdout.writeln(
    '  --exclude-pattern REGEX  Skip schemas whose original name matches this regex',
  );
  stdout.writeln(
    '  --client-class NAME      Also generate request-wrapper classes extending NAME',
  );
  stdout.writeln(
    '  --client-import IMPORT   Import(s) for the base client class / RequestMethod',
  );
  stdout.writeln(
    '                           (comma-separated for multiple, e.g. a.dart,b.dart)',
  );
  stdout.writeln(
    '  --client-output PATH     Output path for the client request classes file',
  );
  stdout.writeln(
    '  --prefix PREFIX          Prepend PREFIX to every generated model type name',
  );
  stdout.writeln(
    '                           (e.g. Algo → AlgoAccount). Optional.',
  );
  stdout.writeln(
    '  --client-prefix PREFIX   Prepend PREFIX to generated client request class',
  );
  stdout.writeln(
    '                           names instead of the --client-class name. Optional.',
  );
  stdout.writeln(
    '  --split-per-path         Write one client request file per API path stem',
  );
  stdout.writeln(
    '                           (path params stripped), e.g. /v2/accounts/{id}',
  );
  stdout.writeln('                           → v2_accounts.dart. Optional.');
  stdout.writeln(
    '  --client-path-member N   Getter name for the endpoint URL in generated',
  );
  stdout.writeln(
    '                           client classes (default: path). A non-default',
  );
  stdout.writeln(
    '                           name emits a non-nullable getter.',
  );
  stdout.writeln(
    '  --client-path-params M   Path parameter style: inline (default,',
  );
  stdout.writeln("                           '/v2/a/\$x') or list (template +");
  stdout.writeln(
    '                           `List<String> get pathParameters`).',
  );
  stdout.writeln('  --client-body-getter     Emit `Map? get body` instead of');
  stdout.writeln(
    '                           config-driven `dynamic body()` in clients.',
  );
  stdout.writeln(
    '  --client-method-member N Getter name for the JSON-RPC operation name',
  );
  stdout.writeln('                           (default: jsonRpcMethd).');
  stdout.writeln(
    '  --client-json-rpc        Emit JSON-RPC-shaped clients (jsonRpcMethod +',
  );
  stdout.writeln(
    '                           body() + onResponse; hand-written buildRequest',
  );
  stdout.writeln('                           owns transport).');
  stdout.writeln(
    '  --no-client-const        Omit `const` on generated client constructors',
  );
  stdout.writeln(
    '                           (for bases without a const constructor).',
  );
  stdout.writeln(
    '  --client-post-base NAME  Base class for operations WITH a body member',
  );
  stdout.writeln(
    '                           (default: --client-class). E.g. TonApiRequest',
  );
  stdout.writeln(
    '                           for GETs + TonApiPostRequest for POSTs.',
  );
  stdout.writeln(
    '  --client-result-map F    JSON file mapping operations to RESULT types',
  );
  stdout.writeln(
    '                           ({"operationId": "DartType", ...}; also tries',
  );
  stdout.writeln(
    '                           "METHOD path" and bare method names).',
  );
  stdout.writeln(
    '  --client-exclude KS      Comma-separated operation keys (same lookup)',
  );
  stdout.writeln(
    '                           skipped from client generation (hand-kept',
  );
  stdout.writeln('                           methods with custom wire logic).');
  stdout.writeln(
    '  --client-models-import U Models import emitted into client output',
  );
  stdout.writeln(
    '                           (default: relative to the client file; use a',
  );
  stdout.writeln(
    '                           package: URI for cross-directory placement).',
  );
  stdout.writeln(
    '  --client-parent NAME     Also emit the client base stack: chain root',
  );
  stdout.writeln(
    '                           `NAME<RESULT, RESPONSE, E extends',
  );
  stdout.writeln(
    '                           BaseServiceRequestParams>`, provider base',
  );
  stdout.writeln(
    '                           `<--client-class>` with generic REST',
  );
  stdout.writeln(
    '                           buildRequest, and `<--client-details>`',
  );
  stdout.writeln('                           request-details (default');
  stdout.writeln(
    '                           `<--client-class>Details`). E.g. TonClient +',
  );
  stdout.writeln(
    '                           TonApiClient + TonApiRequestDetails.',
  );
  stdout.writeln(
    '  --client-details NAME    Request-details class name for --client-parent',
  );
  stdout.writeln(
    '                           (default: <--client-class>Details).',
  );
  stdout.writeln(
    '  --replace-pattern REGEX  Regex whose matches get replaced with "" in every',
  );
  stdout.writeln('                           generated file (repeatable)');
  stdout.writeln(
    '  --json-config Name:URI  Config-driven toJson: every toJson takes',
  );
  stdout.writeln(
    '                           `{Name} config = {Name}.defaultConfig` and routes',
  );
  stdout.writeln(
    '                           maps/BigInt through `config.encodeMap` /',
  );
  stdout.writeln(
    '                           `config.encodeBigint`. {Name} must implement',
  );
  stdout.writeln(
    '                           JsonifyConfig and is imported from URI.',
  );
  stdout.writeln(
    '                           Default (flag absent): JsonifyConfig with',
  );
  stdout.writeln(
    '                           DefaultJsonifyConfig.defaultConfig from',
  );
  stdout.writeln('                           blockchain_utils.');
  stdout.writeln('  -h, --help               Show this help');
}

CliArgs? _parseArgs(List<String> argv) {
  final args = CliArgs();
  var i = 0;
  while (i < argv.length) {
    final a = argv[i];
    switch (a) {
      case '-h':
      case '--help':
        _printUsage();
        return null;
      case '-o':
      case '--output':
        args.output = argv[++i];
        break;
      case '--split':
        args.split = true;
        break;
      case '--import':
        args.packageImport = argv[++i];
        break;
      case '--exclude-pattern':
        args.excludePattern = argv[++i];
        break;
      case '--client-class':
        args.clientClass = argv[++i];
        break;
      case '--client-import':
        args.clientImport = argv[++i];
        break;
      case '--client-output':
        args.clientOutput = argv[++i];
        break;
      case '--prefix':
        args.classPrefix = argv[++i];
        break;
      case '--client-prefix':
        args.clientPrefix = argv[++i];
        break;
      case '--client-path-member':
        args.clientPathMember = argv[++i];
        break;
      case '--client-path-params':
        args.clientPathParams = argv[++i];
        if (args.clientPathParams != 'inline' &&
            args.clientPathParams != 'list') {
          stderr.writeln(
            'Invalid --client-path-params (expected inline|list): '
            '${args.clientPathParams}',
          );
          _printUsage();
          return null;
        }
        break;
      case '--client-body-getter':
        args.clientBodyGetter = true;
        break;
      case '--client-method-member':
        args.clientMethodMember = argv[++i];
        break;
      case '--client-json-rpc':
        args.clientJsonRpc = true;
        break;
      case '--no-client-const':
        args.clientConstCtors = false;
        break;
      case '--client-post-base':
        args.clientPostBase = argv[++i];
        break;
      case '--client-result-map':
        args.clientResultMapPath = argv[++i];
        break;
      case '--client-exclude':
        args.clientExcludeRaw = argv[++i];
        break;
      case '--client-models-import':
        args.clientModelsImport = argv[++i];
        break;
      case '--client-parent':
        args.clientParent = argv[++i];
        break;
      case '--client-details':
        args.clientDetails = argv[++i];
        break;
      case '--split-per-path':
        args.splitPerPath = true;
        break;
      case '--replace-pattern':
        args.replacePatterns.add(argv[++i]);
        break;
      case '--json-config':
        final spec = argv[++i];
        final sep = spec.indexOf(':');
        if (sep <= 0 || sep == spec.length - 1) {
          stderr.writeln(
            'Invalid --json-config (expected Name:import-uri): $spec',
          );
          _printUsage();
          return null;
        }
        args.jsonConfigType = spec.substring(0, sep).trim();
        args.jsonConfigImport = spec.substring(sep + 1).trim();
        args.jsonConfigDefault = '${args.jsonConfigType}.defaultConfig';
        if (args.jsonConfigType.isEmpty || args.jsonConfigImport!.isEmpty) {
          stderr.writeln(
            'Invalid --json-config (expected Name:import-uri): $spec',
          );
          _printUsage();
          return null;
        }
        break;
      default:
        if (args.input == null && !a.startsWith('-')) {
          args.input = a;
        } else {
          stderr.writeln('Unknown argument: $a');
          _printUsage();
          return null;
        }
    }
    i++;
  }
  if (args.input == null) {
    stderr.writeln('Missing required <input.json> argument.');
    _printUsage();
    return null;
  }
  return args;
}

String _applyReplacePatterns(String text, List<String> patterns) {
  for (final pattern in patterns) {
    text = text.replaceAll(RegExp(pattern, multiLine: true), '');
  }
  return text;
}

// ---------------------------------------------------------------------------
// OpenRPC → OpenAPI normalization
// ---------------------------------------------------------------------------

/// Converts an OpenRPC document (e.g. Filecoin Lotus `full_node_1.36.json`:
/// 100+ methods with all-inline params/results and no reusable schemas or
/// paths) into an OpenAPI-shaped document the generator understands.
///
/// Each method yields two component schemas — `{Method}Params` (object of
/// the method's params, required = required ones) and `{Method}Result`
/// (the method's result schema verbatim) — plus a synthetic
/// `POST /{method.name}` path, so endpoint usage, naming, type mapping and
/// union dispatch all reuse the normal pipeline.
Map<String, dynamic> openrpcToOpenapi(Map<String, dynamic> rpc) {
  final schemas = <String, dynamic>{};
  final paths = <String, dynamic>{};
  for (final mAny in asList(rpc['methods'])) {
    final m = asMapOrNull(mAny);
    if (m == null) continue;
    final name = (m['name']?.toString() ?? '').trim();
    if (name.isEmpty) continue;
    final base = sanitizeClassName(name);
    final description = m['description'];
    final summary = m['summary'];

    final props = <String, dynamic>{};
    final required = <String>[];
    for (final pAny in asList(m['params'])) {
      final p = asMapOrNull(pAny);
      if (p == null) continue;
      final pname = (p['name']?.toString() ?? '').trim();
      if (pname.isEmpty || props.containsKey(pname)) continue;
      final pschema = asMapOrNull(p['schema']) ?? <String, dynamic>{};
      // Keep per-param docs on the property, not the method blob.
      props[pname] = pschema;
      if (p['required'] == true) required.add(pname);
    }
    final paramsName = '${base}Params';
    schemas[paramsName] = {
      if (summary is String && summary.isNotEmpty) 'title': summary,
      if (description is String && description.isNotEmpty)
        'description': description,
      'type': 'object',
      'properties': props,
      if (required.isNotEmpty) 'required': required,
    };

    final result = asMapOrNull(m['result']);
    final resultName = '${base}Result';
    final rschema = result?['schema'];
    schemas[resultName] = rschema is Map
        ? Map<String, dynamic>.from(
            rschema.map((k, v) => MapEntry(k.toString(), v)),
          )
        : <String, dynamic>{
            'description': 'Result of `$name` (no schema declared in OpenRPC).',
          };

    paths['/$name'] = {
      'post': {
        'operationId': name,
        if (summary is String && summary.isNotEmpty) 'summary': summary,
        if (description is String && description.isNotEmpty)
          'description': description,
        'requestBody': {
          'content': {
            'application/json': {
              'schema': {'\$ref': '#/components/schemas/$paramsName'},
            },
          },
          'required': required.isNotEmpty,
        },
        'responses': {
          '200': {
            'description': '',
            'content': {
              'application/json': {
                'schema': {'\$ref': '#/components/schemas/$resultName'},
              },
            },
          },
        },
      },
    };
  }
  final info = asMapOrNull(rpc['info']);
  return {
    'openapi': '3.0.0',
    'info': info ?? {'title': 'OpenRPC', 'version': ''},
    'paths': paths,
    'components': {'schemas': schemas},
  };
}

/// Loads a `--client-result-map` JSON file (`{lookupKey: DartType}`) or
/// returns an empty map when no path is given. Exits non-zero on bad input.
Map<String, String> _loadClientResultMap(String? path) {
  if (path == null) return const {};
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('Client result map not found: $path');
    exit(1);
  }
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map) {
    stderr.writeln('Client result map must be a JSON object: $path');
    exit(1);
  }
  return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
}

void generate(List<String> argv) {
  final args = _parseArgs(argv);
  if (args == null) {
    exit(argv.contains('-h') || argv.contains('--help') ? 0 : 1);
  }

  final inFile = File(args.input!);
  if (!inFile.existsSync()) {
    stderr.writeln('Input not found: ${args.input}');
    exit(1);
  }

  var openapi = asMap(jsonDecode(inFile.readAsStringSync()));
  // OpenRPC documents (e.g. Filecoin Lotus: all-inline method
  // params/results, no reusable schemas/paths) are normalized into an
  // OpenAPI-shaped document first so the normal pipeline applies.
  if (openapi.containsKey('openrpc') && !openapi.containsKey('paths')) {
    openapi = openrpcToOpenapi(openapi);
  }

  final gen = OpenApiToDart(
    openapi,
    packageImport: args.packageImport,
    excludePattern: args.excludePattern,
    classPrefix: args.classPrefix,
    clientPrefix: args.clientPrefix,
    jsonConfigType: args.jsonConfigType,
    jsonConfigDefault: args.jsonConfigDefault,
    jsonConfigImport: args.jsonConfigImport,
    clientPathMember: args.clientPathMember,
    clientPathParams: args.clientPathParams,
    clientBodyGetter: args.clientBodyGetter,
    clientMethodMember: args.clientMethodMember,
    clientJsonRpc: args.clientJsonRpc,
    clientResultMap: _loadClientResultMap(args.clientResultMapPath),
    clientExclude: args.clientExcludeRaw == null
        ? const <String>{}
        : args.clientExcludeRaw!
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toSet(),
    clientParent: args.clientParent,
    clientDetails: args.clientDetails,
    clientConstCtors: args.clientConstCtors,
    clientPostBase: args.clientPostBase,
  );

  String modelsImport;
  final outPath = args.output;

  // Component (types) schemas are always resolved first, so the model
  // classes exist under their canonical names before client request
  // generation runs. Client response/body hints then reuse those classes
  // instead of minting client-driven inline duplicates, and the models
  // output stays types-first.
  gen.ensureAllSchemas();

  // Run client request generation *before* writing models so that any
  // response/request body schemas (including inline ones) discovered while
  // building RESULT types are registered in `generated` and emitted into
  // the models output.
  Map<String, String> clientByStem = {};
  if (args.clientClass != null) {
    clientByStem = gen.generateClientRequests(
      args.clientClass!,
      splitPerPath: args.splitPerPath,
    );
  }

  if (args.split) {
    final outDir = Directory(outPath);
    final written = gen.generateSplit(outDir);
    if (args.replacePatterns.isNotEmpty) {
      for (final f in written) {
        f.writeAsStringSync(
          _applyReplacePatterns(f.readAsStringSync(), args.replacePatterns),
        );
      }
    }
    stdout.writeln('Wrote ${written.length} files to $outPath');
    modelsImport = 'models.dart';
  } else {
    var src = gen.generateAll();
    src = _applyReplacePatterns(src, args.replacePatterns);
    final outFile = File(outPath);
    outFile.parent.createSync(recursive: true);
    outFile.writeAsStringSync(src);
    stdout.writeln(
      'Wrote $outPath (${src.length} bytes, ${gen.generated.length} types)',
    );
    modelsImport = outFile.uri.pathSegments.last;
  }
  print(clientByStem.length);
  if (args.clientClass != null) {
    var classCount = 0;
    for (final s in clientByStem.values) {
      classCount += RegExp(r'^class ', multiLine: true).allMatches(s).length;
    }

    // Optional client base stack (`--client-parent`): chain root + provider
    // base with generic REST buildRequest + request details. Emitted before
    // the per-method classes (prepended in single-file mode, `client_base.dart`
    // in split mode so per-stem files can import it).
    String? clientBaseSrc;
    String clientDetailsName = '';
    if (args.clientParent != null && args.clientParent!.isNotEmpty) {
      clientDetailsName =
          (args.clientDetails != null && args.clientDetails!.isNotEmpty)
          ? args.clientDetails!
          : '${args.clientClass}Details';
      clientBaseSrc = gen.generateClientBase(
        args.clientParent!,
        args.clientClass!,
        clientDetailsName,
      );
    }

    if (classCount == 0) {
      stdout.writeln(
        'No HTTP operations found in `paths` — no request classes generated.',
      );
    } else if (args.splitPerPath) {
      // Directory for per-path request files.
      Directory clientDir;
      if (args.clientOutput != null) {
        final co = args.clientOutput!;
        // Treat as directory when it has no .dart extension or ends with /
        clientDir = co.endsWith('.dart')
            ? Directory(File(co).parent.path)
            : Directory(co);
      } else if (args.split) {
        clientDir = Directory('$outPath/requests');
      } else {
        final outFile = File(outPath);
        clientDir = Directory('${outFile.parent.path}/requests');
      }
      clientDir.createSync(recursive: true);

      // Relative import path from requests/ back to models.
      String modelsImportFromRequests;
      if (args.split) {
        // models barrel is sibling of requests/
        modelsImportFromRequests = '../models.dart';
      } else {
        // models file is one level up
        modelsImportFromRequests = '../$modelsImport';
      }
      // If client-output was an explicit dir outside models, use the models
      // import as provided (caller may need a full package path via replace).
      if (args.clientOutput != null && !args.split) {
        modelsImportFromRequests = modelsImport;
      }

      final header = <String>['// GENERATED CODE - DO NOT MODIFY BY HAND', ''];
      header.add("import 'package:blockchain_utils/blockchain_utils.dart';");
      if (args.clientImport != null) {
        for (final imp in args.clientImport!.split(',')) {
          final uri = imp.trim();
          if (uri.isNotEmpty &&
              uri != 'package:blockchain_utils/blockchain_utils.dart') {
            header.add("import '$uri';");
          }
        }
      }
      final modelsImportForHeader =
          (args.clientModelsImport != null &&
              args.clientModelsImport!.isNotEmpty)
          ? args.clientModelsImport!
          : modelsImportFromRequests;
      header.add("import '$modelsImportForHeader';");
      if (gen.clientNeedsModelsImport) {
        // Some RESULT collides with its wrapper name (addressed as models.X).
        header.add("import '$modelsImportForHeader' as models;");
      }
      if (clientBaseSrc != null) {
        header.add("import 'client_base.dart';");
      }
      header.add('');

      final barrel = <String>['// GENERATED CODE - DO NOT MODIFY BY HAND', ''];
      final stems = clientByStem.keys.toList()..sort();
      var filesWritten = 0;
      if (clientBaseSrc != null) {
        final baseFile = File('${clientDir.path}/client_base.dart');
        baseFile.writeAsStringSync(
          '// GENERATED CODE - DO NOT MODIFY BY HAND\n'
          "import 'package:blockchain_utils/blockchain_utils.dart';\n\n"
          '$clientBaseSrc',
        );
        barrel.add("export 'client_base.dart';");
        filesWritten++;
      }
      for (final stem in stems) {
        var body = clientByStem[stem]!;
        if (body.isEmpty) continue;
        body = _applyReplacePatterns(body, args.replacePatterns);
        final fileStem = stem.isEmpty ? 'root' : stem;
        final outFile = File('${clientDir.path}/$fileStem.dart');
        outFile.writeAsStringSync('${header.join('\n')}$body');
        barrel.add("export '$fileStem.dart';");
        filesWritten++;
      }
      final barrelFile = File('${clientDir.path}/requests.dart');
      barrelFile.writeAsStringSync('${barrel.join('\n')}\n');
      stdout.writeln(
        'Wrote $filesWritten request files + barrel to ${clientDir.path} '
        '($classCount request classes)',
      );
    } else {
      // Single combined client file (original behaviour).
      var clientSrc = clientByStem.values.join('\n');
      if (clientBaseSrc != null) {
        clientSrc = '$clientBaseSrc\n$clientSrc';
      }
      clientSrc = _applyReplacePatterns(clientSrc, args.replacePatterns);
      File clientOutFile;
      if (args.clientOutput != null) {
        clientOutFile = File(args.clientOutput!);
      } else if (args.split) {
        clientOutFile = File('$outPath/requests.dart');
      } else {
        final outFile = File(outPath);
        final dir = outFile.parent.path;
        final base = outFile.uri.pathSegments.last;
        final dotIdx = base.lastIndexOf('.');
        final stem = dotIdx >= 0 ? base.substring(0, dotIdx) : base;
        final ext = dotIdx >= 0 ? base.substring(dotIdx) : '';
        clientOutFile = File('$dir/${stem}_requests$ext');
      }
      final header = <String>['// GENERATED CODE - DO NOT MODIFY BY HAND', ''];
      header.add("import 'package:blockchain_utils/blockchain_utils.dart';");
      if (args.clientImport != null) {
        for (final imp in args.clientImport!.split(',')) {
          final uri = imp.trim();
          if (uri.isNotEmpty &&
              uri != 'package:blockchain_utils/blockchain_utils.dart') {
            header.add("import '$uri';");
          }
        }
      }
      header.add("import '$modelsImport';");
      if (gen.clientNeedsModelsImport) {
        // Some RESULT collides with its wrapper name (addressed as models.X).
        header.add("import '$modelsImport' as models;");
      }
      header.add('');
      clientOutFile.parent.createSync(recursive: true);
      var outSrc = '${header.join('\n')}$clientSrc';
      if (args.clientModelsImport != null &&
          args.clientModelsImport!.isNotEmpty) {
        outSrc = outSrc.replaceFirst(
          "import '$modelsImport';",
          "import '${args.clientModelsImport}';",
        );
      }
      clientOutFile.writeAsStringSync(outSrc);
      stdout.writeln(
        'Wrote ${clientOutFile.path} ($classCount request classes)',
      );
    }
  }
}
