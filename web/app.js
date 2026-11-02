'use strict';

/* =========================================================
   MotoDash — motorcycle dashboard PWA
   Speed + distance from GPS, odometer, trip, fuel & oil reminders.
   Data: IndexedDB (primary) + localStorage (fast mirror/fallback).
   ========================================================= */

const DEFAULT_STATE = {
  version: 1,
  odoKm: 10820,          // total km on the bike
  fuelKm: 150,           // estimated range left in the tank
  kmSinceFill: 0,
  lastOilKm: 10000,      // odometer at last oil change -> next at 11000
  appKm: 0,              // distance measured by this app
  fuelSpent: 0,          // DT
  trip: { km: 0, movingMs: 0, maxKmh: 0, startedAt: Date.now() },
  flags: {
    milestone: 10,       // last 1000-km milestone announced (10 = 10 000 km)
    oilWarnTarget: null, // "oil soon" already sent for this target odometer
    oilDueTarget: null,  // "oil due" already sent for this target odometer
    oilOverdueStep: 0,
    fuelWarned: false,
    fuelEmpty: false,
  },
  settings: {
    oilInterval: 1000,
    oilWarn: 100,
    fuelPerFill: 220,
    fuelPrice: 20,
    fuelWarn: 20,
    sound: true,
    wake: true,
    gapFill: true,
    sim: false,
    simMul: 1,
  },
  updatedAt: 0,
};

const GPS = {
  maxAccuracy: 40,     // m — ignore fixes worse than this
  gapSeconds: 20,      // a longer silence means the app was paused
  glitchKmh: 220,      // implied speed above this = GPS jump
  maxGapKmh: 130,      // gap-fill only if implied average speed is plausible
  staleMs: 6000,       // no fix for this long -> show 0 km/h
};
const GAUGE_MAX = 160;
const LS_KEY = 'motodash.state';
const LS_EVENTS = 'motodash.events';

const LS_LOCKED = 'motodash.locked';

const $ = (id) => document.getElementById(id);
const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
const fmtInt = (n) => Math.round(n).toLocaleString('fr-FR');
const withTimeout = (p, ms) => Promise.race([p, new Promise((_, reject) => setTimeout(() => reject(new Error('timeout')), ms))]);

let state = structuredClone(DEFAULT_STATE);

/* ---------------------------------------------------------
   Storage
   --------------------------------------------------------- */
const Store = {
  db: null,

  async open() {
    if (!('indexedDB' in window)) return null;
    try {
      // iOS sometimes never answers indexedDB.open: don't wait forever, localStorage has a copy
      this.db = await withTimeout(new Promise((resolve, reject) => {
        const req = indexedDB.open('motodash', 1);
        req.onupgradeneeded = () => {
          const db = req.result;
          db.createObjectStore('kv');
          db.createObjectStore('events', { keyPath: 'id', autoIncrement: true });
        };
        req.onsuccess = () => resolve(req.result);
        req.onerror = () => reject(req.error);
      }), 4000);
    } catch (e) {
      console.warn('IndexedDB unavailable, using localStorage only', e);
      this.db = null;
    }
    return this.db;
  },

  req(store, mode, fn) {
    return new Promise((resolve, reject) => {
      const tx = this.db.transaction(store, mode);
      const r = fn(tx.objectStore(store));
      tx.oncomplete = () => resolve(r && r.result);
      tx.onerror = () => reject(tx.error);
    });
  },

  async loadState() {
    let fromLs = null, fromDb = null;
    try { fromLs = JSON.parse(localStorage.getItem(LS_KEY)); } catch (e) {}
    if (this.db) {
      try { fromDb = await withTimeout(this.req('kv', 'readonly', (s) => s.get('state')), 3000); } catch (e) {}
    }
    const pick = [fromLs, fromDb].filter(Boolean).sort((a, b) => (b.updatedAt || 0) - (a.updatedAt || 0))[0];
    return pick ? mergeDefaults(pick) : null;
  },

  // Everything before the first await runs synchronously: localStorage is written on return
  async saveState(s) {
    s.updatedAt = Date.now();
    try { localStorage.setItem(LS_KEY, JSON.stringify(s)); } catch (e) {}
    if (this.db) {
      try { await this.req('kv', 'readwrite', (st) => st.put(structuredClone(s), 'state')); } catch (e) {}
    }
  },

  async addEvent(ev) {
    ev = { at: Date.now(), ...ev };
    if (this.db) {
      try { await this.req('events', 'readwrite', (s) => s.add(ev)); return; } catch (e) {}
    }
    const list = this._lsEvents();
    list.push(ev);
    try { localStorage.setItem(LS_EVENTS, JSON.stringify(list.slice(-300))); } catch (e) {}
  },

  async events() {
    if (this.db) {
      try { return (await this.req('events', 'readonly', (s) => s.getAll())) || []; } catch (e) {}
    }
    return this._lsEvents();
  },

  async replaceEvents(list) {
    if (this.db) {
      await this.req('events', 'readwrite', (s) => {
        s.clear();
        list.forEach(({ id, ...ev }) => s.add(ev));
      });
    } else {
      localStorage.setItem(LS_EVENTS, JSON.stringify(list));
    }
  },

  _lsEvents() {
    try { return JSON.parse(localStorage.getItem(LS_EVENTS)) || []; } catch (e) { return []; }
  },
};

function mergeDefaults(s) {
  const d = structuredClone(DEFAULT_STATE);
  return {
    ...d, ...s,
    trip: { ...d.trip, ...(s.trip || {}) },
    flags: { ...d.flags, ...(s.flags || {}) },
    settings: { ...d.settings, ...(s.settings || {}) },
  };
}

/* Several copies of the app can be open at once (a Safari tab and the Home Screen
   app, a tab iOS kept frozen for days…). Each holds its own state in memory, so
   before using or saving it we check whether another copy saved in the meantime;
   if so we continue from that data plus the distance this copy measured since.
   Nothing is saved until the stored data has been loaded (ready). */
let ready = false;
let syncedAt = 0;               // updatedAt of the stored state the in-memory state is based on
let pending = freshPending();   // distance measured since syncedAt, not saved yet

function freshPending() { return { km: 0, appKm: 0, movingMs: 0, maxKmh: 0 }; }

function applyPending() {
  const p = pending;
  state.odoKm += p.km;
  state.appKm += p.appKm;
  state.trip.km += p.km;
  state.trip.movingMs += p.movingMs;
  state.trip.maxKmh = Math.max(state.trip.maxKmh, p.maxKmh);
  state.fuelKm -= p.km;
  state.kmSinceFill += p.km;
}

// Returns true when another copy had saved newer data (now adopted)
function refreshFromStorage() {
  if (!ready) return false;
  let stored = null;
  try { stored = JSON.parse(localStorage.getItem(LS_KEY)); } catch (e) {}
  if (!stored || !(stored.updatedAt > syncedAt)) return false;
  state = mergeDefaults(stored);
  syncedAt = stored.updatedAt;
  applyPending();
  render();
  return true;
}

function persist(force = false) {
  if (!ready) return Promise.resolve();
  if (!force) refreshFromStorage();
  const saved = Store.saveState(state);
  syncedAt = state.updatedAt;
  pending = freshPending();
  return saved;
}

let saveTimer = null;
function scheduleSave() {
  if (saveTimer) return;
  saveTimer = setTimeout(() => { saveTimer = null; persist(); }, 2000);
}
function saveNow(force = false) {
  clearTimeout(saveTimer);
  saveTimer = null;
  return persist(force);
}

/* ---------------------------------------------------------
   Distance accounting + reminders
   --------------------------------------------------------- */
// manual = km typed in by the user: counts like ridden km, but not as "tracked by app"
function addDistance(km, movingSeconds = 0, manual = false) {
  if (!(km > 0)) return;
  refreshFromStorage();
  const appKm = manual ? 0 : km;
  state.odoKm += km;
  state.appKm += appKm;
  state.trip.km += km;
  state.trip.movingMs += movingSeconds * 1000;
  state.fuelKm -= km;
  state.kmSinceFill += km;
  pending.km += km;
  pending.appKm += appKm;
  pending.movingMs += movingSeconds * 1000;
  checkReminders();
  scheduleSave();
}

function addManualKm() {
  const km = parseFloat($('addKm').value);
  if (!(km > 0 && km <= 5000)) {
    toast('Enter the km to add', 'Type the missed distance (e.g. 12.5), then tap +KM.', 'warn');
    return;
  }
  addDistance(km, 0, true);
  Store.addEvent({ type: 'manual', odo: state.odoKm, note: `+${km.toFixed(1)} km added by hand` });
  toast(`+${km.toFixed(1)} km added`, `Odometer ${fmtInt(state.odoKm)} km · fuel ${Math.max(0, Math.floor(state.fuelKm))} km left`, 'ok');
  $('addKm').value = '';
  saveNow();
  fillSettings();
  render();
}

function checkReminders() {
  const s = state, st = s.settings, f = s.flags;

  // 1000-km milestones on the odometer
  let milestone = null;
  const ms = Math.floor(s.odoKm / 1000);
  if (ms > f.milestone) {
    f.milestone = ms;
    milestone = ms * 1000;
    Store.addEvent({ type: 'milestone', odo: milestone, note: `${fmtInt(milestone)} km reached` });
  }

  // Oil change (vidange)
  const nextOil = s.lastOilKm + st.oilInterval;
  const oilLeft = nextOil - s.odoKm;
  if (oilLeft <= 0) {
    const step = Math.floor(-oilLeft / 50); // remind again every 50 km overdue
    const first = f.oilDueTarget !== nextOil;
    if (first || step > f.oilOverdueStep) {
      f.oilDueTarget = nextOil;
      f.oilWarnTarget = nextOil;
      f.oilOverdueStep = step;
      const title = milestone ? `${fmtInt(milestone)} km — Oil change time!` : first ? 'Oil change due (vidange)' : `Oil change overdue by ${Math.round(-oilLeft)} km`;
      notify(title, `Total: ${fmtInt(s.odoKm)} km. Change the oil, then tap “Oil changed”.`, 'danger', 'oil');
      milestone = null;
    }
  } else if (oilLeft <= st.oilWarn && f.oilWarnTarget !== nextOil) {
    f.oilWarnTarget = nextOil;
    notify('Oil change soon', `${Math.ceil(oilLeft)} km left — vidange at ${fmtInt(nextOil)} km.`, 'warn', 'oil');
  }

  if (milestone) {
    notify(`${fmtInt(milestone)} km reached`, `Total distance on the bike: ${fmtInt(s.odoKm)} km.`, 'ok', 'milestone');
  }

  // Fuel
  if (s.fuelKm <= 0 && !f.fuelEmpty) {
    f.fuelEmpty = f.fuelWarned = true;
    notify(`Fuel: pay ${st.fuelPrice} DT`, `${Math.round(s.kmSinceFill)} km since last fill — time to refuel.`, 'danger', 'fuel');
  } else if (s.fuelKm > 0 && s.fuelKm <= st.fuelWarn && !f.fuelWarned) {
    f.fuelWarned = true;
    notify('Fuel low', `About ${Math.ceil(s.fuelKm)} km left. Plan to pay ${st.fuelPrice} DT soon.`, 'warn', 'fuel');
  }
}

function resetFuelFlags() {
  const st = state.settings;
  state.flags.fuelEmpty = state.fuelKm <= 0;
  state.flags.fuelWarned = state.fuelKm <= st.fuelWarn;
}

function refuel() {
  refreshFromStorage();
  const st = state.settings;
  state.fuelKm = Math.max(0, state.fuelKm) + st.fuelPerFill;
  state.fuelSpent += st.fuelPrice;
  const since = state.kmSinceFill;
  state.kmSinceFill = 0;
  resetFuelFlags();
  Store.addEvent({ type: 'fuel', odo: state.odoKm, note: `Paid ${st.fuelPrice} DT · ${Math.round(since)} km since previous fill` });
  toast('Fuel added', `+${st.fuelPerFill} km of range · ${st.fuelPrice} DT`, 'ok');
  saveNow();
  render();
}

function oilChanged() {
  refreshFromStorage();
  state.lastOilKm = Math.floor(state.odoKm);
  state.flags.oilWarnTarget = state.flags.oilDueTarget = null;
  state.flags.oilOverdueStep = 0;
  Store.addEvent({ type: 'oil', odo: state.odoKm, note: `Oil changed · next at ${fmtInt(state.lastOilKm + state.settings.oilInterval)} km` });
  toast('Oil change saved', `Next vidange at ${fmtInt(state.lastOilKm + state.settings.oilInterval)} km`, 'ok');
  saveNow();
  render();
}

function resetTrip() {
  refreshFromStorage();
  const t = state.trip;
  if (t.km > 0.05) {
    Store.addEvent({ type: 'trip', odo: state.odoKm, note: `Trip ${t.km.toFixed(1)} km · ${fmtDuration(t.movingMs)} · max ${Math.round(t.maxKmh)} km/h` });
  }
  state.trip = { km: 0, movingMs: 0, maxKmh: 0, startedAt: Date.now() };
  saveNow();
  render();
}

/* ---------------------------------------------------------
   Alerts: toast + sound + system notification
   --------------------------------------------------------- */
let audioCtx = null;
function unlockAudio() {
  if (audioCtx) { audioCtx.resume?.(); return; }
  const AC = window.AudioContext || window.webkitAudioContext;
  if (!AC) return;
  audioCtx = new AC();
  // iOS: play a silent buffer inside the gesture to unlock
  const b = audioCtx.createBuffer(1, 1, 22050);
  const src = audioCtx.createBufferSource();
  src.buffer = b; src.connect(audioCtx.destination); src.start(0);
}

function beep(level) {
  if (!state.settings.sound || !audioCtx) return;
  const pattern = level === 'danger' ? [880, 0, 880, 0, 880] : level === 'warn' ? [660, 0, 660] : [520, 780];
  let t = audioCtx.currentTime + 0.02;
  for (const f of pattern) {
    if (f) {
      const o = audioCtx.createOscillator(), g = audioCtx.createGain();
      o.type = 'square'; o.frequency.value = f;
      g.gain.setValueAtTime(0.0001, t);
      g.gain.exponentialRampToValueAtTime(0.25, t + 0.01);
      g.gain.exponentialRampToValueAtTime(0.0001, t + 0.16);
      o.connect(g).connect(audioCtx.destination);
      o.start(t); o.stop(t + 0.18);
    }
    t += 0.18;
  }
}

function toast(title, body, level = 'info', ms = 6000) {
  const el = document.createElement('div');
  el.className = `toast ${level}`;
  el.innerHTML = `<div class="toast-title"></div><div class="toast-body"></div>`;
  el.firstChild.textContent = title;
  el.lastChild.textContent = body || '';
  el.onclick = () => dismiss();
  $('toasts').prepend(el);
  const dismiss = () => { el.classList.add('out'); setTimeout(() => el.remove(), 300); };
  setTimeout(dismiss, ms);
}

async function notify(title, body, level, tag) {
  toast(title, body, level, level === 'danger' ? 12000 : 8000);
  beep(level);
  if (navigator.vibrate) navigator.vibrate(level === 'danger' ? [300, 100, 300] : 200);
  if (!('Notification' in window) || Notification.permission !== 'granted') return;
  const opts = { body, tag, renotify: true, icon: 'icons/icon-192.png', badge: 'icons/icon-192.png' };
  try {
    const reg = await navigator.serviceWorker?.getRegistration();
    if (reg) await reg.showNotification(title, opts);
    else new Notification(title, opts);
  } catch (e) { console.warn('notification failed', e); }
}

async function enableNotifications() {
  unlockAudio();
  if (!('Notification' in window)) {
    toast('Notifications need the Home Screen app', 'On iPhone: Safari → Share → “Add to Home Screen”, then open MotoDash from its icon and enable again.', 'warn', 10000);
    return;
  }
  const res = await Notification.requestPermission();
  updateNotifHint();
  if (res === 'granted') notify('Notifications enabled', 'You will get oil and fuel reminders here.', 'ok', 'test');
}

function updateNotifHint() {
  const hint = $('notifHint'), btn = $('btnNotif');
  if (!('Notification' in window)) {
    hint.textContent = isStandalone() ? 'Not supported on this device' : 'iPhone: Add to Home Screen first';
    btn.textContent = 'How?';
    return;
  }
  const p = Notification.permission;
  hint.textContent = p === 'granted' ? 'Enabled' : p === 'denied' ? 'Blocked — allow in iOS Settings' : 'Not enabled';
  btn.textContent = p === 'granted' ? 'Test' : 'Enable';
}

const isStandalone = () => window.matchMedia('(display-mode: standalone)').matches || navigator.standalone === true;

/* ---------------------------------------------------------
   Ride: GPS / simulation
   --------------------------------------------------------- */
let riding = false;
let watchId = null;
let lastFix = null;     // { lat, lon, t }
let lastFixAt = 0;      // Date.now() of last accepted fix
let speedKmh = 0;       // displayed (smoothed)
let simTimer = null;
let wakeLock = null;

function startRide() {
  if (!ready) return;
  unlockAudio();
  riding = true;
  lastFix = null;
  if (state.settings.sim) startSim(); else startGps();
  requestWakeLock();
  renderRideButton();
}

function stopRide() {
  riding = false;
  if (watchId != null) navigator.geolocation.clearWatch(watchId);
  watchId = null;
  clearInterval(simTimer);
  simTimer = null;
  lastFix = null;
  setSpeed(0, true);
  setGps('', 'GPS off');
  releaseWakeLock();
  saveNow();
  renderRideButton();
  render();
}

function startGps() {
  if (!('geolocation' in navigator)) {
    toast('No GPS', 'This browser has no geolocation.', 'danger');
    stopRide();
    return;
  }
  setGps('searching', 'Searching…');
  watchId = navigator.geolocation.watchPosition(onPosition, onGpsError, {
    enableHighAccuracy: true,
    maximumAge: 0,
    timeout: 20000,
  });
}

function onGpsError(err) {
  if (err.code === err.PERMISSION_DENIED) {
    setGps('err', 'No permission');
    toast('Location blocked', 'Allow location: iPhone Settings → Privacy → Location Services → Safari Websites → While Using.', 'danger', 12000);
    stopRide();
  } else {
    setGps('searching', err.code === err.TIMEOUT ? 'Waiting for GPS…' : 'GPS error');
  }
}

function onPosition(pos) {
  if (!riding || state.settings.sim) return;
  const c = pos.coords;
  const t = pos.timestamp || Date.now();
  const acc = c.accuracy || 999;

  setGps(acc <= 15 ? 'ok' : acc <= GPS.maxAccuracy ? 'weak' : 'searching', `GPS ±${Math.round(acc)} m`);
  if (acc > GPS.maxAccuracy) return;

  const cur = { lat: c.latitude, lon: c.longitude, t };
  const gpsSpeed = c.speed != null && c.speed >= 0 ? c.speed * 3.6 : null;

  if (!lastFix) {
    lastFix = cur;
    lastFixAt = Date.now();
    setSpeed(gpsSpeed ?? 0);
    return;
  }

  const dt = (t - lastFix.t) / 1000;
  if (dt <= 0) return;
  const d = haversine(lastFix, cur); // meters
  const implied = (d / dt) * 3.6;

  // App was paused (screen locked / other app): GPS had a gap
  if (dt > GPS.gapSeconds) {
    // If another copy of the app saved meanwhile, it already counted this time
    const otherCopyCounted = refreshFromStorage();
    if (!otherCopyCounted && state.settings.gapFill && d > 50 && implied < GPS.maxGapKmh) {
      const km = d / 1000;
      addDistance(km, 0);
      Store.addEvent({ type: 'gap', odo: state.odoKm, note: `Estimated ${km.toFixed(1)} km while app was paused (${fmtDuration(dt * 1000)})` });
      toast('Distance estimated', `+${km.toFixed(1)} km (straight line) while the app was paused.`, 'info');
    }
    lastFix = cur;
    lastFixAt = Date.now();
    setSpeed(gpsSpeed ?? 0);
    render();
    return;
  }

  if (implied > GPS.glitchKmh) return; // GPS jump, wait for a sane fix

  lastFixAt = Date.now();
  const kmh = gpsSpeed ?? implied;
  const jitter = Math.max(5, acc * 0.5);

  if (d < jitter && kmh < 4) {
    // Standing still: keep the anchor position, just advance its time
    lastFix.t = t;
    setSpeed(0);
    return;
  }

  addDistance(d / 1000, kmh >= 3 ? dt : 0);
  lastFix = cur;
  setSpeed(kmh);
  render();
}

function haversine(a, b) {
  const R = 6371000, rad = Math.PI / 180;
  const dLat = (b.lat - a.lat) * rad, dLon = (b.lon - a.lon) * rad;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(a.lat * rad) * Math.cos(b.lat * rad) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

/* Simulation: a fake ride, for testing on a computer */
function startSim() {
  setGps('sim', `SIM ×${state.settings.simMul}`);
  let v = 0, target = 50, last = performance.now();
  simTimer = setInterval(() => {
    const now = performance.now();
    const dt = (now - last) / 1000;
    last = now;
    if (Math.random() < 0.06) target = Math.random() < 0.12 ? 0 : 25 + Math.random() * 85;
    v += clamp(target - v, -12 * dt, 6 * dt);
    v = Math.max(0, v + (Math.random() - 0.5) * 1.5);
    const mul = Number(state.settings.simMul) || 1;
    lastFixAt = Date.now();
    setSpeed(v);
    addDistance((v / 3600) * dt * mul, v >= 3 ? dt * mul : 0);
    render();
  }, 500);
}

function setSpeed(kmh, immediate) {
  kmh = clamp(kmh || 0, 0, 300);
  speedKmh = immediate ? kmh : speedKmh * 0.35 + kmh * 0.65;
  if (speedKmh < 1.5) speedKmh = 0;
  if (riding && speedKmh > state.trip.maxKmh) state.trip.maxKmh = pending.maxKmh = speedKmh;
  renderSpeed();
}

function setGps(cls, text) {
  $('gpsStatus').className = 'gps ' + cls;
  $('gpsText').textContent = text;
}

/* Wake lock keeps the screen on so iOS doesn't pause the app */
async function requestWakeLock() {
  if (!state.settings.wake || !('wakeLock' in navigator) || !riding) return;
  try {
    wakeLock = await navigator.wakeLock.request('screen');
    wakeLock.addEventListener('release', () => { wakeLock = null; });
  } catch (e) { console.warn('wake lock', e); }
}
function releaseWakeLock() {
  wakeLock?.release().catch(() => {});
  wakeLock = null;
}

/* ---------------------------------------------------------
   Rendering
   --------------------------------------------------------- */
const G = { cx: 150, cy: 140, r: 110, start: 150, sweep: 240 };

function polar(r, deg) {
  const a = (deg * Math.PI) / 180;
  return [G.cx + r * Math.cos(a), G.cy + r * Math.sin(a)];
}
function arcPath(r, fromDeg, toDeg) {
  const [x0, y0] = polar(r, fromDeg), [x1, y1] = polar(r, toDeg);
  const large = toDeg - fromDeg > 180 ? 1 : 0;
  return `M${x0.toFixed(2)} ${y0.toFixed(2)} A${r} ${r} 0 ${large} 1 ${x1.toFixed(2)} ${y1.toFixed(2)}`;
}

function buildGauge() {
  $('arcBg').setAttribute('d', arcPath(G.r, G.start, G.start + G.sweep));
  const ticks = $('ticks'), labels = $('tickLabels');
  const ns = 'http://www.w3.org/2000/svg';
  for (let v = 0; v <= GAUGE_MAX; v += 10) {
    const deg = G.start + (v / GAUGE_MAX) * G.sweep;
    const major = v % 20 === 0;
    const [x0, y0] = polar(G.r - 14, deg), [x1, y1] = polar(G.r - (major ? 24 : 19), deg);
    const line = document.createElementNS(ns, 'line');
    line.setAttribute('x1', x0); line.setAttribute('y1', y0);
    line.setAttribute('x2', x1); line.setAttribute('y2', y1);
    line.setAttribute('class', major ? 'tick major' : 'tick');
    ticks.appendChild(line);
    if (major) {
      const [lx, ly] = polar(G.r - 36, deg);
      const text = document.createElementNS(ns, 'text');
      text.setAttribute('x', lx); text.setAttribute('y', ly);
      text.setAttribute('class', 'tick-label');
      text.textContent = v;
      labels.appendChild(text);
    }
  }
}

function renderSpeed() {
  const v = Math.round(speedKmh);
  $('speed').textContent = v;
  const frac = clamp(speedKmh / GAUGE_MAX, 0, 1);
  $('arcFg').setAttribute('d', frac > 0.004 ? arcPath(G.r, G.start, G.start + frac * G.sweep) : '');
}

function fmtDuration(ms) {
  const m = Math.floor(ms / 60000);
  const h = Math.floor(m / 60);
  return h ? `${h}:${String(m % 60).padStart(2, '0')}h` : `${m}:${String(Math.floor(ms / 1000) % 60).padStart(2, '0')}`;
}

function render() {
  const s = state, st = s.settings;

  // Odometer
  const odo10 = Math.floor(s.odoKm * 10);
  $('odo').textContent = String(Math.floor(odo10 / 10)).padStart(6, '0');
  $('odoDec').textContent = '.' + (odo10 % 10);

  // Trip
  const t = s.trip;
  $('tripKm').textContent = t.km.toFixed(1);
  $('tripTime').textContent = fmtDuration(t.movingMs);
  $('tripAvg').textContent = t.movingMs > 10000 ? Math.round(t.km / (t.movingMs / 3600000)) : 0;
  $('tripMax').textContent = Math.round(t.maxKmh);

  // Fuel
  const fuelLeft = Math.max(0, s.fuelKm);
  $('fuelKm').textContent = Math.floor(fuelLeft);
  $('fuelSub').textContent = `since fill ${Math.round(s.kmSinceFill)} km`;
  $('fuelBar').style.width = clamp((fuelLeft / st.fuelPerFill) * 100, 0, 100) + '%';
  const priceLbl = $('refuelPriceLbl'); // absent while the button shows "Confirm paid?"
  if (priceLbl) priceLbl.textContent = st.fuelPrice;
  const fuelCard = $('fuelCard');
  fuelCard.classList.toggle('is-danger', s.fuelKm <= 0);
  fuelCard.classList.toggle('is-warn', s.fuelKm > 0 && s.fuelKm <= st.fuelWarn);

  // Oil
  const nextOil = s.lastOilKm + st.oilInterval;
  const oilLeft = nextOil - s.odoKm;
  $('oilNext').textContent = fmtInt(nextOil);
  $('oilLeft').textContent = oilLeft > -1 ? Math.max(0, Math.floor(oilLeft)) : '−' + Math.floor(-oilLeft);
  $('oilLeft').nextElementSibling.textContent = oilLeft >= 0 ? 'km to change' : 'km overdue';
  $('oilBar').style.width = clamp((oilLeft / st.oilInterval) * 100, 0, 100) + '%';
  const oilCard = $('oilCard');
  oilCard.classList.toggle('is-danger', oilLeft <= 0);
  oilCard.classList.toggle('is-warn', oilLeft > 0 && oilLeft <= st.oilWarn);

  // Persistent banners
  const alerts = [];
  if (oilLeft <= 0) alerts.push(['danger', `Oil change (vidange) due — ${oilLeft <= -1 ? Math.floor(-oilLeft) + ' km overdue' : 'now'}`]);
  if (s.fuelKm <= 0) alerts.push(['danger', `Fuel: pay ${st.fuelPrice} DT now`]);
  const html = alerts.map(([lvl, msg]) => `<div class="alert ${lvl}">⚠ ${msg}</div>`).join('');
  if ($('alerts').innerHTML !== html) $('alerts').innerHTML = html;
}

function renderRideButton() {
  $('btnRide').classList.toggle('on', riding);
  $('rideLabel').textContent = riding ? 'Stop ride' : state.settings.sim ? 'Start simulated ride' : 'Start ride';
}

/* ---------------------------------------------------------
   Settings + history sheet
   --------------------------------------------------------- */
const numFields = {
  setOdo: ['odoKm', null],
  setFuel: ['fuelKm', null],
  setLastOil: ['lastOilKm', null],
  setOilInterval: ['oilInterval', 'settings'],
  setOilWarn: ['oilWarn', 'settings'],
  setFuelPerFill: ['fuelPerFill', 'settings'],
  setFuelPrice: ['fuelPrice', 'settings'],
  setFuelWarn: ['fuelWarn', 'settings'],
};
const boolFields = { setSound: 'sound', setWake: 'wake', setGapFill: 'gapFill', setSim: 'sim' };

function fillSettings() {
  for (const [id, [key, scope]] of Object.entries(numFields)) {
    const v = scope ? state.settings[key] : state[key];
    $(id).value = key === 'odoKm' ? (Math.floor(v * 10) / 10) : Math.round(v * 10) / 10;
  }
  for (const [id, key] of Object.entries(boolFields)) $(id).checked = !!state.settings[key];
  $('setSimMul').value = String(state.settings.simMul);
  $('fuelSpent').textContent = `${fmtInt(state.fuelSpent)} DT`;
  $('appKm').textContent = `${state.appKm.toFixed(1)} km`;
  updateNotifHint();
}

function onNumberChange(id) {
  const [key, scope] = numFields[id];
  const v = parseFloat($(id).value);
  refreshFromStorage();
  if (!isFinite(v) || v < 0) { fillSettings(); return; }
  const old = scope ? state.settings[key] : state[key];
  if (scope) state.settings[key] = v; else state[key] = v;

  if (key === 'odoKm') {
    state.flags.milestone = Math.floor(v / 1000);
    Store.addEvent({ type: 'edit', odo: v, note: `Odometer set from ${old.toFixed(1)} to ${v.toFixed(1)} km` });
  }
  if (key === 'fuelKm' || key === 'fuelWarn') resetFuelFlags();
  if (key === 'lastOilKm' || key === 'oilInterval' || key === 'oilWarn') {
    state.flags.oilWarnTarget = state.flags.oilDueTarget = null;
    state.flags.oilOverdueStep = 0;
  }
  checkReminders();
  saveNow();
  render();
}

function openSheet() {
  refreshFromStorage();
  fillSettings();
  $('sheetBackdrop').hidden = false;
  $('sheet').classList.add('open');
  $('sheet').setAttribute('aria-hidden', 'false');
}
function closeSheet() {
  $('sheet').classList.remove('open');
  $('sheet').setAttribute('aria-hidden', 'true');
  $('sheetBackdrop').hidden = true;
  document.activeElement?.blur();
}

const EVENT_ICONS = { fuel: '⛽', oil: '🛢', trip: '🏁', milestone: '🏆', gap: '📡', edit: '✎', import: '⤓', manual: '＋' };
const EVENT_TITLES = { fuel: 'Refuel', oil: 'Oil change', trip: 'Trip saved', milestone: 'Milestone', gap: 'GPS gap', edit: 'Manual edit', import: 'Backup imported', manual: 'Km added' };

async function renderHistory() {
  const list = (await Store.events()).sort((a, b) => b.at - a.at).slice(0, 200);
  const ul = $('historyList');
  ul.innerHTML = '';
  if (!list.length) {
    ul.innerHTML = '<li class="empty">No events yet. Refuels, oil changes and trips will appear here.</li>';
    return;
  }
  for (const ev of list) {
    const li = document.createElement('li');
    const d = new Date(ev.at);
    li.innerHTML = `<span class="h-ico"></span><span class="h-title"></span><span class="h-odo"></span><span class="h-meta"></span>`;
    li.children[0].textContent = EVENT_ICONS[ev.type] || '•';
    li.children[1].textContent = EVENT_TITLES[ev.type] || ev.type;
    li.children[2].textContent = ev.odo != null ? `${fmtInt(ev.odo)} km` : '';
    li.children[3].textContent = `${d.toLocaleDateString('fr-FR')} ${d.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })} · ${ev.note || ''}`;
    ul.appendChild(li);
  }
}

async function exportBackup() {
  await saveNow();
  const data = { app: 'motodash', exportedAt: new Date().toISOString(), state, events: await Store.events() };
  const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
  const file = new File([blob], `motodash-${new Date().toISOString().slice(0, 10)}.json`, { type: 'application/json' });
  if (navigator.canShare?.({ files: [file] })) {
    try { await navigator.share({ files: [file], title: 'MotoDash backup' }); return; } catch (e) { if (e.name === 'AbortError') return; }
  }
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = file.name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 5000);
}

async function importBackup(file) {
  try {
    const data = JSON.parse(await file.text());
    if (data.app !== 'motodash' || !data.state) throw new Error('Not a MotoDash backup');
    state = mergeDefaults(data.state);
    pending = freshPending();
    await saveNow(true); // the backup replaces whatever any other copy saved
    if (Array.isArray(data.events)) await Store.replaceEvents(data.events);
    await Store.addEvent({ type: 'import', odo: state.odoKm, note: `From ${data.exportedAt || 'file'}` });
    await saveNow();
    fillSettings(); render(); renderRideButton();
    toast('Backup restored', `Odometer ${fmtInt(state.odoKm)} km`, 'ok');
  } catch (e) {
    toast('Import failed', e.message, 'danger');
  }
}

async function factoryReset() {
  if (riding) stopRide();
  state = structuredClone(DEFAULT_STATE);
  pending = freshPending();
  await saveNow(true);
  await Store.replaceEvents([]);
  fillSettings(); render(); renderRideButton();
  toast('Reset done', 'Back to 10 820 km and 150 km of fuel.', 'ok');
}

/* Two-tap confirm for buttons you don't want to hit by accident (gloves, bumps) */
function armed(btn, label, action) {
  const original = btn.innerHTML;
  let timer = null;
  btn.addEventListener('click', () => {
    if (btn.dataset.armed) {
      clearTimeout(timer);
      delete btn.dataset.armed;
      btn.classList.remove('armed');
      btn.innerHTML = original;
      action();
    } else {
      btn.dataset.armed = '1';
      btn.classList.add('armed');
      btn.textContent = label;
      timer = setTimeout(() => {
        delete btn.dataset.armed;
        btn.classList.remove('armed');
        btn.innerHTML = original;
        // keep dynamic labels current
        render();
      }, 3000);
    }
  });
}

/* ---------------------------------------------------------
   Screen lock: blocks every touch (rain, gloves, bumps).
   Unlock = drag the lock knob along an "L" by the screen edge:
   down the left edge, then right along the bottom.
   --------------------------------------------------------- */
const Lock = {
  on: false,
  pts: null,      // [A, B, C]: start, corner, end of the L
  len1: 0, len: 0,
  progress: 0,    // distance travelled along the L
  dragging: false,

  layout() {
    const el = $('lock'), cs = getComputedStyle(el);
    const sl = parseFloat(cs.paddingLeft) || 0, sr = parseFloat(cs.paddingRight) || 0;
    const st = parseFloat(cs.paddingTop) || 0, sb = parseFloat(cs.paddingBottom) || 0;
    const w = window.innerWidth, h = window.innerHeight;
    const x0 = sl + 40;                   // clear of the edge-swipe zone
    const yTop = st + (h - st - sb) * 0.3;
    const yCorner = h - sb - 84;          // above the iPhone home bar (swiping there switches apps)
    const xEnd = w - sr - 40;
    this.pts = [[x0, yTop], [x0, yCorner], [xEnd, yCorner]];
    this.len1 = yCorner - yTop;
    this.len = this.len1 + (xEnd - x0);
    const [a, b, c] = this.pts;
    $('lockSvg').setAttribute('viewBox', `0 0 ${w} ${h}`);
    $('lockPath').setAttribute('d', `M${a} L${b} L${c}`);
    const hint = $('lockHint');
    hint.style.left = `${x0 + 44}px`;
    hint.style.top = `${yCorner - 64}px`;
    this.setProgress(0);
  },

  pointAt(p) {
    const [a, b] = this.pts;
    return p <= this.len1 ? [a[0], a[1] + p] : [b[0] + (p - this.len1), b[1]];
  },

  // Closest point of the L to (x, y): { p, dist }
  project(x, y) {
    const [a, b, c] = this.pts;
    const y1 = clamp(y, a[1], b[1]), x2 = clamp(x, b[0], c[0]);
    const d1 = Math.hypot(x - a[0], y - y1), d2 = Math.hypot(x - x2, y - b[1]);
    return d1 <= d2 ? { p: y1 - a[1], dist: d1 } : { p: this.len1 + (x2 - b[0]), dist: d2 };
  },

  setProgress(p) {
    this.progress = p;
    const [x, y] = this.pointAt(p);
    const knob = $('lockKnob');
    knob.style.transform = `translate(${x - 30}px, ${y - 30}px)`;
    const [a, b] = this.pts;
    $('lockDone').setAttribute('d', p > 0 ? (p <= this.len1 ? `M${a} L${x},${y}` : `M${a} L${b} L${x},${y}`) : '');
  },

  snapBack() {
    this.dragging = false;
    $('lockKnob').classList.add('back');
    this.setProgress(0);
    setTimeout(() => $('lockKnob').classList.remove('back'), 300);
  },

  lock() {
    closeSheet();
    this.on = true;
    $('lock').hidden = false;
    this.layout();
    try { localStorage.setItem(LS_LOCKED, '1'); } catch (e) {}
  },

  unlock() {
    this.on = false;
    this.dragging = false;
    $('lock').hidden = true;
    try { localStorage.removeItem(LS_LOCKED); } catch (e) {}
    toast('Unlocked', '', 'ok', 1500);
  },

  bind() {
    const el = $('lock'), knob = $('lockKnob');
    // Swallow every touch so nothing underneath reacts, and iOS doesn't scroll or zoom
    for (const type of ['touchstart', 'touchmove', 'touchend', 'gesturestart', 'contextmenu']) {
      el.addEventListener(type, (e) => e.preventDefault(), { passive: false });
    }
    el.addEventListener('pointerdown', (e) => {
      const [kx, ky] = this.pointAt(this.progress);
      if (Math.hypot(e.clientX - kx, e.clientY - ky) > 44) {
        // Touched somewhere else: show where to slide
        el.classList.remove('nudge'); void el.offsetWidth; el.classList.add('nudge');
        return;
      }
      this.dragging = true;
      knob.classList.add('held');
      try { el.setPointerCapture(e.pointerId); } catch (err) {}
    });
    el.addEventListener('pointermove', (e) => {
      if (!this.dragging) return;
      const { p, dist } = this.project(e.clientX, e.clientY);
      // Must stay on the track and move continuously along it
      if (dist > 60 || Math.abs(p - this.progress) > 120) { knob.classList.remove('held'); this.snapBack(); return; }
      this.setProgress(p);
    });
    const end = () => {
      if (!this.dragging) return;
      knob.classList.remove('held');
      if (this.progress >= this.len - 16) this.unlock();
      else this.snapBack();
    };
    el.addEventListener('pointerup', end);
    el.addEventListener('pointercancel', () => { knob.classList.remove('held'); this.snapBack(); });
    window.addEventListener('resize', () => { if (this.on) this.layout(); });
  },
};

/* ---------------------------------------------------------
   Boot
   --------------------------------------------------------- */
function bindUi() {
  $('btnRide').addEventListener('click', () => (riding ? stopRide() : startRide()));
  armed($('btnTripReset'), 'Tap again', resetTrip);
  armed($('btnRefuel'), 'Confirm paid?', refuel);
  armed($('btnOil'), 'Confirm?', oilChanged);
  armed($('btnReset'), 'Tap again to erase all', factoryReset);
  armed($('btnAddKm'), 'Confirm?', addManualKm);

  $('btnLock').addEventListener('click', () => Lock.lock());
  Lock.bind();
  $('btnSettings').addEventListener('click', openSheet);
  $('btnCloseSheet').addEventListener('click', closeSheet);
  $('sheetBackdrop').addEventListener('click', closeSheet);
  document.querySelectorAll('.tab').forEach((tab) => tab.addEventListener('click', () => {
    document.querySelectorAll('.tab').forEach((t) => t.classList.toggle('active', t === tab));
    document.querySelectorAll('.sheet-body').forEach((p) => { p.hidden = p.dataset.panel !== tab.dataset.tab; });
    if (tab.dataset.tab === 'history') renderHistory();
  }));

  for (const id of Object.keys(numFields)) $(id).addEventListener('change', () => onNumberChange(id));
  for (const [id, key] of Object.entries(boolFields)) {
    $(id).addEventListener('change', () => {
      refreshFromStorage();
      state.settings[key] = $(id).checked;
      if (key === 'sim' && riding) { stopRide(); }
      if (key === 'wake') state.settings.wake && riding ? requestWakeLock() : releaseWakeLock();
      if (key === 'sound' && state.settings.sound) unlockAudio();
      saveNow();
      renderRideButton();
    });
  }
  $('setSimMul').addEventListener('change', () => {
    refreshFromStorage();
    state.settings.simMul = Number($('setSimMul').value);
    if (riding && state.settings.sim) setGps('sim', `SIM ×${state.settings.simMul}`);
    saveNow();
  });
  $('btnNotif').addEventListener('click', () => {
    if ('Notification' in window && Notification.permission === 'granted') notify('Test notification', 'Reminders are working.', 'ok', 'test');
    else enableNotifications();
  });
  $('btnExport').addEventListener('click', exportBackup);
  $('fileImport').addEventListener('change', (e) => {
    const f = e.target.files[0];
    if (f) importBackup(f);
    e.target.value = '';
  });

  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'hidden') {
      saveNow();
    } else {
      refreshFromStorage();
      if (riding) requestWakeLock();
      audioCtx?.resume?.();
    }
  });
  window.addEventListener('pagehide', () => { persist(); });
  window.addEventListener('pageshow', () => refreshFromStorage());
  // Another open copy of the app saved
  window.addEventListener('storage', (e) => { if (e.key === LS_KEY) refreshFromStorage(); });
}

function tick() {
  const now = new Date();
  $('clock').textContent = now.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });
  if (riding && !state.settings.sim && Date.now() - lastFixAt > GPS.staleMs && speedKmh > 0) setSpeed(0, true);
  render();
}

async function init() {
  buildGauge();

  // Load the saved data before anything can save or count km: saving the defaults
  // first would overwrite the real odometer (that's how it fell back to 10 820 km)
  await Store.open();
  const saved = await Store.loadState();
  ready = true;
  if (saved) { state = saved; syncedAt = saved.updatedAt || 0; }
  else await saveNow(true);
  bindUi();
  try { if (localStorage.getItem(LS_LOCKED)) Lock.lock(); } catch (e) {}

  let persisted = false;
  try { persisted = await navigator.storage?.persist?.(); } catch (e) {}
  $('storageInfo').textContent = `${Store.db ? 'IndexedDB' : 'localStorage'}${persisted ? ' · persistent' : ''}`;

  render();
  renderSpeed();
  renderRideButton();
  tick();
  setInterval(tick, 1000);

  if ('serviceWorker' in navigator && location.protocol !== 'file:') {
    navigator.serviceWorker.register('sw.js').catch((e) => console.warn('SW', e));
  }
}

init();
