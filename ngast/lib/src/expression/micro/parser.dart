import 'package:meta/meta.dart';

import '../../ast.dart';
import '../../exception_handler/exception_handler.dart';
import 'ast.dart';
import 'lexer.dart';
import 'token.dart';

class NgMicroParser {
  @literal
  const factory NgMicroParser() = NgMicroParser._;

  const NgMicroParser._();

  NgMicroAst parse(
    String directive,
    String? expression,
    int? expressionOffset, {
    required String sourceUrl,
    TemplateAst? origin,
  }) {
    var paddedExpression = ' ' * expressionOffset! + expression!;
    var tokens = const NgMicroLexer().tokenize(paddedExpression).iterator;
    return _RecursiveMicroAstParser(
      directive,
      expressionOffset,
      expression.length,
      tokens,
      origin,
    ).parse();
  }
}

class _RecursiveMicroAstParser {
  final String _directive;
  final int? _expressionOffset;
  final int? _expressionLength;
  // final String _sourceUrl;
  final Iterator<NgMicroToken> _tokens;

  final letBindings = <LetBindingAst>[];
  final properties = <PropertyAst>[];

  final TemplateAst? _origin;

  _RecursiveMicroAstParser(
    this._directive,
    this._expressionOffset,
    this._expressionLength,
    this._tokens,
    this._origin,
  );

  NgMicroAst parse() {
    // Only the first token can be bound to the left-hand side property.
    var first = true;
    while (_tokens.moveNext()) {
      var token = _tokens.current;
      if (token.type == NgMicroTokenType.letKeyword) {
        _parseLet();
      } else if (token.type == NgMicroTokenType.bindIdentifier) {
        _parseBind();
      } else if (first && token.type == NgMicroTokenType.bindExpression) {
        _parseImplicitBind();
      } else if (token.type != NgMicroTokenType.endExpression) {
        throw _unexpected(token);
      }
      first = false;
    }
    return NgMicroAst(letBindings: letBindings, properties: properties);
  }

  void _parseBind() {
    var name = _tokens.current.lexeme;
    if (!_tokens.moveNext() ||
        _tokens.current.type != NgMicroTokenType.bindExpressionBefore ||
        !_tokens.moveNext() ||
        _tokens.current.type != NgMicroTokenType.bindExpression) {
      throw _unexpected();
    }
    var value = _tokens.current.lexeme;
    properties.add(PropertyAst.from(
      _origin,
      '$_directive${name[0].toUpperCase()}${name.substring(1)}',
      value,
    ));
  }

  // An implicit binding has no accompanying identifier. Instead, it is bound
  // to the property on the left-hand side to which the micro-syntax expression
  // was assigned.
  void _parseImplicitBind() {
    properties.add(PropertyAst.from(
      _origin,
      _directive,
      _tokens.current.lexeme,
    ));
  }

  void _parseLet() {
    String identifier;
    if (!_tokens.moveNext() ||
        _tokens.current.type != NgMicroTokenType.letKeywordAfter ||
        !_tokens.moveNext() ||
        _tokens.current.type != NgMicroTokenType.letIdentifier) {
      throw _unexpected();
    }
    identifier = _tokens.current.lexeme;
    if (!_tokens.moveNext() ||
        _tokens.current.type == NgMicroTokenType.endExpression ||
        !_tokens.moveNext() ||
        _tokens.current.type == NgMicroTokenType.endExpression) {
      letBindings.add(LetBindingAst.from(_origin, identifier));
      return;
    }
    if (_tokens.current.type == NgMicroTokenType.letAssignment) {
      letBindings.add(LetBindingAst.from(
        _origin,
        identifier,
        _tokens.current.lexeme.trimRight(),
      ));
    } else {
      letBindings.add(LetBindingAst.from(_origin, identifier));
      if (_tokens.current.type != NgMicroTokenType.bindIdentifier) {
        throw _unexpected();
      }
      var property = _tokens.current.lexeme;
      if (!_tokens.moveNext() ||
          _tokens.current.type != NgMicroTokenType.bindExpressionBefore ||
          !_tokens.moveNext() ||
          _tokens.current.type != NgMicroTokenType.bindExpression) {
        throw _unexpected();
      }
      var expression = _tokens.current.lexeme;
      properties.add(PropertyAst.from(
        _origin,
        '$_directive${property[0].toUpperCase()}${property.substring(1)}',
        expression,
      ));
    }
  }

  AngularParserException _unexpected([NgMicroToken? token]) {
    token ??= _tokens.current;
    return AngularParserException(
      ParserErrorCode.invalidMicroExpression,
      _expressionOffset,
      _expressionLength,
    );
  }
}
