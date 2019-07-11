import 'package:redis/src/executor.dart';

class _Command {
  static const String publish = r'PUBLISH';
  static const String channels = r'PUBSUB CHANNELS';
  static const String numSub = r'PUBSUB NUMSUB';
  static const String numPat = r'PUBSUB NUMPAT';
}

mixin PubSubCommandsMixin on Executor {
  /// Posts a [message] to the given [channel].
  ///
  /// See: https://redis.io/commands/publish
  Future<int> publish(String channel, String message) =>
      exec(_Command.publish, [channel, message]);

  /// List the currently active channels. An active channel is Pub/Sub channel
  /// with one or more subscribers (not including clients subscribed to
  /// patterns).
  ///
  /// If no [pattern] is specified, all the channels are listed, otherwise
  /// only channels matching the specified [pattern] are listed.
  ///
  /// See: https://redis.io/commands/pubsub#pubsub-channels-pattern
  Future<Iterable<String>> channels([String pattern]) async {
    final result = await exec<List<String>>(
        _Command.channels, [if (pattern != null) pattern]);

    return result;
  }

  /// Returns the number of subscribers (not counting clients subscribed to
  /// patterns) for the specified [channels].
  ///
  /// See: https://redis.io/commands/pubsub#codepubsub-numsub-channel-1--channel-ncode
  Future<int> numsub([Iterable<String> channels]) =>
      exec(_Command.numSub, [if (channels != null) ...channels]);

  /// Returns the number of subscriptions to any patterns.
  ///
  /// See: https://redis.io/commands/pubsub#codepubsub-numpatcode
  Future<int> numpat() => exec(_Command.numPat);
}
