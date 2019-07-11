/// Package `redis` provides a non-blocking Redis client.
///
/// To use in your code:
/// ```dart
/// import "package:redis/redis.dart";
/// ```
library redis;

export 'src/connection.dart' show Connection, ConnectionConfig;
export 'src/pool.dart' show Pool, PooledConnection, PoolConfig, PoolStats;
export 'src/pubsub_commands_mixin.dart' show PubSubCommandsMixin;
export 'src/string_commands_mixin.dart' show StringCommandsMixin;
export 'src/subscriber.dart' show Subscriber, Event, MessageEvent, EventKind;
