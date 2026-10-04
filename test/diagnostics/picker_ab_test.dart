import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/core/errors/import_exception.dart';
import 'package:retail_offline/diagnostics/picker_ab.dart';
import 'package:retail_offline/models/store.dart';
import 'package:retail_offline/screens/home/home_screen.dart';

Uint8List get _zip => Uint8List.fromList([0x50, 0x4B, 3, 4, 0]);

void main() {
  test('the default variant is the app-owned picker with no diagnostics', () {
    const v = PickerAbVariant.appPicker;
    expect(PickerAbVariant.current, v);
    expect(v.label, 'app-picker');
    expect(v.wrapsClick, isFalse);
    expect(v.addsInputListeners, isFalse);
    expect(v.retainsInput, isFalse);
    expect(pickerAbBuild, startsWith('prod-picker1-'));
  });

  group('ProbedLocalFileService reports how the picker ended', () {
    test('PENDING while the picker is open, then FILE', () async {
      final probe = PickerAbProbe();
      final states = <PickerAbState>[];
      probe.addListener(() => states.add(probe.state));
      final service = ProbedLocalFileService(
        probe,
        picker: () async => (name: 'a.xlsx', bytes: _zip),
      );

      final file = await service.pickXlsx();

      expect(file, isNotNull);
      expect(states, [PickerAbState.pending, PickerAbState.file]);
      expect(probe.detail, '5 bytes');
    });

    test(
      'NULL when the picker returns null (the result is unchanged)',
      () async {
        final probe = PickerAbProbe();
        final service = ProbedLocalFileService(probe, picker: () async => null);

        expect(await service.pickXlsx(), isNull);
        expect(probe.state, PickerAbState.nullResult);
      },
    );

    test('ERROR when the picker throws (the exception is unchanged)', () async {
      final probe = PickerAbProbe();
      final service = ProbedLocalFileService(
        probe,
        picker: () async => throw StateError('boom'),
      );

      await expectLater(service.pickXlsx(), throwsA(isA<ImportException>()));
      expect(probe.state, PickerAbState.error);
      expect(probe.detail, 'StateError');
    });

    test('a file that validation rejects still counts as FILE', () async {
      final probe = PickerAbProbe();
      final service = ProbedLocalFileService(
        probe,
        picker: () async => (name: 'a.txt', bytes: _zip),
      );

      await expectLater(service.pickXlsx(), throwsA(isA<ImportException>()));
      expect(probe.state, PickerAbState.file);
      expect(probe.detail, 'rejected by validation');
    });
  });

  testWidgets('the home screen shows build, variant and last result', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: HomeScreen(
          store: Store(nameStore: 'Тест', idStore: '1'),
        ),
      ),
    );

    final marker = find.byKey(const Key('picker-ab-marker'));
    await tester.ensureVisible(marker);
    final text = tester.widget<Text>(
      find.descendant(of: marker, matching: find.byType(Text)),
    );
    expect(text.data, contains('iOS picker A/B'));
    expect(text.data, contains('Build: $pickerAbBuild'));
    expect(text.data, contains('Variant: '));
    expect(text.data, contains('Last picker result: -'));
  });
}
