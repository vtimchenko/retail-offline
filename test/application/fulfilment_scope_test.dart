import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/application/fulfilment_scope.dart';
import 'package:retail_offline/application/fulfilment_tab_coordinator.dart';
import 'package:retail_offline/application/fulfilment_ui_controller.dart';
import 'package:retail_offline/application/page_visibility.dart';
import 'package:retail_offline/persistence/browser/storage_change_notice.dart';
import 'package:retail_offline/persistence/fulfilment_repository.dart';

import '../support/memory_fulfilment_repository.dart';

void main() {
  group('FulfilmentScope', () {
    testWidgets('a subscribed descendant rebuilds with the current phase', (
      tester,
    ) async {
      final repository = _GatedRepository();
      final gate = Completer<void>();
      repository.loadGate = gate;
      final controller = _open(repository);
      final builds = <String>[];

      await tester.pumpWidget(
        FulfilmentScope(
          controller: controller,
          child: MaterialApp(
            home: _PhaseText(listen: true, prefix: 'of', builds: builds),
          ),
        ),
      );

      expect(find.text('of:loading'), findsOneWidget);
      expect(builds, ['loading']);

      gate.complete();
      await _pumpUntil(
        tester,
        () => find.text('of:empty').evaluate().isNotEmpty,
      );

      expect(find.text('of:empty'), findsOneWidget);
      expect(builds, ['loading', 'empty']);
      expect(controller.phase, FulfilmentUiPhase.empty);
      expect(controller.coordinator.isClosed, isFalse);
    });

    testWidgets('read does not subscribe the caller to notifications', (
      tester,
    ) async {
      final repository = _GatedRepository();
      final gate = Completer<void>();
      repository.loadGate = gate;
      final controller = _open(repository);
      final readerBuilds = <String>[];

      await tester.pumpWidget(
        FulfilmentScope(
          controller: controller,
          child: MaterialApp(
            home: Column(
              children: [
                const _PhaseText(listen: true, prefix: 'of'),
                _PhaseText(listen: false, prefix: 'read', builds: readerBuilds),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('of:loading'), findsOneWidget);
      expect(find.text('read:loading'), findsOneWidget);
      final readsWhileLoading = readerBuilds.length;
      expect(readsWhileLoading, greaterThan(0));

      gate.complete();
      await _pumpUntil(
        tester,
        () => find.text('of:empty').evaluate().isNotEmpty,
      );

      expect(find.text('of:empty'), findsOneWidget);
      expect(find.text('read:loading'), findsOneWidget);
      expect(readerBuilds, hasLength(readsWhileLoading));
      expect(controller.phase, FulfilmentUiPhase.empty);
    });

    testWidgets('a pushed route and the route under it both rebuild', (
      tester,
    ) async {
      final repository = _GatedRepository();
      final gate = Completer<void>();
      repository.loadGate = gate;
      final controller = _open(repository);
      final log = <String>[];

      await tester.pumpWidget(
        FulfilmentScope(
          controller: controller,
          child: MaterialApp(
            home: _RouteProbe(name: 'home', log: log),
          ),
        ),
      );
      expect(log, ['home:loading']);

      final homeContext = tester.element(find.text('home:loading'));
      Navigator.of(homeContext).push(
        PageRouteBuilder<void>(
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (context, animation, secondaryAnimation) {
            return _RouteProbe(name: 'pushed', log: log);
          },
        ),
      );
      await tester.pump();

      expect(log, ['home:loading', 'pushed:loading']);
      log.clear();
      gate.complete();
      await _pumpUntil(
        tester,
        () => log.contains('home:empty') && log.contains('pushed:empty'),
      );

      expect(log, contains('home:empty'));
      expect(log, contains('pushed:empty'));
      expect(find.text('home:empty', skipOffstage: false), findsOneWidget);
      expect(find.text('pushed:empty'), findsOneWidget);
      expect(controller.phase, FulfilmentUiPhase.empty);
    });

    testWidgets('of and read fail when no scope is an ancestor', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: _MissingScope(listen: true)),
      );
      final ofError = tester.takeException();
      expect(ofError, isFlutterError);
      expect(ofError.toString(), contains('FulfilmentScope.of'));

      await tester.pumpWidget(
        const MaterialApp(home: _MissingScope(listen: false)),
      );
      final readError = tester.takeException();
      expect(readError, isFlutterError);
      expect(readError.toString(), contains('FulfilmentScope.read'));
    });

    testWidgets('unmounting the scope leaves the controller alive', (
      tester,
    ) async {
      final repository = _GatedRepository();
      final gate = Completer<void>();
      repository.loadGate = gate;
      late FulfilmentUiController controller;

      await tester.pumpWidget(
        _Owner(
          repository: repository,
          showScope: true,
          onCreated: (created) => controller = created,
        ),
      );
      await _pumpUntil(tester, () => repository.loads == 1);

      expect(find.text('scoped:loading'), findsOneWidget);
      expect(controller.coordinator.isClosed, isFalse);

      await tester.pumpWidget(
        _Owner(
          repository: repository,
          showScope: false,
          onCreated: (created) => controller = created,
        ),
      );

      expect(find.byType(FulfilmentScope), findsNothing);
      expect(controller.coordinator.isClosed, isFalse);
      expect(controller.phase, FulfilmentUiPhase.loading);

      controller.dispose();
      expect(controller.coordinator.isClosed, isTrue);
      gate.complete();
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}

const _databaseName = 'retail-offline-test';

FulfilmentUiController _open(_GatedRepository repository) {
  final controller = FulfilmentUiController.open(
    repository: repository,
    databaseName: _databaseName,
    transport: _Transport(),
    visibility: _Pages(),
    senderId: 'scope-test',
  );
  addTearDown(controller.dispose);
  return controller;
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    if (done()) return;
    await tester.pump();
  }
  fail('timed out waiting for the scope');
}

class _Owner extends StatefulWidget {
  const _Owner({
    required this.repository,
    required this.showScope,
    required this.onCreated,
  });

  final _GatedRepository repository;
  final bool showScope;
  final ValueChanged<FulfilmentUiController> onCreated;

  @override
  State<_Owner> createState() => _OwnerState();
}

class _OwnerState extends State<_Owner> {
  late final FulfilmentUiController _controller;

  @override
  void initState() {
    super.initState();
    _controller = FulfilmentUiController.open(
      repository: widget.repository,
      databaseName: _databaseName,
      transport: _Transport(),
      visibility: _Pages(),
      senderId: 'scope-owner',
    );
    widget.onCreated(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showScope) return const SizedBox();
    return FulfilmentScope(
      controller: _controller,
      child: MaterialApp(
        home: Builder(
          builder: (context) {
            final phase = FulfilmentScope.of(context).phase;
            return Text('scoped:${phase.name}');
          },
        ),
      ),
    );
  }
}

class _PhaseText extends StatelessWidget {
  const _PhaseText({required this.listen, required this.prefix, this.builds});

  final bool listen;
  final String prefix;
  final List<String>? builds;

  @override
  Widget build(BuildContext context) {
    final phase = listen
        ? FulfilmentScope.of(context).phase
        : FulfilmentScope.read(context).phase;
    builds?.add(phase.name);
    return Text('$prefix:${phase.name}');
  }
}

class _RouteProbe extends StatelessWidget {
  const _RouteProbe({required this.name, required this.log});

  final String name;
  final List<String> log;

  @override
  Widget build(BuildContext context) {
    final phase = FulfilmentScope.of(context).phase;
    final observation = '$name:${phase.name}';
    log.add(observation);
    return Text(observation);
  }
}

class _MissingScope extends StatelessWidget {
  const _MissingScope({required this.listen});

  final bool listen;

  @override
  Widget build(BuildContext context) {
    if (listen) {
      FulfilmentScope.of(context);
    } else {
      FulfilmentScope.read(context);
    }
    return const SizedBox();
  }
}

final class _GatedRepository extends MemoryFulfilmentRepository {
  Completer<void>? loadGate;
  var loads = 0;

  @override
  Future<LoadResult> load() async {
    loads++;
    final gate = loadGate;
    loadGate = null;
    if (gate != null) await gate.future;
    return super.load();
  }
}

final class _Pages implements PageVisibility {
  var _closed = false;

  @override
  bool get isAvailable => !_closed;

  @override
  void listen(void Function() onResume) {}

  @override
  void close() {
    _closed = true;
  }
}

final class _Transport implements StorageChangeTransport {
  var _closed = false;

  @override
  bool get isAvailable => !_closed;

  @override
  bool publish(StorageChangeNotice notice) => !_closed;

  @override
  void listen(void Function(StorageChangeNotice notice) onNotice) {}

  @override
  void close() {
    _closed = true;
  }
}
