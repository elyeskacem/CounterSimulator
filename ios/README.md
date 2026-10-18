# MotoDash for iPhone (Swift / SwiftUI)

Same dashboard as the web app (speed, odometer, trip, fuel, oil/vidange, history, backup) plus what a website can't do:

- **Background tracking**: keeps counting with the screen locked or the app in the background (iOS "location" background mode, blue status-bar pill).
- **Dynamic Island + Lock Screen Live Activity** (iPhone 14 Pro and later, so your 16 Pro Max): shows **km since you tapped Start ride** by default.
  - Change what it shows in **Settings → Dynamic Island**: Ride distance (default) · Speed · Trip · Odometer.
  - Or change it live without opening the app: long-press the Dynamic Island and tap the ↻ button.
- **Real notifications** for oil/fuel/1000 km, sent even while the app is in the background.
- **Relaunches itself** after a significant move if iOS terminated it (needs location permission "Always").
- Data: JSON files in Application Support (never purged like a cache), included in the iPhone backup. **Export / Import backup uses the same file format as the web app**, so you can move your odometer from the website to the app.

Requires iOS 17+. Never compiled or run by the author of this repo yet: see "Status" below.

## Project layout

```
ios/
  project.yml            XcodeGen definition (app + Live Activity extension)
  Shared/                code used by both targets (activity attributes, island modes, button intent)
  MotoDash/              the app
    RideEngine.swift     GPS, background tracking, distance rules, reminders, notifications, Live Activity
    Reminders.swift      fuel / oil / 1000-km rules (pure logic)
    Store.swift          JSON persistence
    BackupCodec.swift    backup format shared with the web app
    *View.swift          SwiftUI screens
  MotoDashWidgets/       Dynamic Island + Lock Screen UI
```

The `.xcodeproj` is generated, not committed.

## Option A: you have a Mac

```bash
brew install xcodegen
cd ios
xcodegen generate
open MotoDash.xcodeproj
```
In Xcode: select the **MotoDash** target and the **MotoDashWidgets** target → *Signing & Capabilities* → pick your Apple ID team (free works). Plug in the iPhone, enable *Settings → Privacy & Security → Developer Mode*, press Run.

To change the bundle id (`com.elyeskacem.motodash`), edit `ios/project.yml` and regenerate.

## Option B: Windows only (no Mac)

The GitHub Action **Build iOS app** (`.github/workflows/ios-build.yml`) builds the app on a free GitHub Mac and gives you an unsigned `.ipa`:

1. Push to GitHub → *Actions* → **Build iOS app** → open the latest run → download the artifact **MotoDash-unsigned-ipa**.
2. Install [Sideloadly](https://sideloadly.io) on Windows (needs iTunes + iCloud from apple.com, not the Microsoft Store versions).
3. Plug in the iPhone, drag `MotoDash-unsigned.ipa` into Sideloadly, sign in with your Apple ID, press Start.
4. iPhone: *Settings → General → VPN & Device Management* → trust your Apple ID; enable *Developer Mode*.

A free Apple ID signature **expires after 7 days**: re-run Sideloadly weekly (your data stays). A paid developer account ($99/year) removes that limit.

## First launch on the iPhone

1. Tap **Start ride** → allow **notifications** and **location**.
2. Choose **Allow While Using**, then when iOS later offers **Change to Always Allow**, accept it (or *Settings → MotoDash → Location → Always*). "Always" is what lets the app restart itself after iOS closes it.
3. Settings → check *Live Activities* is allowed for MotoDash (*iOS Settings → MotoDash*).
4. Optional: import your backup from the website (web Settings → Export backup → app Settings → Import backup).

## What survives what

| Situation | Result |
|---|---|
| Lock the screen / go to the Home Screen / open other apps | Keeps counting. Dynamic Island keeps updating. |
| Swipe the app away in the app switcher | iOS stops continuous GPS. With "Always" permission iOS should relaunch it after a significant move (about 500 m) and it resumes counting, estimating the gap as a straight line. Not guaranteed by Apple. **Best: don't swipe it away during a ride.** |
| iOS kills it for memory | Same relaunch mechanism as above. |
| Ride longer than 8 hours | iOS ends any Live Activity after 8 h; opening the app starts a new one. |
| Phone restarts | Open the app and tap Start ride. |

## Status

Written without access to a Mac or Xcode, so it has **not been compiled or run on a device yet**. The `Build iOS app` workflow is the first compile check; expect to fix a few compiler errors on the first run. Things to verify on the real iPhone:

- [ ] Dynamic Island shows the ride km and updates while the screen is locked
- [ ] The ↻ button in the expanded island cycles the display
- [ ] Notifications arrive in the background (use Settings → Simulation mode ×300 to hit the 11 000 km alerts quickly)
- [ ] Counting continues for a 10 min ride with the screen locked
- [ ] Relaunch after swiping the app away (ride > 1 km afterwards)
