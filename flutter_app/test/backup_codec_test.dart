import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:motodash/backup_codec.dart';
import 'package:motodash/models.dart';

// A file exactly as the WEB app exports it (see web/app.js exportBackup()).
const webBackup = '''
{
  "app": "motodash",
  "exportedAt": "2026-10-17T15:44:00.000Z",
  "state": {
    "version": 1,
    "odoKm": 11234.5,
    "fuelKm": 88.2,
    "kmSinceFill": 131.8,
    "lastOilKm": 11000,
    "appKm": 414.5,
    "fuelSpent": 40,
    "trip": {"km": 12.3, "movingMs": 1800000, "maxKmh": 77.4, "startedAt": 1760715000000},
    "flags": {"milestone": 11, "oilWarnTarget": null, "oilDueTarget": null, "oilOverdueStep": 0, "fuelWarned": false, "fuelEmpty": false},
    "settings": {"oilInterval": 1000, "oilWarn": 100, "fuelPerFill": 220, "fuelPrice": 20, "fuelWarn": 20, "sound": true, "wake": true, "gapFill": true, "sim": true, "simMul": 300},
    "updatedAt": 1760715900000
  },
  "events": [
    {"at": 1760700000000, "type": "fuel", "odo": 11000, "note": "Paid 20 DT"},
    {"at": 1760710000000, "type": "import", "odo": 11100, "note": "x"},
    {"at": 1760720000000, "type": "gap", "odo": 11200, "note": "gap"}
  ]
}
''';

void main() {
  test('imports a backup exported by the web app', () {
    final r = BackupCodec.decode(webBackup);
    expect(r.state.odoKm, 11234.5);
    expect(r.state.fuelKm, 88.2);
    expect(r.state.nextOilKm, 12000 - 1000 + 1000 - 0); // 11000 + 1000
    expect(r.state.trip.km, 12.3);
    expect(r.state.trip.startedAtMs, 1760715000000);
    expect(r.state.flags.milestone, 11);
    expect(r.state.flags.oilDueTarget, isNull);
    expect(r.state.settings.simMul, 300);
    expect(r.state.settings.sim, isFalse, reason: 'a simulated ride never survives an import');
    expect(r.state.isRiding, isFalse);
    expect(r.events.map((e) => e.kind), [EventKind.gap, EventKind.importBackup, EventKind.fuel],
        reason: 'newest first');
  });

  test('round trip keeps everything', () {
    final s = AppState()
      ..odoKm = 12345.6
      ..fuelKm = 42
      ..lastOilKm = 12000
      ..fuelSpent = 60
      ..settings.islandMode = IslandMode.speed
      ..trip.km = 3.3;
    s.flags.oilDueTarget = 13000;
    final events = [
      RideEvent(kind: EventKind.oil, odo: 12000, note: 'b', at: DateTime.fromMillisecondsSinceEpoch(2000)),
      RideEvent(kind: EventKind.fuel, odo: 11900, note: 'a', at: DateTime.fromMillisecondsSinceEpoch(1000)),
    ];
    final r = BackupCodec.decode(BackupCodec.encode(s, events));
    expect(r.state.odoKm, 12345.6);
    expect(r.state.settings.islandMode, IslandMode.speed);
    expect(r.state.flags.oilDueTarget, 13000);
    expect(r.state.trip.km, 3.3);
    expect(r.events.map((e) => e.note), ['b', 'a']);
  });

  test('exported file has the structure the web app expects', () {
    final j = jsonDecode(BackupCodec.encode(AppState(), [])) as Map<String, dynamic>;
    expect(j['app'], 'motodash');
    final st = j['state'] as Map<String, dynamic>;
    for (final k in ['odoKm', 'fuelKm', 'kmSinceFill', 'lastOilKm', 'appKm', 'fuelSpent', 'trip', 'flags', 'settings']) {
      expect(st.containsKey(k), isTrue, reason: k);
    }
    expect((st['trip'] as Map).containsKey('movingMs'), isTrue);
    expect(j['events'], isEmpty);
  });

  test('rejects files that are not a backup', () {
    expect(() => BackupCodec.decode('not json'), throwsA(isA<BackupException>()));
    expect(() => BackupCodec.decode('{"app":"other"}'), throwsA(isA<BackupException>()));
    expect(() => BackupCodec.decode('[1,2]'), throwsA(isA<BackupException>()));
  });

  test('a saved file from an older version (missing fields) still loads with defaults', () {
    final s = AppState.fromJson({'odoKm': 15000});
    expect(s.odoKm, 15000);
    expect(s.settings.oilInterval, 1000);
    expect(s.settings.islandMode, IslandMode.rideKm);
    expect(s.flags.milestone, 15, reason: 'no flags saved: do not re-announce past milestones');
  });
}
