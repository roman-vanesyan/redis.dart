import 'dart:async' show StreamController;
import 'dart:io' show SecurityContext, InternetAddress;

import 'package:redis/resp.dart' show ArrayReply, Reply, ReplyKind;

import 'package:redis/src/connection.dart' show ConnectionConfig;
import 'package:redis/src/raw_connection.dart' show RawConnection;
import 'package:redis/src/utils.dart';

class _Command {
  static const String subscribe = r'SUBSCRIBE';
  static const String psubscribe = r'PSUBSCRIBE';
  static const String unsubscribe = r'UNSUBSCRIBE';
  static const String punsubscribe = r'PUNSUBSCRIBE';
}

class _EventType {
  static const String subscribe = r'subscribe';
  static const String unsubscribe = r'unsubscribe';
  static const String message = r'message';
  static const String pong = r'pong';
}

enum EventKind {
  pong,
  subscription,
  unsubscription,
  message,
}

abstract class Event {
  EventKind get kind;
}

class UnsubscriptionEvent implements Event {
  UnsubscriptionEvent._(this.channel, this.total)
      : kind = EventKind.unsubscription;

  @override
  final EventKind kind;

  final String channel;

  final int total;
}

class SubscriptionEvent implements Event {
  SubscriptionEvent._(this.channel, this.total) : kind = EventKind.subscription;

  @override
  final EventKind kind;

  final String channel;

  final int total;
}

/// An event is emitted when a message is published to the [channel].
class MessageEvent implements Event {
  MessageEvent._(this.channel, this.value) : kind = EventKind.message;

  @override
  final EventKind kind;

  /// The channel this message coming from.
  final String channel;

  /// The actual message.
  final String value;
}

/// Pong event is sent as response to [Subscriber.ping] call.
class PongEvent implements Event {
  PongEvent(this.value) : kind = EventKind.pong;

  @override
  final EventKind kind;

  final String value;
}

/// [SubscriberConfig] is used to configure a [Subscriber].
class SubscriberConfig extends ConnectionConfig {
  const SubscriberConfig({
    String password,
    bool isTlsEnabled = false,
    SecurityContext securityContext,
  }) : super(
          password: password,
          isTlsEnabled: isTlsEnabled,
          securityContext: securityContext,
        );
}

class Subscriber {
  Subscriber._(this._cnx) : _controller = StreamController.broadcast() {
    _cnx.replies.listen(_onReply);
  }

  final RawConnection _cnx;
  final StreamController<Event> _controller;

  Stream<Event> get messages => _controller.stream;

  static Future<Subscriber> connect(
    dynamic host, {
    int port = 6379,
    SubscriberConfig config = const SubscriberConfig(),
  }) async {
    final cnx = await RawConnection.connect(
      host,
      port,
      isTlsEnabled: config.isTlsEnabled,
      context: config.securityContext,
    );

    return Subscriber._(cnx);
  }

  void _onReply(Reply reply) {
    assert(reply.kind == ReplyKind.array);

    final values = unwrapArrayReply(reply as ArrayReply);
    final String type = values[0] as String;

    switch (type) {
      case _EventType.subscribe:
        _controller.add(SubscriptionEvent._(
          values[1] as String,
          values[2] as int,
        ));
        break;

      case _EventType.unsubscribe:
        _controller.add(UnsubscriptionEvent._(
          values[1] as String,
          values[2] as int,
        ));
        break;

      case _EventType.message:
        _controller.add(MessageEvent._(
          values[1] as String,
          values[2] as String,
        ));
        break;

      case _EventType.pong:
        final val = values[1] as String;

        _controller.add(PongEvent(val != '' ? val : null));
        break;

      default:
        throw Exception('unknown reply!');
    }
  }

  void _send(String command, [List args]) =>
      _cnx.send(convertToRespLine([command, if (args != null) ...args]));

  void ping([String message]) =>
      _send(r'PING', <String>[if (message != null) message]);

  /// Subscribes this client to the specified [channels].
  ///
  /// https://redis.io/commands/subscribe
  void subscribe(Iterable<String> channels) =>
      _send(_Command.subscribe, <String>[...channels]);

  /// Subscribes this client to the given [patterns].
  ///
  /// https://redis.io/commands/psubscribe
  void psubscribe(Iterable<String> patterns) =>
      _send(_Command.psubscribe, <String>[...patterns]);

  /// Unsubscribes this client from the given [channels], if no [channels] are
  /// provided unsubscribes from previously subscribed channels.
  ///
  /// https://redis.io/commands/unsubscribe
  void unsubscribe([Iterable<String> channels]) =>
      _send(_Command.unsubscribe, <String>[if (channels != null) ...channels]);

  /// https://redis.io/commands/punsubscribe
  void punsubscribe([Iterable<String> patterns]) =>
      _send(_Command.subscribe, <String>[if (patterns != null) ...patterns]);

  Future<void> close({bool force = false}) => _cnx.close(false);
}
