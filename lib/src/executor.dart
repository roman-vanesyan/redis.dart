/// Executor used to send commands to the Redis server.
abstract class Executor {
  /// Sends a command to Redis server and receives result of type [T].
  ///
  /// Each enclosing argument must be stringify before put into the arguments
  /// list.
  ///
  /// ```dart
  /// await cnx.exec<String>([r'GET', 'key']);
  /// ```
  Future<T> exec<T>(List<String> args);
}
