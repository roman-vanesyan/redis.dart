import 'dart:io' show IOException;

/// [ClosedConnectionException] is thrown when performing any operations on
/// closed connection.
class ClosedConnectionException extends IOException {
  ClosedConnectionException(this.message);

  final String message;

  @override
  String toString() => "ClosedConnectionException: $message";
}

/// [ClosedConnectionPoolException] is thrown when performing any operations on
/// a closed [Pool].
class ClosedConnectionPoolException extends IOException {
  ClosedConnectionPoolException(this.message);

  final String message;

  @override
  String toString() => "ClosedConnectionPoolException: $message";
}

class ConnectionException extends IOException {
  ConnectionException(this.message);

  final String message;

  @override
  String toString() => 'ConnectionException: $message';
}
