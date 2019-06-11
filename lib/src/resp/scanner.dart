import 'dart:io' show BytesBuilder;
import 'dart:math' show min;

import 'package:redis/src/resp/byte_buffer.dart';
import 'package:redis/src/resp/protocol_exception.dart';
import 'package:redis/src/resp/token_type.dart';
import 'package:redis/src/resp/reply.dart';

const int _cr = 0x0d;
const int _lf = 0x0a;

class _State {
  _State() : _state = 0;

  int _state;

  bool contains(int state) => _state & state > 0;

  void set(int state) => _state |= state;

  void unset(int state) {
    if (contains(state)) _state ^= state;
  }

  static const int scanSimpleString = 1;
  static const int scanError = 2 << 1;
  static const int scanInteger = 2 << 2;
  static const int scanBulkString = 2 << 3;
  static const int scanArray = 2 << 4;
  static const int scanBulkStringLength = 2 << 5;
  static const int scanArrayLength = 2 << 6;
}

class Scanner {
  Scanner()
      : _state = _State(),
        _crlf = 0,
        _accumulator = BytesBuilder(copy: false);

  _State _state;

  Scanner _arrayScanner;
  List<Reply> _replies;
  Reply _reply;
  int _crlf;
  int _bulkStringLength;
  int _arrayLength;

  BytesBuilder _accumulator;

  bool get idling => !_state.contains(_State.scanBulkString |
      _State.scanArray |
      _State.scanInteger |
      _State.scanSimpleString |
      _State.scanError);

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

      if (_state.contains(_State.scanArrayLength)) {
        _arrayLength = len;

        // Reset state
        _state.unset(_State.scanArrayLength);
      } else if (_state.contains(_State.scanBulkStringLength)) {
        _bulkStringLength = len;

        // Reset state
        _state.unset(_State.scanBulkStringLength);
      }

      // Reset state
      _accumulator.clear();
    }

    return done;
  }

  bool _scanInteger(ByteBuffer buffer) {
    final done = _scanLine(buffer);

    if (done) {
      _reply = IntegerReply(_getInt());

      // Reset states
      _state.unset(_State.scanInteger);
    }

    return done;
  }

  bool _scanSimpleString(ByteBuffer buffer) {
    final done = _scanLine(buffer);

    if (done) {
      _reply = SimpleStringReply(_getString());

      // Reset states
      _state.unset(_State.scanSimpleString);
      _accumulator.clear();
    }

    return done;
  }

  bool _scanError(ByteBuffer buffer) {
    final done = _scanLine(buffer);

    if (done) {
      _reply = ErrorReply(_getString());

      // Reset states
      _state.unset(_State.scanError);
      _accumulator.clear();
    }

    return done;
  }

  bool _scanBulkString(ByteBuffer buffer) {
    if (_bulkStringLength == null) {
      if (!_scanLength(buffer)) {
        return false;
      }
    }

    if (_bulkStringLength == -1) {
      _reply = NilReply();

      // Reset states
      _state.unset(_State.scanBulkString);
      _bulkStringLength = null;
      _accumulator.clear();

      return true;
    }

    while (buffer.available() > 0) {
      if (_bulkStringLength == 0) {
        final byte = buffer.takeOne();

        if (byte == _cr) {
          _crlf++;
          continue;
        } else if (byte == _lf) {
          _crlf++;

          assert(_crlf == 2);

          _reply = BulkStringReply(_getString());

          // Reset state
          _state.unset(_State.scanBulkString);
          _crlf = 0;
          _bulkStringLength = null;
          _accumulator.clear();

          return true;
        }
      }

      final size = min(_bulkStringLength, buffer.available());
      _accumulator.add(buffer.take(size));
      _bulkStringLength -= size;
    }

    return false;
  }

  bool _scanArray(ByteBuffer buffer) {
    if (_arrayLength == null) {
      if (!_scanLength(buffer)) {
        return false;
      }

      _replies = [];
    }

    if (_arrayLength == -1) {
      _reply = NilReply();

      // Reset state
      _state.unset(_State.scanArray);
      _arrayLength = null;
      _replies = null;

      return true;
    }

    _arrayScanner ??= Scanner();

    while (_arrayLength > 0) {
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
      _arrayLength--;
    }

    _reply = ArrayReply(_replies);

    // Reset state
    _state.unset(_State.scanArray);
    _replies = null;
    _arrayScanner = null;
    _arrayLength = null;

    return true;
  }

  bool scan(ByteBuffer buffer) {
    if (_state.contains(_State.scanSimpleString)) {
      return _scanSimpleString(buffer);
    } else if (_state.contains(_State.scanError)) {
      return _scanError(buffer);
    } else if (_state.contains(_State.scanInteger)) {
      return _scanInteger(buffer);
    } else if (_state.contains(_State.scanBulkString)) {
      return _scanBulkString(buffer);
    } else if (_state.contains(_State.scanArray)) {
      return _scanArray(buffer);
    }

    throw ProtocolException('Uknown reply type!');
  }

  void feed(int tok) {
    switch (tok) {
      case TokenType.array:
        _state.set(_State.scanArray | _State.scanArrayLength);
        break;

      case TokenType.error:
        _state.set(_State.scanError);
        break;

      case TokenType.simpleString:
        _state.set(_State.scanSimpleString);
        break;

      case TokenType.bulkString:
        _state.set(_State.scanBulkString | _State.scanBulkStringLength);
        break;

      case TokenType.integer:
        _state.set(_State.scanInteger);
        break;
    }
  }
}
