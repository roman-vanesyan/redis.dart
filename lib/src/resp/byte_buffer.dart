import 'dart:typed_data' show Uint8List, ByteData;

class ByteBuffer {
  factory ByteBuffer(List<int> bytes) =>
      ByteBuffer._(Uint8List.fromList(bytes));

  ByteBuffer._(this._bytes)
      : _buffer = ByteData.view(_bytes.buffer),
        _rdOffset = 0;

  final Uint8List _bytes;
  final ByteData _buffer;
  int _rdOffset;

  /// Returns length of this buffer in bytes.
  int get length => _buffer.lengthInBytes;

  /// Returns current reading offset.
  int get offset => _rdOffset;

  int takeOne() => _buffer.getUint8(_rdOffset++);

  List<int> take(int count) {
    final offset = _rdOffset;
    _rdOffset += count;

    return Uint8List.view(_bytes.buffer, offset, count);
  }

  int peek([int offset = 0]) => _buffer.getUint8(_rdOffset + offset);

  /// Returns the number of non-read bytes in this buffer that can be read.
  int available() => length - _rdOffset;
}
