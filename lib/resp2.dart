/// Package [redis.resp2] implements RESP protocol a plaintext binary self
/// protocol.
///
/// **Important**: The initial RESP was obsoleted by RESP3 protocol which is
/// extension of this protocol and is used as default protocol starting
/// from Redis v6.
///
/// The RESP3 protocol is also implemented by this package and can be found in
/// the [redis.resp3] library.
///
/// To use this library in your code:
/// ```dart
/// import 'package:redis/resp2.dart';
/// ```
///
/// This library exposes [RespCodec] converter that is capable to encode and
/// decode RESP protocol replies. The [RespEncoder] and [RespDecoder]
/// used to encode and decode RESP protocol replies correspondingly are also
/// exported.
///
/// [RespCodec], [RespEncoder] and [RespDecoder] are implementing Dart's
/// standard library [Codec] and [Converter] classes exported from `dart:convert`
/// library. The [RespEncoder] is capable to transform a bytes stream to RESP
/// replies stream.
///
/// See https://redis.io/topics/protocol for whole protocol description.
library redis.resp2;

export 'src/resp/resp2/codec.dart' show RespCodec, RespEncoder,RespDecoder;
export 'src/resp/resp2/reply.dart'
    show
        Reply,
        ReplyKind,
        ArrayReply,
        BulkStringReply,
        ErrorReply,
        IntegerReply,
        NilReply,
        SimpleStringReply;
