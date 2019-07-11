import 'dart:async' show Completer;
import 'dart:async';
import 'dart:collection' show Queue;
import 'dart:io' show SecurityContext;

import 'package:meta/meta.dart' show immutable;
import 'package:jetlog/jetlog.dart' as log;
import 'package:redis/resp.dart' show ArrayReply, Reply, ReplyKind;
import 'package:redis/src/context_provider.dart';

import 'package:redis/src/executor.dart';
import 'package:redis/src/utils.dart';
import 'package:redis/src/raw_connection.dart';

class _Command {
  static const String auth = r'AUTH';
  static const String echo = r'ECHO';
  static const String ping = r'PING';
  static const String quit = r'QUIT';
  static const String select = r'SELECT';
  static const String swapdb = r'SWAPDB';
}

@immutable
class ConnectionConfig implements log.Loggable {
  const ConnectionConfig(
      {this.password, this.isTlsEnabled = false, this.securityContext});

  /// Optional password to use when connecting to the database.
  final String password;

  /// Indicates if connection should be upgraded to serve over TLS.
  final bool isTlsEnabled;

  /// Optional security context socket should use when upgrading connection
  /// to serve over TLS.
  final SecurityContext securityContext;

  @override
  Iterable<log.Field> toFields() => {
        log.Bool('isTlsEnabled', isTlsEnabled),
      };
}

/// Connections is a single connection from the connection [Pool].
class Connection extends Executor with ContextProvider {
  Connection._(this._cnx, this.config) : _tasks = Queue() {
    _subscription = _cnx.replies.listen(_onReply);
  }

  final RawConnection _cnx;
  final Queue<Completer> _tasks;
  StreamSubscription<Reply> _subscription;

  /// This connection configurations.
  final ConnectionConfig config;

  static Future<Connection> connect(dynamic host,
      {int port = 6379, ConnectionConfig config}) async {
    final raw = await RawConnection.connect(
      host,
      port,
      isTlsEnabled: config.isTlsEnabled,
      context: config.securityContext,
    );

    final cnx = Connection._(raw, config);

    if (config.password != null) {
      await cnx._auth(config.password);
    }

    return cnx;
  }

  void _onReply(Reply reply) {
    final task = _tasks.removeFirst();

    switch (reply.kind) {
      case ReplyKind.error:
        task.completeError(Exception(reply.value));
        break;

      case ReplyKind.array:
        task.complete(unwrapArrayReply(reply as ArrayReply));
        break;

      default:
        task.complete(reply.value);
        break;
    }
  }

  Future<void> _quit() => exec(_Command.quit);

  Future<void> _auth(String password) {
    ArgumentError.checkNotNull(password);

    return exec(_Command.auth, [password]);
  }

  @override
  Future<T> exec<T>(String command, [List<String> args]) {
    final task = Completer<T>();

    _cnx.send(convertToRespLine([command, if (args != null) ...args]));
    _tasks.add(task);

    return task.future;
  }

  Future<String> echo(String message) => exec(_Command.echo, [message]);

  Future<String> ping([String message]) =>
      exec(_Command.ping, [if (message != null) message]);

  Future<void> select(int db) => exec(_Command.select, [db.toString()]);

  /// Returns this connection back to the connection pool of the owner client.
  Future<void> close({bool force = false}) async {
    await _quit();
    await _cnx.close(force);
  }
}
