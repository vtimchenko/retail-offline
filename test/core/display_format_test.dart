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
}
