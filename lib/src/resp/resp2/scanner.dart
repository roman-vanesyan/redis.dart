import 'dart:io' show BytesBuilder;
import 'dart:math' show min;

import '../byte_reader.dart';
import 'protocol_exception.dart';
import 'reply.dart';
import 'signal_char.dart' as signal_code;

const int _cr = 0x0d; // <CR>
const int _lf = 0x0a; // <LF>

const int _sScanSimpleString = 1;
const int _sScanError = 2 << 1;
const int _sScanInteger = 2 << 2;
const int _sScanBulkString = 2 << 3;
const int _sScanArray = 2 << 4;
const int _sScanLength = 2 << 5;

bool _isIdling(Scanner scanner) =>
    scanner._state &
        (_sScanBulkString |
            _sScanArray |
            _sScanInteger |
            _sScanSimpleString |
            _sScanError) ==
    0;

class Scanner {
  Scanner()
      : _state = 0,
        _crlf = 0,
        _accumulator = BytesBuilder(copy: false);

  int _state;

  Scanner _arrayScanner;
  List<Reply> _replies;
  Reply _reply;
  int _crlf; // end symbols counter.
  int _length;

  final BytesBuilder _accumulator;

  Reply get reply => _reply;

  String _getString() => String.fromCharCodes(_accumulator.takeBytes());

  int _getInt() => int.tryParse(_getString());

  bool _scanLine(ByteReader reader) {
    while (reader.available() > 0) {
      final byte = reader.takeOne();

      if (byte == _cr || byte == _lf) {
        _crlf++;
        if (byte == _lf) {
          // Asserts tail of each reply message must end with <CR><LF>
          // symbol sequence.
          assert(_crlf == 2);
          _crlf = 0;

          return true;
        }
      } else {
        _accumulator.addByte(byte);
      }
    }

    return false;
  }

  bool _scanLength(ByteReader reader) {
    final done = _scanLine(reader);

    if (done) {
      final len = _getInt();

      _length = len;

      _state ^= _sScanLength;
      _accumulator.clear();
    }

    return done;
  }

  bool _scanInteger(ByteReader reader) {
    final done = _scanLine(reader);

    if (done) {
      _reply = IntegerReply(_getInt());
      _state ^= _sScanInteger;
      _accumulator.clear();
    }

    return done;
  }

  bool _scanSimpleString(ByteReader reader) {
    final done = _scanLine(reader);

    if (done) {
      _reply = SimpleStringReply(_getString());
      _state ^= _sScanSimpleString;
      _accumulator.clear();
    }

    return done;
  }

  bool _scanError(ByteReader reader) {
    final done = _scanLine(reader);

    if (done) {
      _reply = ErrorReply(_getString());
      _state ^= _sScanError;
      _accumulator.clear();
    }

    return done;
  }

  bool _scanBulkString(ByteReader reader) {
    if (_length == null) {
      if (!_scanLength(reader)) {
        return false;
      }
    }

    if (_length == -1) {
      _reply = NilReply();
      _state ^= _sScanBulkString;
      _length = null;
      _accumulator.clear();

      return true;
    }

    while (reader.available() > 0) {
      if (_length == 0) {
        final byte = reader.takeOne();

        if (byte == _cr) {
          _crlf++;
          continue;
        } else if (byte == _lf) {
          _crlf++;

          assert(_crlf == 2);

          _reply = BulkStringReply(_getString());

          _state ^= _sScanBulkString;
          _crlf = 0;
          _length = null;
          _accumulator.clear();

          return true;
        }
      }

      final size = min(_length, reader.available());

      _accumulator.add(reader.take(size));
      _length -= size;
    }

    return false;
  }

  bool _scanArray(ByteReader reader) {
    if (_length == null) {
      if (!_scanLength(reader)) {
        return false;
      }

      _replies = [];
    }

    if (_length == -1) {
      _reply = NilReply();

      _state ^= _sScanArray;
      _length = null;
      _replies = null;

      return true;
    }

    _arrayScanner ??= Scanner();

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

    _reply = ArrayReply(_replies);

    _state ^= _sScanArray;
    _replies = null;
    _arrayScanner = null;
    _length = null;

    return true;
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
    }

    throw StateError('Unable to scan reply!');
  }

  void _feed(ByteReader reader) {
    final char = reader.takeOne();

    switch (char) {
      case signal_code.array:
        _state |= _sScanArray | _sScanLength;
        break;

      case signal_code.error:
        _state |= _sScanError;
        break;

      case signal_code.simpleString:
        _state |= _sScanSimpleString;
        break;

      case signal_code.bulkString:
        _state |= _sScanBulkString | _sScanLength;
        break;

      case signal_code.integer:
        _state |= _sScanInteger;
        break;

      default:
        throw ProtocolException('Unknown reply type!');
    }
  }
}
