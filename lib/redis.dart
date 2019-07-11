/// Package `redis` provides a non-blocking Redis client.
///
/// To use in your code:
/// ```dart
/// import "package:redis/redis.dart";
/// ```
library redis;

export 'src/connection.dart' show Connection, ConnectionConfig;
export 'src/pool.dart' show Pool, PooledConnection, PoolConfig, PoolStats;
export 'src/pubsub_context.dart' show PubSubContext;
export 'src/strings_context.dart' show StringsContext;
export 'src/subscriber.dart'
    show Subscriber, SubscriberConfig, Event, MessageEvent, EventKind;
