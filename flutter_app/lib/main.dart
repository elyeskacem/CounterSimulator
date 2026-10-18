import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'native_bridge.dart';
import 'notification_service.dart';
import 'ride_engine.dart';
import 'store.dart';
import 'ui/dashboard_screen.dart';
import 'ui/engine_scope.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

  final engine = RideEngine(store: Store(), notifier: NotificationService(), bridge: NativeBridge());
  // Loads the saved state, re-attaches to a running ride and starts the timers.
  await engine.init();

  runApp(MotoDashApp(engine: engine));
}

class MotoDashApp extends StatefulWidget {
  const MotoDashApp({super.key, required this.engine});

  final RideEngine engine;

  @override
  State<MotoDashApp> createState() => _MotoDashAppState();
}

class _MotoDashAppState extends State<MotoDashApp> with WidgetsBindingObserver {
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.engine.addListener(_syncWakelock);
    _syncWakelock();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.engine.removeListener(_syncWakelock);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    switch (state) {
      case AppLifecycleState.resumed:
        widget.engine.onResumed();
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        widget.engine.flushToDisk();
    }
    _syncWakelock();
  }

  bool? _wakelockOn;

  void _syncWakelock() {
    final want = widget.engine.state.settings.keepScreenOn && _lifecycle == AppLifecycleState.resumed;
    if (want == _wakelockOn) return;
    _wakelockOn = want;
    WakelockPlus.toggle(enable: want).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    return EngineScope(
      engine: widget.engine,
      child: MaterialApp(
        title: 'MotoDash',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const DashboardScreen(),
      ),
    );
  }
}
