import 'dart:convert' show Codec;

import 'package:redis/src/resp/decoder.dart';
import 'package:redis/src/resp/encoder.dart';
import 'package:redis/src/resp/reply.dart';

const RespCodec resp = RespCodec();

class RespCodec extends Codec<Reply, List<int>> {
  const RespCodec() : super();

  @override
  RespDecoder get decoder => const RespDecoder();

  @override
  RespEncoder get encoder => const RespEncoder();
}
