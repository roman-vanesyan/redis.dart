import 'dart:io' show BytesBuilder;
import 'dart:math' show min;

import 'package:redis/src/resp/byte_buffer.dart';
import 'package:redis/src/resp/protocol_exception.dart';
import 'package:redis/src/resp/token_type.dart';
import 'package:redis/src/resp/reply.dart';

const int _cr = 0x0d;
const int _lf = 0x0a;

class _State {
  static const int scanSimpleString = 1;
  static const int scanError = 2 << 1;
  static const int scanInteger = 2 << 2;
  static const int scanBulkString = 2 << 3;
  static const int scanArray = 2 << 4;
  static const int scanLength = 2 << 5;
}

class Scanner {
  Scanner()
      : _state = 0,
        _crlf = 0,
        _accumulator = BytesBuilder(copy: false);

  int _state;

  Scanner _arrayScanner;
  List<Reply> _replies;
  Reply _reply;
  int _crlf;
  int _length;

  BytesBuilder _accumulator;

  bool get idling =>
      _state &
          (_State.scanBulkString |
              _State.scanArray |
              _State.scanInteger |
              _State.scanSimpleString |
              _State.scanError) ==
      0;

  Reply get reply => _reply;

  String _getString() => String.fromCharCodes(_accumulator.takeBytes());

  int _getInt() => int.tryParse(_getString());

  bool _scanLine(ByteBuffer buffer) {
    while (buffer.available() > 0) {
      final byte = buffer.takeOne();

      switch (byte) {
        case _cr:
          _crlf++;
          break;

        case _lf:
          _crlf++;

          assert(_crlf == 2);

          _crlf = 0;

          return true;

        default:
          _accumulator.addByte(byte);
          break;
      }
    }

    return false;
  }

  bool _scanLength(ByteBuffer buffer) {
    final done = _scanLine(buffer);

    if (done) {
      final len = _getInt();

      _length = len;

      // Reset state
      _state ^= _State.scanLength;
      _accumulator.clear();
    }

    return done;
  }

  bool _scanInteger(ByteBuffer buffer) {
    final done = _scanLine(buffer);

    if (done) {
      _reply = IntegerReply(_getInt());

      // Reset states
      _state ^= _State.scanInteger;
      _accumulator.clear();
    }

    return done;
  }

  bool _scanSimpleString(ByteBuffer buffer) {
    final done = _scanLine(buffer);

    if (done) {
      _reply = SimpleStringReply(_getString());

      // Reset states
      _state ^= _State.scanSimpleString;
      _accumulator.clear();
    }

    return done;
  }

  bool _scanError(ByteBuffer buffer) {
    final done = _scanLine(buffer);

    if (done) {
      _reply = ErrorReply(_getString());

      // Reset states
      _state ^= _State.scanError;
      _accumulator.clear();
    }

    return done;
  }

  bool _scanBulkString(ByteBuffer buffer) {
    if (_length == null) {
      if (!_scanLength(buffer)) {
        return false;
      }
    }

    if (_length == -1) {
      _reply = NilReply();

      // Reset states
      _state ^= _State.scanBulkString;
      _length = null;
      _accumulator.clear();

      return true;
    }

    while (buffer.available() > 0) {
      if (_length == 0) {
        final byte = buffer.takeOne();

        if (byte == _cr) {
          _crlf++;
          continue;
        } else if (byte == _lf) {
          _crlf++;

          assert(_crlf == 2);

          _reply = BulkStringReply(_getString());

          // Reset state
          _state ^= _State.scanBulkString;
          _crlf = 0;
          _length = null;
          _accumulator.clear();

          return true;
        }
      }

      final size = min(_length, buffer.available());

      _accumulator.add(buffer.take(size));
      _length -= size;
    }

    return false;
  }

  bool _scanArray(ByteBuffer buffer) {
    if (_length == null) {
      if (!_scanLength(buffer)) {
        return false;
      }

      _replies = [];
    }

    if (_length == -1) {
      _reply = NilReply();

      // Reset state
      _state ^= _State.scanArray;
      _length = null;
      _replies = null;

      return true;
    }

    _arrayScanner ??= Scanner();

    while (_length > 0) {
      if (buffer.available() == 0) {
        return false;
      }

      if (_arrayScanner.idling) {
        _arrayScanner.feed(buffer.takeOne());
      }

      if (!_arrayScanner.scan(buffer)) {
        return false;
      }

      _replies.add(_arrayScanner.reply);
      _length--;
    }

    _reply = ArrayReply(_replies);

    // Reset state
    _state ^= _State.scanArray;
    _replies = null;
    _arrayScanner = null;
    _length = null;

    return true;
  }

  bool scan(ByteBuffer buffer) {
    if (_state & _State.scanSimpleString > 0) {
      return _scanSimpleString(buffer);
    } else if (_state & _State.scanError > 0) {
      return _scanError(buffer);
    } else if (_state & _State.scanInteger > 0) {
      return _scanInteger(buffer);
    } else if (_state & _State.scanBulkString > 0) {
      return _scanBulkString(buffer);
    } else if (_state & _State.scanArray > 0) {
      return _scanArray(buffer);
    }

    throw StateError('Uninitialized parser state, use `Scanner#feed`'
        'before calling to `Scanner#scan`!');
  }

  void feed(int tok) {
    switch (tok) {
      case TokenType.array:
        _state |= _State.scanArray | _State.scanLength;
        break;

      case TokenType.error:
        _state |= _State.scanError;
        break;

      case TokenType.simpleString:
        _state |= _State.scanSimpleString;
        break;

      case TokenType.bulkString:
        _state |= _State.scanBulkString | _State.scanLength;
        break;

      case TokenType.integer:
        _state |= _State.scanInteger;
        break;

      default:
        throw ProtocolException('Uknown reply type!');
    }
  }
}
