import 'dart:io'
    show SecurityContext, SecureSocket, Socket, SocketException, SocketOption;

import 'package:redis/resp.dart'
    show RespDecoder, RespEncoder, Reply, ArrayReply;

import 'package:redis/src/exceptions.dart'
    show ConnectionException, ClosedConnectionException;

class RawConnection {
  RawConnection._(this._socket)
      : encoder = const RespEncoder(),
        decoder = const RespDecoder();

  final RespEncoder encoder;
  final RespDecoder decoder;
  final Socket _socket;

  Stream<Reply> get replies => _socket.transform(decoder);

  void send(ArrayReply reply) => _socket.add(encoder.convert(reply));

  static Future<RawConnection> connect(dynamic host, int port,
      {bool isTlsEnabled, SecurityContext context}) async {
    // ignore: close_sinks
    Socket socket;

    try {
      socket = await Socket.connect(host, port)
        ..setOption(SocketOption.tcpNoDelay, true);
    } on SocketException {
      final h = host.toString();
      final p = port.toString();

      throw ConnectionException(
          'Unable to connect to Redis server at host: $h, port: $p');
    }

    if (isTlsEnabled) {
      socket = await SecureSocket.secure(socket, context: context);
    }

    return RawConnection._(socket);
  }

  Future<void> close(bool force) async {
    if (!force) {
      await _socket.flush();
    }

    try {
      await _socket.close();
    } on SocketException {
      /* ignore */
    }
  }
}
