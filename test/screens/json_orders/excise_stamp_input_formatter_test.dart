import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/screens/json_orders/excise_stamp_dialog.dart';

void main() {
  const formatter = ExciseStampInputFormatter();

  TextEditingValue edit(String oldText, String newText) {
    return formatter.formatEditUpdate(
      TextEditingValue(
        text: oldText,
        selection: TextSelection.collapsed(offset: oldText.length),
      ),
      TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      ),
    );
  }

  group('ExciseStampInputFormatter', () {
    test('accepts a stamp, uppercases it, and stops at 10 characters', () {
      final pasted = edit('', 'qwer123456');
      final extra = edit('', 'QWER1234567');

      expect(pasted.text, 'QWER123456');
      expect(pasted.selection.extentOffset, 10);
      expect(extra.text, 'QWER123456');
      expect(extra.selection.extentOffset, 10);
    });

    test('keeps letters in the first four positions and digits after them', () {
      expect(edit('', '1WER123456').text, 'WER123456');
      expect(edit('', 'QW3R123456').text, 'QW312345');
      expect(edit('', 'QWERAB3456').text, 'QWER3456');
      expect(edit('', 'QWER12345').text, 'QWER12345');
      expect(edit('QWER12345', 'QWER123456').text, 'QWER123456');
    });

    test('drops Cyrillic, spaces, and other characters', () {
      expect(edit('', '\u0410BCD123456').text, 'BCD123456');
      expect(edit('', ' QWER 123456 ').text, 'QWER123456');
      expect(edit('QWER', 'QWER ').text, 'QWER');
      expect(edit('QW', 'QW\u0410').text, 'QW');
    });

    test('edits one section without discarding the other', () {
      final deletedLetter = edit('QWER123456', 'QER123456');
      final deletedDigit = edit('QWER123456', 'QWER13456');
      final replacedLetter = edit('QWER123456', 'QWxR123456');
      final replacedDigit = edit('QWER123456', 'QWER129456');
      final rejectedDigit = edit('QWER123456', '1QWER123456');
      final rejectedLetter = edit('QWER123456', 'QWERX123456');

      expect(deletedLetter.text, 'QER123456');
      expect(deletedLetter.selection.extentOffset, 1);
      expect(deletedDigit.text, 'QWER13456');
      expect(deletedDigit.selection.extentOffset, 5);
      expect(replacedLetter.text, 'QWXR123456');
      expect(replacedLetter.selection.extentOffset, 3);
      expect(replacedDigit.text, 'QWER129456');
      expect(replacedDigit.selection.extentOffset, 7);
      expect(rejectedDigit.text, 'QWER123456');
      expect(rejectedDigit.selection.extentOffset, 10);
      expect(rejectedLetter.text, 'QWER123456');
      expect(rejectedLetter.selection.extentOffset, 10);
    });

    test('a full pasted stamp replaces the current value', () {
      final value = edit('ASDF654321', 'qwer123456');

      expect(value.text, 'QWER123456');
      expect(value.selection.extentOffset, 10);
    });

    test('moving the caret does not change the text', () {
      const current = TextEditingValue(
        text: 'QWER12',
        selection: TextSelection(baseOffset: 1, extentOffset: 4),
      );

      final next = formatter.formatEditUpdate(current, current);

      expect(next.text, 'QWER12');
      expect(next.selection, current.selection);
    });
  });
}
