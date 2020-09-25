import 'dart:async' show StreamController, StreamTransformer;
import 'dart:convert' show utf8;
import 'dart:math' as math;
import 'dart:typed_data' show Uint8List;

import 'package:redis/resp2.dart';
import 'package:test/test.dart';

Uint8List encodeUtf8String(String value) => utf8.encoder.convert(value);

dynamic _unwrapArray(Reply reply) {
  switch (reply.kind) {
    case ReplyKind.array:
      final list = <dynamic>[];

      for (final r in (reply as Reply<List<Reply>>).value) {
        list.add(_unwrapArray(r));
      }

      return list;

    default:
      return reply.value;
  }
}

final _unwrapTransformer =
    StreamTransformer<Reply, dynamic>.fromHandlers(handleData: (reply, sink) {
  switch (reply.kind) {
    case ReplyKind.array:
      final list = <dynamic>[];
      for (final r in (reply as Reply<List<Reply>>).value) {
        list.add(_unwrapArray(r));
      }

      sink.add(list);
      break;

    default:
      sink.add(reply.value);
      break;
  }
});

void main() {
  group('Encoder', () {
    RespEncoder encoder;

    setUp(() {
      encoder = const RespEncoder();
    });

    test('Correctly encodes simple string', () {
      final result1 = encoder.convert(
          const Reply<String>(kind: ReplyKind.simpleString, value: 'PING'));
      final result2 = encoder.convert(const Reply<String>(
          kind: ReplyKind.simpleString, value: 'Simple String'));

      expect(result1, equals([43, 80, 73, 78, 71, 13, 10]));

      expect(
          result2,
          equals([
            43,
            83,
            105,
            109,
            112,
            108,
            101,
            32,
            83,
            116,
            114,
            105,
            110,
            103,
            13,
            10
          ]));
    });

    test('Correctly encodes integers', () {
      final result1 = encoder.convert(
          const Reply<int>(kind: ReplyKind.integer, value: -4294967296));
      final result2 = encoder.convert(Reply<int>(
          kind: ReplyKind.integer, value: (math.pow(2, 63) - 1).toInt()));
      final result3 =
          encoder.convert(const Reply<int>(kind: ReplyKind.integer, value: 0));
      final result4 =
          encoder.convert(const Reply<int>(kind: ReplyKind.integer, value: -1));

      expect(result1, [58, 45, 52, 50, 57, 52, 57, 54, 55, 50, 57, 54, 13, 10]);
      expect(result2, [
        58,
        57,
        50,
        50,
        51,
        51,
        55,
        50,
        48,
        51,
        54,
        56,
        53,
        52,
        55,
        55,
        53,
        56,
        48,
        55,
        13,
        10
      ]);
      expect([58, 48, 13, 10], result3);
      expect([58, 45, 49, 13, 10], result4);
    });
  });

  group('Decoder', () {
    RespDecoder decoder;

    setUp(() {
      decoder = const RespDecoder();
    });

    group('#startChunkedConversion', () {
      StreamController<Uint8List> socket;
      Stream<dynamic> stream;

      setUp(() {
        socket = StreamController();
        stream = socket.stream
            .transform(decoder)
            .transform<dynamic>(_unwrapTransformer);
      });

      test('Integer', () {
        final data1 = encodeUtf8String(':-123123\r\n');
        final data2 = encodeUtf8String(':1000000000\r\n');

        socket
          ..add(data1)
          ..add(data2)

          // -32
          ..add(encodeUtf8String(':'))
          ..add(encodeUtf8String('-'))
          ..add(encodeUtf8String('32'))
          ..add(encodeUtf8String('\r\n'));

        expectLater(stream, emitsInOrder(<int>[-123123, 1000000000, -32]));
      });

      test('Error', () {
        final data1 = encodeUtf8String('-ERR error!\r\n');
        final data2 = encodeUtf8String('---error\r\n');

        socket
          // ERR error!
          ..add(data1)

          // --error
          ..add(data2)

          // ER-R
          ..add(encodeUtf8String('-'))
          ..add(encodeUtf8String('E'))
          ..add(encodeUtf8String('R'))
          ..add(encodeUtf8String('-'))
          ..add(encodeUtf8String('R'))
          ..add(encodeUtf8String('\r'))
          ..add(encodeUtf8String('\n'));

        expectLater(
            stream, emitsInOrder(<String>['ERR error!', '--error', 'ER-R']));
      });

      test('Simple strings', () {
        final data1 = encodeUtf8String('+OK\r\n');

        socket
          ..add(data1)
          ..add(data1)
          ..add(data1)
          ..add(data1)
          ..add(data1)
          ..add(data1)

          // ++
          ..add(encodeUtf8String('+++\r\n'))

          // ok
          ..add(encodeUtf8String('+'))
          ..add(encodeUtf8String('o'))
          ..add(encodeUtf8String('k'))
          ..add(encodeUtf8String('\r\n'));

        expectLater(
            stream,
            emitsInOrder(
                <String>['OK', 'OK', 'OK', 'OK', 'OK', 'OK', '++', 'ok']));
      });

      test('Bulk strings', () {
        final data1 = encodeUtf8String('\$13\r\ncomplete data\r\n');
        final data2 = encodeUtf8String('\$12\r\nchunked data\r\n');

        socket
          // complete data
          ..add(data1)

          // chunked data
          ..add(data2.sublist(0, 3))
          ..add(data2.sublist(3, 9))
          ..add(data2.sublist(9))

          // bulk$string
          ..add(encodeUtf8String('\$11\r'))
          ..add(encodeUtf8String('\nbulk\$'))
          ..add(encodeUtf8String('string\r\n'));

        expectLater(
            stream, emitsInOrder(<String>['complete data', 'chunked data']));
      });

      test('Null bulk strings', () {
        final data = encodeUtf8String('\$-1\r\n');

        socket.add(data);

        expectLater(stream, emitsInOrder(<dynamic>[null]));
      });

      test('Arrays', () {
        socket
          ..add(encodeUtf8String('*'))
          ..add(encodeUtf8String('5'))
          ..add(encodeUtf8String('\r\n'))
          ..add(encodeUtf8String(':5\r\n'))
          ..add(encodeUtf8String('\$11\r\nBulk String\r\n'))
          ..add(encodeUtf8String('+Simple String\r\n'))
          ..add(encodeUtf8String('\$13\r\nBulk String 2\r\n'))
          ..add(encodeUtf8String(':-100'))
          ..add(encodeUtf8String('\r'))
          ..add(encodeUtf8String('\n'));

        expectLater(
            stream,
            emits(<dynamic>[
              5,
              'Bulk String',
              'Simple String',
              'Bulk String 2',
              -100
            ]));
      });

      test('Nested arrays', () {
        socket
          ..add(encodeUtf8String('*3\r\n*2\r\n'))
          ..add(encodeUtf8String('\$6\r\nfoobar\r\n'))
          ..add(encodeUtf8String('*1\r\n'))
          ..add(encodeUtf8String(':-10\r\n'))
          ..add(encodeUtf8String('+simple_string\r\n'))
          ..add(encodeUtf8String('\$6\r\nFooBar\r\n'))

          // [null]
          ..add(encodeUtf8String('*1\r\n*-1\r\n'));

        expectLater(
            stream,
            emitsInOrder(<dynamic>[
              [
                [
                  'foobar',
                  [-10]
                ],
                'simple_string',
                'FooBar',
              ],
              [null]
            ]));
      });

      test('Null array', () {
        final data = encodeUtf8String('*-1\r\n');

        socket.add(data);

        expectLater(stream, emitsInOrder(<dynamic>[null]));
      });
    });
  });
}
