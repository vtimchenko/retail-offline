import 'package:flutter/foundation.dart';

/// Exact source text of a JSON integer token.
///
/// [literal] is the exact decimal digits of a non-negative JSON integer.
/// Zero is `0`. A leading minus, fraction, or exponent is rejected before
/// a value is built. Future export writes [literal] back as an unquoted
/// JSON number. It is never parsed with `int.parse`, `double`, or `num`,
/// because identifiers can exceed both JavaScript's safe integer range and
/// a 64-bit integer.
@immutable
class ExactInteger {
  const ExactInteger(this.literal);

  final String literal;

  @override
  bool operator ==(Object other) =>
      other is ExactInteger && other.literal == literal;

  @override
  int get hashCode => literal.hashCode;

  @override
  String toString() => literal;
}
