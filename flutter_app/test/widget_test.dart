import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motodash/main.dart';
import 'package:motodash/native_bridge.dart';
import 'package:motodash/notification_service.dart';
import 'package:motodash/ride_engine.dart';
import 'package:motodash/store.dart';

void main() {
  late Directory dir;
  late RideEngine engine;

  setUp(() => dir = Directory.systemTemp.createTempSync('motodash_ui'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> boot(WidgetTester tester) async {
    // iPhone 16 Pro Max logical size
    tester.view.physicalSize = const Size(1320, 2868);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    engine = RideEngine(store: Store(directory: dir), notifier: NotificationService(), bridge: NativeBridge());
    await tester.runAsync(engine.init);
    await tester.pumpWidget(MotoDashApp(engine: engine));
    await tester.pump();
  }

  Future<void> shutdown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    engine.dispose();
    await tester.runAsync(engine.store.flush); // let pending file writes finish before the folder is deleted
  }

  testWidgets('dashboard shows the starting values', (tester) async {
    await boot(tester);
    expect(find.text('010820'), findsOneWidget); // odometer
    expect(find.text('.0'), findsOneWidget);
    expect(find.text('0.0'), findsWidgets); // trip
    expect(find.text('150'), findsOneWidget); // fuel km left
    expect(find.text('180'), findsOneWidget); // km to oil change
    expect(find.text('next at 11 000 km'), findsOneWidget);
    expect(find.text('Paid 20 DT'), findsOneWidget);
    expect(find.text('Start ride'), findsOneWidget);
    await shutdown(tester);
  });

  testWidgets('destructive buttons need two taps', (tester) async {
    await boot(tester);
    await tester.tap(find.text('Paid 20 DT'));
    await tester.pump();
    expect(find.text('Confirm paid?'), findsOneWidget);
    expect(engine.state.fuelKm, 150, reason: 'nothing happened after one tap');

    await tester.pump(const Duration(seconds: 4)); // disarms itself
    expect(find.text('Paid 20 DT'), findsOneWidget);
    await shutdown(tester);
  });

  testWidgets('settings screen opens and lists the Dynamic Island choices', (tester) async {
    await boot(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('DYNAMIC ISLAND & LOCK SCREEN'), findsOneWidget);
    for (final title in ['Ride distance', 'Speed', 'Trip', 'Odometer']) {
      expect(find.text(title), findsWidgets);
    }
    await shutdown(tester);
  });
}
