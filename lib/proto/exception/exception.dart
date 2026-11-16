class OnChainProtoException implements Exception {
  final String message;
  const OnChainProtoException(this.message);
  @override
  String toString() {
    return "OnChainProtoException($message)";
  }
}
