import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// Persistence: two JSON files in the app's Application Support folder (not the
/// cache, so iOS never purges them; they are also part of the phone backup).
/// Writes go to a temp file first and are renamed, so a crash can't corrupt them.
/// Writes are queued one after the other, and a failed write never crashes the app.
class Store {
  Store({this._directory});

  Directory? _directory;
  Future<void> _queue = Future.value();

  Future<File> _file(String name) async {
    _directory ??= await getApplicationSupportDirectory();
    await _directory!.create(recursive: true);
    return File('${_directory!.path}/$name');
  }

  Future<AppState?> loadState() async {
    try {
      final f = await _file('state.json');
      if (!await f.exists()) return null;
      return AppState.fromJson(jsonDecode(await f.readAsString()));
    } catch (_) {
      return null;
    }
  }

  Future<List<RideEvent>> loadEvents() async {
    try {
      final f = await _file('events.json');
      if (!await f.exists()) return [];
      final list = jsonDecode(await f.readAsString());
      if (list is! List) return [];
      return list.map(RideEvent.fromJson).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveState(AppState s) => _write('state.json', jsonEncode(s.toJson()));

  Future<void> saveEvents(List<RideEvent> events) =>
      _write('events.json', jsonEncode(events.map((e) => e.toJson()).toList()));

  /// Completes when every write queued so far is on disk.
  Future<void> flush() => _queue;

  Future<void> _write(String name, String content) {
    _queue = _queue.then((_) async {
      try {
        final target = await _file(name);
        final tmp = File('${target.path}.tmp');
        await tmp.writeAsString(content, flush: true);
        await tmp.rename(target.path);
      } catch (e) {
        debugPrint('Saving $name failed: $e');
      }
    });
    return _queue;
  }
}
