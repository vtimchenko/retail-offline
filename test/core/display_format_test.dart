import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/core/format/display_format.dart';

void main() {
  group('formatMoney', () {
    test('formats minor units with a decimal comma', () {
      expect(DisplayFormat.formatMoney(32900), '329,00');
      expect(DisplayFormat.formatMoney(10050), '100,50');
      expect(DisplayFormat.formatMoney(1999), '19,99');
      expect(DisplayFormat.formatMoney(0), '0,00');
    });
  });

  group('formatInvoiceDate', () {
    test('formats local date and time without seconds', () {
      expect(
        DisplayFormat.formatInvoiceDate(DateTime(2026, 10, 3, 11, 46, 18)),
        '03.10.2026 11:46',
      );
    });
  });

  group('formatPhone', () {
    test('formats a 10-digit Ukrainian mobile number', () {
      expect(DisplayFormat.formatPhone('0991234567'), '(099) 123-45-67');
    });

    test('accepts a 380 prefix with or without a plus', () {
      expect(DisplayFormat.formatPhone('380991234567'), '(099) 123-45-67');
      expect(DisplayFormat.formatPhone('+380991234567'), '(099) 123-45-67');
    });

    test('accepts spaces, brackets and hyphens', () {
      expect(
        DisplayFormat.formatPhone('+38 (099) 123-45-67'),
        '(099) 123-45-67',
      );
      expect(DisplayFormat.formatPhone('099 123 45 67'), '(099) 123-45-67');
    });

    test('keeps leading zeros inside the national number', () {
      expect(DisplayFormat.formatPhone('0990123456'), '(099) 012-34-56');
      expect(DisplayFormat.formatPhone('380990123456'), '(099) 012-34-56');
    });

    test('leaves an unrecognized number unchanged', () {
      expect(DisplayFormat.formatPhone('12345'), '12345');
      expect(DisplayFormat.formatPhone('1234567890'), '1234567890');
      expect(DisplayFormat.formatPhone('099123456'), '099123456');
      expect(DisplayFormat.formatPhone('3800991234567'), '3800991234567');
      expect(
        DisplayFormat.formatPhone('+380671234567890123'),
        '+380671234567890123',
      );
      expect(DisplayFormat.formatPhone('0991234567x'), '0991234567x');
      expect(DisplayFormat.formatPhone('+1 202 555 0147'), '+1 202 555 0147');
      expect(DisplayFormat.formatPhone(''), '');
      expect(DisplayFormat.formatPhone('  '), '  ');
    });
  });
}
