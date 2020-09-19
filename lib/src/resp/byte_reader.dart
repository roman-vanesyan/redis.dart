import 'dart:math' show min;
import 'dart:typed_data' show Uint8List, ByteData;

class ByteReader {
  factory ByteReader(Uint8List bytes) => ByteReader._(bytes);

  ByteReader._(this._bytes)
      : _buffer = ByteData.view(_bytes.buffer),
        _rdOffset = 0;

  final Uint8List _bytes;
  final ByteData _buffer;
  int _rdOffset;

  /// Returns length of this buffer in bytes.
  int get length => _buffer.lengthInBytes;

  /// Returns current reading offset.
  int get offset => _rdOffset;

  int takeOne() {
    if (available() == 0) {
      return -1;
    }

    return _buffer.getUint8(_rdOffset++);
  }

  Uint8List take(int count) {
    final start = _rdOffset;
    final offset = min(count, _buffer.lengthInBytes);
    _rdOffset += offset;

    return Uint8List.view(_bytes.buffer, start, offset);
  }

  int peek([int offset = 0]) {
    if (available() == 0) {
      return -1;
    }

    return _buffer.getUint8(_rdOffset + offset);
  }

  /// Returns the number of non-read bytes in this buffer that can be read.
  int available() => length - _rdOffset;
}
