import 'dart:convert' show ChunkedConversionSink, Codec, Converter, utf8;
import 'dart:io' show BytesBuilder;
import 'dart:typed_data' show Uint8List;

import '../byte_reader.dart';
import '../scanner.dart';
import '../signal_char.dart' as signal_char;
import 'reply.dart';

const int _cr = 0x0d;
const int _lf = 0x0a;
final Uint8List _crlf = Uint8List(2)
  ..[0] = _cr
  ..[1] = _lf;

/// A [RespCodec] decodes chunk of bytes to a corresponding RESP protocol
/// reply and encodes reply to its [RESP] bytes representation.
///
/// [RESP]: https://redis.io/topics/protocol
class RespCodec extends Codec<Reply, Uint8List> {
  const RespCodec() : super();

  @override
  RespDecoder get decoder => const RespDecoder();

  @override
  RespEncoder get encoder => const RespEncoder();
}

class RespDecoder extends Converter<Uint8List, Reply> {
  const RespDecoder() : super();

  @override
  Reply convert(Uint8List input) {
    final reader = ByteReader(input);
    final scanner = Scanner(protocolKind: ProtocolKind.resp);

    if (scanner.scan(reader)) {
      return scanner.reply;
    }

    throw Exception('Unable to scan RESP reply!');
  }

  @override
  Sink<Uint8List> startChunkedConversion(Sink<Reply> sink) =>
      _RespDecodeSink(sink);
}

class _RespDecodeSink extends ChunkedConversionSink<Uint8List> {
  _RespDecodeSink(this._sink)
      : _scanner = Scanner(protocolKind: ProtocolKind.resp);

  final Scanner _scanner;
  final Sink<Reply> _sink;

  @override
  void add(Uint8List chunk) {
    final buffer = ByteReader(chunk);

    while (buffer.available() > 0) {
      final done = _scanner.scan(buffer);

      if (done) {
        _sink.add(_scanner.reply);
      }
    }
  }

  @override
  void close() => _sink.close();
}

class RespEncoder extends Converter<Reply<dynamic>, Uint8List> {
  const RespEncoder() : super();

  Uint8List _encodeArray(Reply<List<Reply>> reply) {
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
      ..addByte(signal_char.array)
      ..add(utf8.encode(len.toString()))
      ..add(_crlf);

    for (final reply in replies) {
      buffer.add(convert(reply));
    }

    return buffer.takeBytes();
  }

  Uint8List _encodeInteger(Reply<int> reply) {
    final data = utf8.encode(reply.value.toString());

    return (BytesBuilder(copy: false)
          ..addByte(signal_char.integer)
          ..add(data)
          ..add(_crlf))
        .takeBytes();
  }

  Uint8List _encodeSimpleString(Reply<String> reply) =>
      (BytesBuilder(copy: false)
            ..addByte(signal_char.simpleString)
            ..add(utf8.encode(reply.value))
            ..add(_crlf))
          .takeBytes();

  Uint8List _encodeBulkString(Reply<String> reply) {
    if (reply.value.isEmpty) {
      return Uint8List(4)
        ..[0] = signal_char.bulkString
        ..[1] = 0x30 /* 0 */
        ..[2] = _cr
        ..[3] = _lf;
    }

    final len = reply.value.length;
    final buffer = BytesBuilder(copy: false)
      ..addByte(signal_char.bulkString)
      ..add(utf8.encode(len.toString()))
      ..add(_crlf)
      ..add(utf8.encode(reply.value))
      ..add(_crlf);

    return buffer.takeBytes();
  }

  Uint8List _encodeError(Reply<String> reply) => (BytesBuilder(copy: false)
        ..addByte(signal_char.error)
        ..add(utf8.encode(reply.value))
        ..add(_crlf))
      .takeBytes();

  Uint8List _encodeDouble(Reply<double> reply) => (BytesBuilder(copy: false)
        ..addByte(signal_char.double)
        ..add(utf8.encode('${reply.value}'))
        ..add(_crlf))
      .takeBytes();

  @override
  Uint8List convert(Reply<dynamic> input) {
    final kind = input.kind;

    switch (kind) {
      case ReplyKind.array:
        return _encodeArray(input as Reply<List<Reply>>);

      case ReplyKind.nil:
        return Uint8List(5)
          ..[0] = signal_char.bulkString
          ..[1] = 0x2d /* - */
          ..[2] = 0x31 /* 1 */
          ..[3] = _cr
          ..[4] = _lf;

      case ReplyKind.simpleString:
        return _encodeSimpleString(input as Reply<String>);

      case ReplyKind.integer:
        return _encodeInteger(input as Reply<int>);

      case ReplyKind.bulkString:
        return _encodeBulkString(input as Reply<String>);

      case ReplyKind.error:
        return _encodeError(input as Reply<String>);

      case ReplyKind.double:
        return _encodeDouble(input as Reply<double>);

      case ReplyKind.boolean:
//        return _encodeBoolean(input as Reply<bool>);
        break;
    }

    throw Exception('Unknown reply kind!');
  }
}
