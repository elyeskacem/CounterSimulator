# MotoDash

A motorcycle dashboard: GPS speed, odometer, trip meter, fuel reminder (every 220 km → pay 20 DT) and oil-change (vidange) reminder every 1000 km.

| Folder | What it is |
|---|---|
| [`web/`](web/) | The web app (PWA). Live at https://elyeskacem.github.io/CounterSimulator/ (redeploys automatically when `web/` changes) |
| [`ios/`](ios/) | Native iPhone app in Swift/SwiftUI: background tracking, Dynamic Island |
| [`flutter_app/`](flutter_app/) | The same iPhone app in Flutter/Dart (Dynamic Island part is Swift) |

All three use the same backup file format, so the odometer, fuel and history can move between them.
See each folder's README for how to run it.
