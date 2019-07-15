import 'package:redis/src/executor.dart';

class PubSubContext {
  PubSubContext(this._executor);

  final Executor _executor;

  /// Posts a [message] to the given [channel].
  ///
  /// See: https://redis.io/commands/publish
  Future<int> publish(String channel, String message) =>
      _executor.exec([r'PUBLISH', channel, message]);

  /// List the currently active channels. An active channel is Pub/Sub channel
  /// with one or more subscribers (not including clients subscribed to
  /// patterns).
  ///
  /// If no [pattern] is specified, all the channels are listed, otherwise
  /// only channels matching the specified [pattern] are listed.
  ///
  /// See: https://redis.io/commands/pubsub#pubsub-channels-pattern
  Future<Iterable<String>> channels([String pattern]) async {
    final result = await _executor.exec<List<String>>(
        [r'PUBSUB', r'CHANNELS', if (pattern != null) pattern]);

    return result;
  }

  /// Returns the number of subscribers (not counting clients subscribed to
  /// patterns) for the specified [channels].
  ///
  /// See: https://redis.io/commands/pubsub#codepubsub-numsub-channel-1--channel-ncode
  Future<int> numsub([Iterable<String> channels]) =>
      _executor.exec([r'PUBSUB', r'NUMSUB', if (channels != null) ...channels]);

  /// Returns the number of subscriptions to any patterns.
  ///
  /// See: https://redis.io/commands/pubsub#codepubsub-numpatcode
  Future<int> numpat() => _executor.exec([r'PUBSUB', r'NUMPAT']);
}
