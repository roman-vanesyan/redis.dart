import 'package:meta/meta.dart' show required, sealed, immutable;

enum ReplyKind {
  simpleString,
  error,
  integer,
  bulkString,
  nil,
  array,

  // RESP3
  double,
  boolean
}

@sealed
@immutable
class Reply<T> {
  const Reply({@required this.value, @required this.kind});

  final T value;
  final ReplyKind kind;

  // ignore: prefer_void_to_null
  static const Reply nilReply = Reply<Null>(
    value: null,
    kind: ReplyKind.nil,
  );
}
