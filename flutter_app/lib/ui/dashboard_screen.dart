import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../format.dart';
import '../models.dart';
import '../ride_engine.dart';
import 'engine_scope.dart';
import 'gauge.dart';
import 'settings_screen.dart';
import 'theme.dart';
import 'widgets.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final engine = EngineScope.of(context);
    final s = engine.state;

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    children: [
                      _StatusBar(engine: engine),
                      ..._banners(s),
                      GaugeView(speed: engine.speedKmh),
                      const SizedBox(height: 4),
                      Center(child: _Odometer(odoKm: s.odoKm)),
                      const SizedBox(height: 12),
                      _TripCard(engine: engine),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _FuelCard(engine: engine)),
                          const SizedBox(width: 12),
                          Expanded(child: _OilCard(engine: engine)),
                        ],
                      ),
                    ],
                  ),
                ),
                _RideButton(engine: engine),
              ],
            ),
          ),
          const ToastOverlay(),
        ],
      ),
    );
  }

  List<Widget> _banners(AppState s) {
    final out = <Widget>[];
    if (s.oilLeftKm <= 0) {
      final left = s.oilLeftKm;
      out.add(_Banner(text: 'Oil change (vidange) due: ${left <= -1 ? '${(-left).floor()} km overdue' : 'now'}'));
    }
    if (s.fuelKm <= 0) {
      out.add(_Banner(text: 'Fuel: pay ${Fmt.intGrouped(s.settings.fuelPrice)} DT now'));
    }
    return out;
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Palette.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Palette.danger.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFFF8080), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(color: Color(0xFFFF8080), fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.engine});
  final RideEngine engine;

  Color get _dot {
    switch (engine.gpsStatus) {
      case GpsStatus.off:
        return const Color(0xFF3A4350);
      case GpsStatus.searching:
      case GpsStatus.weak:
        return Palette.warn;
      case GpsStatus.good:
        return Palette.accent;
      case GpsStatus.denied:
        return Palette.danger;
      case GpsStatus.sim:
        return Palette.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Container(width: 9, height: 9, decoration: BoxDecoration(color: _dot, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(engine.gpsText,
                      overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Palette.muted)),
                ),
              ],
            ),
          ),
          const _Clock(),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: 'Settings',
                icon: const Icon(Icons.settings_outlined, color: Palette.muted),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => EngineScope(engine: engine, child: const SettingsScreen())),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Clock extends StatelessWidget {
  const _Clock();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DateTime>(
      stream: Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now()),
      initialData: DateTime.now(),
      builder: (context, snap) => Text(
        DateFormat.Hm().format(snap.data!),
        style: mono(size: 15, weight: FontWeight.w600),
      ),
    );
  }
}

class _Odometer extends StatelessWidget {
  const _Odometer({required this.odoKm});
  final double odoKm;

  @override
  Widget build(BuildContext context) {
    final tenths = (odoKm * 10).floor();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Palette.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text('ODO', style: mono(size: 12, color: Palette.muted)),
          const SizedBox(width: 8),
          Text((tenths ~/ 10).toString().padLeft(6, '0'), style: mono(size: 26, weight: FontWeight.w700, color: Colors.white)),
          Text('.${tenths % 10}', style: mono(size: 18, color: Palette.muted)),
          const SizedBox(width: 6),
          const Text('km', style: TextStyle(fontSize: 12, color: Palette.muted)),
        ],
      ),
    );
  }
}

Widget _cardTitle(String text, {IconData? icon}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 14, color: Palette.muted), const SizedBox(width: 6)],
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: Palette.muted),
          ),
        ),
      ],
    );

Widget _stat(String label, String value) => Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Palette.muted)),
        Text(value, style: mono(size: 17, weight: FontWeight.w600)),
      ],
    );

class _TripCard extends StatelessWidget {
  const _TripCard({required this.engine});
  final RideEngine engine;

  @override
  Widget build(BuildContext context) {
    final s = engine.state;
    final t = s.trip;
    final avg = t.movingMs > 10000 ? (t.km / (t.movingMs / 3600000)).round() : 0;
    return DashCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _cardTitle('TRIP'),
              ConfirmButton(label: 'Reset', armedLabel: 'Tap again', compact: true, onConfirmed: engine.resetTrip),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(Fmt.km1(t.km), style: mono(size: 34, weight: FontWeight.w700)),
              const SizedBox(width: 6),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text('km', style: TextStyle(fontSize: 13, color: Palette.muted)),
              ),
              const Spacer(),
              _stat('Time', Fmt.duration(t.movingMs)),
              const SizedBox(width: 18),
              _stat('Avg', '$avg'),
              const SizedBox(width: 18),
              _stat('Max', '${t.maxKmh.round()}'),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.route_outlined, size: 16, color: Palette.muted),
              const SizedBox(width: 6),
              const Text('This ride', style: TextStyle(fontSize: 12, color: Palette.muted)),
              const Spacer(),
              Text('${Fmt.km1(s.rideKm)} km', style: mono(size: 15, weight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}

class _FuelCard extends StatelessWidget {
  const _FuelCard({required this.engine});
  final RideEngine engine;

  @override
  Widget build(BuildContext context) {
    final s = engine.state;
    final st = s.settings;
    final left = s.fuelKm < 0 ? 0.0 : s.fuelKm;
    final empty = s.fuelKm <= 0;
    final low = !empty && s.fuelKm <= st.fuelWarn;
    final tone = empty ? Palette.danger : (low ? Palette.warn : Palette.accent);

    return DashCard(
      border: empty ? Palette.danger.withValues(alpha: 0.7) : (low ? Palette.warn.withValues(alpha: 0.55) : Palette.line),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle('FUEL', icon: Icons.local_gas_station_outlined),
          const SizedBox(height: 2),
          Text('since fill ${s.kmSinceFill.round()} km', style: const TextStyle(fontSize: 12, color: Palette.muted)),
          const SizedBox(height: 10),
          Meter(fraction: left / (st.fuelPerFill < 1 ? 1 : st.fuelPerFill), color: tone),
          const SizedBox(height: 10),
          Text('${left.floor()}', style: mono(size: 26, weight: FontWeight.w700, color: empty || low ? tone : Colors.white)),
          const Text('km left', style: TextStyle(fontSize: 13, color: Palette.muted)),
          const SizedBox(height: 10),
          ConfirmButton(
            label: 'Paid ${Fmt.intGrouped(st.fuelPrice)} DT',
            armedLabel: 'Confirm paid?',
            onConfirmed: engine.refuel,
          ),
        ],
      ),
    );
  }
}

class _OilCard extends StatelessWidget {
  const _OilCard({required this.engine});
  final RideEngine engine;

  @override
  Widget build(BuildContext context) {
    final s = engine.state;
    final st = s.settings;
    final left = s.oilLeftKm;
    final due = left <= 0;
    final soon = !due && left <= st.oilWarn;
    final tone = due ? Palette.danger : (soon ? Palette.warn : Palette.accent);
    final leftText = left > -1 ? '${left < 0 ? 0 : left.floor()}' : '−${(-left).floor()}';

    return DashCard(
      border: due ? Palette.danger.withValues(alpha: 0.7) : (soon ? Palette.warn.withValues(alpha: 0.55) : Palette.line),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle('OIL · VIDANGE', icon: Icons.water_drop_outlined),
          const SizedBox(height: 2),
          Text('next at ${Fmt.intGrouped(s.nextOilKm)} km', style: const TextStyle(fontSize: 12, color: Palette.muted)),
          const SizedBox(height: 10),
          Meter(fraction: left / (st.oilInterval < 1 ? 1 : st.oilInterval), color: tone),
          const SizedBox(height: 10),
          Text(leftText, style: mono(size: 26, weight: FontWeight.w700, color: due || soon ? tone : Colors.white)),
          Text(left > -1 ? 'km to change' : 'km overdue', style: const TextStyle(fontSize: 13, color: Palette.muted)),
          const SizedBox(height: 10),
          ConfirmButton(label: 'Oil changed', armedLabel: 'Confirm?', onConfirmed: engine.oilChanged),
        ],
      ),
    );
  }
}

class _RideButton extends StatelessWidget {
  const _RideButton({required this.engine});
  final RideEngine engine;

  @override
  Widget build(BuildContext context) {
    final riding = engine.state.isRiding;
    final label = riding ? 'Stop ride' : (engine.state.settings.sim ? 'Start simulated ride' : 'Start ride');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: SizedBox(
        width: double.infinity,
        height: 58,
        child: TextButton(
          onPressed: () => riding ? engine.stopRide() : engine.startRide(),
          style: TextButton.styleFrom(
            backgroundColor: riding ? const Color(0xFF2A1416) : Palette.accent,
            foregroundColor: riding ? const Color(0xFFFF8080) : const Color(0xFF04120C),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: riding ? Palette.danger.withValues(alpha: 0.5) : Colors.transparent),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: riding ? Palette.danger : const Color(0xFF04120C),
                  shape: riding ? BoxShape.rectangle : BoxShape.circle,
                  borderRadius: riding ? BorderRadius.circular(3) : null,
                ),
              ),
              const SizedBox(width: 10),
              Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}
