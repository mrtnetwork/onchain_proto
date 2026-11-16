import 'package:blockchain_utils/helper/extensions/extensions.dart';
import 'package:onchain_proto/proto/types/types.dart';

extension ExtTypeLocation on ProtoTypeLocation {
  String importDirective() {
    return '"$importPath" as $alias';
  }

  String qualifyType(String identifier, ProtoType type) {
    if (type case ProtoMessageRefrence()) {
      if (type.fullTypeName() == name && type.package == packageName) {
        return '$alias.$identifier';
      }
    }
    return identifier;
  }
}

extension GetRefrenceTypesImport on Iterable<ProtoTypeLocation> {
  String qualifyType(String typeString, ProtoType type) {
    if (type case ProtoMessageRefrence()) {
      final t = firstWhereNullable(
        (e) => e.name == type.fullTypeName() && e.packageName == type.package,
      );
      final import = t?.qualifyType(typeString, type) ?? typeString;
      return import;
    }
    return typeString;
  }
}
