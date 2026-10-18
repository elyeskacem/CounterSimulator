import Foundation
import CoreLocation
import ActivityKit
import UserNotifications
import UIKit

private enum Cfg {
    static let maxAccuracy = 40.0      // m: ignore GPS fixes worse than this
    static let gapSeconds = 20.0       // a longer silence = tracking was interrupted
    static let maxGapSeconds = 900.0   // ...but only estimate gaps up to 15 min
    static let glitchKmh = 220.0       // implied speed above this = GPS jump
    static let maxGapKmh = 130.0       // gap estimate only if the average speed is plausible
    static let staleSeconds = 6.0      // no fix for this long -> show 0 km/h
    static let maxEvents = 500
}

enum NumberField {
    case odometer, fuelKm, lastOil, oilInterval, oilWarn, fuelPerFill, fuelPrice, fuelWarn
}

/// Everything that moves: GPS, distance, reminders, notifications, Live Activity.
/// One shared instance; created at launch (including background relaunches).
final class RideEngine: NSObject, ObservableObject {
    static let shared = RideEngine()

    @Published private(set) var state: AppState
    @Published private(set) var events: [RideEvent]
    @Published private(set) var speedKmh = 0.0
    @Published private(set) var gpsStatus = GPSStatus.off
    @Published private(set) var gpsText = "GPS off"
    @Published private(set) var toasts: [Toast] = []
    @Published private(set) var notificationStatus = UNAuthorizationStatus.notDetermined
    @Published private(set) var locationAuth = CLAuthorizationStatus.notDetermined

    private struct Fix {
        var location: CLLocation
        var time: Date
    }

    private let manager = CLLocationManager()
    private var lastFix: Fix?
    private var lastFixAt = Date.distantPast
    private var simTimer: Timer?
    private var tickTimer: Timer?
    private var saveItem: DispatchWorkItem?
    private var activity: Activity<RideActivityAttributes>?
    private var lastPush = Date.distantPast
    private var lastPushed: RideActivityAttributes.ContentState?
    private var askedAlways = false
    private var simSpeed = 0.0
    private var simTarget = 50.0
    private var simLast = Date()

    override init() {
        state = Store.shared.loadState() ?? AppState()
        events = Store.shared.loadEvents()
        super.init()

        manager.delegate = self
        UNUserNotificationCenter.current().delegate = self
        locationAuth = manager.authorizationStatus
        refreshNotificationStatus()

        // The Dynamic Island button runs inside this process.
        IntentBridge.onCycle = { [weak self] in
            DispatchQueue.main.async { self?.cycleIslandMode() }
        }

        adoptExistingActivity()

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer

        if state.isRiding {
            resumeTracking()
        }
    }

    // MARK: - Ride control

    func startRide() {
        guard !state.isRiding else { return }
        if notificationStatus == .notDetermined { requestNotifications() }

        var s = state
        s.isRiding = true
        s.rideKm = 0
        s.rideStartedAt = Date()
        s.anchor = nil
        state = s
        lastFix = nil

        beginTracking()
        startLiveActivity()
        saveNow()
    }

    func stopRide() {
        guard state.isRiding else { return }
        stopTracking()

        var s = state
        let started = s.rideStartedAt ?? Date()
        s.isRiding = false
        s.anchor = nil
        state = s

        if s.rideKm > 0.05 {
            let ms = Date().timeIntervalSince(started) * 1000
            addEvent(RideEvent(kind: .ride, odo: s.odoKm,
                               note: "Ride \(Fmt.km1(s.rideKm)) km in \(Fmt.duration(ms: ms))"))
        }

        setSpeed(0, immediate: true)
        gpsStatus = .off
        gpsText = "GPS off"
        endLiveActivity()
        saveNow()
    }

    /// App was relaunched (or reopened) while a ride was in progress.
    private func resumeTracking() {
        if state.settings.sim {
            // A simulated ride can't survive a relaunch.
            var s = state
            s.isRiding = false
            state = s
            saveNow()
            return
        }
        if let a = state.anchor, Date().timeIntervalSince(a.time) <= Cfg.maxGapSeconds {
            // Lets the first new fix estimate the distance covered while we were not running.
            lastFix = Fix(location: CLLocation(latitude: a.lat, longitude: a.lon), time: a.time)
        }
        beginTracking()
    }

    private func beginTracking() {
        if state.settings.sim {
            startSim()
            return
        }
        gpsStatus = .searching
        gpsText = "Searching…"
        locationAuth = manager.authorizationStatus

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            requestAlwaysOnce()
            startUpdates()
        case .authorizedAlways:
            startUpdates()
        default:
            denyLocation()
        }
    }

    private func requestAlwaysOnce() {
        guard !askedAlways else { return }
        askedAlways = true
        manager.requestAlwaysAuthorization()
    }

    private func startUpdates() {
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
        // Safety net: if iOS terminates the app, a significant move wakes it again.
        if CLLocationManager.significantLocationChangeMonitoringAvailable() {
            manager.startMonitoringSignificantLocationChanges()
        }
    }

    private func stopTracking() {
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        manager.allowsBackgroundLocationUpdates = false
        simTimer?.invalidate()
        simTimer = nil
        lastFix = nil
    }

    private func denyLocation() {
        gpsStatus = .denied
        gpsText = "No permission"
        showToast("Location is off",
                  "Settings > MotoDash > Location: choose “Always” (or “While Using”).",
                  level: .danger, seconds: 10)
    }

    // MARK: - GPS processing

    private func process(_ loc: CLLocation) {
        let acc = loc.horizontalAccuracy
        guard acc >= 0 else { return }

        gpsStatus = acc <= 15 ? .good : (acc <= Cfg.maxAccuracy ? .weak : .searching)
        gpsText = "GPS ±\(Int(acc.rounded())) m"
        guard acc <= Cfg.maxAccuracy else { return }
        if abs(loc.timestamp.timeIntervalSinceNow) > 10 { return } // cached, old fix

        let gpsKmh: Double? = loc.speed >= 0 ? loc.speed * 3.6 : nil

        guard let prev = lastFix else {
            lastFix = Fix(location: loc, time: loc.timestamp)
            lastFixAt = Date()
            setSpeed(gpsKmh ?? 0)
            saveAnchor(loc)
            return
        }

        let dt = loc.timestamp.timeIntervalSince(prev.time)
        guard dt > 0 else { return }
        let d = loc.distance(from: prev.location) // meters
        let implied = d / dt * 3.6

        if dt > Cfg.gapSeconds {
            // Tracking was interrupted (app was terminated and relaunched, or GPS lost).
            if state.settings.gapFill && dt <= Cfg.maxGapSeconds && d > 50 && implied < Cfg.maxGapKmh {
                let km = d / 1000
                addDistance(km, moving: 0)
                addEvent(RideEvent(kind: .gap, odo: state.odoKm,
                                   note: "Estimated \(Fmt.km1(km)) km while tracking was interrupted (\(Int(dt)) s)"))
                showToast("Distance estimated",
                          "+\(Fmt.km1(km)) km (straight line) while tracking was interrupted.",
                          level: .info, seconds: 6)
            }
            lastFix = Fix(location: loc, time: loc.timestamp)
            lastFixAt = Date()
            setSpeed(gpsKmh ?? 0)
            saveAnchor(loc)
            return
        }

        if implied > Cfg.glitchKmh { return } // GPS jump: wait for a sane fix

        lastFixAt = Date()
        let kmh = gpsKmh ?? implied
        let jitter = max(5.0, acc * 0.5)

        if d < jitter && kmh < 4 {
            // Standing still: keep the anchor position, only advance its time.
            lastFix = Fix(location: prev.location, time: loc.timestamp)
            setSpeed(0)
            return
        }

        addDistance(d / 1000, moving: kmh >= 3 ? dt : 0)
        lastFix = Fix(location: loc, time: loc.timestamp)
        setSpeed(kmh)
        saveAnchor(loc)
    }

    private func saveAnchor(_ loc: CLLocation) {
        state.anchor = Anchor(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude, time: loc.timestamp)
        scheduleSave()
    }

    private func setSpeed(_ kmh: Double, immediate: Bool = false) {
        let target = min(max(kmh, 0), 300)
        var v = immediate ? target : speedKmh * 0.35 + target * 0.65
        if v < 1.5 { v = 0 }
        speedKmh = v
        if state.isRiding && v > state.trip.maxKmh {
            state.trip.maxKmh = v
        }
    }

    private func addDistance(_ km: Double, moving seconds: Double) {
        guard km > 0 else { return }
        var s = state
        s.odoKm += km
        s.appKm += km
        s.rideKm += km
        s.trip.km += km
        s.trip.movingMs += seconds * 1000
        s.fuelKm -= km
        s.kmSinceFill += km
        let result = Reminders.check(&s)
        state = s
        apply(result)
        scheduleSave()
        pushActivity()
    }

    private func tick() {
        if state.isRiding && !state.settings.sim && speedKmh > 0
            && Date().timeIntervalSince(lastFixAt) > Cfg.staleSeconds {
            setSpeed(0, immediate: true)
        }
        pushActivity()
    }

    // MARK: - Simulation (testing without riding)

    private func startSim() {
        gpsStatus = .sim
        gpsText = "SIM ×\(Int(state.settings.simMul))"
        simSpeed = 0
        simTarget = 50
        simLast = Date()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.simStep() }
        RunLoop.main.add(timer, forMode: .common)
        simTimer = timer
    }

    private func simStep() {
        let now = Date()
        let dt = now.timeIntervalSince(simLast)
        simLast = now
        if Double.random(in: 0...1) < 0.06 {
            simTarget = Double.random(in: 0...1) < 0.12 ? 0 : 25 + Double.random(in: 0...85)
        }
        let delta = simTarget - simSpeed
        simSpeed += min(max(delta, -12 * dt), 6 * dt)
        simSpeed = max(0, simSpeed + Double.random(in: -0.75...0.75))
        let mul = max(1, state.settings.simMul)
        lastFixAt = now
        setSpeed(simSpeed)
        addDistance(simSpeed / 3600 * dt * mul, moving: simSpeed >= 3 ? dt * mul : 0)
    }

    // MARK: - Actions

    func refuel() {
        var s = state
        let st = s.settings
        let since = s.kmSinceFill
        s.fuelKm = max(0, s.fuelKm) + st.fuelPerFill
        s.fuelSpent += st.fuelPrice
        s.kmSinceFill = 0
        Reminders.resetFuelFlags(&s)
        state = s
        addEvent(RideEvent(kind: .fuel, odo: s.odoKm,
                           note: "Paid \(Fmt.int(st.fuelPrice)) DT, \(Int(since.rounded())) km since previous fill"))
        showToast("Fuel added", "+\(Fmt.int(st.fuelPerFill)) km of range · \(Fmt.int(st.fuelPrice)) DT", level: .ok)
        saveNow()
        pushActivity(force: true)
    }

    func oilChanged() {
        var s = state
        s.lastOilKm = floor(s.odoKm)
        Reminders.resetOilFlags(&s)
        state = s
        addEvent(RideEvent(kind: .oil, odo: s.odoKm,
                           note: "Oil changed, next at \(Fmt.int(s.nextOilKm)) km"))
        showToast("Oil change saved", "Next vidange at \(Fmt.int(s.nextOilKm)) km", level: .ok)
        saveNow()
        pushActivity(force: true)
    }

    func resetTrip() {
        let t = state.trip
        if t.km > 0.05 {
            addEvent(RideEvent(kind: .trip, odo: state.odoKm,
                               note: "Trip \(Fmt.km1(t.km)) km · \(Fmt.duration(ms: t.movingMs)) · max \(Int(t.maxKmh.rounded())) km/h"))
        }
        state.trip = Trip()
        saveNow()
        pushActivity(force: true)
    }

    func value(of field: NumberField) -> Double {
        switch field {
        case .odometer: return state.odoKm
        case .fuelKm: return state.fuelKm
        case .lastOil: return state.lastOilKm
        case .oilInterval: return state.settings.oilInterval
        case .oilWarn: return state.settings.oilWarn
        case .fuelPerFill: return state.settings.fuelPerFill
        case .fuelPrice: return state.settings.fuelPrice
        case .fuelWarn: return state.settings.fuelWarn
        }
    }

    func set(_ field: NumberField, to v: Double) {
        guard v.isFinite, v >= 0 else { return }
        var s = state
        switch field {
        case .odometer:
            let old = s.odoKm
            s.odoKm = v
            s.flags.milestone = Int(floor(v / 1000))
            addEvent(RideEvent(kind: .edit, odo: v,
                               note: "Odometer set from \(Fmt.km1(old)) to \(Fmt.km1(v)) km"))
        case .fuelKm:
            s.fuelKm = v
            Reminders.resetFuelFlags(&s)
        case .lastOil:
            s.lastOilKm = v
            Reminders.resetOilFlags(&s)
        case .oilInterval:
            s.settings.oilInterval = max(1, v)
            Reminders.resetOilFlags(&s)
        case .oilWarn:
            s.settings.oilWarn = v
            Reminders.resetOilFlags(&s)
        case .fuelPerFill:
            s.settings.fuelPerFill = max(1, v)
        case .fuelPrice:
            s.settings.fuelPrice = v
        case .fuelWarn:
            s.settings.fuelWarn = v
            Reminders.resetFuelFlags(&s)
        }
        let result = Reminders.check(&s)
        state = s
        apply(result)
        saveNow()
        pushActivity(force: true)
    }

    func updateSettings(_ change: (inout Settings) -> Void) {
        var s = state
        change(&s.settings)
        state = s
        saveNow()
    }

    func setIslandMode(_ mode: IslandMode) {
        updateSettings { $0.islandMode = mode }
        pushActivity(force: true)
    }

    func cycleIslandMode() {
        setIslandMode(state.settings.islandMode.next)
    }

    func setSimulation(_ on: Bool) {
        if state.isRiding { stopRide() }
        updateSettings { $0.sim = on }
    }

    func factoryReset() {
        if state.isRiding { stopRide() }
        state = AppState()
        events = []
        Store.shared.save(events: events)
        setSpeed(0, immediate: true)
        saveNow()
        showToast("Reset done", "Back to 10 820 km and 150 km of fuel.", level: .ok)
    }

    // MARK: - Backup

    func exportBackupFile() throws -> URL {
        let data = try BackupCodec.encode(state: state, events: events)
        let day = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("motodash-\(day).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    func importBackup(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try BackupCodec.decode(data)
            if state.isRiding { stopRide() }
            var s = decoded.state
            s.settings.sim = false
            state = s
            events = decoded.events
            addEvent(RideEvent(kind: .importBackup, odo: s.odoKm, note: "Backup restored"))
            saveNow()
            showToast("Backup restored", "Odometer \(Fmt.int(s.odoKm)) km", level: .ok)
        } catch {
            showToast("Import failed", error.localizedDescription, level: .danger, seconds: 8)
        }
    }

    // MARK: - Events, saving

    private func addEvent(_ event: RideEvent) {
        events.insert(event, at: 0)
        if events.count > Cfg.maxEvents { events.removeLast(events.count - Cfg.maxEvents) }
        Store.shared.save(events: events)
    }

    private func scheduleSave() {
        guard saveItem == nil else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.saveItem = nil
            Store.shared.save(state: self.state)
        }
        saveItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: item)
    }

    func saveNow() {
        saveItem?.cancel()
        saveItem = nil
        Store.shared.save(state: state)
    }

    /// Called when the app goes to the background: make sure nothing is lost.
    func flushToDisk() {
        saveNow()
        Store.shared.flush()
    }

    // MARK: - Alerts and notifications

    private func apply(_ result: ReminderResult) {
        for e in result.events { addEvent(e) }
        for a in result.alerts { notify(a) }
    }

    private func notify(_ a: PendingAlert) {
        showToast(a.title, a.body, level: a.level, seconds: a.level == .danger ? 12 : 8)

        let content = UNMutableNotificationContent()
        content.title = a.title
        content.body = a.body
        content.threadIdentifier = a.id
        if state.settings.sound { content.sound = .default }
        let request = UNNotificationRequest(identifier: "\(a.id)-\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }

        if UIApplication.shared.applicationState == .active {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(a.level == .danger ? .error : .warning)
        }
    }

    func showToast(_ title: String, _ body: String, level: AlertLevel, seconds: Double = 6) {
        let toast = Toast(title: title, body: body, level: level)
        toasts.insert(toast, at: 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.dismissToast(toast.id)
        }
    }

    func dismissToast(_ id: UUID) {
        toasts.removeAll { $0.id == id }
    }

    func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] _, _ in
            self?.refreshNotificationStatus()
        }
    }

    func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async { self?.notificationStatus = settings.authorizationStatus }
        }
    }

    // MARK: - Live Activity (Dynamic Island + Lock Screen)

    private func makeContentState() -> RideActivityAttributes.ContentState {
        let s = state
        return RideActivityAttributes.ContentState(
            speedKmh: Int(speedKmh.rounded()),
            rideKm: (s.rideKm * 10).rounded() / 10,
            tripKm: (s.trip.km * 10).rounded() / 10,
            odoKm: s.odoKm.rounded(.down),
            fuelLeftKm: Int(max(0, s.fuelKm).rounded(.down)),
            oilLeftKm: Int(s.oilLeftKm.rounded(.down)),
            mode: s.settings.islandMode
        )
    }

    private func adoptExistingActivity() {
        let existing = Activity<RideActivityAttributes>.activities
        if state.isRiding, let first = existing.first {
            activity = first
            for extra in existing.dropFirst() { finish(extra) }
        } else {
            for old in existing { finish(old) }
        }
    }

    private func finish(_ a: Activity<RideActivityAttributes>) {
        Task { await a.end(nil, dismissalPolicy: .immediate) }
    }

    private func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            showToast("Live Activities are off",
                      "Turn them on in Settings > MotoDash to see the ride in the Dynamic Island.",
                      level: .warn, seconds: 8)
            return
        }
        if let old = activity { finish(old) }
        activity = nil

        let attributes = RideActivityAttributes(startedAt: state.rideStartedAt ?? Date())
        let content = ActivityContent(state: makeContentState(), staleDate: nil)
        do {
            activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
            lastPushed = content.state
            lastPush = Date()
        } catch {
            showToast("Dynamic Island unavailable", error.localizedDescription, level: .warn, seconds: 8)
        }
    }

    /// Re-create the Live Activity if the user swiped it away or it hit iOS's 8-hour limit.
    func ensureLiveActivity() {
        guard state.isRiding else { return }
        if let a = activity, a.activityState == .active { return }
        startLiveActivity()
    }

    private func endLiveActivity() {
        guard let a = activity else { return }
        activity = nil
        lastPushed = nil
        let final = ActivityContent(state: makeContentState(), staleDate: nil)
        Task { await a.end(final, dismissalPolicy: .immediate) }
    }

    private func pushActivity(force: Bool = false) {
        guard let a = activity else { return }
        let content = makeContentState()
        if !force {
            if Date().timeIntervalSince(lastPush) < 1 { return }
            if content == lastPushed { return }
        }
        lastPush = Date()
        lastPushed = content
        Task { await a.update(ActivityContent(state: content, staleDate: nil)) }
    }
}

// MARK: - CLLocationManagerDelegate

extension RideEngine: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard state.isRiding, !state.settings.sim else { return }
        for loc in locations { process(loc) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard state.isRiding else { return }
        if (error as? CLError)?.code == .denied {
            denyLocation()
        } else {
            gpsStatus = .searching
            gpsText = "GPS error"
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        locationAuth = manager.authorizationStatus
        guard state.isRiding, !state.settings.sim else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse:
            requestAlwaysOnce()
            startUpdates()
        case .authorizedAlways:
            startUpdates()
        case .denied, .restricted:
            denyLocation()
        default:
            break
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension RideEngine: UNUserNotificationCenterDelegate {
    /// Show the banner even while the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}
