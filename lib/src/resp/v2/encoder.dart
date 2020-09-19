import 'dart:convert' show Converter, utf8;
import 'dart:io' show BytesBuilder;
import 'dart:typed_data' show Uint8List;

import 'reply.dart';
import 'token_type.dart';

const int _cr = 0x0d;
const int _lf = 0x0a;
final Uint8List _crlf = Uint8List(2)
  ..[0] = _cr
  ..[1] = _lf;

class RespEncoder extends Converter<Reply<dynamic>, Uint8List> {
  const RespEncoder() : super();

  Uint8List _encodeArray(ArrayReply reply) {
    if (reply.value.isEmpty) {
      return Uint8List(4)
        ..[0] = 0x2a /* * */
        ..[1] = 0x30 /* 0 */
        ..[2] = _cr
        ..[3] = _lf;
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

  Uint8List _encodeInteger(IntegerReply reply) {
    final data = utf8.encode(reply.value.toString());

    return (BytesBuilder(copy: false)
          ..addByte(TokenType.integer)
          ..add(data)
          ..add(_crlf))
        .takeBytes();
  }

  Uint8List _encodeSimpleString(SimpleStringReply reply) =>
      (BytesBuilder(copy: false)
            ..addByte(TokenType.simpleString)
            ..add(utf8.encode(reply.value))
            ..add(_crlf))
          .takeBytes();

  Uint8List _encodeBulkString(BulkStringReply reply) {
    if (reply.value.isEmpty) {
      return Uint8List(4)
        ..[0] = TokenType.bulkString
        ..[1] = 0x30 /* 0 */
        ..[2] = _cr
        ..[3] = _lf;
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

  Uint8List _encodeError(ErrorReply reply) => (BytesBuilder(copy: false)
        ..addByte(TokenType.error)
        ..add(utf8.encode(reply.value))
        ..add(_crlf))
      .takeBytes();

  @override
  Uint8List convert(Reply<dynamic> input) {
    final kind = input.kind;

    switch (kind) {
      case ReplyKind.array:
        return _encodeArray(input as ArrayReply);

      case ReplyKind.nil:
        return Uint8List(5)
          ..[0] = TokenType.bulkString
          ..[1] = 0x2d /* - */
          ..[2] = 0x31 /* 1 */
          ..[3] = _cr
          ..[4] = _lf;

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
