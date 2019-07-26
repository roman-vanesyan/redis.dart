import 'dart:io' show InternetAddress;

import 'package:redis/redis.dart' show Pool;

Future<void> main() async {
  final pool = Pool(InternetAddress.loopbackIPv4);

  final tx = await pool.multi();
  final ops = [
    tx.strings.set('greeting', 'hello world!'),
    tx.strings.get('greeting').then(print) // => 'Hello world'
  ];

  await tx.exec();
  await Future.wait(ops);

  await pool.close();
}
