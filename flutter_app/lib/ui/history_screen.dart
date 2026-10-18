import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../format.dart';
import '../models.dart';
import 'engine_scope.dart';
import 'theme.dart';

/// Refuels, oil changes, rides, trips and milestones, newest first.
class HistoryList extends StatelessWidget {
  const HistoryList({super.key});

  static IconData _icon(EventKind k) {
    switch (k) {
      case EventKind.fuel:
        return Icons.local_gas_station_outlined;
      case EventKind.oil:
        return Icons.water_drop_outlined;
      case EventKind.trip:
        return Icons.flag_outlined;
      case EventKind.ride:
        return Icons.route_outlined;
      case EventKind.milestone:
        return Icons.emoji_events_outlined;
      case EventKind.gap:
        return Icons.settings_input_antenna;
      case EventKind.edit:
        return Icons.edit_outlined;
      case EventKind.importBackup:
        return Icons.download_outlined;
      case EventKind.other:
        return Icons.circle_outlined;
    }
  }

  static String _title(EventKind k) {
    switch (k) {
      case EventKind.fuel:
        return 'Refuel';
      case EventKind.oil:
        return 'Oil change';
      case EventKind.trip:
        return 'Trip saved';
      case EventKind.ride:
        return 'Ride';
      case EventKind.milestone:
        return 'Milestone';
      case EventKind.gap:
        return 'GPS gap';
      case EventKind.edit:
        return 'Manual edit';
      case EventKind.importBackup:
        return 'Backup restored';
      case EventKind.other:
        return 'Event';
    }
  }

  @override
  Widget build(BuildContext context) {
    final events = EngineScope.of(context).events;
    if (events.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 32, color: Palette.muted),
            SizedBox(height: 6),
            Text('No events yet', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            SizedBox(height: 4),
            Text('Refuels, oil changes and rides will appear here.', style: TextStyle(fontSize: 13, color: Palette.muted)),
          ],
        ),
      );
    }

    final dateFormat = DateFormat('d MMM y, HH:mm');
    return ListView.separated(
      itemCount: events.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final e = events[i];
        return ListTile(
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: Palette.panel2, borderRadius: BorderRadius.circular(10)),
            child: Icon(_icon(e.kind), size: 18),
          ),
          title: Row(
            children: [
              Expanded(child: Text(_title(e.kind), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
              if (e.odo != null) Text('${Fmt.intGrouped(e.odo!)} km', style: mono(size: 13, color: Palette.muted)),
            ],
          ),
          subtitle: Text('${e.note}\n${dateFormat.format(e.at)}', style: const TextStyle(fontSize: 12, color: Palette.muted)),
          isThreeLine: true,
        );
      },
    );
  }
}
