import 'package:onchain_proto/src/exception/exception.dart';
import 'package:onchain_proto/src/types/types.dart';

abstract class TypeResolver {
  /// detect if is package just accept full path
  /// example:
  /// cosmos.crypto.hd.v1;
  bool isPackage(String fullPackagePath);

  /// All known package full-names, e.g. {"cosmos.crypto.hd.v1", ...}.
  /// Used to enumerate candidates for the global fallback search.
  Iterable<String> get allPackageNames;

  /// All type paths declared directly inside [fullPackagePath], relative
  /// to that package (legacy/cheap symbol table — top-level names as-is,
  /// nested as "TypeA.B"). Kept as a fallback alongside
  /// [getPackageDeclaration] in case the richer declarations aren't
  /// available for some package.
  Set<String> types(String fullPackagePath);

  /// Every declaration (message/enum) in [fullPackagePath], flattened —
  /// both top-level AND nested declarations, each with its own [parent]
  /// pointer set when nested (null for top-level). This is the real
  /// symbol table: [ProtoDeclaration.fullName] gives each
  /// declaration's full dotted path within the package (e.g.
  /// "SignatureDescriptor.Data"), and [parent] lets the resolver walk
  /// the actual nesting tree to implement proto's enclosing-message
  /// scoping rules.
  List<ProtoDeclaration> getPackageDeclaration(String fullPackagePath);

  ProtoMessageRefrence resolveTypeRefrence({
    /// the current file full package name
    /// when we parse this typeName
    required String origin,

    /// The message you are currently parsing fields/options inside, if
    /// any. Pass this whenever typeName is referenced from inside a
    /// nested context — e.g. while parsing the fields of
    /// `message SignatureDescriptor { Data data = 2; ... }`, pass the
    /// SignatureDescriptor declaration here so "Data" resolves against
    /// SignatureDescriptor's own nested scope first (proto's C++-style
    /// scoping checks the enclosing message before the package). Leave
    /// null when parsing top-level message/enum/service fields directly.
    required ProtoDeclaration? enclosingMessage,

    /// exactly field name we parsed in message
    /// e.g. "Params"
    /// e.g. "google.protobuf.Any"
    /// e.g. ".google.protobuf.Any",
    /// e.g. "protobuf.Any.B"
    required String typeName,
  }) {
    final bool isAbsolute = typeName.startsWith('.');
    final String raw = isAbsolute ? typeName.substring(1) : typeName;

    if (raw.isEmpty) {
      throw OnChainProtoException(
        'typeName must not be empty (got "$typeName")',
      );
    }

    final List<String> segments = raw.split('.');

    final _Split resolved = isAbsolute
        ? _resolveAbsolute(segments)
        : _resolveRelative(origin, segments, enclosingMessage);

    final String typeNameOnly = resolved.rest.last;
    final String? nestedName = resolved.rest.length > 1
        ? resolved.rest.join('.')
        : null;

    return ProtoMessageRefrence(
      fullName: typeName,
      typeName: typeNameOnly,
      package: resolved.package,
      nestedName: nestedName,
    );
  }

  // ---------------------------------------------------------------------
  // Absolute resolution (leading dot, e.g. ".google.protobuf.Any")
  // ---------------------------------------------------------------------

  _Split _resolveAbsolute(List<String> segments) {
    // Absolute references are never affected by enclosing-message scope
    // (a leading dot always means "search from the global/package root"),
    // so this is unchanged from before.
    final _Split? verified = _splitVerifiedByDeclarations(<String>[], segments);
    if (verified != null) return verified;

    final _Split? verifiedLegacy = _splitVerifiedByTypes(<String>[], segments);
    if (verifiedLegacy != null) return verifiedLegacy;

    final _Split byPackage = _splitByLongestPackagePrefix(segments);
    if (byPackage.package.isNotEmpty) return byPackage;

    final _Split? globalMatch = _findPackageBySuffix(segments);
    if (globalMatch != null) return globalMatch;

    return _Split(
      segments.length > 1
          ? segments.sublist(0, segments.length - 1).join('.')
          : '',
      <String>[segments.last],
    );
  }

  // ---------------------------------------------------------------------
  // Relative resolution (no leading dot)
  // ---------------------------------------------------------------------

  _Split _resolveRelative(
    String origin,
    List<String> segments,
    ProtoDeclaration? enclosingMessage,
  ) {
    // Step -1 (new): if we're currently inside a message, search that
    // message's own nesting scope first — innermost enclosing message
    // outward to the top-level message, all within `origin`. This is
    // what makes "Data" referenced inside `SignatureDescriptor` resolve
    // to the nested "SignatureDescriptor.Data" instead of falling
    // through to "no such top-level type, default to bare name in
    // origin package". Mirrors real proto C++ scoping, which checks
    // enclosing message scopes before package-level / ancestor scopes.
    if (enclosingMessage != null) {
      final _Split? inEnclosing = _searchEnclosingMessageScopes(
        origin,
        segments,
        enclosingMessage,
      );
      if (inEnclosing != null) return inEnclosing;
    }

    // Step 0: does origin itself directly declare this type (or nested
    // path), checked via the rich declaration list first, then the
    // legacy types() set.
    final _Split? inOriginDecl = _verifyTypeInPackageByDeclarations(
      origin,
      segments,
    );
    if (inOriginDecl != null) return inOriginDecl;
    final _Split? inOrigin = _verifyTypeInPackage(origin, segments);
    if (inOrigin != null) return inOrigin;

    // Step 1: try the relative name's own leading segments as a package,
    // with no origin prefix.
    final _Split? standaloneDecl = _splitVerifiedByDeclarations(
      <String>[],
      segments,
    );
    if (standaloneDecl != null) return standaloneDecl;
    final _Split? standalone = _splitVerifiedByTypes(<String>[], segments);
    if (standalone != null) return standalone;

    // Step 2: climb the origin scope outward (innermost ancestor to
    // global), prepending each ancestor scope to the relative name.
    for (final scope in _scopesFromOrigin(origin)) {
      if (scope.isEmpty) continue;
      if (scope == origin) continue; // already checked in step 0
      final _Split? declSplit = _splitVerifiedByDeclarations(
        scope.split('.'),
        segments,
      );
      if (declSplit != null) return declSplit;
      final _Split? split = _splitVerifiedByTypes(scope.split('.'), segments);
      if (split != null) return split;
    }

    // Step 3: maybe the relative name just redundantly restates the tail
    // of origin itself, e.g. "hd.v1.BIP44Params" from inside
    // "cosmos.crypto.hd.v1" really means plain "BIP44Params" in that
    // same package.
    final int overlap = _originTailOverlap(origin, segments);
    if (overlap > 0) {
      final List<String> candidateRest = segments.sublist(overlap);
      if (candidateRest.isNotEmpty) {
        final String candidateTypePath = candidateRest.join('.');
        if (_packageDeclares(origin, candidateTypePath) ||
            types(origin).contains(candidateTypePath)) {
          return _Split(origin, candidateRest);
        }
      }
    }

    // Step 4: global search across every known package's declarations.
    final _Split? globalDecl = _findPackageByDeclarationGlobally(segments);
    if (globalDecl != null) return globalDecl;
    final _Split? global = _findPackageByTypeGlobally(segments);
    if (global != null) return global;

    // Step 5: legacy isPackage-pattern fallback.
    final _Split? foundByName = _splitByNamePatternOnly(origin, segments);
    if (foundByName != null) return foundByName;

    // Step 6: absolute last resort.
    return _Split(origin, segments);
  }

  // ---------------------------------------------------------------------
  // Enclosing-message scope walk (new)
  // ---------------------------------------------------------------------

  /// Walks the enclosing-message chain starting at [enclosingMessage]
  /// (innermost) outward through each [ProtoDeclaration.parent] up
  /// to the top-level message (parent == null), and at each level
  /// checks whether that level's own type path combined with a leading
  /// run of [segments] matches a declared nested type in [origin]. This
  /// finds things like "Data" resolving to "SignatureDescriptor.Data"
  /// when called from inside SignatureDescriptor, and also "Single"
  /// resolving to "SignatureDescriptor.Data.Single" when called from
  /// inside the nested Data message itself.
  _Split? _searchEnclosingMessageScopes(
    String origin,
    List<String> segments,
    ProtoDeclaration enclosingMessage,
  ) {
    final List<ProtoDeclaration> declared = getPackageDeclaration(origin);
    if (declared.isEmpty) return null;

    final List<String> scopeChain = <String>[];
    ProtoDeclaration? current = enclosingMessage;
    while (current != null) {
      scopeChain.add(current.fullName());
      current = current.parent;
    }

    for (final scopePath in scopeChain) {
      for (int len = segments.length; len >= 1; len--) {
        final String candidateRest = segments.sublist(0, len).join('.');
        final String candidateFullPath = '$scopePath.$candidateRest';
        for (final decl in declared) {
          if (decl.fullName() == candidateFullPath) {
            // FIX: use the declaration's own fullName split into segments
            // instead of duplicating scopePath + segments
            final List<String> fullRest = candidateFullPath.split('.');
            return _Split(origin, fullRest);
          }
        }
      }
    }
    return null;
  }

  bool _packageDeclares(String package, String typePath) {
    final List<ProtoDeclaration> declared = getPackageDeclaration(package);
    for (final decl in declared) {
      if (decl.fullName() == typePath) return true;
    }
    return false;
  }

  /// Checks whether [package] directly declares the type path formed by
  /// a leading run of [segments] (longest possible run first).
  _Split? _verifyTypeInPackageByDeclarations(
    String package,
    List<String> segments,
  ) {
    final List<ProtoDeclaration> declared = getPackageDeclaration(package);
    if (declared.isEmpty) return null;
    for (int len = segments.length; len >= 1; len--) {
      final String candidate = segments.sublist(0, len).join('.');
      for (final decl in declared) {
        if (decl.fullName() == candidate) {
          return _Split(package, segments.sublist(0, len));
        }
      }
    }
    return null;
  }

  /// Tries "scopeParts + segments[0..n]" as a package (n from longest
  /// down to requiring at least 1 leftover segment), and for each
  /// candidate package, verifies via [getPackageDeclaration] that it
  /// actually declares the remaining segments as a type path.
  _Split? _splitVerifiedByDeclarations(
    List<String> scopeParts,
    List<String> segments,
  ) {
    final int maxExtra = segments.length - 1;
    for (int extra = maxExtra; extra >= 0; extra--) {
      final List<String> candidateParts = <String>[
        ...scopeParts,
        ...segments.sublist(0, extra),
      ];
      if (candidateParts.isEmpty) continue;
      final String candidatePackage = candidateParts.join('.');
      final List<String> rest = segments.sublist(extra);
      if (rest.isEmpty) continue;
      final List<ProtoDeclaration> declared = getPackageDeclaration(
        candidatePackage,
      );
      if (declared.isEmpty) continue;
      for (int restLen = rest.length; restLen >= 1; restLen--) {
        final String candidateType = rest.sublist(0, restLen).join('.');
        for (final decl in declared) {
          if (decl.fullName() == candidateType) {
            return _Split(candidatePackage, rest.sublist(0, restLen));
          }
        }
      }
    }
    return null;
  }

  /// Global search across every known package's declarations, by
  /// trailing run of [segments] (longest run treated as the type first).
  _Split? _findPackageByDeclarationGlobally(List<String> segments) {
    for (int len = segments.length; len >= 1; len--) {
      final List<String> typeSegs = segments.sublist(segments.length - len);
      final String candidateType = typeSegs.join('.');
      final List<String> leftover = segments.sublist(0, segments.length - len);

      String? bestPackage;
      bool bestPackageNameMatches = false;

      for (final pkg in allPackageNames) {
        final List<ProtoDeclaration> declared = getPackageDeclaration(pkg);
        final bool has = declared.any((d) => d.fullName() == candidateType);
        if (!has) continue;

        final List<String> pkgParts = pkg.split('.');
        final bool nameMatches =
            leftover.isEmpty || _endsWith(pkgParts, leftover);

        if (bestPackage == null) {
          bestPackage = pkg;
          bestPackageNameMatches = nameMatches;
        } else if (nameMatches && !bestPackageNameMatches) {
          bestPackage = pkg;
          bestPackageNameMatches = true;
        } else if (nameMatches == bestPackageNameMatches &&
            pkg.length < bestPackage.length) {
          bestPackage = pkg;
        }
      }

      if (bestPackage != null) {
        return _Split(bestPackage, typeSegs);
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // Legacy types()-set helpers (kept as fallback for packages where the
  // richer declaration list isn't populated).
  // ---------------------------------------------------------------------

  _Split? _verifyTypeInPackage(String package, List<String> segments) {
    final Set<String> declared = types(package);
    if (declared.isEmpty) return null;
    for (int len = segments.length; len >= 1; len--) {
      final String candidate = segments.sublist(0, len).join('.');
      if (declared.contains(candidate)) {
        return _Split(package, segments.sublist(0, len));
      }
    }
    return null;
  }

  _Split? _splitVerifiedByTypes(
    List<String> scopeParts,
    List<String> segments,
  ) {
    final int maxExtra = segments.length - 1;
    for (int extra = maxExtra; extra >= 0; extra--) {
      final List<String> candidateParts = <String>[
        ...scopeParts,
        ...segments.sublist(0, extra),
      ];
      if (candidateParts.isEmpty) continue;
      final String candidatePackage = candidateParts.join('.');
      final List<String> rest = segments.sublist(extra);
      if (rest.isEmpty) continue;
      final Set<String> declared = types(candidatePackage);
      if (declared.isEmpty) continue;
      for (int restLen = rest.length; restLen >= 1; restLen--) {
        final String candidateType = rest.sublist(0, restLen).join('.');
        if (declared.contains(candidateType)) {
          return _Split(candidatePackage, rest.sublist(0, restLen));
        }
      }
    }
    return null;
  }

  _Split? _findPackageByTypeGlobally(List<String> segments) {
    for (int len = segments.length; len >= 1; len--) {
      final List<String> typeSegs = segments.sublist(segments.length - len);
      final String candidateType = typeSegs.join('.');
      final List<String> leftover = segments.sublist(0, segments.length - len);

      String? bestPackage;
      bool bestPackageNameMatches = false;

      for (final pkg in allPackageNames) {
        if (!types(pkg).contains(candidateType)) continue;

        final List<String> pkgParts = pkg.split('.');
        final bool nameMatches =
            leftover.isEmpty || _endsWith(pkgParts, leftover);

        if (bestPackage == null) {
          bestPackage = pkg;
          bestPackageNameMatches = nameMatches;
        } else if (nameMatches && !bestPackageNameMatches) {
          bestPackage = pkg;
          bestPackageNameMatches = true;
        } else if (nameMatches == bestPackageNameMatches &&
            pkg.length < bestPackage.length) {
          bestPackage = pkg;
        }
      }

      if (bestPackage != null) {
        return _Split(bestPackage, typeSegs);
      }
    }
    return null;
  }

  bool _endsWith(List<String> pkgParts, List<String> tail) {
    if (pkgParts.length < tail.length) return false;
    final List<String> pkgTail = pkgParts.sublist(
      pkgParts.length - tail.length,
    );
    for (int i = 0; i < tail.length; i++) {
      if (pkgTail[i] != tail[i]) return false;
    }
    return true;
  }

  // ---------------------------------------------------------------------
  // Legacy name-pattern-only helpers (isPackage-based, no symbol table
  // at all). Used only as a last-resort fallback.
  // ---------------------------------------------------------------------

  _Split? _splitByNamePatternOnly(String origin, List<String> segments) {
    _Split? found = _tryPackagePrefix(<String>[], segments);

    if (found == null) {
      for (final scope in _scopesFromOrigin(origin)) {
        if (scope.isEmpty) continue;
        final _Split? split = _tryPackagePrefix(
          scope.split('.'),
          segments,
          requireAtLeastOneExtraSegment: true,
        );
        if (split != null) {
          found = split;
          break;
        }
      }
    }

    if (found != null) return found;

    final int overlap = _originTailOverlap(origin, segments);
    if (overlap > 0) {
      final List<String> rest = segments.sublist(overlap);
      return _Split(origin, rest.isEmpty ? <String>[segments.last] : rest);
    }

    return _findPackageBySuffix(segments);
  }

  _Split _splitByLongestPackagePrefix(List<String> segments) {
    final int maxPackageLen = segments.length - 1;
    for (int len = maxPackageLen; len >= 1; len--) {
      final String candidate = segments.sublist(0, len).join('.');
      if (isPackage(candidate)) {
        return _Split(candidate, segments.sublist(len));
      }
    }
    return _Split('', segments);
  }

  _Split? _tryPackagePrefix(
    List<String> scopeParts,
    List<String> segments, {
    bool requireAtLeastOneExtraSegment = false,
  }) {
    final int maxExtra = segments.length - 1;
    final int minExtra = requireAtLeastOneExtraSegment ? 1 : 0;
    for (int extra = maxExtra; extra >= minExtra; extra--) {
      final List<String> candidateParts = <String>[
        ...scopeParts,
        ...segments.sublist(0, extra),
      ];
      if (candidateParts.isEmpty) continue;
      final String candidate = candidateParts.join('.');
      if (isPackage(candidate)) {
        return _Split(candidate, segments.sublist(extra));
      }
    }
    return null;
  }

  int _originTailOverlap(String origin, List<String> segments) {
    if (origin.isEmpty) return 0;
    final List<String> originParts = origin.split('.');
    final int maxLen = segments.length - 1;
    final int cap = maxLen < originParts.length ? maxLen : originParts.length;
    for (int len = cap; len >= 1; len--) {
      final List<String> originTail = originParts.sublist(
        originParts.length - len,
      );
      final List<String> segHead = segments.sublist(0, len);
      bool matches = true;
      for (int i = 0; i < len; i++) {
        if (originTail[i] != segHead[i]) {
          matches = false;
          break;
        }
      }
      if (matches) return len;
    }
    return 0;
  }

  _Split? _findPackageBySuffix(List<String> segments) {
    final int maxLen = segments.length - 1;
    if (maxLen < 1) return null;

    for (int len = maxLen; len >= 1; len--) {
      final List<String> segHead = segments.sublist(0, len);
      String? bestPackage;

      for (final pkg in allPackageNames) {
        final List<String> pkgParts = pkg.split('.');
        if (pkgParts.length < len) continue;
        final List<String> pkgTail = pkgParts.sublist(pkgParts.length - len);
        bool matches = true;
        for (int i = 0; i < len; i++) {
          if (pkgTail[i] != segHead[i]) {
            matches = false;
            break;
          }
        }
        if (!matches) continue;
        if (bestPackage == null || pkg.length < bestPackage.length) {
          bestPackage = pkg;
        }
      }

      if (bestPackage != null) {
        return _Split(bestPackage, segments.sublist(len));
      }
    }
    return null;
  }

  List<String> _scopesFromOrigin(String origin) {
    if (origin.isEmpty) return <String>[''];
    final List<String> parts = origin.split('.');
    final List<String> scopes = <String>[];
    for (int i = parts.length; i >= 1; i--) {
      scopes.add(parts.sublist(0, i).join('.'));
    }
    scopes.add('');
    return scopes;
  }
}

class _Split {
  final String package;
  final List<String> rest;
  _Split(this.package, this.rest);
}
