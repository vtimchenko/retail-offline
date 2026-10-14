import 'package:flutter/foundation.dart';

import '../../core/constants/dataset_messages.dart';
import '../../core/errors/dataset_parse_exception.dart';
import 'json_scanner.dart';

/// A JSON value whose numbers are still source text.
@immutable
sealed class JsonValue {
  const JsonValue();
}

/// JSON object.
///
/// A repeated property name in this object is rejected while decoding.
/// The same name may appear in a different object.
@immutable
final class JsonObjectValue extends JsonValue {
  JsonObjectValue(Map<String, JsonValue> fields)
    : fields = Map.unmodifiable(fields);

  final Map<String, JsonValue> fields;
}

/// JSON array.
@immutable
final class JsonArrayValue extends JsonValue {
  JsonArrayValue(List<JsonValue> items) : items = List.unmodifiable(items);

  final List<JsonValue> items;
}

/// Decoded JSON string.
@immutable
final class JsonStringValue extends JsonValue {
  const JsonStringValue(this.text);

  final String text;
}

/// JSON number token, preserved exactly.
///
/// [literal] may contain a fraction or an exponent. Callers that need an
/// integer identifier must reject those forms without parsing [literal]
/// as `num`.
@immutable
final class JsonNumberValue extends JsonValue {
  const JsonNumberValue(this.literal);

  final String literal;
}

/// JSON `true` or `false`.
@immutable
final class JsonBoolValue extends JsonValue {
  const JsonBoolValue(this.value);

  final bool value;
}

/// JSON `null`.
@immutable
final class JsonNullValue extends JsonValue {
  const JsonNullValue();
}

/// Decodes JSON without `jsonDecode` and without `num`.
///
/// `dart:convert` turns numbers into `num`. On the web that is a
/// JavaScript number, so identifiers past 2^53 lose digits. This decoder
/// keeps every number token as the characters that appeared in the source.
class PrecisionJsonDecoder {
  const PrecisionJsonDecoder();

  JsonValue decode(String source) {
    final parser = _Parser(source);
    final value = parser.readValue();
    final trailing = parser.scanner.next();
    if (trailing.kind != JsonTokenKind.eof) {
      throw jsonSyntaxAt(
        source,
        trailing.offset,
        'Unexpected trailing token ${trailing.kind.name}',
      );
    }
    return value;
  }
}

class _Parser {
  _Parser(this.source) : scanner = JsonScanner(source);

  final String source;
  final JsonScanner scanner;

  JsonValue readValue() {
    final token = scanner.next();
    switch (token.kind) {
      case JsonTokenKind.beginObject:
        return _readObject();
      case JsonTokenKind.beginArray:
        return _readArray();
      case JsonTokenKind.string:
        return JsonStringValue(token.text!);
      case JsonTokenKind.number:
        return JsonNumberValue(token.text!);
      case JsonTokenKind.boolean:
        return JsonBoolValue(token.boolValue!);
      case JsonTokenKind.nullValue:
        return const JsonNullValue();
      case JsonTokenKind.endObject:
      case JsonTokenKind.endArray:
      case JsonTokenKind.colon:
      case JsonTokenKind.comma:
      case JsonTokenKind.eof:
        throw jsonSyntaxAt(source, token.offset, 'Expected a JSON value');
    }
  }

  JsonObjectValue _readObject() {
    final fields = <String, JsonValue>{};
    if (scanner.peek().kind == JsonTokenKind.endObject) {
      scanner.next();
      return JsonObjectValue(fields);
    }
    while (true) {
      final key = scanner.next();
      if (key.kind != JsonTokenKind.string) {
        _fail(key, 'Object key must be a string');
      }
      final name = key.text!;
      if (fields.containsKey(name)) {
        _duplicateKey(key, name);
      }
      final colon = scanner.next();
      if (colon.kind != JsonTokenKind.colon) {
        _fail(colon, 'Expected a colon after an object key');
      }
      fields[name] = readValue();
      final separator = scanner.next();
      if (separator.kind == JsonTokenKind.endObject) {
        return JsonObjectValue(fields);
      }
      if (separator.kind != JsonTokenKind.comma) {
        _fail(separator, 'Expected a comma or the end of an object');
      }
      if (scanner.peek().kind == JsonTokenKind.endObject) {
        final end = scanner.next();
        _fail(end, 'Trailing comma in object');
      }
    }
  }

  JsonArrayValue _readArray() {
    if (scanner.peek().kind == JsonTokenKind.endArray) {
      scanner.next();
      return JsonArrayValue(const []);
    }
    final items = <JsonValue>[];
    while (true) {
      items.add(readValue());
      final separator = scanner.next();
      if (separator.kind == JsonTokenKind.endArray) {
        return JsonArrayValue(items);
      }
      if (separator.kind != JsonTokenKind.comma) {
        _fail(separator, 'Expected a comma or the end of an array');
      }
      if (scanner.peek().kind == JsonTokenKind.endArray) {
        final end = scanner.next();
        _fail(end, 'Trailing comma in array');
      }
    }
  }

  Never _fail(JsonToken token, String technical) {
    throw jsonSyntaxAt(source, token.offset, technical);
  }

  Never _duplicateKey(JsonToken key, String name) {
    final located = jsonSyntaxAt(
      source,
      key.offset,
      'Duplicate object key "$name"',
    );
    throw JsonSyntaxException(
      DatasetMessages.duplicateKey(
        name,
        line: located.line,
        column: located.column,
      ),
      technical: located.technical,
      offset: key.offset,
      line: located.line,
      column: located.column,
    );
  }
}
