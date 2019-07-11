import 'package:meta/meta.dart' show required;

import 'package:redis/src/executor.dart' show Executor;
import 'package:redis/src/utils.dart' show isOk;

class _Command {
  static const String append = r'APPEND';
  static const String bitcount = r'BITCOUNT';
  static const String bitfield = r'BITFIELD';
  static const String bitop = r'BITOP';
  static const String bitops = r'BITOPS';
  static const String decr = r'DECR';
  static const String decrby = r'DECRBY';
  static const String get = r'GET';
  static const String getbit = r'GETBIT';
  static const String getrange = r'GETRANGE';
  static const String getset = r'GETSET';
  static const String incr = r'INCR';
  static const String incrby = r'INCRBY';
  static const String incrbyfloat = r'INCRBYFLOAT';
  static const String mget = r'MGET';
  static const String mset = r'MSET';
  static const String msetnx = r'MSETNX';
  static const String psetex = r'PSETEX';
  static const String set = r'SET';
  static const String setbit = r'SETBIT';
  static const String setex = r'SETEX';
  static const String setnx = r'SETNX';
  static const String setrange = r'SETRANGE';
  static const String strlen = r'STRLEN';
}

/// [BitOp] an bitwise operation wrapper used for [StringsContext.bitop].
///
/// See https://redis.io/commands/bitop
class BitOp {
  const BitOp._(this.value);

  final String value;

  static const BitOp and = BitOp._(r'AND');
  static const BitOp or = BitOp._(r'OR');
  static const BitOp xor = BitOp._(r'XOR');
  static const BitOp not = BitOp._(r'NOT');
}

class BitFieldOpType {
  const BitFieldOpType._(this.value);

  final String value;

  static const BitFieldOpType set = BitFieldOpType._(r'SET');
  static const BitFieldOpType incrby = BitFieldOpType._(r'INCRBY');
  static const BitFieldOpType get = BitFieldOpType._(r'GET');

  @override
  String toString() => value;
}

class BitFieldOverflowType {
  const BitFieldOverflowType._(this.value);

  final String value;

  static const BitFieldOverflowType wrap = BitFieldOverflowType._(r'WRAP');
  static const BitFieldOverflowType sat = BitFieldOverflowType._(r'SAT');
  static const BitFieldOverflowType fail = BitFieldOverflowType._(r'FAIL');

  @override
  String toString() => 'OVERFLOW $value';
}

class BitFieldOp {
  const BitFieldOp(
      {@required this.opType,
      @required this.type,
      @required this.offset,
      this.value,
      this.overflow})
      : assert(opType != BitFieldOpType.incrby && overflow != null),
        assert(opType == BitFieldOpType.get && value != null);

  final BitFieldOpType opType;
  final String type;
  final int offset;
  final String value;
  final BitFieldOverflowType overflow;
}

/// Mixin implements string related operation methods.
class StringsContext {
  StringsContext(this._executor);

  final Executor _executor;

  /// Appends the [value] to the end of the string found by [key], otherwise,
  /// if [key] does not exists it is created and set as the [value].
  ///
  /// Returns length of the string after the append operation.
  ///
  /// See https://redis.io/commands/append
  Future<int> append(String key, String value) =>
      _executor.exec<int>(_Command.append, [key, value]);

  /// Count the number of set bits (population counting) in a string.
  ///
  /// Returns number of bits set to `1`.
  ///
  /// See https://redis.io/commands/bitcount
  Future<int> bitcount(String key, [int start, int end]) {
    assert((start != null && end == null) || (start == null && end != null));

    return _executor.exec(_Command.bitcount,
        [if (start != null) start.toString(), if (end != null) end.toString()]);
  }

  /// See https://redis.io/commands/bitfield
  Future<void> bitfield(String key, {Iterable<BitFieldOp> operations}) {
    final args = <String>[];

    for (final op in operations) {
      args.add(op.opType.toString());
      args.add(op.offset.toString());
      if (op.value != null) args.add(op.value);
      if (op.overflow != null) args.add(op.overflow.toString());
    }

    return _executor.exec(_Command.bitfield, [key, ...args]);
  }

  /// Perform a bitwise operation between multiple [src] keys and store the
  /// result in [dest] key.
  ///
  /// See https://redis.io/commands/bitop
  Future<bool> bitop(BitOp op, String dest, Iterable<String> src) async {
    assert(src.isNotEmpty);

    final res = await _executor.exec<String>(_Command.bitop, [
      op.value,
      dest,
      ...src,
    ]);

    return isOk(res);
  }

  /// See https://redis.io/commands/bitops
  Future<int> bitops(String key, int start, int end) =>
      _executor.exec(_Command.bitops, [
        key,
        start.toString(),
        end.toString(),
      ]);

  /// See https://redis.io/commands/decr
  Future<int> decr(String key) => _executor.exec(_Command.decr, [key]);

  /// See https://redis.io/commands/decrby
  Future<int> decrby(String key, int value) =>
      _executor.exec(_Command.decrby, [key, value.toString()]);

  /// Gets the value of [key].
  ///
  /// Returns value stored under the [key], otherwise, if [key] does not exist
  /// `null` is returned.
  ///
  /// See https://redis.io/commands/get
  Future<String> get(String key) => _executor.exec(_Command.get, [key]);

  /// Returns the bit value at [offset] in the value stored at [key].
  ///
  /// See https://redis.io/commands/getbit
  Future<int> getbit(String key, int offset) =>
      _executor.exec(_Command.getbit, [
        key,
        offset.toString(),
      ]);

  /// See https://redis.io/commands/getrange
  Future<String> getrange(String key, int start, int end) =>
      _executor.exec(_Command.getrange, [
        key,
        start.toString(),
        end.toString(),
      ]);

  /// Sets [key] to [value] and returns old value stored at [key].
  ///
  /// See https://redis.io/commands/getset
  Future<String> getset(String key, String value) =>
      _executor.exec(_Command.getset, [key, value]);

  /// See https://redis.io/commands/incr
  Future<int> incr(String key) => _executor.exec(_Command.incr, [key]);

  /// Increments the number stored at [key] by [value].
  ///
  /// Returns the value after the incrementation.
  ///
  /// See https://redis.io/commands/incrby
  Future<int> incrby(String key, int value) =>
      _executor.exec(_Command.incrby, [key, value.toString()]);

  /// See https://redis.io/commands/incrbyfloat
  Future<double> incrbyfloat(String key, double value) async {
    final result = await _executor
        .exec<String>(_Command.incrbyfloat, [key, value.toString()]);

    return double.parse(result);
  }

  /// Returns the values of all specified [keys].
  ///
  /// For every key that does not hold a string value or does not exist,
  /// `null` is set ordinally.
  ///
  /// See https://redis.io/commands/mget
  Future<List<String>> mget(List<String> keys) =>
      _executor.exec(_Command.mget, [...keys]);

  /// Sets keys to their respective values; if any key is already presented
  /// the value is overridden with current one.
  ///
  /// See [StringsContext.msetnx] if values should not be overridden for any
  /// existing key.
  ///
  /// See https://redis.io/commands/mset
  Future<bool> mset(Map<String, String> kv) async {
    final args = List<String>(kv.length);
    int c = 0;

    kv.forEach((k, v) {
      args
        ..[c++] = k
        ..[c++] = v;
    });

    final result = await _executor.exec<String>(_Command.mset, args);

    return isOk(result);
  }

  /// See https://redis.io/commands/msetnx
  Future<bool> msetnx(Map<String, String> kv) async {
    final args = List<String>(kv.length);
    int c = 0;

    kv.forEach((k, v) {
      args
        ..[c++] = k
        ..[c++] = v;
    });

    final result = await _executor.exec<String>(_Command.msetnx, args);

    return isOk(result);
  }

  /// [psetex] works exactly like [setex] with the difference that the
  /// expiration time is set in milliseconds rather than seconds.
  ///
  /// See https://redis.io/commands/psetex
  Future<bool> psetex(String key, String value, Duration expiresIn) async {
    final res = await _executor.exec<String>(_Command.psetex, [
      key,
      expiresIn.inMilliseconds.toString(),
      value,
    ]);

    return isOk(res);
  }

  /// See https://redis.io/commands/set
  Future<bool> set(String key, String value,
      {Duration expiresIn,
      bool createOnly = false,
      bool replaceOnly = false}) async {
    assert(createOnly && replaceOnly);

    final res = await _executor.exec<String>(_Command.set, [
      key,
      value,
      if (expiresIn != null) ...['PX', expiresIn.inMilliseconds.toString()],
      if (createOnly) 'NX',
      if (replaceOnly) 'XX',
    ]);

    return isOk(res);
  }

  /// Sets or clears the bit at [offset] in the string value stored at [key].
  ///
  /// See https://redis.io/commands/setbit
  Future<int> setbit(String key, int bit, int offset) {
    assert(bit == 0 || bit == 1);
    assert(!offset.isNegative);

    return _executor.exec(_Command.setbit, [
      key.toString(),
      offset.toString(),
      bit.toString(),
    ]);
  }

  /// Set [key] to hold [value] and set [key] to timeout in [expiresIn].
  ///
  /// See https://redis.io/commands/setex
  Future<bool> setex(String key, String value, Duration expiresIn) async {
    final res = await _executor.exec<String>(_Command.setex, [
      key,
      value,
      expiresIn.inSeconds.toString(),
    ]);

    return isOk(res);
  }

  /// Sets [key] to hold [value] if [key] does not exist.
  ///
  /// See https://redis.io/commands/setnx
  Future<bool> setnx(String key, String value) async {
    final result = await _executor.exec<int>(_Command.setnx, [key, value]);

    return result == 1;
  }

  /// See https://redis.io/commands/setrange
  Future<String> setrange(String key, int offset, String value) =>
      _executor.exec(_Command.setrange, [
        key,
        offset.toString(),
        value,
      ]);

  /// Returns the length of the string value stored at the [key].
  ///
  /// See https://redis.io/commands/strlen
  Future<int> strlen(String key) async =>
      _executor.exec(_Command.strlen, [key]);
}
