import 'dart:convert' show Converter, ChunkedConversionSink;
import 'dart:typed_data' show Uint8List;

import '../byte_reader.dart';
import 'reply.dart';
import 'scanner.dart';

class RespDecoder extends Converter<Uint8List, Reply> {
  const RespDecoder() : super();

  @override
  Reply convert(Uint8List input) {
    final buffer = ByteReader(input);
    final scanner = Scanner();

    scanner
      ..feed(buffer.takeOne())
      ..scan(buffer);

    return scanner.reply;
  }

  @override
  Sink<Uint8List> startChunkedConversion(Sink<Reply> sink) =>
      _RespDecodeSink(sink);
}

class _RespDecodeSink extends ChunkedConversionSink<Uint8List> {
  _RespDecodeSink(this._sink) : _scanner = Scanner();

  final Scanner _scanner;
  final Sink<Reply> _sink;

  @override
  void add(Uint8List chunk) {
    final buffer = ByteReader(chunk);

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
