'use strict';

// ---- Settings you might want to change ----
const DEFAULT_RATE = 3000; // new projects start at $30.00/hr (stored in cents)
const CURRENCY = 'USD';
// Billing rounds the month's exact total UP to the next full hour (4h 10m bills as 5 h).
// The work log always shows the exact times.
const BILL_ROUND_MINUTES = 60;
const COLORS = ['#E07A5F', '#3D8B7D', '#E3B04B', '#6A8FC7', '#A26EA1', '#8DB596', '#E89AAE', '#1C1C1E'];
const PHOTO_MAX_PX = 1600; // photos are shrunk to this size so the phone doesn't fill up

const STORE_KEY = 'timesheet.v1';

const $ = sel => document.querySelector(sel);
const uid = () => Date.now().toString(36) + Math.random().toString(36).slice(2, 7);
const esc = s => String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const money = new Intl.NumberFormat(undefined, { style: 'currency', currency: CURRENCY });
const fmtMoney = cents => money.format(cents / 100);

// ---- Time helpers ----
const MIN = 60000, HOUR = 3600000;
const fmtTime = ts => new Date(ts).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
const sameDay = (a, b) => new Date(a).toDateString() === new Date(b).toDateString();
const pad = n => String(n).padStart(2, '0');
// "6h 58m" / "45m"
function dur(ms) {
  const m = Math.floor(Math.max(0, ms) / MIN);
  return m >= 60 ? `${Math.floor(m / 60)}h ${m % 60}m` : `${m}m`;
}
// "01:23:45"
function hms(ms) {
  const s = Math.floor(Math.max(0, ms) / 1000);
  return `${pad(Math.floor(s / 3600))}:${pad(Math.floor(s / 60) % 60)}:${pad(s % 60)}`;
}
const billedHours = ms => Math.ceil(Math.floor(ms / MIN) / BILL_ROUND_MINUTES) * BILL_ROUND_MINUTES / 60;

const breakTotal = (breaks, until) => breaks.reduce((s, b) => s + ((b.end ?? until) - b.start), 0);
const worked = e => Math.max(0, e.end - e.start - (e.breakMs || 0));

function thisMonth() { const d = new Date(); return { y: d.getFullYear(), m: d.getMonth() }; }
const sameMonth = (a, b) => a.y === b.y && a.m === b.m;
const monthOf = ts => { const d = new Date(ts); return { y: d.getFullYear(), m: d.getMonth() }; };
const monthName = (mo, opts = { month: 'long', year: 'numeric' }) => new Date(mo.y, mo.m, 1).toLocaleDateString(undefined, opts);

// ---- Data ----
// Entries store exact start/stop timestamps plus total break time. The running timer lives in db.active
// as timestamps too, so it keeps counting even if the app is closed or the phone restarts.
let db = load();

function load() {
  try {
    const d = JSON.parse(localStorage.getItem(STORE_KEY));
    if (d && Array.isArray(d.projects) && Array.isArray(d.entries)) return { active: null, ...d };
  } catch {}
  return { projects: [], entries: [], active: null };
}
function save() {
  try { localStorage.setItem(STORE_KEY, JSON.stringify(db)); }
  catch { toast('Could not save', 'Storage is full or unavailable.'); }
}
const projOf = id => db.projects.find(p => p.id === id);
const entriesOf = (projectId, month) => db.entries
  .filter(e => e.projectId === projectId && (!month || sameMonth(monthOf(e.start), month)));
const totalOf = list => list.reduce((s, e) => s + worked(e), 0);

// ---- Photos (IndexedDB: too big for localStorage) ----
let idbConn;
function photoDB() {
  return idbConn ||= new Promise((resolve, reject) => {
    const r = indexedDB.open('timesheet-photos', 1);
    r.onupgradeneeded = () => r.result.createObjectStore('photos');
    r.onsuccess = () => resolve(r.result);
    r.onerror = () => reject(r.error);
  });
}
async function idb(mode, fn) {
  const d = await photoDB();
  return new Promise((resolve, reject) => {
    const tx = d.transaction('photos', mode);
    const req = fn(tx.objectStore('photos'));
    tx.oncomplete = () => resolve(req?.result);
    tx.onerror = () => reject(tx.error);
  });
}
const putPhoto = (id, blob) => idb('readwrite', s => s.put(blob, id));
const getPhoto = id => idb('readonly', s => s.get(id));
const photoUrls = new Map();
async function deletePhotos(ids) {
  for (const id of ids) {
    try { await idb('readwrite', s => s.delete(id)); } catch {}
    if (photoUrls.has(id)) { URL.revokeObjectURL(photoUrls.get(id)); photoUrls.delete(id); }
  }
}
async function photoUrl(id) {
  if (!photoUrls.has(id)) {
    const blob = await getPhoto(id).catch(() => null);
    photoUrls.set(id, blob ? URL.createObjectURL(blob) : '');
  }
  return photoUrls.get(id);
}
// Fill in <img data-photo="id"> once the photo is read from storage
function hydrate(root) {
  root.querySelectorAll('img[data-photo]').forEach(async img => {
    const url = await photoUrl(img.dataset.photo);
    if (url) img.src = url;
  });
}
// Shrink to PHOTO_MAX_PX and re-encode as JPEG
async function shrink(file) {
  const url = URL.createObjectURL(file);
  try {
    const img = new Image();
    img.src = url;
    await img.decode();
    const k = Math.min(1, PHOTO_MAX_PX / Math.max(img.naturalWidth, img.naturalHeight));
    const c = document.createElement('canvas');
    c.width = Math.round(img.naturalWidth * k);
    c.height = Math.round(img.naturalHeight * k);
    c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
    return await new Promise(r => c.toBlob(r, 'image/jpeg', 0.82)) || file;
  } catch {
    return file;
  } finally {
    URL.revokeObjectURL(url);
  }
}

// ---- Badges / chips ----
const dot = (color, size = '') => `<span class="badge ${size}" style="--c:${color}"><span class="dot"></span></span>`;
const probe = document.createElement('span');
function textOn(color) {
  probe.style.color = color;
  document.body.appendChild(probe);
  const [r, g, b] = getComputedStyle(probe).color.match(/[\d.]+/g).map(Number)
    .map(v => { v /= 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; });
  probe.remove();
  const lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  return 1.05 / (lum + 0.05) >= 2.8 ? '#FFFFFF' : '#1C1C1E';
}
function projectChips(selected, withAdd) {
  return db.projects.map(p => `<button type="button" class="chip${p.id === selected ? ' on' : ''}" data-proj="${p.id}"
      style="--c:${p.color};--on:${textOn(p.color)}">${dot(p.color, 'sm')}<span class="truncate">${esc(p.name)}</span></button>`).join('')
    + (withAdd ? '<button type="button" class="chip add" data-new-proj>+ New project</button>' : '');
}

// ---- Rendering ----
let page = 'home';      // 'home' | 'project'
let openProjectId = null;
let view = thisMonth(); // month shown in the project log

function render() {
  if (page === 'project' && !projOf(openProjectId)) page = 'home';
  $('#home').hidden = page !== 'home';
  $('#projectView').hidden = page !== 'project';
  if (page === 'home') renderHome(); else renderProject();
  renderDock();
}

function renderHome() {
  const now = thisMonth();
  const month = db.entries.filter(e => sameMonth(monthOf(e.start), now));
  const projCount = new Set(month.map(e => e.projectId)).size;
  $('#homeMonth').textContent = `Worked in ${monthName(now, { month: 'long' })}`;
  $('#homeTotal').textContent = dur(totalOf(month));
  $('#homeSub').textContent = month.length
    ? `${month.length} ${month.length === 1 ? 'session' : 'sessions'} across ${projCount} ${projCount === 1 ? 'project' : 'projects'}`
    : 'No sessions yet this month';

  const list = $('#projList');
  if (!db.projects.length) {
    list.innerHTML = '<p class="empty">No projects yet.<br>Tap <b>+ New</b> to create your first one.</p>';
    return;
  }
  list.innerHTML = db.projects.map(p => {
    const t = totalOf(entriesOf(p.id, now));
    const running = db.active?.projectId === p.id;
    const meta = [running ? '<span class="running-dot">●</span> Timer running' : '', esc(p.client || ''), `${fmtMoney(p.rate)}/hr`]
      .filter(Boolean).join(' · ');
    return `<button class="row" data-open-proj="${p.id}">
      ${dot(p.color)}
      <span class="row-main"><span class="row-name truncate">${esc(p.name)}</span><span class="row-meta truncate">${meta}</span></span>
      <span class="row-amt num">${dur(t)}<small>this month</small></span>
    </button>`;
  }).join('');
}

const CAMERA_ICON = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M4 8.5A1.5 1.5 0 0 1 5.5 7h2l1.5-2h6l1.5 2h2A1.5 1.5 0 0 1 20 8.5v9a1.5 1.5 0 0 1-1.5 1.5h-13A1.5 1.5 0 0 1 4 17.5z"/><circle cx="12" cy="13" r="3.5"/></svg>';
const LIBRARY_ICON = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><rect x="4" y="5" width="16" height="14" rx="2"/><circle cx="9" cy="10" r="1.5"/><path d="M20 15l-4.5-4.5L8 18"/></svg>';
const X_ICON = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M7 7l10 10M17 7L7 17"/></svg>';

function dayLabel(ts) {
  const today = new Date();
  const yest = new Date(today.getFullYear(), today.getMonth(), today.getDate() - 1);
  if (sameDay(ts, today)) return 'Today';
  if (sameDay(ts, yest)) return 'Yesterday';
  return new Date(ts).toLocaleDateString(undefined, { weekday: 'long', month: 'short', day: 'numeric' });
}

function entryCard(e) {
  const n = e.photos.length;
  const shown = e.photos.slice(0, 4);
  const photos = n
    ? `<span class="entry-photos n${Math.min(n, 4)}">${shown.map((id, i) => `<span class="ph" data-view="${e.id}" data-i="${i}">
        <img data-photo="${id}" alt="Work photo ${i + 1}">${i === 3 && n > 4 ? `<span class="more">+${n - 4}</span>` : ''}</span>`).join('')}</span>`
    : `<span class="entry-photos none" aria-label="No photos">${CAMERA_ICON}</span>`;
  const nextDay = !sameDay(e.start, e.end) ? ' <span>+1d</span>' : '';
  return `<button class="entry" data-entry="${e.id}">
    <span class="entry-top">
      <span class="entry-left">
        <span>
          <span class="entry-times num">${fmtTime(e.start)} <span>→</span> ${fmtTime(e.end)}${nextDay}</span>
          ${e.breakMs ? `<span class="entry-tag num">${dur(e.breakMs)} break</span>` : ''}
        </span>
        <span class="entry-total num"><small>Total worked</small>${dur(worked(e))}</span>
      </span>
      ${photos}
    </span>
    ${e.description ? `<span class="entry-desc">${esc(e.description)}</span>` : '<span class="entry-desc muted">No description</span>'}
  </button>`;
}

function renderProject(animate = false) {
  const p = projOf(openProjectId);
  $('#projTitle').textContent = p.name;
  $('#monthLabel').textContent = monthName(view);
  const list = entriesOf(p.id, view);
  const total = totalOf(list);
  $('#projTotal').textContent = dur(total);
  const hours = billedHours(total);
  $('#projSub').innerHTML = list.length
    ? `${list.length} ${list.length === 1 ? 'session' : 'sessions'} · Bills as <b>${hours} h × ${fmtMoney(p.rate)} = ${fmtMoney(hours * p.rate)}</b>`
    : `${fmtMoney(p.rate)}/hr`;

  // Group by the day each session started: newest day first, sessions in order within a day
  const days = new Map();
  for (const e of [...list].sort((a, b) => a.start - b.start)) {
    const k = new Date(e.start).toDateString();
    if (!days.has(k)) days.set(k, []);
    days.get(k).push(e);
  }
  const log = $('#logList');
  log.innerHTML = days.size
    ? [...days.values()].reverse().map(es => `<div class="day">
        <div class="day-head"><strong>${dayLabel(es[0].start)}</strong><span class="num">${dur(totalOf(es))}</span></div>
        <div class="entries">${es.map(entryCard).join('')}</div>
      </div>`).join('')
    : `<div class="card"><p class="empty">No work logged in ${esc(monthName(view, { month: 'long' }))}.</p></div>`;
  hydrate(log);
  if (animate) {
    const c = $('#projContent');
    c.classList.remove('switch'); void c.offsetWidth; c.classList.add('switch');
  }
}

function renderDock() {
  const btn = $('#dockBtn'), a = db.active;
  btn.classList.remove('paused');
  btn.style.removeProperty('--btn');
  if (!a) { btn.textContent = 'Start timer'; return; }
  const p = projOf(a.projectId);
  const name = p ? esc(p.name) : 'Timer';
  if (a.end) { btn.innerHTML = `Finish entry · ${name}`; return; }
  btn.classList.toggle('paused', isPaused());
  btn.innerHTML = `<span class="live"></span><span class="num">${hms(elapsed())}</span><span class="truncate">· ${name}</span>`;
}

// ---- Sheets ----
let onSheetClose = null;
function openSheet(id) {
  document.querySelectorAll('.sheet.open').forEach(s => s.classList.remove('open'));
  $(id).classList.add('open');
  $('#scrim').classList.add('open');
  document.body.classList.add('locked');
}
function closeSheets() {
  document.activeElement?.blur?.();
  document.querySelectorAll('.sheet.open').forEach(s => s.classList.remove('open'));
  $('#scrim').classList.remove('open');
  if (!$('#timer').classList.contains('open')) document.body.classList.remove('locked');
  const cb = onSheetClose;
  onSheetClose = null;
  cb?.();
}
if (window.visualViewport) {
  const vv = window.visualViewport;
  const sync = () => {
    const kb = Math.max(0, window.innerHeight - vv.height - vv.offsetTop);
    document.documentElement.style.setProperty('--kb', kb + 'px');
    document.documentElement.style.setProperty('--vvh', vv.height + 'px');
  };
  vv.addEventListener('resize', sync);
  vv.addEventListener('scroll', sync);
}
function shake(el) { el.classList.remove('shake'); void el.offsetWidth; el.classList.add('shake'); }
function grow(t) { t.style.height = 'auto'; t.style.height = t.scrollHeight + 2 + 'px'; }

// ---- Timer ----
let draft = { projectId: null, description: '' }; // what's picked before Start is pressed
const isPaused = () => { const b = db.active?.breaks.at(-1); return !!b && b.end == null; };
function elapsed(now = Date.now()) {
  const a = db.active;
  if (!a) return 0;
  const until = a.end ?? now;
  return Math.max(0, until - a.start - breakTotal(a.breaks, until));
}

function openTimer(projectId) {
  if (!db.active) {
    draft.projectId = projectId ?? (projOf(draft.projectId) ? draft.projectId : db.projects.at(-1)?.id ?? null);
  }
  renderTimer();
  $('#timer').classList.add('open');
  $('#timer').scrollTop = 0;
  document.body.classList.add('locked');
  tick();
}
function closeTimer() {
  document.activeElement?.blur?.();
  $('#timer').classList.remove('open');
  document.body.classList.remove('locked');
  render();
}

function renderTimer() {
  const a = db.active;
  const finishing = !!a?.end;
  $('#timer').classList.toggle('focus', !!a && !finishing);
  $('#timerPanel').hidden = finishing;
  $('#finishPanel').hidden = !finishing;
  if (finishing) return renderFinish();

  $('#timerProjects').innerHTML = projectChips(a ? a.projectId : draft.projectId, true);
  const desc = $('#timerDesc');
  desc.value = a ? a.description : draft.description;
  requestAnimationFrame(() => grow(desc));

  const actions = $('#timerActions');
  if (!a) {
    actions.className = 'timer-actions';
    actions.innerHTML = '<button class="primary-btn go-btn" id="startBtn">Start</button>';
  } else {
    actions.className = 'timer-actions two';
    actions.innerHTML = `<button class="secondary-btn" id="pauseBtn" style="height:54px;border-radius:27px">${isPaused() ? 'Resume' : 'Pause'}</button>
      <button class="primary-btn stop-btn" id="stopBtn">Stop</button>`;
  }
  updateElapsed();
}

function updateClock() {
  const now = new Date();
  const parts = new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' }).formatToParts(now);
  const period = parts.find(p => p.type === 'dayPeriod')?.value;
  const time = parts.filter(p => p.type !== 'dayPeriod').map(p => p.value).join('').trim();
  $('#clockTime').innerHTML = `${esc(time)}${period ? `<small>${esc(period)}</small>` : ''}`;
  $('#clockDate').textContent = now.toLocaleDateString(undefined, { weekday: 'long', month: 'long', day: 'numeric' });
}

function updateElapsed() {
  const a = db.active, el = $('#elapsed'), meta = $('#elapsedMeta');
  if (!a) {
    el.textContent = '00:00:00';
    el.className = 'elapsed num idle';
    meta.textContent = db.projects.length ? 'Pick a project, then tap Start' : 'Create a project to get started';
    return;
  }
  const paused = isPaused();
  el.textContent = hms(elapsed());
  el.className = `elapsed num${paused ? ' paused' : ''}`;
  const brk = breakTotal(a.breaks, Date.now());
  const bits = [paused ? `<b>Paused</b> since ${fmtTime(a.breaks.at(-1).start)}` : `Started <b>${fmtTime(a.start)}</b>`];
  if (paused) bits.push(`started ${fmtTime(a.start)}`);
  if (brk >= MIN) bits.push(`${dur(brk)} break`);
  meta.innerHTML = bits.join(' · ');
}

function startTimer() {
  if (!projOf(draft.projectId)) {
    shake($('#timerProjects'));
    toast('Pick a project first', db.projects.length ? '' : 'Tap + New project to create one.');
    return;
  }
  db.active = { projectId: draft.projectId, description: $('#timerDesc').value.trim(), start: Date.now(), breaks: [], photos: [] };
  draft = { projectId: draft.projectId, description: '' };
  save();
  renderTimer();
  renderDock();
}

function togglePause() {
  const a = db.active;
  if (!a) return;
  const now = Date.now();
  if (isPaused()) a.breaks.at(-1).end = now;
  else a.breaks.push({ start: now, end: null });
  save();
  renderTimer();
  renderDock();
}

async function stopTimer() {
  const a = db.active;
  if (!a) return;
  a.description = $('#timerDesc').value.trim();
  // Stopping while paused ends the session when the pause began
  if (isPaused()) a.end = a.breaks.pop().start;
  else a.end = Date.now();
  save();
  renderTimer();
  renderDock();
  $('#timer').scrollTop = 0;
}

function resumeTimer() {
  const a = db.active;
  if (!a?.end) return;
  // The gap between Stop and Resume counts as a break
  a.breaks.push({ start: a.end, end: Date.now() });
  delete a.end;
  save();
  renderTimer();
  renderDock();
}

function renderFinish() {
  const a = db.active, p = projOf(a.projectId);
  $('#doneProj').innerHTML = p ? `${dot(p.color, 'sm')}${esc(p.name)}` : '';
  const ms = elapsed();
  $('#doneTotal').textContent = ms < MIN ? `${Math.floor(ms / 1000)}s` : dur(ms);
  $('#doneTimes').innerHTML = `${fmtTime(a.start)} <span>→</span> ${fmtTime(a.end)}`;
  const brk = breakTotal(a.breaks, a.end);
  $('#doneBreak').textContent = brk >= MIN ? `${dur(brk)} break not counted` : '';
  const desc = $('#doneDesc');
  desc.value = a.description;
  requestAnimationFrame(() => grow(desc));
  renderPhotoGrid($('#donePhotos'), a.photos);
  $('#saveEntryBtn').textContent = a.photos.length ? 'Save to log' : 'Skip photo & save';
}

function saveActive() {
  const a = db.active;
  if (!a?.end) return;
  const entry = {
    id: uid(),
    projectId: a.projectId,
    start: a.start,
    end: a.end,
    breakMs: breakTotal(a.breaks, a.end),
    description: a.description.trim(),
    photos: a.photos,
  };
  db.entries.push(entry);
  db.active = null;
  save();
  closeTimer();
  // Show the entry where it landed
  openProject(entry.projectId, monthOf(entry.start));
  toast('Saved to work log', `${dur(worked(entry))} on ${projOf(entry.projectId)?.name ?? 'project'}`);
}

// ---- Photo grids (finish screen + entry sheet) ----
let photoTarget = null; // array that new photos are added to
let photoRerender = null;

function renderPhotoGrid(el, ids) {
  el.innerHTML = (ids.length ? `<div class="photo-grid">${ids.map((id, i) => `<div class="tile" data-tile="${i}">
      <img data-photo="${id}" alt="Photo ${i + 1}">
      <button type="button" class="x" data-remove="${i}" aria-label="Remove photo">${X_ICON}</button>
    </div>`).join('')}</div>` : '')
    + `<div class="photo-actions">
      <button type="button" class="add" data-pick="camera">${CAMERA_ICON}Take photo</button>
      <button type="button" class="add" data-pick="library">${LIBRARY_ICON}Library</button>
    </div>`;
  hydrate(el);
}

function wirePhotoGrid(el, getIds, onChange) {
  el.addEventListener('click', e => {
    const pick = e.target.closest('[data-pick]');
    if (pick) {
      photoTarget = getIds();
      photoRerender = onChange;
      $(pick.dataset.pick === 'camera' ? '#cameraInput' : '#libraryInput').click();
      return;
    }
    const rm = e.target.closest('[data-remove]');
    if (rm) {
      const ids = getIds();
      const [gone] = ids.splice(+rm.dataset.remove, 1);
      onChange({ removed: gone });
      return;
    }
    const tile = e.target.closest('[data-tile]');
    if (tile) openViewer(getIds(), +tile.dataset.tile);
  });
}

async function addPhotos(files) {
  if (!files.length || !photoTarget) return;
  const target = photoTarget, rerender = photoRerender;
  for (const f of files) {
    try {
      const id = uid();
      await putPhoto(id, await shrink(f));
      target.push(id);
      rerender({ added: id });
    } catch {
      toast('Could not add photo', 'Storage may be full.');
    }
  }
}
for (const sel of ['#cameraInput', '#libraryInput']) {
  $(sel).addEventListener('change', e => {
    const files = [...e.target.files];
    e.target.value = '';
    addPhotos(files);
  });
}

wirePhotoGrid($('#donePhotos'), () => db.active.photos, ({ removed } = {}) => {
  if (removed) deletePhotos([removed]);
  save();
  renderFinish();
});

// ---- Photo viewer ----
let viewerIds = [], viewerIdx = 0;
async function openViewer(ids, i) {
  viewerIds = ids; viewerIdx = i;
  await showViewerPhoto();
  $('#viewer').classList.add('open');
}
async function showViewerPhoto() {
  $('#viewerImg').src = await photoUrl(viewerIds[viewerIdx]);
  $('#viewerCount').textContent = viewerIds.length > 1 ? `${viewerIdx + 1} / ${viewerIds.length}` : '';
}
$('#viewerImg').addEventListener('click', () => {
  if (viewerIds.length < 2) return;
  viewerIdx = (viewerIdx + 1) % viewerIds.length;
  showViewerPhoto();
});
$('#viewerClose').addEventListener('click', () => $('#viewer').classList.remove('open'));
$('#viewer').addEventListener('click', e => { if (e.target.id === 'viewer') $('#viewer').classList.remove('open'); });

// ---- Project sheet ----
let editingProj = null, projColor = COLORS[0], afterProjectSave = null;

function openProjectSheet(p, after = null) {
  editingProj = p;
  afterProjectSave = after;
  $('#projHeading').textContent = p ? 'Edit project' : 'New project';
  $('#projName').value = p?.name ?? '';
  $('#projClient').value = p?.client ?? '';
  $('#projRate').value = ((p?.rate ?? DEFAULT_RATE) / 100).toFixed(2);
  projColor = p?.color ?? COLORS[db.projects.length % COLORS.length];
  renderSwatches();
  $('#projDelete').hidden = !p;
  openSheet('#projectSheet');
  if (!p) setTimeout(() => $('#projName').focus(), 350);
}
function renderSwatches() {
  $('#projColors').innerHTML = COLORS.map(c =>
    `<button type="button" class="swatch${c === projColor ? ' on' : ''}" data-color="${c}" style="--c:${c}" aria-label="Color"></button>`).join('');
}
$('#projColors').addEventListener('click', e => {
  const s = e.target.closest('[data-color]');
  if (!s) return;
  projColor = s.dataset.color;
  renderSwatches();
});

function parseMoney(v) {
  let s = String(v).replace(/[^\d.,]/g, '');
  s = s.includes('.') ? s.replace(/,/g, '') : s.replace(',', '.');
  const n = parseFloat(s);
  return Number.isFinite(n) ? Math.round(n * 100) : NaN;
}

$('#projectSheet').addEventListener('submit', e => {
  e.preventDefault();
  const name = $('#projName').value.trim();
  if (!name) { shake($('#projName')); $('#projName').focus(); return; }
  const rate = $('#projRate').value.trim() === '' ? DEFAULT_RATE : parseMoney($('#projRate').value);
  if (!Number.isFinite(rate) || rate < 0) { shake($('#projRate').closest('.inline-field')); return; }
  const fields = { name, client: $('#projClient').value.trim(), rate, color: projColor };
  let p = editingProj;
  if (p) Object.assign(p, fields);
  else { p = { id: uid(), createdAt: Date.now(), ...fields }; db.projects.push(p); }
  save();
  const after = afterProjectSave;
  afterProjectSave = null;
  closeSheets();
  after?.(p);
  render();
});

$('#projDelete').addEventListener('click', async () => {
  const p = editingProj;
  if (!p) return;
  if (db.active?.projectId === p.id) {
    toast('Timer is running', 'Stop the timer on this project before deleting it.');
    return;
  }
  const list = entriesOf(p.id);
  const ok = await ask({
    title: `Delete "${p.name}"?`,
    message: list.length
      ? `This also deletes its ${list.length} logged ${list.length === 1 ? 'session' : 'sessions'} and their photos. This can't be undone.`
      : 'This project has no logged work.',
  });
  if (!ok) return;
  await deletePhotos(list.flatMap(e => e.photos));
  db.entries = db.entries.filter(e => e.projectId !== p.id);
  db.projects = db.projects.filter(x => x.id !== p.id);
  save();
  closeSheets();
  page = 'home';
  render();
});

// ---- Entry sheet (edit a logged session, or add one by hand) ----
let editingEntry = null, entryForm = null;
const toInput = ts => { const d = new Date(ts); return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`; };
const fromInput = v => { const t = new Date(v).getTime(); return Number.isFinite(t) ? t : NaN; };

function openEntrySheet(entry) {
  editingEntry = entry;
  const now = Date.now();
  const end = entry?.end ?? Math.floor(now / (5 * MIN)) * 5 * MIN;
  entryForm = {
    projectId: entry?.projectId ?? openProjectId,
    photos: [...(entry?.photos ?? [])],
    added: [],
    removed: [],
  };
  $('#entryHeading').textContent = entry ? 'Edit entry' : 'Add entry';
  $('#entryProjects').innerHTML = projectChips(entryForm.projectId, false);
  $('#entryStart').value = toInput(entry?.start ?? end - HOUR);
  $('#entryEnd').value = toInput(end);
  $('#entryBreak').value = entry?.breakMs ? Math.round(entry.breakMs / MIN) : '';
  $('#entryDesc').value = entry?.description ?? '';
  $('#entryDelete').hidden = !entry;
  renderPhotoGrid($('#entryPhotos'), entryForm.photos);
  updateEntryWorked();
  openSheet('#entrySheet');
  requestAnimationFrame(() => grow($('#entryDesc')));
  // Closing without saving throws away photos added in this sheet
  onSheetClose = () => {
    if (entryForm) deletePhotos(entryForm.added);
    entryForm = null;
  };
}

function readEntryTimes() {
  const start = fromInput($('#entryStart').value);
  const end = fromInput($('#entryEnd').value);
  const breakMs = (parseInt($('#entryBreak').value, 10) || 0) * MIN;
  return { start, end, breakMs };
}
function updateEntryWorked() {
  const { start, end, breakMs } = readEntryTimes();
  const out = $('#entryWorked');
  if (!Number.isFinite(start) || !Number.isFinite(end)) out.textContent = 'Enter a start and stop time';
  else if (end <= start) out.textContent = 'Stop time must be after the start time';
  else if (breakMs >= end - start) out.textContent = 'Breaks are longer than the session';
  else out.textContent = `${dur(end - start - breakMs)} worked`;
}
for (const id of ['#entryStart', '#entryEnd', '#entryBreak']) $(id).addEventListener('input', updateEntryWorked);
$('#entryDesc').addEventListener('input', e => grow(e.target));
$('#doneDesc').addEventListener('input', e => {
  grow(e.target);
  if (db.active) { db.active.description = e.target.value; save(); }
});
$('#timerDesc').addEventListener('input', e => {
  grow(e.target);
  if (db.active) { db.active.description = e.target.value; save(); }
  else draft.description = e.target.value;
});

$('#entryProjects').addEventListener('click', e => {
  const chip = e.target.closest('[data-proj]');
  if (!chip || !entryForm) return;
  entryForm.projectId = chip.dataset.proj;
  $('#entryProjects').innerHTML = projectChips(entryForm.projectId, false);
});

wirePhotoGrid($('#entryPhotos'), () => entryForm.photos, ({ added, removed } = {}) => {
  if (!entryForm) { if (added) deletePhotos([added]); return; } // sheet was closed while the photo saved
  if (added) entryForm.added.push(added);
  if (removed) {
    // Photos added in this sheet can go right away; existing ones only once the edit is saved
    if (entryForm.added.includes(removed)) { entryForm.added = entryForm.added.filter(x => x !== removed); deletePhotos([removed]); }
    else entryForm.removed.push(removed);
  }
  renderPhotoGrid($('#entryPhotos'), entryForm.photos);
});

$('#entrySheet').addEventListener('submit', e => {
  e.preventDefault();
  const { start, end, breakMs } = readEntryTimes();
  if (!Number.isFinite(start) || !Number.isFinite(end) || end <= start || breakMs >= end - start) {
    shake($('#entryWorked'));
    return;
  }
  const fields = {
    projectId: entryForm.projectId, start, end, breakMs,
    description: $('#entryDesc').value.trim(), photos: entryForm.photos,
  };
  if (editingEntry) Object.assign(editingEntry, fields);
  else db.entries.push({ id: uid(), ...fields });
  save();
  deletePhotos(entryForm.removed);
  entryForm = null; // keep the new photos
  closeSheets();
  if (page === 'project') {
    openProjectId = fields.projectId;
    view = monthOf(start);
  }
  render();
});

$('#entryDelete').addEventListener('click', async () => {
  if (!editingEntry) return;
  const ok = await ask({ title: 'Delete this entry?', message: `${dur(worked(editingEntry))} on ${dayLabel(editingEntry.start)}. Its photos are deleted too.` });
  if (!ok) return;
  db.entries = db.entries.filter(x => x !== editingEntry);
  save();
  deletePhotos([...editingEntry.photos, ...entryForm.added]);
  entryForm = null;
  closeSheets();
  render();
});

// ---- Toast + dialog ----
let toastTimer;
function toast(title, body = '') {
  const t = $('#toast');
  t.innerHTML = `<div><b>${esc(title)}</b>${body ? `<span>${esc(body)}</span>` : ''}</div>`;
  t.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => t.classList.remove('show'), 3400);
}
function ask({ title, message = '', ok = 'Delete', danger = true }) {
  return new Promise(resolve => {
    const wrap = $('#dialog'), okBtn = $('#dlgOk'), cancel = $('#dlgCancel');
    $('#dlgTitle').textContent = title;
    $('#dlgMsg').textContent = message;
    okBtn.textContent = ok;
    okBtn.classList.toggle('danger', danger);
    wrap.classList.add('open');
    const done = value => {
      wrap.classList.remove('open');
      okBtn.onclick = cancel.onclick = wrap.onclick = null;
      resolve(value);
    };
    okBtn.onclick = () => done(true);
    cancel.onclick = () => done(false);
    wrap.onclick = e => { if (e.target === wrap) done(false); };
  });
}

// ---- Backup ----
const blobToDataUrl = blob => new Promise((resolve, reject) => {
  const r = new FileReader();
  r.onload = () => resolve(r.result);
  r.onerror = () => reject(r.error);
  r.readAsDataURL(blob);
});

$('#exportBtn').addEventListener('click', async () => {
  const ids = [...db.entries.flatMap(e => e.photos), ...(db.active?.photos ?? [])];
  const photos = {};
  for (const id of ids) {
    const blob = await getPhoto(id).catch(() => null);
    if (blob) photos[id] = await blobToDataUrl(blob);
  }
  const name = `timesheet-backup-${new Date().toISOString().slice(0, 10)}.json`;
  const file = new File([JSON.stringify({ ...db, photos })], name, { type: 'application/json' });
  if (navigator.canShare?.({ files: [file] })) {
    try { await navigator.share({ files: [file] }); } catch {}
    return;
  }
  const a = document.createElement('a');
  a.href = URL.createObjectURL(file);
  a.download = name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
});

$('#importBtn').addEventListener('click', () => $('#importFile').click());
$('#importFile').addEventListener('change', async e => {
  const f = e.target.files[0];
  e.target.value = '';
  if (!f) return;
  try {
    const d = JSON.parse(await f.text());
    if (!Array.isArray(d.projects) || !Array.isArray(d.entries)) throw new Error();
    const ok = await ask({
      title: 'Restore backup?',
      message: `This replaces everything on this phone with the backup (${d.projects.length} projects, ${d.entries.length} sessions).`,
      ok: 'Restore',
    });
    if (!ok) return;
    await idb('readwrite', s => s.clear());
    photoUrls.forEach(u => u && URL.revokeObjectURL(u));
    photoUrls.clear();
    for (const [id, url] of Object.entries(d.photos || {})) {
      await putPhoto(id, await (await fetch(url)).blob());
    }
    db = { projects: d.projects, entries: d.entries, active: d.active ?? null };
    save();
    page = 'home';
    closeSheets();
    render();
    toast('Backup restored');
  } catch {
    toast('Import failed', 'That file is not a valid backup.');
  }
});

// ---- Wiring ----
function openProject(id, month = thisMonth()) {
  page = 'project';
  openProjectId = id;
  view = month;
  render();
  window.scrollTo(0, 0);
  renderProject(true);
}
function shiftMonth(delta) {
  const d = new Date(view.y, view.m + delta, 1);
  view = { y: d.getFullYear(), m: d.getMonth() };
  renderProject(true);
}

$('#projList').addEventListener('click', e => {
  const row = e.target.closest('[data-open-proj]');
  if (row) openProject(row.dataset.openProj);
});
$('#backBtn').addEventListener('click', () => { page = 'home'; render(); window.scrollTo(0, 0); });
$('#editProjBtn').addEventListener('click', () => openProjectSheet(projOf(openProjectId)));
$('#newProjBtn').addEventListener('click', () => openProjectSheet(null));
$('#prevMonth').addEventListener('click', () => shiftMonth(-1));
$('#nextMonth').addEventListener('click', () => shiftMonth(1));
$('#monthLabel').addEventListener('click', () => {
  if (sameMonth(view, thisMonth())) return;
  view = thisMonth();
  renderProject(true);
});
$('#addEntryBtn').addEventListener('click', () => openEntrySheet(null));
$('#logList').addEventListener('click', e => {
  const ph = e.target.closest('[data-view]');
  const entry = db.entries.find(x => x.id === (ph ? ph.dataset.view : e.target.closest('[data-entry]')?.dataset.entry));
  if (!entry) return;
  if (ph) openViewer(entry.photos, +ph.dataset.i);
  else openEntrySheet(entry);
});

$('#dockBtn').addEventListener('click', () => openTimer(page === 'project' ? openProjectId : undefined));
$('#settingsBtn').addEventListener('click', () => openSheet('#settingsSheet'));
$('#scrim').addEventListener('click', closeSheets);
document.querySelectorAll('[data-close]').forEach(b => b.addEventListener('click', closeSheets));

$('#timerClose').addEventListener('click', closeTimer);
$('#timerProjects').addEventListener('click', e => {
  if (e.target.closest('[data-new-proj]')) {
    openProjectSheet(null, p => {
      if (db.active && !db.active.end) { db.active.projectId = p.id; save(); }
      else draft.projectId = p.id;
      renderTimer();
    });
    return;
  }
  const chip = e.target.closest('[data-proj]');
  if (!chip) return;
  if (db.active) { db.active.projectId = chip.dataset.proj; save(); }
  else draft.projectId = chip.dataset.proj;
  $('#timerProjects').innerHTML = projectChips(chip.dataset.proj, true);
});
$('#timerActions').addEventListener('click', async e => {
  if (e.target.closest('#startBtn')) startTimer();
  else if (e.target.closest('#pauseBtn')) togglePause();
  else if (e.target.closest('#stopBtn')) {
    const ok = await ask({ title: 'Stop the timer?', message: `You've worked ${dur(elapsed())} so far.`, ok: 'Stop' });
    if (ok) stopTimer();
  }
});
$('#saveEntryBtn').addEventListener('click', saveActive);
$('#resumeBtn').addEventListener('click', resumeTimer);
$('#discardBtn').addEventListener('click', async () => {
  const a = db.active;
  if (!a?.end) return;
  const ok = await ask({ title: 'Discard this session?', message: `This session won't be saved to the log.${a.photos.length ? ' Its photos are deleted too.' : ''}`, ok: 'Discard' });
  if (!ok) return;
  deletePhotos(a.photos);
  db.active = null;
  save();
  closeTimer();
  toast('Session discarded');
});

// One clock for everything that counts
function tick() {
  if ($('#timer').classList.contains('open')) {
    updateClock();
    if (db.active && !db.active.end) updateElapsed();
  }
  if (db.active && !db.active.end) renderDock();
}
setInterval(tick, 1000);

document.addEventListener('visibilitychange', () => {
  if (document.visibilityState !== 'visible') return;
  render();
  tick();
});

if ('serviceWorker' in navigator && location.protocol !== 'file:') {
  navigator.serviceWorker.register('sw.js').catch(() => {});
}
navigator.storage?.persist?.().catch(() => {});

render();
// Reopening the app mid-session goes straight back to the timer
if (db.active) openTimer();
