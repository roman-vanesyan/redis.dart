import 'package:redis/resp.dart'
    show ArrayReply, Reply, NilReply, BulkStringReply, ReplyKind;

ArrayReply convertToRespLine(List<Object> input) {
  final arguments = <Reply<Object>>[];

  for (final singleInput in input) {
    if (singleInput == null) {
      arguments.add(NilReply());
    } else {
      arguments.add(BulkStringReply(singleInput.toString()));
    }
  }

  return ArrayReply(arguments);
}

List<dynamic> unwrapArrayReply(ArrayReply reply) {
  final a = reply.value;
  final l = reply.length;
  final list = List<dynamic>(l);

  for (int i = 0; i < l; i++) {
    final kind = a[i].kind;

    switch (kind) {
      case ReplyKind.array:
        list[i] = unwrapArrayReply(a[i] as ArrayReply);
        break;

      default:
        list[i] = a[i].value;
        break;
    }
  }

  return list;
}

bool isOk(String s) => s == 'OK';
