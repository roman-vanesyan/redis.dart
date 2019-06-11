import 'dart:async' show StreamController, StreamTransformer;
import 'dart:convert' show utf8;
import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:redis/resp.dart';

dynamic _unwrapArray(Reply reply) {
  switch (reply.kind) {
    case ReplyKind.array:
      final list = <dynamic>[];

      for (final r in (reply as ArrayReply).value) {
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
      for (final r in (reply as ArrayReply).value) {
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
      final result1 = encoder.convert(SimpleStringReply('PING'));
      final result2 = encoder.convert(SimpleStringReply('Simple String'));

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
      final result1 = encoder.convert(IntegerReply(-4294967296));
      final result2 = encoder.convert(IntegerReply(math.pow(2, 63) - 1 as int));
      final result3 = encoder.convert(IntegerReply(0));
      final result4 = encoder.convert(IntegerReply(-1));

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
      StreamController<List<int>> socket;
      Stream<dynamic> stream;

      setUp(() {
        socket = StreamController();
        stream = socket.stream
            .transform(decoder)
            .transform<dynamic>(_unwrapTransformer);
      });

      test('Integer', () {
        final data1 = utf8.encode(':-123123\r\n');
        final data2 = utf8.encode(':1000000000\r\n');

        socket
          ..add(data1)
          ..add(data2)

          // -32
          ..add(utf8.encode(':'))
          ..add(utf8.encode('-'))
          ..add(utf8.encode('32'))
          ..add(utf8.encode('\r\n'));

        expectLater(stream, emitsInOrder(<int>[-123123, 1000000000, -32]));
      });

      test('Error', () {
        final data1 = utf8.encode('-ERR error!\r\n');
        final data2 = utf8.encode('---error\r\n');

        socket
          // ERR error!
          ..add(data1)

          // --error
          ..add(data2)

          // ER-R
          ..add(utf8.encode('-'))
          ..add(utf8.encode('E'))
          ..add(utf8.encode('R'))
          ..add(utf8.encode('-'))
          ..add(utf8.encode('R'))
          ..add(utf8.encode('\r'))
          ..add(utf8.encode('\n'));

        expectLater(
            stream, emitsInOrder(<String>['ERR error!', '--error', 'ER-R']));
      });

      test('Simple strings', () {
        final data1 = utf8.encode('+OK\r\n');

        socket
          ..add(data1)
          ..add(data1)
          ..add(data1)
          ..add(data1)
          ..add(data1)
          ..add(data1)

          // ++
          ..add(utf8.encode('+++\r\n'))

          // ok
          ..add(utf8.encode('+'))
          ..add(utf8.encode('o'))
          ..add(utf8.encode('k'))
          ..add(utf8.encode('\r\n'));

        expectLater(
            stream,
            emitsInOrder(
                <String>['OK', 'OK', 'OK', 'OK', 'OK', 'OK', '++', 'ok']));
      });

      test('Bulk strings', () {
        final data1 = utf8.encode('\$13\r\ncomplete data\r\n');
        final data2 = utf8.encode('\$12\r\nchunked data\r\n');

        socket
          // complete data
          ..add(data1)

          // chunked data
          ..add(data2.sublist(0, 3))
          ..add(data2.sublist(3, 9))
          ..add(data2.sublist(9))

          // bulk$string
          ..add(utf8.encode('\$11\r'))
          ..add(utf8.encode('\nbulk\$'))
          ..add(utf8.encode('string\r\n'));

        expectLater(
            stream, emitsInOrder(<String>['complete data', 'chunked data']));
      });

      test('Null bulk strings', () {
        final data = utf8.encode('\$-1\r\n');

        socket.add(data);

        expectLater(stream, emitsInOrder(<dynamic>[null]));
      });

      test('Arrays', () {
        socket
          ..add(utf8.encode('*'))
          ..add(utf8.encode('5'))
          ..add(utf8.encode('\r\n'))
          ..add(utf8.encode(':5\r\n'))
          ..add(utf8.encode('\$11\r\nBulk String\r\n'))
          ..add(utf8.encode('+Simple String\r\n'))
          ..add(utf8.encode('\$13\r\nBulk String 2\r\n'))
          ..add(utf8.encode(':-100'))
          ..add(utf8.encode('\r'))
          ..add(utf8.encode('\n'));

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
          ..add(utf8.encode('*3\r\n*2\r\n'))
          ..add(utf8.encode('\$6\r\nfoobar\r\n'))
          ..add(utf8.encode('*1\r\n'))
          ..add(utf8.encode(':-10\r\n'))
          ..add(utf8.encode('+simple_string\r\n'))
          ..add(utf8.encode('\$6\r\nFooBar\r\n'))

          // [null]
          ..add(utf8.encode('*1\r\n*-1\r\n'));

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
        final data = utf8.encode('*-1\r\n');

        socket.add(data);

        expectLater(stream, emitsInOrder(<dynamic>[null]));
      });
    });
  });
}
