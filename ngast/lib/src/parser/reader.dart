import 'dart:collection';

import 'package:source_span/source_span.dart';

import '../token/tokens.dart';

/// A narrow interface for reading tokens from a series of tokens.
/// Can only move forward within token iterable.
///
/// Not compatible with error recovery.
class NgTokenReader<T> {
  final Iterator<NgBaseToken<Object>> _iterator;

  NgBaseToken<Object>? _peek;

  factory NgTokenReader(
      SourceFile? source, Iterable<NgBaseToken<Object>> tokens) {
    return NgTokenReader._(source, tokens.iterator);
  }

  NgTokenReader._(SourceFile? source, this._iterator);

  /// Returns the next token, if any, otherwise `null`.
  NgBaseToken<Object>? next() {
    if (_peek != null) {
      var token = _peek;
      _peek = null;
      return token;
    }
    return _iterator.moveNext() ? _iterator.current : null;
  }

  /// Returns the next token without incrementing.
  /// Returns null otherwise.
  NgBaseToken<Object>? peek() => _peek = next();

  /// Returns the next token type without incrementing.
  /// Returns null otherwise.
  T? peekType() {
    _peek = next();
    if (_peek != null) {
      return _peek!.type as T;
    }
    return null;
  }

  /// Returns whether the current token is of [type].
  bool when(T type) => _iterator.current.type == type;

  /// Returns whether there is any more tokens to return.
  bool get isDone {
    if (_peek != null) {
      return false;
    }
    if (peek() == null) {
      return true;
    }
    return false;
  }
}

/// A more advanced interface for reading tokens from a series of tokens.
/// Can move forward within iterable of Tokens, and put tokens back.
///
/// Compatible with Error Recovery.
class NgTokenReversibleReader<T> extends NgTokenReader<T> {
  final Queue<NgBaseToken<Object>> _seen = Queue<NgBaseToken<Object>>();

  factory NgTokenReversibleReader(
    SourceFile? source,
    Iterable<NgBaseToken<Object>> tokens,
  ) {
    return NgTokenReversibleReader._(source, tokens.iterator);
  }

  NgTokenReversibleReader._(
    super.source,
    super.iterator,
  ) : super._();

  /// Scans forward for the next peek type that isn't ignoreType
  /// For example, `peekTypeIgnoringType(whitespace)` will peek
  /// for the next type that isn't whitespace.
  /// Returns `null` if there are no further types aside from ignoreType
  /// or iterator is empty.
  T peekTypeIgnoringType(T ignoreType) {
    var buffer = Queue<NgBaseToken<Object>>();

    peek();
    while (_peek != null && _peek!.type == ignoreType) {
      buffer.add(_peek!);
      _peek = null;
      peek();
    }

    var returnType = (_peek == null) ? null : _peek!.type;
    if (_peek != null) {
      buffer.add(_peek!);
      _peek = null;
    }
    _seen.addAll(buffer);

    return returnType as T;
  }

  @override
  NgBaseToken<Object>? next() {
    if (_peek != null) {
      var token = _peek;
      _peek = null;
      return token;
    } else if (_seen.isNotEmpty) {
      return _seen.removeFirst();
    }
    return _iterator.moveNext() ? _iterator.current : null;
  }

  NgBaseToken<Object> putBack(NgBaseToken<Object> token) {
    if (_peek != null) {
      _seen.addFirst(_peek!);
      _peek = token;
      return _peek!;
    } else {
      _peek = token;
      return _peek!;
    }
  }
}
