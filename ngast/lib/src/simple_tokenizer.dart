import 'package:charcode/charcode.dart';
import 'package:meta/meta.dart';
import 'package:string_scanner/string_scanner.dart';

import 'token/chars.dart';
import 'token/tokens.dart';

class NgSimpleTokenizer {
  @literal
  const factory NgSimpleTokenizer() = NgSimpleTokenizer._;

  const NgSimpleTokenizer._();

  Iterable<NgSimpleToken> tokenize(String template) sync* {
    var scanner = NgSimpleScanner(template);
    scanner.resetState();
    var token = scanner.scan();
    while (token.type != NgSimpleTokenType.eof) {
      yield token;
      token = scanner.scan();
    }
    yield token; // Explicitly yield the EOF token.
  }
}

class NgSimpleScanner {
  static bool matchesGroup(Match match, int group) =>
      match.group(group) != null;

  static final _allTextMatches = RegExp(r'([^\<]+)|(<!--)|(<)');
  static final _allElementMatches = RegExp(r'(\])|' //1  ]
      r'(\!)|' //2  !
      r'(\-)|' //3  -
      r'(\))|' //4  )
      r'(>)|' //5  >
      r'(\/)|' //6  /
      r'(\[)|' //7  [
      r'(\()|' //8  (
      r'([\s]+)|' //9 whitespace
      //10 any alphanumeric + '-' + '_' + ':'
      r'([a-zA-Z]([\w\_\-:])*[a-zA-Z0-9]?)|'
      r'("([^"\\]+|\\.)*"?)|' //12 closed double quote (includes group 13)
      r"('([^'\\]+|\\.)*'?)|" //14 closed single quote (includes group 15)
      r'(<)|' //16 <
      r'(=)|' //17 =
      r'(\*)|' //18 *
      r'(\#)|' //19 #
      r'(\.)|' //20 .
      r'(\%)|' //21 %
      r'(\\)|' //22 \
      r'(\@)'); //23 @
  static final _commentEnd = RegExp('-->');
  static final _mustaches = RegExp(r'({{)|(}})');
  static final _newline = RegExp('\n');
  static final _escape = RegExp(r'&#([0-9]{2,4});|' // 1 decimal
      '&#x([0-9A-Fa-f]{2,4});|' // 2 hex
      '&([a-zA-Z]+);'); // 3 named

  static final _doctypeBegin = RegExp(r'(<!DOCTYPE)|(>)');
  static final _gt = RegExp(r'>');

  final StringScanner _scanner;
  _NgSimpleScannerState _state = _NgSimpleScannerState.doctype;

  factory NgSimpleScanner(String html, {sourceUrl}) {
    return NgSimpleScanner._(StringScanner(html, sourceUrl: sourceUrl));
  }

  NgSimpleScanner._(this._scanner);

  NgSimpleToken scan() {
    switch (_state) {
      case _NgSimpleScannerState.comment:
        return scanComment();
      case _NgSimpleScannerState.commentEnd:
        return scanCommentEnd();
      case _NgSimpleScannerState.doctype:
        return scanDoctype();
      case _NgSimpleScannerState.element:
        return scanElement();
      case _NgSimpleScannerState.text:
        return scanText();
      case _NgSimpleScannerState.interpolation:
        return scanInterpolation();
    }
  }

  NgSimpleToken scanComment() {
    var offset = _scanner.position;
    while (true) {
      if (_scanner.peekChar() == $dash &&
          _scanner.peekChar(1) == $dash &&
          _scanner.peekChar(2) == $gt) {
        break;
      }
      if (_scanner.position < _scanner.string.length) {
        _scanner.position++;
      }
      if (_scanner.isDone) {
        _state = _NgSimpleScannerState.text;
        var substring = _scanner.string.substring(offset);
        return _newTextToken(offset, substring);
      }
    }
    _state = _NgSimpleScannerState.commentEnd;
    return _newTextToken(offset, _scanner.substring(offset));
  }

  NgSimpleToken scanCommentEnd() {
    var offset = _scanner.position;
    _scanner.scan(_commentEnd);
    _state = _NgSimpleScannerState.text;
    return NgSimpleToken.commentEnd(offset);
  }

  NgSimpleToken scanDoctype() {
    var offset = _scanner.position;
    if (_scanner.isDone) {
      return NgSimpleToken.eof(offset);
    }
    _state = _NgSimpleScannerState.text;

    if (_scanner.scan(_doctypeBegin)) {
      // DOCTYPE declaration exists
      var text = _scanner.string.substring(_scanner.position);
      var endOffset = _scanner.string.length;

      var match = _gt.firstMatch(text);
      if (match != null) {
        endOffset = _scanner.position + match.end;
      }
      _scanner.position = endOffset;
      return _newTextToken(
          offset, _scanner.string.substring(offset, endOffset));
    }
    return scanText();
  }

  NgSimpleToken scanElement() {
    var offset = _scanner.position;
    if (_scanner.isDone) {
      return NgSimpleToken.eof(offset);
    }
    if (_scanner.scan(_allElementMatches)) {
      var match = _scanner.lastMatch!;
      if (matchesGroup(match, 1)) {
        return NgSimpleToken.closeBracket(offset);
      }
      if (matchesGroup(match, 2)) {
        return NgSimpleToken.bang(offset);
      }
      if (matchesGroup(match, 3)) {
        return NgSimpleToken.dash(offset);
      }
      if (matchesGroup(match, 4)) {
        if (_scanner.peekChar() == $close_bracket) {
          _scanner.position++;
          return NgSimpleToken.closeBanana(offset);
        }
        return NgSimpleToken.closeParen(offset);
      }
      if (matchesGroup(match, 5)) {
        _state = _NgSimpleScannerState.text;
        return NgSimpleToken.tagEnd(offset);
      }
      if (matchesGroup(match, 6)) {
        if (_scanner.peekChar() == $gt) {
          _scanner.position++;
          _state = _NgSimpleScannerState.text;
          return NgSimpleToken.voidCloseTag(offset);
        }
        return NgSimpleToken.forwardSlash(offset);
      }
      if (matchesGroup(match, 7)) {
        if (_scanner.peekChar() == $open_paren) {
          _scanner.position++;
          return NgSimpleToken.openBanana(offset);
        }
        return NgSimpleToken.openBracket(offset);
      }
      if (matchesGroup(match, 8)) {
        return NgSimpleToken.openParen(offset);
      }
      if (matchesGroup(match, 9)) {
        return NgSimpleToken.whitespace(offset, _scanner.substring(offset));
      }
      if (matchesGroup(match, 10)) {
        var s = _scanner.substring(offset);
        return NgSimpleToken.identifier(offset, s);
      }
      if (matchesGroup(match, 12)) {
        var lexeme = _scanner.substring(offset).replaceAll(r'\"', '"');
        var isClosed = (lexeme.length > 1) && lexeme[lexeme.length - 1] == '"';
        return NgSimpleQuoteToken.doubleQuotedText(offset, lexeme, isClosed);
      }
      if (matchesGroup(match, 14)) {
        var lexeme = _scanner.substring(offset).replaceAll(r"\'", "'");
        var isClosed = (lexeme.length > 1) && lexeme[lexeme.length - 1] == "'";
        return NgSimpleQuoteToken.singleQuotedText(offset, lexeme, isClosed);
      }
      if (matchesGroup(match, 16)) {
        if (_scanner.peekChar() == $exclamation &&
            _scanner.peekChar(1) == $dash &&
            _scanner.peekChar(2) == $dash) {
          _state = _NgSimpleScannerState.comment;
          _scanner.position = offset + 4;
          return NgSimpleToken.commentBegin(offset);
        }
        if (_scanner.peekChar() == $slash) {
          _scanner.position++;
          return NgSimpleToken.closeTagStart(offset);
        }
        return NgSimpleToken.openTagStart(offset);
      }
      if (matchesGroup(match, 17)) {
        return NgSimpleToken.equalSign(offset);
      }
      if (matchesGroup(match, 18)) {
        return NgSimpleToken.star(offset);
      }
      if (matchesGroup(match, 19)) {
        return NgSimpleToken.hash(offset);
      }
      if (matchesGroup(match, 20)) {
        return NgSimpleToken.period(offset);
      }
      if (matchesGroup(match, 21)) {
        return NgSimpleToken.percent(offset);
      }
      if (matchesGroup(match, 22)) {
        return NgSimpleToken.backSlash(offset);
      }
      if (matchesGroup(match, 23)) {
        return NgSimpleToken.atSign(offset);
      }
    }
    return NgSimpleToken.unexpectedChar(
        offset, String.fromCharCode(_scanner.readChar()));
  }

  NgSimpleToken scanText() {
    var offset = _scanner.position;
    if (_scanner.isDone) {
      return NgSimpleToken.eof(offset);
    }
    if (_scanner.scan(_allTextMatches)) {
      var match = _scanner.lastMatch!;
      if (matchesGroup(match, 1)) {
        var text = _scanner.substring(offset);
        var mustacheMatch = _mustaches.firstMatch(text);

        // Mustache exists
        if (mustacheMatch != null) {
          var mustacheStart = offset + mustacheMatch.start;

          // Mustache exists, but text precedes it - return the text first.
          if (mustacheStart != offset) {
            _scanner.position = mustacheStart;
            return _newTextToken(
                offset, _scanner.substring(offset, mustacheStart));
          }

          // Mustache exists and text doesn't precede it - return mustache.
          _scanner.position = offset + mustacheMatch.end;
          if (matchesGroup(mustacheMatch, 1)) {
            _state = _NgSimpleScannerState.interpolation;
            return NgSimpleToken.mustacheBegin(mustacheStart);
          }
          if (matchesGroup(mustacheMatch, 2)) {
            return NgSimpleToken.mustacheEnd(mustacheStart);
          }
        }
        // Mustache doesn't exist; simple text.
        return _newTextToken(offset, text);
      }
      if (matchesGroup(match, 2)) {
        _state = _NgSimpleScannerState.comment;
        return NgSimpleToken.commentBegin(offset);
      }
      if (matchesGroup(match, 3)) {
        if (_scanner.peekChar() == $slash) {
          _scanner.position++;
          _state = _NgSimpleScannerState.element;
          return NgSimpleToken.closeTagStart(offset);
        }
        _state = _NgSimpleScannerState.element;
        return NgSimpleToken.openTagStart(offset);
      }
    }
    return NgSimpleToken.unexpectedChar(
        offset, String.fromCharCode(_scanner.readChar()));
  }

  NgSimpleToken scanInterpolation() {
    // Need a separate scan state to ensure that '<' isn't
    // automatically mistaken as a element start. It can be a less than sign
    // used in interpolation expression.
    var offset = _scanner.position;
    if (_scanner.peekChar() == null) {
      return NgSimpleToken.eof(offset);
    }
    var text = _scanner.string.substring(offset);
    var match = _mustaches.firstMatch(text);

    // No matches found, meaning that mustache continues until EOF,
    // or until first newline found.
    if (match == null) {
      var newlineMatch = _newline.firstMatch(text);

      // New line encountered before EOF.
      if (newlineMatch != null) {
        var newlineStart = offset + newlineMatch.start;
        var newlineEnd = offset + newlineMatch.end;

        // If text precedes it, return text.
        if (newlineStart != offset) {
          _scanner.position = newlineStart;
          return _newTextToken(offset, _scanner.substring(offset));
        }
        // Otherwise, return the newline and switch state back to text.
        _state = _NgSimpleScannerState.text;
        _scanner.position = newlineEnd;
        return NgSimpleToken.whitespace(offset, _scanner.substring(offset));
      }

      // Simply scan text until EOF hit.
      _scanner.position = offset + text.length;
      _state = _NgSimpleScannerState.text;
      return _newTextToken(offset, _scanner.substring(offset));
    }

    var matchStartOffset = offset + match.start;

    // Match exists, but text precedes it - return the text first.
    if (matchStartOffset != offset) {
      _scanner.position = matchStartOffset;
      return _newTextToken(offset, _scanner.substring(offset));
    }

    _scanner.position = offset + match.end;
    if (matchesGroup(match, 1)) {
      return NgSimpleToken.mustacheBegin(matchStartOffset);
    }
    if (matchesGroup(match, 2)) {
      _state = _NgSimpleScannerState.text;
      return NgSimpleToken.mustacheEnd(matchStartOffset);
    }
    return NgSimpleToken.unexpectedChar(
        offset, String.fromCharCode(_scanner.readChar()));
  }

  void resetState() {
    _state = _NgSimpleScannerState.doctype;
  }

  NgSimpleToken _newTextToken(int offset, String lexme) =>
      NgSimpleToken.decodedText(offset, _unEscapeText(lexme), lexme.length);

  String _unEscapeText(String string) {
    return string.replaceAllMapped(_escape, (match) {
      // decimal
      if (matchesGroup(match, 1)) {
        return String.fromCharCode(int.parse(match.group(1)!));
      }
      // hex
      if (matchesGroup(match, 2)) {
        return String.fromCharCode(int.parse(match.group(2)!, radix: 16));
      }
      // named
      if (matchesGroup(match, 3)) {
        return namedEntities[match.group(3)] ?? match.group(3)!;
      }

      return '';
    });
  }
}

enum _NgSimpleScannerState {
  doctype,
  text,
  element,
  comment,
  commentEnd,
  interpolation,
}
