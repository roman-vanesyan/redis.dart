import 'dart:convert' show Codec;

import 'package:redis/src/resp/v2/decoder.dart';
import 'package:redis/src/resp/v2/encoder.dart';
import 'package:redis/src/resp/v2/reply.dart';

const RespCodec resp = RespCodec();

class RespCodec extends Codec<Reply, List<int>> {
  const RespCodec() : super();

  @override
  RespDecoder get decoder => const RespDecoder();

  @override
  RespEncoder get encoder => const RespEncoder();
}
