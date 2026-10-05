import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/models/serial_selection.dart';
import 'package:retail_offline/screens/orders/serial_search.dart';

const _rows = [
  AvailableSerial(address: 'A1', serialNumber: 'SN001', availableQuantity: 3),
  AvailableSerial(address: 'B2', serialNumber: 'SN001', availableQuantity: 1),
  AvailableSerial(
    address: 'C3',
    serialNumber: '0MSH3HJL900062',
    availableQuantity: 2,
  ),
];

void main() {
  test('a blank query returns every row in order', () {
    expect(SerialSearch.filter(_rows, ''), _rows);
    expect(SerialSearch.filter(_rows, '   '), _rows);
  });

  test('matches a partial case-sensitive serial and ignores address', () {
    expect(SerialSearch.filter(_rows, '  SN00 ').map((row) => row.address), [
      'A1',
      'B2',
    ]);
    expect(SerialSearch.filter(_rows, 'sn001'), isEmpty);
    expect(SerialSearch.filter(_rows, 'B2'), isEmpty);
    expect(
      SerialSearch.filter(_rows, '0MSH').single.serialNumber,
      '0MSH3HJL900062',
    );
  });

  test('does not modify the stored serial', () {
    SerialSearch.filter(_rows, '  sn001  ');
    expect(_rows.first.serialNumber, 'SN001');
    expect(_rows.last.serialNumber, '0MSH3HJL900062');
  });

  test('no match returns an empty list', () {
    expect(SerialSearch.filter(_rows, 'немає'), isEmpty);
  });
}
