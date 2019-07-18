/// Runner used to send commands to the Redis server.
abstract class Runner {
  /// Sends a command to Redis server and receives result of type [T].
  ///
  /// Each enclosing argument must be stringify before put into the arguments
  /// list.
  Future<T> run<T>(List<String> args);
}
