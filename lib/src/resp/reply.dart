enum ReplyKind {
  simpleString,
  error,
  integer,
  bulkString,
  nil,
  array,
}

abstract class Reply<T> {
  T get value;

  ReplyKind get kind;
}

class SimpleStringReply extends Reply<String> {
  SimpleStringReply(this.value) : kind = ReplyKind.simpleString;

  @override
  final String value;

  @override
  final ReplyKind kind;
}

class ErrorReply extends Reply<String> {
  ErrorReply(this.value) : kind = ReplyKind.error;

  @override
  final String value;

  @override
  final ReplyKind kind;
}

class IntegerReply extends Reply<int> {
  IntegerReply(this.value) : kind = ReplyKind.integer;

  @override
  final int value;

  @override
  final ReplyKind kind;
}

class BulkStringReply extends Reply<String> {
  BulkStringReply(this.value) : kind = ReplyKind.bulkString;

  @override
  final String value;

  @override
  final ReplyKind kind;
}

class ArrayReply extends Reply<List<Reply<dynamic>>> {
  ArrayReply(this.value) : kind = ReplyKind.array;

  @override
  final List<Reply<dynamic>> value;

  @override
  final ReplyKind kind;

  int get length => value.length;
}

class NilReply extends Reply<Object> {
  NilReply()
      : kind = ReplyKind.nil,
        value = null;

  @override
  final ReplyKind kind;

  @override
  final Object value;
}
