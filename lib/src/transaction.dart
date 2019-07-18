import 'dart:async' show Completer, FutureOr;
import 'dart:collection' show Queue;

import 'package:redis/src/context_provider.dart';
import 'package:redis/src/runner.dart';
import 'package:redis/src/connection_impl.dart';
import 'package:redis/src/utils.dart';

abstract class TransactionExecutor {
  /// Marks the start of a transaction block.
  Future<Transaction> multi();
}

class Transaction extends Runner with ContextProvider {
  Transaction(this._cnx, [this._onFinalize]) : _tasks = Queue();

  final ConnectionImpl _cnx;
  final FutureOr<void> Function() _onFinalize;
  final Queue<Completer> _tasks;

  /// Executes all previously queued commands in this transaction and restores
  /// the connection state to normal.
  Future<void> exec() async {
    final results = await _cnx.execute<List>([r'EXEC']);

    if (results.length != _tasks.length) {
      throw Exception('Malformed return!');
    }

    results.forEach((dynamic result) {
      _tasks.removeFirst().complete(result);
    });

    if (_onFinalize != null) {
      await _onFinalize();
    }
  }

  /// Releases all previously queued commands in this transaction and restores
  /// the connection state to normal. Any previously watched keys are unwatched.
  Future<bool> discard() async => isOk(await _cnx.execute([r'DISCARD']));

  @override
  Future<T> run<T>(List<String> args) async {
    final task = Completer<T>();

    await _cnx.execute<void>(args); // => 'QUEUED'
    _tasks.add(task);

    return task.future;
  }
}
