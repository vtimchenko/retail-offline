import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/core/errors/dataset_parse_exception.dart';
import 'package:retail_offline/services/json/precision_json_decoder.dart';

const _overInt64 = '9999999999999999999';

JsonValue _decode(String source) => const PrecisionJsonDecoder().decode(source);

JsonSyntaxException _syntax(String source) {
  try {
    _decode(source);
  } on JsonSyntaxException catch (error) {
    return error;
  }
  fail('Expected JsonSyntaxException');
}

void main() {
  group('PrecisionJsonDecoder', () {
    test('preserves number literals without converting them', () {
      final value = _decode(
        '{'
        '"id":$_overInt64,'
        '"price":324.50,'
        '"exp":1e+2,'
        '"neg":-42'
        '}',
      ) as JsonObjectValue;

      String literal(String key) =>
          (value.fields[key]! as JsonNumberValue).literal;

      expect(literal('id'), _overInt64);
      expect(literal('id'), hasLength(19));
      expect(literal('price'), '324.50');
      expect(literal('exp'), '1e+2');
      expect(literal('neg'), '-42');
    });

    test('jsonDecode cannot keep an integer past 64 bits', () {
      final decoded = jsonDecode(_overInt64);
      expect(decoded, isNot(isA<int>()));
      expect(decoded.toString(), isNot(_overInt64));
    });

    test('double cannot keep a 19-digit identifier', () {
      const id = '1290564103789190763';
      expect(double.parse(id).toString(), isNot(id));
    });

    test('decodes strings, bools, null and arrays', () {
      final value = _decode(
        ' { "name" : "Магазин\\n\\"А\\"" , '
        '"ok" : true , "no" : false , "empty" : null , '
        '"tags" : [ "А" , false , null ] } ',
      ) as JsonObjectValue;

      expect((value.fields['name']! as JsonStringValue).text, 'Магазин\n"А"');
      expect((value.fields['ok']! as JsonBoolValue).value, isTrue);
      expect((value.fields['no']! as JsonBoolValue).value, isFalse);
      expect(value.fields['empty'], isA<JsonNullValue>());
      final tags = (value.fields['tags']! as JsonArrayValue).items;
      expect((tags[0] as JsonStringValue).text, 'А');
      expect((tags[1] as JsonBoolValue).value, isFalse);
      expect(tags[2], isA<JsonNullValue>());
    });

    test('decodes unicode escapes and a surrogate pair', () {
      final value = _decode(
        r'{"letter":"\u0410","face":"\uD83D\uDE00"}',
      ) as JsonObjectValue;
      expect((value.fields['letter']! as JsonStringValue).text, 'А');
      expect((value.fields['face']! as JsonStringValue).text, '😀');
    });

    test('rejects a duplicate key and keeps one leading BOM', () {
      final duplicate = _syntax('{"a":1,"a":2}');
      expect(duplicate.message, contains('«a»'));
      expect(duplicate.message, contains('повторюється поле'));
      expect(duplicate.line, 1);

      final escaped = _syntax('{"a":1,"\\u0061":2}');
      expect(escaped.message, contains('«a»'));

      final value = _decode('\uFEFF{"n":1}') as JsonObjectValue;
      expect((value.fields['n']! as JsonNumberValue).literal, '1');
      expect(_syntax('\uFEFF\uFEFF{"n":1}'), isA<JsonSyntaxException>());
      expect(_syntax('{\uFEFF"n":1}'), isA<JsonSyntaxException>());
    });

    test('rejects malformed JSON in Ukrainian', () {
      final error = _syntax('{\n');
      expect(error.message, contains('Некоректний JSON'));
      expect(error.message, contains('рядок 2'));
      expect(error.line, 2);
    });

    for (final source in [
      '',
      '   ',
      '+1',
      '01',
      '.5',
      '1.',
      '1e',
      'NaN',
      'Infinity',
      "{'a':1}",
      '{"a":1,}',
      '[1,]',
      '{"a":1} []',
      '"unterminated',
      '{"a":"line\nbreak"}',
    ]) {
      test('rejects `$source`', () {
        expect(_syntax(source), isA<JsonSyntaxException>());
      });
    }
  });
}
