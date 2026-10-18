import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';

import '../format.dart';
import '../models.dart';
import '../ride_engine.dart';
import 'engine_scope.dart';
import 'history_screen.dart';
import 'theme.dart';
import 'widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Settings'),
          bottom: const TabBar(
            indicatorColor: Palette.accent,
            tabs: [Tab(text: 'Settings'), Tab(text: 'History')],
          ),
        ),
        body: const TabBarView(children: [_SettingsList(), HistoryList()]),
      ),
    );
  }
}

class _SettingsList extends StatelessWidget {
  const _SettingsList();

  @override
  Widget build(BuildContext context) {
    final engine = EngineScope.of(context);
    final st = engine.state.settings;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          const _Header('Dynamic Island & Lock Screen'),
          for (final mode in IslandMode.values)
            ListTile(
              title: Text(mode.title),
              subtitle: Text(mode.detail, style: const TextStyle(color: Palette.muted, fontSize: 12)),
              trailing: st.islandMode == mode ? const Icon(Icons.check_circle, color: Palette.accent) : const Icon(Icons.circle_outlined, color: Palette.muted),
              onTap: () => engine.setIslandMode(mode),
            ),
          const _Footer(
              'This is what the Dynamic Island shows while you ride. You can also change it without opening the app: touch and hold the Dynamic Island and tap the arrows button.'),

          const _Header('Alerts'),
          ListTile(
            title: const Text('Notifications'),
            subtitle: Text(engine.notificationsEnabled ? 'Enabled' : 'Not enabled (or blocked in iOS Settings)',
                style: const TextStyle(color: Palette.muted, fontSize: 12)),
            trailing: engine.notificationsEnabled
                ? null
                : TextButton(
                    onPressed: () async {
                      await engine.requestNotifications();
                      if (!engine.notificationsEnabled) await engine.openLocationSettings();
                    },
                    child: const Text('Enable'),
                  ),
          ),
          SwitchListTile(
            title: const Text('Sound on alerts'),
            value: st.sound,
            onChanged: (v) => engine.updateSettings((s) => s.sound = v),
          ),
          SwitchListTile(
            title: const Text('Keep screen on while the app is open'),
            value: st.keepScreenOn,
            onChanged: (v) => engine.updateSettings((s) => s.keepScreenOn = v),
          ),

          const _Header('Counters'),
          _num(engine, 'Odometer (km)', NumberField.odometer),
          _num(engine, 'Fuel range left (km)', NumberField.fuelKm),
          _num(engine, 'Last oil change at (km)', NumberField.lastOil),

          const _Header('Oil (vidange)'),
          _num(engine, 'Change every (km)', NumberField.oilInterval),
          _num(engine, 'Warn when (km) left', NumberField.oilWarn),

          const _Header('Fuel'),
          _num(engine, 'One fill = (km)', NumberField.fuelPerFill),
          _num(engine, 'One fill costs (DT)', NumberField.fuelPrice),
          _num(engine, 'Warn when (km) left', NumberField.fuelWarn),

          const _Header('GPS'),
          SwitchListTile(
            title: const Text('Estimate distance during GPS gaps'),
            value: st.gapFill,
            onChanged: (v) => engine.updateSettings((s) => s.gapFill = v),
          ),
          SwitchListTile(
            title: const Text('Simulation mode (fake ride)'),
            value: st.sim,
            onChanged: engine.setSimulation,
          ),
          ListTile(
            title: const Text('Simulation speed-up'),
            trailing: DropdownButton<double>(
              value: st.simMul,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 1.0, child: Text('1×')),
                DropdownMenuItem(value: 10.0, child: Text('10×')),
                DropdownMenuItem(value: 60.0, child: Text('60×')),
                DropdownMenuItem(value: 300.0, child: Text('300×')),
              ],
              onChanged: (v) => engine.updateSettings((s) => s.simMul = v ?? 1),
            ),
          ),
          ListTile(
            title: const Text('Location permission'),
            trailing: Text(_permissionText(engine.locationPermission), style: const TextStyle(color: Palette.muted)),
          ),
          if (engine.locationPermission != LocationPermission.always)
            ListTile(
              title: const Text('Open Settings to choose "Always"', style: TextStyle(color: Palette.accent)),
              onTap: engine.openLocationSettings,
            ),
          const _Footer('"Always" lets MotoDash restart itself and keep counting if iOS closes it while you ride.'),

          const _Header('Data'),
          ListTile(title: const Text('Fuel spent total'), trailing: Text('${Fmt.intGrouped(engine.state.fuelSpent)} DT', style: const TextStyle(color: Palette.muted))),
          ListTile(title: const Text('Distance tracked by the app'), trailing: Text('${Fmt.km1(engine.state.appKm)} km', style: const TextStyle(color: Palette.muted))),
          ListTile(title: const Text('Export backup'), onTap: () => _export(context, engine)),
          ListTile(title: const Text('Import backup (from this app or the website)'), onTap: () => _import(context, engine)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: ConfirmButton(
              label: 'Factory reset',
              armedLabel: 'Tap again to erase everything',
              danger: true,
              onConfirmed: engine.factoryReset,
            ),
          ),
          const _Footer('MotoDash · data stays on this phone'),
        ],
      ),
    );
  }

  static Widget _num(RideEngine engine, String title, NumberField f) =>
      NumberRow(title: title, value: engine.valueOf(f), onCommit: (v) => engine.setField(f, v));

  static String _permissionText(LocationPermission p) {
    switch (p) {
      case LocationPermission.always:
        return 'Always';
      case LocationPermission.whileInUse:
        return 'While Using';
      case LocationPermission.deniedForever:
        return 'Denied';
      case LocationPermission.denied:
        return 'Not asked yet';
      case LocationPermission.unableToDetermine:
        return 'Unknown';
    }
  }

  static Future<void> _export(BuildContext context, RideEngine engine) async {
    try {
      final file = await engine.exportBackupFile();
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], subject: 'MotoDash backup'));
    } catch (e) {
      engine.showToast('Export failed', '$e', AlertLevel.danger, seconds: 8);
    }
  }

  static Future<void> _import(BuildContext context, RideEngine engine) async {
    try {
      final picked = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['json']);
      final path = picked?.path;
      if (path == null) return;
      await engine.importBackupText(await File(path).readAsString());
    } catch (e) {
      engine.showToast('Import failed', '$e', AlertLevel.danger, seconds: 8);
    }
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 22, 16, 6),
        child: Text(text.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: Palette.muted)),
      );
}

class _Footer extends StatelessWidget {
  const _Footer(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        child: Text(text, style: const TextStyle(fontSize: 12, color: Palette.muted)),
      );
}
