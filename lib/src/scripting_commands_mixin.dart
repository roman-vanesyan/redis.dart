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
mixin ScriptingCommandsMixin on Executor {
  /// Evaluates Lua [script] on the server-side.
  ///
  /// See: https://redis.io/commands/eval
  Future<void> eval(
          String script, Iterable<String> keys, Iterable<String> args) =>
      exec(_Command.eval, [script, keys.length.toString(), ...keys, ...args]);

  /// Evaluates a script cached on the server-side by its [hash] SHA1 digest.
  ///
  /// See: https://redis.io/commands/evalsha
  Future evalsha(String hash, Iterable<String> keys, Iterable<String> args) =>
      exec<int>(_Command.evalsha, [keys.length.toString(), ...keys, ...args]);

  /// Set the debug mode for subsequent scripts executed with [eval].
  ///
  /// See: https://redis.io/commands/script-debug
  Future<void> scriptDebug(ScriptDebugMode mode) async =>
      isOk(await exec<String>(_Command.debug, [mode.value]));

  /// Returns information about the existence of the scripts in the script
  /// cache.
  ///
  /// Returns a list of booleans that corresponds to specified [hashes]. For
  /// every corresponding SHA1 digest of a script that actually exists in
  /// the script cache `true` is returned, otherwise `false` is returned.
  ///
  /// See: https://redis.io/commands/script-exists
  Future<List<bool>> scriptExists(Iterable<String> hashes) async {
    assert(hashes != null && hashes.isNotEmpty);

    final raw = await exec<List<int>>(_Command.exists, <String>[...hashes]);
    final result = [for (final r in raw) r == 1];

    return result;
  }

  Future<void> scriptFlush() => exec(_Command.flush);

  Future<void> scriptLoad() => exec(_Command.load);
}
