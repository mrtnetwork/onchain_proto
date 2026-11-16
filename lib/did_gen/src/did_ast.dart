sealed class DidType {
  const DidType();
}

final class DidPrimitive extends DidType {
  final String name;
  const DidPrimitive(this.name);
}

final class DidOpt extends DidType {
  final DidType inner;
  const DidOpt(this.inner);
}

final class DidVec extends DidType {
  final DidType inner;
  const DidVec(this.inner);
}

final class DidNamed extends DidType {
  final String name;
  const DidNamed(this.name);
}

final class DidRecord extends DidType {
  final List<DidField> fields;
  const DidRecord(this.fields);
}

final class DidVariant extends DidType {
  final List<DidField> fields;
  const DidVariant(this.fields);
}

final class DidFunc extends DidType {
  const DidFunc();
}

final class DidServiceType extends DidType {
  const DidServiceType();
}

final class DidField {
  final String name;
  final DidType? type;
  const DidField(this.name, this.type);
}

final class DidTypeDef {
  final String name;
  final DidType type;
  final String? comment;
  const DidTypeDef(this.name, this.type, {this.comment});
}

/// One method inside a `service { ... }` block.
final class DidMethod {
  final String name;
  final List<DidType> args;
  final List<DidType> rets;
  final bool isQuery;
  final bool isOneway;
  final bool isCompositeQuery;

  const DidMethod({
    required this.name,
    required this.args,
    required this.rets,
    this.isQuery = false,
    this.isOneway = false,
    this.isCompositeQuery = false,
  });

  bool get isUpdate => !isQuery && !isCompositeQuery && !isOneway;
}

final class DidService {
  final String? name;
  final List<DidMethod> methods;
  const DidService({this.name, required this.methods});
}

final class DidFile {
  final List<DidTypeDef> types;
  final List<DidService> services;
  const DidFile(this.types, {this.services = const []});
}
