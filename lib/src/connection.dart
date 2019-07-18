import 'dart:io' show SecurityContext;

import 'package:meta/meta.dart' show immutable;
import 'package:jetlog/jetlog.dart' as log;

import 'package:redis/src/connection_impl.dart' show ConnectionImpl;
import 'package:redis/src/context_provider.dart';
import 'package:redis/src/runner.dart';
import 'package:redis/src/transaction.dart';
import 'package:redis/src/raw_connection.dart';

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

/// Connections is a single connection rather than a pool of connections.
abstract class Connection implements Runner, ContextProvider {
  /// Whether the connection is transaction mode.
  ///
  /// Connection is considered to be in transaction mode once [multi] is
  /// executed till corresponding [Transaction.exec] method call.
  bool get isTransacting;

  static Future<Connection> connect(dynamic host,
      {int port = 6379, ConnectionConfig config}) async {
    final raw = await RawConnection.connect(
      host,
      port,
      isTlsEnabled: config.isTlsEnabled,
      context: config.securityContext,
    );

    final cnx = ConnectionImpl(raw, config);

    if (config.password != null) {
      await cnx.auth(config.password);
    }

    return cnx;
  }

  Future<String> echo(String message);

  Future<String> ping([String message]);

  Future<void> select(int db);
}
