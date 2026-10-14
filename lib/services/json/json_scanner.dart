import '../../core/constants/dataset_messages.dart';
import '../../core/errors/dataset_parse_exception.dart';

/// Builds a [JsonSyntaxException] at [offset] in [source].
JsonSyntaxException jsonSyntaxAt(String source, int offset, String technical) {
  var line = 1;
  var column = 1;
  final end = offset < source.length ? offset : source.length;
  for (var i = 0; i < end; i++) {
    if (source.codeUnitAt(i) == 0x0A) {
      line++;
      column = 1;
    } else {
      column++;
    }
  }
  return JsonSyntaxException(
    DatasetMessages.syntax(line: line, column: column),
    technical: technical,
    offset: offset,
    line: line,
    column: column,
  );
}

enum JsonTokenKind {
  beginObject,
  endObject,
  beginArray,
  endArray,
  colon,
  comma,
  string,
  number,
  boolean,
  nullValue,
  eof,
}

/// One JSON token.
///
/// A [JsonTokenKind.number] keeps the raw literal in [text]. A
/// [JsonTokenKind.string] keeps the decoded text. Neither numbers nor
/// strings are converted with `num`.
class JsonToken {
  const JsonToken(this.kind, this.offset, {this.text, this.boolValue});

  final JsonTokenKind kind;
  final int offset;
  final String? text;
  final bool? boolValue;
}

/// Tokenizes JSON text.
///
/// Number tokens are slices of [source]. They are not parsed as integers
/// or doubles, so a 19-digit identifier survives with its original digits.
class JsonScanner {
  /// Skips one leading U+FEFF.
  ///
  /// A later BOM outside a JSON string is an unexpected character.
  JsonScanner(this.source) {
    if (source.isNotEmpty && source.codeUnitAt(0) == 0xFEFF) {
      _index = 1;
    }
  }

  final String source;
  int _index = 0;
  JsonToken? _buffered;

  JsonToken peek() => _buffered ??= _read();

  JsonToken next() {
    final token = peek();
    _buffered = null;
    return token;
  }

  JsonToken _read() {
    _skipWhitespace();
    final offset = _index;
    final unit = _peek();
    if (unit < 0) {
      return JsonToken(JsonTokenKind.eof, offset);
    }
    switch (unit) {
      case 0x7B:
        _index++;
        return JsonToken(JsonTokenKind.beginObject, offset);
      case 0x7D:
        _index++;
        return JsonToken(JsonTokenKind.endObject, offset);
      case 0x5B:
        _index++;
        return JsonToken(JsonTokenKind.beginArray, offset);
      case 0x5D:
        _index++;
        return JsonToken(JsonTokenKind.endArray, offset);
      case 0x3A:
        _index++;
        return JsonToken(JsonTokenKind.colon, offset);
      case 0x2C:
        _index++;
        return JsonToken(JsonTokenKind.comma, offset);
      case 0x22:
        return JsonToken(JsonTokenKind.string, offset, text: _readString());
      case 0x2D:
      case >= 0x30 && <= 0x39:
        return JsonToken(JsonTokenKind.number, offset, text: _readNumber());
      case 0x74:
        return _keyword('true', JsonTokenKind.boolean, boolValue: true);
      case 0x66:
        return _keyword('false', JsonTokenKind.boolean, boolValue: false);
      case 0x6E:
        return _keyword('null', JsonTokenKind.nullValue);
      default:
        _fail('Unexpected character U+${unit.toRadixString(16)}');
    }
  }

  void _skipWhitespace() {
    while (true) {
      final unit = _peek();
      if (unit != 0x20 && unit != 0x09 && unit != 0x0A && unit != 0x0D) {
        return;
      }
      _index++;
    }
  }

  int _peek([int ahead = 0]) {
    final i = _index + ahead;
    if (i >= source.length) return -1;
    return source.codeUnitAt(i);
  }

  bool _isDigit(int unit) => unit >= 0x30 && unit <= 0x39;

  String _readString() {
    final start = _index;
    _index++;
    final buffer = StringBuffer();
    while (_index < source.length) {
      final unit = source.codeUnitAt(_index);
      if (unit == 0x22) {
        _index++;
        return buffer.toString();
      }
      if (unit == 0x5C) {
        buffer.write(_readEscape());
        continue;
      }
      if (unit < 0x20) {
        _fail('Unescaped control character', start);
      }
      buffer.writeCharCode(unit);
      _index++;
    }
    _fail('Unterminated string', start);
  }

  String _readEscape() {
    final slash = _index;
    _index++;
    if (_index >= source.length) {
      _fail('Truncated escape', slash);
    }
    final unit = source.codeUnitAt(_index);
    _index++;
    switch (unit) {
      case 0x22:
        return '"';
      case 0x5C:
        return r'\';
      case 0x2F:
        return '/';
      case 0x62:
        return '\b';
      case 0x66:
        return '\f';
      case 0x6E:
        return '\n';
      case 0x72:
        return '\r';
      case 0x74:
        return '\t';
      case 0x75:
        return _readUnicode(slash);
      default:
        _fail('Invalid escape', slash);
    }
  }

  String _readUnicode(int slash) {
    final high = _readHex4(slash);
    if (_isHighSurrogate(high) && _peek() == 0x5C && _peek(1) == 0x75) {
      _index += 2;
      final low = _readHex4(slash);
      return String.fromCharCodes([high, low]);
    }
    return String.fromCharCode(high);
  }

  int _readHex4(int slash) {
    if (_index + 4 > source.length) {
      _fail('Truncated unicode escape', slash);
    }
    final hex = source.substring(_index, _index + 4);
    final code = int.tryParse(hex, radix: 16);
    if (code == null) {
      _fail('Invalid unicode escape', slash);
    }
    _index += 4;
    return code;
  }

  bool _isHighSurrogate(int code) => code >= 0xD800 && code <= 0xDBFF;

  /// Copies a JSON number verbatim.
  ///
  /// The grammar follows RFC 8259: no leading zeros, an optional fraction,
  /// and an optional exponent. The caller decides which of those forms a
  /// field may use.
  String _readNumber() {
    final start = _index;
    if (_peek() == 0x2D) _index++;
    if (_index >= source.length) {
      _fail('Truncated number', start);
    }
    final first = source.codeUnitAt(_index);
    if (first == 0x30) {
      _index++;
    } else if (first >= 0x31 && first <= 0x39) {
      while (_isDigit(_peek())) {
        _index++;
      }
    } else {
      _fail('Invalid number', start);
    }
    if (_peek() == 0x2E) {
      _index++;
      if (!_isDigit(_peek())) {
        _fail('Invalid fraction', start);
      }
      while (_isDigit(_peek())) {
        _index++;
      }
    }
    final exponent = _peek();
    if (exponent == 0x65 || exponent == 0x45) {
      _index++;
      final sign = _peek();
      if (sign == 0x2B || sign == 0x2D) _index++;
      if (!_isDigit(_peek())) {
        _fail('Invalid exponent', start);
      }
      while (_isDigit(_peek())) {
        _index++;
      }
    }
    return source.substring(start, _index);
  }

  JsonToken _keyword(String word, JsonTokenKind kind, {bool? boolValue}) {
    if (source.startsWith(word, _index)) {
      final offset = _index;
      _index += word.length;
      return JsonToken(kind, offset, boolValue: boolValue);
    }
    _fail('Invalid token');
  }

  Never _fail(String technical, [int? offset]) {
    throw jsonSyntaxAt(source, offset ?? _index, technical);
  }
}
