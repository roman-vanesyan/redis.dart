import 'dart:convert' show Converter, utf8;
import 'dart:io' show BytesBuilder;

import 'package:redis/src/resp/reply.dart';
import 'package:redis/src/resp/token_type.dart';

const int _cr = 0x0d;
const int _lf = 0x0a;
const List<int> _crlf = [_cr, _lf];

class RespEncoder extends Converter<Reply<dynamic>, List<int>> {
  const RespEncoder() : super();

  List<int> _encodeArray(ArrayReply reply) {
    if (reply.value.isEmpty) {
      return [0x2a /* * */, 0x30 /* 0 */, _cr, _lf];
    }

    final len = reply.value.length;
    final replies = reply.value;
    final buffer = BytesBuilder(copy: false)
      ..addByte(TokenType.array)
      ..add(utf8.encode(len.toString()))
      ..add(_crlf);

    for (final reply in replies) {
      buffer.add(convert(reply));
    }

    return buffer.takeBytes();
  }

  List<int> _encodeInteger(IntegerReply reply) {
    final data = utf8.encode(reply.value.toString());

    return (BytesBuilder(copy: false)
          ..addByte(TokenType.integer)
          ..add(data)
          ..add(_crlf))
        .takeBytes();
  }

  List<int> _encodeSimpleString(SimpleStringReply reply) =>
      (BytesBuilder(copy: false)
            ..addByte(TokenType.simpleString)
            ..add(utf8.encode(reply.value))
            ..add(_crlf))
          .takeBytes();

  List<int> _encodeBulkString(BulkStringReply reply) {
    if (reply.value.isEmpty) {
      return [TokenType.bulkString, 0x30 /* 0 */, _cr, _lf];
    }

    final len = reply.value.length;
    final buffer = BytesBuilder(copy: false)
      ..addByte(TokenType.bulkString)
      ..add(utf8.encode(len.toString()))
      ..add(_crlf)
      ..add(utf8.encode(reply.value))
      ..add(_crlf);

    return buffer.takeBytes();
  }

  List<int> _encodeError(ErrorReply reply) => (BytesBuilder(copy: false)
        ..addByte(TokenType.error)
        ..add(utf8.encode(reply.value))
        ..add(_crlf))
      .takeBytes();

  @override
  List<int> convert(Reply<dynamic> input) {
    final kind = input.kind;

    switch (kind) {
      case ReplyKind.array:
        return _encodeArray(input as ArrayReply);

      case ReplyKind.nil:
        return [TokenType.bulkString, 0x2d /* - */, 0x31 /* 1 */, _cr, _lf];

      case ReplyKind.simpleString:
        return _encodeSimpleString(input as SimpleStringReply);

      case ReplyKind.integer:
        return _encodeInteger(input as IntegerReply);

      case ReplyKind.bulkString:
        return _encodeBulkString(input as BulkStringReply);

      case ReplyKind.error:
        return _encodeError(input as ErrorReply);
    }

    throw Exception('Unknown reply kind!');
  }
}
