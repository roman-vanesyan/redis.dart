import 'dart:io' show InternetAddress;

import 'package:redis/redis.dart' show Pool;

Future<void> main() async {
  final client = await Pool.connect(InternetAddress.loopbackIPv4);

  await client.strings.set('greeting', 'Hello world!');
  final value = await client.strings.get('greeting');

  print(value); // => 'Hello world'

  await client.close();
}
