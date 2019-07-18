import 'dart:async' show Completer, StreamSubscription;
import 'dart:collection' show Queue;

import 'package:redis/resp.dart' show ArrayReply, Reply, ReplyKind;

import 'package:redis/src/connection.dart';
import 'package:redis/src/context_provider.dart';
import 'package:redis/src/runner.dart';
import 'package:redis/src/utils.dart';
import 'package:redis/src/transaction.dart';
import 'package:redis/src/raw_connection.dart';

class ConnectionImpl extends Runner with ContextProvider implements Connection {
  ConnectionImpl(this._cnx, this.config)
      : _tasks = Queue(),
        isTransacting = false {
    _subscription = _cnx.replies.listen(_onReply);
  }

  final RawConnection _cnx;
  final Queue<Completer> _tasks;
  StreamSubscription<Reply> _subscription;

  @override
  bool isTransacting;

  final ConnectionConfig config;

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

  Future<void> _quit() => run([r'QUIT']);

  Future<void> auth(String password) {
    ArgumentError.checkNotNull(password);

    return run([r'AUTH', password]);
  }

  Future<T> execute<T>(List<String> args) {
    final task = Completer<T>();

    _cnx.send(convertToRespLine(args));
    _tasks.add(task);

    return task.future;
  }

  @override
  Future<T> run<T>(List<String> args) {
    if (isTransacting) {
      throw StateError('Unable to execute a command directly on the connection '
          'while it is in transaction mode, use appropreated Transaction object '
          'to execute commands instead!');
    }

    return execute(args);
  }

  @override
  Future<String> echo(String message) => run([r'ECHO', message]);

  @override
  Future<String> ping([String message]) =>
      run([r'PING', if (message != null) message]);

  @override
  Future<void> select(int db) => run([r'SELECT', db.toString()]);

  /// Returns this connection back to the connection pool of the owner client.
  Future<void> close({bool force = false}) async {
    await _quit();
    await _cnx.close(force);
  }

  /// Marks the start of a transaction block.
  Future<Transaction> multi() async {
    final ok = isOk(await execute<String>([r'MULTI']));
    isTransacting = true;

    if (!ok) {
      throw Exception('Malformed data!');
    }

    return Transaction(this, () => isTransacting = false);
  }
}
