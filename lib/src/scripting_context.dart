import 'package:redis/src/executor.dart';
import 'package:redis/src/utils.dart';

class _Command {
  static const String eval = r'EVAL';
  static const String evalsha = r'EVALSHA';
  static const String exists = r'SCRIPT EXISTS';
  static const String debug = r'SCRIPT DEBUG';
  static const String flush = r'SCRIPT FLUSH';
  static const String load = r'SCRIPT LOAD';
}

class ScriptDebugMode {
  const ScriptDebugMode._(this.value);

  final String value;

  /// Debug mode for non-blocking asynchronous debugging for Lua scripts.
  static const ScriptDebugMode yes = ScriptDebugMode._('YES');

  /// Debug mode for blocking synchronous debugging of Lua scripts.
  static const ScriptDebugMode sync = ScriptDebugMode._('SYNC');

  /// Debug mode used to disable debugging of Lua scripts.
  static const ScriptDebugMode no = ScriptDebugMode._('NO');
}

/// See: http://redis.io/commands#scripting
class ScriptingContext {
  ScriptingContext(this._executor);

  final Executor _executor;

  /// Evaluates Lua [script] on the server-side.
  ///
  /// See: https://redis.io/commands/eval
  Future<void> eval(
          String script, Iterable<String> keys, Iterable<String> args) =>
      _executor
          .exec([r'EVAL', script, keys.length.toString(), ...keys, ...args]);

  /// Evaluates a script cached on the server-side by its [hash] SHA1 digest.
  ///
  /// See: https://redis.io/commands/evalsha
  Future evalsha(String hash, Iterable<String> keys, Iterable<String> args) =>
      _executor
          .exec<int>([r'EVALSHA', keys.length.toString(), ...keys, ...args]);

  /// Set the debug [mode] for subsequent scripts executed with [eval].
  ///
  /// See: https://redis.io/commands/script-debug
  Future<void> debug(ScriptDebugMode mode) async =>
      isOk(await _executor.exec<String>([r'SCRIPT', r'DEBUG', mode.value]));

  /// Returns information about the existence of the scripts in the script
  /// cache.
  ///
  /// Returns a list of booleans that corresponds to specified [hashes]. For
  /// every corresponding SHA1 digest of a script that actually exists in
  /// the script cache `true` is returned, otherwise `false` is returned.
  ///
  /// See: https://redis.io/commands/script-exists
  Future<List<bool>> exists(Iterable<String> hashes) async {
    assert(hashes != null && hashes.isNotEmpty);

    final raw =
        await _executor.exec<List<int>>([r'SCRIPT', r'EXISTS', ...hashes]);
    final result = [for (final r in raw) r == 1];

    return result;
  }

  Future<void> flush() => _executor.exec([r'SCRIPT', r'FLUSH']);

  Future<void> load() => _executor.exec([r'SCRIPT', r'LOAD']);
}
