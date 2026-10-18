import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:motodash/models.dart';
import 'package:motodash/native_bridge.dart';
import 'package:motodash/notification_service.dart';
import 'package:motodash/ride_engine.dart';
import 'package:motodash/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late RideEngine engine;
  late DateTime now;
  final t0 = DateTime(2026, 10, 18, 12);

  Position fix(double metersNorth, int seconds, {double accuracy = 8, double speed = 13.9}) {
    now = t0.add(Duration(seconds: seconds));
    return Position(
      latitude: 36.8 + metersNorth / 111320,
      longitude: 10.18,
      timestamp: now,
      accuracy: accuracy,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: speed,
      speedAccuracy: 0,
    );
  }

  void feed(Position p) {
    now = p.timestamp;
    engine.processPosition(p);
  }

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('motodash_test');
    now = t0;
    engine = RideEngine(
      store: Store(directory: dir),
      notifier: NotificationService(),
      bridge: NativeBridge(),
      clock: () => now,
    );
    await engine.init();
    engine.state.isRiding = true; // as if "Start ride" was tapped
  });

  tearDown(() async {
    engine.dispose();
    await engine.store.flush();
    dir.deleteSync(recursive: true);
  });

  test('60 s at 50 km/h adds ~0.83 km to odometer, trip, ride and fuel', () {
    final odo0 = engine.state.odoKm;
    feed(fix(0, 0));
    for (var i = 1; i <= 60; i++) {
      feed(fix(i * 13.9, i));
    }
    expect(engine.state.odoKm - odo0, closeTo(0.834, 0.01));
    expect(engine.state.trip.km, closeTo(0.834, 0.01));
    expect(engine.state.rideKm, closeTo(0.834, 0.01));
    expect(engine.state.fuelKm, closeTo(150 - 0.834, 0.01));
    expect(engine.speedKmh, closeTo(50, 1));
    expect(engine.state.trip.maxKmh, closeTo(50, 1));
    expect(engine.state.anchor, isNotNull);
  });

  test('standing still with GPS jitter adds nothing and shows 0 km/h', () {
    feed(fix(0, 0));
    final odo = engine.state.odoKm;
    for (var i = 1; i <= 30; i++) {
      feed(fix((i.isEven ? 2.0 : -2.0), i, accuracy: 10, speed: 0));
    }
    expect(engine.state.odoKm, odo);
    expect(engine.speedKmh, 0);
  });

  test('a 60 s GPS gap is estimated as a straight line', () {
    feed(fix(0, 0));
    feed(fix(13.9, 1));
    final before = engine.state.odoKm;
    feed(fix(13.9 + 1500, 61, speed: 12)); // moved 1.5 km while we were not running
    expect(engine.state.odoKm - before, closeTo(1.5, 0.01));
    expect(engine.events.first.kind, EventKind.gap);
  });

  test('a GPS jump (5 km in 1 s) is ignored', () {
    feed(fix(0, 0));
    feed(fix(13.9, 1));
    final before = engine.state.odoKm;
    feed(fix(5000, 2));
    expect(engine.state.odoKm, before);
  });

  test('fixes with poor accuracy are ignored', () {
    feed(fix(0, 0));
    final before = engine.state.odoKm;
    feed(fix(500, 1, accuracy: 120));
    expect(engine.state.odoKm, before);
  });

  test('riding past 11 000 km fires oil + milestone alerts, saved in history', () {
    engine.state.odoKm = 10999.95;
    feed(fix(0, 0));
    for (var i = 1; i <= 10; i++) {
      feed(fix(i * 13.9, i));
    }
    expect(engine.toasts.map((t) => t.title), contains('11 000 km: oil change time!'));
    expect(engine.events.map((e) => e.kind), contains(EventKind.milestone));
  });

  test('refuel adds 220 km and counts 20 DT; oil changed moves the next vidange', () async {
    engine.state
      ..odoKm = 11020
      ..fuelKm = 10;
    await engine.refuel();
    expect(engine.state.fuelKm, 230);
    expect(engine.state.fuelSpent, 20);
    expect(engine.state.kmSinceFill, 0);

    await engine.oilChanged();
    expect(engine.state.nextOilKm, 12020);
    expect(engine.events.map((e) => e.kind), containsAll([EventKind.fuel, EventKind.oil]));
  });

  test('state survives a restart (saved to the JSON file)', () async {
    engine.state.isRiding = false;
    await engine.setField(NumberField.odometer, 12000.5);
    await engine.setIslandMode(IslandMode.speed);

    final again = RideEngine(store: Store(directory: dir), notifier: NotificationService(), bridge: NativeBridge());
    await again.init();
    expect(again.state.odoKm, 12000.5);
    expect(again.state.settings.islandMode, IslandMode.speed);
    expect(again.events.first.kind, EventKind.edit);
    again.dispose();
  });

  test('Dynamic Island content follows the selected mode', () async {
    engine.state.rideKm = 4.26;
    expect(engine.contentState()['mode'], 'rideKm');
    expect(engine.contentState()['rideKm'], 4.3);
    engine.cycleIslandMode();
    expect(engine.state.settings.islandMode, IslandMode.speed);
    engine.cycleIslandMode();
    engine.cycleIslandMode();
    engine.cycleIslandMode();
    expect(engine.state.settings.islandMode, IslandMode.rideKm, reason: 'cycles back around');
  });

  test('factory reset goes back to 10 820 km / 150 km', () async {
    engine.state.isRiding = false;
    await engine.setField(NumberField.odometer, 20000);
    await engine.factoryReset();
    expect(engine.state.odoKm, 10820);
    expect(engine.state.fuelKm, 150);
    expect(engine.events, isEmpty);
  });
}
