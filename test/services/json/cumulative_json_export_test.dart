import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/domain/fulfilment/fulfilment_session.dart';
import 'package:retail_offline/models/exact_integer.dart';
import 'package:retail_offline/models/retail_dataset.dart';
import 'package:retail_offline/persistence/dataset_fingerprint.dart';
import 'package:retail_offline/persistence/export_consistency.dart';
import 'package:retail_offline/services/json/cumulative_json_export.dart';
import 'package:retail_offline/services/json/precision_json_decoder.dart';

/// Synthetic catalogue only. No real customers, phones, or products.
final _created = DateTime(2026, 10, 3, 11, 46, 18);

const _export = CumulativeJsonExport();

void main() {
  const export = _export;

  group('CumulativeJsonExport.prepare', () {
    test('a session with no issued orders is unchanged', () {
      final session = mustOpen(
        data(
          stocks: [slot()],
          orders: [
            order(goods: [good()]),
          ],
        ),
      );

      final result = export.prepare(session, now: unreadClock());

      expect(result, isA<CumulativeExportUnchanged>());
      expect(identical(publishedSession(session, result), session), isTrue);
      expect(session.statusOf('ORD-1'), OrderStatus.noSelection);
      expect(lineReserved(session), 0);
    });

    test('previously exported orders alone do not start an export', () {
      final session = mustExport(issued(orderId: 'ORD-1'));

      final result = export.prepare(session, now: unreadClock());

      expect(result, isA<CumulativeExportUnchanged>());
      expect(session.statusOf('ORD-1'), OrderStatus.exported);
      expect(lineReserved(session), 1);
    });

    test('ready and in-progress orders do not start an export', () {
      final session = readyAndPartial();

      final result = export.prepare(session, now: unreadClock());

      expect(result, isA<CumulativeExportUnchanged>());
      expect(session.statusOf('ORD-EXP'), OrderStatus.exported);
      expect(session.statusOf('ORD-READY'), OrderStatus.readyForIssue);
      expect(session.statusOf('ORD-PART'), OrderStatus.inProgress);
      expect(lineReserved(session, orderId: 'ORD-EXP'), 1);
      expect(lineReserved(session, orderId: 'ORD-READY'), 1);
      expect(lineReserved(session, orderId: 'ORD-PART'), 1);
    });

    test('omitting the clock still does not read it when nothing is new', () {
      final session = mustOpen(
        data(
          stocks: [slot()],
          orders: [
            order(goods: [good()]),
          ],
        ),
      );

      expect(export.prepare(session), isA<CumulativeExportUnchanged>());
      expect(session.statusOf('ORD-1'), OrderStatus.noSelection);
    });

    test('one newly issued order prepares a file and a new session', () {
      final session = issued();
      var reads = 0;

      final prepared = asPrepared(
        export.prepare(
          session,
          now: () {
            reads++;
            return DateTime(2026, 10, 14, 15, 7, 22);
          },
        ),
      );

      expect(reads, 1);
      expect(prepared.document.dateCreate, _stamp);
      expect(prepared.document.filename, 'export_Store_01-A_$_stamp.json');
      expect(identical(prepared.pendingSession, session), isFalse);
      expect(session.statusOf('ORD-1'), OrderStatus.issued);
      expect(prepared.pendingSession.statusOf('ORD-1'), OrderStatus.exported);
      expect(lineReserved(session), 1);
      expect(lineReserved(prepared.pendingSession), 1);
      expect(
        utf8.decode(prepared.document.bytes),
        contains('"OrderID": "ORD-1"'),
      );
    });

    test('a new issue keeps previous exports and leaves the input session', () {
      final opened = mustOpen(
        data(
          stocks: [slot(quantity: 4)],
          orders: [
            order(orderId: 'ORD-OLD', goods: [good()]),
            order(orderId: 'ORD-WAIT', orderNumber: '2', goods: [good()]),
            order(orderId: 'ORD-NEW', orderNumber: '3', goods: [good()]),
          ],
        ),
      );
      final exported = mustExport(
        mustIssue(mustReserve(opened, 'ORD-OLD'), 'ORD-OLD'),
        'ORD-OLD',
      );
      final session = mustIssue(mustReserve(exported, 'ORD-NEW'), 'ORD-NEW');
      final prepared = asPrepared(export.prepare(session, now: stampClock));
      final text = utf8.decode(prepared.document.bytes);

      expect(session.statusOf('ORD-OLD'), OrderStatus.exported);
      expect(session.statusOf('ORD-WAIT'), OrderStatus.noSelection);
      expect(session.statusOf('ORD-NEW'), OrderStatus.issued);
      expect(prepared.pendingSession.statusOf('ORD-OLD'), OrderStatus.exported);
      expect(
        prepared.pendingSession.statusOf('ORD-WAIT'),
        OrderStatus.noSelection,
      );
      expect(prepared.pendingSession.statusOf('ORD-NEW'), OrderStatus.exported);
      expect(text, contains('"OrderID": "ORD-OLD"'));
      expect(text, contains('"OrderID": "ORD-NEW"'));
      expect(text, isNot(contains('ORD-WAIT')));
      expect(lineReserved(session, orderId: 'ORD-OLD'), 1);
      expect(lineReserved(session, orderId: 'ORD-NEW'), 1);
    });

    test('a service-only issued order exports its ordered quantity', () {
      final session = mustIssue(
        mustOpen(
          data(
            stocks: [slot()],
            orders: [
              order(
                goods: [good(productId: '200', quantity: 3, service: true)],
              ),
            ],
          ),
        ),
      );
      final prepared = asPrepared(export.prepare(session, now: stampClock));
      final line = _singleGood(_decode(utf8.decode(prepared.document.bytes)));

      expect(session.statusOf('ORD-1'), OrderStatus.issued);
      expect(prepared.pendingSession.statusOf('ORD-1'), OrderStatus.exported);
      expect(lineReserved(session, productId: '200'), 0);
      expect((line.fields['Address']! as JsonStringValue).text, isEmpty);
      expect((line.fields['SerialNumber']! as JsonStringValue).text, isEmpty);
      expect((line.fields['Quantity']! as JsonNumberValue).literal, '3');
    });

    test('several newly issued orders are marked in one prepared session', () {
      final opened = mustOpen(
        data(
          stocks: [slot(quantity: 4)],
          orders: [
            order(orderId: 'ORD-1', goods: [good()]),
            order(orderId: 'ORD-2', orderNumber: '2', goods: [good()]),
          ],
        ),
      );
      final session = mustIssue(
        mustIssue(mustReserve(mustReserve(opened, 'ORD-1'), 'ORD-2'), 'ORD-1'),
        'ORD-2',
      );
      final prepared = asPrepared(export.prepare(session, now: stampClock));

      expect(session.statusOf('ORD-1'), OrderStatus.issued);
      expect(session.statusOf('ORD-2'), OrderStatus.issued);
      expect(prepared.pendingSession.statusOf('ORD-1'), OrderStatus.exported);
      expect(prepared.pendingSession.statusOf('ORD-2'), OrderStatus.exported);
      expect(
        utf8.decode(prepared.document.bytes),
        contains('"OrderID": "ORD-1"'),
      );
      expect(
        utf8.decode(prepared.document.bytes),
        contains('"OrderID": "ORD-2"'),
      );
    });

    test('local timestamp components are zero-padded', () {
      final prepared = asPrepared(
        export.prepare(issued(), now: () => DateTime(2026, 1, 2, 3, 4, 5)),
      );

      expect(prepared.document.dateCreate, '20260102030405');
      expect(
        prepared.document.filename,
        'export_Store_01-A_20260102030405.json',
      );
      expect(
        utf8.decode(prepared.document.bytes),
        contains('"dateCreate": "20260102030405"'),
      );
      expect(prepared.document.dateCreate, isNot('20261003114618'));
    });

    test('document bytes stay intact when the returned list is changed', () {
      final prepared = asPrepared(export.prepare(issued(), now: stampClock));
      final view = prepared.document.bytes;
      final original = Uint8List.fromList(view);

      view[0] = view[0] == 0x7B ? 0x20 : 0x7B;

      expect(prepared.document.bytes, original);
      expect(identical(view, prepared.document.bytes), isFalse);
    });

    test(
      'a parcel split across addresses is written into the prepared file',
      () {
        final session = mustIssue(
          mustReserve(
            mustReserve(
              mustOpen(
                data(
                  stocks: [
                    slot(address: 'A-01', serialNumber: 'TTN-1', quantity: 2),
                    slot(address: 'B-02', serialNumber: 'TTN-1', quantity: 3),
                  ],
                  orders: [
                    order(goods: [good(quantity: 4, parcelTtn: 'TTN-1')]),
                  ],
                ),
              ),
              'ORD-1',
              serialNumber: 'TTN-1',
              quantity: 2,
            ),
            'ORD-1',
            address: 'B-02',
            serialNumber: 'TTN-1',
            quantity: 2,
          ),
        );
        final prepared = asPrepared(export.prepare(session, now: stampClock));
        final goods = _goods(_decode(utf8.decode(prepared.document.bytes)));

        expect(goods, hasLength(2));
        expect((goods[0].fields['Address']! as JsonStringValue).text, 'A-01');
        expect((goods[1].fields['Address']! as JsonStringValue).text, 'B-02');
        expect(
          (goods[0].fields['SerialNumber']! as JsonStringValue).text,
          'TTN-1',
        );
        expect(
          (goods[1].fields['SerialNumber']! as JsonStringValue).text,
          'TTN-1',
        );
        expect(session.statusOf('ORD-1'), OrderStatus.issued);
        expect(prepared.pendingSession.statusOf('ORD-1'), OrderStatus.exported);
      },
    );

    test('a second export includes every previously exported order', () {
      final opened = mustOpen(
        data(
          stocks: [slot(quantity: 4)],
          orders: [
            order(orderId: 'ORD-A', goods: [good()]),
            order(orderId: 'ORD-B', orderNumber: '2', goods: [good()]),
          ],
        ),
      );
      final first = asPrepared(
        export.prepare(
          mustIssue(mustReserve(opened, 'ORD-A'), 'ORD-A'),
          now: () => DateTime(2026, 10, 14, 15, 7, 22),
        ),
      );
      final second = asPrepared(
        export.prepare(
          mustIssue(mustReserve(first.pendingSession, 'ORD-B'), 'ORD-B'),
          now: () => DateTime(2026, 10, 14, 16, 8, 9),
        ),
      );
      final text = utf8.decode(second.document.bytes);

      expect(text, contains('"OrderID": "ORD-A"'));
      expect(text, contains('"OrderID": "ORD-B"'));
      expect(first.document.filename, 'export_Store_01-A_$_stamp.json');
      expect(second.document.dateCreate, '20261014160809');
      expect(second.document.filename, 'export_Store_01-A_20261014160809.json');
      expect(first.pendingSession.statusOf('ORD-A'), OrderStatus.exported);
      expect(first.pendingSession.statusOf('ORD-B'), OrderStatus.noSelection);
      expect(second.pendingSession.statusOf('ORD-A'), OrderStatus.exported);
      expect(second.pendingSession.statusOf('ORD-B'), OrderStatus.exported);
    });
  });

  group('Goods reconstruction', () {
    test('an issued order keeps the reserved slot, not a copied line', () {
      const productId = '1292834549023548345';
      const orderNumber = '9007199254740993';
      final line = good(productId: productId);
      final source = order(
        orderNumber: orderNumber,
        invoiceNumber: 'РОЗ234234234',
        goods: [line],
      );
      final session = mustIssue(
        mustReserve(
          mustOpen(
            data(
              stocks: [slot(productId: productId)],
              orders: [source],
            ),
          ),
          'ORD-1',
          productId: productId,
        ),
      );

      final prepared = asPrepared(export.prepare(session, now: stampClock));
      final reconstruction = export.reconstruct(session);

      expect(prepared.pendingSession.statusOf('ORD-1'), OrderStatus.exported);
      expect(reconstruction.failures, isEmpty);
      expect(reconstruction.orders, hasLength(1));
      final reconstructed = reconstruction.orders.single;
      expect(reconstructed.orderId, 'ORD-1');
      expect(reconstructed.invoiceNumber, 'РОЗ234234234');
      expect(reconstructed.orderNumber, same(source.orderNumber));
      expect(reconstructed.orderNumber.literal, orderNumber);
      expect(reconstructed.goods, hasLength(1));
      expectGood(
        reconstructed.goods.single,
        productId: productId,
        quantity: 1,
        address: 'A-01',
        serialNumber: 'SN-1',
      );
      expect(reconstructed.goods.single.productId, same(line.productId));
      expect(session.statusOf('ORD-1'), OrderStatus.issued);
    });

    test('different serials stay separate Goods entries', () {
      final session = mustIssue(
        mustReserve(
          mustReserve(
            mustOpen(
              data(
                stocks: [
                  slot(serialNumber: 'SN-1', quantity: 2),
                  slot(serialNumber: 'SN-2', quantity: 2),
                ],
                orders: [
                  order(goods: [good(quantity: 3)]),
                ],
              ),
            ),
            'ORD-1',
            serialNumber: 'SN-1',
            quantity: 1,
          ),
          'ORD-1',
          serialNumber: 'SN-2',
          quantity: 2,
        ),
      );

      final goods = export.reconstruct(session).orders.single.goods;

      expect(goods, hasLength(2));
      expectGood(
        goods[0],
        productId: '100',
        quantity: 1,
        address: 'A-01',
        serialNumber: 'SN-1',
      );
      expectGood(
        goods[1],
        productId: '100',
        quantity: 2,
        address: 'A-01',
        serialNumber: 'SN-2',
      );
    });

    test('the same serial at two addresses stays two entries', () {
      final session = mustIssue(
        mustReserve(
          mustReserve(
            mustOpen(
              data(
                stocks: [
                  slot(address: 'A-01', quantity: 2),
                  slot(address: 'B-02', quantity: 2),
                ],
                orders: [
                  order(goods: [good(quantity: 3)]),
                ],
              ),
            ),
            'ORD-1',
            quantity: 1,
          ),
          'ORD-1',
          address: 'B-02',
          quantity: 2,
        ),
      );

      final goods = export.reconstruct(session).orders.single.goods;

      expect(goods, hasLength(2));
      expectGood(
        goods[0],
        productId: '100',
        quantity: 1,
        address: 'A-01',
        serialNumber: 'SN-1',
      );
      expectGood(
        goods[1],
        productId: '100',
        quantity: 2,
        address: 'B-02',
        serialNumber: 'SN-1',
      );
    });

    test('a parcel split across addresses keeps ParcelTTN on each entry', () {
      final session = mustIssue(
        mustReserve(
          mustReserve(
            mustOpen(
              data(
                stocks: [
                  slot(address: 'A-01', serialNumber: 'TTN-1', quantity: 2),
                  slot(address: 'B-02', serialNumber: 'TTN-1', quantity: 3),
                  slot(address: 'C-03', serialNumber: 'OTHER', quantity: 2),
                ],
                orders: [
                  order(goods: [good(quantity: 4, parcelTtn: 'TTN-1')]),
                ],
              ),
            ),
            'ORD-1',
            serialNumber: 'TTN-1',
            quantity: 2,
          ),
          'ORD-1',
          address: 'B-02',
          serialNumber: 'TTN-1',
          quantity: 2,
        ),
      );

      final reconstruction = export.reconstruct(session);

      expect(reconstruction.failures, isEmpty);
      expect(reconstruction.orders.single.goods, hasLength(2));
      expectGood(
        reconstruction.orders.single.goods[0],
        productId: '100',
        quantity: 2,
        address: 'A-01',
        serialNumber: 'TTN-1',
      );
      expectGood(
        reconstruction.orders.single.goods[1],
        productId: '100',
        quantity: 2,
        address: 'B-02',
        serialNumber: 'TTN-1',
      );
    });

    test('a service-only issued order exports its ordered quantity', () {
      final session = mustIssue(
        mustOpen(
          data(
            stocks: [slot()],
            orders: [
              order(
                goods: [
                  good(
                    product: 'Доставка',
                    productId: '200',
                    quantity: 3,
                    service: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      final reconstruction = export.reconstruct(session);

      expect(reconstruction.failures, isEmpty);
      expect(reconstruction.orders.single.goods, hasLength(1));
      expectGood(
        reconstruction.orders.single.goods.single,
        productId: '200',
        quantity: 3,
        address: '',
        serialNumber: '',
      );
      expect(lineReserved(session, productId: '200'), 0);
    });

    test(
      'a mixed order uses reservations for stock and the line for service',
      () {
        final session = mustIssue(
          mustReserve(
            mustOpen(
              data(
                stocks: [slot(productId: '100', quantity: 2)],
                orders: [
                  order(
                    goods: [
                      good(productId: '100', quantity: 2),
                      good(
                        product: 'Доставка',
                        productId: '200',
                        quantity: 4,
                        service: true,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            'ORD-1',
            quantity: 2,
          ),
        );

        final goods = export.reconstruct(session).orders.single.goods;

        expect(goods, hasLength(2));
        expectGood(
          goods[0],
          productId: '100',
          quantity: 2,
          address: 'A-01',
          serialNumber: 'SN-1',
        );
        expectGood(
          goods[1],
          productId: '200',
          quantity: 4,
          address: '',
          serialNumber: '',
        );
      },
    );

    test('a new issue also reconstructs previously exported orders', () {
      final opened = mustOpen(
        data(
          stocks: [
            slot(productId: '100'),
            slot(productId: '200', serialNumber: 'SN-9'),
            slot(productId: '300'),
          ],
          orders: [
            order(
              orderId: 'ORD-OLD',
              invoiceNumber: 'OLD-INV',
              goods: [good(productId: '100')],
            ),
            order(
              orderId: 'ORD-WAIT',
              orderNumber: '2',
              invoiceNumber: 'WAIT-INV',
              goods: [good(productId: '300', quantity: 2)],
            ),
            order(
              orderId: 'ORD-NEW',
              orderNumber: '3',
              invoiceNumber: 'NEW-INV',
              goods: [good(productId: '200')],
            ),
          ],
        ),
      );
      final exported = mustExport(
        mustIssue(mustReserve(opened, 'ORD-OLD', productId: '100'), 'ORD-OLD'),
        'ORD-OLD',
      );
      final waiting = mustReserve(exported, 'ORD-WAIT', productId: '300');
      final session = mustIssue(
        mustReserve(waiting, 'ORD-NEW', productId: '200', serialNumber: 'SN-9'),
        'ORD-NEW',
      );

      final prepared = asPrepared(export.prepare(session, now: stampClock));
      final reconstruction = export.reconstruct(session);
      final text = utf8.decode(prepared.document.bytes);

      expect(text, contains('"OrderID": "ORD-OLD"'));
      expect(text, contains('"OrderID": "ORD-NEW"'));
      expect(text, isNot(contains('ORD-WAIT')));
      expect(session.statusOf('ORD-NEW'), OrderStatus.issued);
      expect(prepared.pendingSession.statusOf('ORD-NEW'), OrderStatus.exported);
      expect(reconstruction.failures, isEmpty);
      expect(reconstruction.orders.map((item) => item.orderId), [
        'ORD-OLD',
        'ORD-NEW',
      ]);
      expect(reconstruction.orders[0].invoiceNumber, 'OLD-INV');
      expectGood(
        reconstruction.orders[0].goods.single,
        productId: '100',
        quantity: 1,
        address: 'A-01',
        serialNumber: 'SN-1',
      );
      expect(reconstruction.orders[1].invoiceNumber, 'NEW-INV');
      expectGood(
        reconstruction.orders[1].goods.single,
        productId: '200',
        quantity: 1,
        address: 'A-01',
        serialNumber: 'SN-9',
      );
      expect(session.statusOf('ORD-OLD'), OrderStatus.exported);
      expect(session.statusOf('ORD-WAIT'), OrderStatus.inProgress);
      expect(session.statusOf('ORD-NEW'), OrderStatus.issued);
    });

    test('unissued orders are left out even when they hold stock', () {
      final opened = mustOpen(
        data(
          stocks: [slot(quantity: 6)],
          orders: [
            order(orderId: 'ORD-ISSUED', goods: [good()]),
            order(orderId: 'ORD-READY', orderNumber: '2', goods: [good()]),
            order(
              orderId: 'ORD-PART',
              orderNumber: '3',
              goods: [good(quantity: 2)],
            ),
            order(orderId: 'ORD-NONE', orderNumber: '4', goods: [good()]),
          ],
        ),
      );
      final issuedOrder = mustIssue(
        mustReserve(opened, 'ORD-ISSUED'),
        'ORD-ISSUED',
      );
      final ready = mustReserve(issuedOrder, 'ORD-READY');
      final session = mustReserve(ready, 'ORD-PART');

      final reconstruction = export.reconstruct(session);

      expect(reconstruction.failures, isEmpty);
      expect(reconstruction.orders.single.orderId, 'ORD-ISSUED');
      expectGood(
        reconstruction.orders.single.goods.single,
        productId: '100',
        quantity: 1,
        address: 'A-01',
        serialNumber: 'SN-1',
      );
      expect(lineReserved(session, orderId: 'ORD-READY'), 1);
      expect(session.statusOf('ORD-PART'), OrderStatus.inProgress);
      expect(session.statusOf('ORD-NONE'), OrderStatus.noSelection);
    });

    test(
      'ExactInteger 01 rejects the export and leaves the session issued',
      () {
        final session = issuedLiteral(orderNumber: '01');

        final result = export.prepare(session, now: unreadClock());

        expect(identical(publishedSession(session, result), session), isTrue);
        expect(failureViews(result), [
          (
            orderId: 'ORD-1',
            reason: CumulativeExportReason.invalidIntegerLiteral,
            productId: null,
          ),
        ]);
        expect(session.statusOf('ORD-1'), OrderStatus.issued);
        expect(lineReserved(session), 1);
      },
    );

    test('ExactInteger 1e2 rejects the product literal', () {
      final session = issuedLiteral(productId: '1e2');

      final result = export.prepare(session, now: unreadClock());

      expect(failureViews(result), [
        (
          orderId: 'ORD-1',
          reason: CumulativeExportReason.invalidIntegerLiteral,
          productId: '1e2',
        ),
      ]);
      expect(identical(publishedSession(session, result), session), isTrue);
      expect(session.statusOf('ORD-1'), OrderStatus.issued);
      expect(lineReserved(session, productId: '1e2'), 1);
    });

    test('rejection does not change reservations or export flags', () {
      final session = issuedLiteral(orderNumber: '01');
      final reserved = lineReserved(session);

      final result = export.prepare(session, now: unreadClock());

      expect(result, isA<CumulativeExportRejected>());
      expect(identical(publishedSession(session, result), session), isTrue);
      expect(session.statusOf('ORD-1'), OrderStatus.issued);
      expect(lineReserved(session), reserved);
      expect(
        export.prepare(session, now: unreadClock()),
        isA<CumulativeExportRejected>(),
      );
      expect(session.statusOf('ORD-1'), OrderStatus.issued);
    });

    test('collects every invalid literal with its order id', () {
      final opened = mustOpen(
        data(
          stocks: [
            slot(productId: '01'),
            slot(productId: '200'),
          ],
          orders: [
            order(
              orderId: 'ORD-A',
              orderNumber: '01',
              goods: [good(productId: '01')],
            ),
            order(
              orderId: 'ORD-SKIP',
              orderNumber: '01',
              goods: [good(productId: '300', service: true)],
            ),
            order(
              orderId: 'ORD-B',
              orderNumber: '1e2',
              goods: [good(productId: '200')],
            ),
          ],
        ),
      );
      final first = mustIssue(
        mustReserve(opened, 'ORD-A', productId: '01'),
        'ORD-A',
      );
      final session = mustIssue(
        mustReserve(first, 'ORD-B', productId: '200'),
        'ORD-B',
      );

      final result = export.prepare(session, now: unreadClock());

      expect(failureViews(result), [
        (
          orderId: 'ORD-A',
          reason: CumulativeExportReason.invalidIntegerLiteral,
          productId: null,
        ),
        (
          orderId: 'ORD-A',
          reason: CumulativeExportReason.invalidIntegerLiteral,
          productId: '01',
        ),
        (
          orderId: 'ORD-B',
          reason: CumulativeExportReason.invalidIntegerLiteral,
          productId: null,
        ),
      ]);
      expect(session.statusOf('ORD-A'), OrderStatus.issued);
      expect(session.statusOf('ORD-SKIP'), OrderStatus.readyForIssue);
      expect(session.statusOf('ORD-B'), OrderStatus.issued);
    });
  });

  group('JSON writer', () {
    test('writes the cumulative export structure', () {
      final text = written(contractSession());

      expect(text, _contractJson);
      final prepared = asPrepared(
        export.prepare(contractSession(), now: stampClock),
      );
      expect(utf8.decode(prepared.document.bytes), _contractJson);
      expect(prepared.document.dateCreate, _stamp);
      expect(prepared.document.dateCreate, isNot('20261003114618'));
      expect(
        prepared.document.filename,
        'export_retail_ki_kiev_test_$_stamp.json',
      );
    });

    test('indents with two spaces', () {
      final lines = written(contractSession()).split('\n');

      expect(lines.first, '{');
      expect(lines[1], '  "storeName": "ТВ Київ Тест",');
      expect(lines, contains('    {'));
      expect(lines, contains('      "OrderID": "$_contractOrderId",'));
      expect(lines, contains('        {'));
      expect(lines, contains('          "ProductID": $_contractProductId,'));
      expect(lines.last, '}');
    });

    test('encodes UTF-8 without a BOM', () {
      final bytes = exportBytes(contractSession());

      expect(bytes.first, 0x7B);
      expect(bytes.take(3).toList(), isNot([0xEF, 0xBB, 0xBF]));
      expect(utf8.decode(bytes), isNot(startsWith('\uFEFF')));
      expect(utf8.decode(bytes), written(contractSession()));
    });

    test('uses LF and no carriage return', () {
      final text = written(contractSession());

      expect(text, contains('\n'));
      expect(text, isNot(contains('\r')));
    });

    test('writes Ukrainian text without unicode escapes', () {
      final text = written(contractSession());

      expect(text, contains('ТВ Київ Тест'));
      expect(text, contains('РОЗ234234234'));
      expect(text, isNot(contains(r'\u')));
    });

    test('escapes quotes, backslashes, and control characters', () {
      const storeName = 'ТВ "Київ"\\\n\u0001';
      const serialNumber = 'A"B\\C';
      final session = mustIssue(
        mustReserve(
          mustOpen(
            data(
              storeName: storeName,
              stocks: [slot(serialNumber: serialNumber)],
              orders: [
                order(goods: [good()]),
              ],
            ),
          ),
          'ORD-1',
          serialNumber: serialNumber,
        ),
      );
      final text = written(session);
      final encodedName = jsonEncode(storeName);

      expect(text, contains(encodedName));
      expect(text, contains('Київ'));
      expect(text, isNot(contains(r'\u041a')));
      expect(encodedName, contains(r'\"'));
      expect(encodedName, contains(r'\\'));
      expect(encodedName, contains(r'\n'));
      expect(encodedName, contains(r'\u0001'));
      expect(text, contains(jsonEncode(serialNumber)));

      final root = _decode(text);
      expect((root.fields['storeName']! as JsonStringValue).text, storeName);
      final line = _singleGood(root);
      expect(
        (line.fields['SerialNumber']! as JsonStringValue).text,
        serialNumber,
      );
    });

    test('keeps a ProductID past 2^53 - 1 unquoted', () {
      final text = written(contractSession());

      expect(text, contains('"ProductID": $_contractProductId'));
      expect(text, isNot(contains('"ProductID": "')));
      expect(_productLiteral(text), _contractProductId);
    });

    test('keeps an OrderNumber past 2^53 - 1 unquoted', () {
      const orderNumber = '9007199254740993';
      final session = mustIssue(
        mustReserve(
          mustOpen(
            data(
              stocks: [slot(productId: _contractProductId)],
              orders: [
                order(
                  orderNumber: orderNumber,
                  goods: [good(productId: _contractProductId)],
                ),
              ],
            ),
          ),
          'ORD-1',
          productId: _contractProductId,
        ),
      );
      final text = written(session);

      expect(text, contains('"OrderNumber": $orderNumber'));
      expect(text, isNot(contains('"OrderNumber": "')));
      expect(text, contains('"ProductID": $_contractProductId'));
      expect(_orderLiteral(text), orderNumber);
      expect(_productLiteral(text), _contractProductId);
    });

    test('round-trips exact integers through the precision decoder', () {
      final text = written(contractSession());

      expect(_orderLiteral(text), '908222222');
      expect(_productLiteral(text), _contractProductId);
      expect(_quantityLiteral(text), '1');
    });

    test('writes empty address and serial for a service', () {
      final session = mustIssue(
        mustOpen(
          data(
            stocks: [slot()],
            orders: [
              order(
                goods: [good(productId: '200', quantity: 3, service: true)],
              ),
            ],
          ),
        ),
      );
      final text = written(session);
      final line = _singleGood(_decode(text));

      expect(text, contains('"Address": ""'));
      expect(text, contains('"SerialNumber": ""'));
      expect((line.fields['Address']! as JsonStringValue).text, isEmpty);
      expect((line.fields['SerialNumber']! as JsonStringValue).text, isEmpty);
      expect(_quantityLiteral(text), '3');
      expect(_productLiteral(text), '200');
    });

    test('writes one Goods object per parcel address', () {
      final session = mustIssue(
        mustReserve(
          mustReserve(
            mustOpen(
              data(
                stocks: [
                  slot(address: 'A-01', serialNumber: 'TTN-1', quantity: 2),
                  slot(address: 'B-02', serialNumber: 'TTN-1', quantity: 3),
                ],
                orders: [
                  order(goods: [good(quantity: 4, parcelTtn: 'TTN-1')]),
                ],
              ),
            ),
            'ORD-1',
            serialNumber: 'TTN-1',
            quantity: 2,
          ),
          'ORD-1',
          address: 'B-02',
          serialNumber: 'TTN-1',
          quantity: 2,
        ),
      );
      final text = written(session);
      final goods = _goods(_decode(text));

      expect(goods, hasLength(2));
      expect((goods[0].fields['Address']! as JsonStringValue).text, 'A-01');
      expect((goods[1].fields['Address']! as JsonStringValue).text, 'B-02');
      expect(
        (goods[0].fields['SerialNumber']! as JsonStringValue).text,
        'TTN-1',
      );
      expect(
        (goods[1].fields['SerialNumber']! as JsonStringValue).text,
        'TTN-1',
      );
      expect((goods[0].fields['Quantity']! as JsonNumberValue).literal, '2');
      expect((goods[1].fields['Quantity']! as JsonNumberValue).literal, '2');
      _expectExportKeys(_decode(text));
    });

    test('adds no fields beyond the export contract', () {
      _expectExportKeys(_decode(written(contractSession())));
    });

    test('repeats the same bytes for the same orders and stamp', () {
      final session = contractSession();

      expect(exportBytes(session), exportBytes(session));
      expect(
        exportBytes(session, dateCreate: _stamp),
        isNot(exportBytes(session, dateCreate: '20261003114618')),
      );
    });

    test('refuses a non-canonical integer before writing it', () {
      Uint8List write(String orderNumber, String productId) {
        return export.writeExport(
          storeName: 'Магазин',
          dbName: 'Store_01-A',
          dateCreate: _stamp,
          orders: [
            ReconstructedExportOrder(
              orderId: 'ORD-1',
              invoiceNumber: 'INV',
              orderNumber: ExactInteger(orderNumber),
              goods: [
                ReconstructedExportGood(
                  productId: ExactInteger(productId),
                  quantity: 1,
                  address: 'A-01',
                  serialNumber: 'SN-1',
                ),
              ],
            ),
          ],
        );
      }

      expect(() => write('01', '100'), throwsArgumentError);
      expect(() => write('1', '1e2'), throwsArgumentError);
    });
  });

  group('excise stamps', () {
    const stampA = 'QWER123456';
    const stampB = 'ASDF654321';
    const productId = '1290564103789190763';

    test('alcohol goods include ExciseStamp and regular goods omit it', () {
      final session = mustIssue(
        mustReserve(
          mustOpen(
            data(
              stocks: [
                slot(productId: productId, quantity: 2),
                slot(productId: '200', serialNumber: 'SN-2'),
              ],
              orders: [
                order(goods: [good(productId: productId, alcohol: true)]),
                order(
                  orderId: 'ORD-2',
                  orderNumber: '2',
                  goods: [good(productId: '200')],
                ),
              ],
            ),
          ),
          'ORD-1',
          productId: productId,
          exciseStamps: const [stampA],
        ),
      );
      final both = mustIssue(
        mustReserve(session, 'ORD-2', productId: '200', serialNumber: 'SN-2'),
        'ORD-2',
      );
      final firstBytes = Uint8List.fromList(
        asPrepared(export.prepare(session, now: stampClock)).document.bytes,
      );

      final prepared = asPrepared(export.prepare(both, now: stampClock));
      final text = utf8.decode(prepared.document.bytes);
      final root = _decode(text);
      final orders = (root.fields['orders']! as JsonArrayValue).items;
      final alcohol = orders.first as JsonObjectValue;
      final regular = orders.last as JsonObjectValue;
      final alcoholGood =
          (alcohol.fields['Goods']! as JsonArrayValue).items.single
              as JsonObjectValue;
      final regularGood =
          (regular.fields['Goods']! as JsonArrayValue).items.single
              as JsonObjectValue;

      expect(alcohol.fields['OrderID'], isA<JsonStringValue>());
      expect(
        (alcoholGood.fields['ProductID']! as JsonNumberValue).literal,
        productId,
      );
      expect(alcoholGood.fields.keys.toList(), [
        'ProductID',
        'Quantity',
        'Address',
        'SerialNumber',
        'ExciseStamp',
      ]);
      expect(
        (alcoholGood.fields['ExciseStamp']! as JsonStringValue).text,
        stampA,
      );
      expect(regularGood.fields.containsKey('ExciseStamp'), isFalse);
      expect(text, contains('"ProductID": $productId'));
      expect(text, isNot(contains('"ProductID": "$productId"')));
      expect(firstBytes, isNot(prepared.document.bytes));
      const fingerprint =
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
      expect(
        ExportConsistency.matches(
          dataset: prepared.pendingSession.dataset,
          fingerprint: fingerprint,
          snapshot: prepared.pendingSession.capture(
            datasetFingerprint: fingerprint,
          ),
          document: prepared.document,
          digest: DatasetFingerprint.of(prepared.document.bytes),
        ),
        isTrue,
      );
      final broken = Uint8List.fromList(
        utf8.encode(text.replaceFirst(stampA, 'qwer123456')),
      );
      expect(
        ExportConsistency.matches(
          dataset: prepared.pendingSession.dataset,
          fingerprint: fingerprint,
          snapshot: prepared.pendingSession.capture(
            datasetFingerprint: fingerprint,
          ),
          document: ExportDocument(
            filename: prepared.document.filename,
            bytes: broken,
            dateCreate: prepared.document.dateCreate,
          ),
          digest: DatasetFingerprint.of(broken),
        ),
        isFalse,
      );
    });

    test('different stamps on one serial stay separate records', () {
      const stampC = 'ZXCV112233';
      final opened = mustOpen(
        data(
          stocks: [slot(quantity: 3)],
          orders: [
            order(goods: [good(quantity: 3, alcohol: true)]),
          ],
        ),
      );
      final reserved = mustReserve(
        opened,
        'ORD-1',
        quantity: 3,
        exciseStamps: const [stampA, stampB, stampC],
      );
      final issued = mustIssue(reserved);
      final goods = export.reconstruct(issued).orders.single.goods;

      expect(export.reconstruct(issued).failures, isEmpty);
      expect(goods, hasLength(3));
      expectGood(
        goods[0],
        productId: '100',
        quantity: 1,
        address: 'A-01',
        serialNumber: 'SN-1',
        exciseStamp: stampA,
      );
      expectGood(
        goods[1],
        productId: '100',
        quantity: 1,
        address: 'A-01',
        serialNumber: 'SN-1',
        exciseStamp: stampB,
      );
      expectGood(
        goods[2],
        productId: '100',
        quantity: 1,
        address: 'A-01',
        serialNumber: 'SN-1',
        exciseStamp: stampC,
      );
    });

    test('exact stamp removal exports only the stamps that remain', () {
      const stampC = 'ZXCV112233';
      final opened = mustOpen(
        data(
          stocks: [slot(quantity: 3)],
          orders: [
            order(goods: [good(quantity: 3, alcohol: true)]),
          ],
        ),
      );
      final reserved = mustReserve(
        opened,
        'ORD-1',
        quantity: 3,
        exciseStamps: const [stampA, stampB, stampC],
      );
      final removed = switch (reserved.removeAlcoholUnit(
        orderId: 'ORD-1',
        productId: '100',
        address: 'A-01',
        serialNumber: 'SN-1',
        exciseStamp: stampB,
      )) {
        UnitsRemoved(:final session) => session,
        final other => fail('remove failed: $other'),
      };
      const replacement = 'HHHH445566';
      final completed = mustReserve(
        removed,
        'ORD-1',
        exciseStamps: const [replacement],
      );
      final issued = mustIssue(completed);
      final reconstructed = export.reconstruct(issued);
      final goods = reconstructed.orders.single.goods;

      expect(reconstructed.failures, isEmpty);
      expect(goods, hasLength(3));
      expectGood(
        goods[0],
        productId: '100',
        quantity: 1,
        address: 'A-01',
        serialNumber: 'SN-1',
        exciseStamp: stampA,
      );
      expectGood(
        goods[1],
        productId: '100',
        quantity: 1,
        address: 'A-01',
        serialNumber: 'SN-1',
        exciseStamp: stampC,
      );
      expectGood(
        goods[2],
        productId: '100',
        quantity: 1,
        address: 'A-01',
        serialNumber: 'SN-1',
        exciseStamp: replacement,
      );
      expect(goods.any((good) => good.exciseStamp == stampB), isFalse);
    });

    test('a second export still carries the earlier excise stamp', () {
      final opened = mustOpen(
        data(
          stocks: [slot(quantity: 2)],
          orders: [
            order(orderId: 'ORD-A', goods: [good(alcohol: true)]),
            order(
              orderId: 'ORD-B',
              orderNumber: '2',
              goods: [good(alcohol: true)],
            ),
          ],
        ),
      );
      final first = asPrepared(
        export.prepare(
          mustIssue(
            mustReserve(opened, 'ORD-A', exciseStamps: const [stampA]),
            'ORD-A',
          ),
          now: stampClock,
        ),
      );
      final historical = Uint8List.fromList(first.document.bytes);
      final second = asPrepared(
        export.prepare(
          mustIssue(
            mustReserve(
              first.pendingSession,
              'ORD-B',
              exciseStamps: const [stampB],
            ),
            'ORD-B',
          ),
          now: () => DateTime(2026, 10, 14, 16, 8, 9),
        ),
      );
      final text = utf8.decode(second.document.bytes);

      expect(first.document.bytes, historical);
      expect(text, contains('"OrderID": "ORD-A"'));
      expect(text, contains('"OrderID": "ORD-B"'));
      expect(text, contains('"ExciseStamp": "$stampA"'));
      expect(text, contains('"ExciseStamp": "$stampB"'));
      expect(second.pendingSession.statusOf('ORD-A'), OrderStatus.exported);
    });

    test('a missing or invalid excise stamp rejects that order', () {
      final missing = exciseStampExportFailure(
        isAlko: true,
        orderId: 'ORD-9',
        productId: productId,
        quantity: 1,
        stamps: const [],
      );
      final invalid = exciseStampExportFailure(
        isAlko: true,
        orderId: 'ORD-9',
        productId: productId,
        quantity: 1,
        stamps: const ['АBCD123456'],
      );
      final regular = exciseStampExportFailure(
        isAlko: false,
        orderId: 'ORD-9',
        productId: '100',
        quantity: 2,
        stamps: const [],
      );

      expect(missing!.reason, CumulativeExportReason.invalidExciseStamp);
      expect(missing.orderId, 'ORD-9');
      expect(missing.productId, productId);
      expect(invalid!.orderId, 'ORD-9');
      expect(invalid.reason, CumulativeExportReason.invalidExciseStamp);
      expect(regular, isNull);
    });
  });
}

DateTime Function() unreadClock() {
  return () => fail('The export clock was read');
}

DateTime stampClock() => DateTime(2026, 10, 14, 15, 7, 22);

CumulativeExportPrepared asPrepared(CumulativeExportResult result) {
  return switch (result) {
    CumulativeExportPrepared() && final prepared => prepared,
    final other => fail('expected a prepared export, got $other'),
  };
}

FulfilmentSession publishedSession(
  FulfilmentSession session,
  CumulativeExportResult result,
) {
  return switch (result) {
    CumulativeExportPrepared(:final pendingSession) => pendingSession,
    CumulativeExportUnchanged() || CumulativeExportRejected() => session,
  };
}

DatasetGood good({
  String product = 'Товар',
  String productId = '100',
  int quantity = 1,
  bool service = false,
  bool alcohol = false,
  String? parcelTtn,
}) {
  return DatasetGood(
    product: product,
    productId: ExactInteger(productId),
    quantity: quantity,
    priceMinorUnits: 100,
    amountMinorUnits: 100,
    isServiceGood: service,
    isParcel: parcelTtn != null,
    isAlko: alcohol,
    parcelTtn: parcelTtn,
  );
}

DatasetStock slot({
  String productId = '100',
  String address = 'A-01',
  String serialNumber = 'SN-1',
  int quantity = 5,
}) {
  return DatasetStock(
    address: address,
    productId: ExactInteger(productId),
    serialNumber: serialNumber,
    quantity: quantity,
  );
}

DatasetOrder order({
  String orderId = 'ORD-1',
  String orderNumber = '1',
  String invoiceNumber = 'INV',
  List<DatasetGood>? goods,
}) {
  final lines = goods ?? [good()];
  return DatasetOrder(
    orderId: orderId,
    invoiceDate: _created,
    invoiceNumber: invoiceNumber,
    orderNumber: ExactInteger(orderNumber),
    customer: 'Клієнт',
    customerPhone: '0501112233',
    totalMinorUnits: 100 * lines.length,
    goods: lines,
  );
}

RetailDataset data({
  String storeName = 'Магазин',
  String dbName = 'Store_01-A',
  required List<DatasetStock> stocks,
  required List<DatasetOrder> orders,
}) {
  return RetailDataset(
    storeName: storeName,
    dbName: dbName,
    dateCreate: _created,
    stocks: stocks,
    orders: orders,
  );
}

const _stamp = '20261014150722';
const _contractOrderId = '0350EAE5-C59E-11F1-BC2C-BE3AF2B6059F';
const _contractProductId = '1292834549023548345';

const _contractJson =
    '''{
  "storeName": "ТВ Київ Тест",
  "dbName": "retail_ki_kiev_test",
  "dateCreate": "$_stamp",
  "orders": [
    {
      "OrderID": "$_contractOrderId",
      "InvoiceNumber": "РОЗ234234234",
      "OrderNumber": 908222222,
      "Goods": [
        {
          "ProductID": $_contractProductId,
          "Quantity": 1,
          "Address": "AL.3.1.1.1",
          "SerialNumber": "\$PD777777"
        }
      ]
    }
  ]
}''';

FulfilmentSession contractSession() {
  const serialNumber = '\$PD777777';
  return mustIssue(
    mustReserve(
      mustOpen(
        data(
          storeName: 'ТВ Київ Тест',
          dbName: 'retail_ki_kiev_test',
          stocks: [
            slot(
              productId: _contractProductId,
              address: 'AL.3.1.1.1',
              serialNumber: serialNumber,
            ),
          ],
          orders: [
            order(
              orderId: _contractOrderId,
              orderNumber: '908222222',
              invoiceNumber: 'РОЗ234234234',
              goods: [good(productId: _contractProductId)],
            ),
          ],
        ),
      ),
      _contractOrderId,
      productId: _contractProductId,
      address: 'AL.3.1.1.1',
      serialNumber: serialNumber,
    ),
    _contractOrderId,
  );
}

Uint8List exportBytes(FulfilmentSession session, {String dateCreate = _stamp}) {
  final reconstruction = _export.reconstruct(session);
  expect(reconstruction.failures, isEmpty);
  return _export.writeExport(
    storeName: session.dataset.storeName,
    dbName: session.dataset.dbName,
    dateCreate: dateCreate,
    orders: reconstruction.orders,
  );
}

String written(FulfilmentSession session, {String dateCreate = _stamp}) {
  return utf8.decode(exportBytes(session, dateCreate: dateCreate));
}

JsonObjectValue _decode(String text) {
  return const PrecisionJsonDecoder().decode(text) as JsonObjectValue;
}

JsonObjectValue _singleOrder(JsonObjectValue root) {
  final orders = root.fields['orders']! as JsonArrayValue;
  return orders.items.single as JsonObjectValue;
}

List<JsonObjectValue> _goods(JsonObjectValue root) {
  final goods = _singleOrder(root).fields['Goods']! as JsonArrayValue;
  return [for (final item in goods.items) item as JsonObjectValue];
}

JsonObjectValue _singleGood(JsonObjectValue root) => _goods(root).single;

String _orderLiteral(String text) {
  final order = _singleOrder(_decode(text));
  return (order.fields['OrderNumber']! as JsonNumberValue).literal;
}

String _productLiteral(String text) {
  return (_singleGood(_decode(text)).fields['ProductID']! as JsonNumberValue)
      .literal;
}

String _quantityLiteral(String text) {
  return (_singleGood(_decode(text)).fields['Quantity']! as JsonNumberValue)
      .literal;
}

void _expectExportKeys(JsonObjectValue root) {
  expect(root.fields.keys.toList(), [
    'storeName',
    'dbName',
    'dateCreate',
    'orders',
  ]);
  final orders = root.fields['orders']! as JsonArrayValue;
  for (final item in orders.items) {
    final order = item as JsonObjectValue;
    expect(order.fields.keys.toList(), [
      'OrderID',
      'InvoiceNumber',
      'OrderNumber',
      'Goods',
    ]);
    expect(order.fields['OrderNumber'], isA<JsonNumberValue>());
    final goods = order.fields['Goods']! as JsonArrayValue;
    for (final line in goods.items) {
      final good = line as JsonObjectValue;
      expect(good.fields.keys.toList(), [
        'ProductID',
        'Quantity',
        'Address',
        'SerialNumber',
      ]);
      expect(good.fields['ProductID'], isA<JsonNumberValue>());
      expect(good.fields['Quantity'], isA<JsonNumberValue>());
      expect(good.fields['Address'], isA<JsonStringValue>());
      expect(good.fields['SerialNumber'], isA<JsonStringValue>());
    }
  }
}

FulfilmentSession mustOpen(RetailDataset dataset) {
  return switch (FulfilmentSession.open(dataset)) {
    DatasetOpened(:final session) => session,
    DatasetRejected(:final problem) => fail('dataset rejected: $problem'),
  };
}

FulfilmentSession mustReserve(
  FulfilmentSession session,
  String orderId, {
  String productId = '100',
  String address = 'A-01',
  String serialNumber = 'SN-1',
  int quantity = 1,
  List<String> exciseStamps = const [],
}) {
  return switch (session.reserve(
    orderId: orderId,
    productId: productId,
    address: address,
    serialNumber: serialNumber,
    quantity: quantity,
    exciseStamps: exciseStamps,
  )) {
    ReserveApplied(:final session) => session,
    final other => fail('reserve failed: $other'),
  };
}

FulfilmentSession issuedLiteral({
  String orderNumber = '1',
  String productId = '100',
}) {
  return mustIssue(
    mustReserve(
      mustOpen(
        data(
          stocks: [slot(productId: productId)],
          orders: [
            order(
              orderNumber: orderNumber,
              goods: [good(productId: productId)],
            ),
          ],
        ),
      ),
      'ORD-1',
      productId: productId,
    ),
  );
}

void expectGood(
  ReconstructedExportGood good, {
  required String productId,
  required int quantity,
  required String address,
  required String serialNumber,
  String? exciseStamp,
}) {
  expect(good.productId.literal, productId);
  expect(good.quantity, quantity);
  expect(good.address, address);
  expect(good.serialNumber, serialNumber);
  expect(good.exciseStamp, exciseStamp);
}

List<({String? orderId, CumulativeExportReason reason, String? productId})>
failureViews(CumulativeExportResult result) {
  return switch (result) {
    CumulativeExportRejected(:final failures) => [
      for (final failure in failures)
        (
          orderId: failure.orderId,
          reason: failure.reason,
          productId: failure.productId,
        ),
    ],
    _ => fail('expected a rejection, got $result'),
  };
}

FulfilmentSession mustIssue(
  FulfilmentSession session, [
  String orderId = 'ORD-1',
]) {
  return switch (session.issueOrder(orderId)) {
    OrderIssued(:final session) => session,
    final other => fail('issue failed: $other'),
  };
}

FulfilmentSession issued({String orderId = 'ORD-1'}) {
  return mustIssue(mustReserve(basic(), orderId), orderId);
}

FulfilmentSession basic() {
  return mustOpen(
    data(
      stocks: [slot()],
      orders: [
        order(goods: [good()]),
      ],
    ),
  );
}

FulfilmentSession mustExport(
  FulfilmentSession session, [
  String orderId = 'ORD-1',
]) {
  return switch (session.markExported(orderId)) {
    OrderMarkedExported(:final session) => session,
    final other => fail('export failed: $other'),
  };
}

FulfilmentSession readyAndPartial() {
  final opened = mustOpen(
    data(
      stocks: [slot(quantity: 10)],
      orders: [
        order(orderId: 'ORD-EXP', goods: [good()]),
        order(orderId: 'ORD-READY', orderNumber: '2', goods: [good()]),
        order(
          orderId: 'ORD-PART',
          orderNumber: '3',
          goods: [good(quantity: 2)],
        ),
      ],
    ),
  );
  final exported = mustExport(
    mustIssue(mustReserve(opened, 'ORD-EXP'), 'ORD-EXP'),
    'ORD-EXP',
  );
  final ready = mustReserve(exported, 'ORD-READY');
  return mustReserve(ready, 'ORD-PART');
}

int lineReserved(
  FulfilmentSession session, {
  String orderId = 'ORD-1',
  String productId = '100',
}) {
  return session.lineReservedQuantity(orderId: orderId, productId: productId);
}
