import 'dart:io' show IOException;

class ProtocolException extends IOException {
  ProtocolException(this.message) : super();

  final String message;

  @override
  String toString() => 'ProtocolException: $message';
}
