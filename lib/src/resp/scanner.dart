import 'dart:io' show BytesBuilder;
import 'dart:math' show min;
import 'dart:typed_data' show Uint8List;

import 'package:meta/meta.dart' show required;

import 'byte_reader.dart';
import 'resp2/protocol_exception.dart';
import 'resp2/reply.dart';
import 'signal_char.dart' as signal_code;

const int _cr = 0x0d; // <CR>
const int _lf = 0x0a; // <LF>

// RESP2.
const int _sScanSimpleString = 1;
const int _sScanError = 2 << 1;
const int _sScanInteger = 2 << 2;
const int _sScanBulkString = 2 << 3;
const int _sScanArray = 2 << 4;
const int _sScanLength = 2 << 5;

// RESP3.
const int _sScanDouble = 2 << 6;
const int _sScanBoolean = 2 << 7;
const int _sScanBlobError = 2 << 8;
const int _sScanVerbatimString = 2 << 9;
const int _sScanMap = 2 << 10;
const int _sScanSet = 2 << 11;
const int _sScanAttribute = 2 << 12;
const int _sScanPush = 2 << 13;
const int _sScanHello = 2 << 14;
const int _sScanBigNumber = 2 << 15;
const int _sScanNull = 2 << 16;

enum ProtocolKind { resp, resp3 }

bool _isIdling(Scanner scanner) =>
    scanner._state &
        (_sScanBulkString |
            _sScanArray |
            _sScanInteger |
            _sScanSimpleString |
            _sScanError) ==
    0;

class Scanner {
  Scanner({@required this.protocolKind})
      : _state = 0,
        _crlf = 0,
        _accumulator = BytesBuilder(copy: false);

  final ProtocolKind protocolKind;

  Scanner _arrayScanner;
  List<Reply> _replies;
  Reply _reply; // scanned reply.
  int _state; // current scanning state, like scanning array, string, etc.
  int _crlf; // end symbols counter.
  int _length; // consumed length of the bulk string, or array.

  final BytesBuilder _accumulator;

  Reply get reply => _reply;

  String _takeString() => String.fromCharCodes(_accumulator.takeBytes());

  Uint8List _takeBytes() => _accumulator.takeBytes();

  int _takeInt() => int.tryParse(_takeString());

  double _takeDouble() {
    final value = _takeString();
    if (value == 'inf') {
      return double.infinity;
    } else if (value == '-inf') {
      return double.negativeInfinity;
    }

    // TODO: disallow scientific notion.
    return double.tryParse(value);
  }

  bool _scanLine(ByteReader reader) {
    while (reader.available() > 0) {
      final char = reader.takeOne();

      if (char == _cr || char == _lf) {
        _crlf++;

        if (char == _lf) {
          // Tail of each reply message must end with <CR><LF>
          // symbol sequence.
          assert(_crlf == 2);
          _crlf = 0;

          return true;
        }
      } else {
        _accumulator.addByte(char);
      }
    }

    return false;
  }

  bool _scanLength(ByteReader reader) {
    final done = _scanLine(reader);
    if (done) {
      final len = _takeInt();
      _length = len;
      _state ^= _sScanLength;

      _accumulator.clear();
    }

    return done;
  }

  bool _scanInteger(ByteReader reader) {
    final done = _scanLine(reader);
    if (done) {
      _reply = Reply<int>(
        kind: ReplyKind.integer,
        value: _takeInt(),
      );
      _state ^= _sScanInteger;

      _accumulator.clear();
    }

    return done;
  }

  bool _scanSimpleString(ByteReader reader) {
    final done = _scanLine(reader);
    if (done) {
      _reply = Reply<String>(
        kind: ReplyKind.simpleString,
        value: _takeString(),
      );
      _state ^= _sScanSimpleString;

      _accumulator.clear();
    }

    return done;
  }

  bool _scanError(ByteReader reader) {
    final done = _scanLine(reader);
    if (done) {
      _reply = Reply<String>(
        kind: ReplyKind.error,
        value: _takeString(),
      );
      _state ^= _sScanError;

      _accumulator.clear();
    }

    return done;
  }

  bool _scanBulkString(ByteReader reader) {
    if (_state & _sScanLength > 0) {
      if (!_scanLength(reader)) {
        return false;
      }
    }

    if (_length == -1) {
      if (protocolKind == ProtocolKind.resp) {
        _reply = Reply.nilReply;
        _state ^= _sScanBulkString;
        _length = null;

        _accumulator.clear();

        return true;
      }

      throw ProtocolException('Invalid bulk string size!');
    }

    while (reader.available() > 0) {
      if (_length == 0) {
        final byte = reader.takeOne();

        if (byte == _cr || byte == _lf) {
          _crlf++;

          if (byte == _lf) {
            assert(_crlf == 2);

            _reply = Reply<String>(
              kind: ReplyKind.bulkString,
              value: _takeString(),
            );
            _state ^= _sScanBulkString;
            _crlf = 0;
            _length = 0;

            _accumulator.clear();

            return true;
          }
        }
      }

      final size = min(_length, reader.available());
      _length -= size;

      _accumulator.add(reader.take(size));
    }

    return false;
  }

  bool _scanArray(ByteReader reader) {
    if (_state & _sScanLength > 0) {
      if (!_scanLength(reader)) {
        return false;
      }

      _replies = [];
    }

    if (_length == -1) {
      if (protocolKind == ProtocolKind.resp) {
        _reply = Reply.nilReply;
        _state ^= _sScanArray;
        _length = null;
        _replies = null;

        return true;
      }

      throw ProtocolException('Invalid array reply size!');
    }

    _arrayScanner ??= Scanner(protocolKind: protocolKind);

    while (_length > 0) {
      if (reader.available() == 0) {
        return false;
      }

      if (_isIdling(_arrayScanner)) {
        _arrayScanner._feed(reader);
      }

      if (!_arrayScanner.scan(reader)) {
        return false;
      }

      _replies.add(_arrayScanner.reply);
      _length--;
    }

    _reply = Reply<List<Reply>>(
      kind: ReplyKind.array,
      value: _replies,
    );

    _state ^= _sScanArray;
    _replies = null;
    _arrayScanner = null;
    _length = null;

    return true;
  }

  // RESP3
  // ===========================================================================

  bool _scanNull(ByteReader reader) {
    while (reader.available() > 0) {
      final char = reader.takeOne();
      if (char == _cr || char == _lf) {
        _crlf++;
        if (char == _lf) {
          assert(_crlf == 2);

          _reply = Reply.nilReply;
          _state ^= _sScanNull;

          return true;
        }
      }
    }

    return false;
  }

  bool _scanDouble(ByteReader reader) {
    final done = _scanLine(reader);
    if (done) {
      _reply = Reply<double>(kind: ReplyKind.double, value: _takeDouble());
      _state ^= _sScanDouble;

      _accumulator.clear();
    }

    return false;
  }

  bool _scanBoolean(ByteReader reader) {
    final done = _scanLine(reader);
    if (done) {
      final bytes = _takeBytes();
      if (bytes.lengthInBytes != 1) {
        throw ProtocolException('Malformed boolean reply!');
      }

      bool value;
      if (bytes[0] == 0x74 /* t */) {
        value = true;
      } else if (bytes[0] == 0x66 /* f */) {
        value = false;
      } else {
        throw ProtocolException('Malformed boolean reply!');
      }

      _reply = Reply<bool>(
        kind: ReplyKind.boolean,
        value: value,
      );
      _state ^= _sScanBoolean;

      _accumulator.clear();

      return true;
    }

    return false;
  }

  // ===========================================================================

  void _feed(ByteReader reader) {
    final char = reader.takeOne();

    if (char == signal_code.array) {
      _state |= _sScanArray | _sScanLength;
    } else if (char == signal_code.error) {
      _state |= _sScanError;
    } else if (char == signal_code.simpleString) {
      _state |= _sScanSimpleString;
    } else if (char == signal_code.bulkString) {
      _state |= _sScanBulkString | _sScanLength;
    } else if (char == signal_code.integer) {
      _state |= _sScanInteger;
    } else {
      if (protocolKind == ProtocolKind.resp3) {
        if (char == signal_code.nil) {
          _state |= _sScanNull;
        } else if (char == signal_code.double) {
          _state |= _sScanDouble;
        }
      }

      throw ProtocolException('Unknown reply type!');
    }
  }

  bool scan(ByteReader reader) {
    if (_isIdling(this)) {
      _feed(reader);
    }

    if (_state & _sScanSimpleString > 0) {
      return _scanSimpleString(reader);
    } else if (_state & _sScanError > 0) {
      return _scanError(reader);
    } else if (_state & _sScanInteger > 0) {
      return _scanInteger(reader);
    } else if (_state & _sScanBulkString > 0) {
      return _scanBulkString(reader);
    } else if (_state & _sScanArray > 0) {
      return _scanArray(reader);
    } else if (_state & _sScanNull > 0) {
      return _scanNull(reader);
    }

    throw StateError('Unable to scan reply!');
  }
}
