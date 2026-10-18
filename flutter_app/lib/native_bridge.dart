import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Talks to the Swift side of the iOS app (ios/Runner/NativeBridge.swift):
/// the Dynamic Island / Lock Screen Live Activity, the "Always" location
/// permission and the "wake me up after iOS closed the app" monitor.
/// Every call is safe on platforms without the native side (tests, Windows):
/// it just does nothing.
class NativeBridge {
  NativeBridge({MethodChannel? channel}) : _channel = channel ?? const MethodChannel('motodash/native');

  final MethodChannel _channel;

  /// Set by the engine: the ↻ button in the expanded Dynamic Island was tapped.
  VoidCallback? onCycleMode;

  void attach() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'cycleMode') onCycleMode?.call();
      return null;
    });
  }

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('NativeBridge.$method failed: ${e.message}');
      return null;
    }
  }

  /// Starts the Live Activity. Returns null when it started (or when there is
  /// no native side), otherwise a message explaining why it did not.
  Future<String?> startActivity(int startedAtMs, Map<String, Object> state) async {
    final r = await _invoke<Map<Object?, Object?>>('activityStart', {'startedAt': startedAtMs, 'state': state});
    if (r == null) return null;
    return r['ok'] == true ? null : (r['message'] as String? ?? 'Live Activity unavailable');
  }

  Future<void> updateActivity(Map<String, Object> state) => _invoke<void>('activityUpdate', {'state': state});

  Future<void> endActivity(Map<String, Object> state) => _invoke<void>('activityEnd', {'state': state});

  /// True if a Live Activity is currently showing (null: unknown / no native side).
  Future<bool?> isActivityActive() => _invoke<bool>('activityIsActive');

  /// Asks iOS for the "Always" location permission (upgrade from "While Using").
  Future<void> requestAlwaysPermission() => _invoke<void>('requestAlways');

  /// While a ride is on, asks iOS to relaunch the app after a significant move
  /// if the system terminated it.
  Future<void> setRelaunchMonitor(bool enabled) => _invoke<void>('setRelaunchMonitor', {'enabled': enabled});
}
