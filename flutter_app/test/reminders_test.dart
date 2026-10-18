import 'package:flutter_test/flutter_test.dart';
import 'package:motodash/models.dart';
import 'package:motodash/reminders.dart';

List<String> titles(ReminderResult r) => r.alerts.map((a) => a.title).toList();

void main() {
  test('starts at 10 820 km, 150 km of fuel, oil due at 11 000', () {
    final s = AppState();
    expect(s.odoKm, 10820);
    expect(s.fuelKm, 150);
    expect(s.nextOilKm, 11000);
    expect(s.oilLeftKm, 180);
    expect(Reminders.check(s).alerts, isEmpty);
  });

  test('oil: warns 100 km before, once', () {
    final s = AppState()..odoKm = 10900.5;
    expect(titles(Reminders.check(s)), ['Oil change soon']);
    s.odoKm = 10950;
    expect(Reminders.check(s).alerts, isEmpty);
  });

  test('oil: due alert at 11 000 merges with the 1000 km milestone', () {
    final s = AppState()..odoKm = 10999.9;
    Reminders.check(s); // "soon"
    s.odoKm = 11000.2;
    final r = Reminders.check(s);
    expect(titles(r), ['11 000 km: oil change time!']);
    expect(r.alerts.single.level, AlertLevel.danger);
    expect(r.events.single.kind, EventKind.milestone);
    expect(Reminders.check(s).alerts, isEmpty); // no duplicate
  });

  test('oil: repeats every 50 km overdue', () {
    final s = AppState()..odoKm = 11000.2;
    Reminders.check(s);
    s.odoKm = 11049;
    expect(Reminders.check(s).alerts, isEmpty);
    s.odoKm = 11051;
    expect(titles(Reminders.check(s)).single, startsWith('Oil change overdue by 51'));
  });

  test('oil changed resets the cycle: next at +1000', () {
    final s = AppState()..odoKm = 11020;
    Reminders.check(s);
    s.lastOilKm = s.odoKm.floorToDouble();
    Reminders.resetOilFlags(s);
    expect(s.nextOilKm, 12020);
    expect(Reminders.check(s).alerts, isEmpty);
  });

  test('milestone alone (no oil) is a green notification', () {
    final s = AppState()
      ..odoKm = 12000.4
      ..lastOilKm = 12000
      ..flags.milestone = 11;
    final r = Reminders.check(s);
    expect(r.alerts.single.title, '12 000 km reached');
    expect(r.alerts.single.level, AlertLevel.ok);
  });

  test('fuel: low at 20 km, empty at 0 asks to pay 20 DT, no duplicates', () {
    final s = AppState()..fuelKm = 19;
    expect(titles(Reminders.check(s)), ['Fuel low']);
    expect(Reminders.check(s).alerts, isEmpty);
    s
      ..fuelKm = -0.5
      ..kmSinceFill = 220;
    final r = Reminders.check(s);
    expect(r.alerts.single.title, 'Fuel: pay 20 DT');
    expect(r.alerts.single.level, AlertLevel.danger);
    expect(Reminders.check(s).alerts, isEmpty);
  });

  test('editing the fuel level re-arms the warnings', () {
    final s = AppState()..fuelKm = 5;
    Reminders.check(s);
    s.fuelKm = 150;
    Reminders.resetFuelFlags(s);
    expect(s.flags.fuelWarned, isFalse);
    s.fuelKm = 10;
    expect(titles(Reminders.check(s)), ['Fuel low']);
  });
}
