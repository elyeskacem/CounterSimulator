import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';

import 'backup_codec.dart';
import 'format.dart';
import 'models.dart';
import 'native_bridge.dart';
import 'notification_service.dart';
import 'reminders.dart';
import 'store.dart';

class Cfg {
  static const maxAccuracy = 40.0; // m: ignore GPS fixes worse than this
  static const gapSeconds = 20; // a longer silence = tracking was interrupted
  static const maxGapSeconds = 900; // ...but only estimate gaps up to 15 min
  static const glitchKmh = 220.0; // implied speed above this = GPS jump
  static const maxGapKmh = 130.0; // gap estimate only if the average speed is plausible
  static const staleSeconds = 6; // no fix for this long -> show 0 km/h
  static const maxEvents = 500;
}

enum NumberField { odometer, fuelKm, lastOil, oilInterval, oilWarn, fuelPerFill, fuelPrice, fuelWarn }

class _Fix {
  _Fix(this.lat, this.lon, this.time);
  final double lat;
  final double lon;
  final DateTime time;
}

/// Everything that moves: GPS, distance, reminders, notifications, Live Activity.
class RideEngine extends ChangeNotifier {
  RideEngine({required this.store, required this.notifier, required this.bridge, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final Store store;
  final NotificationService notifier;
  final NativeBridge bridge;
  final DateTime Function() _clock;

  AppState state = AppState();
  List<RideEvent> events = [];
  double speedKmh = 0;
  GpsStatus gpsStatus = GpsStatus.off;
  String gpsText = 'GPS off';
  final List<ToastMsg> toasts = [];
  LocationPermission locationPermission = LocationPermission.denied;
  bool notificationsEnabled = false;
  bool notificationsAsked = false;

  StreamSubscription<Position>? _posSub;
  _Fix? _lastFix;
  DateTime _lastFixAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _tickTimer;
  Timer? _simTimer;
  Timer? _saveTimer;
  bool _activityRunning = false;
  DateTime _lastPush = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastPushed;
  bool _askedAlways = false;
  int _toastId = 0;
  bool _disposed = false;

  double _simSpeed = 0;
  double _simTarget = 50;
  DateTime _simLast = DateTime.now();

  // ---------------------------------------------------------------- startup

  Future<void> init() async {
    state = await store.loadState() ?? AppState();
    events = await store.loadEvents();
    await notifier.init();
    bridge.onCycleMode = cycleIslandMode;
    bridge.attach();
    await refreshNotificationStatus();
    try {
      locationPermission = await Geolocator.checkPermission();
    } catch (_) {}

    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());

    if (state.isRiding) await _resumeRide();
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _tickTimer?.cancel();
    _simTimer?.cancel();
    _saveTimer?.cancel();
    _posSub?.cancel();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ----------------------------------------------------------- ride control

  Future<void> startRide() async {
    if (state.isRiding) return;
    if (!notificationsAsked && !notificationsEnabled) {
      notificationsAsked = true;
      unawaited(requestNotifications());
    }

    state
      ..isRiding = true
      ..rideKm = 0
      ..rideStartedAtMs = DateTime.now().millisecondsSinceEpoch
      ..anchor = null;
    _lastFix = null;
    _notify();

    await _beginTracking();
    await _startLiveActivity();
    await bridge.setRelaunchMonitor(true);
    await _saveNow();
  }

  Future<void> stopRide() async {
    if (!state.isRiding) return;
    _stopTracking();

    final started = state.rideStartedAtMs ?? DateTime.now().millisecondsSinceEpoch;
    state
      ..isRiding = false
      ..anchor = null;

    if (state.rideKm > 0.05) {
      final ms = (DateTime.now().millisecondsSinceEpoch - started).toDouble();
      _addEvent(RideEvent(
        kind: EventKind.ride,
        odo: state.odoKm,
        note: 'Ride ${Fmt.km1(state.rideKm)} km in ${Fmt.duration(ms)}',
      ));
    }

    _setSpeed(0, immediate: true);
    gpsStatus = GpsStatus.off;
    gpsText = 'GPS off';
    _notify();
    await bridge.setRelaunchMonitor(false);
    await _endLiveActivity();
    await _saveNow();
  }

  /// The app was relaunched (or reopened) while a ride was in progress.
  Future<void> _resumeRide() async {
    if (state.settings.sim) {
      state.isRiding = false; // a simulated ride can't survive a relaunch
      await _saveNow();
      return;
    }
    final a = state.anchor;
    if (a != null) {
      final time = DateTime.fromMillisecondsSinceEpoch(a.timeMs);
      if (DateTime.now().difference(time).inSeconds <= Cfg.maxGapSeconds) {
        // Lets the first new fix estimate the distance covered while we were not running.
        _lastFix = _Fix(a.lat, a.lon, time);
      }
    }
    await _beginTracking();
    _activityRunning = (await bridge.isActivityActive()) ?? false;
  }

  Future<void> _beginTracking() async {
    if (state.settings.sim) {
      _startSim();
      return;
    }
    _setGps(GpsStatus.searching, 'Searching…');

    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      locationPermission = perm;
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        _denyLocation();
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        _setGps(GpsStatus.denied, 'Location services off');
        showToast('Location services are off', 'Turn on Location Services in iOS Settings > Privacy.', AlertLevel.danger, seconds: 10);
        return;
      }
      if (perm == LocationPermission.whileInUse && !_askedAlways) {
        _askedAlways = true;
        unawaited(bridge.requestAlwaysPermission());
      }
      _startUpdates();
    } catch (e) {
      _setGps(GpsStatus.denied, 'GPS unavailable');
      debugPrint('GPS start failed: $e');
    }
  }

  void _startUpdates() {
    _posSub?.cancel();
    final LocationSettings settings = (!kIsWeb && Platform.isIOS)
        ? AppleSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            activityType: ActivityType.automotiveNavigation,
            distanceFilter: 0,
            pauseLocationUpdatesAutomatically: false,
            showBackgroundLocationIndicator: true,
            allowBackgroundLocationUpdates: true,
          )
        : const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 0);
    _posSub = Geolocator.getPositionStream(locationSettings: settings).listen(
      processPosition,
      onError: (Object e) {
        _setGps(GpsStatus.searching, 'GPS error');
        _notify();
      },
    );
  }

  void _stopTracking() {
    _posSub?.cancel();
    _posSub = null;
    _simTimer?.cancel();
    _simTimer = null;
    _lastFix = null;
  }

  void _denyLocation() {
    _setGps(GpsStatus.denied, 'No permission');
    showToast('Location is off', 'iOS Settings > MotoDash > Location: choose "Always" (or "While Using").', AlertLevel.danger, seconds: 10);
  }

  void _setGps(GpsStatus status, String text) {
    gpsStatus = status;
    gpsText = text;
    _notify();
  }

  Future<void> openLocationSettings() async {
    await Geolocator.openAppSettings();
  }

  Future<void> refreshLocationPermission() async {
    try {
      locationPermission = await Geolocator.checkPermission();
      _notify();
    } catch (_) {}
  }

  // ------------------------------------------------------- GPS processing

  /// One GPS fix. Public so tests can feed positions without a GPS.
  @visibleForTesting
  void processPosition(Position p) {
    if (!state.isRiding || state.settings.sim) return;
    final acc = p.accuracy;
    if (acc < 0) return;

    _setGps(
      acc <= 15 ? GpsStatus.good : (acc <= Cfg.maxAccuracy ? GpsStatus.weak : GpsStatus.searching),
      'GPS ±${acc.round()} m',
    );
    if (acc > Cfg.maxAccuracy) return;
    final now = _clock();
    if (now.difference(p.timestamp).inSeconds.abs() > 10) return; // cached, old fix

    final double? gpsKmh = p.speed >= 0 ? p.speed * 3.6 : null;

    final prev = _lastFix;
    if (prev == null) {
      _lastFix = _Fix(p.latitude, p.longitude, p.timestamp);
      _lastFixAt = now;
      _setSpeed(gpsKmh ?? 0);
      _saveAnchor(p);
      return;
    }

    final dt = p.timestamp.difference(prev.time).inMilliseconds / 1000.0;
    if (dt <= 0) return;
    final d = Geolocator.distanceBetween(prev.lat, prev.lon, p.latitude, p.longitude); // meters
    final implied = d / dt * 3.6;

    if (dt > Cfg.gapSeconds) {
      // Tracking was interrupted (app terminated and relaunched, or GPS lost).
      if (state.settings.gapFill && dt <= Cfg.maxGapSeconds && d > 50 && implied < Cfg.maxGapKmh) {
        final km = d / 1000;
        _addDistance(km, 0);
        _addEvent(RideEvent(
          kind: EventKind.gap,
          odo: state.odoKm,
          note: 'Estimated ${Fmt.km1(km)} km while tracking was interrupted (${dt.round()} s)',
        ));
        showToast('Distance estimated', '+${Fmt.km1(km)} km (straight line) while tracking was interrupted.', AlertLevel.info);
      }
      _lastFix = _Fix(p.latitude, p.longitude, p.timestamp);
      _lastFixAt = now;
      _setSpeed(gpsKmh ?? 0);
      _saveAnchor(p);
      return;
    }

    if (implied > Cfg.glitchKmh) return; // GPS jump: wait for a sane fix

    _lastFixAt = now;
    final kmh = gpsKmh ?? implied;
    final jitter = math.max(5.0, acc * 0.5);

    if (d < jitter && kmh < 4) {
      // Standing still: keep the anchor position, only advance its time.
      _lastFix = _Fix(prev.lat, prev.lon, p.timestamp);
      _setSpeed(0);
      return;
    }

    _addDistance(d / 1000, kmh >= 3 ? dt : 0);
    _lastFix = _Fix(p.latitude, p.longitude, p.timestamp);
    _setSpeed(kmh);
    _saveAnchor(p);
  }

  void _saveAnchor(Position p) {
    state.anchor = Anchor(p.latitude, p.longitude, p.timestamp.millisecondsSinceEpoch);
    _scheduleSave();
  }

  void _setSpeed(double kmh, {bool immediate = false}) {
    final target = kmh.clamp(0.0, 300.0);
    var v = immediate ? target : speedKmh * 0.35 + target * 0.65;
    if (v < 1.5) v = 0;
    speedKmh = v;
    if (state.isRiding && v > state.trip.maxKmh) state.trip.maxKmh = v;
    _notify();
  }

  void _addDistance(double km, double movingSeconds) {
    if (km <= 0) return;
    final s = state;
    s.odoKm += km;
    s.appKm += km;
    s.rideKm += km;
    s.trip.km += km;
    s.trip.movingMs += movingSeconds * 1000;
    s.fuelKm -= km;
    s.kmSinceFill += km;
    _apply(Reminders.check(s));
    _scheduleSave();
    _pushActivity();
    _notify();
  }

  void _tick() {
    if (state.isRiding &&
        !state.settings.sim &&
        speedKmh > 0 &&
        _clock().difference(_lastFixAt).inSeconds > Cfg.staleSeconds) {
      _setSpeed(0, immediate: true);
    }
    _pushActivity();
  }

  // ------------------------------------------- simulation (test without riding)

  void _startSim() {
    _setGps(GpsStatus.sim, 'SIM ×${state.settings.simMul.round()}');
    _simSpeed = 0;
    _simTarget = 50;
    _simLast = DateTime.now();
    _simTimer?.cancel();
    _simTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => _simStep());
  }

  final math.Random _rng = math.Random();

  void _simStep() {
    final now = DateTime.now();
    final dt = now.difference(_simLast).inMilliseconds / 1000.0;
    _simLast = now;
    if (_rng.nextDouble() < 0.06) {
      _simTarget = _rng.nextDouble() < 0.12 ? 0 : 25 + _rng.nextDouble() * 85;
    }
    final delta = _simTarget - _simSpeed;
    _simSpeed += delta.clamp(-12 * dt, 6 * dt);
    _simSpeed = math.max(0, _simSpeed + (_rng.nextDouble() - 0.5) * 1.5);
    final mul = math.max(1.0, state.settings.simMul);
    _lastFixAt = now;
    _setSpeed(_simSpeed);
    _addDistance(_simSpeed / 3600 * dt * mul, _simSpeed >= 3 ? dt * mul : 0);
  }

  // --------------------------------------------------------------- actions

  Future<void> refuel() async {
    final st = state.settings;
    final since = state.kmSinceFill;
    state
      ..fuelKm = math.max(0.0, state.fuelKm) + st.fuelPerFill
      ..fuelSpent += st.fuelPrice
      ..kmSinceFill = 0;
    Reminders.resetFuelFlags(state);
    _addEvent(RideEvent(
      kind: EventKind.fuel,
      odo: state.odoKm,
      note: 'Paid ${Fmt.intGrouped(st.fuelPrice)} DT, ${since.round()} km since previous fill',
    ));
    showToast('Fuel added', '+${Fmt.intGrouped(st.fuelPerFill)} km of range · ${Fmt.intGrouped(st.fuelPrice)} DT', AlertLevel.ok);
    _pushActivity(force: true);
    _notify();
    await _saveNow();
  }

  Future<void> oilChanged() async {
    state.lastOilKm = state.odoKm.floorToDouble();
    Reminders.resetOilFlags(state);
    _addEvent(RideEvent(
      kind: EventKind.oil,
      odo: state.odoKm,
      note: 'Oil changed, next at ${Fmt.intGrouped(state.nextOilKm)} km',
    ));
    showToast('Oil change saved', 'Next vidange at ${Fmt.intGrouped(state.nextOilKm)} km', AlertLevel.ok);
    _pushActivity(force: true);
    _notify();
    await _saveNow();
  }

  Future<void> resetTrip() async {
    final t = state.trip;
    if (t.km > 0.05) {
      _addEvent(RideEvent(
        kind: EventKind.trip,
        odo: state.odoKm,
        note: 'Trip ${Fmt.km1(t.km)} km · ${Fmt.duration(t.movingMs)} · max ${t.maxKmh.round()} km/h',
      ));
    }
    state.trip = Trip();
    _pushActivity(force: true);
    _notify();
    await _saveNow();
  }

  double valueOf(NumberField f) {
    switch (f) {
      case NumberField.odometer:
        return state.odoKm;
      case NumberField.fuelKm:
        return state.fuelKm;
      case NumberField.lastOil:
        return state.lastOilKm;
      case NumberField.oilInterval:
        return state.settings.oilInterval;
      case NumberField.oilWarn:
        return state.settings.oilWarn;
      case NumberField.fuelPerFill:
        return state.settings.fuelPerFill;
      case NumberField.fuelPrice:
        return state.settings.fuelPrice;
      case NumberField.fuelWarn:
        return state.settings.fuelWarn;
    }
  }

  Future<void> setField(NumberField f, double v) async {
    if (!v.isFinite || v < 0) return;
    final s = state;
    switch (f) {
      case NumberField.odometer:
        final old = s.odoKm;
        s.odoKm = v;
        s.flags.milestone = (v / 1000).floor();
        _addEvent(RideEvent(
          kind: EventKind.edit,
          odo: v,
          note: 'Odometer set from ${Fmt.km1(old)} to ${Fmt.km1(v)} km',
        ));
      case NumberField.fuelKm:
        s.fuelKm = v;
        Reminders.resetFuelFlags(s);
      case NumberField.lastOil:
        s.lastOilKm = v;
        Reminders.resetOilFlags(s);
      case NumberField.oilInterval:
        s.settings.oilInterval = math.max(1, v);
        Reminders.resetOilFlags(s);
      case NumberField.oilWarn:
        s.settings.oilWarn = v;
        Reminders.resetOilFlags(s);
      case NumberField.fuelPerFill:
        s.settings.fuelPerFill = math.max(1, v);
      case NumberField.fuelPrice:
        s.settings.fuelPrice = v;
      case NumberField.fuelWarn:
        s.settings.fuelWarn = v;
        Reminders.resetFuelFlags(s);
    }
    _apply(Reminders.check(s));
    _pushActivity(force: true);
    _notify();
    await _saveNow();
  }

  Future<void> updateSettings(void Function(AppSettings s) change) async {
    change(state.settings);
    _notify();
    await _saveNow();
  }

  Future<void> setIslandMode(IslandMode mode) async {
    await updateSettings((s) => s.islandMode = mode);
    _pushActivity(force: true);
  }

  void cycleIslandMode() => setIslandMode(state.settings.islandMode.next);

  Future<void> setSimulation(bool on) async {
    if (state.isRiding) await stopRide();
    await updateSettings((s) => s.sim = on);
  }

  Future<void> factoryReset() async {
    if (state.isRiding) await stopRide();
    state = AppState();
    events = [];
    unawaited(store.saveEvents(events));
    _setSpeed(0, immediate: true);
    showToast('Reset done', 'Back to 10 820 km and 150 km of fuel.', AlertLevel.ok);
    _notify();
    await _saveNow();
  }

  // ---------------------------------------------------------------- backup

  Future<File> exportBackupFile() async {
    final dir = await getTemporaryDirectory();
    final day = DateTime.now().toIso8601String().substring(0, 10);
    final file = File('${dir.path}/motodash-$day.json');
    return file.writeAsString(BackupCodec.encode(state, events), flush: true);
  }

  Future<void> importBackupText(String text) async {
    try {
      final decoded = BackupCodec.decode(text);
      if (state.isRiding) await stopRide();
      state = decoded.state;
      events = decoded.events;
      _addEvent(RideEvent(kind: EventKind.importBackup, odo: state.odoKm, note: 'Backup restored'));
      showToast('Backup restored', 'Odometer ${Fmt.intGrouped(state.odoKm)} km', AlertLevel.ok);
      _notify();
      await _saveNow();
    } on BackupException catch (e) {
      showToast('Import failed', e.message, AlertLevel.danger, seconds: 8);
    }
  }

  // -------------------------------------------------- events, saving, toasts

  void _addEvent(RideEvent e) {
    events.insert(0, e);
    if (events.length > Cfg.maxEvents) events.removeRange(Cfg.maxEvents, events.length);
    unawaited(store.saveEvents(events));
  }

  void _scheduleSave() {
    _saveTimer ??= Timer(const Duration(seconds: 2), () {
      _saveTimer = null;
      unawaited(store.saveState(state));
    });
  }

  Future<void> _saveNow() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    await store.saveState(state);
  }

  /// Called when the app goes to the background: make sure nothing is lost.
  Future<void> flushToDisk() => _saveNow();

  void showToast(String title, String body, AlertLevel level, {int seconds = 6}) {
    final id = ++_toastId;
    toasts.insert(0, ToastMsg(id, title, body, level));
    _notify();
    Timer(Duration(seconds: seconds), () => dismissToast(id));
  }

  void dismissToast(int id) {
    toasts.removeWhere((t) => t.id == id);
    _notify();
  }

  void _apply(ReminderResult r) {
    for (final e in r.events) {
      _addEvent(e);
    }
    for (final a in r.alerts) {
      _announce(a);
    }
  }

  void _announce(PendingAlert a) {
    showToast(a.title, a.body, a.level, seconds: a.level == AlertLevel.danger ? 12 : 8);
    unawaited(notifier.show(thread: a.id, title: a.title, body: a.body, sound: state.settings.sound));
  }

  Future<void> requestNotifications() async {
    await notifier.requestPermission();
    await refreshNotificationStatus();
  }

  Future<void> refreshNotificationStatus() async {
    notificationsEnabled = await notifier.isEnabled();
    _notify();
  }

  // ---------------------------------------------- Live Activity (Dynamic Island)

  Map<String, Object> contentState() {
    final s = state;
    return {
      'speedKmh': speedKmh.round(),
      'rideKm': (s.rideKm * 10).round() / 10,
      'tripKm': (s.trip.km * 10).round() / 10,
      'odoKm': s.odoKm.floorToDouble(),
      'fuelLeftKm': math.max(0.0, s.fuelKm).floor(),
      'oilLeftKm': s.oilLeftKm.floor(),
      'mode': s.settings.islandMode.name,
    };
  }

  Future<void> _startLiveActivity() async {
    final problem = await bridge.startActivity(
      state.rideStartedAtMs ?? DateTime.now().millisecondsSinceEpoch,
      contentState(),
    );
    if (problem == null) {
      _activityRunning = true;
      _lastPushed = jsonEncode(contentState());
      _lastPush = DateTime.now();
    } else {
      _activityRunning = false;
      showToast('Dynamic Island unavailable', problem, AlertLevel.warn, seconds: 8);
    }
  }

  /// Re-create the Live Activity if the user swiped it away or it hit iOS's 8-hour limit.
  Future<void> onResumed() async {
    await refreshNotificationStatus();
    await refreshLocationPermission();
    if (state.isRiding && !state.settings.sim) {
      final active = await bridge.isActivityActive();
      if (active == false) await _startLiveActivity();
    }
  }

  Future<void> _endLiveActivity() async {
    if (!_activityRunning) return;
    _activityRunning = false;
    _lastPushed = null;
    await bridge.endActivity(contentState());
  }

  void _pushActivity({bool force = false}) {
    if (!_activityRunning) return;
    final content = contentState();
    final encoded = jsonEncode(content);
    if (!force) {
      if (DateTime.now().difference(_lastPush).inMilliseconds < 1000) return;
      if (encoded == _lastPushed) return;
    }
    _lastPush = DateTime.now();
    _lastPushed = encoded;
    unawaited(bridge.updateActivity(content));
  }
}
