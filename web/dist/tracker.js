(() => {
  const resName = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'sanctuary_crafting';
  const IMG_BASE = 'nui://ox_inventory/web/images/';
  const LS_PIN = 'sc_tracker_pin';
  const LS_MODE = 'sc_tracker_mode'; /* legacy — mapped via SanctuaryHud */
  const LS_POS = 'sc_tracker_pos'; /* legacy top/right */
  const LS_POS_XY = 'craftTrackerPosition'; /* {x, y} — required NUI key */
  const HUD = () => window.SanctuaryHud;
  const MODES = ['expanded', 'compact', 'minimal', 'hidden'];
  const DRAG_THRESHOLD = 6;
  const DEFAULT_POS = { top: 24, right: 24 };
  const EDGE = 8;
  const MIN_VISIBLE = 40;

  const root = document.getElementById('craft-tracker');
  if (!root) return;

  const els = {
    list: root.querySelector('#ct-list'),
    count: root.querySelector('#ct-count'),
    pin: root.querySelector('#ct-pin'),
    header: root.querySelector('#ct-header'),
    reduce: root.querySelector('#ct-reduce'),
    reduced: root.querySelector('#ct-reduced'),
    reducedCount: root.querySelector('#ct-reduced-count'),
    reducedPct: root.querySelector('#ct-reduced-pct'),
    waiting: root.querySelector('#ct-waiting'),
  };

  let config = {
    enabled: true,
    defaultPosition: { top: 24, right: 24 },
    defaultMode: 'expanded',
    autoShowOnStart: true,
    hideWithMenuIfUnpinned: true,
    showOnNewCraftIfHidden: true,
    persistPin: true,
    persistMode: true,
    persistPosition: true,
    allowDrag: true,
    completedLingerMs: 2000,
    autoRemoveCompleted: true,
    tickMs: 250,
    phases: {
      medical: ['Préparation', 'Assemblage', 'Stérilisation', 'Finalisation'],
      mechanical: ['Découpe', 'Assemblage', 'Calibrage', 'Finition'],
      cooking: ['Préparation', 'Cuisson', 'Conditionnement'],
      default: ['Préparation', 'Assemblage', 'Finition'],
    },
    sounds: { Enabled: true, OnStart: true, OnComplete: true, OnError: true },
    uiSounds: { Enabled: true, Volume: 0.35, Files: {} },
  };

  const jobs = new Map(); // craftId -> entry (+ local timing)
  let menuOpen = false;
  let pinned = false;
  let mode = 'expanded';
  let tickTimer = null;
  let audioCtx = null;
  let completing = new Set();
  let drag = null;
  let dragMoved = false;

  function post(name, data) {
    return fetch(`https://${resName}/${name}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(data || {}),
    }).then((r) => r.json()).catch(() => ({ ok: false }));
  }

  function lsGet(key, fallback) {
    try {
      const v = localStorage.getItem(key);
      return v == null ? fallback : v;
    } catch (_) {
      return fallback;
    }
  }

  function lsSet(key, value) {
    try { localStorage.setItem(key, value); } catch (_) { /* ignore */ }
  }

  function mergeConfig(cfg) {
    if (!cfg || typeof cfg !== 'object') return;
    config = { ...config, ...cfg };
    if (cfg.phases) config.phases = { ...config.phases, ...cfg.phases };
    if (cfg.sounds) config.sounds = { ...config.sounds, ...cfg.sounds };
    if (cfg.uiSounds) config.uiSounds = { ...config.uiSounds, ...cfg.uiSounds };
    if (cfg.defaultMode === 'normal') config.defaultMode = 'expanded';
    if (cfg.showOnNewCraftIfHidden == null) config.showOnNewCraftIfHidden = true;
  }

  function itemImageUrl(item) {
    if (!item) return '';
    return `${IMG_BASE}${encodeURIComponent(String(item))}.png`;
  }

  function bindItemImg(img, item, fallbackEl) {
    if (!img) return;
    const url = itemImageUrl(item);
    img.classList.remove('is-fallback');
    if (fallbackEl) fallbackEl.style.display = '';
    if (!url) {
      img.classList.add('is-fallback');
      img.removeAttribute('src');
      return;
    }
    img.onload = () => {
      if (fallbackEl) fallbackEl.style.display = 'none';
      img.classList.remove('is-fallback');
    };
    img.onerror = () => {
      img.classList.add('is-fallback');
      if (fallbackEl) fallbackEl.style.display = '';
    };
    img.src = url;
    img.alt = item || '';
  }

  function ensureAudio() {
    if (audioCtx) return audioCtx;
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return null;
    audioCtx = new AC();
    return audioCtx;
  }

  function beep(kind) {
    const snd = config.sounds || {};
    const ui = config.uiSounds || {};
    if (snd.Enabled === false || ui.Enabled === false) return;
    if (kind === 'start' && snd.OnStart === false) return;
    if (kind === 'complete' && snd.OnComplete === false) return;
    if (kind === 'error' && snd.OnError === false) return;

    const files = ui.Files || {};
    const map = { start: 'click', complete: 'success', error: 'error', click: 'click' };
    const fileKey = map[kind] || 'click';
    const path = files[fileKey];
    if (path) {
      try {
        const a = new Audio(path);
        a.volume = typeof ui.Volume === 'number' ? ui.Volume : 0.35;
        a.play().catch(() => { /* ignore */ });
        return;
      } catch (_) { /* fall through */ }
    }
    try {
      const ctx = ensureAudio();
      if (!ctx) return;
      const o = ctx.createOscillator();
      const g = ctx.createGain();
      o.type = 'square';
      const freq = kind === 'error' ? 180 : (kind === 'complete' ? 520 : 340);
      o.frequency.value = freq;
      g.gain.value = 0.03;
      o.connect(g); g.connect(ctx.destination);
      o.start();
      o.stop(ctx.currentTime + 0.07);
    } catch (_) { /* ignore */ }
  }

  function normalizeMode(next) {
    const hud = HUD();
    if (hud && typeof hud.normalizeMode === 'function') return hud.normalizeMode(next);
    if (next === 'normal') return 'expanded';
    return MODES.includes(next) ? next : 'expanded';
  }

  function applyMode(next, opts) {
    const silent = opts && opts.silent;
    const fromSettings = opts && opts.fromSettings;
    mode = normalizeMode(next);
    root.classList.remove('mode-normal', 'mode-compact', 'mode-minimal', 'mode-expanded', 'mode-hidden');
    root.classList.add(`mode-${mode}`);
    syncReduceButton();
    if (config.persistMode !== false) {
      const hud = HUD();
      if (hud && typeof hud.writeMode === 'function') {
        hud.writeMode(mode, { silent: true, silentPost: true, source: 'widget' });
      } else {
        lsSet(LS_MODE, mode === 'expanded' ? 'normal' : mode);
      }
    }
    if (!silent) post('trackerMode', { mode });
    if (!fromSettings && !silent) {
      const hud = HUD();
      if (hud && typeof hud.writeMode === 'function') {
        /* LS already written; notify overlay */
        hud.refreshPanel && hud.refreshPanel();
      }
    }
    updateVisibility();
  }

  function syncReduceButton() {
    if (!els.reduce) return;
    const reduced = mode !== 'expanded';
    els.reduce.title = reduced ? 'Agrandir' : 'Réduire';
    els.reduce.setAttribute('aria-label', reduced ? 'Agrandir' : 'Réduire');
    const ico = els.reduce.querySelector('i');
    if (ico) ico.className = reduced ? 'fa-solid fa-plus' : 'fa-solid fa-minus';
  }

  function syncPinButton() {
    if (!els.pin) return;
    els.pin.classList.toggle('is-on', pinned);
    els.pin.setAttribute('aria-pressed', pinned ? 'true' : 'false');
    const tip = pinned ? 'Retirer l’épingle' : 'Épingler le widget';
    els.pin.title = tip;
    els.pin.setAttribute('aria-label', tip);
  }

  function applyPin(next) {
    pinned = !!next;
    syncPinButton();
    if (config.persistPin !== false) lsSet(LS_PIN, pinned ? '1' : '0');
    post('trackerPin', { pinned });
    updateVisibility();
  }

  function widgetSize() {
    const rect = root.getBoundingClientRect();
    const compact = mode === 'compact' || mode === 'minimal';
    const w = rect.width > 1 ? rect.width : (compact ? 220 : 292);
    const h = rect.height > 1 ? rect.height : 56;
    return { w, h };
  }

  function isFiniteNum(n) {
    return typeof n === 'number' && Number.isFinite(n);
  }

  function onScreen(x, y, w, h) {
    if (!isFiniteNum(x) || !isFiniteNum(y) || !isFiniteNum(w) || !isFiniteNum(h)) return false;
    const vw = window.innerWidth || 0;
    const vh = window.innerHeight || 0;
    if (vw < 2 || vh < 2) return true;
    if (x + w < MIN_VISIBLE || y + h < MIN_VISIBLE) return false;
    if (x > vw - MIN_VISIBLE || y > vh - MIN_VISIBLE) return false;
    return true;
  }

  function clampXY(x, y) {
    const { w, h } = widgetSize();
    const vw = window.innerWidth || 800;
    const vh = window.innerHeight || 600;
    const maxX = Math.max(EDGE, vw - w - EDGE);
    const maxY = Math.max(EDGE, vh - h - EDGE);
    return {
      x: Math.round(Math.max(EDGE, Math.min(maxX, x))),
      y: Math.round(Math.max(EDGE, Math.min(maxY, y))),
    };
  }

  function applyDefaultTopRight() {
    const pos = (HUD() && HUD().DEFAULT_POS) || config.defaultPosition || DEFAULT_POS;
    const top = isFiniteNum(Number(pos.top)) ? Number(pos.top) : 24;
    const right = isFiniteNum(Number(pos.right)) ? Number(pos.right) : 24;
    root.style.top = `${top}px`;
    root.style.right = `${right}px`;
    root.style.left = 'auto';
    root.style.bottom = 'auto';
  }

  function applyXY(x, y) {
    const { w, h } = widgetSize();
    if (!onScreen(x, y, w, h)) {
      applyDefaultTopRight();
      return false;
    }
    const c = clampXY(x, y);
    root.style.left = `${c.x}px`;
    root.style.top = `${c.y}px`;
    root.style.right = 'auto';
    root.style.bottom = 'auto';
    return true;
  }

  function parseXY(raw) {
    if (!raw) return null;
    try {
      const o = typeof raw === 'string' ? JSON.parse(raw) : raw;
      if (!o || typeof o !== 'object') return null;
      const x = Number(o.x);
      const y = Number(o.y);
      if (!Number.isFinite(x) || !Number.isFinite(y)) return null;
      return { x, y };
    } catch (_) {
      return null;
    }
  }

  function parseLegacyPos(raw) {
    if (!raw) return null;
    try {
      const o = typeof raw === 'string' ? JSON.parse(raw) : raw;
      if (!o || typeof o !== 'object') return null;
      if (Number.isFinite(Number(o.x)) && Number.isFinite(Number(o.y))) {
        return { x: Number(o.x), y: Number(o.y) };
      }
      const top = Number(o.top);
      const right = Number(o.right);
      if (!Number.isFinite(top) || !Number.isFinite(right)) return null;
      const { w } = widgetSize();
      return { x: (window.innerWidth || 800) - right - w, y: top };
    } catch (_) {
      return null;
    }
  }

  function applyPosition(pos) {
    if (!pos) {
      applyDefaultTopRight();
      return;
    }
    const xy = parseXY(pos) || parseLegacyPos(pos);
    if (!xy) {
      applyDefaultTopRight();
      return;
    }
    applyXY(xy.x, xy.y);
  }

  function currentXY() {
    const rect = root.getBoundingClientRect();
    if (rect.width > 1) return { x: Math.round(rect.left), y: Math.round(rect.top) };
    const left = parseInt(root.style.left, 10);
    const top = parseInt(root.style.top, 10);
    if (Number.isFinite(left) && Number.isFinite(top)) return { x: left, y: top };
    return null;
  }

  function persistPos(payload) {
    if (config.persistPosition === false) return;
    const hud = HUD();
    if (hud && typeof hud.writePos === 'function') hud.writePos(payload, { silent: true });
    else lsSet(LS_POS, JSON.stringify({ top: payload.top, right: payload.right }));
    if (isFiniteNum(payload.x) && isFiniteNum(payload.y)) {
      lsSet(LS_POS_XY, JSON.stringify({ x: payload.x, y: payload.y }));
    }
  }

  function persistAndPostXY(x, y) {
    const { w, h } = widgetSize();
    if (!onScreen(x, y, w, h)) {
      applyDefaultTopRight();
      const fallback = currentXY();
      if (!fallback) {
        const def = (HUD() && HUD().DEFAULT_POS) || config.defaultPosition || DEFAULT_POS;
        const payload = {
          top: def.top || 24,
          right: def.right || 24,
          x: (window.innerWidth || 800) - (def.right || 24) - w,
          y: def.top || 24,
        };
        persistPos(payload);
        post('trackerPosition', payload);
        return;
      }
      x = fallback.x;
      y = fallback.y;
    }
    const c = clampXY(x, y);
    root.style.left = `${c.x}px`;
    root.style.top = `${c.y}px`;
    root.style.right = 'auto';
    root.style.bottom = 'auto';
    const { w: ww } = widgetSize();
    const payload = {
      x: c.x,
      y: c.y,
      top: c.y,
      right: Math.round((window.innerWidth || 800) - c.x - ww),
      left: c.x,
    };
    persistPos(payload);
    post('trackerPosition', payload);
  }

  function restorePosition() {
    const hud = HUD();
    const stored = parseXY(lsGet(LS_POS_XY, ''));
    if (stored) {
      if (!applyXY(stored.x, stored.y)) applyDefaultTopRight();
      return;
    }
    let legacy = null;
    try {
      const hudPos = hud && hud.readPos && hud.readPos();
      legacy = parseLegacyPos(hudPos) || parseLegacyPos(lsGet(LS_POS, ''));
    } catch (_) {
      legacy = null;
    }
    if (legacy && applyXY(legacy.x, legacy.y)) return;
    applyDefaultTopRight();
  }

  function activeJobCount() {
    let n = 0;
    jobs.forEach((j) => {
      if (j.status === 'active' || j.status === 'queued' || j.status === 'paused' || j.status === 'done') n += 1;
    });
    return n;
  }

  function updateVisibility() {
    root.classList.remove('hidden-panel');
    const hasJobs = jobs.size > 0;
    const hideUnpinned = config.hideWithMenuIfUnpinned !== false;
    /* Pin = stay visible after menu close. Unpin hides when menu closes / idle.
       HUD mode=hidden still hides. Never destroy the queue. */
    let shown = config.enabled !== false && hasJobs && mode !== 'hidden';
    if (shown && !pinned && hideUnpinned && !menuOpen) shown = false;
    root.classList.toggle('is-visible', !!shown);
    root.classList.toggle('is-hidden', !shown);
    root.setAttribute('aria-hidden', shown ? 'false' : 'true');
    if (els.reduced) {
      const reduced = mode === 'compact' || mode === 'minimal';
      els.reduced.setAttribute('aria-hidden', reduced && shown ? 'false' : 'true');
    }
  }

  function phaseLabel(entry, progress) {
    const p = Math.max(0, Math.min(1, progress || 0));
    const st = entry.status || 'active';
    if (st === 'error') return 'Erreur';
    if (st === 'done' || st === 'completed' || st === 'completing' || p >= 1) {
      return 'FABRICATION TERMINÉE';
    }
    if (st === 'queued') return 'EN ATTENTE';
    if (entry.stepLabel && entry.totalSteps > 1) {
      return entry.stepLabel;
    }
    const family = entry.phaseFamily || 'default';
    const phases = (config.phases && (config.phases[family] || config.phases.default)) || ['Préparation', 'Assemblage', 'Finition'];
    const idx = Math.min(phases.length - 1, Math.floor(Math.min(0.999, p) * phases.length));
    return phases[idx] || entry.stepLabel || 'Fabrication';
  }

  function formatRemain(ms) {
    const s = Math.max(0, Math.ceil(ms / 1000));
    if (s < 60) return `${s}s`;
    const m = Math.floor(s / 60);
    const r = s % 60;
    return `${m}:${String(r).padStart(2, '0')}`;
  }

  function computeProgress(entry) {
    if (entry.status === 'done') return { pct: 1, remain: 0 };
    if (entry.status === 'error' || entry.status === 'cancelled') return { pct: 1, remain: 0 };

    const duration = Math.max(1, Number(entry.duration) || 1);
    let remain;
    let elapsed;

    if (entry.useWallClock && entry.endsAt) {
      remain = entry.endsAt - Date.now();
      elapsed = duration - remain;
    } else if (entry._localEndsAt) {
      remain = entry._localEndsAt - Date.now();
      elapsed = duration - remain;
    } else {
      elapsed = Date.now() - (entry._localStart || Date.now());
      remain = duration - elapsed;
    }

    const pct = Math.max(0, Math.min(1, elapsed / duration));
    return { pct, remain: Math.max(0, remain) };
  }

  function anchorTiming(entry) {
    const duration = Math.max(0, Number(entry.duration) || 0);
    if (entry.useWallClock && entry.endsAt) {
      entry._localEndsAt = entry.endsAt;
      entry._localStart = entry.endsAt - duration;
      return;
    }
    // Sync from client GetGameTimer via clientTimer snapshot
    if (entry.clientTimer != null && entry.endsAt != null && entry.startedAt != null) {
      const elapsedGame = Math.max(0, entry.clientTimer - entry.startedAt);
      entry._localStart = Date.now() - elapsedGame;
      entry._localEndsAt = entry._localStart + duration;
      return;
    }
    entry._localStart = Date.now();
    entry._localEndsAt = Date.now() + duration;
  }

  function upsertJob(raw) {
    if (!raw || !raw.craftId) return;
    const prev = jobs.get(raw.craftId) || {};
    const entry = { ...prev, ...raw };
    const timingChanged =
      raw.startedAt !== prev.startedAt
      || raw.endsAt !== prev.endsAt
      || raw.duration !== prev.duration
      || raw.status !== prev.status
      || raw.stepIndex !== prev.stepIndex;

    if (timingChanged || !prev._localEndsAt) {
      anchorTiming(entry);
    }

    const isNew = !jobs.has(raw.craftId);
    jobs.set(raw.craftId, entry);

    /* G: new active craft while tracker hidden → compact (config, default on) */
    if (isNew && (entry.status === 'active' || entry.status === 'queued') && mode === 'hidden') {
      if (config.showOnNewCraftIfHidden !== false) {
        applyMode('compact');
      }
    }

    render();
    updateVisibility();
    ensureTick();

    if (isNew && (entry.status === 'active' || entry.status === 'queued')) {
      beep('start');
    }
    if (entry.status === 'done' && prev.status !== 'done') {
      beep('complete');
      scheduleAutoRemove(entry.craftId);
    }
    if (entry.status === 'error' && prev.status !== 'error') {
      beep('error');
      scheduleAutoRemove(entry.craftId);
    }
  }

  function scheduleAutoRemove(id) {
    if (config.autoRemoveCompleted === false) return;
    const wait = config.completedLingerMs || 2000;
    setTimeout(() => {
      const j = jobs.get(id);
      if (j && (j.status === 'done' || j.status === 'error' || j.status === 'cancelled')) {
        jobs.delete(id);
        render();
        updateVisibility();
        post('trackerDismiss', { craftId: id });
      }
    }, wait);
  }

  function removeJob(id) {
    if (!id) return;
    jobs.delete(id);
    completing.delete(id);
    render();
    updateVisibility();
  }

  function renderJob(entry) {
    const { pct, remain } = computeProgress(entry);
    const phase = phaseLabel(entry, pct);
    const pctTxt = `${Math.round(pct * 100)}%`;
    const statusClass = `is-${entry.status || 'active'}`;
    const el = document.createElement('article');
    el.className = `ct-job ${statusClass}`;
    el.dataset.craftId = entry.craftId;
    el.innerHTML = `
      <div class="ct-thumb">
        <img alt="" />
        <span class="ct-thumb-fallback" aria-hidden="true"><i class="fa-solid fa-hammer"></i></span>
      </div>
      <div class="ct-body">
        <div class="ct-row1">
          <div class="ct-label"></div>
          <div class="ct-batch"></div>
        </div>
        <div class="ct-phase"></div>
        <div class="ct-bar"><div class="ct-fill"></div></div>
        <div class="ct-meta">
          <span class="ct-time"></span>
          <span class="ct-pct"></span>
        </div>
      </div>
      <button type="button" class="ct-dismiss" title="Retirer" aria-label="Retirer">
        <i class="fa-solid fa-xmark"></i>
      </button>
    `;
    el.querySelector('.ct-label').textContent = entry.label || entry.recipeId || 'Production';
    el.querySelector('.ct-batch').textContent = `×${entry.count || entry.batch || 1}`;
    el.querySelector('.ct-phase').textContent = phase;
    el.querySelector('.ct-fill').style.width = `${Math.round(pct * 100)}%`;
    const visualDone = entry.status === 'done' || entry.status === 'completed' || entry.status === 'completing' || pct >= 1;
    el.querySelector('.ct-time').textContent =
      entry.status === 'error' ? 'Échec'
        : visualDone ? 'Terminé'
          : entry.status === 'queued' ? `EN ATTENTE · ${formatRemain(remain)}`
            : formatRemain(remain);
    const dismiss = el.querySelector('.ct-dismiss');
    // Hide cancel/dismiss while completing at 100% — card auto-removes after linger
    if (dismiss && visualDone && entry.status !== 'error') {
      dismiss.classList.add('hidden');
    }
    el.querySelector('.ct-pct').textContent = pctTxt;
    bindItemImg(el.querySelector('img'), entry.item || entry.recipeId, el.querySelector('.ct-thumb-fallback'));

    el.addEventListener('click', (ev) => {
      if (ev.target.closest('.ct-dismiss')) return;
      post('trackerClick', { craftId: entry.craftId, benchKey: entry.benchKey });
    });
    el.querySelector('.ct-dismiss').addEventListener('click', (ev) => {
      ev.stopPropagation();
      jobs.delete(entry.craftId);
      render();
      updateVisibility();
      post('trackerDismiss', { craftId: entry.craftId });
    });
    return el;
  }

  function liveJobCount(arr) {
    const n = arr.filter((j) => j.status !== 'done' && j.status !== 'error').length;
    return n || arr.length;
  }

  function primaryProgressPct(arr) {
    const live = arr.find((j) => j.status === 'active')
      || arr.find((j) => j.status === 'queued' || j.status === 'paused')
      || arr[0];
    if (!live) return 0;
    return Math.round(computeProgress(live).pct * 100);
  }

  function paintReduced(arr) {
    const n = liveJobCount(arr);
    const pct = primaryProgressPct(arr);
    if (els.reducedCount) els.reducedCount.textContent = String(n);
    if (els.reducedPct) els.reducedPct.textContent = `${pct}%`;
  }

  function paintWaiting(arr) {
    if (!els.waiting) return;
    const extra = Math.max(0, arr.length - 1);
    if (extra > 0) {
      els.waiting.hidden = false;
      els.waiting.textContent = `+${extra} en attente`;
    } else {
      els.waiting.hidden = true;
      els.waiting.textContent = '';
    }
  }

  function render() {
    if (!els.list) return;
    els.list.innerHTML = '';
    const arr = Array.from(jobs.values()).sort((a, b) => (a.startedAt || 0) - (b.startedAt || 0));
    const n = liveJobCount(arr);
    if (els.count) els.count.textContent = String(n);
    paintReduced(arr);
    paintWaiting(arr);

    if (!arr.length) {
      const empty = document.createElement('div');
      empty.className = 'ct-empty';
      empty.textContent = 'Aucune production';
      els.list.appendChild(empty);
      return;
    }
    const primary = arr.find((j) => j.status === 'active')
      || arr.find((j) => j.status === 'queued' || j.status === 'paused')
      || arr[0];
    els.list.appendChild(renderJob(primary));
  }

  function tickVisual() {
    jobs.forEach((entry) => {
      if (entry.status !== 'active' && entry.status !== 'queued' && entry.status !== 'paused') return;
      const { pct, remain } = computeProgress(entry);
      const node = els.list && Array.from(els.list.querySelectorAll('.ct-job')).find((n) => n.dataset.craftId === entry.craftId);
      if (node) {
        const fill = node.querySelector('.ct-fill');
        const time = node.querySelector('.ct-time');
        const pctEl = node.querySelector('.ct-pct');
        const phase = node.querySelector('.ct-phase');
        if (fill) fill.style.width = `${Math.round(pct * 100)}%`;
        if (pctEl) pctEl.textContent = `${Math.round(pct * 100)}%`;
        if (time) {
          time.textContent = entry.status === 'queued'
            ? `EN ATTENTE · ${formatRemain(remain)}`
            : (remain <= 0 ? 'Terminé' : formatRemain(remain));
        }
        if (phase) phase.textContent = phaseLabel(entry, pct);
        const dismiss = node.querySelector('.ct-dismiss');
        if (dismiss && remain <= 0) dismiss.classList.add('hidden');
      }
      if (els.reducedPct && entry.status === 'active') {
        els.reducedPct.textContent = `${Math.round(pct * 100)}%`;
      }
      if (remain <= 0 && !completing.has(entry.craftId)) {
        completing.add(entry.craftId);
        // Immediate visual TERMINÉ — never leave FINALISATION at 100%
        entry.status = entry.status === 'queued' ? entry.status : 'done';
        if (entry.status !== 'queued') {
          entry.stepLabel = 'FABRICATION TERMINÉE';
          jobs.set(entry.craftId, entry);
          if (node) {
            const ph = node.querySelector('.ct-phase');
            const tm = node.querySelector('.ct-time');
            if (ph) ph.textContent = 'FABRICATION TERMINÉE';
            if (tm) tm.textContent = 'Terminé';
          }
          scheduleAutoRemove(entry.craftId);
        }
        const failSafe = setTimeout(() => {
          const still = jobs.get(entry.craftId);
          if (still && still.status === 'active') {
            still.status = 'done';
            still.stepLabel = 'FABRICATION TERMINÉE';
            jobs.set(entry.craftId, still);
            render();
            scheduleAutoRemove(entry.craftId);
          }
          completing.delete(entry.craftId);
        }, 1500);
        post('trackerComplete', { craftId: entry.craftId }).then((r) => {
          clearTimeout(failSafe);
          const cur = jobs.get(entry.craftId);
          if (!cur) {
            completing.delete(entry.craftId);
            return;
          }
          if (r && r.ok && r.advanced) {
            completing.delete(entry.craftId);
            return;
          }
          if (r && r.reason === 'queue_not_ready') {
            completing.delete(entry.craftId);
            return;
          }
          // ok, already, craft_too_far, timeout, no reply → TERMINÉ (watchdog grants)
          cur.status = 'done';
          cur.stepLabel = 'FABRICATION TERMINÉE';
          jobs.set(entry.craftId, cur);
          render();
          scheduleAutoRemove(entry.craftId);
          completing.delete(entry.craftId);
        }).catch(() => {
          clearTimeout(failSafe);
          const cur = jobs.get(entry.craftId);
          if (cur && cur.status === 'active') {
            cur.status = 'done';
            cur.stepLabel = 'FABRICATION TERMINÉE';
            jobs.set(entry.craftId, cur);
            render();
            scheduleAutoRemove(entry.craftId);
          }
          completing.delete(entry.craftId);
        });
      }
    });
  }

  function ensureTick() {
    if (tickTimer) return;
    const ms = Math.max(100, Number(config.tickMs) || 250);
    tickTimer = setInterval(() => {
      if (jobs.size === 0) {
        clearInterval(tickTimer);
        tickTimer = null;
        return;
      }
      tickVisual();
    }, ms);
  }

  function syncAll(payload) {
    if (payload && payload.config) mergeConfig(payload.config);
    if (typeof payload.menuOpen === 'boolean') menuOpen = payload.menuOpen;
    if (Array.isArray(payload.jobs)) {
      const seen = new Set();
      payload.jobs.forEach((j) => {
        if (!j || !j.craftId) return;
        seen.add(j.craftId);
        upsertJob(j);
      });
      Array.from(jobs.keys()).forEach((id) => {
        if (!seen.has(id)) jobs.delete(id);
      });
      render();
      updateVisibility();
      ensureTick();
    } else {
      updateVisibility();
    }
  }

  // Drag from empty header (not PIN / reduce). Threshold so a click is not a drag.
  function onPointerDown(ev) {
    if (config.allowDrag === false) return;
    if (ev.button != null && ev.button !== 0) return;
    if (ev.target.closest('button')) return;
    if (!els.header || !els.header.contains(ev.target)) return;
    const rect = root.getBoundingClientRect();
    drag = {
      ox: ev.clientX - rect.left,
      oy: ev.clientY - rect.top,
      w: rect.width,
      h: rect.height,
      startX: ev.clientX,
      startY: ev.clientY,
      moved: false,
    };
    dragMoved = false;
  }

  function onPointerMove(ev) {
    if (!drag) return;
    const dx = ev.clientX - drag.startX;
    const dy = ev.clientY - drag.startY;
    if (!drag.moved && (dx * dx + dy * dy) >= DRAG_THRESHOLD * DRAG_THRESHOLD) {
      drag.moved = true;
      root.classList.add('is-dragging');
    }
    if (!drag.moved) return;
    dragMoved = true;
    const left = Math.max(EDGE, Math.min(window.innerWidth - drag.w - EDGE, ev.clientX - drag.ox));
    const top = Math.max(EDGE, Math.min(window.innerHeight - drag.h - EDGE, ev.clientY - drag.oy));
    root.style.left = `${left}px`;
    root.style.top = `${top}px`;
    root.style.right = 'auto';
    root.style.bottom = 'auto';
  }

  function onPointerUp() {
    if (!drag) return;
    const moved = drag.moved;
    drag = null;
    root.classList.remove('is-dragging');
    if (!moved) return;
    dragMoved = true;
    const rect = root.getBoundingClientRect();
    persistAndPostXY(Math.round(rect.left), Math.round(rect.top));
  }

  if (els.header) {
    els.header.addEventListener('mousedown', onPointerDown);
  }
  window.addEventListener('mousemove', onPointerMove);
  window.addEventListener('mouseup', onPointerUp);

  function stopOwn(ev, fn) {
    ev.stopPropagation();
    fn(ev);
  }

  if (els.pin) {
    els.pin.addEventListener('click', (ev) => stopOwn(ev, () => applyPin(!pinned)));
    els.pin.addEventListener('mousedown', (ev) => ev.stopPropagation());
  }
  if (els.reduce) {
    els.reduce.addEventListener('click', (ev) => stopOwn(ev, () => {
      if (mode === 'expanded') applyMode('compact');
      else applyMode('expanded');
    }));
    els.reduce.addEventListener('mousedown', (ev) => ev.stopPropagation());
  }

  if (els.reduced) {
    els.reduced.addEventListener('click', (ev) => {
      if (dragMoved) { dragMoved = false; return; }
      if (ev.target.closest('button')) return;
      if (mode === 'compact' || mode === 'minimal') applyMode('expanded');
    });
  }

  window.addEventListener('resize', () => {
    const xy = currentXY();
    if (!xy) return;
    const { w, h } = widgetSize();
    if (!onScreen(xy.x, xy.y, w, h)) applyDefaultTopRight();
    else applyXY(xy.x, xy.y);
  });

  // Restore prefs — F: invalid LS mode → expanded
  pinned = lsGet(LS_PIN, '0') === '1';
  syncPinButton();
  const hud = HUD();
  const bootMode = hud ? hud.readMode() : normalizeMode(lsGet(LS_MODE, config.defaultMode || 'expanded'));
  applyMode(bootMode, { silent: false });
  restorePosition();

  window.addEventListener('sanctuary-hud:change', (ev) => {
    const d = (ev && ev.detail) || {};
    if (d.reset) {
      applyMode('expanded', { silent: true, fromSettings: true });
      applyDefaultTopRight();
      updateVisibility();
      return;
    }
    if (d.trackerMode && normalizeMode(d.trackerMode) !== mode) {
      applyMode(d.trackerMode, { silent: true, fromSettings: true });
    }
    if (d.trackerPos) applyPosition(d.trackerPos);
  });

  window.addEventListener('message', (event) => {
    const msg = event.data || {};
    const action = msg.action;
    if (!action || typeof action !== 'string') return;

    if (action === 'tracker:sync') {
      syncAll(msg);
      return;
    }
    if (action === 'tracker:upsert') {
      if (msg.config) mergeConfig(msg.config);
      if (typeof msg.menuOpen === 'boolean') menuOpen = msg.menuOpen;
      upsertJob(msg.entry);
      return;
    }
    if (action === 'tracker:remove') {
      removeJob(msg.craftId);
      return;
    }
    if (action === 'tracker:setVisible') {
      if (msg.resetPosition) applyPosition(msg.resetPosition);
      if (typeof msg.visible === 'boolean') {
        if (msg.visible && mode === 'hidden') applyMode('expanded', { fromSettings: true });
        if (!msg.visible && mode !== 'hidden') {
          /* Lua setVisible false is not explicit hidden mode — just visual */
        }
        updateVisibility();
        if (msg.visible) root.classList.remove('hidden-panel');
      } else {
        updateVisibility();
      }
      return;
    }
    if (action === 'tracker:menuState') {
      if (msg.config) mergeConfig(msg.config);
      menuOpen = !!msg.menuOpen;
      if (Array.isArray(msg.jobs)) {
        msg.jobs.forEach((j) => upsertJob(j));
      }
      updateVisibility();
      return;
    }
    if (action === 'hud:reset') {
      applyMode('expanded', { fromSettings: true });
      applyDefaultTopRight();
      return;
    }
    if (action === 'craftFinished') {
      if (!msg.craftId) return;
      const prev = jobs.get(msg.craftId) || { craftId: msg.craftId };
      upsertJob({
        ...prev,
        craftId: msg.craftId,
        status: 'done',
        stepLabel: 'FABRICATION TERMINÉE',
        label: msg.label || prev.label,
        item: (msg.result && msg.result.item) || prev.item,
        count: (msg.result && msg.result.count) || prev.count,
        batch: msg.batch || prev.batch,
        benchKey: msg.benchKey || prev.benchKey,
      });
      return;
    }
    if (action === 'craftAdvanced') {
      if (!msg.craftId) return;
      const prev = jobs.get(msg.craftId) || { craftId: msg.craftId };
      upsertJob({
        ...prev,
        craftId: msg.craftId,
        status: 'active',
        duration: msg.duration,
        stepIndex: msg.stepIndex,
        totalSteps: msg.totalSteps,
        stepLabel: msg.stepLabel || msg.label,
        label: msg.label || prev.label,
      });
      completing.delete(msg.craftId);
      return;
    }
  });

  // Expose for settings overlay + structural tests A–G
  window.__craftTracker = {
    jobs,
    render,
    updateVisibility,
    applyMode,
    applyPin,
    getMode: () => mode,
    getPinned: () => pinned,
    setMode: (m) => applyMode(m),
    hide: () => applyMode('hidden'),
    expand: () => applyMode('expanded'),
    restorePosition,
    persistAndPostXY,
    parseXY,
    clampXY,
    LS_POS_XY,
  };
})();
