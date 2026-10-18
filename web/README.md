# MotoDash — motorcycle dashboard (iPhone web app)

GPS speedometer, odometer, trip meter, fuel and oil-change (vidange) reminders.
No build step, no server code: plain HTML/CSS/JS + a service worker.

## Run locally

```
python -m http.server 8765
```
Open http://localhost:8765. To test without riding, turn on Settings → GPS → **Simulation mode** and pick a speed-up (300× runs ~25 km per minute).

## Put it on the iPhone

GPS needs **HTTPS**, so host the folder on any static host, for example:

- **Netlify Drop**: drag this folder onto https://app.netlify.com/drop
- **GitHub Pages**: push the folder to a repo → Settings → Pages

Then on the iPhone:

1. Open the URL in **Safari** → Share → **Add to Home Screen**.
2. Open **MotoDash from the home-screen icon** (needed for notifications and so iOS doesn't erase the data).
3. Settings ⚙ → Notifications → **Enable**. Allow location when you tap **Start ride**.

## How the counters work

| Item | Start value | Rule |
|---|---|---|
| Odometer | 10 820 km | + GPS distance |
| Fuel | 150 km left | one fill = 220 km = 20 DT; warns at 20 km left, alerts at 0 → tap **Paid 20 DT** |
| Oil | last change at 10 000 km | every 1 000 km; warns 100 km before, alerts when due and every 50 km overdue → tap **Oil changed** |
| Milestones | — | notification at every 1 000 km on the odometer |

All values and thresholds are editable in Settings. The refuel, oil change and trip reset buttons need two taps, so you can't press them by accident.

## Data

Saved on the phone in **IndexedDB** (with a localStorage copy). Use Settings → **Export backup** now and then; **Import** restores it on a new phone.

## Background — iPhone limits

iOS pauses web apps when the screen locks or you switch apps; no web app can read GPS in the background on iPhone. MotoDash handles this as follows:

- **Keep screen on while riding** (on by default) stops the phone from locking, so tracking never pauses. Keep the phone on a mount with a charger.
- If the app was paused anyway, when you come back it adds the **straight-line distance** since the last fix (shown as "GPS gap" in History). Real roads are longer than straight lines, so this undercounts a bit. Correct the odometer in Settings if needed.
- Notifications are only sent while the app is open or right when you return to it.
