import 'dart:convert';

import 'models.dart';

class BackupException implements Exception {
  BackupException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Backup file format: identical to the web app's "Export backup", so the
/// odometer, fuel and history can move between the website and this app.
class BackupCodec {
  static String encode(AppState state, List<RideEvent> events) {
    final data = {
      'app': 'motodash',
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'state': state.toJson(),
      // oldest first, like the web app
      'events': events.reversed.map((e) => e.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  static ({AppState state, List<RideEvent> events}) decode(String text) {
    final dynamic root;
    try {
      root = jsonDecode(text);
    } on FormatException {
      throw BackupException('This file is not a MotoDash backup.');
    }
    if (root is! Map || root['app'] != 'motodash' || root['state'] is! Map) {
      throw BackupException('This file is not a MotoDash backup.');
    }
    final state = AppState.fromJson(root['state']);
    state.isRiding = false;
    state.anchor = null;
    state.settings.sim = false;

    final events = <RideEvent>[];
    final list = root['events'];
    if (list is List) {
      for (final e in list) {
        events.add(RideEvent.fromJson(e));
      }
    }
    events.sort((a, b) => b.at.compareTo(a.at)); // newest first in the app
    return (state: state, events: events);
  }
}
