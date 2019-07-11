import 'dart:async';
import 'dart:collection';
import 'dart:io' show SecurityContext;
import 'dart:io';

import 'package:meta/meta.dart' show immutable;
import 'package:jetlog/jetlog.dart' as log;

import 'package:redis/src/connection.dart';
import 'package:redis/src/exceptions.dart';
import 'package:redis/src/executor.dart';
import 'package:redis/src/pubsub_commands_mixin.dart';
import 'package:redis/src/scripting_commands_mixin.dart';
import 'package:redis/src/server_commands_mixin.dart';
import 'package:redis/src/string_commands_mixin.dart';

final log.Logger logger = log.Logger.getLogger('redis.Pool');

/// [PoolConfig] is used to configure a [Pool].
@immutable
class PoolConfig extends ConnectionConfig implements log.Loggable {
  const PoolConfig({
    this.maxConns = 5,
    this.maxRetries = 3,
    this.db = 0,
    String password,
    bool isTlsEnabled = false,
    SecurityContext securityContext,
  }) : super(
          password: password,
          isTlsEnabled: isTlsEnabled,
          securityContext: securityContext,
        );

  /// Database this client should connect to.
  final int db;

  /// Maximum number of connections the connection pool is allowed to own.
  final int maxConns;

  /// Maximum number of connection retries before throwing out.
  final int maxRetries;

  @override
  Iterable<log.Field> toFields() => {
        log.Int('db', db),
        log.Int('maxConns', maxConns),
        log.Int('maxRetries', maxRetries),
        log.Bool('isTlsEnabled', isTlsEnabled)
      };
}

/// [PoolStats] contains the connection [pool](Pool) statistic.
@immutable
class PoolStats implements log.Loggable {
  const PoolStats._(this.totalConns, this.idlingConns, this.pendingConns,
      this.inUseConns, this.maxConns);

  final int totalConns;
  final int idlingConns;
  final int pendingConns;
  final int maxConns;
  final int inUseConns;

  @override
  String toString() => 'PoolStats('
      'totalConns=$totalConns '
      'idlingConns=$idlingConns '
      'pendingConns=$pendingConns '
      'inUseConns=$inUseConns '
      'maxConns=$maxConns'
      ')';

  @override
  Iterable<log.Field> toFields() => {
        log.Int('totalConns', totalConns),
        log.Int('idlingConns', idlingConns),
        log.Int('pendingConns', pendingConns),
        log.Int('inUseConns', inUseConns),
        log.Int('maxConns', maxConns),
      };
}

/// A [Pool] is a pool of zero or more connections.
///
/// The connection pool maintains a pool of idling connections and manages them
/// automatically.
///
/// ```dart
/// void main() async {
///   final pool = Pool(InternetAddress.loopbackIPv4);
///
///   await pool.set('key', 'value');
///   final value = await client.get('key');
///
///   print(value); // => 'value'
///
///   // Frees dedicated resources.
///   await pool.close();
/// }
/// ```
///
/// By default pooled connections connecting to port `6379`, to connect to
/// another port set corresponding option in [Pool] constructor.
///
/// # Secure connections (TCP over TLS)
/// A [Pool] can communicate with Redis over TLS secure networking protocol.
/// Set [PoolConfig.isTlsEnabled] to `true` and provide corresponding client
/// certificates in [PoolConfig.context] if any.
///
/// # Closing the pool
/// As connection pool make use of persistent connections and caches them to
/// reuse later, underlying connections will be kept open, thus preventing
/// the main process from exit even if all work is done. Use [Pool.close] to
/// close idling connections.
///
/// # Single connection
/// If only a single connection is needed for the whole application lifetime
/// use [Connection] instead.
class Pool extends Executor
    with
        PubSubCommandsMixin,
        ServerCommandsMixin,
        StringCommandsMixin,
        ScriptingCommandsMixin {
  Pool._(this.host, this.port, this.config)
      : _allConns = {},
        _idlingConns = Queue(),
        _pendingConns = Queue(),
        _completer = Completer(),
        _isClosed = false,
        _nextCnxId = 0,
        _totalConns = 0,
        _totalPendingConns = 0,
        _totalIdlingConns = 0;

  final Completer<void> _completer;
  final Map<int, PooledConnection> _allConns;
  final Queue<PooledConnection> _idlingConns;
  final Queue<Completer<PooledConnection>> _pendingConns;

  int _nextCnxId;
  bool _isClosed;

  // conns counters
  // --------------
  int _totalConns;
  int _totalIdlingConns;
  int _totalPendingConns;

  /// This connection pool configurations.
  final PoolConfig config;

  final dynamic host;

  final int port;

  /// Whether the pool is closed.
  ///
  /// Connection pool becomes closed by calling the [close]. Once connection
  /// pool is closed, no operations can be performed by the pool.
  bool get isClosed => _isClosed;

  /// This database statistics.
  PoolStats get stats => PoolStats._(
        _totalConns,
        _totalIdlingConns,
        _totalPendingConns,
        _totalConns - _totalIdlingConns,
        config.maxConns,
      );

  /// Creates a new connection pool to the [host] and [port] and returns
  static Future<Pool> connect(dynamic /* InternetAddress | String */ host,
      {int port = 6379, PoolConfig config = const PoolConfig()}) async {
    ArgumentError.checkNotNull(host);

    if (host is String) {
      // TODO: handle string URI
    } else if (host is! InternetAddress) {
      throw ArgumentError.value(
          host, 'host', 'expected URI string or `InternedAddress`!');
    }

    // TODO: handle min idle conns?

    if (logger.isEnabledFor(log.Level.debug)) {
      logger.bind({
        log.Str('host', host.toString()),
        log.Int('port', port),
      }).debug('make a new connection pool');
    }

    return Pool._(host, port, config);
  }

  int _getNextId() => _nextCnxId++;

  Future<PooledConnection> _createConnection() async {
    for (int failures = 0; failures < config.maxRetries; failures++) {
      try {
        _totalConns++;

        final raw = await Connection.connect(host, port: port, config: config);
        final id = _getNextId();

        if (config.db != null) {
          await raw.select(config.db);
        }

        final cnx = PooledConnection._(this, raw, id);
        _allConns[id] = cnx;

        return cnx;
      } on ConnectionException {
        _totalConns--;
      }
    }

    throw ConnectionException('unable to connect to desired Redis server!');
  }

  void _remove(PooledConnection cnx) {
    _totalConns--;
    _allConns.remove(cnx._id);
    cnx._close(false);
  }

  Future<void> _release(PooledConnection cnx) async {
    try {
      await cnx.ping();
    } on ClosedConnectionException {
      _remove(cnx);
    }

    if (_pendingConns.isNotEmpty) {
      final pendingCnx = _pendingConns.removeFirst();
      final cnx = await acquire();

      pendingCnx.complete(cnx);
    }
  }

  /// Get a future that will complete when this client is closed,
  /// or when an error occurs.
  ///
  /// This future is identical to the future returned by [close].
  Future<void> get done => _completer.future;

  @override
  Future<T> exec<T>(String command, [List<String> args]) async {
    final cnx = await acquire();

    try {
      final result = await cnx.exec<T>(command, args);

      return result;
    } finally {
      await cnx.release();
    }
  }

  /// Returns a single connection maintained by this connection pool.
  ///
  /// The connection may be taken from the pool if available,
  /// if number of connections in the pool are not exceeded limit a new
  /// connection is open, otherwise the task is put to the waiting list
  /// and is processed once connection a free connection is available.
  Future<PooledConnection> acquire() async {
    if (isClosed) {
      throw ClosedConnectionException('connection pool is closed!');
    }

    if (logger.isEnabledFor(log.Level.debug)) {
      logger.debug('acquiring a new connection');
    }

    PooledConnection cnx;

    if (_idlingConns.isNotEmpty) {
      cnx = _idlingConns.removeFirst();
      _totalIdlingConns--;
    } else if (config.maxConns > _totalConns) {
      cnx = await _createConnection();
    } else {
      final task = Completer<PooledConnection>();

      _pendingConns.add(task);
      _totalPendingConns++;

      if (logger.isEnabledFor(log.Level.debug)) {
        logger.bind({log.Obj('stats', stats)}).debug(
            'no connections are available, postpone connection acquisition');
      }

      return task.future;
    }

    if (logger.isEnabledFor(log.Level.debug)) {
      logger.bind({
        log.Int('id', cnx._id),
      }).debug('acquired connection');
    }

    return cnx;
  }

  /// Closes this connection pool and all underlying connections.
  ///
  /// By default a pool closes connections in graceful mode, meaning it is
  /// waiting for tasks to be done. To close connections immediately
  /// set [force] to `true`.
  ///
  /// Once connection pool is closed it cannot reconnect to the desired Redis
  /// server. Call [connect] to instantiate a new connection pool if
  /// needed.
  Future<void> close({bool force = false}) async {
    if (_isClosed) {
      throw ClosedConnectionPoolException(
          'connection pool has already been closed!');
    }

    _isClosed = true;
    final conns = _allConns.values;

    await Future.forEach<Completer<PooledConnection>>(
        _pendingConns,
        (cnx) => cnx.completeError(
            ClosedConnectionPoolException('client has been closed!')));
    await Future.forEach<PooledConnection>(conns, (cnx) => cnx._close(force));

    _allConns.clear();
    _pendingConns.clear();
    _completer.complete();

    return done;
  }
}

/// [PooledConnection] is a single connection managed by particular connection
/// pool.
class PooledConnection extends Executor
    with StringCommandsMixin, PubSubCommandsMixin {
  PooledConnection._(this._pool, this._cnx, this._id);

  final Connection _cnx;
  final Pool _pool;
  final int _id;

  Future<void> _close(bool force) => _cnx.close(force: force);

  @override
  Future<T> exec<T>(String command, [List<String> args]) =>
      _cnx.exec(command, args);

  Future<String> ping([String message]) => _cnx.ping(message);

  /// Returns this connection back to the owner connection pool.
  Future<void> release() => _pool._release(this);
}
