// GENERATED CODE - DO NOT MODIFY BY HAND

import 'package:blockchain_utils/blockchain_utils.dart';

/// Shared helpers for generated Candid types (principal parse, etc.).
abstract final class GeneratorParserUtils {
  /// Convert a decoded Candid principal value to [IcpPrincipalAddress].
  static IcpPrincipalAddress principalFromCandid(dynamic e) {
    if (e is IcpPrincipalAddress) return e;
    if (e is String) return IcpPrincipalAddress(e);
    if (e is List<int>) return IcpPrincipalAddress.fromBytes(e);
    try {
      final b = (e as dynamic).bytes;
      if (b is List<int>) return IcpPrincipalAddress.fromBytes(b);
    } catch (_) {}
    throw ArgumentException.invalidOperationArguments(
      'GeneratorParserUtils.principalFromCandid',
      reason: 'Expected principal, got ${e.runtimeType}',
    );
  }
}
