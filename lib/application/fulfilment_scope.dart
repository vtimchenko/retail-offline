import 'package:flutter/widgets.dart';

import 'fulfilment_ui_controller.dart';

/// Exposes one [FulfilmentUiController] to descendant widgets.
///
/// The scope does not create, copy, or dispose [controller]. The owner that
/// builds this widget keeps that responsibility. Place the scope above a
/// [Navigator] so pushed routes can subscribe.
class FulfilmentScope extends InheritedNotifier<FulfilmentUiController> {
  /// Publishes [controller] to [child] and its descendants.
  const FulfilmentScope({
    super.key,
    required FulfilmentUiController controller,
    required super.child,
  }) : super(notifier: controller);

  /// Returns the controller and registers [context] to rebuild.
  ///
  /// Call this from [build]. Throws [FlutterError] when no
  /// [FulfilmentScope] is an ancestor of [context].
  static FulfilmentUiController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<FulfilmentScope>();
    return _controllerOf(scope, 'FulfilmentScope.of');
  }

  /// Returns the controller without registering [context] to rebuild.
  ///
  /// Use this from callbacks and after an `await`, where [of] must not
  /// subscribe. Throws [FlutterError] when no [FulfilmentScope] is an
  /// ancestor of [context].
  static FulfilmentUiController read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<FulfilmentScope>();
    return _controllerOf(scope, 'FulfilmentScope.read');
  }

  static FulfilmentUiController _controllerOf(
    FulfilmentScope? scope,
    String lookup,
  ) {
    final controller = scope?.notifier;
    if (controller == null) {
      throw FlutterError(
        '$lookup was called with a context that has no FulfilmentScope ancestor.',
      );
    }
    return controller;
  }
}
