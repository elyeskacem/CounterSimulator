# MotoDash: Flutter version (iPhone)

Same app as the Swift version in `../ios`, written in Dart with Flutter:
speed gauge, odometer, trip, fuel (every 220 km → pay 20 DT), oil change (vidange) every 1000 km, 1000-km notifications, history, backup.
Starts at **10 820 km** with **150 km** of fuel.

| | |
|---|---|
| Background tracking | `geolocator` with iOS background location (blue pill). Keeps counting with the screen locked. |
| Dynamic Island | Native Swift Live Activity (`ios/MotoDashWidgets`), driven from Dart through a small channel (`ios/Runner/NativeBridge.swift`). Shows **km since you tapped Start ride** by default; Settings → Dynamic Island switches to Speed / Trip / Odometer, or tap the ↻ button in the expanded island. |
| Notifications | `flutter_local_notifications` (fire from the background) |
| Data | JSON files in Application Support (not a cache). **Export / Import backup is the same format as the website and the Swift app.** |
| Relaunch | With "Always" location permission, a significant-change monitor lets iOS relaunch the app if it was terminated; the ride resumes and the gap is estimated as a straight line. Not guaranteed by Apple. |

Flutter can't draw a Dynamic Island, so that part is Swift (a Flutter app can contain Swift code).

## Layout

```
flutter_app/
  lib/
    ride_engine.dart       GPS, distance rules, reminders, notifications, Live Activity calls
    reminders.dart         fuel / oil / 1000-km rules (pure logic, unit tested)
    models.dart            state + JSON (same format as the website backup)
    store.dart             JSON persistence
    backup_codec.dart      import / export
    native_bridge.dart     Dart side of the Swift channel
    ui/                    dashboard, gauge, settings, history
  test/                    26 tests (rules, backup format, GPS handling, screens)
  ios/
    Runner/                the app + NativeBridge.swift
    MotoDashWidgets/       Dynamic Island + Lock Screen Live Activity
    Shared/                code shared by both (activity attributes, island modes)
```

## Run the checks (any computer with Flutter)

```bash
cd flutter_app
flutter pub get
flutter analyze
flutter test
```

## Build for iPhone

### On a Mac (Xcode 15+, Flutter 3.47+)

```bash
cd flutter_app
flutter pub get                     # creates the files Xcode needs; do this before opening Xcode
open ios/Runner.xcworkspace         # or: open ios/Runner.xcodeproj
```
In Xcode: select the **Runner** project → for **both** targets, *Runner* and *MotoDashWidgets* → *Signing & Capabilities* → pick your Apple ID as Team. Change the bundle ids to something unique to you (`com.yourname.motodash` and `com.yourname.motodash.widgets`; the extension's id must start with the app's id). Plug in the iPhone (Developer Mode on) and press ▶︎, or from the terminal: `flutter run --release`.

### Without a Mac

The GitHub Action **Build Flutter iOS app** runs the analyzer and tests, builds the app, and uploads an unsigned `.ipa`. Download it from *Actions → latest run → Artifacts*, then install it with Sideloadly (see `../ios/README.md`, "Option B"). A free Apple ID signature lasts 7 days.

## First launch

1. Tap **Start ride** → allow notifications and location.
2. Choose **Allow While Using**, then accept **Change to Always Allow** when iOS offers it.
3. iOS Settings → MotoDash → make sure **Live Activities** is on.
4. Settings → **Simulation mode** (300×) is the quickest way to see the Dynamic Island and the 11 000 km oil alert without riding.

## Status

Verified on Windows: `flutter analyze` is clean and all 26 tests pass (rules, backup compatibility with a web-app file, GPS jitter/gap/jump handling, state persistence, screens). The Swift part (Dynamic Island, Always permission, relaunch) and the Xcode project edits have **not been compiled or run yet**; the GitHub Mac build is the first check, and a real iPhone is the second. Expect to fix a few compiler messages on the first run.
