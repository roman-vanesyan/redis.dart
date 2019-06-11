import 'dart:convert' show Converter, ByteConversionSinkBase;
import 'package:redis/src/resp/byte_buffer.dart';
import 'package:redis/src/resp/scanner.dart';
import 'package:redis/src/resp/reply.dart';

class RespDecoder extends Converter<List<int>, Reply> {
  const RespDecoder() : super();

  @override
  Reply convert(List<int> input) {
    final buffer = ByteBuffer(input);
    final consumer = Scanner();

    consumer
      ..feed(buffer.takeOne())
      ..scan(buffer);

    return consumer.reply;
  }

  @override
  Sink<List<int>> startChunkedConversion(Sink<Reply> sink) =>
      _RespDecodeSink(sink);
}

class _RespDecodeSink extends ByteConversionSinkBase {
  _RespDecodeSink(this._sink) : _scanner = Scanner();

  final Scanner _scanner;
  final Sink<Reply> _sink;

  @override
  void add(List<int> chunk) {
    final buffer = ByteBuffer(chunk);

    while (buffer.available() > 0) {
      if (_scanner.idling) {
        _scanner.feed(buffer.takeOne());
      }

      final done = _scanner.scan(buffer);

      if (done) {
        _sink.add(_scanner.reply);
      }
    }
  }

  @override
  void close() => _sink.close();
}
