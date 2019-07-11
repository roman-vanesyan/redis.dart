import 'dart:io' show InternetAddress;

import 'package:redis/redis.dart' show Pool;

Future<void> main() async {
  final pool = await Pool.connect(InternetAddress.loopbackIPv4);

  await pool.strings.set('greeting', 'Hello world!');
  final value = await pool.strings.get('greeting');

  print(value); // => 'Hello world'

  await pool.close();
}
