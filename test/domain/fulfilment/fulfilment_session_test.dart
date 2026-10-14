import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/domain/fulfilment/fulfilment_session.dart';
import 'package:retail_offline/models/exact_integer.dart';
import 'package:retail_offline/models/retail_dataset.dart';

/// Synthetic catalogue only. No real customers, phones, or products.
final _created = DateTime(2026, 10, 3, 11, 46, 18);

const _leftId = '1290564103789190763';
const _rightId = '1290564103789190764';

void main() {
  group('dataset', () {
    test('a valid dataset opens with an empty overlay', () {
      final dataset = data(
        stocks: [slot()],
        orders: [
          order(goods: [good()]),
        ],
      );
      final session = mustOpen(dataset);

      expect(session.dataset, same(dataset));
      expect(session.statusOf('ORD-1'), OrderStatus.noSelection);
      expect(session.statusOf('ORD-1')!.label, 'Без вибору');
      expect(available(session), 5);
      expect(lineReserved(session), 0);
    });

    test('duplicate stock keys are rejected and not summed', () {
      final result = FulfilmentSession.open(
        data(
          stocks: [slot(quantity: 2), slot(quantity: 9)],
          orders: [
            order(goods: [good()]),
          ],
        ),
      );

      final problem = switch (result) {
        DatasetRejected(:final problem) => problem,
        DatasetOpened() => fail('duplicate stock opened a session'),
      };
      expect(problem.reason, DatasetProblemReason.duplicateStock);
      expect(problem.productId, '100');
      expect(problem.address, 'A-01');
      expect(problem.serialNumber, 'SN-1');
    });

    test('the same serial at another address is a different slot', () {
      final session = mustOpen(
        data(
          stocks: [
            slot(address: 'A-01', quantity: 2),
            slot(address: 'B-02', quantity: 4),
          ],
          orders: [
            order(goods: [good(quantity: 2)]),
          ],
        ),
      );
      final reserved = mustApply(session, quantity: 2).session;

      expect(available(reserved), 0);
      expect(available(reserved, address: 'B-02'), 4);
    });

    test('the same address and serial on another product is another slot', () {
      final session = mustOpen(
        data(
          stocks: [
            slot(productId: '100', quantity: 2),
            slot(productId: '200', quantity: 3),
          ],
          orders: [
            order(
              goods: [
                good(productId: '100'),
                good(product: 'Інший', productId: '200'),
              ],
            ),
          ],
        ),
      );

      final reserved = mustApply(session, quantity: 1).session;
      expect(available(reserved, productId: '100'), 1);
      expect(available(reserved, productId: '200'), 3);
    });

    test('large ProductIDs that differ by one stay distinct', () {
      final session = mustOpen(
        data(
          stocks: [
            slot(productId: _leftId, quantity: 2),
            slot(productId: _rightId, quantity: 4),
          ],
          orders: [
            order(
              goods: [
                good(productId: _leftId, quantity: 2),
                good(product: 'Сусід', productId: _rightId, quantity: 2),
              ],
            ),
          ],
        ),
      );

      final reserved = mustApply(
        session,
        productId: _leftId,
        quantity: 2,
      ).session;

      expect(lineReserved(reserved, productId: _leftId), 2);
      expect(lineReserved(reserved, productId: _rightId), 0);
      expect(available(reserved, productId: _leftId), 0);
      expect(available(reserved, productId: _rightId), 4);
      expect(_leftId, hasLength(19));
      expect(_rightId, hasLength(19));
    });

    test('a repeated OrderID is rejected', () {
      final result = FulfilmentSession.open(
        data(
          stocks: [slot()],
          orders: [
            order(),
            order(orderId: 'ORD-1', orderNumber: '2'),
          ],
        ),
      );
      expect(switch (result) {
        DatasetRejected(:final problem) => problem.reason,
        DatasetOpened() => fail('duplicate order opened'),
      }, DatasetProblemReason.duplicateOrder);
    });

    test('a repeated ProductID inside one order is rejected', () {
      final result = FulfilmentSession.open(
        data(
          stocks: [slot(quantity: 4)],
          orders: [
            order(
              goods: [
                good(),
                good(product: 'Ще'),
              ],
            ),
          ],
        ),
      );
      expect(switch (result) {
        DatasetRejected(:final problem) => problem.reason,
        DatasetOpened() => fail('duplicate product opened'),
      }, DatasetProblemReason.duplicateProduct);
    });
  });

  group('reservations', () {
    test('reserves one unit and several units', () {
      final session = basic(stockQuantity: 5, lineQuantity: 4);
      final one = mustApply(session, quantity: 1);
      expect(one.appliedQuantity, 1);
      expect(slotReserved(one.session), 1);

      final several = mustApply(one.session, quantity: 3);
      expect(several.appliedQuantity, 3);
      expect(slotReserved(several.session), 4);
      expect(available(several.session), 1);
    });

    test('several orders share one stock slot', () {
      final session = mustOpen(
        data(
          stocks: [slot(quantity: 5)],
          orders: [
            order(orderId: 'ORD-1', goods: [good(quantity: 3)]),
            order(
              orderId: 'ORD-2',
              orderNumber: '2',
              goods: [good(quantity: 3)],
            ),
          ],
        ),
      );

      final first = mustApply(session, orderId: 'ORD-1', quantity: 3).session;
      final second = mustApply(first, orderId: 'ORD-2', quantity: 3);
      expect(second.appliedQuantity, 2);
      expect(lineReserved(second.session, orderId: 'ORD-1'), 3);
      expect(lineReserved(second.session, orderId: 'ORD-2'), 2);
      expect(available(second.session), 0);
    });

    test('ownership follows OrderID, not OrderNumber', () {
      final session = mustOpen(
        data(
          stocks: [slot(quantity: 4)],
          orders: [
            order(orderId: 'ORD-1', orderNumber: '77', goods: [good()]),
            order(orderId: 'ORD-2', orderNumber: '77', goods: [good()]),
          ],
        ),
      );
      final reserved = mustApply(session, orderId: 'ORD-1').session;

      expect(lineReserved(reserved, orderId: 'ORD-1'), 1);
      expect(lineReserved(reserved, orderId: 'ORD-2'), 0);
      expect(available(reserved), 3);
    });

    test('one line can hold several slots', () {
      final session = mustOpen(
        data(
          stocks: [
            slot(address: 'A-01', quantity: 2),
            slot(address: 'B-02', serialNumber: 'SN-2', quantity: 2),
          ],
          orders: [
            order(goods: [good(quantity: 3)]),
          ],
        ),
      );
      final first = mustApply(session, quantity: 2).session;
      final second = mustApply(
        first,
        address: 'B-02',
        serialNumber: 'SN-2',
        quantity: 2,
      );

      expect(second.appliedQuantity, 1);
      expect(slotReserved(second.session), 2);
      expect(
        slotReserved(second.session, address: 'B-02', serialNumber: 'SN-2'),
        1,
      );
      expect(lineReserved(second.session), 3);
    });

    test('does not take units from a slot that was not requested', () {
      final session = mustOpen(
        data(
          stocks: [
            slot(address: 'A-01', quantity: 1),
            slot(address: 'B-02', quantity: 5),
          ],
          orders: [
            order(goods: [good(quantity: 4)]),
          ],
        ),
      );
      final applied = mustApply(session, quantity: 4);

      expect(applied.appliedQuantity, 1);
      expect(available(applied.session, address: 'B-02'), 5);
      expect(
        session.availableQuantity(
          productId: '100',
          address: 'A-01',
          serialNumber: 'SN-1',
        ),
        1,
      );
    });

    test('a short slot applies only what is free', () {
      final session = basic(stockQuantity: 2, lineQuantity: 5);
      final applied = mustApply(session, quantity: 5);

      expect(applied.requestedQuantity, 5);
      expect(applied.appliedQuantity, 2);
      expect(slotReserved(applied.session), 2);
      expect(slotReserved(session), 0);
      expect(available(session), 2);
      expect(available(applied.session), 0);
      expect(applied.session.statusOf('ORD-1'), OrderStatus.inProgress);
    });

    test('zero availability returns InsufficientStock', () {
      final held = mustApply(
        mustOpen(
          data(
            stocks: [slot(quantity: 1)],
            orders: [
              order(orderId: 'ORD-1', goods: [good(quantity: 2)]),
              order(orderId: 'ORD-2', orderNumber: '2', goods: [good()]),
            ],
          ),
        ),
        orderId: 'ORD-1',
        quantity: 1,
      ).session;
      final result = held.reserve(
        orderId: 'ORD-2',
        productId: '100',
        address: 'A-01',
        serialNumber: 'SN-1',
        quantity: 1,
      );

      expect(result, isA<InsufficientStock>());
      expect(lineReserved(held, orderId: 'ORD-1'), 1);
      expect(lineReserved(held, orderId: 'ORD-2'), 0);
      expect(available(held), 0);
      expect(held.statusOf('ORD-1'), OrderStatus.inProgress);
    });

    test('a request above the remaining line need is capped', () {
      final session = basic(stockQuantity: 10, lineQuantity: 3);
      final applied = mustApply(session, quantity: 8);

      expect(applied.appliedQuantity, 3);
      expect(applied.session.statusOf('ORD-1'), OrderStatus.readyForIssue);
      expect(
        applied.session.reserve(
          orderId: 'ORD-1',
          productId: '100',
          address: 'A-01',
          serialNumber: 'SN-1',
          quantity: 1,
        ),
        isA<LineComplete>(),
      );
      expect(slotReserved(applied.session), 3);
    });

    test('rejects an unknown order, line, slot, or quantity', () {
      final session = basic();

      expect(
        rejection(
          session.reserve(
            orderId: 'ORD-1',
            productId: '100',
            address: 'A-01',
            serialNumber: 'SN-1',
            quantity: 0,
          ),
        ),
        ReserveRejection.invalidQuantity,
      );
      expect(
        rejection(
          session.reserve(
            orderId: 'MISSING',
            productId: '100',
            address: 'A-01',
            serialNumber: 'SN-1',
            quantity: 1,
          ),
        ),
        ReserveRejection.unknownOrder,
      );
      expect(
        rejection(
          session.reserve(
            orderId: 'ORD-1',
            productId: '999',
            address: 'A-01',
            serialNumber: 'SN-1',
            quantity: 1,
          ),
        ),
        ReserveRejection.unknownLine,
      );
      expect(
        rejection(
          session.reserve(
            orderId: 'ORD-1',
            productId: '100',
            address: 'Z-99',
            serialNumber: 'SN-1',
            quantity: 1,
          ),
        ),
        ReserveRejection.unknownStock,
      );
      expect(slotReserved(session), 0);
    });

    test('a service line cannot reserve stock', () {
      final session = mustOpen(
        data(
          stocks: [slot()],
          orders: [
            order(goods: [good(product: 'Послуга', service: true)]),
          ],
        ),
      );
      final result = session.reserve(
        orderId: 'ORD-1',
        productId: '100',
        address: 'A-01',
        serialNumber: 'SN-1',
        quantity: 1,
      );

      expect(rejection(result), ReserveRejection.serviceLine);
      expect(available(session), 5);
      expect(session.statusOf('ORD-1'), OrderStatus.readyForIssue);
    });

    test('a parcel accepts only its ParcelTTN', () {
      final session = mustOpen(
        data(
          stocks: [
            slot(serialNumber: 'TTN-1', quantity: 2),
            slot(serialNumber: 'OTHER', quantity: 2),
          ],
          orders: [
            order(goods: [good(quantity: 2, parcelTtn: 'TTN-1')]),
          ],
        ),
      );

      expect(
        rejection(
          session.reserve(
            orderId: 'ORD-1',
            productId: '100',
            address: 'A-01',
            serialNumber: 'OTHER',
            quantity: 1,
          ),
        ),
        ReserveRejection.parcelMismatch,
      );
      expect(slotReserved(session, serialNumber: 'OTHER'), 0);

      final applied = mustApply(session, serialNumber: 'TTN-1', quantity: 2);
      expect(applied.appliedQuantity, 2);
      expect(slotReserved(applied.session, serialNumber: 'TTN-1'), 2);
    });

    test('a parcel line can be split across addresses', () {
      final session = mustOpen(
        data(
          stocks: [
            slot(address: 'A-01', serialNumber: 'TTN-1', quantity: 2),
            slot(address: 'B-02', serialNumber: 'TTN-1', quantity: 3),
          ],
          orders: [
            order(goods: [good(quantity: 4, parcelTtn: 'TTN-1')]),
          ],
        ),
      );
      final first = mustApply(
        session,
        serialNumber: 'TTN-1',
        quantity: 2,
      ).session;
      final second = mustApply(
        first,
        address: 'B-02',
        serialNumber: 'TTN-1',
        quantity: 3,
      );

      expect(second.appliedQuantity, 2);
      expect(slotReserved(second.session, serialNumber: 'TTN-1'), 2);
      expect(
        slotReserved(second.session, address: 'B-02', serialNumber: 'TTN-1'),
        2,
      );
      expect(second.session.statusOf('ORD-1'), OrderStatus.readyForIssue);
    });

    test('stock identity is case-sensitive', () {
      final session = mustOpen(
        data(
          stocks: [
            slot(address: 'A-01', serialNumber: 'ABC'),
            slot(address: 'a-01', serialNumber: 'abc', quantity: 3),
          ],
          orders: [
            order(goods: [good(quantity: 2)]),
          ],
        ),
      );

      expect(
        rejection(
          session.reserve(
            orderId: 'ORD-1',
            productId: '100',
            address: 'A-01',
            serialNumber: 'abc',
            quantity: 1,
          ),
        ),
        ReserveRejection.unknownStock,
      );
      final applied = mustApply(session, serialNumber: 'ABC');
      expect(slotReserved(applied.session, serialNumber: 'ABC'), 1);
      expect(
        available(applied.session, address: 'a-01', serialNumber: 'abc'),
        3,
      );
    });

    test('a failed reserve does not publish a partial overlay', () {
      final session = basic(stockQuantity: 2, lineQuantity: 4);
      final result = session.reserve(
        orderId: 'ORD-1',
        productId: '100',
        address: 'MISSING',
        serialNumber: 'SN-1',
        quantity: 2,
      );

      expect(result, isA<ReserveRejected>());
      expect(lineReserved(session), 0);
      expect(available(session), 2);

      final applied = mustApply(session, quantity: 2);
      expect(applied.appliedQuantity, 2);
      expect(lineReserved(session), 0);
      expect(lineReserved(applied.session), 2);
    });
  });

  group('release', () {
    test('removes one unit or several and frees the stock', () {
      final session = mustOpen(
        data(
          stocks: [slot(quantity: 6)],
          orders: [
            order(orderId: 'ORD-1', goods: [good(quantity: 4)]),
            order(
              orderId: 'ORD-2',
              orderNumber: '2',
              goods: [good(quantity: 4)],
            ),
          ],
        ),
      );
      final held = mustApply(session, orderId: 'ORD-1', quantity: 4).session;
      final one = mustRemove(held, quantity: 1);
      expect(slotReserved(one), 3);
      expect(available(one), 3);

      final several = mustRemove(one, quantity: 2);
      expect(slotReserved(several), 1);
      expect(available(several), 5);
      final taken = mustApply(several, orderId: 'ORD-2', quantity: 4);
      expect(taken.appliedQuantity, 4);
      expect(lineReserved(taken.session, orderId: 'ORD-1'), 1);
    });

    test('rejects a removal larger than the reserved slot', () {
      final session = mustApply(basic(lineQuantity: 3), quantity: 2).session;
      final result = session.removeUnits(
        orderId: 'ORD-1',
        productId: '100',
        address: 'A-01',
        serialNumber: 'SN-1',
        quantity: 3,
      );

      expect(switch (result) {
        RemoveUnitsRejected(:final reason) => reason,
        UnitsRemoved() => fail('removed more than reserved'),
      }, RemoveRejection.insufficientReserved);
      expect(slotReserved(session), 2);
    });

    test('clear drops one order and leaves the other', () {
      final session = mustOpen(
        data(
          stocks: [
            slot(quantity: 8),
            slot(productId: '200', quantity: 2),
          ],
          orders: [
            order(
              orderId: 'ORD-1',
              goods: [
                good(productId: '100', quantity: 2),
                good(product: 'Другий', productId: '200', quantity: 1),
              ],
            ),
            order(
              orderId: 'ORD-2',
              orderNumber: '2',
              goods: [good(quantity: 2)],
            ),
          ],
        ),
      );
      var current = mustApply(session, quantity: 2).session;
      current = mustApply(current, productId: '200', quantity: 1).session;
      current = mustApply(current, orderId: 'ORD-2', quantity: 2).session;

      final cleared = switch (current.clearOrder('ORD-1')) {
        OrderCleared(:final session, :final clearedQuantity) => (
          session,
          clearedQuantity,
        ),
        ClearOrderRejected(:final reason) => fail('clear failed: $reason'),
      };

      expect(cleared.$2, 3);
      expect(lineReserved(cleared.$1, orderId: 'ORD-1'), 0);
      expect(lineReserved(cleared.$1, orderId: 'ORD-1', productId: '200'), 0);
      expect(lineReserved(cleared.$1, orderId: 'ORD-2'), 2);
      expect(available(cleared.$1), 6);
    });

    test('clearing an order with no reservations succeeds', () {
      final session = basic();
      final cleared = switch (session.clearOrder('ORD-1')) {
        OrderCleared(:final session, :final clearedQuantity) => (
          session,
          clearedQuantity,
        ),
        ClearOrderRejected(:final reason) => fail('clear failed: $reason'),
      };

      expect(cleared.$2, 0);
      expect(identical(cleared.$1, session), isTrue);
    });
  });

  group('status', () {
    test('reports the five labels', () {
      expect(OrderStatus.noSelection.label, 'Без вибору');
      expect(OrderStatus.inProgress.label, 'В процесі');
      expect(OrderStatus.readyForIssue.label, 'Готово до видачі');
      expect(OrderStatus.issued.label, 'Видано');
      expect(OrderStatus.exported.label, 'Експортовано');
    });

    test('moves an ordinary order from no selection to ready', () {
      final session = basic(stockQuantity: 2, lineQuantity: 2);
      expect(session.statusOf('ORD-1'), OrderStatus.noSelection);

      final partial = mustApply(session).session;
      expect(partial.statusOf('ORD-1'), OrderStatus.inProgress);

      final ready = mustApply(partial).session;
      expect(ready.statusOf('ORD-1'), OrderStatus.readyForIssue);
    });

    test('a service-only order is ready before any reservation', () {
      final session = mustOpen(
        data(
          stocks: [slot()],
          orders: [
            order(
              goods: [
                good(product: 'Доставка', productId: '100', service: true),
                good(product: 'Збірка', productId: '200', service: true),
              ],
            ),
          ],
        ),
      );

      expect(session.statusOf('ORD-1'), OrderStatus.readyForIssue);
      expect(lineReserved(session), 0);
      expect(lineReserved(session, productId: '200'), 0);
    });

    test('services in a mixed order do not count as reservation work', () {
      final session = mustOpen(
        data(
          stocks: [slot(quantity: 2)],
          orders: [
            order(
              goods: [
                good(product: 'Доставка', productId: '200', service: true),
                good(productId: '100', quantity: 2),
              ],
            ),
          ],
        ),
      );

      expect(session.statusOf('ORD-1'), OrderStatus.noSelection);
      final partial = mustApply(session).session;
      expect(partial.statusOf('ORD-1'), OrderStatus.inProgress);
      final ready = mustApply(partial).session;
      expect(ready.statusOf('ORD-1'), OrderStatus.readyForIssue);
      expect(lineReserved(ready, productId: '200'), 0);
    });

    test('issued and exported replace the derived ready state', () {
      final ready = mustApply(basic(stockQuantity: 1, lineQuantity: 1)).session;
      final issued = mustIssue(ready);
      expect(issued.statusOf('ORD-1'), OrderStatus.issued);
      expect(slotReserved(issued), 1);

      final exported = mustExport(issued);
      expect(exported.statusOf('ORD-1'), OrderStatus.exported);
      expect(slotReserved(exported), 1);
    });
  });

  group('issuance', () {
    test('rejects an order that is not ready', () {
      final session = basic(stockQuantity: 2, lineQuantity: 2);
      expect(issueReason(session.issueOrder('ORD-1')), IssueRejection.notReady);

      final partial = mustApply(session).session;
      expect(issueReason(partial.issueOrder('ORD-1')), IssueRejection.notReady);
      expect(partial.statusOf('ORD-1'), OrderStatus.inProgress);
    });

    test('issues a ready order and locks reservation edits', () {
      final ready = mustApply(
        basic(stockQuantity: 2, lineQuantity: 2),
        quantity: 2,
      ).session;
      final issued = mustIssue(ready);

      expect(issued.statusOf('ORD-1'), OrderStatus.issued);
      expect(slotReserved(issued), 2);
      expect(slotReserved(ready), 2);
      expect(ready.statusOf('ORD-1'), OrderStatus.readyForIssue);
      expect(
        rejection(
          issued.reserve(
            orderId: 'ORD-1',
            productId: '100',
            address: 'A-01',
            serialNumber: 'SN-1',
            quantity: 1,
          ),
        ),
        ReserveRejection.orderLocked,
      );
      expect(switch (issued.removeUnits(
        orderId: 'ORD-1',
        productId: '100',
        address: 'A-01',
        serialNumber: 'SN-1',
        quantity: 1,
      )) {
        RemoveUnitsRejected(:final reason) => reason,
        UnitsRemoved() => fail('issued order released stock'),
      }, RemoveRejection.orderLocked);
      expect(switch (issued.clearOrder('ORD-1')) {
        ClearOrderRejected(:final reason) => reason,
        OrderCleared() => fail('issued order was cleared'),
      }, ClearRejection.orderLocked);
      expect(slotReserved(issued), 2);
      expect(available(issued), 0);
    });

    test('an issued order keeps blocking the same stock', () {
      final session = mustOpen(
        data(
          stocks: [slot(quantity: 1)],
          orders: [
            order(orderId: 'ORD-1', goods: [good()]),
            order(orderId: 'ORD-2', orderNumber: '2', goods: [good()]),
          ],
        ),
      );
      final issued = mustIssue(mustApply(session).session);
      final result = issued.reserve(
        orderId: 'ORD-2',
        productId: '100',
        address: 'A-01',
        serialNumber: 'SN-1',
        quantity: 1,
      );

      expect(result, isA<InsufficientStock>());
      expect(issued.statusOf('ORD-1'), OrderStatus.issued);
      expect(available(issued), 0);
      expect(lineReserved(issued, orderId: 'ORD-2'), 0);
    });

    test('issues a service-only order', () {
      final session = mustOpen(
        data(
          stocks: [slot()],
          orders: [
            order(goods: [good(service: true)]),
          ],
        ),
      );
      final issued = mustIssue(session);

      expect(issued.statusOf('ORD-1'), OrderStatus.issued);
      expect(available(issued), 5);
    });

    test('cancel issuance keeps reservations and allows edits again', () {
      final ready = mustApply(
        basic(stockQuantity: 2, lineQuantity: 2),
        quantity: 2,
      ).session;
      final issued = mustIssue(ready);
      final cancelled = switch (issued.cancelIssuance('ORD-1')) {
        IssuanceCancelled(:final session) => session,
        CancelIssuanceRejected(:final reason) => fail('cancel failed: $reason'),
      };

      expect(cancelled.statusOf('ORD-1'), OrderStatus.readyForIssue);
      expect(slotReserved(cancelled), 2);
      expect(slotReserved(issued), 2);
      expect(available(cancelled), 0);

      final edited = mustRemove(cancelled, quantity: 1);
      expect(edited.statusOf('ORD-1'), OrderStatus.inProgress);
      expect(slotReserved(edited), 1);
      expect(available(edited), 1);
      expect(issued.statusOf('ORD-1'), OrderStatus.issued);
    });

    test('after cancel issuance the order can reserve and be cleared', () {
      final ready = mustApply(
        basic(stockQuantity: 2, lineQuantity: 2),
        quantity: 2,
      ).session;
      final issued = mustIssue(ready);
      final cancelled = switch (issued.cancelIssuance('ORD-1')) {
        IssuanceCancelled(:final session) => session,
        CancelIssuanceRejected(:final reason) => fail('cancel failed: $reason'),
      };

      final cleared = switch (cancelled.clearOrder('ORD-1')) {
        OrderCleared(:final session, :final clearedQuantity) => (
          session,
          clearedQuantity,
        ),
        ClearOrderRejected(:final reason) => fail('clear failed: $reason'),
      };
      expect(cleared.$2, 2);
      expect(cleared.$1.statusOf('ORD-1'), OrderStatus.noSelection);
      expect(slotReserved(issued), 2);

      final reserved = mustApply(cleared.$1);
      expect(reserved.appliedQuantity, 1);
      expect(slotReserved(reserved.session), 1);
      expect(available(reserved.session), 1);
      expect(issued.statusOf('ORD-1'), OrderStatus.issued);
    });

    test('an exported order cannot cancel issuance', () {
      final exported = mustExport(
        mustIssue(mustApply(basic(stockQuantity: 1, lineQuantity: 1)).session),
      );
      expect(switch (exported.cancelIssuance('ORD-1')) {
        CancelIssuanceRejected(:final reason) => reason,
        IssuanceCancelled() => fail('exported order was cancelled'),
      }, CancelRejection.exported);
      expect(exported.statusOf('ORD-1'), OrderStatus.exported);
      expect(slotReserved(exported), 1);
    });
  });

  group('exported state', () {
    test('marks an issued order exported', () {
      final issued = mustIssue(
        mustApply(basic(stockQuantity: 1, lineQuantity: 1)).session,
      );
      final exported = mustExport(issued);

      expect(exported.statusOf('ORD-1'), OrderStatus.exported);
      expect(issued.statusOf('ORD-1'), OrderStatus.issued);
      expect(slotReserved(exported), 1);
    });

    test('a second markExported returns alreadyExported', () {
      final exported = mustExport(
        mustIssue(mustApply(basic(stockQuantity: 1, lineQuantity: 1)).session),
      );

      expect(
        exportReason(exported.markExported('ORD-1')),
        MarkExportRejection.alreadyExported,
      );
      expect(exported.statusOf('ORD-1'), OrderStatus.exported);
      expect(slotReserved(exported), 1);
    });

    test('rejects export of an order that is not issued', () {
      final session = basic(stockQuantity: 1, lineQuantity: 1);
      expect(
        exportReason(session.markExported('ORD-1')),
        MarkExportRejection.notIssued,
      );

      final ready = mustApply(session).session;
      expect(
        exportReason(ready.markExported('ORD-1')),
        MarkExportRejection.notIssued,
      );
      expect(ready.statusOf('ORD-1'), OrderStatus.readyForIssue);
    });

    test('exported reservations still consume stock', () {
      final session = mustOpen(
        data(
          stocks: [slot(quantity: 1)],
          orders: [
            order(orderId: 'ORD-1', goods: [good()]),
            order(orderId: 'ORD-2', orderNumber: '2', goods: [good()]),
          ],
        ),
      );
      final exported = mustExport(mustIssue(mustApply(session).session));
      final result = exported.reserve(
        orderId: 'ORD-2',
        productId: '100',
        address: 'A-01',
        serialNumber: 'SN-1',
        quantity: 1,
      );

      expect(result, isA<InsufficientStock>());
      expect(available(exported), 0);
      expect(lineReserved(exported, orderId: 'ORD-2'), 0);
    });

    test('an exported order cannot change reservations', () {
      final exported = mustExport(
        mustIssue(
          mustApply(
            basic(stockQuantity: 2, lineQuantity: 2),
            quantity: 2,
          ).session,
        ),
      );

      expect(
        rejection(
          exported.reserve(
            orderId: 'ORD-1',
            productId: '100',
            address: 'A-01',
            serialNumber: 'SN-1',
            quantity: 1,
          ),
        ),
        ReserveRejection.orderLocked,
      );
      expect(switch (exported.removeUnits(
        orderId: 'ORD-1',
        productId: '100',
        address: 'A-01',
        serialNumber: 'SN-1',
        quantity: 1,
      )) {
        RemoveUnitsRejected(:final reason) => reason,
        UnitsRemoved() => fail('exported order released stock'),
      }, RemoveRejection.orderLocked);
      expect(switch (exported.clearOrder('ORD-1')) {
        ClearOrderRejected(:final reason) => reason,
        OrderCleared() => fail('exported order was cleared'),
      }, ClearRejection.orderLocked);
      expect(slotReserved(exported), 2);
    });
  });

  group('batch export', () {
    FulfilmentSession twoIssued() {
      final session = mustOpen(
        data(
          stocks: [slot(quantity: 2)],
          orders: [
            order(orderId: 'ORD-1', goods: [good()]),
            order(orderId: 'ORD-2', orderNumber: '2', goods: [good()]),
          ],
        ),
      );
      final reserved = mustApply(
        mustApply(session, orderId: 'ORD-1').session,
        orderId: 'ORD-2',
      ).session;
      return mustIssue(mustIssue(reserved, 'ORD-1'), 'ORD-2');
    }

    test('marks two issued orders in one session', () {
      final session = twoIssued();
      final marked = mustMarkExported(session, ['ORD-1', 'ORD-2']);

      expect(marked.statusOf('ORD-1'), OrderStatus.exported);
      expect(marked.statusOf('ORD-2'), OrderStatus.exported);
      expect(lineReserved(marked, orderId: 'ORD-1'), 1);
      expect(lineReserved(marked, orderId: 'ORD-2'), 1);
      expect(available(marked), 0);
      expect(session.statusOf('ORD-1'), OrderStatus.issued);
      expect(session.statusOf('ORD-2'), OrderStatus.issued);
    });

    test('one unissued order rejects the whole batch', () {
      final session = mustOpen(
        data(
          stocks: [slot(quantity: 2)],
          orders: [
            order(orderId: 'ORD-1', goods: [good()]),
            order(orderId: 'ORD-2', orderNumber: '2', goods: [good()]),
          ],
        ),
      );
      final issued = mustIssue(mustApply(session).session);
      final ready = mustApply(issued, orderId: 'ORD-2').session;
      final result = ready.markOrdersExported(['ORD-1', 'ORD-2']);

      expect(batchFailures(result), [
        (orderId: 'ORD-2', reason: BatchExportRejection.notIssued),
      ]);
      expect(ready.statusOf('ORD-1'), OrderStatus.issued);
      expect(ready.statusOf('ORD-2'), OrderStatus.readyForIssue);
      expect(lineReserved(ready, orderId: 'ORD-1'), 1);
      expect(lineReserved(ready, orderId: 'ORD-2'), 1);
      expect(available(ready), 0);
    });

    test('an unknown order rejects the batch without changes', () {
      final session = twoIssued();
      final result = session.markOrdersExported(['ORD-1', 'MISSING']);

      expect(batchFailures(result), [
        (orderId: 'MISSING', reason: BatchExportRejection.unknownOrder),
      ]);
      expect(session.statusOf('ORD-1'), OrderStatus.issued);
      expect(session.statusOf('ORD-2'), OrderStatus.issued);
      expect(available(session), 0);
    });

    test('an already exported order can be included', () {
      final issued = twoIssued();
      final first = mustExport(issued, 'ORD-1');
      final marked = mustMarkExported(first, ['ORD-1', 'ORD-2']);

      expect(marked.statusOf('ORD-1'), OrderStatus.exported);
      expect(marked.statusOf('ORD-2'), OrderStatus.exported);
      expect(lineReserved(marked, orderId: 'ORD-1'), 1);
      expect(available(marked), 0);
      expect(first.statusOf('ORD-1'), OrderStatus.exported);
      expect(first.statusOf('ORD-2'), OrderStatus.issued);
    });

    test('duplicate ids are exported once', () {
      final session = twoIssued();
      final marked = mustMarkExported(session, ['ORD-1', 'ORD-2', 'ORD-1']);

      expect(marked.statusOf('ORD-1'), OrderStatus.exported);
      expect(marked.statusOf('ORD-2'), OrderStatus.exported);
      expect(lineReserved(marked, orderId: 'ORD-1'), 1);
      expect(lineReserved(marked, orderId: 'ORD-2'), 1);
      expect(available(marked), 0);
    });

    test('the previous session stays unchanged after a batch', () {
      final session = twoIssued();
      final marked = mustMarkExported(session, ['ORD-2', 'ORD-1']);

      expect(marked.statusOf('ORD-1'), OrderStatus.exported);
      expect(marked.statusOf('ORD-2'), OrderStatus.exported);
      expect(session.statusOf('ORD-1'), OrderStatus.issued);
      expect(session.statusOf('ORD-2'), OrderStatus.issued);
      expect(lineReserved(session, orderId: 'ORD-1'), 1);
      expect(lineReserved(session, orderId: 'ORD-2'), 1);
      expect(available(session), 0);
    });
  });

  group('replacement', () {
    RetailDataset incoming() => data(
      dbName: 'Store_02-B',
      stocks: [slot(productId: '300', serialNumber: 'NEW')],
      orders: [
        order(
          orderId: 'NEW',
          goods: [good(productId: '300')],
        ),
      ],
    );

    test('active reservations block replacement', () {
      final session = mustApply(basic()).session;
      final result = session.replaceDataset(incoming());

      expect(
        switch (result) {
          ReplacementBlocked(:final orderIds) => orderIds,
          _ => fail('expected a block, got $result'),
        },
        ['ORD-1'],
      );
      expect(lineReserved(session), 1);
      expect(session.dataset.dbName, 'Store_01-A');
    });

    test('an issued order that is not exported blocks replacement', () {
      final ordinary = mustIssue(
        mustApply(basic(stockQuantity: 1, lineQuantity: 1)).session,
      );
      final serviceOnly = mustIssue(
        mustOpen(
          data(
            stocks: [slot()],
            orders: [
              order(goods: [good(service: true)]),
            ],
          ),
        ),
      );

      expect(
        switch (ordinary.replaceDataset(incoming())) {
          ReplacementBlocked(:final orderIds) => orderIds,
          _ => fail('issued order did not block'),
        },
        ['ORD-1'],
      );
      expect(
        switch (serviceOnly.replaceDataset(incoming())) {
          ReplacementBlocked(:final orderIds) => orderIds,
          _ => fail('issued service order did not block'),
        },
        ['ORD-1'],
      );
      expect(
        serviceOnly.lineReservedQuantity(orderId: 'ORD-1', productId: '100'),
        0,
      );
    });

    test('lists every blocking order in dataset order', () {
      final session = mustOpen(
        data(
          stocks: [slot(quantity: 4)],
          orders: [
            order(orderId: 'ORD-1', goods: [good(quantity: 2)]),
            order(
              orderId: 'ORD-2',
              orderNumber: '2',
              goods: [good(service: true)],
            ),
            order(orderId: 'ORD-3', orderNumber: '3', goods: [good()]),
          ],
        ),
      );
      var current = mustApply(session, quantity: 1).session;
      current = mustIssue(current, 'ORD-2');
      current = mustExport(
        mustIssue(mustApply(current, orderId: 'ORD-3').session, 'ORD-3'),
        'ORD-3',
      );

      expect(
        switch (current.replaceDataset(incoming())) {
          ReplacementBlocked(:final orderIds) => orderIds,
          _ => fail('expected ORD-1 and ORD-2 to block'),
        },
        ['ORD-1', 'ORD-2'],
      );
    });

    test('replacement is allowed after reservations are cleared', () {
      final session = mustApply(basic()).session;
      final cleared = switch (session.clearOrder('ORD-1')) {
        OrderCleared(:final session) => session,
        ClearOrderRejected(:final reason) => fail('clear failed: $reason'),
      };
      final replaced = mustReplace(cleared, incoming());

      expect(replaced.dataset.dbName, 'Store_02-B');
      expect(replaced.statusOf('NEW'), OrderStatus.noSelection);
      expect(replaced.statusOf('ORD-1'), isNull);
      expect(lineReserved(cleared), 0);
      expect(
        session.lineReservedQuantity(orderId: 'ORD-1', productId: '100'),
        1,
      );
    });

    test('replacement is allowed after export', () {
      final exported = mustExport(
        mustIssue(mustApply(basic(stockQuantity: 1, lineQuantity: 1)).session),
      );
      final replaced = mustReplace(exported, incoming());

      expect(replaced.statusOf('NEW'), OrderStatus.noSelection);
      expect(lineReserved(replaced, productId: '300'), 0);
      expect(exported.statusOf('ORD-1'), OrderStatus.exported);
      expect(slotReserved(exported), 1);
    });

    test('an unissued service-only order does not block', () {
      final session = mustOpen(
        data(
          stocks: [slot()],
          orders: [
            order(goods: [good(service: true)]),
          ],
        ),
      );

      expect(session.statusOf('ORD-1'), OrderStatus.readyForIssue);
      final replaced = mustReplace(session, incoming());
      expect(replaced.dataset.orders.single.orderId, 'NEW');
    });

    test('a failed replacement keeps the previous session', () {
      final session = mustApply(basic()).session;
      final blocked = session.replaceDataset(incoming());
      final invalid = session.replaceDataset(
        data(
          stocks: [slot(quantity: 2), slot(quantity: 4)],
          orders: [
            order(goods: [good()]),
          ],
        ),
      );

      expect(blocked, isA<ReplacementBlocked>());
      expect(switch (invalid) {
        ReplacementRejected(:final problem) => problem.reason,
        _ => fail('invalid dataset replaced the session'),
      }, DatasetProblemReason.duplicateStock);
      expect(identical(session.dataset.dbName, 'Store_01-A'), isTrue);
      expect(lineReserved(session), 1);
      expect(available(session), 4);
      expect(session.statusOf('ORD-1'), OrderStatus.inProgress);
    });

    test('the same dbName still follows the replacement rules', () {
      final next = data(
        stocks: [slot(serialNumber: 'NEW', quantity: 3)],
        orders: [
          order(orderId: 'NEW', goods: [good()]),
        ],
      );
      final busy = mustApply(basic()).session;
      expect(busy.replaceDataset(next), isA<ReplacementBlocked>());
      expect(lineReserved(busy), 1);

      final replaced = mustReplace(basic(), next);
      expect(replaced.dataset.dbName, 'Store_01-A');
      expect(replaced.statusOf('ORD-1'), isNull);
      expect(available(replaced, serialNumber: 'NEW'), 3);
    });
  });
}

DatasetGood good({
  String product = 'Товар',
  String productId = '100',
  int quantity = 1,
  bool service = false,
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
  List<DatasetGood>? goods,
}) {
  final lines = goods ?? [good()];
  return DatasetOrder(
    orderId: orderId,
    invoiceDate: _created,
    invoiceNumber: 'INV',
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

FulfilmentSession mustOpen(RetailDataset dataset) {
  return switch (FulfilmentSession.open(dataset)) {
    DatasetOpened(:final session) => session,
    DatasetRejected(:final problem) => fail('dataset rejected: $problem'),
  };
}

FulfilmentSession basic({int stockQuantity = 5, int lineQuantity = 2}) {
  return mustOpen(
    data(
      stocks: [slot(quantity: stockQuantity)],
      orders: [
        order(goods: [good(quantity: lineQuantity)]),
      ],
    ),
  );
}

ReserveApplied mustApply(
  FulfilmentSession session, {
  String orderId = 'ORD-1',
  String productId = '100',
  String address = 'A-01',
  String serialNumber = 'SN-1',
  int quantity = 1,
}) {
  return switch (session.reserve(
    orderId: orderId,
    productId: productId,
    address: address,
    serialNumber: serialNumber,
    quantity: quantity,
  )) {
    ReserveApplied() && final applied => applied,
    final other => fail('reserve failed: $other'),
  };
}

FulfilmentSession mustRemove(
  FulfilmentSession session, {
  String orderId = 'ORD-1',
  String productId = '100',
  String address = 'A-01',
  String serialNumber = 'SN-1',
  int quantity = 1,
}) {
  return switch (session.removeUnits(
    orderId: orderId,
    productId: productId,
    address: address,
    serialNumber: serialNumber,
    quantity: quantity,
  )) {
    UnitsRemoved(:final session) => session,
    final other => fail('remove failed: $other'),
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

FulfilmentSession mustExport(
  FulfilmentSession session, [
  String orderId = 'ORD-1',
]) {
  return switch (session.markExported(orderId)) {
    OrderMarkedExported(:final session) => session,
    final other => fail('export failed: $other'),
  };
}

FulfilmentSession mustMarkExported(
  FulfilmentSession session,
  Iterable<String> orderIds,
) {
  return switch (session.markOrdersExported(orderIds)) {
    OrdersMarkedExported(:final session) => session,
    final other => fail('batch export failed: $other'),
  };
}

List<({String orderId, BatchExportRejection reason})> batchFailures(
  MarkOrdersExportedResult result,
) {
  return switch (result) {
    MarkOrdersExportedRejected(:final failures) => [
      for (final failure in failures)
        (orderId: failure.orderId, reason: failure.reason),
    ],
    OrdersMarkedExported() => fail('batch export succeeded'),
  };
}

FulfilmentSession mustReplace(FulfilmentSession session, RetailDataset next) {
  return switch (session.replaceDataset(next)) {
    DatasetReplaced(:final session) => session,
    final other => fail('replace failed: $other'),
  };
}

ReserveRejection rejection(ReserveResult result) {
  return switch (result) {
    ReserveRejected(:final reason) => reason,
    final other => fail('expected a reserve rejection, got $other'),
  };
}

IssueRejection issueReason(IssueOrderResult result) {
  return switch (result) {
    IssueOrderRejected(:final reason) => reason,
    OrderIssued() => fail('order was issued'),
  };
}

MarkExportRejection exportReason(MarkExportedResult result) {
  return switch (result) {
    MarkExportedRejected(:final reason) => reason,
    OrderMarkedExported() => fail('order was exported'),
  };
}

int available(
  FulfilmentSession session, {
  String productId = '100',
  String address = 'A-01',
  String serialNumber = 'SN-1',
}) {
  return session.availableQuantity(
    productId: productId,
    address: address,
    serialNumber: serialNumber,
  );
}

int lineReserved(
  FulfilmentSession session, {
  String orderId = 'ORD-1',
  String productId = '100',
}) {
  return session.lineReservedQuantity(orderId: orderId, productId: productId);
}

int slotReserved(
  FulfilmentSession session, {
  String orderId = 'ORD-1',
  String productId = '100',
  String address = 'A-01',
  String serialNumber = 'SN-1',
}) {
  return session.slotReservedQuantity(
    orderId: orderId,
    productId: productId,
    address: address,
    serialNumber: serialNumber,
  );
}
