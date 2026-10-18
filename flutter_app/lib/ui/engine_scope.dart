import 'package:flutter/widgets.dart';

import '../ride_engine.dart';

/// Gives every screen access to the engine and rebuilds it when the engine changes.
class EngineScope extends InheritedNotifier<RideEngine> {
  const EngineScope({super.key, required RideEngine engine, required super.child}) : super(notifier: engine);

  static RideEngine of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<EngineScope>();
    assert(scope != null, 'No EngineScope found');
    return scope!.notifier!;
  }
}
