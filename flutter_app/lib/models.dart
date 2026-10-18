// Data model. The JSON written by toJson() is the same format as the web app's
// backup ("state" section), so a backup can be moved between web, Swift and Flutter.

double _num(dynamic v, double fallback) => v is num ? v.toDouble() : fallback;
double? _optNum(dynamic v) => v is num ? v.toDouble() : null;
int _int(dynamic v, int fallback) => v is num ? v.toInt() : fallback;
bool _bool(dynamic v, bool fallback) => v is bool ? v : fallback;
Map<String, dynamic> _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

/// What the Dynamic Island / Lock Screen shows as its main value.
enum IslandMode {
  rideKm('Ride distance', 'km since you tapped Start ride', 'km'),
  speed('Speed', 'current speed in km/h', 'km/h'),
  tripKm('Trip', 'your trip meter', 'km'),
  odometer('Odometer', 'total km on the bike', 'km');

  const IslandMode(this.title, this.detail, this.unit);
  final String title;
  final String detail;
  final String unit;

  IslandMode get next => IslandMode.values[(index + 1) % IslandMode.values.length];

  static IslandMode fromName(dynamic name) {
    for (final m in IslandMode.values) {
      if (m.name == name) return m;
    }
    return IslandMode.rideKm;
  }
}

class Trip {
  Trip({this.km = 0, this.movingMs = 0, this.maxKmh = 0, int? startedAtMs})
      : startedAtMs = startedAtMs ?? DateTime.now().millisecondsSinceEpoch;

  double km;
  double movingMs;
  double maxKmh;
  int startedAtMs;

  factory Trip.fromJson(dynamic json) {
    final j = _map(json);
    return Trip(
      km: _num(j['km'], 0),
      movingMs: _num(j['movingMs'], 0),
      maxKmh: _num(j['maxKmh'], 0),
      startedAtMs: j['startedAt'] is num ? (j['startedAt'] as num).toInt() : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'km': km,
        'movingMs': movingMs,
        'maxKmh': maxKmh,
        'startedAt': startedAtMs,
      };
}

class Flags {
  Flags({
    this.milestone = 10,
    this.oilWarnTarget,
    this.oilDueTarget,
    this.oilOverdueStep = 0,
    this.fuelWarned = false,
    this.fuelEmpty = false,
  });

  int milestone; // last 1000-km milestone already announced
  double? oilWarnTarget; // "oil soon" already sent for this odometer target
  double? oilDueTarget; // "oil due" already sent for this odometer target
  int oilOverdueStep;
  bool fuelWarned;
  bool fuelEmpty;

  factory Flags.fromJson(dynamic json) {
    final j = _map(json);
    return Flags(
      milestone: _int(j['milestone'], 10),
      oilWarnTarget: _optNum(j['oilWarnTarget']),
      oilDueTarget: _optNum(j['oilDueTarget']),
      oilOverdueStep: _int(j['oilOverdueStep'], 0),
      fuelWarned: _bool(j['fuelWarned'], false),
      fuelEmpty: _bool(j['fuelEmpty'], false),
    );
  }

  Map<String, dynamic> toJson() => {
        'milestone': milestone,
        'oilWarnTarget': oilWarnTarget,
        'oilDueTarget': oilDueTarget,
        'oilOverdueStep': oilOverdueStep,
        'fuelWarned': fuelWarned,
        'fuelEmpty': fuelEmpty,
      };
}

class AppSettings {
  AppSettings({
    this.oilInterval = 1000,
    this.oilWarn = 100,
    this.fuelPerFill = 220,
    this.fuelPrice = 20,
    this.fuelWarn = 20,
    this.sound = true,
    this.keepScreenOn = false,
    this.gapFill = true,
    this.sim = false,
    this.simMul = 1,
    this.islandMode = IslandMode.rideKm,
  });

  double oilInterval;
  double oilWarn;
  double fuelPerFill;
  double fuelPrice;
  double fuelWarn;
  bool sound;
  bool keepScreenOn;
  bool gapFill;
  bool sim;
  double simMul;
  IslandMode islandMode;

  factory AppSettings.fromJson(dynamic json) {
    final j = _map(json);
    return AppSettings(
      oilInterval: _num(j['oilInterval'], 1000),
      oilWarn: _num(j['oilWarn'], 100),
      fuelPerFill: _num(j['fuelPerFill'], 220),
      fuelPrice: _num(j['fuelPrice'], 20),
      fuelWarn: _num(j['fuelWarn'], 20),
      sound: _bool(j['sound'], true),
      keepScreenOn: _bool(j['keepScreenOn'], false),
      gapFill: _bool(j['gapFill'], true),
      sim: _bool(j['sim'], false),
      simMul: _num(j['simMul'], 1),
      islandMode: IslandMode.fromName(j['islandMode']),
    );
  }

  Map<String, dynamic> toJson() => {
        'oilInterval': oilInterval,
        'oilWarn': oilWarn,
        'fuelPerFill': fuelPerFill,
        'fuelPrice': fuelPrice,
        'fuelWarn': fuelWarn,
        'sound': sound,
        'keepScreenOn': keepScreenOn,
        'gapFill': gapFill,
        'sim': sim,
        'simMul': simMul,
        'islandMode': islandMode.name,
      };
}

/// Last accepted GPS position of the current ride. Saved so that, if iOS
/// terminates the app and relaunches it, the distance covered in between can
/// be estimated instead of lost.
class Anchor {
  Anchor(this.lat, this.lon, this.timeMs);

  double lat;
  double lon;
  int timeMs;

  static Anchor? fromJson(dynamic json) {
    if (json is! Map) return null;
    final j = _map(json);
    if (j['lat'] is! num || j['lon'] is! num || j['time'] is! num) return null;
    return Anchor((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble(), (j['time'] as num).toInt());
  }

  Map<String, dynamic> toJson() => {'lat': lat, 'lon': lon, 'time': timeMs};
}

class AppState {
  AppState({
    this.odoKm = 10820,
    this.fuelKm = 150,
    this.kmSinceFill = 0,
    this.lastOilKm = 10000,
    this.appKm = 0,
    this.fuelSpent = 0,
    this.rideKm = 0,
    this.rideStartedAtMs,
    this.isRiding = false,
    this.anchor,
    Trip? trip,
    Flags? flags,
    AppSettings? settings,
  })  : trip = trip ?? Trip(),
        flags = flags ?? Flags(),
        settings = settings ?? AppSettings();

  double odoKm; // total km on the bike
  double fuelKm; // estimated range left in the tank
  double kmSinceFill;
  double lastOilKm; // odometer at the last oil change -> next at 11 000
  double appKm; // distance measured by this app
  double fuelSpent; // DT
  double rideKm; // km since the last "Start ride"
  int? rideStartedAtMs;
  bool isRiding;
  Anchor? anchor;
  Trip trip;
  Flags flags;
  AppSettings settings;

  double get nextOilKm => lastOilKm + settings.oilInterval;
  double get oilLeftKm => nextOilKm - odoKm;

  factory AppState.fromJson(dynamic json) {
    final j = _map(json);
    return AppState(
      odoKm: _num(j['odoKm'], 10820),
      fuelKm: _num(j['fuelKm'], 150),
      kmSinceFill: _num(j['kmSinceFill'], 0),
      lastOilKm: _num(j['lastOilKm'], 10000),
      appKm: _num(j['appKm'], 0),
      fuelSpent: _num(j['fuelSpent'], 0),
      rideKm: _num(j['rideKm'], 0),
      rideStartedAtMs: j['rideStartedAt'] is num ? (j['rideStartedAt'] as num).toInt() : null,
      isRiding: _bool(j['isRiding'], false),
      anchor: Anchor.fromJson(j['anchor']),
      trip: Trip.fromJson(j['trip']),
      flags: j.containsKey('flags') ? Flags.fromJson(j['flags']) : Flags(milestone: (_num(j['odoKm'], 10820) / 1000).floor()),
      settings: AppSettings.fromJson(j['settings']),
    );
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'odoKm': odoKm,
        'fuelKm': fuelKm,
        'kmSinceFill': kmSinceFill,
        'lastOilKm': lastOilKm,
        'appKm': appKm,
        'fuelSpent': fuelSpent,
        'rideKm': rideKm,
        'rideStartedAt': rideStartedAtMs,
        'isRiding': isRiding,
        'anchor': anchor?.toJson(),
        'trip': trip.toJson(),
        'flags': flags.toJson(),
        'settings': settings.toJson(),
      };
}

enum EventKind {
  fuel,
  oil,
  trip,
  milestone,
  gap,
  edit,
  ride,
  other,
  importBackup;

  /// Name used in the JSON file (the web app calls it "import").
  String get wire => this == EventKind.importBackup ? 'import' : name;

  static EventKind fromWire(dynamic v) {
    for (final k in EventKind.values) {
      if (k.wire == v) return k;
    }
    return EventKind.other;
  }
}

class RideEvent {
  RideEvent({required this.kind, this.odo, required this.note, DateTime? at}) : at = at ?? DateTime.now();

  final DateTime at;
  final EventKind kind;
  final double? odo;
  final String note;

  factory RideEvent.fromJson(dynamic json) {
    final j = _map(json);
    return RideEvent(
      kind: EventKind.fromWire(j['type']),
      odo: _optNum(j['odo']),
      note: j['note'] is String ? j['note'] as String : '',
      at: DateTime.fromMillisecondsSinceEpoch(_int(j['at'], DateTime.now().millisecondsSinceEpoch)),
    );
  }

  Map<String, dynamic> toJson() => {
        'at': at.millisecondsSinceEpoch,
        'type': kind.wire,
        'odo': odo,
        'note': note,
      };
}

enum AlertLevel { ok, info, warn, danger }

enum GpsStatus { off, searching, good, weak, denied, sim }

class ToastMsg {
  ToastMsg(this.id, this.title, this.body, this.level);

  final int id;
  final String title;
  final String body;
  final AlertLevel level;
}
