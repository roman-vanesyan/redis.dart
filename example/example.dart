import 'dart:io' show InternetAddress;

import 'package:redis/redis.dart' show Pool;

Future<void> main() async {
  final client = await Pool.connect(InternetAddress.loopbackIPv4);

  await client.set('greeting', 'Hello world!');
  final value = await client.get('greeting');

  print(value); // => 'Hello world'

  await client.close();
}
