import 'format.dart';
import 'models.dart';

class PendingAlert {
  const PendingAlert(this.title, this.body, this.level, this.id);

  final String title;
  final String body;
  final AlertLevel level;
  final String id;
}

class ReminderResult {
  final List<PendingAlert> alerts = [];
  final List<RideEvent> events = [];
}

/// The fuel / oil / 1000-km rules. Pure logic: mutates the flags inside the
/// state it is given and returns what should be announced.
class Reminders {
  static const overdueRepeatKm = 50.0;

  static ReminderResult check(AppState s) {
    final result = ReminderResult();
    final st = s.settings;

    // 1000-km milestones on the odometer
    int? milestoneKm;
    final reached = (s.odoKm / 1000).floor();
    if (reached > s.flags.milestone) {
      s.flags.milestone = reached;
      milestoneKm = reached * 1000;
      result.events.add(RideEvent(
        kind: EventKind.milestone,
        odo: milestoneKm.toDouble(),
        note: '${Fmt.intGrouped(milestoneKm.toDouble())} km reached',
      ));
    }

    // Oil change (vidange)
    final nextOil = s.nextOilKm;
    final oilLeft = nextOil - s.odoKm;
    if (oilLeft <= 0) {
      final step = (-oilLeft / overdueRepeatKm).floor();
      final first = s.flags.oilDueTarget != nextOil;
      if (first || step > s.flags.oilOverdueStep) {
        s.flags.oilDueTarget = nextOil;
        s.flags.oilWarnTarget = nextOil;
        s.flags.oilOverdueStep = step;

        final String title;
        if (milestoneKm != null) {
          title = '${Fmt.intGrouped(milestoneKm.toDouble())} km: oil change time!';
        } else if (first) {
          title = 'Oil change due (vidange)';
        } else {
          title = 'Oil change overdue by ${(-oilLeft).truncate()} km';
        }
        result.alerts.add(PendingAlert(
          title,
          'Total: ${Fmt.intGrouped(s.odoKm)} km. Change the oil, then tap "Oil changed".',
          AlertLevel.danger,
          'oil',
        ));
        milestoneKm = null; // already announced inside the oil alert
      }
    } else if (oilLeft <= st.oilWarn && s.flags.oilWarnTarget != nextOil) {
      s.flags.oilWarnTarget = nextOil;
      result.alerts.add(PendingAlert(
        'Oil change soon',
        '${oilLeft.ceil()} km left. Vidange at ${Fmt.intGrouped(nextOil)} km.',
        AlertLevel.warn,
        'oil',
      ));
    }

    if (milestoneKm != null) {
      result.alerts.add(PendingAlert(
        '${Fmt.intGrouped(milestoneKm.toDouble())} km reached',
        'Total distance on the bike: ${Fmt.intGrouped(s.odoKm)} km.',
        AlertLevel.ok,
        'milestone',
      ));
    }

    // Fuel: one fill (220 km) = 20 DT
    final price = Fmt.intGrouped(st.fuelPrice);
    if (s.fuelKm <= 0 && !s.flags.fuelEmpty) {
      s.flags.fuelEmpty = true;
      s.flags.fuelWarned = true;
      result.alerts.add(PendingAlert(
        'Fuel: pay $price DT',
        '${s.kmSinceFill.round()} km since the last fill. Time to refuel.',
        AlertLevel.danger,
        'fuel',
      ));
    } else if (s.fuelKm > 0 && s.fuelKm <= st.fuelWarn && !s.flags.fuelWarned) {
      s.flags.fuelWarned = true;
      result.alerts.add(PendingAlert(
        'Fuel low',
        'About ${s.fuelKm.ceil()} km left. Plan to pay $price DT soon.',
        AlertLevel.warn,
        'fuel',
      ));
    }

    return result;
  }

  /// Call after the fuel level or its thresholds were edited by hand.
  static void resetFuelFlags(AppState s) {
    s.flags.fuelEmpty = s.fuelKm <= 0;
    s.flags.fuelWarned = s.fuelKm <= s.settings.fuelWarn;
  }

  /// Call after the oil interval / last change / warning distance were edited.
  static void resetOilFlags(AppState s) {
    s.flags.oilWarnTarget = null;
    s.flags.oilDueTarget = null;
    s.flags.oilOverdueStep = 0;
  }
}
